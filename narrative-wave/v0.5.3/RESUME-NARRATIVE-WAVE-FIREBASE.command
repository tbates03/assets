#!/usr/bin/env bash
# Narrative Wave v0.5.3 - verify the exact Firebase project before continuing deployment.
# Resume the current standalone website without creating duplicate project IDs or modifying other sites.
set -Eeuo pipefail
umask 077

ROOT="${NARRATIVE_WAVE_PUBLIC_ROOT:-$HOME/Applications/Narrative-Wave/public-web}"
PROJECT_FILE="$ROOT/.nw-project-id"
PENDING_FILE="$ROOT/.nw-pending-project-id"
CHECK_JSON="$ROOT/.nw-v053-projects.json"
ACCESS_LOG="$ROOT/.nw-v053-access.log"
CREATE_LOG="$ROOT/.nw-v053-project-create.log"
FUNCTION_LOG="$ROOT/.nw-v053-function-deploy.log"
APPS_LOG="$ROOT/.nw-v053-apps-check.log"
EXPECTED_ID="narrative-wave-tgot-b64ad8"

printf '\n=== NARRATIVE WAVE | VERIFY PROJECT & RESUME DEPLOYMENT (v0.5.3) ===\n'
if [[ ! -t 0 ]]; then
  printf 'ERROR: Run the downloaded script interactively, not as curl | bash.\n' >&2
  exit 2
fi
if [[ ! -f "$ROOT/firebase.json" || ! -f "$ROOT/functions/index.js" || ! -f "$ROOT/public/index.html" ]]; then
  printf 'ERROR: Narrative Wave public files missing at: %s\n' "$ROOT" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'ERROR: Python3 unavailable; existing app was not changed.' >&2
  exit 2
fi
if command -v brew >/dev/null 2>&1; then
  NODE22="$(brew --prefix node@22 2>/dev/null || true)"
  if [[ -x "$NODE22/bin/node" ]]; then export PATH="$NODE22/bin:$PATH"; fi
fi
if ! command -v node >/dev/null 2>&1; then
  echo 'ERROR: Node.js unavailable; no changes made.' >&2
  exit 2
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo unknown)"
if [[ "$NODE_MAJOR" != 22 && "$NODE_MAJOR" != 24 ]]; then
  printf 'ERROR: Need Node 22 or 24 for this Firebase CLI and backend. Found %s.\n' "$(node --version)" >&2
  exit 2
fi
FB="${NARRATIVE_WAVE_FIREBASE_BIN:-$ROOT/.tools/node_modules/.bin/firebase}"
if [[ ! -x "$FB" ]]; then
  if command -v firebase >/dev/null 2>&1; then FB="$(command -v firebase)";
  else echo 'ERROR: Firebase CLI missing; no changes made.' >&2; exit 2; fi
fi
cd "$ROOT"
unset FIREBASE_TOKEN GOOGLE_APPLICATION_CREDENTIALS CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE || true
printf 'App location: %s\nNode: %s\nFirebase CLI: %s\n' "$ROOT" "$(node --version)" "$("$FB" --version)"
printf '\nAuthenticated Firebase CLI accounts:\n'
"$FB" login:list || true

# The screenshot's project ID is used only if there is no saved project ID.
if [[ -s "$PROJECT_FILE" ]]; then
  PROJECT_ID="$(tr -d '\r\n' < "$PROJECT_FILE")"
  printf '\nFound saved Firebase project: %s\n' "$PROJECT_ID"
  if [[ "$PROJECT_ID" != "$EXPECTED_ID" ]]; then
    printf 'NOTE: This differs from the screenshot (%s). The saved app project takes precedence.\n' "$EXPECTED_ID"
  fi
elif [[ -s "$PENDING_FILE" ]]; then
  PROJECT_ID="$(tr -d '\r\n' < "$PENDING_FILE")"
  printf '\nFound previously pending project: %s\n' "$PROJECT_ID"
else
  PROJECT_ID="$EXPECTED_ID"
  printf '\nUsing the exact project ID visible in your screenshot: %s\n' "$PROJECT_ID"
fi
if [[ ! "$PROJECT_ID" =~ ^narrative-wave-tgot-[a-f0-9]{6}$ ]]; then
  printf 'ERROR: Refusing unrelated Firebase project ID: %s\n' "$PROJECT_ID" >&2
  exit 3
