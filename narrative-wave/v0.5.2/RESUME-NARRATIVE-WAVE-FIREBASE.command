#!/usr/bin/env bash
# Narrative Wave v0.5.2: repair Firebase account access and resume a safe, separate deploy.
# Runs from a REAL interactive Terminal, not through `curl | bash`.
# Does not reinstall npm/CLI packages, modify other Firebase projects, or delete local data.
set -Eeuo pipefail

ROOT="${NARRATIVE_WAVE_PUBLIC_ROOT:-$HOME/Applications/Narrative-Wave/public-web}"
PROJECT_FILE="$ROOT/.nw-project-id"
PENDING_FILE="$ROOT/.nw-pending-project-id"
CHECK_JSON="$ROOT/.nw-projects-check.json"
ACCESS_LOG="$ROOT/.nw-firebase-access-diagnostic.log"
FUNCTION_LOG="$ROOT/.nw-function-deploy.log"
CREATE_LOG="$ROOT/.nw-project-create.log"

printf '\n=== NARRATIVE WAVE | FIREBASE DEPLOYMENT REPAIR v0.5.2 ===\n'
if [[ ! -t 0 ]]; then
  printf 'ERROR: This deployer requires an interactive Terminal. Execute the downloaded file; do not pipe it to bash.\n' >&2
  exit 2
fi
if [[ ! -f "$ROOT/firebase.json" || ! -f "$ROOT/public/index.html" || ! -f "$ROOT/functions/index.js" ]]; then
  printf 'ERROR: Existing public Narrative Wave files are missing at %s.\n' "$ROOT" >&2
  printf 'No projects or websites were modified.\n' >&2
  exit 2
fi
if ! command -v node >/dev/null 2>&1; then
  printf 'ERROR: Node.js is unavailable. The existing application has not been changed.\n' >&2
  exit 2
fi

# Node 26 was previously unsupported by the app/runtime. Choose already-installed Node 22 first.
if command -v brew >/dev/null 2>&1; then
  NODE22_DIR="$(brew --prefix node@22 2>/dev/null || true)"
  if [[ -x "$NODE22_DIR/bin/node" ]]; then
    export PATH="$NODE22_DIR/bin:$PATH"
  fi
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
printf 'Node.js: %s\n' "$(node --version)"
if [[ "$NODE_MAJOR" != 22 && "$NODE_MAJOR" != 24 ]]; then
  printf 'WARNING: Node %s is not the version targeted by this Firebase Functions deployment.\n' "$NODE_MAJOR" >&2
  printf 'Please install Node 22 before attempting Cloud Functions deployment.\n' >&2
  exit 2
fi

FB="${NARRATIVE_WAVE_FIREBASE_BIN:-$ROOT/.tools/node_modules/.bin/firebase}"
if [[ ! -x "$FB" ]]; then
  if command -v firebase >/dev/null 2>&1; then
    FB="$(command -v firebase)"
  else
    printf 'ERROR: Firebase CLI not found. The v0.5 installer should have placed it in %s/.tools.\n' "$ROOT" >&2
    exit 2
  fi
fi
printf 'Firebase CLI: %s\n' "$("$FB" --version)"
printf 'Project directory: %s\n' "$ROOT"
cd "$ROOT"
umask 077

# Priority: a legacy FIREBASE_TOKEN or unrelated service account may silently override
# the interactive Firebase CLI account. Unset these only inside this deployer.
if [[ -n "${FIREBASE_TOKEN:-}" ]]; then
  printf 'Found an old FIREBASE_TOKEN override. Ignoring it for THIS deployment only.\n'
  unset FIREBASE_TOKEN
fi
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  printf 'Found a GOOGLE_APPLICATION_CREDENTIALS override. Using the CLI login for THIS deployment only.\n'
  unset GOOGLE_APPLICATION_CREDENTIALS
fi
if [[ -n "${CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE:-}" ]]; then
  unset CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE
fi

printf '\nExisting Firebase CLI accounts:\n'
"$FB" login:list || true

# Preserve original API errors instead of mislabeling every failure as a login problem.
# Store debug only on the user's own Mac, not on the public website.
try_project_access() {
  : > "$CHECK_JSON"
  : > "$ACCESS_LOG"
  if "$FB" projects:list --json --debug > "$CHECK_JSON" 2> "$ACCESS_LOG"; then
    return 0
  fi
  return 1
}

