#!/usr/bin/env bash
# Narrative Wave v0.5.1 - resume the existing standalone Firebase deployment.
# The installer MUST be executed from Terminal as a file, not through 'curl | bash',
# so Firebase can complete its interactive browser-based authorization.
set -euo pipefail

ROOT="$HOME/Applications/Narrative-Wave/public-web"
PROJECT_FILE="$ROOT/.nw-project-id"
FIREBASE="$ROOT/.tools/node_modules/.bin/firebase"

if [[ ! -f "$ROOT/firebase.json" || ! -f "$ROOT/functions/index.js" || ! -f "$ROOT/public/index.html" || ! -x "$FIREBASE" ]]; then
  printf '\nERROR: The existing Narrative Wave v0.5 public installation was not found.\nExpected directory: %s\nNo existing Firebase projects or apps were changed.\n' "$ROOT" >&2
  exit 1
fi
if [[ ! -t 0 ]]; then
  echo 'ERROR: Run this file in an interactive Mac Terminal. Piping it to bash prevents Firebase login from completing.' >&2
  exit 1
fi

# Prefer the Firebase/Functions-supported Node.js 22 to the unsupported Node 26
# reported by npm, without modifying the globally configured Node installation.
node_major() { command -v node >/dev/null 2>&1 && node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0; }
MAJOR="$(node_major)"
if [[ "$MAJOR" != 22 && "$MAJOR" != 24 ]]; then
  if command -v brew >/dev/null 2>&1; then
    NODE22="$(brew --prefix node@22 2>/dev/null || true)"
    if [[ ! -x "$NODE22/bin/node" ]]; then
      printf '\nSetting up compatible Node.js 22 inside Homebrew...\n'
      if ! brew install node@22; then
        printf 'Homebrew could not install Node 22; attempting with the existing Node installation.\n' >&2
      fi
      NODE22="$(brew --prefix node@22 2>/dev/null || true)"
    fi
    if [[ -x "$NODE22/bin/node" ]]; then
      export PATH="$NODE22/bin:$PATH"
      MAJOR="$(node_major)"
    fi
  fi
fi
printf '\n=== NARRATIVE WAVE - FIREBASE PUBLIC DEPLOYMENT RESUME ===\n'
printf 'Existing app: %s\n' "$ROOT"
printf 'Node.js: %s\n' "$(node --version)"
if [[ "$MAJOR" != 22 && "$MAJOR" != 24 ]]; then
  echo 'Note: Node.js 26 is not in Firebase CLI dependency support ranges. Continuing with the installed CLI; no global changes made.'
fi
printf 'Firebase CLI: %s\n' "$("$FIREBASE" --version)"

# Check authentication first, before creating a project or attempting deploy.
if ! "$FIREBASE" projects:list --json > "$ROOT/.firebase-projects-check.json" 2> "$ROOT/.firebase-login-error.log"; then
  printf '\nGoogle authorization is required. A browser may open.\n'
  printf 'Complete the sign-in in the browser using the Google account that owns your Firebase projects.\n'
  printf 'The deployment will continue automatically once Firebase reports a successful login.\n\n'
  if [[ -r /dev/tty ]]; then
    "$FIREBASE" login < /dev/tty
  else
    "$FIREBASE" login
  fi
  if ! "$FIREBASE" projects:list --json > "$ROOT/.firebase-projects-check.json"; then
    echo 'ERROR: Login did not provide access to Firebase projects. Nothing deployed.' >&2
    exit 1
  fi
fi

# Never deploy into the Godfather website or another manually selected project.
# This file is created only when a new, separately named project is successfully created.
if [[ -s "$PROJECT_FILE" ]]; then
  PROJECT_ID="$(cat "$PROJECT_FILE")"
  if [[ ! "$PROJECT_ID" =~ ^narrative-wave-tgot-[a-f0-9]{6}$ ]]; then
    echo 'ERROR: Saved Narrative Wave project ID is unexpected. Refusing deployment to protect other websites.' >&2
    exit 1
  fi
  printf '\nReusing dedicated Narrative Wave project: %s\n' "$PROJECT_ID"
else
  PROJECT_ID="$(python3 -c 'import secrets;print("narrative-wave-tgot-"+secrets.token_hex(3))')"
  printf '\nCreating a NEW Firebase project exclusively for Narrative Wave: %s\n' "$PROJECT_ID"
  if ! "$FIREBASE" projects:create "$PROJECT_ID" --display-name 'Narrative Wave' --non-interactive; then
    echo 'ERROR: Firebase could not create the new project. Existing websites were not modified.' >&2
    exit 1
  fi
  printf '%s\n' "$PROJECT_ID" > "$PROJECT_FILE"
fi

cd "$ROOT"
FUNCTION_LOG="$ROOT/.last-function-deploy.log"
function_deploy() {
  "$FIREBASE" deploy --only functions:narrativeApi --project "$PROJECT_ID" --non-interactive 2>&1 | tee "$FUNCTION_LOG"
}
printf '\nDeploying public research API to %s...\n' "$PROJECT_ID"
if ! function_deploy; then
  if grep -Eiq 'billing|blaze|upgrade|pay.as.you.go|cloud billing' "$FUNCTION_LOG"; then
    printf '\nFirebase requires the NEW Narrative Wave project to have Blaze billing enabled for Cloud Functions.\n'
    printf 'Your Google account must explicitly approve this in the console; the script cannot enable paid billing.\n'
    BILLING_URL="https://console.firebase.google.com/project/$PROJECT_ID/usage/details"
    printf 'Billing page: %s\n' "$BILLING_URL"
    if command -v open >/dev/null 2>&1; then open "$BILLING_URL" >/dev/null 2>&1 || true; fi
    printf '\nAfter approving Blaze in the browser, return to THIS Terminal and press Enter to retry.\n'
    if [[ -r /dev/tty ]]; then
      IFS= read -r _ < /dev/tty
      if ! function_deploy; then
        echo 'ERROR: Research API deploy failed again. The project ID was saved so this same command can safely resume.' >&2
        exit 2
      fi
    else
      echo 'ERROR: No interactive Terminal available to approve billing; rerun the same command afterward.' >&2
      exit 2
    fi
  else
    echo 'ERROR: Research API deployment failed for a reason other than a recognized billing prompt.' >&2
    echo "Inspect the error above. The project ID is saved in $PROJECT_FILE." >&2
    exit 2
  fi
fi

printf '\nDeploying public website...\n'
"$FIREBASE" deploy --only hosting --project "$PROJECT_ID" --non-interactive
SITE="https://$PROJECT_ID.web.app"
printf '\nPUBLIC WEBSITE DEPLOYED\nURL: %s\nFirebase project: %s\n' "$SITE" "$PROJECT_ID"
printf 'Your Godfather site, local Narrative Wave database, TAi-Core and Agentopia were not touched.\n'

if command -v curl >/dev/null 2>&1; then
  VERIFIED=0
  for i in 1 2 3 4 5; do
    if curl -fsSL --max-time 15 "$SITE/api/health" | grep -q '"status":"ok"'; then
      VERIFIED=1
      break
    fi
    sleep 3
  done
  if [[ "$VERIFIED" -eq 1 ]]; then
    printf 'PUBLIC API VERIFIED - the research API is responding through Firebase Hosting.\n'
  else
    printf 'WARNING: Hosting deployed, but the research API has not yet passed the public health check.\n' >&2
  fi
fi
if command -v open >/dev/null 2>&1; then open "$SITE" >/dev/null 2>&1 || true; fi