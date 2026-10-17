#!/usr/bin/env bash
# Narrative Wave v0.6.1 Spark-compatible PUBLIC deployment.
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
l3+//Pv/zr//FzVjZykAGAEA'''
compressed=base64.b64decode(''.join(payload.split()),validate=True)
expected='50071e75552ef13afb88fe8e38e62b273ebbc607a23d9da9e67b322db7b25db0'
if hashlib.sha256(compressed).hexdigest()!=expected:
    raise SystemExit('ERROR: Public website archive SHA-256 mismatch; nothing changed.')
allowed={'index.html','spark.css','spark.js','favicon.svg','README-SPARK.md','legal.html','pyrinas-wordmark.svg'}
out=Path(sys.argv[1]);names=set()
with tarfile.open(fileobj=io.BytesIO(gzip.decompress(compressed)),mode='r:') as archive:
    for entry in archive.getmembers():
        if entry.name not in allowed or not entry.isfile() or entry.size>150000 or entry.name in names:
            raise SystemExit('ERROR: Unexpected or unsafe website archive file. Nothing changed.')
        names.add(entry.name)
        (out/entry.name).write_bytes(archive.extractfile(entry).read())
if names!=allowed:raise SystemExit('ERROR: Incomplete website archive. Nothing changed.')
print('Verified Narrative Wave Spark v0.6.1 public website files.')
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
printf '\n=== NARRATIVE WAVE v0.6.1 | FIREBASE SPARK DEPLOY ===\n'
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
cp "$TMP/legal.html" "$ROOT/public/legal.html"
cp "$TMP/pyrinas-wordmark.svg" "$ROOT/public/pyrinas-wordmark.svg"

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
    if curl -fLsS --max-time 15 "$SITE/?nw_spark=061" 2>/dev/null | grep -q 'Pyrinas.co'; then
      VERIFIED=1;break
    fi
    sleep 4
  done
fi
if [[ "$VERIFIED" == "1" ]]; then
  if ! curl -fLsS --max-time 15 "$SITE/legal.html" 2>/dev/null | grep -q "Privacy &amp; data practices"; then
    printf "WARNING: Legal page not yet verified after Hosting deployment. Please check %s/legal.html\n" "$SITE" >&2
  fi
  printf 'PUBLIC SITE VERIFIED: Firebase is serving the Pyrinas-branded Spark interface.\n'
else
  printf 'NOTICE: Hosting deploy reported success but live page could not be independently verified yet. Check the URL after a minute.\n' >&2
fi
printf 'Pyrinas.co wordmark, footer, and legal disclosures are live. The site can search GDELT from each visitor browser. Live feed availability depends on that third-party API.\n'
if command -v open >/dev/null 2>&1; then open "$SITE" >/dev/null 2>&1 || true; fi