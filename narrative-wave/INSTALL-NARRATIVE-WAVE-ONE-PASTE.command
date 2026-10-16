#!/bin/bash
# Narrative Wave - one-paste, no-download local macOS installer
set -euo pipefail
APP="$HOME/Applications/Narrative-Wave"
if ! command -v python3 >/dev/null 2>&1; then
  echo 'ERROR: Python 3 is required but not available in this Terminal.' >&2
  exit 1
fi
PYTHON="$(command -v python3)"
if ! "$PYTHON" -c 'import sqlite3, http.server, xml.etree.ElementTree' >/dev/null 2>&1; then
  echo 'ERROR: The selected Python lacks required standard-library modules.' >&2
  exit 1
fi
if [[ -e "$APP" && ! -d "$APP" ]]; then
  echo "ERROR: $APP is a file, not a directory. No files changed." >&2
  exit 1
fi
if [[ -d "$APP" && -n "$(ls -A "$APP" 2>/dev/null)" && ! -f "$APP/.narrative-wave-install" && ! -f "$APP/.narrative-wave-one-paste" ]]; then
  echo "ERROR: $APP belongs to another application. No files changed." >&2
  exit 1
fi
mkdir -p "$APP/standalone" "$APP/data"
cat > "$APP/standalone/app.py" <<'NW_PYTHON'
#!/usr/bin/env python3
"""Narrative Wave standalone: local-first evidence ledger and live headline collector."""
import collections
import datetime as dt
import email.utils
import html
import json
import os
import pathlib
import re
import sqlite3
import subprocess
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent.parent
DB = ROOT / 'data' / 'narrative_wave_standalone.sqlite3'
PAGE = ROOT / 'standalone' / 'index.html'
LOCK = threading.RLock()
RUNNING = False
LAST = {'at': None, 'added': 0, 'revised': 0, 'errors': []}
TOPICS = {
  'US news': 'https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en',
  'Katie Zacharia': 'https://news.google.com/rss/search?q=Katie+Zacharia+press+secretary&hl=en-US&gl=US&ceid=US:en',
  'Finance': 'https://news.google.com/rss/search?q=financial+markets+stocks&hl=en-US&gl=US&ceid=US:en',
  'Technology': 'https://news.google.com/rss/search?q=artificial+intelligence+technology&hl=en-US&gl=US&ceid=US:en',
  'Global': 'https://feeds.bbci.co.uk/news/world/rss.xml',
  'Business': 'https://feeds.bbci.co.uk/news/business/rss.xml',
}
SOURCES = [
 {'id':'nw001','publisher':'Associated Press','frame':'stepping down','headline':"The Latest: Trump's new press secretary Katie Zacharia is leaving post after a rocky start",'basis':'AP reports the departure; headline wording alone does not establish whether it was involuntary.','url':'https://apnews.com/article/5da043282984cc21947a2d9c8147e4ff'},
 {'id':'nw002','publisher':'NPR / KPBS','frame':'transitioning out','headline':"Katie Zacharia is 'transitioning out' as press secretary, White House says",'basis':'NPR attributes this description to a White House official not authorized to speak on the record.','url':'https://www.kpbs.org/news/politics/2026/10/16/katie-zacharia-is-transitioning-out-as-press-secretary-white-house-says'},
 {'id':'nw003','publisher':'The Guardian','frame':'fired','headline':'Katie Zacharia fired after five days as White House press secretary - reports','basis':'Guardian headline cites reports of firing and notes other White House terminology.','url':'https://www.theguardian.com/us-news/2026/oct/16/katie-zacharia-fired-press-secretary'},
 {'id':'nw004','publisher':'CBS News','frame':'reconsider','headline':'Trump opens door to Katie Zacharia leaving as White House press secretary after a week on the job','basis':'CBS quotes the president describing his suggestion that she reconsider the role; that is not a dismissal document.','url':'https://www.cbsnews.com/news/trump-katie-zacharia-white-house-press-secretary/'},
 {'id':'nw005','publisher':'UPI','frame':'fired','headline':'Katie Zacharia out as White House press secretary','basis':'UPI attributes the assertion that she was fired to unnamed sources reported by media outlets.','url':'https://www.upi.com/Top_News/US/2026/10/16/trump-fires-white-house-press-secretary-katie-zacharia/3521792174705/'},
]
CLAIMS = [
 {'id':'C1','claim':'Zacharia is departing the press secretary position.','status':'Corroborated reporting','detail':'Multiple sources report a departure; an official is cited describing a transition.'},
 {'id':'C2','claim':'She was fired or dismissed.','status':'Attributed, not independently established','detail':'Some outlets cite unnamed sources. Their reporting is evidence of an attributed claim, not a public dismissal notice.'},
 {'id':'C3','claim':'She chose to resign voluntarily.','status':'Not established','detail':'"Transitioning out" and advice to reconsider do not establish a voluntary resignation.'},
 {'id':'C4','claim':'Trump told her to reconsider the job.','status':'Publicly attributed statement','detail':'The president described this conversation publicly. It does not settle how the departure was decided.'},
 {'id':'C5','claim':'Outlets coordinated to promote a false story.','status':'Not established','detail':'Similar headlines and wording are not proof of coordination; syndication and shared sources are alternative explanations.'},
]

