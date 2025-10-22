#!/usr/bin/env bash
set -euo pipefail

missing=0
for var in SUPABASE_URL SUPABASE_ANON_KEY; do
  if [ -z "${!var:-}" ]; then
    echo "Missing env: $var"
    missing=1
  fi
done

if [ "$missing" -eq 1 ]; then
  echo "Export required envs or configure in Xcode build settings."
  exit 1
fi

echo "Environment OK."







