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

// Zod schema for priority detection
const PriorityMessageSchema = z.object({
  messageId: z.string().describe('ID of the message (from conversation context)'),
  priority: z.enum(['urgent', 'high', 'medium']).describe('Priority level'),
  reason: z.string().describe('Brief explanation of why this is prioritized'),
  actionRequired: z.boolean().describe('Whether this message requires action from the user'),
  suggestedAction: z.string().optional().describe('Suggested action to take'),
});

const PriorityResultSchema = z.object({
  priorityMessages: z.array(PriorityMessageSchema),
});

// Request schema
const RequestSchema = z.object({
  conversationId: z.string().uuid(),
  daysBack: z.number().min(1).max(7).optional().default(3),
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
    const userId = await getUserId(supabase);

    logRequest(requestId, 'authenticated', { userId });

    // Parse and validate request
    const body = await req.json();
    const { conversationId, daysBack } = RequestSchema.parse(body);

    // Verify conversation access
    const hasAccess = await verifyConversationAccess(supabase, userId, conversationId);
    if (!hasAccess) {
      return new Response(
        JSON.stringify({ error: 'Access denied to conversation' }),
        { status: 403, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    // Check rate limit
    const { allowed, count } = await checkRateLimit(supabase, userId, 'detect-priority', 30);
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
        JSON.stringify({ priorityMessages: [] }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    logRequest(requestId, 'messages_fetched', { count: messages.length });

    // Build context for AI with message IDs
    const conversationContext = messages
      .map((m: any, idx: number) => `[MSG-${idx}] [${m.created_at}] ${m.content}`)
      .join('\n');

    const messageIdMap = messages.reduce((acc: any, m: any, idx: number) => {
      acc[`MSG-${idx}`] = m.id;
      return acc;
    }, {});

    // Detect priority messages using AI
    const result = await generateObject({
      model: openai('gpt-4o'),
      schema: PriorityResultSchema,
      prompt: `You are an AI assistant helping a busy parent/caregiver identify important messages that need attention.

Analyze the following conversation and identify messages that should be prioritized. Consider:

URGENT (requires immediate attention):
- Emergency situations
- Time-sensitive requests with deadlines within 24 hours
- School/medical emergencies
- Critical schedule conflicts

HIGH (important, should be addressed soon):
- Upcoming deadlines (within 2-3 days)
- Important decisions that affect multiple people
- RSVP requests
- Permission forms or documents needed
- Schedule changes

MEDIUM (notable, but not time-critical):
- Questions directed at the user
- Information that requires follow-up
- Planning discussions that need input

DO NOT flag as priority:
- General chat
- Updates that don't require action
- Casual conversations
- Already-resolved items

For each priority message, reference it as MSG-0, MSG-1, etc. (from the conversation below).

Conversation:
${conversationContext}

Identify and prioritize messages:`,
    });

    const priorityMessages = result.object.priorityMessages.map(pm => ({
      messageId: messageIdMap[pm.messageId] || pm.messageId,
      priority: pm.priority,
      reason: pm.reason,
      actionRequired: pm.actionRequired,
    }));

    logRequest(requestId, 'priority_detected', { count: priorityMessages.length });

    // Persist priority messages
    const serviceClient = createServiceClient();

    if (priorityMessages.length > 0) {
      // First, check which messages already have priority flags
      const { data: existing } = await serviceClient
        .from('priority_messages')
        .select('message_id')
        .in('message_id', priorityMessages.map(pm => pm.messageId));

      const existingIds = new Set((existing || []).map((e: any) => e.message_id));
      const newPriorityMessages = priorityMessages.filter(pm => !existingIds.has(pm.messageId));

      if (newPriorityMessages.length > 0) {
        const { data: inserted, error: insertError } = await serviceClient
          .from('priority_messages')
          .insert(
            newPriorityMessages.map(pm => ({
              message_id: pm.messageId,
              priority: pm.priority,
              reason: pm.reason,
              action_required: pm.actionRequired,
              dismissed: false,
            }))
          )
          .select();

        if (insertError) {
          console.error('Failed to insert priority messages:', insertError);
          throw new Error('Failed to save priority messages');
        }

        logRequest(requestId, 'priority_stored', { count: inserted?.length || 0 });
      }
    }

    // Log usage
    await logUsage(supabase, userId, 'detect-priority');

    logRequest(requestId, 'complete', { priorityCount: priorityMessages.length });

    return new Response(
      JSON.stringify({ priorityMessages }),
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
