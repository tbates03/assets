#!/bin/bash
# Narrative Wave: patch the actual standalone installation, not the older src/ package.
set -euo pipefail
APP="$HOME/Applications/Narrative-Wave"
PAGE="$APP/standalone/index.html"
if [[ ! -f "$PAGE" || ! -f "$APP/standalone/app.py" ]]; then
  printf 'Could not find the standalone installation at: %s\n' "$APP" >&2
  if [[ -d "$APP" ]]; then ls -la "$APP" >&2; fi
  printf 'No files were changed.\n' >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3 was not found in this Terminal. No files were changed.' >&2
  exit 1
fi
export NW_PATCH_PAGE="$PAGE"
python3 - <<'PY'
from pathlib import Path
from datetime import datetime
import os, shutil
page=Path(os.environ['NW_PATCH_PAGE'])
original=page.read_text(encoding='utf-8')
if 'id="nw-truth-gap-panel"' in original and 'id="nw-hype-cycle"' in original:
    print('Truth Gap and Hype Cycle are already installed; no duplicate changes made.')
    raise SystemExit(0)
if not all(s in original for s in ('<div class="tiles">','</style>','</body></html>','/api/case')):
    raise SystemExit('Unrecognized standalone dashboard format; no changes made.')

css=r'''
/* Narrative Wave v0.3: evidence-based truth gap and topic hype cycle */
.nw-section{border:1px solid #34526a;background:linear-gradient(145deg,#14263b,#0e1c2d);border-radius:15px;padding:22px;margin:21px 0}
.nw-heading{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap}
.nw-heading h2{font-size:23px;margin:3px 0 6px}
.nw-kicker{color:#f7c97a;font-size:10px;font-weight:800;letter-spacing:1.5px;text-transform:uppercase}
.nw-small{color:#a9bfd1;font-size:12px;line-height:1.55}
.nw-gap-grid{display:grid;grid-template-columns:minmax(0,1.1fr) minmax(290px,.9fr);gap:16px;margin-top:17px}
.nw-claim-list{display:grid;gap:8px}
.nw-claim-btn{display:block;width:100%;text-align:left;padding:13px;border:1px solid #2e4357;background:#14283b;border-radius:10px;color:#edf4ff}
.nw-claim-btn:hover,.nw-claim-btn[aria-pressed="true"]{background:#1d3b4f;border-color:#73d6bd}
.nw-claim-row{display:flex;gap:12px;align-items:center;justify-content:space-between}
.nw-claim-row b{font-size:12px;font-weight:700}
.nw-level{white-space:nowrap;color:#c4d3df;font-size:10px}
.nw-band{display:flex;height:9px;overflow:hidden;background:repeating-linear-gradient(135deg,#875040,#875040 7px,#50353c 7px,#50353c 14px);border-radius:12px;margin-top:10px}
.nw-verified{background:linear-gradient(90deg,#3fae9a,#94ead5);height:100%;transition:width .22s ease}
.nw-explain{border:1px solid #38566a;background:#0e1d2e;padding:16px;border-radius:12px}
.nw-explain h3{font-size:17px;margin:7px 0 12px}
.nw-block{margin:11px 0;padding-top:10px;border-top:1px solid #23394e}
.nw-block:first-of-type{border:0;padding-top:0}
.nw-block b{display:block;color:#f4c684;font-size:11px;text-transform:uppercase;letter-spacing:.07em;margin-bottom:4px}
.nw-block p{margin:0;color:#c1d0da;font-size:12px}
.nw-sources{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0 0}
.nw-sources a{font-size:11px;padding:6px 8px;border-radius:8px;border:1px solid #355673;color:#a8d5f6}
.nw-rule{margin-top:14px;border-top:1px solid #2a4357;padding-top:11px;color:#88a3b7;font-size:11px}
.nw-level-key{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.nw-level-key span{border:1px solid #31546b;border-radius:7px;padding:6px 9px;background:#12283b;color:#acc8d9;font-size:11px}
.nw-wave-area{height:255px;margin:17px 0 5px}
.nw-wave-area svg{display:block;width:100%;height:100%}
.nw-legend{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:9px 0}
.nw-dot{display:inline-block;height:9px;width:9px;margin-right:5px;border-radius:3px}
.nw-axis{fill:#9aafc0;font-size:10px}
.nw-gridline{stroke:#33495e;stroke-dasharray:3 5}
.nw-highlight{color:#ffdb9c}
@media(max-width:850px){.nw-gap-grid{grid-template-columns:1fr}.nw-section{padding:16px}.nw-wave-area{height:215px}}
'''

