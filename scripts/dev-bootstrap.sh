#!/usr/bin/env bash
set -euo pipefail

echo "==> Verifying Supabase CLI..."
if ! command -v supabase >/dev/null 2>&1; then
  echo "Error: Supabase CLI not found. Install: https://supabase.com/docs/guides/cli" >&2
  exit 1
fi

echo "==> Pushing database migrations..."
supabase db push

echo "==> Listing functions (if any)..."
supabase functions list || true

echo "==> Done. Configure Xcode build settings with SUPABASE_URL and SUPABASE_ANON_KEY."