fi

check_projects() {
  : > "$CHECK_JSON"; : > "$ACCESS_LOG"
  "$FB" projects:list --json > "$CHECK_JSON" 2> "$ACCESS_LOG"
}
show_failure() {
  python3 - "$ACCESS_LOG" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='replace').read().splitlines()
terms=('error','denied','401','403','404','429','permission','auth','network','ENOTFOUND','ETIMEDOUT','ECONNRESET','certificate','fetch','connect')
items=[]
for line in s:
 if any(q.lower() in line.lower() for q in terms):
  line=re.sub(r'Bearer\s+\S+','Bearer [REDACTED]',line,flags=re.I)
  line=re.sub(r'(?i)(access_token|refresh_token|id_token|client_secret)\s*[=:]\s*\S+',r'\1=[REDACTED]',line)
  line=re.sub(r'https?://\S+','[URL REDACTED]',line)
  items.append(line[-260:])
print('Firebase API result:')
for item in items[-8:]: print(' ',item)
if not items: print('  No usable error message; check local file:',sys.argv[1])
PY
}
if ! check_projects; then
  show_failure
  if grep -Eiq '401|invalid.grant|invalid_grant|credentials are no longer valid|Authentication Error' "$ACCESS_LOG"; then
    printf '\nThe Firebase CLI credentials appear expired. Refreshing the SAME account once...\n'
    "$FB" login --reauth </dev/tty || { echo 'ERROR: Google consent was not completed.' >&2; exit 4; }
    if ! check_projects; then show_failure;echo 'ERROR: API remains inaccessible. Nothing deployed.' >&2;exit 4;fi
  else
    printf '\nERROR: Firebase cannot list projects for the current CLI account.\n' >&2
    printf 'Do not enable billing or create another project yet.\n' >&2
    printf 'The diagnostic was saved locally: %s\n' "$ACCESS_LOG" >&2
    exit 4
  fi
fi

# Abort rather than falsely treating an error payload as an empty/valid list.
LIST_ID_FILE="$ROOT/.nw-v053-visible-ids.txt"
python3 - "$CHECK_JSON" "$LIST_ID_FILE" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1])); a=d.get('result',d.get('projects',[]))
 if isinstance(a,dict): a=a.get('projects',[])
 if d.get('status') not in (None,'success'): raise ValueError('Firebase reported a non-success status')
 if not isinstance(a,list): raise ValueError('unexpected Firebase project-list result format')
 ids=[x.get('projectId') or x.get('project_id') for x in a if isinstance(x,dict)]
 if any(not isinstance(i,str) for i in ids): raise ValueError('unexpected project entry')
 with open(sys.argv[2],'w') as f: f.write('\n'.join(ids)+'\n')
 print('Firebase API authenticated. Accessible project count:',len(ids))
except Exception as exc:
 raise SystemExit('ERROR: Firebase returned an unrecognized project listing ('+str(exc)+'). Refusing deployment.')
PY

project_visible() { grep -Fqx "$PROJECT_ID" "$LIST_ID_FILE"; }
if project_visible; then
  printf '\nVERIFIED: %s EXISTS and is accessible to the current Firebase CLI account.\n' "$PROJECT_ID"
else
  printf '\nProject %s is NOT listed for this Firebase CLI account.\n' "$PROJECT_ID"
  printf 'Attempting to repair that exact project ID, without choosing or creating another random ID...\n'
  if ! "$FB" projects:create "$PROJECT_ID" --display-name 'Narrative Wave' --non-interactive 2>&1 | tee "$CREATE_LOG"; then
    printf '\nERROR: Google would not create the saved project ID.\n' >&2
    printf 'If Google reports that it already exists, this account lacks access or the project belongs to another account.\n' >&2
    printf 'Switch to the Google account that owns the project; do not create another random project.\n' >&2
    printf 'No existing websites were modified.\n' >&2
    exit 5
  fi
  # Firebase creation can take some time to propagate across project listing APIs.
  VISIBLE=0
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    printf 'Waiting for Firebase to verify project (%s/10)...\n' "$attempt"
    sleep 3
    if check_projects && python3 - "$CHECK_JSON" "$LIST_ID_FILE" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1]));a=d.get('result',d.get('projects',[]))
 if isinstance(a,dict):a=a.get('projects',[])
 assert isinstance(a,list)
 with open(sys.argv[2],'w') as f:f.write('\n'.join(str(x['projectId']) for x in a if isinstance(x,dict))+'\n')