markup=r'''
<section class="nw-section" id="nw-truth-gap-panel" aria-label="Truth Gap evidence inspection">
  <div class="nw-heading"><div><div class="nw-kicker">Claim vs. verifiable evidence</div><h2>The Truth Gap</h2></div><span class="pill">NOT a probability of truth</span></div>
  <p class="nw-small">A visual distance between what a claim asserts and what available sources independently establish. Click any claim to see where the evidence ends, what conflicts, and what would resolve it.</p>
  <div class="nw-gap-grid"><div id="nw-truth-rows" class="nw-claim-list">Loading evidence…</div><div id="nw-truth-details" class="nw-explain">Inspect a claim to trace its basis.</div></div>
  <div class="nw-level-key"><span><span class="nw-dot" style="background:#61cdb6"></span>Verified evidence tier</span><span><span class="nw-dot" style="background:#875040"></span>Unresolved evidence gap</span></div>
  <div class="nw-rule">Rubric: 0 = no confirming evidence in this sample · 1 = attributed reporting · 2 = direct/on-record reporting or multiple corroborating accounts · 3 = independently verified primary documentation. Tiers measure evidence completeness, not whether a person is truthful. Missing evidence does not prove a claim false. This is a curated sample, not every available record.</div>
</section>
<section class="nw-section" id="nw-hype-cycle" aria-label="Narrative hype cycle by framing">
  <div class="nw-heading"><div><div class="nw-kicker">Coverage velocity and narrative scopes</div><h2>Hype Cycle: one story, competing frames</h2></div><span class="pill">OBSERVED RSS SAMPLE</span></div>
  <p class="nw-small">White line = volume of collected reporting over time. Colored segments = how headlines characterize the same event. The pattern can reveal amplification, but it does not establish editorial intent or whether a claim is true.</p>
  <div id="nw-hype-legend" class="nw-legend"></div><div id="nw-hype-graph" class="nw-wave-area"><div class="empty">Checking collected case articles…</div></div>
  <p id="nw-hype-notes" class="nw-small">Article timestamps are provided by news feeds and may reflect updates rather than first publication. Headlines are classified by deterministic keywords.</p>
</section>
'''

