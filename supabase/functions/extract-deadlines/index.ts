import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { generateObject, openai, z } from '../_shared/deps.ts';
import {
  createAuthenticatedClient,
  createServiceClient,
  getUserId,
  checkRateLimit,
  logUsage,
  verifyConversationAccess,
  fetchMessages,
  corsHeaders,
  generateRequestId,
  logRequest,
} from '../_shared/utils.ts';

// Zod schema for deadline extraction
const DeadlineSchema = z.object({
  messageId: z.string().describe('ID of the message mentioning the deadline (MSG-0, MSG-1, etc.)'),
  task: z.string().describe('Clear description of what needs to be done'),
  deadline: z.string().describe('Deadline in ISO 8601 format'),
  category: z.enum(['school', 'bills', 'chores', 'forms', 'medical', 'work', 'other']).describe('Category of the task'),
  priority: z.enum(['urgent', 'high', 'medium', 'low']).describe('Priority based on deadline proximity and importance'),
  details: z.string().optional().describe('Additional context or details'),
  assignedTo: z.string().optional().describe('Who is responsible (if mentioned)'),
});

const DeadlineResultSchema = z.object({
  deadlines: z.array(DeadlineSchema),
});

// Request schema
const RequestSchema = z.object({
  conversationId: z.string().uuid(),
  userId: z.string().uuid(),
  daysBack: z.number().min(1).max(30).optional().default(14),
});

serve(async (req) => {
  const requestId = generateRequestId();

  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders() });
  }

  try {
    logRequest(requestId, 'start', { method: req.method });

    // Authenticate user
    const supabase = createAuthenticatedClient(req);
    const authUserId = await getUserId(supabase);

    logRequest(requestId, 'authenticated', { userId: authUserId });

    // Parse and validate request
    const body = await req.json();
    const { conversationId, userId, daysBack } = RequestSchema.parse(body);

    // Ensure authenticated user matches requested userId
    if (authUserId !== userId) {
      return new Response(
        JSON.stringify({ error: 'Cannot extract deadlines for another user' }),
        { status: 403, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    // Verify conversation access
    const hasAccess = await verifyConversationAccess(supabase, userId, conversationId);
    if (!hasAccess) {
      return new Response(
        JSON.stringify({ error: 'Access denied to conversation' }),
        { status: 403, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    // Check rate limit
    const { allowed, count } = await checkRateLimit(supabase, userId, 'extract-deadlines', 30);
    if (!allowed) {
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded', count }),
        { status: 429, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    logRequest(requestId, 'rate_check', { count, allowed });

    // Fetch messages
    const messages = await fetchMessages(supabase, conversationId, {
      daysBack,
      limit: 100,
    });

    if (messages.length === 0) {
      return new Response(
        JSON.stringify({ deadlines: [] }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    logRequest(requestId, 'messages_fetched', { count: messages.length });

    // Get user's profile
    const { data: userProfile } = await supabase
      .from('users')
      .select('display_name, username')
      .eq('id', userId)
      .single();

    const userName = userProfile?.display_name || userProfile?.username || 'User';

    // Build context for AI
    const conversationContext = messages
      .map((m: any, idx: number) => `[MSG-${idx}] [${m.created_at}] ${m.content}`)
      .join('\n');

    const messageIdMap = messages.reduce((acc: any, m: any, idx: number) => {
      acc[`MSG-${idx}`] = m.id;
      return acc;
    }, {});

    const today = new Date().toISOString();

    // Extract deadlines using AI
    const result = await generateObject({
      model: openai('gpt-4o'),
      schema: DeadlineResultSchema,
      prompt: `You are an AI assistant helping a busy parent/caregiver track deadlines and tasks.

The user's name is: ${userName}
Today's date: ${today}

Analyze the following conversation and extract any deadlines or time-sensitive tasks. Look for:

SCHOOL-RELATED:
- Permission slips due dates
- Project deadlines
- School form submissions
- Book reports, homework
- Picture day, field trip deadlines

BILLS & FINANCIAL:
- Bill payment due dates
- Subscription renewals
- Insurance deadlines

CHORES & HOUSEHOLD:
- Tasks that need to be done by a certain date
- Seasonal tasks (winterizing, etc.)

FORMS & PAPERWORK:
- Registration deadlines
- Application deadlines
- Document submissions

MEDICAL:
- Prescription refills needed by
- Appointment scheduling deadlines
- Medical form returns

For each deadline, extract:
- Message ID (MSG-0, MSG-1, etc.) where it's mentioned
- Clear task description
- Deadline date/time in ISO 8601 format
- Appropriate category
- Priority (urgent if <2 days, high if <7 days, medium if <30 days, low if >30 days)
- Any additional details
- Who it's assigned to (if mentioned)

Only extract actionable deadlines with specific dates. Ignore vague "sometime soon" mentions.

Conversation:
${conversationContext}

Extract all deadlines:`,
    });

    const deadlines = result.object.deadlines.map(d => ({
      messageId: messageIdMap[d.messageId] || d.messageId,
      task: d.task,
      deadline: d.deadline,
      category: d.category,
      priority: d.priority,
      details: d.details,
    }));

    logRequest(requestId, 'deadlines_extracted', { count: deadlines.length });

    // Persist deadlines
    const serviceClient = createServiceClient();

    if (deadlines.length > 0) {
      const { data: inserted, error: insertError } = await serviceClient
        .from('deadlines')
        .insert(
          deadlines.map(deadline => ({
            message_id: deadline.messageId,
            conversation_id: conversationId,
            user_id: userId,
            task: deadline.task,
            deadline: deadline.deadline,
            category: deadline.category,
            priority: deadline.priority,
            details: deadline.details || null,
            status: 'pending',
          }))
        )
        .select();

      if (insertError) {
        console.error('Failed to insert deadlines:', insertError);
        throw new Error('Failed to save deadlines');
      }

      logRequest(requestId, 'deadlines_stored', { count: inserted?.length || 0 });

      // Auto-create reminders for deadlines (1 day before)
      const reminders = deadlines
        .filter(d => {
          const deadlineDate = new Date(d.deadline);
          const oneDayBefore = new Date(deadlineDate);
          oneDayBefore.setDate(oneDayBefore.getDate() - 1);
          return oneDayBefore > new Date(); // Only if reminder is in the future
        })
        .map(d => {
          const deadlineDate = new Date(d.deadline);
          const reminderTime = new Date(deadlineDate);
          reminderTime.setDate(reminderTime.getDate() - 1);
          reminderTime.setHours(9, 0, 0, 0); // 9 AM the day before

          return {
            user_id: userId,
            title: `Reminder: ${d.task}`,
            reminder_time: reminderTime.toISOString(),
            priority: d.priority,
            status: 'pending',
            created_by: 'ai',
          };
        });

      if (reminders.length > 0) {
        await serviceClient.from('reminders').insert(reminders);
        logRequest(requestId, 'reminders_created', { count: reminders.length });
      }
    }

    // Log usage
    await logUsage(supabase, userId, 'extract-deadlines');

    logRequest(requestId, 'complete', { deadlinesExtracted: deadlines.length });

    return new Response(
      JSON.stringify({ deadlines }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
    );

  } catch (error) {
    console.error('Error:', error);
    logRequest(requestId, 'error', { error: error.message });

    const status = error.message.includes('Unauthorized') ? 401 :
                   error.message.includes('Access denied') ? 403 : 500;

    return new Response(
      JSON.stringify({ error: error.message }),
      { status, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
    );
  }
});
