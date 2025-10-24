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

// Zod schema for calendar event extraction
const CalendarEventSchema = z.object({
  title: z.string().describe('Brief title of the event'),
  date: z.string().describe('Date in YYYY-MM-DD format'),
  time: z.string().optional().describe('Time in HH:MM format (24-hour)'),
  location: z.string().optional().describe('Location of the event'),
  description: z.string().optional().describe('Additional details about the event'),
  category: z.enum(['school', 'medical', 'social', 'sports', 'work', 'other']).describe('Event category'),
  confidence: z.number().min(0).max(1).describe('Confidence score (0-1) for this extraction'),
});

const ExtractionResultSchema = z.object({
  events: z.array(CalendarEventSchema),
});

// Request schema
const RequestSchema = z.object({
  conversationId: z.string().uuid(),
  messageIds: z.array(z.string().uuid()).optional(),
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
    const { conversationId, messageIds, daysBack } = RequestSchema.parse(body);

    // Verify conversation access
    const hasAccess = await verifyConversationAccess(supabase, userId, conversationId);
    if (!hasAccess) {
      return new Response(
        JSON.stringify({ error: 'Access denied to conversation' }),
        { status: 403, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    // Check rate limit
    const { allowed, count } = await checkRateLimit(supabase, userId, 'extract-calendar-events', 30);
    if (!allowed) {
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded', count }),
        { status: 429, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    logRequest(requestId, 'rate_check', { count, allowed });

    // Fetch messages
    const messages = await fetchMessages(supabase, conversationId, {
      messageIds,
      daysBack: messageIds ? undefined : daysBack,
      limit: 100,
    });

    if (messages.length === 0) {
      return new Response(
        JSON.stringify({ events: [] }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    logRequest(requestId, 'messages_fetched', { count: messages.length });

    // Build context for AI
    const conversationContext = messages
      .map((m: any) => `[${m.created_at}] ${m.content}`)
      .join('\n');

    // Extract calendar events using AI
    const result = await generateObject({
      model: openai('gpt-4o'),
      schema: ExtractionResultSchema,
      prompt: `You are an AI assistant helping a busy parent/caregiver manage their schedule.

Analyze the following conversation and extract any calendar events mentioned. Look for:
- School events (parent-teacher conferences, field trips, performances, etc.)
- Medical appointments (doctor visits, dentist, therapy sessions, etc.)
- Social events (playdates, birthday parties, family gatherings, etc.)
- Sports and activities (practices, games, recitals, lessons, etc.)
- Work-related events that affect family schedule

For each event, extract:
- A clear, concise title
- The date (in YYYY-MM-DD format)
- Time if mentioned (in HH:MM 24-hour format)
- Location if specified
- Any important details
- Appropriate category
- Your confidence level (0-1) that this is actually a scheduled event

Only extract events that have at least a date. Ignore vague mentions like "we should do something soon."

Conversation:
${conversationContext}

Extract all calendar events:`,
    });

    const extractedEvents = result.object.events;

    logRequest(requestId, 'events_extracted', { count: extractedEvents.length });

    // Filter events with confidence >= 0.7 and persist them
    const serviceClient = createServiceClient();
    const eventsToStore = extractedEvents.filter(e => e.confidence >= 0.7);

    if (eventsToStore.length > 0) {
      const { data: insertedEvents, error: insertError } = await serviceClient
        .from('calendar_events')
        .insert(
          eventsToStore.map(event => ({
            conversation_id: conversationId,
            title: event.title,
            date: event.date,
            time: event.time || null,
            location: event.location || null,
            description: event.description || null,
            category: event.category,
            confidence: event.confidence,
            confirmed: false,
          }))
        )
        .select();

      if (insertError) {
        console.error('Failed to insert events:', insertError);
        throw new Error('Failed to save calendar events');
      }

      logRequest(requestId, 'events_stored', { count: insertedEvents?.length || 0 });
    }

    // Log usage
    await logUsage(supabase, userId, 'extract-calendar-events');

    logRequest(requestId, 'complete', { eventsReturned: extractedEvents.length });

    return new Response(
      JSON.stringify({ events: extractedEvents }),
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