show_cause() {
  python3 - "$ACCESS_LOG" <<'PY'
from pathlib import Path
import re,sys
log=Path(sys.argv[1]).read_text(errors='replace').splitlines()
print('Firebase API diagnostic (filtered; tokens are not shown):')
patterns=[
 r'HTTP Error:\s*[0-9]{3}', r'\[apiv2\]\[status\].*\s(401|403|404|429|5\d\d)\b',
 r'invalid.grant', r'credentials are no longer valid', r'permission denied',
 r'PERMISSION_DENIED', r'ACCESS_TOKEN', r'insufficient.*permission',
 r'Authentication Error', r'Failed to make request', r'getaddrinfo', r'ENOTFOUND',
 r'ETIMEDOUT', r'ECONNREFUSED', r'ECONNRESET', r'CERTIFICATE',
 r'Unable to parse JSON', r'Failed to list Firebase projects', r'Error:.*(403|401|quota|project)',
]
seen=[]
for line in log:
    if any(re.search(p,line,re.I) for p in patterns):
        # only a short diagnostic excerpt; suppress bearer tokens and URL query parameters
        line=re.sub(r'Bearer\s+\S+','Bearer [REDACTED]',line,flags=re.I)
        line=re.sub(r'(?i)(access_token|refresh_token|id_token|client_secret|authorization)\s*[=:]\s*\S+',r'\1=[REDACTED]',line)
        line=re.sub(r'https?://[^\s]+', '[URL REDACTED]',line)
        line=line[-280:]
        if line not in seen:
            seen.append(line)
for line in seen[-9:]: print('  '+line)
if not seen:
    print('  No status code in CLI stderr. Full diagnostic remains local at:',sys.argv[1])
PY
}

access_class() {
  python3 - "$ACCESS_LOG" <<'PY'
from pathlib import Path
import sys,re
s=Path(sys.argv[1]).read_text(errors='replace')
if re.search(r'\b403\b|PERMISSION_DENIED|insufficient.permissions|permission denied|not authorized',s,re.I): print('permission')
elif re.search(r'\b401\b|invalid.grant|credentials are no longer valid|Authentication Error|unauthorized',s,re.I): print('expired')
elif re.search(r'ENOTFOUND|ETIMEDOUT|ECONNRESET|CERTIFICATE|ENETUNREACH|EAI_AGAIN|Unexpected token.*<|Unable to parse JSON',s,re.I): print('network')
else: print('unknown')
PY
}

printf '\nTesting your EXISTING Google Firebase authorization...\n'
ACCESS_OK=0
if try_project_access; then
  ACCESS_OK=1
elif [[ -z "${NARRATIVE_WAVE_FIREBASE_BIN:-}" ]] && command -v firebase >/dev/null 2>&1; then
  # Previously successful Mac deployments may have used the existing global Firebase CLI.
  # The private and global CLI can differ in version even with the same cached account.
  GLOBAL_FB="$(command -v firebase)"
  if [[ "$GLOBAL_FB" != "$FB" ]]; then
    printf 'Private Firebase CLI could not list projects. Checking your existing system Firebase CLI...\n'
    PRIVATE_FB="$FB"
    FB="$GLOBAL_FB"
    if try_project_access; then
      ACCESS_OK=1
      printf 'Existing system CLI works. Using: %s (version %s)\n' "$FB" "$("$FB" --version)"
    else
      # The global result is the latest diagnostic. Restore the private CLI for repair.
      FB="$PRIVATE_FB"
    fi
  fi
fi
if [[ "$ACCESS_OK" == 0 ]]; then
  CATEGORY="$(access_class)"
  show_cause
  if [[ "$CATEGORY" == 'network' ]]; then
    printf '\nERROR: Firebase could not complete its API request; this looks like a network, DNS, SSL, or proxy issue.\n' >&2
    printf 'No logout or project creation was attempted.\n' >&2
    exit 3
  fi
  if [[ "$CATEGORY" == 'permission' ]]; then
    printf '\nFirebase returned a permission error. Select an existing authorized Firebase account if you have more than one.\n'
    "$FB" login:use < /dev/tty || true
  else
    printf '\nFirebase login is cached, but the API access failed. Refreshing consent ONCE (not logging out other apps)...\n'
    if ! "$FB" login --reauth < /dev/tty; then
      printf 'ERROR: Google authorization was not completed; nothing was deployed.\n' >&2
      exit 3
    fi
  fi
  printf '\nRetesting the Firebase API after the account correction...\n'
  if ! try_project_access; then
    show_cause
    printf '\nERROR: Firebase still cannot list accessible projects.\n' >&2
    printf 'This is not an app-test or Node problem. Inspect the Firebase API error above. No project was created.\n' >&2
    printf 'Local diagnostic: %s\n' "$ACCESS_LOG" >&2
    printf 'If access is denied, check which Google account owns your existing Firebase projects.\n' >&2
    exit 3
  fi
fi
printf 'Firebase API access: OK.\n'
python3 - "$CHECK_JSON" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1])); a=d.get('result',d.get('projects',[]));
 if isinstance(a,dict): a=a.get('projects',[])
 ids=[str(x.get('projectId','')) for x in a if isinstance(x,dict)]
 print('Accessible projects:',len(ids),'| Existing Godfather project listed:', 'yes' if 'thegodfatheroftech' in ids else 'not in this account/list')
