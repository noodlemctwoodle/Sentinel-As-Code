(function(){
  "use strict";
  const M = JSON.parse(document.getElementById('sac-model').textContent);
  // The window the cards cover: the days of activity the collector read
  // (M.window, from run-context.json), 30 for a model from before the
  // setting, and the recent window within it. collected is fixed: what was
  // judged when the data was collected (the maturity score, the findings)
  // keeps it. d() reads "30d", w() "30 days"; rd() and rw() the recent ones.
  const WIN=(function(){
    const days=(M.window&&+M.window.days>0)? +M.window.days : 30;
    const recent=(M.window&&+M.window.recentDays>0)? +M.window.recentDays : Math.min(7,days);
    const words=n=>n===1? '1 day' : n+' days';
    // ago: how many days before the collection the window ends (0: it ends
    // with it); startT, endT and lastT: its first and last day and the
    // collection's (UTC midnights), set once the daily series are read.
    const o={days, recent, collected:days, ago:0, startT:null, endT:null, lastT:null};
    o.d=()=>o.days+'d'; o.w=()=>words(o.days); o.rd=()=>o.recent+'d'; o.rw=()=>words(o.recent); o.cd=()=>o.collected+'d'; o.cw=()=>words(o.collected);
    o.words=words;
    // The window in a sentence: "the last 7 days", or for one that ends
    // before the collection "the 7 days to 7 Sep 2026". Its own date words,
    // as the page's fixed text is named before fmtDate is set up.
    const MON=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const day=t=>{ const d=new Date(t); return d.getUTCDate()+' '+MON[d.getUTCMonth()]+' '+d.getUTCFullYear(); };
    o.span=()=>o.ago>0 && o.endT!=null? 'the '+words(o.days)+' to '+day(o.endT) : 'the last '+words(o.days);
    return o;
  })();
  // The date range. The build's daily series (M.daily) count per day ago
  // over the daily span (the lookback, at most 90), so any N consecutive
  // days of them, ending ago days before the collection, are an N-day
  // window. The range's N and ago, and after a change
  // the open view and report page, live in window.name across the reload a
  // change makes (on SharePoint the web part runs the script again on each
  // load of its frame, which keeps its height meanwhile, so the page stays
  // where it was; served as files, the browser keeps the scroll position). window.name can be set by any page this tab
  // visited, so each value is checked before use and never written out as
  // markup. A model without daily series keeps its collected window.
  const DAILY=(M.daily&&+M.daily.span>0)? M.daily : null;
  const SAVED=(function(){
    try{ const m=/^sacDash:(.*)$/.exec(window.name||''); const o=m? JSON.parse(m[1]) : null; return (o&&typeof o==='object')? o : {}; }
    catch(e){ return {}; }
  })();
  if(DAILY){
    const span=+DAILY.span, want=Math.round(+SAVED.days||0), n=Math.min(Math.max(want,1), span);
    const ago=Math.min(Math.max(Math.round(+SAVED.ago||0),0), span-n);
    if(want>=1 && (n!==WIN.collected || ago>0)){ WIN.days=n; WIN.ago=ago; WIN.recent=Math.min(WIN.recent, n); applyWindow(M, DAILY, WIN.days, WIN.recent, WIN.ago); }
    const at=Date.parse(DAILY.asOf||'');
    if(!isNaN(at)){ const d=new Date(at); WIN.lastT=Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()); WIN.endT=WIN.lastT-WIN.ago*864e5; WIN.startT=WIN.endT-(WIN.days-1)*864e5; }
  }
  // Rebuild every windowed part of the model for the last N days (R of them
  // recent) from the daily series, the way the build makes it from the
  // collected captures: cost and its projection to a month, the billing
  // flow, the estate and its rings, the top alerting rules, operational
  // health, rule effectiveness, detection outcomes and opportunities,
  // playbook runs, incident outcomes and the alert lifecycle. Cost and the
  // flow are re-priced only when the estimate priced every table (costed).
  // What does not count activity (configuration, threat intelligence,
  // findings, maturity, the Report tab's pages) keeps the collected window.
  function applyWindow(M, D, N, R, S){
    // S: the days before the collection the window ends (0: with it); each
    // series is [days ago, values], so the window is days ago S to S+N-1.
    S=+S||0;
    const sum=(d,i,n)=>{ let s=0; (d||[]).forEach(e=>{ const k=+e[0]-S; if(k>=0 && k<n) s+=(+e[i]||0); }); return s; };
    const r1=v=>Math.round(v*10)/10, r2=v=>Math.round(v*100)/100, r3=v=>Math.round(v*1000)/1000;
    const asi=pv=>/^ASI (Scheduled|NRT) Alerts$/.test(pv||'');
    // Tables: GB over N days and over the recent days, priced per GB and
    // projected to a month as the cost estimate does.
    const T=(D.tables||[]).map(t=>{ const gb=sum(t.d,1,N); return {t, gb, recent:sum(t.d,1,R), cost:r2(gb*(+t.u||0)*30/N)}; })
      .filter(x=>x.gb>0).sort((a,b)=>b.gb-a.gb);
    if(M.cost && D.costed){
      const C=M.cost, plans=(C.byPlan||[]).map(p=>p.plan), agg={};
      plans.forEach(p=>{ agg[p]={gb:0,cost:0}; });
      T.forEach(x=>{ const b=plans.includes(x.t.plan)? x.t.plan : 'Analytics'; const a=agg[b]||(agg[b]={gb:0,cost:0}); a.gb+=x.gb; a.cost+=x.cost; });
      C.byPlan=Object.keys(agg).map(p=>({plan:p, gb30d:r2(agg[p].gb), cost:r2(agg[p].cost)}));
      C.allTables=T.map(x=>({table:x.t.t, plan:x.t.plan, gb30d:r2(x.gb), cost:x.cost}));
      C.topTables=C.allTables.slice().sort((a,b)=>b.cost-a.cost).slice(0,10);
      C.monthlyTotal=r2(C.allTables.reduce((a,r)=>a+r.cost,0));
      // The billing flow: the nine largest tables and the rest as one node
      // with a part per plan label; families, tables, plans and lake tiers,
      // then billed in full or eligible for a data grant (b).
      // GB to two places first, as the estimate rounds each table.
      const rows=T.slice(0,9).map(x=>{ const gb=r3(r2(x.gb)); return {table:x.t.t, family:x.t.f, gb, parts:[{plan:x.t.pl, gb, billedGb:(+x.t.u>0 && !x.t.b? gb : 0)}]}; });
      const rest=T.slice(9);
      if(rest.length){
        const parts={};
        rest.forEach(x=>{ const gb=r2(x.gb), p=parts[x.t.pl]||(parts[x.t.pl]={plan:x.t.pl, gb:0, billedGb:0}); p.gb+=gb; if(+x.t.u>0 && !x.t.b) p.billedGb+=gb; });
        let restGb=0; const list=Object.values(parts);
        list.forEach(p=>{ p.gb=r3(p.gb); p.billedGb=r3(p.billedGb); restGb+=p.gb; });
        rows.push({table:'Other (+'+rest.length+')', family:'Other', gb:r3(restGb), parts:list});
      }
      const fam={}, plan={}, pb={}, bucket={'Billed':0, 'Grant eligible':0};
      rows.forEach(row=>{
        fam[row.family]=(fam[row.family]||0)+row.gb;
        row.parts.forEach(p=>{
          plan[p.plan]=(plan[p.plan]||0)+p.gb;
          const free=r3(p.gb-p.billedGb);
          bucket['Billed']+=p.billedGb; bucket['Grant eligible']+=free;
          [['Billed',p.billedGb],['Grant eligible',free]].forEach(([b,v])=>{ if(v>0){ const k=p.plan+'|'+b; pb[k]=(pb[k]||0)+v; } });
        });
      });
      const nodes=[], links=[];
      Object.keys(fam).sort((a,b)=>fam[b]-fam[a]).forEach(f=>nodes.push({id:'f:'+f, col:0, label:f, value:r3(fam[f])}));
      rows.forEach(row=>nodes.push({id:'t:'+row.table, col:1, label:row.table, value:row.gb}));
      Object.keys(plan).sort((a,b)=>plan[b]-plan[a]).forEach(p=>nodes.push({id:'p:'+p, col:2, label:p, value:r3(plan[p]), lake:/lake/i.test(p)}));
      ['Billed','Grant eligible'].forEach(b=>{ if(bucket[b]>0) nodes.push({id:'b:'+b, col:3, label:b, value:r3(bucket[b])}); });
      rows.forEach(row=>{
        links.push({source:'f:'+row.family, target:'t:'+row.table, value:row.gb});
        row.parts.forEach(p=>links.push({source:'t:'+row.table, target:'p:'+p.plan, value:p.gb}));
      });
      Object.keys(pb).forEach(k=>{ const i=k.indexOf('|'); links.push({source:'p:'+k.slice(0,i), target:'b:'+k.slice(i+1), value:r3(pb[k])}); });
      M.flow={nodes, links};
      M.flowTables=T.map(x=>{ const gb=r3(r2(x.gb)); return {table:x.t.t, family:x.t.f, plan:x.t.pl, gb, billedGb:(+x.t.u>0 && !x.t.b? gb : 0)}; });
      if(M.dataLake && M.dataLake.cost){
        const row=p=>C.byPlan.find(x=>x.plan===p)||{gb30d:0, cost:0};
        Object.assign(M.dataLake.cost, {analyticsGb:row('Analytics').gb30d, analyticsCost:row('Analytics').cost, lakeGb:row('DataLake').gb30d, lakeCost:row('DataLake').cost});
      }
    }
    // Alerts, once each on the day first seen, grouped as the volumes
    // capture groups them (name, product, severity).
    const A=(D.alerts||[]).map(a=>({a, n:sum(a.d,1,N)})).filter(x=>x.n>0);
    const vol={}, pfOf={};
    let all=0, sen=0, xdr=0;
    A.forEach(({a,n})=>{
      all+=n; if(/sentinel/i.test(a.p||'')) sen+=n; else xdr+=n;
      if(a.p) pfOf[a.p]=a.pf||'';
      const k=[a.n,a.p,a.s].join('\u001f'); const v=vol[k]||(vol[k]={name:a.n, product:a.p, severity:a.s, alerts:0}); v.alerts+=n;
    });
    M.topRules=Object.values(vol).sort((a,b)=>b.alerts-a.alerts);
    // Sentinel's scheduled and NRT rules that fired, keyed on rule id (or
    // alert name without one), as rules-fired keys them.
    const fired={}, firedById={}, firedByName={};
    A.forEach(({a,n})=>{
      if(!asi(a.pv)) return;
      const k=a.r||a.n; fired[k]=(fired[k]||0)+n;
      if(a.r) firedById[a.r]=(firedById[a.r]||0)+n;
      if(a.n) firedByName[a.n]=(firedByName[a.n]||0)+n;
    });
    // The ring counts those that are enabled now, as the build does.
    const QK=Array.isArray(D.queryRules)? new Set(D.queryRules) : null;
    const ruleAlerts=Object.values(fired).reduce((s,v)=>s+v,0);
    const firedCount=QK? A.filter(({a})=>asi(a.pv) && (a.r? QK.has(a.r) : QK.has('name:'+a.n))).map(({a})=>a.r||a.n).filter((k,i,l)=>l.indexOf(k)===i).length
                       : Object.keys(fired).length;
    if(all<=0){ all=ruleAlerts; sen=ruleAlerts; }
    // Incidents at their latest state: [incidents, acknowledged, ack minutes, resolved, resolve minutes].
    const I=(D.incidents||[]).map(i=>({i, v:[1,2,3,4,5].map(k=>sum(i.d,k,N))})).filter(x=>x.v[0]>0);
    const incidents=I.reduce((s,x)=>s+x.v[0],0), closed=I.filter(x=>x.i.st==='Closed').reduce((s,x)=>s+x.v[0],0);
    if(M.estate){
      const E=M.estate, fams={};
      let seen=0, active=0, covered=0, total=0, covGb=0;
      E.tables=T.map(x=>{
        const t=x.t, act=x.recent>0;
        seen++; if(act) active++; total+=x.gb;
        const f=fams[t.f]||(fams[t.f]={category:t.f, tables:0, gb:0, coveredGb:0, covered:0});
        f.tables++; f.gb+=x.gb;
        if(t.cov){ if(act) covered++; covGb+=x.gb; f.covered++; f.coveredGb+=x.gb; }
        return {table:t.t, family:t.f, gb:r2(x.gb), rules:+t.r||0, customDetections:+t.cd||0, covered:!!t.cov};
      });
      E.sources=Object.values(fams).sort((a,b)=>b.gb-a.gb).map(f=>({category:f.category, tables:f.tables, gb:r2(f.gb), coveredGb:r2(f.coveredGb), covered:f.covered}));
      const prod={};
      Object.values(vol).forEach(v=>{
        if(!v.product || /sentinel/i.test(v.product)) return;
        const fm=pfOf[v.product]||'', k=fm+'|'+v.product;
        const p=prod[k]||(prod[k]={family:fm, product:v.product, alerts:0, detections:0}); p.alerts+=v.alerts; p.detections++;
      });
      E.productAlerts=Object.values(prod).sort((a,b)=>b.alerts-a.alerts);
      E.totalGb=r2(total); E.coveredGb=r2(covGb); E.uncoveredGb=r2(total-covGb);
      const ring=(k,label,value,max)=>{ const r=(E.rings||(E.rings={}))[k]||(E.rings[k]={label}); if(label) r.label=label; r.value=value; r.max=max; r.pct=max>0? Math.round(100*value/max) : null; };
      ring('ingestion','Tables still receiving data ('+R+'d, of those with data in '+N+'d)',active,seen);
      ring('detection','',covered,active);
      ring('alerts','',firedCount,+D.rulesQueryEnabled||0);
      ring('incidents','',closed,incidents);
      Object.assign(E, {window:N+'d', rulesFired:firedCount, alerts:all, alertsSentinel:sen, alertsXdr:Math.max(0,all-sen), ruleAlerts,
        incidents, incidentsClosed:closed, incidentsOpen:Math.max(0,incidents-closed)});
    }
    if(M.health){
      const rows=(D.health||[]).map(h=>({OperationName:h.o, Status:h.st, LogCount:sum(h.d,1,N)})).filter(r=>r.LogCount>0).sort((a,b)=>b.LogCount-a.LogCount);
      const tot=rows.reduce((s,r)=>s+r.LogCount,0), ok=rows.filter(r=>r.Status==='Success').reduce((s,r)=>s+r.LogCount,0);
      M.health={pct:tot>0? r1(100*ok/tot) : 0, totalEvents:tot, rows};
    }
    // Incidents per detection with their verdicts: Sentinel rules (by rule
    // id) first, then other products' alerts by name.
    const RU=(D.rules||[]).map(r=>{ const v=[1,2,3,4,5,6].map(k=>sum(r.d,k,N)); return {r, inc:v[0], closed:v[1], tp:v[2], fp:v[3], bp:v[4], und:v[5]}; }).filter(x=>x.inc>0);
    M.effectiveness=RU.slice().sort((a,b)=>((a.r.id?0:1)-(b.r.id?0:1))||(b.inc-a.inc)).map(x=>({rule:x.r.an, source:x.r.src, incidents:x.inc, closed:x.closed,
      tp:x.tp, fp:x.fp, bp:x.bp, undetermined:x.und, fpRate:r1(100*x.fp/(x.closed||1))}));
    if(M.detectionOutcomes){
      const effById={}, effByName={};
      RU.forEach(x=>{ if(x.r.id) effById[x.r.id]=x; if(x.r.an && !effByName[x.r.an]) effByName[x.r.an]=x; });
      const rank={Failing:0, Working:1, Silent:2};
      M.detectionOutcomes=M.detectionOutcomes.map(o=>{
        const sentinel=o.source==='Sentinel';
        const e=(sentinel && o.key && effById[o.key]) || effByName[o.name] || null;
        const alerts=sentinel? ((o.key && firedById[o.key]) || firedByName[o.name] || 0) : 0;
        const inc=e? e.inc : 0, cl=e? e.closed : 0, tp=e? e.tp : 0, fp=e? e.fp : 0, bp=e? e.bp : 0, und=e? e.und : 0;
        const health=(+o.failures||0)>0? 'Failing' : ((alerts>0||inc>0)? 'Working' : 'Silent');
        return Object.assign({}, o, {health, alerts, incidents:inc, closed:cl, tp, fp, bp, undetermined:und,
          unclassified:Math.max(0,cl-tp-fp-bp-und), open:Math.max(0,inc-cl)});
      }).sort((a,b)=>(rank[a.health]-rank[b.health])||(b.incidents-a.incidents)||String(a.name).localeCompare(String(b.name)));
    }
    if(M.detectionOpportunities){
      const gbOf={}; T.forEach(x=>{ gbOf[x.t.t]=x.gb; });
      M.detectionOpportunities=M.detectionOpportunities.filter(o=>(gbOf[o.table]||0)>0)
        .map(o=>Object.assign({}, o, {gb30d:r2(gbOf[o.table])})).sort((a,b)=>b.gb30d-a.gb30d);
    }
    if(M.playbookHealth && D.playbooks){
      let runs=0, failed=0, unavailable=0; const failing=[];
      D.playbooks.forEach(p=>{
        if(p.unavailable){ unavailable++; return; }
        const r=sum(p.d,1,N), f=sum(p.d,2,N); runs+=r; failed+=f;
        if(f>0) failing.push({playbook:p.n, runs:r, failed:f, lastFailure:p.last||''});
      });
      M.playbookHealth={runs7d:runs, failed7d:failed, playbooks:D.playbooks.length, unavailable, failing:failing.sort((a,b)=>b.failed-a.failed)};
    }
    if(M.incidentsByClassification){
      const cls={};
      I.forEach(x=>{ if(x.i.st==='Closed'){ const c=x.i.c||'Unclassified'; cls[c]=(cls[c]||0)+x.v[0]; } });
      M.incidentsByClassification=Object.keys(cls).sort((a,b)=>cls[b]-cls[a]).map(k=>({label:k, value:cls[k]}));
    }
    if(M.alertLifecycle){
      const L=M.alertLifecycle;
      if(L.closedBy){ const by={AutomationRule:0, Analyst:0, DefenderXdr:0, Other:0}; I.forEach(x=>{ if(x.i.st==='Closed' && x.i.by in by) by[x.i.by]+=x.v[0]; }); L.closedBy=by; }
      if(L.openBySeverity){ const sv={High:0, Medium:0, Low:0, Informational:0}; I.forEach(x=>{ if(x.i.st!=='Closed' && x.i.sev in sv) sv[x.i.sev]+=x.v[0]; }); L.openBySeverity=sv; }
      const rc=I.reduce((s,x)=>s+x.v[3],0), rs=I.reduce((s,x)=>s+x.v[4],0);
      L.mttrMinutes=rc>0? r1(rs/rc) : null;
    }
    // The daily ingestion trend: the calendar days the window touches.
    if(M.usageDaily){
      const t=Date.parse(D.asOf||'');
      if(!isNaN(t)){ const last=new Date(t-S*864e5).toISOString().slice(0,10), first=new Date(t-(S+N-1)*864e5).toISOString().slice(0,10);
        M.usageDaily=M.usageDaily.filter(u=>String(u.day)>=first && String(u.day)<=last); }
    }
  }
  // Fixed text in the page names the window through data-win spans.
  const paintWindow=()=>document.querySelectorAll('[data-win]').forEach(e=>{ const k=e.dataset.win; e.textContent= k==='d'? WIN.d() : k==='rd'? WIN.rd() : k==='rw'? WIN.rw() : k==='span'? WIN.span() : WIN.w(); });
  paintWindow();
  // Where the dashboard's files are. On SharePoint the web part says
  // (window.sacSnapshot: the folder, a reader and a loader), since the frame's
  // own address is about:srcdoc; served as files, the page's folder (the
  // folder above, for a snapshot under history/). From disk there is none.
  const SNAP=(function(){
    const host=window.sacSnapshot||null;
    let root=null;
    try{
      if(host&&host.base) root=new URL(host.base);
      else if(/^https?:$/.test(location.protocol)){ const here=new URL('.',location.href); root=/\/history\/$/.test(here.pathname)? new URL('..',here) : here; }
    }catch(e){ root=null; }
    const read=!root? null : (file=> host&&host.read ? host.read(file).then(t=>JSON.parse(t)) :
      fetch(new URL(file,root).href,{credentials:'same-origin',cache:'no-store'}).then(r=>r.ok?r.json():null));
    return {host, root, read};
  })();
  // cross-tab navigation hooks (assigned later, used by the gap-analysis buttons)
  let gotoDocSection = null;   // (num) => void  — open a section in the Sections tab
  let activateTab = null;      // (name) => void — switch the top-level tab
  let curView = 'overview';    // the view showing, and the report page open (for the date range's reload)
  let curDoc = () => null;
  // Bring an element's top into view, so a link opens at the top of what it
  // shows rather than at the old scroll position. On SharePoint the web part
  // grows its iframe to the dashboard's full height and the SharePoint page
  // does the scrolling, so window.scrollTo here moves nothing; scrollIntoView
  // scrolls every scrolling ancestor, the host page's included. With
  // onlyIfAbove, an element whose top is already on screen stays put.
  function bringTop(el, onlyIfAbove){
    el=el||document.body;
    if(onlyIfAbove){
      let top=el.getBoundingClientRect().top;
      try{ if(window.frameElement) top+=window.frameElement.getBoundingClientRect().top; }catch(e){}
      if(top>=0) return;
    }
    try{ el.scrollIntoView({block:'start'}); }catch(e){ window.scrollTo(0,0); }
  }
  const famColor = {
    'Entra ID / Identity':'#3b6fb0','Defender XDR':'#2b8c9e','Threat Intelligence':'#7a5a9e',
    'Azure / Syslog':'#c2912b','Custom logs':'#8a6d3b','Other':'#64748b'
  };
  const colColor = ['#3b6fb0','#94a3b8','#4f5bd5','#2e8b64'];
  const lakeColor = '#0d9488';
  const nodeFill = n => n.col===0 ? (famColor[n.label]||'#64748b')
    : n.col===3 ? (n.label==='Billed'?'#c2912b':'#2e8b64')
    : (n.col===2 && n.lake) ? lakeColor : colColor[n.col];
  const esc = s => (s==null?'':String(s)).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  // moreWrap(inner,total,shown,label): the inner markup marks its hidden
  // entries with data-mr + hidden; the button toggles them. Nested wraps
  // only toggle their own entries.
  // sbtn(label, attrs, opts): the dashboard's one button (see .sbtn). label
  // is HTML; attrs is a string of extra attributes; opts.go adds the arrow
  // for a button that opens something, opts.cls classes that place it,
  // opts.icon the square symbol form, opts.href makes it a link to a page.
  const SBTN_ARROW='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14m-6-6 6 6-6 6"/></svg>';
  function sbtn(label, attrs, opts){
    opts=opts||{};
    const cls='sbtn'+(opts.icon?' icon':'')+(opts.cls?' '+opts.cls:'');
    const inner=label+(opts.go?SBTN_ARROW:'');
    return opts.href
      ? '<a class="'+cls+'" href="'+esc(opts.href)+'"'+(attrs?' '+attrs:'')+'>'+inner+'</a>'
      : '<button type="button" class="'+cls+'"'+(attrs?' '+attrs:'')+'>'+inner+'</button>';
  }
  function moreWrap(inner,total,shown,label){
    const btn = total>shown ? sbtn('Show all '+total+' '+label, 'data-more data-all="Show all '+total+' '+label+'" data-less="Show fewer"', {cls:'morebtn'}) : '';
    return '<div class="morewrap">'+inner+btn+'</div>';
  }