def now(): return dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')
def connect():
    db = sqlite3.connect(str(DB), timeout=20)
    db.row_factory = sqlite3.Row
    return db

def init():
    DB.parent.mkdir(parents=True, exist_ok=True)
    with connect() as db:
        db.executescript('''
        CREATE TABLE IF NOT EXISTS articles (
          url TEXT PRIMARY KEY, title TEXT NOT NULL, publisher TEXT,
          topic TEXT, published TEXT, first_seen TEXT, last_seen TEXT
        );
        CREATE TABLE IF NOT EXISTS revisions (
          id INTEGER PRIMARY KEY, url TEXT, old_title TEXT, new_title TEXT, observed_at TEXT
        );
        CREATE TABLE IF NOT EXISTS reviews (
          id INTEGER PRIMARY KEY, claim_id TEXT, conclusion TEXT, notes TEXT, reviewed_at TEXT
        );
        ''')

def parse_feed(payload, topic):
    root = ET.fromstring(payload)
    result = []
    for item in root.findall('.//item')[:45]:
        def val(tag):
            node = item.find(tag)
            return ''.join(node.itertext()).strip() if node is not None else ''
        title, url, pub = val('title'), val('link'), val('pubDate')
        source = item.find('source')
        publisher = ''.join(source.itertext()).strip() if source is not None else ''
        publisher = publisher or urllib.parse.urlparse(url).netloc or topic
        try:
            d = email.utils.parsedate_to_datetime(pub)
            published = d.astimezone(dt.timezone.utc).isoformat(timespec='seconds')
        except (ValueError, TypeError, OverflowError):
            published = None
        if title and url.startswith('http'):
            result.append((url, html.unescape(title), publisher, topic, published))
    return result

def collect():
    global RUNNING
    added = revised = 0
    errors = []
    try:
        for topic, url in TOPICS.items():
            try:
                request = urllib.request.Request(url, headers={'User-Agent':'NarrativeWaveResearch/0.2 (+local user app)'})
                with urllib.request.urlopen(request, timeout=7) as response:
                    content = response.read(1500000)
                entries = parse_feed(content, topic)
                with connect() as db:
                    for link, title, publisher, category, published in entries:
                        previous = db.execute('SELECT title FROM articles WHERE url=?', (link,)).fetchone()
                        if previous is None:
                            db.execute('INSERT INTO articles VALUES (?,?,?,?,?,?,?)',
                                       (link, title, publisher, category, published, now(), now()))
                            added += 1
                        else:
                            if previous['title'] != title:
                                db.execute('INSERT INTO revisions (url,old_title,new_title,observed_at) VALUES (?,?,?,?)',
                                           (link, previous['title'], title, now()))
                                db.execute('UPDATE articles SET title=?,last_seen=? WHERE url=?', (title, now(), link))
                                revised += 1
                            else:
                                db.execute('UPDATE articles SET last_seen=? WHERE url=?', (now(), link))
            except Exception as exc:
                errors.append('%s: %s' % (topic, str(exc)[:180]))
    finally:
        with LOCK:
            LAST.update(at=now(), added=added, revised=revised, errors=errors)
            RUNNING = False

