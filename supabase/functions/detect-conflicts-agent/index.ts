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

    // Parse request body once (can only read once!)
    const body = await req.json();
    const { conversationId, startDate, endDate, daysAhead } = RequestSchema.parse(body);

    // Check if this is a service role request (from trigger) or user request
    const authHeader = req.headers.get('Authorization') || '';
    const isServiceRole = authHeader.includes(Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '');

    let supabase;
    let userId;

    if (isServiceRole) {
      // Service role request (from trigger) - use service client
      console.log('[ConflictDetection] Service role request detected');
      supabase = createServiceClient();

      // Get first participant of conversation as userId for context
      const { data: participant } = await supabase
        .from('conversation_participants')
        .select('user_id')
        .eq('conversation_id', conversationId)
        .limit(1)
        .single();

      userId = participant?.user_id;

      if (!userId) {
        throw new Error('No participants found for conversation');
      }

      logRequest(requestId, 'service_role', { userId, conversationId });
    } else {
      // Regular user request - authenticate normally
      supabase = createAuthenticatedClient(req);
      userId = await getUserId(supabase);

      logRequest(requestId, 'authenticated', { userId });

      // Verify conversation access
      const hasAccess = await verifyConversationAccess(supabase, userId, conversationId);
      if (!hasAccess) {
        return new Response(
          JSON.stringify({ error: 'Access denied to conversation' }),
          { status: 403, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
        );
      }

      // Check rate limit (allow 100 calls per hour for conflict detection - most are instant cache hits)
      const { allowed, count } = await checkRateLimit(supabase, userId, 'detect-conflicts', 100);
      if (!allowed) {
        return new Response(
          JSON.stringify({ error: 'Rate limit exceeded', count }),
          { status: 429, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
        );
      }

      logRequest(requestId, 'rate_check', { count, allowed });
    }

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
      supabase: serviceClient,  // Always use service client for tool execution
      serviceClient,
      userId,
      conversationId,
    };

    // ========================================================================
    // SMART CACHING: Check if events changed since last analysis
    // ========================================================================
    console.log('[CACHE-CHECK] Checking if conflict analysis is needed');

    // Get last conflict analysis timestamp
    const { data: conversation, error: convError } = await serviceClient
      .from('conversations')
      .select('ai_last_analysis')
      .eq('id', conversationId)
      .single();

    if (convError) {
      console.error('[CACHE-CHECK] Failed to fetch conversation:', convError);
    }

    const lastAnalysisStr = conversation?.ai_last_analysis?.['detect-conflicts'];
    console.log(`[CACHE-CHECK] Last analysis: ${lastAnalysisStr || 'never'}`);

    // Get latest event update timestamp
    const { data: latestEvent, error: eventError } = await serviceClient
      .from('calendar_events')
      .select('updated_at')
      .eq('conversation_id', conversationId)
      .gte('date', startDateStr)
      .lte('date', endDateStr)
      .order('updated_at', { ascending: false })
      .limit(1)
      .single();

    if (eventError && eventError.code !== 'PGRST116') {  // PGRST116 = no rows
      console.error('[CACHE-CHECK] Failed to fetch latest event:', eventError);
    }

    const latestEventUpdate = latestEvent?.updated_at;
    console.log(`[CACHE-CHECK] Latest event update: ${latestEventUpdate || 'none'}`);

    // If we have a last analysis AND no events changed since then, return cached conflicts
    if (lastAnalysisStr && latestEventUpdate) {
      const lastAnalysisDate = new Date(lastAnalysisStr);
      const latestEventDate = new Date(latestEventUpdate);

      if (lastAnalysisDate >= latestEventDate) {
        console.log('[CACHE-CHECK] ✅ Events unchanged, returning cached conflicts');

        // Fetch cached conflicts
        const { data: cachedConflicts } = await serviceClient
          .from('scheduling_conflicts')
          .select('*')
          .eq('conversation_id', conversationId)
          .eq('user_id', userId)
          .eq('status', 'unresolved')
          .order('severity', { ascending: false })
          .order('created_at', { ascending: false });

        logRequest(requestId, 'cache_hit', {
          conflictsCount: cachedConflicts?.length || 0,
          lastAnalysis: lastAnalysisStr,
          latestEventUpdate
        });

        await logUsage(supabase, userId, 'detect-conflicts');

        return new Response(
          JSON.stringify({
            summary: 'Conflicts loaded from cache (no events changed since last analysis)',
            conflicts: cachedConflicts || [],
            detectedCount: cachedConflicts?.length || 0,
            stats: {
              stepsUsed: 0,
              dateRange: { startDate: startDateStr, endDate: endDateStr },
              analysisComplete: true,
              cached: true
            },
            toolCalls: []
          }),
          { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
        );
      } else {
        console.log('[CACHE-CHECK] ⚠️ Events changed, running fresh analysis');
        logRequest(requestId, 'cache_miss', { reason: 'events_updated' });
      }
    } else {
      console.log('[CACHE-CHECK] ⚠️ No previous analysis or no events, running fresh analysis');
      logRequest(requestId, 'cache_miss', { reason: 'first_run_or_no_events' });
    }

    // ========================================================================
    // PRE-PROCESSING: Deterministic same-time conflict detection
    // ========================================================================
    // Fetch all events in date range to check for obvious conflicts
    console.log(`[PRE-PROCESSING] Fetching events for conversation: ${conversationId}`);
    console.log(`[PRE-PROCESSING] Date range: ${startDateStr} to ${endDateStr}`);

    const { data: allEvents, error: fetchError } = await supabase
      .from('calendar_events')
      .select('*')
      .eq('conversation_id', conversationId)
      .gte('date', startDateStr)
      .lte('date', endDateStr)
      .order('date', { ascending: true })
      .order('time', { ascending: true, nullsFirst: false });

    if (fetchError) {
      console.error('[PRE-PROCESSING] Error fetching events:', fetchError);
    }

    console.log(`[PRE-PROCESSING] Fetched ${allEvents?.length || 0} events`);
    if (allEvents && allEvents.length > 0) {
      console.log('[PRE-PROCESSING] Events:', JSON.stringify(allEvents.map(e => ({
        title: e.title,
        date: e.date,
        time: e.time
      }))));
    }

    let preDetectedCount = 0;
    if (allEvents && allEvents.length > 1) {
      console.log(`[PRE-PROCESSING] Checking ${allEvents.length} events for conflicts...`);

      // Check all pairs for exact same-time conflicts
      for (let i = 0; i < allEvents.length; i++) {
        for (let j = i + 1; j < allEvents.length; j++) {
          const event1 = allEvents[i];
          const event2 = allEvents[j];

          console.log(`[PRE-PROCESSING] Comparing: "${event1.title}" (${event1.date} ${event1.time}) vs "${event2.title}" (${event2.date} ${event2.time})`);

          // Exact same date and time = urgent conflict
          const dateMatch = event1.date === event2.date;
          const timeMatch = event1.time === event2.time;
          const timeNotNull = event1.time !== null;

          console.log(`[PRE-PROCESSING] Date match: ${dateMatch}, Time match: ${timeMatch}, Time not null: ${timeNotNull}`);

          if (dateMatch && timeMatch && timeNotNull) {
            console.log(`[PRE-PROCESSING] ⚠️ CONFLICT DETECTED: "${event1.title}" vs "${event2.title}"`);
            // Note: Not storing here - let AI agent handle storage via tools to avoid duplicates
            preDetectedCount++;
          }
        }
      }
    } else {
      console.log('[PRE-PROCESSING] Not enough events to check for conflicts');
    }

    console.log(`[PRE-PROCESSING] Total conflicts detected: ${preDetectedCount}`);

    logRequest(requestId, 'pre_processing', {
      eventsChecked: allEvents?.length || 0,
      sameTimeConflicts: preDetectedCount
    });

    // Clear old unresolved conflicts for this conversation to avoid duplicates
    console.log('[CLEANUP] Clearing old unresolved conflicts for conversation');
    const { error: deleteError } = await serviceClient
      .from('scheduling_conflicts')
      .delete()
      .eq('conversation_id', conversationId)
      .eq('status', 'unresolved');

    if (deleteError) {
      console.error('[CLEANUP] Failed to clear old conflicts:', deleteError);
    } else {
      console.log('[CLEANUP] Old conflicts cleared successfully');
    }

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

    // Run the agent with automatic tool calling loop (reduced maxSteps to avoid timeout)
    console.log('[AI-AGENT] Starting conflict detection analysis');
    const analysisStartTime = Date.now();

    const result = await generateText({
      model: openai('gpt-4o'),
      tools: boundTools,
      maxSteps: 20, // Reduced from 30 to avoid 60s timeout (each step ~2-3s)
      system: systemPrompt,
      prompt: `Analyze the schedule for conflicts and provide a comprehensive report. Check EVERY event pair and store ALL conflicts found, no matter how minor.`,
      onStepFinish: ({ stepType, toolCalls, toolResults }) => {
        const elapsed = ((Date.now() - analysisStartTime) / 1000).toFixed(1);
        console.log(`[AI-AGENT] Step complete (${elapsed}s elapsed)`);

        if (toolCalls) {
          toolCalls.forEach((call, idx) => {
            logRequest(requestId, 'tool_executed', {
              tool: call.toolName,
              args: call.args,
              result: toolResults?.[idx],
              elapsedSeconds: elapsed
            });
          });
        }
      },
    });

    const totalElapsed = ((Date.now() - analysisStartTime) / 1000).toFixed(1);
    console.log(`[AI-AGENT] Analysis complete in ${totalElapsed}s`);

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

    // Update analysis timestamp for caching
    const now = new Date().toISOString();
    await serviceClient
      .from('conversations')
      .update({
        ai_last_analysis: {
          ...conversation?.ai_last_analysis,
          'detect-conflicts': now
        }
      })
      .eq('id', conversationId);

    console.log(`[CACHE-UPDATE] Updated last analysis timestamp to: ${now}`);

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
          analysisComplete: true,
          cached: false
        },
        toolCalls: result.toolCalls?.map((call: any) => ({
          tool: call.toolName,
          args: call.args
        })) || []
      }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders() } }
    );

  } catch (error) {
    console.error('[ERROR] Function failed:', error);
    console.error('[ERROR] Stack:', error.stack);
    logRequest(requestId, 'error', {
      message: error.message,
      name: error.name,
      stack: error.stack?.substring(0, 200) // First 200 chars of stack
    });

    // Determine status code
    let status = 500;
    let errorMessage = error.message || 'Unknown error occurred';

    if (error.message?.includes('Unauthorized') || error.message?.includes('JWT')) {
      status = 401;
      errorMessage = 'Authentication failed. Please sign in again.';
    } else if (error.message?.includes('Access denied') || error.message?.includes('permission')) {
      status = 403;
      errorMessage = 'You do not have access to this conversation.';
    } else if (error.message?.includes('timeout') || error.message?.includes('ETIMEDOUT')) {
      status = 504;
      errorMessage = 'Analysis took too long. Try again with fewer events or a shorter time range.';
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