js=r'''
<script id="nw-truth-gap-script">
(()=>{'use strict';
const $=id=>document.getElementById(id);
const safe=s=>String(s??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
const tiers=['No confirming evidence in this sample','Attributed reporting','Reported corroboration / on-record statement','Independently verified primary record'];
const audits=[
 {id:'C1',title:'The press secretary is leaving the role',tier:2,status:'Reported departure',support:'AP and NPR/KPBS report that the role is ending; NPR attributes the description to a White House official.',counter:'Different accounts use different terms for the mechanism, but those differences do not themselves contradict the departure.',missing:'A direct formal personnel record or statement would close the remaining documentary gap.',refs:['nw001','nw002']},
 {id:'C2',title:'She was fired or dismissed',tier:1,status:'Mechanism not independently established',support:'The Guardian and UPI report the firing characterization, citing reported or unnamed sources.',counter:'NPR/KPBS reports a White House official describing her as “transitioning out.” That phrasing is not proof she resigned voluntarily, nor proof she was not dismissed.',missing:'A direct on-record confirmation, contemporaneous personnel document, or firsthand verified account of the employment decision.',refs:['nw003','nw005','nw002']},
 {id:'C3',title:'She voluntarily resigned',tier:0,status:'Voluntary choice not established',support:'A transition was reported, but the wording alone does not establish who initiated the departure.',counter:'Firing reports present another explanation; neither has been reconciled with independently verifiable employment records in this sample.',missing:'Her own direct confirmation, a resignation letter, or an authorized personnel record.',refs:['nw002','nw003']},
 {id:'C4',title:'The president publicly advised reconsideration',tier:2,status:'Publicly attributed account',support:'CBS reports the president’s public comments about whether she should reconsider the role.',counter:'Advice to reconsider does not by itself show that a dismissal occurred or that she resigned.',missing:'Review and archive the original unedited remarks or transcript, including full context.',refs:['nw004']},
 {id:'C5',title:'Outlets coordinated a knowingly false story',tier:0,status:'Not demonstrated in this sample',support:'No direct evidence of coordinated editorial action is included in the selected records.',counter:'Shared sources, wire distribution, independent reporting, and ordinary headline convergence are plausible alternative explanations.',missing:'Provenance establishing deliberate coordination, shared instructions, or documented knowing falsity. This is a research hypothesis, not a documented headline.',refs:['nw001','nw003','nw005']}
];
let selected='C2';let sourceMap={};
function drawTruth(){
  $('nw-truth-rows').innerHTML=audits.map(a=>`<button class="nw-claim-btn" data-nw-claim="${a.id}" aria-pressed="${a.id===selected}"><div class="nw-claim-row"><b>${safe(a.id+' · '+a.title)}</b><span class="nw-level">Tier ${a.tier}/3</span></div><div class="nw-band" aria-hidden="true"><div class="nw-verified" style="width:${a.tier/3*100}%"></div></div></button>`).join('');
  const a=audits.find(x=>x.id===selected)||audits[0];
  const refs=a.refs.map(id=>sourceMap[id]).filter(Boolean);
  $('nw-truth-details').innerHTML=`<div class="nw-kicker">${safe(a.status)}</div><h3>${safe(a.title)}</h3><div class="nw-block"><b>What the available record supports</b><p>${safe(a.support)}</p></div><div class="nw-block"><b>Conflicting or limiting evidence</b><p>${safe(a.counter)}</p></div><div class="nw-block"><b>What would close the gap?</b><p>${safe(a.missing)}</p></div><div class="nw-block"><b>Verification status</b><p>${safe(tiers[a.tier])}. Not an algorithmic true/false ruling.</p></div><div class="nw-sources">${refs.map(r=>`<a target="_blank" rel="noopener noreferrer" href="${safe(r.url)}">${safe(r.publisher)} ↗</a>`).join('')}</div>`;
}
function frame(t){let s=String(t||'').toLowerCase();if(/\b(fired|sacked|dismissed|terminated|ousted)\b/.test(s))return'fired';if(/\b(removed|pushed out|forced out)\b/.test(s))return'removed';if(/\b(transitioning|stepping down|resigned|resigns|resignation|leaving|steps down)\b/.test(s))return'leaving';if(/\b(reconsider|advised|urged|future)\b/.test(s))return'reconsider';return'other'}
const colors={fired:'#e99ca7',removed:'#edc184',leaving:'#74dac5',reconsider:'#b7adf4',other:'#729fda'};
const labels={fired:'Fired / dismissed',removed:'Removed',leaving:'Leaving / transition',reconsider:'Reconsideration',other:'Other'};
async function renderHype(){
  const root=$('nw-hype-graph');if(!root)return;
  const res=await fetch('/api/news?topic='+encodeURIComponent('Katie Zacharia'),{cache:'no-store'});
  if(!res.ok)throw Error('News API HTTP '+res.status);
  const d=await res.json();
  const rows=(d.articles||[]).filter(a=>a.published&&!Number.isNaN(Date.parse(a.published)));
  const bins=new Map();
  for(const a of rows){let dt=new Date(a.published);const step=Math.floor(dt.getUTCHours()/3)*3;const stamp=Date.UTC(dt.getUTCFullYear(),dt.getUTCMonth(),dt.getUTCDate(),step);let b=bins.get(stamp);if(!b){b={time:stamp,total:0,fired:0,removed:0,leaving:0,reconsider:0,other:0};bins.set(stamp,b)}b.total++;b[frame(a.title)]++}
  const points=Array.from(bins.values()).sort((a,b)=>a.time-b.time).slice(-15);
  const counted=points.reduce((n,b)=>n+b.total,0);
  const allFrames=['fired','removed','leaving','reconsider','other'];
  $('nw-hype-legend').innerHTML=allFrames.map(k=>`<span class="nw-small"><i class="nw-dot" style="background:${colors[k]}"></i>${labels[k]}</span>`).join('')+'<span class="nw-small"><i class="nw-dot" style="background:#ffffff"></i>Coverage volume</span>';
  if(!points.length){root.innerHTML='<div class="empty">No timestamped Katie Zacharia feed records yet. Use “Collect RSS feeds” to gather observed coverage. No trend will be invented.</div>';
   $('nw-hype-notes').textContent='Curated source reports lack comparable hourly publication timestamps, so they are not assigned invented times.';return}
  const W=920,H=240,left=45,right=20,top=23,bottom=48,plotW=W-left-right,plotH=H-top-bottom;
  const max=Math.max(1,...points.map(p=>p.total));const x=i=>left+(points.length===1?plotW/2:i*plotW/(points.length-1));const y=v=>top+plotH-v/max*plotH;
  const width=Math.min(43,plotW/Math.max(2,points.length)*.55);
  let svg=`<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Observed 3-hour news coverage volumes and headline frame composition">`;
  for(let j=0;j<=4;j++){let v=max*j/4, yy=y(v);svg+=`<line class="nw-gridline" x1="${left}" x2="${W-right}" y1="${yy}" y2="${yy}"/><text class="nw-axis" x="${left-8}" y="${yy+4}" text-anchor="end">${Number(v.toFixed(1))}</text>`}
  for(let i=0;i<points.length;i++){
   const p=points[i];let offset=0;
   for(const f of allFrames){if(!p[f])continue;const h=p[f]/max*plotH;svg+=`<rect x="${x(i)-width/2}" y="${y(offset+p[f])}" width="${width}" height="${h}" fill="${colors[f]}"><title>${safe(labels[f])}: ${p[f]} headlines</title></rect>`;offset+=p[f]}
   if(points.length<=6||i%2===0||i===points.length-1){const t=new Date(p.time).toLocaleString('en-US',{month:'short',day:'numeric',hour:'numeric',timeZone:'UTC'});svg+=`<text class="nw-axis" x="${x(i)}" y="${H-21}" text-anchor="middle">${safe(t)}Z</text>`}
  }
  svg+='<polyline points="'+points.map((p,i)=>x(i)+','+y(p.total)).join(' ')+'" fill="none" stroke="#f4f8ff" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>';
  for(let i=0;i<points.length;i++)svg+=`<circle cx="${x(i)}" cy="${y(points[i].total)}" r="3.5" fill="#ffffff"><title>${points[i].total} sampled records</title></circle>`;
  root.innerHTML=svg+'</svg>';
  $('nw-hype-notes').innerHTML=`${counted} timestamped case articles represented across ${points.length} observed three-hour publication buckets (UTC). ${points.length<2?'<span class="nw-highlight">Only one bucket: a rise or fall cannot be established yet.</span> ':'These counts are from sampled RSS metadata, not an industry census.'} Publication and update timestamps may differ.`;
}
async function start(){try{const r=await fetch('/api/case',{cache:'no-store'});if(!r.ok)throw Error('Case API HTTP '+r.status);let d=await r.json();sourceMap=Object.fromEntries((d.sources||[]).map(s=>[s.id,s]));drawTruth();await renderHype()}catch(e){$('nw-truth-rows').textContent='Evidence unavailable: '+e.message;$('nw-hype-graph').textContent='Hype trend unavailable: '+e.message}}
$('nw-truth-rows').addEventListener('click',e=>{const button=e.target.closest('[data-nw-claim]');if(!button)return;selected=button.dataset.nwClaim;drawTruth()});
start();setInterval(()=>renderHype().catch(console.warn),30000);
})();
</script>
'''

