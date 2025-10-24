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

// Zod schema for decision extraction
const DecisionSchema = z.object({
  decisionText: z.string().describe('Clear statement of what was decided'),
  category: z.enum(['activity', 'schedule', 'purchase', 'policy', 'food', 'other']).describe('Type of decision'),
  decidedBy: z.string().optional().describe('Name or identifier of who made the decision'),
  deadline: z.string().optional().describe('Deadline for the decision in YYYY-MM-DD format'),
  messageReference: z.string().optional().describe('Brief excerpt showing where this decision was made'),
});

const DecisionResultSchema = z.object({
  decisions: z.array(DecisionSchema),
});

// Request schema
const RequestSchema = z.object({
  conversationId: z.string().uuid(),
  daysBack: z.number().min(1).max(30).optional().default(7),
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
    const { allowed, count } = await checkRateLimit(supabase, userId, 'track-decisions', 30);
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
        JSON.stringify({ decisions: [] }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    logRequest(requestId, 'messages_fetched', { count: messages.length });

    // Build context for AI
    const conversationContext = messages
      .map((m: any) => `[${m.created_at}] ${m.content}`)
      .join('\n');

    // Extract decisions using AI
    const result = await generateObject({
      model: openai('gpt-4o'),
      schema: DecisionResultSchema,
      prompt: `You are an AI assistant helping a busy parent/caregiver track family decisions.

Analyze the following family/group conversation and identify any decisions that were made. Look for:
- Activity decisions ("Let's go to the park Saturday")
- Schedule changes ("Soccer practice moved to 4pm")
- Purchases ("We'll get the blue backpack")
- Family policies ("Kids need to be home by 6pm on weekdays")
- Food/meal decisions ("Pizza for dinner tonight")
- Any other commitments or agreements

For each decision, extract:
- A clear statement of what was decided
- The category that best fits
- Who made or agreed to the decision (if clear)
- Any deadline associated with it
- A brief reference to the message where it was decided

Only extract actual decisions, not questions or suggestions. Look for phrases like:
- "Let's...", "We'll...", "I'll..."
- "Okay", "Sounds good", "Deal", "Agreed"
- "It's decided", "That works"

Conversation:
${conversationContext}

Extract all decisions made in this conversation:`,
    });

    const extractedDecisions = result.object.decisions;

    logRequest(requestId, 'decisions_extracted', { count: extractedDecisions.length });

    // Persist decisions
    const serviceClient = createServiceClient();

    if (extractedDecisions.length > 0) {
      const { data: insertedDecisions, error: insertError } = await serviceClient
        .from('decisions')
        .insert(
          extractedDecisions.map(decision => ({
            conversation_id: conversationId,
            decision_text: decision.decisionText,
            category: decision.category,
            decided_by: null, // Will need user mapping logic in production
            deadline: decision.deadline || null,
          }))
        )
        .select();

      if (insertError) {
        console.error('Failed to insert decisions:', insertError);
        throw new Error('Failed to save decisions');
      }

      logRequest(requestId, 'decisions_stored', { count: insertedDecisions?.length || 0 });
    }

    // Log usage
    await logUsage(supabase, userId, 'track-decisions');

    logRequest(requestId, 'complete', { decisionsReturned: extractedDecisions.length });

    return new Response(
      JSON.stringify({ decisions: extractedDecisions }),
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
