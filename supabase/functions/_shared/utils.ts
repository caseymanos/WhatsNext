import { createClient, type SupabaseClient } from './deps.ts';

/**
 * Create authenticated Supabase client from request headers
 * This ensures RLS policies are enforced using the user's JWT
 */
export function createAuthenticatedClient(req: Request): SupabaseClient {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    throw new Error('Missing Authorization header');
  }

  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    {
      global: {
        headers: { Authorization: authHeader },
      },
    }
  );
}

/**
 * Create service role Supabase client (bypasses RLS)
 * Use only when necessary and with caution
 */
export function createServiceClient(): SupabaseClient {
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!serviceRoleKey) {
    throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY');
  }

  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    serviceRoleKey
  );
}

/**
 * Get authenticated user ID from request
 */
export async function getUserId(supabase: SupabaseClient): Promise<string> {
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    throw new Error('Unauthorized');
  }
  return user.id;
}

/**
 * Check rate limit for AI function calls
 * Returns true if user is within rate limit, false if exceeded
 */
export async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  functionName: string,
  limit: number = 30
): Promise<{ allowed: boolean; count: number }> {
  const oneDayAgo = new Date();
  oneDayAgo.setDate(oneDayAgo.getDate() - 1);

  const { data, error } = await supabase
    .from('ai_usage')
    .select('id')
    .eq('user_id', userId)
    .eq('function_name', functionName)
    .gte('created_at', oneDayAgo.toISOString());

  if (error) {
    console.error('Rate limit check error:', error);
    // On error, allow the request
    return { allowed: true, count: 0 };
  }

  const count = data?.length || 0;
  return { allowed: count < limit, count };
}

/**
 * Log AI function usage for rate limiting and cost tracking
 */
export async function logUsage(
  supabase: SupabaseClient,
  userId: string,
  functionName: string,
  tokensUsed?: number
): Promise<void> {
  const serviceClient = createServiceClient();

  const { error } = await serviceClient
    .from('ai_usage')
    .insert({
      user_id: userId,
      function_name: functionName,
      tokens_used: tokensUsed || null,
    });

  if (error) {
    console.error('Failed to log usage:', error);
    // Don't throw - logging failure shouldn't block the request
  }
}

/**
 * Verify user is a participant in the conversation
 * Uses service client to bypass RLS (safe since we're doing explicit user_id check)
 */
export async function verifyConversationAccess(
  supabase: SupabaseClient,
  userId: string,
  conversationId: string
): Promise<boolean> {
  console.log(`[verifyConversationAccess] Checking user ${userId} for conversation ${conversationId}`);

  // Use service client to avoid RLS issues with conversation_participants
  const serviceClient = createServiceClient();

  const { data, error } = await serviceClient
    .from('conversation_participants')
    .select('user_id')
    .eq('conversation_id', conversationId)
    .eq('user_id', userId)
    .single();

  console.log(`[verifyConversationAccess] Result - data:`, data, `error:`, error);

  const hasAccess = !error && !!data;
  console.log(`[verifyConversationAccess] Final result: ${hasAccess}`);

  return hasAccess;
}

/**
 * Fetch messages for a conversation with optional filters
 */
export async function fetchMessages(
  supabase: SupabaseClient,
  conversationId: string,
  options: {
    limit?: number;
    daysBack?: number;
    messageIds?: string[];
  } = {}
): Promise<any[]> {
  const { limit = 100, daysBack, messageIds } = options;

  let query = supabase
    .from('messages')
    .select('id, conversation_id, sender_id, content, message_type, created_at')
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: false })
    .limit(limit);

  if (daysBack) {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - daysBack);
    query = query.gte('created_at', cutoffDate.toISOString());
  }

  if (messageIds && messageIds.length > 0) {
    query = query.in('id', messageIds);
  }

  const { data, error } = await query;

  if (error) {
    throw new Error(`Failed to fetch messages: ${error.message}`);
  }

  // Return in chronological order (oldest first) for AI processing
  return (data || []).reverse();
}

/**
 * Create CORS headers for response
 */
