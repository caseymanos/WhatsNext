#!/usr/bin/env -S deno run --allow-net --allow-env

/**
 * Test script for conflict detection agent
 *
 * Usage:
 *   deno run --allow-net --allow-env test-agent.ts <email> <password>
 *
 * Or set environment variables:
 *   TEST_USER_EMAIL=user@example.com
 *   TEST_USER_PASSWORD=password
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.0';

const SUPABASE_URL = 'https://wgptkitofarpdyhmmssx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndncHRraXRvZmFycGR5aG1tc3N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjEwMjYxNDgsImV4cCI6MjA3NjYwMjE0OH0.L-WW15OaaYGDyQowAlhXFvSa8TNNjCHo0xjfYDdfy6s';
const CONVERSATION_ID = '386dd901-8ef9-4f14-a075-46cf63f5e59d';

async function main() {
  console.log('============================================');
  console.log('Conflict Detection Agent Test');
  console.log('============================================\n');

  // Get credentials
  const email = Deno.args[0] || Deno.env.get('TEST_USER_EMAIL');
  const password = Deno.args[1] || Deno.env.get('TEST_USER_PASSWORD');

  if (!email || !password) {
    console.error('❌ Error: Email and password required');
    console.error('\nUsage:');
    console.error('  deno run --allow-net --allow-env test-agent.ts <email> <password>');
    console.error('\nOr set environment variables:');
    console.error('  TEST_USER_EMAIL=user@example.com');
    console.error('  TEST_USER_PASSWORD=password');
    Deno.exit(1);
  }

  // Create Supabase client
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  // Sign in
  console.log('1. Authenticating user...');
  const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (authError) {
    console.error('❌ Authentication failed:', authError.message);
    Deno.exit(1);
  }

  console.log('✅ Authenticated as:', authData.user.email);
  console.log('   User ID:', authData.user.id);

  const token = authData.session.access_token;
  console.log('   Token length:', token.length, 'characters\n');

  // Call the edge function
  console.log('2. Calling detect-conflicts-agent...');
  console.log('   Conversation:', CONVERSATION_ID);
  console.log('   Analysis period: 14 days\n');

  const startTime = Date.now();

  const response = await fetch(
    `${SUPABASE_URL}/functions/v1/detect-conflicts-agent`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        conversationId: CONVERSATION_ID,
        daysAhead: 14,
      }),
    }
  );

  const elapsed = Date.now() - startTime;

  console.log('3. Response received');
  console.log('   Status:', response.status, response.statusText);
  console.log('   Time:', elapsed, 'ms\n');

  if (!response.ok) {
    const errorText = await response.text();
    console.error('❌ Error:', errorText);
    Deno.exit(1);
  }

  const result = await response.json();

  console.log('============================================');
  console.log('Results');
  console.log('============================================\n');

  console.log('📊 Stats:');
  console.log('   Tool calls:', result.stats?.stepsUsed || 0);
  console.log('   Date range:', result.stats?.dateRange?.startDate, 'to', result.stats?.dateRange?.endDate);
  console.log('   Conflicts detected:', result.detectedCount);
  console.log('   Conflicts stored:', result.conflicts?.length || 0);
  console.log('');

  if (result.toolCalls && result.toolCalls.length > 0) {
    console.log('🔧 Tools Used:');
    const toolCounts = result.toolCalls.reduce((acc: any, call: any) => {
      acc[call.tool] = (acc[call.tool] || 0) + 1;
      return acc;
    }, {});
    Object.entries(toolCounts).forEach(([tool, count]) => {
      console.log(`   ${tool}: ${count}x`);
    });
    console.log('');
  }

  console.log('📝 AI Summary:');
  console.log(result.summary);
  console.log('');

  if (result.conflicts && result.conflicts.length > 0) {
    console.log('⚠️  Stored Conflicts:');
    result.conflicts.forEach((conflict: any, idx: number) => {
      const severityEmoji = {
        urgent: '🔴',
        high: '🟠',
        medium: '🟡',
        low: '🟢',
      }[conflict.severity] || '⚪';

      console.log(`\n${idx + 1}. ${severityEmoji} ${conflict.conflict_type.toUpperCase()} (${conflict.severity})`);
      console.log(`   ${conflict.description}`);
      console.log(`   → ${conflict.suggested_resolution}`);
      if (conflict.affected_items && conflict.affected_items.length > 0) {
        console.log(`   Affects: ${conflict.affected_items.join(', ')}`);
      }
    });
  } else {
    console.log('✅ No conflicts stored (either none detected or storage failed)');
  }

  console.log('\n============================================');
  console.log('Test Complete');
  console.log('============================================');

  // Sign out
  await supabase.auth.signOut();
}

main().catch((error) => {
  console.error('\n❌ Fatal error:', error);
  Deno.exit(1);
});
