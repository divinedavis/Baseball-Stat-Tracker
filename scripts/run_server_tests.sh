#!/usr/bin/env bash
# Edge-function tests (Deno). No network calls to Supabase or Anthropic;
# only fetches pinned module URLs (esm.sh / jsr) on first run.
#   scripts/run_server_tests.sh
set -euo pipefail
cd "$(dirname "$0")/../supabase"
exec deno test --allow-net --allow-read --allow-env tests/
