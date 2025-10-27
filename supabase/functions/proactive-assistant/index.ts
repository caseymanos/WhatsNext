import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { generateText, openai, z } from '../_shared/deps.ts';
import {
  createAuthenticatedClient,
  getUserId,
  checkRateLimit,
  logUsage,
  verifyConversationAccess,
  corsHeaders,
  generateRequestId,
  logRequest,
} from '../_shared/utils.ts';

// Tool definitions for the proactive assistant
const tools = {
  getRecentMessages: {
    description: 'Fetch recent messages from a conversation',
    parameters: z.object({
      limit: z.number().default(50).describe('Number of recent messages to fetch'),
      daysBack: z.number().optional().describe('Limit to messages from the last N days'),
    }),
  },
  getCalendarEvents: {
    description: 'Get upcoming calendar events for the user',
    parameters: z.object({
      daysAhead: z.number().default(14).describe('Number of days ahead to look'),
    }),
  },
  getPendingRSVPs: {
    description: 'Get all pending RSVP requests for the user',
    parameters: z.object({}),
  },
  getDeadlines: {
    description: 'Get upcoming deadlines for the user',
    parameters: z.object({
      status: z.enum(['pending', 'completed', 'all']).default('pending'),
      daysAhead: z.number().default(30).describe('Look ahead this many days'),
    }),
  },
  checkConflicts: {
    description: 'Check for scheduling conflicts in calendar events',
    parameters: z.object({
      daysAhead: z.number().default(7).describe('Days to check for conflicts'),
    }),
  },
  createReminder: {
    description: 'Create a reminder for the user',
    parameters: z.object({
      title: z.string().describe('Reminder title'),
      reminderTime: z.string().describe('When to send reminder (ISO 8601)'),
      priority: z.enum(['urgent', 'high', 'medium', 'low']).default('medium'),
    }),
  },
};

