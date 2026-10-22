#!/usr/bin/env bash
# Builds the Arah web app and puts it live on Cloudflare Pages:
#   https://arah-2xp.pages.dev  (Cloudflare added -2xp: arah.pages.dev was taken)
#
#   ./tools/web/deploy.sh
#
# Same Cloudflare account and wrangler login as the portfolio
# (`npx wrangler login` if it ever expires). The web app is online only: no
# offline packs, GPS only while the page is open.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export CLOUDFLARE_ACCOUNT_ID="863c8569b09cb26bbcb75f90f23a26e5"
PROJECT=arah
cd "$ROOT"

source "$HOME/Documents/dev/tools/flutter-env.sh"
flutter build web --release --no-wasm-dry-run

# The project was created once on 2026-10-22 with
#   wrangler pages project create arah --production-branch main --force
# (--force keeps it on classic Pages instead of Workers; only needed to create).
npx --yes wrangler@latest pages deploy build/web --project-name "$PROJECT" --branch main --commit-dirty=true
