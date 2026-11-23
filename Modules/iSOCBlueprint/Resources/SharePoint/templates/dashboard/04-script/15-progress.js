  // ---- progress (change across runs) ----
  // Each export is a snapshot: the date range re-scopes its activity, but
  // posture (findings, criteria, rules, coverage) is as it was on the day.
  // The build writes a progress record for every run (M.progress) and the
  // history of them beside the dashboard (progress-history.json: earlier
  // day folders' records locally, the publisher's on the site). This view
  // compares two of those runs, chosen by the top bar's date range: the
  // run kept at its end against the run kept at its start, drawn in the
  // dashboard's own parts (the Overview's tiles, the maturity view's area
  // bars, the Insights cards).
  (function(){
    const board=document.getElementById('progressBoard');
    // The sentence naming the runs compared, shown in the header.
    let ctxHtml='';
    HERO_CTX.progress=()=>ctxHtml;
    const setCtx=h=>{ ctxHtml=h; if(curView==='progress') paintHeroCtx(); };
    if(!board) return;
    const latest=M.progress||null;
    let cur=latest;
    if(!cur){
      setCtx('This snapshot was built before progress tracking. Each run from now on adds a record, and this view compares them.');
      return;
    }
    // key, label, which way is better ('up', 'down' or '' for neither), format
    const METRICS=[
      ['maturityScore','Maturity score','up','score'],
      ['criteriaMet','Maturity criteria met','up'],
      ['criteriaGap','Maturity criteria with a gap','down'],
      ['findings','Findings','down'],
      ['findingsCritical','Critical findings','down'],
      ['findingsWarning','Warning findings','down'],
      ['rulesEnabled','Analytics rules enabled','up'],
      ['customDetections','Custom detections enabled','up'],
      ['techniquesCovered','ATT&CK techniques covered','up'],
      ['tacticsCovered','ATT&CK tactics covered','up'],
      ['connectors','Data connectors','up'],
      ['tablesIngesting','Tables ingesting',''],
      ['uncoveredTables','Ingesting tables no detection reads','down'],
      ['uncoveredGb','GB no detection reads','down','gb'],
      ['dailyGb','Billable GB a day','','gb'],
      ['monthlyCost','Estimated monthly cost','','money'],
      ['openIncidents','Open incidents','down'],
      ['mttrMinutes','Mean time to resolve','down','minutes']
    ];
    const MK={}; METRICS.forEach(m=>{ MK[m[0]]=m; });
    // The headline tiles, in the Overview's style.
    const TILES=[['maturityScore',ICON.gauge],['findings',ICON.shieldAlert],['findingsCritical',ICON.flag],['rulesEnabled',ICON.bolt],
      ['techniquesCovered',ICON.crosshair],['uncoveredGb',ICON.database],['openIncidents',ICON.pulse],['monthlyCost',ICON.coins]];
    const TRENDS=[['maturityScore','indigo'],['findings','amber'],['rulesEnabled','brand'],['techniquesCovered','teal'],['uncoveredGb','violet'],['monthlyCost','cyan']];
    const SHOW=8;
    let entries=[latest], viewRuns=[latest];
    const day=d=>new Date(d+'T00:00:00Z');
    const daysBetween=(a,b)=>Math.round((day(b)-day(a))/86400000);
    const short=d=>fmtDate(d,{year:false});
    const long=d=>fmtDate(d);
    const andList=a=>a.length<2? a.join('') : a.slice(0,-1).join(', ')+' and '+a[a.length-1];
    // The runs the date range compares: the latest kept on or before its
    // last day, against the latest kept on or before its first day (or,
    // when none is, the earliest inside it); one day alone compares that
    // day's run with the one before. Without a calendar (a model with no
    // daily series), the snapshot's run against the previous one.
    const dayT=d=>Date.parse(d+'T00:00:00Z');
    function chooseRuns(){
      const runs=entries.slice().sort((a,b)=>a.date<b.date?-1:1);
      if(WIN.endT==null){ const i=runs.indexOf(latest); return {end:latest, base:i>0? runs[i-1] : null}; }
      const end=runs.filter(r=>dayT(r.date)<=WIN.endT).pop()||null;
      if(!end) return {end:null, base:null};
      const before=runs.filter(r=>r.date<end.date);
      return {end, base:before.filter(r=>dayT(r.date)<=WIN.startT).pop() || before.find(r=>dayT(r.date)>=WIN.startT) || null};
    }
    const mv=(e,k)=>{ const v=e&&e.metrics? e.metrics[k] : null; return v==null||v===''? null : +v; };
    const fmtVal=(v,f)=>{
      if(v==null) return 'n/a';
      if(f==='score') return (+v).toFixed(2);
      if(f==='gb') return fmtN(v)+' GB';
      if(f==='money') return esc(fmtMoney(cur.currency,v));
      if(f==='minutes') return v<60? Math.round(v)+' min' : v<1440? (v/60).toFixed(1)+' hours' : (v/1440).toFixed(1)+' days';
      return (+v).toLocaleString('en-GB');
    };
    const fmtDelta=(a,b,better,f)=>{
      if(a==null||b==null) return '<span class="pg-same">n/a</span>';
      const d=b-a; if(Math.abs(d)<1e-9) return '<span class="pg-same">no change</span>';
      const cls=!better? 'pg-same' : (d>0)===(better==='up')? 'pg-good' : 'pg-bad';
      const mag=f==='score'? Math.abs(d).toFixed(2) : f==='money'? fmtMoney(cur.currency,Math.abs(d)) : f==='gb'? fmtN(Math.abs(d))+' GB' : f==='minutes'? fmtVal(Math.abs(d),'minutes') : Math.abs(d).toLocaleString('en-GB');
      return '<span class="'+cls+'">'+(d>0?'&#9650; ':'&#9660; ')+esc(mag)+'</span>';
    };
    const diff=(a,b)=>{ const A=new Set(a||[]), B=new Set(b||[]); return {added:[...B].filter(x=>!A.has(x)).sort(), removed:[...A].filter(x=>!B.has(x)).sort()}; };
    const techName={}; ((M.attack&&M.attack.techniques)||[]).forEach(t=>{ techName[t.id]=t.name; });
    const listedFindings=new Set(((M.findings&&M.findings.items)||[]).map(f=>f.id));
    const link=(cls,data,text)=>'<span class="pglink '+cls+'" tabindex="0" role="button" '+data+'>'+esc(text)+'</span>';

    // Tiles: each headline number now, and its change since the baseline.
    function tilesHtml(base){
      return '<div class="panel glance"><div class="phead"><div><h2>Progress at a glance</h2><p class="note">'+
        (base? 'Each figure on '+esc(long(cur.date))+', and how it has moved since '+esc(long(base.date))+'. Green is better and red is worse; cost and volume are neither.' : 'Each figure as this run collected it. The next run adds the comparison.')+
        ' Activity and cost are each run\'s own collected window ('+WIN.words(+cur.windowDays||WIN.collected)+' here), whatever dates are chosen at the top.'+
        '</p></div></div><div class="tiles pgtiles">'+TILES.filter(([k])=>mv(cur,k)!=null).map(([k,ic])=>{
          const m=MK[k], a=base? mv(base,k) : null, b=mv(cur,k);
          const s=!base? 'No earlier run yet' : a==null? 'Not captured on '+esc(short(base.date)) : fmtDelta(a,b,m[2],m[3])+' since '+esc(short(base.date));
          return '<div class="pill"><span class="kic">'+ic+'</span><div class="k">'+esc(m[1])+'</div><div class="v">'+fmtVal(b,m[3])+'</div><div class="s">'+s+'</div></div>';
        }).join('')+'</div></div>';
    }
    // Area bars, as the maturity view draws them: the bar is the score now
    // (amber below the target level) and the dashed marker the target, so
    // the markers line up as they do there. The change since the baseline is
    // a segment at the bar's end: green for what the area gained, red for
    // what it lost.
    function areasHtml(base){
      const target=M.maturity&&M.maturity.targetLevel;
      const pc=v=>(Math.max(0,Math.min(5,+v))/5*100).toFixed(1)+'%';
      const order=((M.maturity&&M.maturity.areas)||[]).filter(a=>cur.areas && cur.areas[a.id]!==undefined);
      if(!order.length) return '';
      const rows=order.map(a=>{
        const now=cur.areas[a.id], then=base&&base.areas? base.areas[a.id] : null;
        const s=now==null? 0 : +now, d=(now!=null&&then!=null)? +now-+then : null;
        const badge=!base? '<span class="matbadge">first run</span>' : d==null? '<span class="matbadge">not scored</span>' : Math.abs(d)<0.005? '<span class="matbadge">no change</span>' :
          '<span class="matbadge '+(d>0?'good':'worse')+'">'+(d>0?'&#9650; ':'&#9660; ')+Math.abs(d).toFixed(2)+'</span>';
        const below=now!=null&&target!=null&&a.level<target;
        return '<div class="abar" style="--c1:'+(below?'#d97706':'#2563eb')+';--c2:'+(below?'#f59e0b':'#6d5efc')+'"><div class="al"><b>'+esc(a.id)+'</b> '+esc(a.name)+'</div>'+
          '<div class="at"><div class="af" style="--w:'+(s/5*100).toFixed(1)+'%"></div>'+
          (d!=null&&Math.abs(d)>=0.005? '<div class="pgd '+(d>0?'up':'down')+'" style="left:'+pc(Math.min(+now,+then))+';width:'+pc(Math.abs(d))+'" title="'+esc(short(base.date))+': '+(+then).toFixed(2)+', now '+(+now).toFixed(2)+'"></div>' : '')+
          (target!=null? '<div class="am" style="--t:'+(target/5*100)+'%"></div>' : '')+'</div>'+
          '<div class="av">'+(now==null? 'n/a' : (+now).toFixed(2))+'</div>'+badge+'</div>';
      }).join('');
      return '<div class="panel"><div class="phead"><div><h2>Maturity by area</h2><p class="note">Each area\'s score out of 5 on '+esc(long(cur.date))+''+
        (base? '; green at the end of a bar is what it gained since '+esc(long(base.date))+', red what it lost' : '')+'. '+
        (target!=null? 'Dashed marker = target level; amber bars are below it.' : '')+'</p></div></div><div class="areabars">'+rows+'</div></div>';
    }
    // Insights cards: each headline number across every kept run, scaled to
    // its own range so a small move shows.
    function trendsHtml(){
      if(viewRuns.length<2) return '';
      const cards=TRENDS.map(([k,theme])=>{
        const m=MK[k], kept=viewRuns.filter(e=>mv(e,k)!=null); if(kept.length<2) return '';
        const first=mv(kept[0],k), last=mv(kept[kept.length-1],k);
        return '<div class="ipanel"><h3>'+esc(m[1])+'</h3><p class="note">'+fmtVal(first,m[3])+' on '+esc(short(kept[0].date))+', '+fmtVal(last,m[3])+' on '+esc(short(kept[kept.length-1].date))+' ('+fmtDelta(first,last,m[2],m[3])+'), over '+kept.length+' runs.</p>'+
          trendHtml(kept.map(e=>({label:short(e.date),value:mv(e,k)})),{theme:theme,unit:m[3]==='gb'?' GB':'',fit:true})+'</div>';
      }).join('');
      return cards? '<div class="seclabel">Over time</div><div class="insights pgcards">'+cards+'</div>' : '';
    }
    // A card of changes: each side a list with its dot, every item listed
    // (the first SHOW, then Show all). A subject with no change has no card.
    function changeCard(title, sides){
      const live=sides.filter(g=>g.items.length);
      if(!live.length) return {title:title, html:''};
      const body=live.map(g=>{
        const rows=g.items.map((h,i)=>'<div class="pgrow"'+(i>=SHOW?' data-mr hidden':'')+'><i class="'+g.tone+'"></i><span>'+h+'</span></div>').join('');
        const all='Show all '+g.items.length;
        const more=g.items.length>SHOW? sbtn(all,'data-more data-all="'+all+'" data-less="Show fewer"',{cls:'morebtn'}) : '';
        return '<div class="pgsub"><div class="pgsubh">'+esc(g.label)+'<span class="subcount">'+g.items.length.toLocaleString('en-GB')+'</span></div><div class="morewrap">'+rows+more+'</div></div>';
      }).join('');
      return {title:title, html:'<div class="ipanel"><h3>'+esc(title)+'</h3><p class="note">'+
        esc(live.map(g=>g.items.length.toLocaleString('en-GB')+' '+g.label.toLowerCase()).join(', '))+'.</p>'+body+'</div>'};
    }
    function changesHtml(base){
      if(!base) return '';
      const bs=base.sets||{}, cs=cur.sets||{};
      const fb={}, fc={}; (bs.findings||[]).forEach(f=>{ fb[f.id]=f; }); (cs.findings||[]).forEach(f=>{ fc[f.id]=f; });
      const fd=diff(Object.keys(fb),Object.keys(fc));
      const cb={}, cc={}; (bs.criteria||[]).forEach(c=>{ cb[c.id]=c; }); (cs.criteria||[]).forEach(c=>{ cc[c.id]=c; });
      const nowMet=Object.keys(cc).filter(id=>cc[id].status==='M' && (!cb[id]||cb[id].status!=='M')).sort();
      const nowGap=Object.keys(cc).filter(id=>cc[id].status==='G' && cb[id] && cb[id].status==='M').sort();
      const rd=diff(bs.rules,cs.rules), td=diff(bs.techniques,cs.techniques), tbd=diff(bs.tables,cs.tables);
      const ud=diff(bs.uncovered,cs.uncovered), ing=new Set(cs.tables||[]);
      const findItem=f=>(listedFindings.has(f.id)? link('pgfind','data-id="'+esc(f.id)+'"',f.id) : '<b>'+esc(f.id)+'</b>')+' <span class="tagpill">'+esc(f.severity||'')+'</span> '+esc(f.title);
      const critItem=id=>link('pgcrit','data-id="'+esc(id)+'"',id)+' '+esc((cc[id]||cb[id]||{}).name||'');
      const ruleItem=n=>link('pgrule','data-name="'+esc(n)+'"',n);
      const techItem=id=>'<b>'+esc(id)+'</b>'+(techName[id]? ' '+esc(techName[id]) : '');
      const cards=[
        changeCard('Findings',[{label:'Resolved',tone:'good',items:fd.removed.map(id=>findItem(fb[id]))},{label:'New',tone:'bad',items:fd.added.map(id=>findItem(fc[id]))}]),
        changeCard('Maturity criteria',[{label:'Now met',tone:'good',items:nowMet.map(critItem)},{label:'Now a gap',tone:'bad',items:nowGap.map(critItem)}]),
        changeCard('Analytics rules',[{label:'Enabled',tone:'good',items:rd.added.map(ruleItem)},{label:'No longer enabled',tone:'bad',items:rd.removed.map(esc)}]),
        changeCard('ATT&CK coverage',[{label:'Now covered',tone:'good',items:td.added.map(techItem)},{label:'No longer covered',tone:'bad',items:td.removed.map(techItem)}]),
        changeCard('Detection coverage of tables',[{label:'Now read by a detection',tone:'good',items:ud.removed.filter(t=>ing.has(t)).map(esc)},{label:'No detection reads them now',tone:'bad',items:ud.added.map(esc)}]),
        changeCard('Ingestion',[{label:'Started ingesting',tone:'',items:tbd.added.map(esc)},{label:'Stopped ingesting',tone:'',items:tbd.removed.map(esc)}])
      ];
      const shown=cards.filter(c=>c.html), quiet=cards.filter(c=>!c.html).map(c=>c.title);
      const head='<div class="seclabel">What changed since '+esc(long(base.date))+'</div>';
      if(!shown.length) return head+'<div class="panel"><p class="note pgquiet">Nothing changed in findings, maturity criteria, analytics rules, ATT&amp;CK coverage, detection coverage or ingestion.</p></div>';
      return head+'<div class="insights pgcards">'+shown.map(c=>c.html).join('')+'</div>'+
        (quiet.length? '<p class="note pgquiet">No change in '+esc(andList(quiet))+'.</p>' : '');
    }
    // Every measure, then and now.
    function tableHtml(base){
      const rows=METRICS.filter(([k])=>mv(cur,k)!=null||mv(base,k)!=null).map(([k,label,better,f])=>
        '<tr><td>'+esc(label)+'</td>'+(base?'<td class="num">'+fmtVal(mv(base,k),f)+'</td>':'')+'<td class="num">'+fmtVal(mv(cur,k),f)+'</td>'+(base?'<td class="num">'+fmtDelta(mv(base,k),mv(cur,k),better,f)+'</td>':'')+'</tr>');
      return '<div class="panel"><div class="phead"><div><h2>Every measure</h2><p class="note">'+
        (base? 'Each figure on '+esc(long(base.date))+' and on '+esc(long(cur.date))+'. Posture is as each run collected it; activity and cost are each run\'s own collected window ('+WIN.words(+cur.windowDays||WIN.collected)+' here), not the dates chosen at the top.' : 'Each figure as this run collected it.')+'</p></div></div>'+
        '<table class="tbl"><thead><tr><th>Measure</th>'+(base?'<th class="num">'+esc(short(base.date))+'</th>':'')+'<th class="num">'+esc(short(cur.date))+'</th>'+(base?'<th class="num">Change</th>':'')+'</tr></thead><tbody>'+rows.join('')+'</tbody></table></div>';
    }

    function draw(){
      const sel=chooseRuns(), base=sel.end? sel.base : null;
      cur=sel.end||latest;
      // The trends cover the runs between the two compared, both included.
      viewRuns=entries.filter(e=>(!base || e.date>=base.date) && e.date<=cur.date).sort((a,b)=>a.date<b.date?-1:1);
      const n=base? daysBetween(base.date,cur.date) : 0;
      setCtx(!sel.end? 'No run was kept on or before <b>'+esc(fmtDate(WIN.endT))+'</b>. Choose later dates to compare.' :
        base? 'Change from the run of <b>'+esc(long(base.date))+'</b> to the run of <b>'+esc(long(cur.date))+'</b>, '+n+' day'+(n===1?'':'s')+' apart. The dates chosen at the top pick the runs; '+entries.length+' are kept.' :
        entries.length>1? 'Only the run of <b>'+esc(long(cur.date))+'</b> falls on or before these dates. Choose dates that reach back to an earlier run to compare.' :
        'Only the run of <b>'+esc(long(cur.date))+'</b> is kept so far. Each run adds a record, and this view compares them.');
      if(!sel.end){ board.innerHTML=''; return; }
      board.innerHTML=tilesHtml(base)+areasHtml(base)+trendsHtml()+changesHtml(base)+tableHtml(base);
      // Balanced rows, as the other boards: after this script has run, as
      // the first draw comes before the grid list is set up.
      requestAnimationFrame(()=>{ if(typeof balanceGrids==='function') balanceGrids(); });
      if(typeof markClamped==='function') markClamped();
      if(typeof window.fitIframe==='function') window.fitIframe();
    }
    board.addEventListener('click',e=>openItem(e.target.closest('.pglink')));
    board.addEventListener('keydown',e=>{ const l=e.target.closest('.pglink'); if(l && (e.key==='Enter'||e.key===' ')){ e.preventDefault(); openItem(l); } });
    function openItem(l){
      if(!l) return;
      if(l.classList.contains('pgfind') && typeof window.showFinding==='function') window.showFinding(l.dataset.id);
      else if(l.classList.contains('pgcrit') && typeof window.showCriterion==='function'){ if(activateTab) activateTab('maturity'); window.showCriterion(l.dataset.id); }
      else if(l.classList.contains('pgrule') && typeof window.openRuleReport==='function') window.openRuleReport(l.dataset.name);
    }
    draw();
    // The history beside the dashboard: the runs before this one.
    try{
      if(SNAP.read){
        SNAP.read('progress-history.json').then(h=>{
          const earlier=((h&&h.entries)||[]).filter(e=>e&&e.date&&e.date<latest.date).sort((a,b)=>a.date<b.date?-1:1);
          if(!earlier.length) return;
          entries=earlier.concat([latest]); draw();
        }).catch(()=>{});
      }
    }catch(e){}
  })();