// Request schema
const RequestSchema = z.object({
  conversationId: z.string().uuid(),
  query: z.string().optional().describe('Optional specific query from user'),
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
    const { conversationId, query } = RequestSchema.parse(body);

    // Use authenticated user ID from JWT token
    const userId = authUserId;

    // Verify conversation access
    console.log(`[ProactiveAssistant] Checking access for user ${userId} to conversation ${conversationId}`);
    const hasAccess = await verifyConversationAccess(supabase, userId, conversationId);
    console.log(`[ProactiveAssistant] Access check result: ${hasAccess}`);
    if (!hasAccess) {
      console.error(`[ProactiveAssistant] 403-ACCESS-DENIED: user ${userId} not participant in conversation ${conversationId}`);
      return new Response(
        JSON.stringify({ error: '[ACCESS-DENIED] Access denied to conversation' }),
        { status: 403, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    // Check rate limit (stricter for agent calls)
    const { allowed, count } = await checkRateLimit(supabase, userId, 'proactive-assistant', 15);
    if (!allowed) {
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded', count }),
        { status: 429, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    logRequest(requestId, 'rate_check', { count, allowed });

    // Get user profile
    const { data: userProfile } = await supabase
      .from('users')
      .select('display_name, username')
      .eq('id', userId)
      .single();

    const userName = userProfile?.display_name || userProfile?.username || 'User';

    // Tool execution context
    const toolExecutionLog: any[] = [];
    const maxToolCalls = 5;
    let toolCallCount = 0;

    // Tool execution function
    async function executeTool(toolName: string, params: any): Promise<any> {
      if (toolCallCount >= maxToolCalls) {
        return { error: 'Maximum tool calls reached' };
      }
      toolCallCount++;

      logRequest(requestId, 'tool_call', { tool: toolName, params });
      toolExecutionLog.push({ tool: toolName, params });

      try {
        switch (toolName) {
          case 'getRecentMessages': {
            const { limit = 50, daysBack } = params;
            let query = supabase
              .from('messages')
              .select('id, content, created_at, sender_id')
              .eq('conversation_id', conversationId)
              .order('created_at', { ascending: false })
              .limit(limit);

            if (daysBack) {
              const cutoff = new Date();
              cutoff.setDate(cutoff.getDate() - daysBack);
              query = query.gte('created_at', cutoff.toISOString());
            }

            const { data, error } = await query;
            if (error) throw error;

            return { messages: (data || []).reverse() };
          }

          case 'getCalendarEvents': {
            const { daysAhead = 14 } = params;
            const today = new Date();
            const futureDate = new Date();
            futureDate.setDate(futureDate.getDate() + daysAhead);

            const { data, error } = await supabase
              .from('calendar_events')
              .select('*')
              .eq('conversation_id', conversationId)
              .gte('date', today.toISOString().split('T')[0])
              .lte('date', futureDate.toISOString().split('T')[0])
              .order('date', { ascending: true });

            if (error) throw error;
            return { events: data || [] };
          }

          case 'getPendingRSVPs': {
            const { data, error } = await supabase
              .from('rsvp_tracking')
              .select('*')
              .eq('user_id', userId)
              .eq('status', 'pending')
              .order('deadline', { ascending: true, nullsFirst: false });

            if (error) throw error;
            return { rsvps: data || [] };
          }

          case 'getDeadlines': {
            const { status = 'pending', daysAhead = 30 } = params;
            const futureDate = new Date();
            futureDate.setDate(futureDate.getDate() + daysAhead);

            let query = supabase
              .from('deadlines')
              .select('*')
              .eq('user_id', userId)
              .lte('deadline', futureDate.toISOString())
              .order('deadline', { ascending: true });

            if (status !== 'all') {
              query = query.eq('status', status);
            }

            const { data, error } = await query;
            if (error) throw error;
            return { deadlines: data || [] };
          }

          case 'checkConflicts': {
            const { daysAhead = 7 } = params;
            const today = new Date();
            const futureDate = new Date();
            futureDate.setDate(futureDate.getDate() + daysAhead);

            const { data: events, error } = await supabase
              .from('calendar_events')
              .select('*')
              .eq('conversation_id', conversationId)
              .gte('date', today.toISOString().split('T')[0])
              .lte('date', futureDate.toISOString().split('T')[0])
              .order('date', { ascending: true })
              .order('time', { ascending: true, nullsFirst: false });

            if (error) throw error;

            // Simple conflict detection: same date with overlapping times
            const conflicts: any[] = [];
            const eventsByDate = (events || []).reduce((acc: any, event: any) => {
              if (!acc[event.date]) acc[event.date] = [];
              acc[event.date].push(event);
              return acc;
            }, {});

            for (const [date, dateEvents] of Object.entries(eventsByDate)) {
              const eventsArray = dateEvents as any[];
              if (eventsArray.length > 1) {
                // Check for time overlaps or just multiple events on same day
                for (let i = 0; i < eventsArray.length - 1; i++) {
                  conflicts.push({
                    date,
                    event1: eventsArray[i].title,
                    event2: eventsArray[i + 1].title,
                    reason: 'Multiple events on same day',
                  });
                }
              }
            }

            return { conflicts };
          }

          case 'createReminder': {
            const { title, reminderTime, priority = 'medium' } = params;

            // Insert using service client (handled via RLS allowing ai creation)
            const { data, error } = await supabase
              .from('reminders')
              .insert({
                user_id: userId,
                title,
                reminder_time: reminderTime,
                priority,
                status: 'pending',
                created_by: 'ai',
              })
              .select()
              .single();

            if (error) throw error;
            return { reminder: data };
          }

          default:
            return { error: `Unknown tool: ${toolName}` };
        }
      } catch (error) {
        console.error(`Tool execution error for ${toolName}:`, error);
        return { error: error.message };
      }
    }

    // Run the AI agent
    const systemPrompt = `You are a proactive AI assistant helping ${userName}, a busy parent/caregiver, manage their family schedule and responsibilities.

Your role is to:
1. Identify potential scheduling conflicts
2. Remind about pending RSVPs and deadlines
3. Suggest actions to stay organized
4. Create helpful reminders
5. Provide a concise summary of what needs attention

You have access to tools to:
- Get recent messages from the conversation
- Check calendar events
- Review pending RSVPs
- Check upcoming deadlines
- Detect scheduling conflicts
- Create reminders

Be proactive but concise. Focus on actionable insights.

Today's date: ${new Date().toISOString().split('T')[0]}`;

    const userQuery = query ||
      'Please review my schedule, check for any conflicts, pending RSVPs, and upcoming deadlines. Provide a brief summary of what needs my attention.';

    // Simple agentic loop (without full tool calling API - Vercel AI SDK will handle this better in production)
    const result = await generateText({
      model: openai('gpt-4o'),
      prompt: `${systemPrompt}\n\nUser request: ${userQuery}\n\nAnalyze the user's needs and provide actionable guidance.`,
      maxTokens: 800,
    });

    const message = result.text;

    // Execute key tools to gather context for response enhancement
    const [events, rsvps, deadlines] = await Promise.all([
      executeTool('getCalendarEvents', { daysAhead: 14 }),
      executeTool('getPendingRSVPs', {}),
      executeTool('getDeadlines', { status: 'pending', daysAhead: 30 }),
    ]);

    // Check for conflicts
    const conflicts = await executeTool('checkConflicts', { daysAhead: 7 });

    logRequest(requestId, 'agent_complete', {
      toolCalls: toolCallCount,
      upcomingEvents: events.events?.length || 0,
      pendingRSVPs: rsvps.rsvps?.length || 0,
      pendingDeadlines: deadlines.deadlines?.length || 0,
      conflicts: conflicts.conflicts?.length || 0,
    });

    // Log usage
    await logUsage(supabase, userId, 'proactive-assistant');

    return new Response(
      JSON.stringify({
        message,
        insights: {
          upcomingEvents: events.events || [],
          pendingRSVPs: rsvps.rsvps || [],
          upcomingDeadlines: deadlines.deadlines || [],
          schedulingConflicts: conflicts.conflicts || [],
        },
        toolsUsed: toolExecutionLog,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
    );

  } catch (error) {
    console.error('[ERROR] ProactiveAssistant function failed:', error);
    console.error('[ERROR] Stack:', error.stack);
    logRequest(requestId, 'error', {
      message: error.message,
      name: error.name,
      stack: error.stack?.substring(0, 200) // First 200 chars of stack
    });

    // Determine status code and user-friendly message
    let status = 500;
    let errorMessage = error.message || 'Unknown error occurred';

    if (error.message?.includes('Unauthorized') || error.message?.includes('JWT')) {
      status = 401;
      errorMessage = 'Authentication failed. Please sign in again.';
    } else if (error.message?.includes('Access denied') || error.message?.includes('ACCESS-DENIED') || error.message?.includes('permission')) {
      status = 403;
      errorMessage = 'You do not have access to this conversation.';
      console.error(`[ProactiveAssistant] 403-ERROR-HANDLER: error.message="${error.message}"`);
    } else if (error.message?.includes('timeout') || error.message?.includes('ETIMEDOUT')) {
      status = 504;
      errorMessage = 'Analysis took too long. Try again later.';
    } else if (error.message?.includes('Rate limit')) {
      status = 429;
      errorMessage = 'Too many requests. Please wait a moment and try again.';
    } else if (error.name === 'ZodError') {
      status = 400;
      errorMessage = 'Invalid request parameters.';
    } else {
      // Generic error - provide helpful message
      errorMessage = `Analysis failed: ${error.message}. This may be temporary - try again.`;
    }

    return new Response(
      JSON.stringify({
        error: errorMessage,
        details: error.message,
        requestId
      }),
      { status, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
    );
  }
});
