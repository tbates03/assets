#!/usr/bin/env bash
# Narrative Wave v0.6 Spark-compatible PUBLIC deployment.
# Uses only Firebase Hosting; no Cloud Functions, billing change, or plugins.
# Targets ONLY narrative-wave-tgot-b64ad8 with account tim@pyrinas.co.
set -euo pipefail

PROJECT="narrative-wave-tgot-b64ad8"
ACCOUNT="tim@pyrinas.co"
ROOT="${NARRATIVE_WAVE_PUBLIC_ROOT:-$HOME/Applications/Narrative-Wave/public-web}"
MODE="${1:-deploy}"
if [[ "$MODE" != "deploy" && "$MODE" != "--dry-run" ]]; then
  echo "Usage: bash DEPLOY-NARRATIVE-WAVE-SPARK.command [--dry-run]" >&2; exit 2
fi
if [[ ! -f "$ROOT/public/index.html" || ! -f "$ROOT/firebase.json" ]]; then
  printf 'ERROR: Existing Narrative Wave public files not found at %s\nNothing changed.\n' "$ROOT" >&2
  exit 1
fi
if [[ "$MODE" != "--dry-run" ]]; then
  if [[ ! -s "$ROOT/.nw-project-id" ]]; then
    echo 'ERROR: Missing saved Narrative Wave Firebase project ID; refusing to guess or create a project.' >&2
    exit 1
  fi
  ACTUAL="$(tr -d '\r\n' < "$ROOT/.nw-project-id")"
  if [[ "$ACTUAL" != "$PROJECT" ]]; then
    printf 'ERROR: Project ID safety check failed: %s (expected %s)\nNothing changed.\n' "$ACTUAL" "$PROJECT" >&2
    exit 1
  fi
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'ERROR: Python 3 was not found. Existing site was not modified.' >&2
  exit 1
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/narrative-wave-spark.XXXXXXXX")"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

# Package hash and allowed filenames are verified before a single file is changed.
python3 - "$TMP" <<'NW_SPARK_ARCHIVE'
import base64,gzip,hashlib,io,sys,tarfile
from pathlib import Path
payload='''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
4+f/yc//AW7oXAwA8AAA'''
compressed=base64.b64decode(''.join(payload.split()),validate=True)
expected='0676ac32fa2cb33a80d30c20a404c67a3982c21adbe9a4ae40afa130a9642957'
if hashlib.sha256(compressed).hexdigest()!=expected:
    raise SystemExit('ERROR: Public website archive SHA-256 mismatch; nothing changed.')
allowed={'index.html','spark.css','spark.js','favicon.svg','README-SPARK.md'}
out=Path(sys.argv[1]);names=set()
with tarfile.open(fileobj=io.BytesIO(gzip.decompress(compressed)),mode='r:') as archive:
    for entry in archive.getmembers():
        if entry.name not in allowed or not entry.isfile() or entry.size>150000 or entry.name in names:
            raise SystemExit('ERROR: Unexpected or unsafe website archive file. Nothing changed.')
        names.add(entry.name)
        (out/entry.name).write_bytes(archive.extractfile(entry).read())
if names!=allowed:raise SystemExit('ERROR: Incomplete website archive. Nothing changed.')
print('Verified Narrative Wave Spark v0.6 public website files.')
NW_SPARK_ARCHIVE

if [[ "$MODE" == "--dry-run" ]]; then
  if command -v node >/dev/null 2>&1; then node --check "$TMP/spark.js"; fi
  printf '\nDRY RUN COMPLETE. No public deployment, project creation, or local file changes.\n'
  exit 0
fi

# Reuse the existing private Firebase CLI. NEVER install or replace global tools.
FB="$ROOT/.tools/node_modules/.bin/firebase"
if [[ ! -x "$FB" ]]; then
  echo "ERROR: The existing private Firebase CLI is missing: $FB" >&2
  echo 'No new tools were installed; existing site unchanged.' >&2
  exit 1
