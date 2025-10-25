#!/bin/bash

# Test script for conflict detection edge function
# This script invokes the detect-conflicts-agent function with test data

set -e

PROJECT_REF="wgptkitofarpdyhmmssx"
CONVERSATION_ID="386dd901-8ef9-4f14-a075-46cf63f5e59d"

echo "================================================"
echo "Testing Conflict Detection Agent"
echo "================================================"
echo ""
echo "Project: $PROJECT_REF"
echo "Conversation: $CONVERSATION_ID"
echo ""

# Test payload
PAYLOAD='{
  "conversationId": "'$CONVERSATION_ID'",
  "daysAhead": 14
}'

echo "Invoking function with payload:"
echo "$PAYLOAD"
echo ""
echo "================================================"
echo ""

# Invoke the function using Supabase CLI
# This will use the linked project credentials
supabase functions invoke detect-conflicts-agent \
  --project-ref "$PROJECT_REF" \
  --region us-east-1 \
  --body "$PAYLOAD"

echo ""
echo "================================================"
echo "Checking stored conflicts in database..."
echo "================================================"
echo ""

# Query the conflicts table to see what was stored
echo "Running SQL query to fetch conflicts..."
echo ""
