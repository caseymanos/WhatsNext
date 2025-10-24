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
 */
export async function verifyConversationAccess(
  supabase: SupabaseClient,
  userId: string,
  conversationId: string
): Promise<boolean> {
  const { data, error } = await supabase
    .from('conversation_participants')
    .select('user_id')
    .eq('conversation_id', conversationId)
    .eq('user_id', userId)
    .single();

  return !error && !!data;
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