fi
if command -v brew >/dev/null 2>&1; then
  BREW_NODE="$(brew --prefix node@22 2>/dev/null || true)"
  if [[ -x "$BREW_NODE/bin/node" ]]; then export PATH="$BREW_NODE/bin:$PATH"; fi
fi
MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
if [[ "$MAJOR" != "22" && "$MAJOR" != "24" ]]; then
  printf 'ERROR: Firebase CLI needs Node 22 or 24; current: %s\nExisting files unchanged.\n' "$(node --version 2>/dev/null || echo unavailable)" >&2
  exit 1
fi
printf '\n=== NARRATIVE WAVE v0.6 | FIREBASE SPARK DEPLOY ===\n'
printf 'Firebase account: %s\nFirebase project: %s\nMode: Hosting only (Spark, no Blaze)\n' "$ACCOUNT" "$PROJECT"
printf 'Node: %s | Firebase CLI: %s\n' "$(node --version)" "$("$FB" --version)"
if ! "$FB" login:list 2>&1 | grep -Fq "$ACCOUNT"; then
  echo 'ERROR: Firebase CLI is not logged into tim@pyrinas.co. No changes were made.' >&2
  echo 'Sign in to Firebase CLI with the correct account before running this same command.' >&2
  exit 1
fi
# Firebase supports --account to guarantee the correct project owner is used.
unset FIREBASE_TOKEN GOOGLE_APPLICATION_CREDENTIALS 2>/dev/null || true
if ! "$FB" --account "$ACCOUNT" projects:list --json > "$TMP/projects.json"; then
  echo 'ERROR: Firebase could not list projects for tim@pyrinas.co; nothing was deployed.' >&2
  exit 1
fi
if ! python3 - "$TMP/projects.json" "$PROJECT" <<'PY'
import json,sys
try:
 r=json.load(open(sys.argv[1])).get('result',[])
 if isinstance(r,dict):r=r.get('projects',[])
 ok=isinstance(r,list) and any(item.get('projectId')==sys.argv[2] for item in r if isinstance(item,dict))
except Exception:ok=False
if not ok:raise SystemExit(1)
PY
then
  echo 'ERROR: The exact Narrative Wave project is not visible to tim@pyrinas.co; refusing to target a different project.' >&2
  exit 1
fi
printf 'Confirmed access to the existing Narrative Wave Firebase project.\n'

# The new Firebase default-site policy (effective Oct 15, 2026) means
# a freshly-created project might not have a default Hosting site yet.
if ! "$FB" --account "$ACCOUNT" hosting:sites:list --project "$PROJECT" --json > "$TMP/sites.json"; then
  echo 'ERROR: Could not query Firebase Hosting sites. No site creation attempted.' >&2
  exit 1
fi
python3 - "$TMP/sites.json" "$TMP/site-name" "$TMP/site-url" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])).get('result',[])
if isinstance(r,dict):r=r.get('sites',[])
if not isinstance(r,list):raise SystemExit('ERROR: Unrecognized Hosting site response; no changes made.')
defsites=[x for x in r if isinstance(x,dict) and x.get('type')=='DEFAULT_SITE']
if not defsites and r:
    # Do not create another site when one already exists but metadata is ambiguous.
    defsites=[r[0]]
s=defsites[0] if defsites else {}
name=str(s.get('name','')).rsplit('/',1)[-1] if s else ''
url=str(s.get('defaultUrl','')) if s else ''
if name and not name.replace('-','').isalnum():raise SystemExit('ERROR: Invalid site ID from Firebase.')
open(sys.argv[2],'w').write(name)
open(sys.argv[3],'w').write(url or (f'https://{name}.web.app' if name else ''))
PY
SITE_ID="$(cat "$TMP/site-name")"
if [[ -z "$SITE_ID" ]]; then
  printf '\nThis new Firebase project does not yet have its default Hosting site. Creating it on Spark...\n'
  # Only create the exact intended default site in the already-verified project.
  "$FB" --account "$ACCOUNT" hosting:sites:create "$PROJECT" --project "$PROJECT" --non-interactive
  SITE_ID="$PROJECT"
  printf '%s\n' "https://$PROJECT.web.app" > "$TMP/site-url"