export function corsHeaders(origin?: string) {
  return {
    'Access-Control-Allow-Origin': origin || '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };
}

/**
 * Generate unique request ID for logging
 */
export function generateRequestId(): string {
  return `${Date.now()}-${Math.random().toString(36).substring(7)}`;
}

/**
 * Structured logging helper (redacts sensitive data)
 */
export function logRequest(
  requestId: string,
  stage: string,
  data: Record<string, any>
): void {
  // Redact message content and other PII
  const sanitized = { ...data };
  if ('messages' in sanitized) {
    delete sanitized.messages;
  }
  if ('content' in sanitized) {
    delete sanitized.content;
  }

  console.log(JSON.stringify({
    requestId,
    stage,
    timestamp: new Date().toISOString(),
    ...sanitized,
  }));
}

/**
 * Fetch messages incrementally based on last analysis time
 * Returns new messages + context messages for continuity
 *
 * @param supabase - Authenticated Supabase client
 * @param conversationId - UUID of the conversation
 * @param featureName - Name of the AI feature (e.g., 'extract-calendar-events')
 * @param options - Configuration options
 * @returns Object containing messages, incremental flag, and new message count
 */
export async function getIncrementalMessages(
  supabase: SupabaseClient,
  conversationId: string,
  featureName: string,
  options: {
    maxDaysBack?: number;
    contextCount?: number;
    maxMessages?: number;
  } = {}
): Promise<{ messages: any[]; isIncremental: boolean; newCount: number }> {
  const { maxDaysBack = 7, contextCount = 2, maxMessages = 100 } = options;

  // Check conversation's last analysis timestamp
  const { data: conv, error: convError } = await supabase
    .from('conversations')
    .select('ai_last_analysis')
    .eq('id', conversationId)
    .single();

  if (convError) {
    throw new Error(`Failed to fetch conversation: ${convError.message}`);
  }

  const lastAnalysisStr = conv?.ai_last_analysis?.[featureName];

  if (!lastAnalysisStr) {
    // First run - fetch all recent messages
    const messages = await fetchMessages(supabase, conversationId, {
      daysBack: maxDaysBack,
      limit: maxMessages
    });
    return { messages, isIncremental: false, newCount: messages.length };
  }

  // Incremental run - fetch new messages since last analysis
  const { data: newMessages, error: newError } = await supabase
    .from('messages')
    .select('id, conversation_id, sender_id, content, message_type, created_at')
    .eq('conversation_id', conversationId)
    .gt('created_at', lastAnalysisStr)
    .order('created_at', { ascending: true })
    .limit(maxMessages);

  if (newError) {
    throw new Error(`Failed to fetch new messages: ${newError.message}`);
  }

  if (!newMessages || newMessages.length === 0) {
    // No new messages since last analysis
    return { messages: [], isIncremental: true, newCount: 0 };
  }

  // Get context messages before the new ones for continuity
  const { data: contextMessages } = await supabase
    .from('messages')
    .select('id, conversation_id, sender_id, content, message_type, created_at')
    .eq('conversation_id', conversationId)
    .lt('created_at', newMessages[0].created_at)
    .order('created_at', { ascending: false })
    .limit(contextCount);

  // Combine context + new messages in chronological order
  const allMessages = [...(contextMessages || []).reverse(), ...newMessages];

  return {
    messages: allMessages,
    isIncremental: true,
    newCount: newMessages.length
  };
}

/**
 * Update conversation and message tracking after AI analysis
 * Should be called after successfully processing and persisting AI results
 *
 * @param conversationId - UUID of the conversation
 * @param featureName - Name of the AI feature (e.g., 'extract-calendar-events')
 * @param processedMessageIds - Array of message IDs that were processed
 */
export async function updateAnalysisTimestamp(
  conversationId: string,
  featureName: string,
  processedMessageIds: string[]
): Promise<void> {
  const now = new Date().toISOString();
  const serviceClient = createServiceClient();

  try {
    // Get current ai_last_analysis JSONB
    const { data: current } = await serviceClient
      .from('conversations')
      .select('ai_last_analysis')
      .eq('id', conversationId)
      .single();

    // Build updated JSONB with new timestamp for this feature
    const updatedAnalysis = {
      ...(current?.ai_last_analysis || {}),
      [featureName]: now
    };

    // Update conversation's ai_last_analysis
    const { error: convError } = await serviceClient
      .from('conversations')
      .update({ ai_last_analysis: updatedAnalysis })
      .eq('id', conversationId);

    if (convError) {
      console.error('Failed to update conversation analysis timestamp:', convError);
      // Don't throw - this is tracking metadata, shouldn't block the response
    }

    // Update processed messages with timestamp
    if (processedMessageIds.length > 0) {
      const { error: msgError } = await serviceClient
        .from('messages')
        .update({ ai_last_processed: now })
        .in('id', processedMessageIds);

      if (msgError) {
        console.error('Failed to update message timestamps:', msgError);
        // Don't throw - this is tracking metadata, shouldn't block the response
      }
    }
  } catch (error) {
    // Log but don't throw - timestamp updates are best-effort
    console.error('Error updating analysis timestamps:', error);
  }
}