except Exception:sys.exit(1)
PY
    then
      if project_visible;then VISIBLE=1;break;fi
    fi
  done
  if [[ "$VISIBLE" != 1 ]]; then
    echo 'ERROR: Project creation returned success, but Firebase cannot yet verify access.' >&2
    echo 'It may still be provisioning. Rerun this same command later; no other project will be created.' >&2
    exit 5
  fi
  printf 'VERIFIED: Firebase now lists %s.\n' "$PROJECT_ID"
fi

# Do not open a Cloud billing URL unless the Firebase app API can see the same project.
: > "$APPS_LOG"
if ! "$FB" apps:list --project "$PROJECT_ID" > "$APPS_LOG" 2>&1; then
  printf '\nERROR: Project exists but Firebase denies access to list its apps.\n' >&2
  printf 'This matches the permission error in the Chrome screenshot. The website is not ready to deploy.\n' >&2
  tail -n 8 "$APPS_LOG" | sed -E 's/https?:\/\/[^[:space:]]+/(URL redacted)/g' >&2
  exit 6
fi
printf 'VERIFIED: Firebase apps API accessible for project %s.\n' "$PROJECT_ID"
printf 'If Chrome still says the project does not exist, its /u/0 browser account may differ from the CLI account shown above.\n'
printf 'Select that SAME account using the Firebase Console avatar before authorizing any billing.\n'
printf '%s\n' "$PROJECT_ID" > "$PROJECT_FILE"
rm -f "$PENDING_FILE"

# Check the production Node runtime without reinstalling anything.
if command -v npm >/dev/null 2>&1; then
 printf '\nChecking existing research-backend tests...\n'
 (cd "$ROOT/functions" && node --test) || { echo 'ERROR: Research tests failed. No deployment attempted.' >&2;exit 7; }
fi

printf '\nDeploying Narrative Wave research API (dedicated project only)...\n'
deploy_function() { "$FB" deploy --only functions:narrativeApi --project "$PROJECT_ID" --non-interactive 2>&1 | tee "$FUNCTION_LOG"; }
if ! deploy_function; then
  if grep -Eiq 'billing|blaze|upgrade.*plan|cloud billing' "$FUNCTION_LOG"; then
    printf '\nThe EXISTING, VERIFIED project requires billing approval for Cloud Functions.\n'
    printf 'In Chrome, switch to the SAME account shown by Firebase login:list above.\n'
    BILLING_LINK="https://console.firebase.google.com/project/$PROJECT_ID/usage/details"
    printf 'Project billing page: %s\n' "$BILLING_LINK"
    command -v open >/dev/null 2>&1 && open "$BILLING_LINK" >/dev/null 2>&1 || true
    printf 'After authorizing Blaze (if desired), return to THIS Terminal and press Enter to retry.\n'
    IFS= read -r _ </dev/tty
    if ! deploy_function; then
      printf 'ERROR: Cloud Function failed again; original files and project ID are preserved.\n' >&2
      exit 8
    fi
  else
    printf 'ERROR: Functions deployment failed; read the actual Firebase error above.\n' >&2
    exit 8
  fi
fi
printf '\nDeploying Narrative Wave public website...\n'
"$FB" deploy --only hosting --project "$PROJECT_ID" --non-interactive
SITE="https://$PROJECT_ID.web.app"
printf '\nNARRATIVE WAVE PUBLIC SITE DEPLOYED\nURL: %s\nFirebase project: %s\n' "$SITE" "$PROJECT_ID"
printf 'Existing Godfather website and local Narrative Wave data were not changed.\n'
if [[ "${NW_SKIP_PUBLIC_HEALTH:-0}" != 1 ]];then
  if curl -fsSL --max-time 15 "$SITE/api/health" 2>/dev/null | grep -q '"status":"ok"';then
    echo 'Verified: public research API health check passed.'
  else
    echo 'WARNING: Public API health check did not yet pass. Check function logs.' >&2
  fi
fi
if command -v open >/dev/null 2>&1;then open "$SITE" >/dev/null 2>&1 || true;fi