else
  printf 'Existing Hosting site: %s\n' "$SITE_ID"
fi

# Back up older public UI outside the folder that Firebase publishes.
STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP="$ROOT/.nw-spark-backups/$STAMP"
mkdir -p "$BACKUP"
cp -R "$ROOT/public" "$BACKUP/public"
[[ ! -f "$ROOT/firebase.spark.json" ]] || cp "$ROOT/firebase.spark.json" "$BACKUP/firebase.spark.json"
cp "$TMP/index.html" "$ROOT/public/index.html"
cp "$TMP/spark.css" "$ROOT/public/spark.css"
cp "$TMP/spark.js" "$ROOT/public/spark.js"
cp "$TMP/favicon.svg" "$ROOT/public/favicon.svg"
cp "$TMP/README-SPARK.md" "$ROOT/README-SPARK.md"

# Dedicated Hosting-only config; original firebase.json/functions preserved verbatim.
python3 - "$ROOT/firebase.spark.json" "$SITE_ID" <<'PY'
import json,sys
path,site=sys.argv[1:3]
config={'hosting':{
  'site':site,'public':'public',
  'ignore':['**/.*','**/node_modules/**'],
  'headers':[{'source':'**','headers':[
    {'key':'X-Content-Type-Options','value':'nosniff'},
    {'key':'Referrer-Policy','value':'strict-origin-when-cross-origin'},
    {'key':'Cache-Control','value':'public, max-age=300'}
  ]}]
}}
with open(path,'w') as f:json.dump(config,f,indent=2);f.write('\n')
PY
node --check "$ROOT/public/spark.js"
printf '\nBacked up previous website files to %s\n' "$BACKUP"
printf 'Deploying static website to Firebase Hosting (NO Cloud Functions)...\n'
cd "$ROOT"
if ! "$FB" --account "$ACCOUNT" deploy --only hosting --config firebase.spark.json --project "$PROJECT" --non-interactive; then
  echo 'ERROR: Firebase Hosting deployment failed. Previous website files were backed up; no Functions were deployed.' >&2
  exit 2
fi
SITE="$(cat "$TMP/site-url")"
if [[ ! "$SITE" =~ ^https://[a-z0-9-]+\.web\.app$ ]]; then
  SITE="https://$SITE_ID.web.app"
fi
printf '\nNARRATIVE WAVE SPARK WEBSITE DEPLOYED\nPublic URL: %s\nAccount: %s\nProject: %s\nPlan: Spark (Hosting only)\n' "$SITE" "$ACCOUNT" "$PROJECT"
printf 'Local TAi, Agentopia, Godfather website, Cloud Functions and SQLite research data were NOT modified.\n'
VERIFIED=0
if command -v curl >/dev/null 2>&1; then
  for attempt in 1 2 3 4 5; do
    if curl -fLsS --max-time 15 "$SITE/?nw_spark=06" 2>/dev/null | grep -q 'FIREBASE SPARK EDITION'; then
      VERIFIED=1;break
    fi
    sleep 4
  done
fi
if [[ "$VERIFIED" == "1" ]]; then
  printf 'PUBLIC SITE VERIFIED: Firebase is serving the Spark interface.\n'
else
  printf 'NOTICE: Hosting deploy reported success but live page could not be independently verified yet. Check the URL after a minute.\n' >&2
fi
printf 'The site can search GDELT from each visitor browser. Live feed availability depends on that third-party API.\n'
if command -v open >/dev/null 2>&1; then open "$SITE" >/dev/null 2>&1 || true; fi