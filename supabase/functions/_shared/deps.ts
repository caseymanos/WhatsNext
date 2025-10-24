// Shared dependencies for AI Edge Functions
// This file centralizes all imports for Vercel AI SDK, OpenAI, Zod, and Supabase

// AI SDK imports
export { generateObject, generateText } from 'npm:ai@3.4.29';
export { openai } from 'npm:@ai-sdk/openai@1.0.5';

// Zod for schema validation
export { z } from 'npm:zod@3.22.4';

// Supabase client
export { createClient } from 'jsr:@supabase/supabase-js@2';

// Types
export type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