except Exception as e:
 print('Project list responded, but result summary was unavailable. Continuing with explicit project IDs.')
PY

valid_project_id() { [[ "$1" =~ ^narrative-wave-tgot-[a-f0-9]{6}$ ]]; }
if [[ -s "$PROJECT_FILE" ]]; then
  PROJECT_ID="$(tr -d '\r\n' < "$PROJECT_FILE")"
  if ! valid_project_id "$PROJECT_ID"; then
    printf 'ERROR: Unrecognized project ID in %s; refusing to touch an unrelated website.\n' "$PROJECT_FILE" >&2
    exit 4
  fi
  printf '\nResuming Narrative Wave project: %s\n' "$PROJECT_ID"
else
  if [[ -s "$PENDING_FILE" ]]; then
    PROJECT_ID="$(tr -d '\r\n' < "$PENDING_FILE")"
    if ! valid_project_id "$PROJECT_ID"; then
      echo 'ERROR: Saved pending project ID is invalid. No action taken.' >&2
      exit 4
    fi
  else
    PROJECT_ID="$(python3 -c 'import secrets;print("narrative-wave-tgot-"+secrets.token_hex(3))')"
    printf '%s\n' "$PROJECT_ID" > "$PENDING_FILE"
  fi
  printf '\nCreating separate Narrative Wave project: %s\n' "$PROJECT_ID"
  # If a previous run completed creation before being interrupted, the project may already exist.
  if python3 - "$CHECK_JSON" "$PROJECT_ID" <<'PY'
import json,sys
try:
 a=json.load(open(sys.argv[1])).get('result',[])
 if isinstance(a,dict): a=a.get('projects',[])
 assert any(x.get('projectId')==sys.argv[2] for x in a)
except Exception: sys.exit(1)
PY
  then
    printf 'Found previously created dedicated project; reusing it.\n'
  else
    if ! "$FB" projects:create "$PROJECT_ID" --display-name 'Narrative Wave' --non-interactive 2>&1 | tee "$CREATE_LOG"; then
      printf 'ERROR: Firebase could not create a new project. See CLI error above.\n' >&2
      printf 'No existing Firebase project or website was targeted.\n' >&2
      exit 4
    fi
  fi
  printf '%s\n' "$PROJECT_ID" > "$PROJECT_FILE"
  rm -f "$PENDING_FILE"
fi

printf '\nDeploying Narrative Wave research function to %s...\n' "$PROJECT_ID"
deploy_function() { "$FB" deploy --only functions:narrativeApi --project "$PROJECT_ID" --non-interactive 2>&1 | tee "$FUNCTION_LOG"; }
if ! deploy_function; then
  if grep -Eiq 'billing|blaze|upgrade.*plan|cloud billing' "$FUNCTION_LOG"; then
    printf '\nCloud Functions requires Google billing approval on this dedicated Narrative Wave project.\n'
    BILLING_URL="https://console.firebase.google.com/project/$PROJECT_ID/usage/details"
    printf '%s\n' "$BILLING_URL"
    command -v open >/dev/null 2>&1 && open "$BILLING_URL" >/dev/null 2>&1 || true
    printf 'Complete the approval in your Google browser, then press Enter here to retry.\n'
    IFS= read -r _ < /dev/tty
    if ! deploy_function; then
      printf 'ERROR: Functions deployment still failed; the dedicated project ID is saved. No other site was changed.\n' >&2
      exit 5
    fi
  else
    printf 'ERROR: Functions deployment failed for a reason other than billing. See exact error above.\n' >&2
    printf 'Your project is saved as %s so rerunning the same script will resume safely.\n' "$PROJECT_ID" >&2
    exit 5
  fi
fi
printf '\nPublishing Narrative Wave website...\n'
"$FB" deploy --only hosting --project "$PROJECT_ID" --non-interactive
SITE="https://$PROJECT_ID.web.app"
printf '\nPUBLIC WEBSITE DEPLOYED\n%s\n' "$SITE"
printf 'Firebase project: %s\nGodfather website and all other projects were not targeted.\n' "$PROJECT_ID"

if [[ "${NW_SKIP_PUBLIC_HEALTH:-0}" != 1 ]]; then
  VERIFIED=0
  for i in 1 2 3 4 5; do
    if curl -fsSL --max-time 15 "$SITE/api/health" 2>/dev/null | grep -q '"status":"ok"'; then VERIFIED=1;break;fi
    sleep 3
  done
  if [[ "$VERIFIED" == 1 ]]; then
    printf 'Public research API health check: VERIFIED.\n'
  else
    printf 'WARNING: Hosting deployed; public research API health is NOT verified yet.\n' >&2
  fi
fi
if command -v open >/dev/null 2>&1; then open "$SITE" >/dev/null 2>&1 || true; fi