def read_payload(handler):
    length = int(handler.headers.get('Content-Length', '0'))
    if length > 12000: raise ValueError('Request too large')
    return json.loads(handler.rfile.read(length) or b'{}')

def stats():
    with connect() as db:
        articles = db.execute('SELECT COUNT(*) FROM articles').fetchone()[0]
        revisions = db.execute('SELECT COUNT(*) FROM revisions').fetchone()[0]
        reviews = db.execute('SELECT COUNT(*) FROM reviews').fetchone()[0]
        hours = db.execute('''SELECT substr(first_seen,1,13) as hour,COUNT(*) as count
                             FROM articles GROUP BY hour ORDER BY hour DESC LIMIT 24''').fetchall()
    with LOCK:
        return {'articles': articles, 'revisions': revisions, 'reviews': reviews,
                'running': RUNNING, 'last': dict(LAST),
                'activity': [dict(x) for x in reversed(hours)], 'topics': list(TOPICS)}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        if os.environ.get('NW_QUIET') != '1': super().log_message(fmt, *args)
    def reply(self, data, status=200):
        content = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)
    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path == '/':
            data = PAGE.read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if parsed.path == '/api/health': return self.reply({'ok':True,'version':'0.2-one-paste'})
        if parsed.path == '/api/status': return self.reply(stats())
        if parsed.path == '/api/case':
            return self.reply({'name':'Katie Zacharia','case':'NW-001','date':'2026-10-16',
                               'sources':SOURCES,'claims':CLAIMS,
                               'limitations':'Curated source sample. Not exhaustive or representative of all media.'})
        if parsed.path == '/api/news':
            query = urllib.parse.parse_qs(parsed.query)
            topic = (query.get('topic') or [''])[0]
            search = (query.get('search') or [''])[0]
            statement = 'SELECT * FROM articles WHERE 1=1'
            args = []
            if topic and topic in TOPICS:
                statement += ' AND topic=?'; args.append(topic)
            if search:
                statement += ' AND (title LIKE ? OR publisher LIKE ?)'
                args.extend(['%%%s%%'%search, '%%%s%%'%search])
            statement += ' ORDER BY COALESCE(published,first_seen) DESC LIMIT 150'
            with connect() as db:
                rows = [dict(row) for row in db.execute(statement,args)]
            return self.reply({'articles': rows})
        if parsed.path == '/api/revisions':
            with connect() as db:
                rows = [dict(row) for row in db.execute('SELECT * FROM revisions ORDER BY observed_at DESC LIMIT 80')]
            return self.reply({'revisions': rows})
        if parsed.path == '/api/reviews':
            with connect() as db:
                rows = [dict(row) for row in db.execute('SELECT * FROM reviews ORDER BY reviewed_at DESC LIMIT 60')]
            return self.reply({'reviews': rows})
        if parsed.path == '/api/export':
            with connect() as db:
                reviews = [dict(row) for row in db.execute('SELECT * FROM reviews ORDER BY id')]
                revisions = [dict(row) for row in db.execute('SELECT * FROM revisions ORDER BY id')]
            return self.reply({'exported_at':now(),'case':'NW-001','sources':SOURCES,
                               'claims':CLAIMS,'reviews':reviews,'revisions':revisions,
                               'stats':stats()})
        return self.reply({'error':'Not found'}, 404)
    def do_POST(self):
        global RUNNING
        if self.path == '/api/collect':
            with LOCK:
                if RUNNING: return self.reply({'started':False,'message':'Collection already running'})
                RUNNING = True
            threading.Thread(target=collect, daemon=True).start()
            return self.reply({'started':True})
        if self.path == '/api/review':
            try:
                record = read_payload(self)
                cid = str(record.get('claim_id','')).strip()
                status = str(record.get('conclusion','')).strip()[:100]
                note = str(record.get('notes','')).strip()[:2500]
                if cid not in {x['id'] for x in CLAIMS} or not status:
                    return self.reply({'error':'Invalid claim or conclusion'},400)
                with connect() as db:
                    db.execute('INSERT INTO reviews (claim_id,conclusion,notes,reviewed_at) VALUES (?,?,?,?)',
                               (cid,status,note,now()))
                return self.reply({'saved':True})
            except (ValueError, json.JSONDecodeError) as exc:
                return self.reply({'error':str(exc)},400)
        return self.reply({'error':'Not found'},404)