after=original.replace('</style>',css+'</style>',1).replace('<div class="tiles">',markup+'<div class="tiles">',1).replace('</body></html>',js+'</body></html>',1)
if after == original: raise SystemExit('Unexpected missing insertion point: no files changed.')
backup=page.with_name('index.html.before-truth-gap-'+datetime.now().strftime('%Y%m%d-%H%M%S')+'.bak')
shutil.copy2(page,backup)
tmp=page.with_suffix('.html.update')
tmp.write_text(after,encoding='utf-8')
tmp.replace(page)
print('Updated:',page)
print('Backup:',backup)
print('Local research database and original API were not changed.')
PY

# Restart only the exact standalone process launched from this installation.
for pid in $(pgrep -f "$APP/standalone/app.py" 2>/dev/null || true); do
  cmdline="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  case "$cmdline" in
    *"$APP/standalone/app.py"*) kill -TERM "$pid" 2>/dev/null || true ;;
  esac
done
sleep 2
nohup /bin/bash "$APP/START-NARRATIVE-WAVE.command" >"$APP/data/narrative-wave-truth-gap.log" 2>&1 </dev/null &
sleep 3
printf '\nUPDATE COMPLETE - Truth Gap and Hype Cycle added.\n'
printf 'App: %s\n' "$APP"
printf 'Dashboard: http://127.0.0.1:8877 (or next available port)\n'
printf 'Existing evidence and collected articles have been preserved.\n'