import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { generateText, openai, tool } from '../_shared/deps.ts';
import { z } from '../_shared/deps.ts';
import {
  createAuthenticatedClient,
  createServiceClient,
  getUserId,
  checkRateLimit,
  logUsage,
  verifyConversationAccess,
  corsHeaders,
  generateRequestId,
  logRequest,
} from '../_shared/utils.ts';
import { conflictDetectionTools } from './tools.ts';

// Request schema
const RequestSchema = z.object({
  conversationId: z.string().uuid(),
  startDate: z.string().optional(),
  endDate: z.string().optional(),
  daysAhead: z.number().min(1).max(30).default(14),
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
    const { conversationId, startDate, endDate, daysAhead } = RequestSchema.parse(body);

    // Verify conversation access
    const hasAccess = await verifyConversationAccess(supabase, userId, conversationId);
    if (!hasAccess) {
      return new Response(
        JSON.stringify({ error: 'Access denied to conversation' }),
        { status: 403, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    // Check rate limit (allow 20 calls per hour for conflict detection)
    const { allowed, count } = await checkRateLimit(supabase, userId, 'detect-conflicts', 20);
    if (!allowed) {
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded', count }),
        { status: 429, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
      );
    }

    logRequest(requestId, 'rate_check', { count, allowed });

    // Calculate date range
    const today = startDate ? new Date(startDate) : new Date();
    const futureDate = endDate ? new Date(endDate) : new Date();
    if (!endDate) {
      futureDate.setDate(today.getDate() + daysAhead);
    }

    const startDateStr = today.toISOString().split('T')[0];
    const endDateStr = futureDate.toISOString().split('T')[0];

    // Create execution context for tools
    const serviceClient = createServiceClient();
    const toolContext = {
      supabase,
      serviceClient,
      userId,
      conversationId,
    };

    // ========================================================================
    // PRE-PROCESSING: Deterministic same-time conflict detection
    // ========================================================================
    // Fetch all events in date range to check for obvious conflicts
    const { data: allEvents } = await supabase
      .from('calendar_events')
      .select('*')
      .eq('conversation_id', conversationId)
      .gte('date', startDateStr)
      .lte('date', endDateStr)
      .order('date', { ascending: true })
      .order('time', { ascending: true, nullsFirst: false });

    let preDetectedCount = 0;
    if (allEvents && allEvents.length > 1) {
      // Check all pairs for exact same-time conflicts
      for (let i = 0; i < allEvents.length; i++) {
        for (let j = i + 1; j < allEvents.length; j++) {
          const event1 = allEvents[i];
          const event2 = allEvents[j];

          // Exact same date and time = urgent conflict
          if (event1.date === event2.date &&
              event1.time === event2.time &&
              event1.time !== null) {

            try {
              await serviceClient
                .from('scheduling_conflicts')
                .insert({
                  conversation_id: conversationId,
                  user_id: userId,
                  conflict_type: 'time_overlap',
                  severity: 'urgent',
                  description: `Direct time overlap: "${event1.title}" and "${event2.title}" both scheduled at ${event1.time} on ${event1.date}`,
                  affected_items: [event1.title, event2.title],
                  suggested_resolution: 'One event must be rescheduled immediately to avoid conflict',
                  status: 'unresolved'
                });

              preDetectedCount++;
              console.log(`Pre-detected conflict: ${event1.title} vs ${event2.title} at ${event1.time}`);
            } catch (error) {
              console.error('Failed to store pre-detected conflict:', error);
            }
          }
        }
      }
    }

    logRequest(requestId, 'pre_processing', {
      eventsChecked: allEvents?.length || 0,
      sameTimeConflicts: preDetectedCount
    });

    // Bind tools with context
    const boundTools: Record<string, any> = {};
    for (const [name, toolDef] of Object.entries(conflictDetectionTools)) {
      boundTools[name] = tool({
        description: toolDef.description,
        parameters: toolDef.parameters,
        execute: async (params: any) => {
          return await (toolDef.execute as any)(params, toolContext);
        },
      });
    }

    // System prompt for conflict detection agent
    const systemPrompt = `You are a proactive scheduling conflict detection assistant for busy parents and caregivers.

Your goal is to analyze the user's calendar, deadlines, and commitments to identify:
1. **Time conflicts** - Overlapping events, insufficient travel time, back-to-back scheduling
2. **Capacity conflicts** - Too many events in one day, consecutive busy days, peak hour clustering
3. **Deadline pressure** - Calendar events preventing task completion, deadline clustering

## CRITICAL RULES (MUST FOLLOW):
- **ALWAYS call analyzeTimeConflict for EVERY pair of events on the same day** - no exceptions
- **Events at the EXACT same time are ALWAYS urgent conflicts** - this should never be missed
- **Store ALL detected conflicts using storeConflict** - even low severity ones matter
- **Be thorough, not selective** - missing conflicts is worse than over-reporting
- **Call storeConflict IMMEDIATELY after detecting each conflict** - don't wait or filter

## Process (Follow Exactly):
1. Use getCalendarEvents to fetch events in the date range (${startDateStr} to ${endDateStr})
2. Use getDeadlines to fetch pending deadlines
3. **For EVERY pair of events on the same day**, call analyzeTimeConflict (this is mandatory)
4. **IMMEDIATELY call storeConflict for each conflict returned** from analyzeTimeConflict
5. For all events together, use analyzeCapacity to check daily load
6. **Call storeConflict for each capacity conflict** returned
7. For each deadline, use checkDeadlineConflict to verify feasibility
8. **Call storeConflict for each deadline conflict** detected
9. Create reminders for urgent items using createReminder

## Conflict Severity Guidelines:
- **URGENT**: Direct overlap, deadline passed, no way to meet commitment
- **HIGH**: <15min buffer with travel needed, deadline at risk (< 50% chance), >5 events in one day
- **MEDIUM**: <30min buffer, tight deadline (50-80% chance), 3-4 events in one day
- **LOW**: Same day/unclear times, back-to-back same location, comfortable deadline

## Output Requirements:
Provide a clear, actionable summary focusing on:
- Number and severity of conflicts found (include ALL conflicts, not just urgent)
- Specific dates/times affected
- Brief recommendations for each significant conflict
- Priority order (urgent first, but list all)

Current date: ${today.toISOString().split('T')[0]}
Analysis period: ${daysAhead} days (${startDateStr} to ${endDateStr})`;

    // Run the agent with automatic tool calling loop
    const result = await generateText({
      model: openai('gpt-4o'),
      tools: boundTools,
      maxSteps: 30, // Allow up to 30 tool calls for thorough analysis
      system: systemPrompt,
      prompt: `Analyze the schedule for conflicts and provide a comprehensive report. Check EVERY event pair and store ALL conflicts found, no matter how minor.`,
      onStepFinish: ({ stepType, toolCalls, toolResults }) => {
        if (toolCalls) {
          toolCalls.forEach((call, idx) => {
            logRequest(requestId, 'tool_executed', {
              tool: call.toolName,
              args: call.args,
              result: toolResults?.[idx]
            });
          });
        }
      },
    });

    logRequest(requestId, 'agent_complete', {
      stepsUsed: result.toolCalls?.length || 0,
      responseLength: result.text.length
    });

    // Extract detected conflicts from tool results
    const detectedConflicts = result.toolResults
      ?.filter((r: any) => r?.conflict === true || r?.capacityConflicts)
      .flatMap((r: any) => r.capacityConflicts || [r]) || [];

    // Fetch stored conflicts from database
    const { data: storedConflicts } = await serviceClient
      .from('scheduling_conflicts')
      .select('*')
      .eq('conversation_id', conversationId)
      .eq('user_id', userId)
      .eq('status', 'unresolved')
      .order('severity', { ascending: false })
      .order('created_at', { ascending: false });

    // Log usage
    await logUsage(supabase, userId, 'detect-conflicts');

    logRequest(requestId, 'complete', {
      conflictsDetected: detectedConflicts.length,
      conflictsStored: storedConflicts?.length || 0
    });

    return new Response(
      JSON.stringify({
        summary: result.text,
        conflicts: storedConflicts || [],
        detectedCount: detectedConflicts.length,
        stats: {
          stepsUsed: result.toolCalls?.length || 0,
          dateRange: { startDate: startDateStr, endDate: endDateStr },
          analysisComplete: true
        },
        toolCalls: result.toolCalls?.map((call: any) => ({
          tool: call.toolName,
          args: call.args
        })) || []
      }),
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