def serve():
    init()
    server = None
    for port in range(8877,8900):
        try:
            server = ThreadingHTTPServer(('127.0.0.1',port),Handler)
            break
        except OSError:
            continue
    if not server: raise RuntimeError('No available Narrative Wave port (8877-8899)')
    url = 'http://127.0.0.1:%s' % server.server_port
    print('\nNARRATIVE WAVE STARTED: '+url+'\nData: '+str(DB)+'\nPress Ctrl+C to stop.\n', flush=True)
    if os.environ.get('NW_NO_BROWSER') != '1':
        if sys.platform == 'darwin':
            subprocess.Popen(['open',url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else: webbrowser.open(url)
    try: server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt: pass
    finally: server.server_close()

if __name__ == '__main__': serve()
NW_PYTHON
cat > "$APP/standalone/index.html" <<'NW_HTML'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Narrative Wave | Narrative Forensics</title>
<style>
:root{color-scheme:dark;--bg:#0b1220;--panel:#111e30;--border:#24374d;--blue:#65b1ff;--muted:#93a8be;--ink:#eaf4ff;--gold:#f7c97a}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 70% 0%,#132941 0%,var(--bg) 55%);font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:var(--ink)}main{max-width:1250px;margin:auto;padding:22px}header{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:28px;flex-wrap:wrap}.brand{font-size:24px;letter-spacing:.12em;font-weight:850;color:white}.brand b{color:var(--blue)}.subtitle,.muted,small{color:var(--muted)}.status{background:#102638;border:1px solid #295475;border-radius:99px;padding:7px 12px;color:#a8d7ff}h1{font-size:32px;line-height:1.17;letter-spacing:-.03em;margin:10px 0}h2{font-size:18px;margin:0 0 12px}p{margin:6px 0 12px}.lead{font-size:17px;max-width:850px}.kicker{color:var(--gold);font-size:11px;letter-spacing:.14em;font-weight:800}.grid{display:grid;grid-template-columns:1.05fr .95fr;gap:16px}.card,.tile{background:rgba(17,30,48,.92);border:1px solid var(--border);border-radius:15px;padding:18px}.card{margin-top:18px}.tiles{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:22px 0}.tile strong{font-size:29px;display:block}.tile span{color:var(--muted);font-size:12px}.row{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap}.pill{font-size:11px;letter-spacing:.02em;color:var(--blue);border:1px solid #315679;padding:2px 8px;border-radius:99px}.source,.claim,.feed{padding:13px 0;border-top:1px solid var(--border)}a{color:#92c8ff;text-decoration:none}a:hover{text-decoration:underline}.publisher{color:var(--gold);font-size:12px}.heading{font-size:14px;font-weight:700;margin:5px 0}.basis{font-size:12px;color:var(--muted)}button,select,input,textarea{font:inherit;background:#18283b;color:var(--ink);border:1px solid #35506b;border-radius:8px;padding:9px 11px}button{cursor:pointer;background:#245b85;border-color:#4b90c1;font-weight:700}button:hover{background:#3275a7}input{min-width:180px}textarea{width:100%;min-height:65px}.tools{display:flex;flex-wrap:wrap;gap:8px;align-items:center}#bars{display:flex;align-items:end;gap:12px;height:190px;border-bottom:1px solid #44617d;padding:10px 0 0}.barcol{flex:1;display:flex;flex-direction:column;align-items:center;gap:7px;justify-content:end;min-width:0}.bar{width:min(45px,100%);min-height:3px;background:linear-gradient(#65b1ff,#235eaa);border-radius:7px 7px 0 0}.barcol small{font-size:11px;text-align:center;white-space:normal}.barcol b{font-size:13px}.empty{color:var(--muted);padding:14px 0}.info{border-left:3px solid var(--gold);padding:9px 12px;background:#272536;margin-top:10px}.tag{font-size:11px;background:#24384a;border-radius:5px;padding:4px 6px;color:#c7d8ef}.sectionlabel{font-size:12px;color:var(--muted);margin-top:12px}.review{display:grid;gap:9px}.success{color:#8ed8a8}.warning{color:#ffc97d}.foot{text-align:center;color:var(--muted);padding:25px 0 14px}@media(max-width:850px){.grid,.tiles{grid-template-columns:1fr 1fr}.card{grid-column:1/-1}}@media(max-width:540px){.grid,.tiles{grid-template-columns:1fr}h1{font-size:26px}main{padding:13px}}
</style></head><body><main><header><div><div class="brand">NARRATIVE <b>WAVE</b></div><div class="subtitle">Evidence-first media intelligence | Local-first</div></div><div class="status" id="status">● Local dashboard</div></header>
<section><div class="kicker">INVESTIGATION NW-001 · OCT 16, 2026</div><h1>Was Katie Zacharia fired,<br>or did she leave voluntarily?</h1><p class="lead">Compare how outlets characterized her departure against what the reporting actually establishes. This dashboard does not assume that disagreement proves deception or coordination.</p><div class="info"><b>Working finding:</b> Departure reported by multiple outlets. The mechanism is differently characterized and must be attributed precisely. A public statement advising reconsideration does not, by itself, establish resignation or dismissal.</div></section>
<div class="tiles"><div class="tile"><strong id="n_sources">5</strong><span>Selected source reports</span></div><div class="tile"><strong id="n_articles">0</strong><span>Observed feed articles</span></div><div class="tile"><strong id="n_revisions">0</strong><span>Captured headline revisions</span></div><div class="tile"><strong id="n_reviews">0</strong><span>Saved human reviews</span></div></div>
<div class="grid"><section class="card"><div class="row"><h2>Headline-framing distribution</h2><span class="pill">Curated sample, not all media</span></div><div id="bars"></div><p class="sectionlabel">Counts show wording in five selected reports, not verified motivations or total industry share. Click sources to inspect attribution.</p></section><section class="card"><h2>Evidence ledger</h2><div id="claims"></div></section></div>
<div class="grid"><section class="card"><div class="row"><h2>Original report trail</h2><span class="pill">Source links</span></div><div id="sources"></div></section><section class="card"><h2>Record a human review</h2><div class="review"><select id="claim_select"></select><select id="conclusion"><option>Needs more evidence</option><option>Support documented</option><option>Contradictory evidence</option><option>Attribution corrected</option></select><textarea id="notes" placeholder="Evidence, notes, URLs, limitations..."></textarea><button onclick="saveReview()">Save review locally</button><p id="review_status" class="basis"></p></div><h2>Recorded reviews</h2><div id="reviews"></div></section></div>
<section class="card"><div class="row"><h2>Live news industry radar</h2><div class="tools"><button id="collect" onclick="collectNews()">Collect RSS feeds</button><button onclick="exportCase()">Export investigation JSON</button></div></div><p class="basis">Feeds from Google News discovery and BBC. AP, Reuters, and other paid wire feeds need licensed direct integration; Google News entries are discovery records, not the original articles. Collection is manual for this version.</p><div class="tools"><select id="topic" onchange="loadNews()"><option value="">All topics</option></select><input id="search" oninput="scheduleNews()" placeholder="Find outlets or headlines"></div><p id="collect_status" class="sectionlabel">No collection initiated yet.</p><div id="news"></div></section>
<section class="card"><h2>Revision history</h2><p class="basis">Headline changes are detected only when the same URL is observed on separate collections. It cannot reconstruct earlier unseen revisions.</p><div id="revisions" class="empty">No observations yet.</div></section>
<div class="foot">Narrative Wave v0.2 · Independent evidence before assertions · All application data stays on this Mac</div></main>
<script>
let caseData=null, timer=null;
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function api(url,opts){let r=await fetch(url,opts);if(!r.ok)throw Error('HTTP '+r.status);return r.json()}
function sourceView(s){return `<div class="source"><div class="row"><span class="publisher">${esc(s.publisher)}</span><span class="tag">${esc(s.frame)}</span></div><div class="heading"><a href="${esc(s.url)}" target="_blank" rel="noopener noreferrer">${esc(s.headline)} ↗</a></div><div class="basis">${esc(s.basis)}</div></div>`}
function chart(sources){let counts={};sources.forEach(s=>counts[s.frame]=(counts[s.frame]||0)+1);let max=Math.max(...Object.values(counts));document.getElementById('bars').innerHTML=Object.entries(counts).map(([name,num])=>`<div class="barcol"><b>${num}</b><div class="bar" style="height:${Math.max(12,Math.round(num/max*125))}px"></div><small>${esc(name)}</small></div>`).join('')}
async function loadCase(){let d=await api('/api/case');caseData=d;document.getElementById('n_sources').textContent=d.sources.length;document.getElementById('sources').innerHTML=d.sources.map(sourceView).join('');document.getElementById('claims').innerHTML=d.claims.map(c=>`<div class="claim"><div class="row"><b>${esc(c.id)} · ${esc(c.claim)}</b></div><span class="tag">${esc(c.status)}</span><p class="basis">${esc(c.detail)}</p></div>`).join('');document.getElementById('claim_select').innerHTML=d.claims.map(c=>`<option value="${esc(c.id)}">${esc(c.id)} — ${esc(c.claim)}</option>`).join('');chart(d.sources)}
async function loadStatus(){let d=await api('/api/status');for(let [i,key] of [['n_articles','articles'],['n_revisions','revisions'],['n_reviews','reviews']])document.getElementById(i).textContent=d[key];document.getElementById('status').textContent=d.running?'● Collecting live feeds':'● Local service online';let sel=document.getElementById('topic');if(sel.options.length===1)sel.innerHTML+=[...d.topics].map(s=>`<option value="${esc(s)}">${esc(s)}</option>`).join('');if(d.last.at){document.getElementById('collect_status').textContent='Last run '+d.last.at.replace('T',' ')+' · +'+d.last.added+' items · '+d.last.revised+' revisions'+(d.last.errors.length?' · '+d.last.errors.length+' feed errors':'');if(!d.running)document.getElementById('collect').disabled=false;}return d}
async function loadNews(){let topic=document.getElementById('topic').value, search=document.getElementById('search').value;let data=await api('/api/news?'+new URLSearchParams({topic,search}));document.getElementById('news').innerHTML=data.articles.length?data.articles.slice(0,75).map(a=>`<div class="feed"><div class="row"><span class="publisher">${esc(a.publisher)}</span><span class="tag">${esc(a.topic)}</span></div><div class="heading"><a target="_blank" rel="noopener noreferrer" href="${esc(a.url)}">${esc(a.title)} ↗</a></div><div class="basis">Published: ${esc(a.published||'unavailable')} · First observed: ${esc(a.first_seen)}</div></div>`).join(''):'<p class="empty">No local observations yet. Select Collect RSS feeds to begin.</p>'}
async function loadReviews(){let d=await api('/api/reviews');document.getElementById('reviews').innerHTML=d.reviews.length?d.reviews.map(x=>`<div class="claim"><b>${esc(x.claim_id)} · ${esc(x.conclusion)}</b><p class="basis">${esc(x.notes)} · ${esc(x.reviewed_at)}</p></div>`).join(''):'<p class="empty">No reviews recorded.</p>'}
async function loadRevisions(){let d=await api('/api/revisions');document.getElementById('revisions').innerHTML=d.revisions.length?d.revisions.map(x=>`<div class="claim"><div class="basis">${esc(x.observed_at)}</div><div>Previous: ${esc(x.old_title)}</div><div>Observed: ${esc(x.new_title)}</div></div>`).join(''):'<p class="empty">No changes observed on repeat collections.</p>'}
function scheduleNews(){clearTimeout(timer);timer=setTimeout(loadNews,320)}
async function collectNews(){document.getElementById('collect').disabled=true;await api('/api/collect',{method:'POST'});document.getElementById('collect_status').textContent='Collecting... feeds can take a few seconds.';let attempts=0;let id=setInterval(async()=>{try{let d=await loadStatus();if(!d.running||++attempts>30){clearInterval(id);await Promise.all([loadNews(),loadRevisions()])}}catch(e){clearInterval(id);console.error(e)}},1500)}
async function saveReview(){let payload={claim_id:document.getElementById('claim_select').value,conclusion:document.getElementById('conclusion').value,notes:document.getElementById('notes').value};try{await api('/api/review',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});document.getElementById('review_status').textContent='Review saved to the local evidence database.';document.getElementById('notes').value='';await Promise.all([loadReviews(),loadStatus()])}catch(e){document.getElementById('review_status').textContent='Save failed: '+e.message}}
async function exportCase(){let d=await api('/api/export');let a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(d,null,2)],{type:'application/json'}));a.download='Narrative-Wave-NW-001-evidence.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),2000)}
Promise.all([loadCase(),loadStatus(),loadNews(),loadReviews(),loadRevisions()]).catch(e=>{document.getElementById('status').textContent='Error: '+e.message});
</script></body></html>
NW_HTML
cat > "$APP/START-NARRATIVE-WAVE.command" <<EOF
#!/bin/bash
set -euo pipefail
cd "\$HOME/Applications/Narrative-Wave"
exec "$PYTHON" -u "\$HOME/Applications/Narrative-Wave/standalone/app.py"
EOF
chmod +x "$APP/START-NARRATIVE-WAVE.command"
printf 'NARRATIVE_WAVE_ONE_PASTE_V02\n' > "$APP/.narrative-wave-one-paste"
if [[ ! -f "$APP/.narrative-wave-install" ]]; then
  printf 'NARRATIVE_WAVE_INSTALL_V1' > "$APP/.narrative-wave-install"
fi
if [[ -d "$HOME/Desktop" && ! -e "$HOME/Desktop/Narrative Wave.command" ]]; then
  ln -s "$APP/START-NARRATIVE-WAVE.command" "$HOME/Desktop/Narrative Wave.command" || true
fi
"$PYTHON" -m py_compile "$APP/standalone/app.py"
printf '\nINSTALLATION COMPLETE - No Downloads or ZIP required.\nLocation: %s\n' "$APP"
printf 'Starting local dashboard...\n'
exec "$APP/START-NARRATIVE-WAVE.command"