#!/bin/bash

# Direct test using curl
# Note: This requires a valid JWT token from an authenticated user

set -e

PROJECT_URL="https://wgptkitofarpdyhmmssx.supabase.co"
CONVERSATION_ID="386dd901-8ef9-4f14-a075-46cf63f5e59d"

echo "================================================"
echo "Conflict Detection Agent - Direct Test"
echo "================================================"
echo ""

# For testing, you need a JWT token from an authenticated user
# Option 1: Sign in through the iOS app and get the token
# Option 2: Use the test below to see the structure (will fail auth)

echo "Testing function endpoint..."
echo "URL: $PROJECT_URL/functions/v1/detect-conflicts-agent"
echo ""

# This will fail with 401 Unauthorized because we need a real user JWT
# But it shows the endpoint is accessible
curl -X POST \
  "$PROJECT_URL/functions/v1/detect-conflicts-agent" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN_HERE" \
  -d '{
    "conversationId": "'$CONVERSATION_ID'",
    "daysAhead": 14
  }' \
  -v

echo ""
echo ""
echo "================================================"
echo "To get a real JWT token:"
echo "1. Sign in to the iOS app"
echo "2. Get the session token from UserDefaults or Keychain"
echo "3. Replace YOUR_JWT_TOKEN_HERE above"
echo "================================================"
