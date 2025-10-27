#!/bin/bash

# Helper script to configure the service role key in Supabase database
# This script will prompt for the service role key and insert it into app_settings

set -e

echo "========================================="
echo "Service Role Key Configuration"
echo "========================================="
echo ""
echo "This script will help you configure the service role key for auto-parsing."
echo ""
echo "IMPORTANT: Get your service role key from:"
echo "https://supabase.com/dashboard/project/wgptkitofarpdyhmmssx/settings/api"
echo ""
echo "Look for the 'service_role' key (NOT the 'anon' key)"
echo ""
read -sp "Paste your service role key here (input hidden): " SERVICE_ROLE_KEY
echo ""
echo ""

if [ -z "$SERVICE_ROLE_KEY" ]; then
    echo "Error: Service role key cannot be empty"
    exit 1
fi

# Validate key format (should start with eyJ for JWT)
if [[ ! "$SERVICE_ROLE_KEY" =~ ^eyJ ]]; then
    echo "Warning: The key doesn't look like a valid JWT token (should start with 'eyJ')"
    read -p "Continue anyway? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Inserting service role key into database..."

# Use supabase db execute to run the SQL
SQL_COMMAND="INSERT INTO app_settings (key, value, description)
VALUES (
  'service_role_key',
  '$SERVICE_ROLE_KEY',
  'Service role key for internal API calls'
)
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  updated_at = NOW();"

echo "$SQL_COMMAND" | supabase db execute --project-ref wgptkitofarpdyhmmssx

echo ""
echo "✅ Service role key configured successfully!"
echo ""
echo "Verifying configuration..."
supabase db execute --project-ref wgptkitofarpdyhmmssx -c "SELECT key, description, created_at FROM app_settings ORDER BY key;"

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Auto-parsing is now enabled. Try sending a test message like:"
echo "  'Soccer practice Monday at 3pm'"
echo ""
echo "The message should automatically be parsed into an event."
echo ""
