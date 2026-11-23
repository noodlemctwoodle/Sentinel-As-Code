  // ---- insights board (visual Sections) ----
  const board = document.getElementById('insightsBoard');
  const fmt = n => (Math.round(n*100)/100).toLocaleString();
  // color themes so each bar chart reads distinctly
  const THEME = {
    brand:  ['#2563eb','#6d5efc'],
    teal:   ['#0d9488','#22c3a6'],
    violet: ['#7c3aed','#a855f7'],
    amber:  ['#d97706','#f59e0b'],
    rose:   ['#e11d48','#fb7185'],
    cyan:   ['#0891b2','#22d3ee'],
    indigo: ['#4f46e5','#818cf8']
  };
  // Cards that list things fill to the height of the tallest card in their
  // row, then end with a button to the report page that holds the whole
  // list (fillCards). FILL_MIN entries always show; FILL_CAP are drawn.
  const FILL_MIN=8, FILL_CAP=40;
  // keep: the button shows even when every entry fits, for a card whose
  // only link to its page it is.
  // shown: visible from the start, for a list fillCards does not measure.
  const fillFoot=(total,sec,label,keep,shown)=>sbtn('All '+total.toLocaleString()+' '+esc(label)+' in the report','data-jump="'+sec+'"'+(keep?' data-keep':'')+(shown?'':' hidden'),{go:true,cls:'fillmore'});
  function barsHtml(items, opts){
    opts = opts||{};
    const col = THEME[opts.theme] || THEME.brand;
    const max = opts.max || Math.max(1, ...items.map(i=>i.value));
    const style = opts.theme ? ' style="--c1:'+col[0]+';--c2:'+col[1]+'"' : '';
    // opts.fill {sec, label}: fill the card and link to section sec. Without
    // a section to link to, the list keeps its Show all control.
    if(opts.fill && opts.fill.sec==null){ opts.show=opts.show||FILL_MIN; opts.label=opts.label||opts.fill.label; }
    const fill = opts.fill && opts.fill.sec!=null;
    if(fill){
      return '<div class="bars" data-fill-list data-fill-total="'+items.length+'">'+items.slice(0,FILL_CAP).map(i=>
        '<div class="bar '+(i.cls||'')+'"'+style+'><div class="bl" title="'+esc(i.label)+'">'+esc(i.label)+'</div>'+
        '<div class="bt"><div class="bf" style="--w:'+Math.max(2,(i.value/max*100))+'%"></div></div>'+
        '<div class="bv">'+esc(i.display!=null?i.display:i.value)+'</div></div>').join('')+'</div>'+fillFoot(items.length,opts.fill.sec,opts.fill.label,opts.fill.keep);
    }
    const show = opts.show || items.length;
    const html = '<div class="bars">'+items.map((i,ix)=>
      '<div class="bar '+(i.cls||'')+'"'+style+(ix>=show?' data-mr hidden':'')+'><div class="bl" title="'+esc(i.label)+'">'+esc(i.label)+'</div>'+
      '<div class="bt"><div class="bf" style="--w:'+Math.max(2,(i.value/max*100))+'%"></div></div>'+
      '<div class="bv">'+esc(i.display!=null?i.display:i.value)+'</div></div>').join('')+'</div>';
    return opts.show ? moreWrap(html, items.length, show, opts.label||'entries') : html;
  }
  function donutHtml(pct, bigLabel, kLabel){
    return '<div class="donut" style="--p:'+pct+'"><div class="hole"><div><div class="hv">'+esc(bigLabel)+'</div>'+
      '<div class="hk">'+esc(kLabel)+'</div></div></div></div>';
  }
  // pie chart with legend from [{label,value,color}]
  function pieHtml(items){
    const total=items.reduce((a,i)=>a+i.value,0)||1;
    let acc=0; const segs=items.map(i=>{ const start=acc/total*360; acc+=i.value; const end=acc/total*360;
      return i.color+' '+start.toFixed(2)+'deg '+end.toFixed(2)+'deg'; }).join(',');
    const legend=items.map(i=>'<div class="pli"><i style="background:'+i.color+'"></i>'+esc(i.label)+
      '<span class="pv">'+esc(i.display!=null?i.display:i.value)+'</span>'+
      '<span class="pp">'+Math.round(i.value/total*100)+'%</span></div>').join('');
    return '<div class="piewrap"><div class="pie" style="--pie:conic-gradient('+segs+')"></div>'+
      '<div class="pielegend">'+legend+'</div></div>';
  }
  // multi-segment donut with a centre total from [{label,value,color}]
  // A figure too long for a donut's hole goes compact (2.36M), with the
  // exact one on hover; the legend keeps every exact figure.
  function holeFigure(text){
    const s=String(text), n=+s.replace(/,/g,'');
    if(s.length<=7 || !isFinite(n) || Math.abs(n)<1e3) return '<div class="dmsv">'+esc(s)+'</div>';
    const u=[[1e9,'B'],[1e6,'M'],[1e3,'K']].find(([v])=>Math.abs(n)>=v), x=n/u[0];
    const c=parseFloat(x.toFixed(Math.abs(x)>=100?0:Math.abs(x)>=10?1:2))+u[1];
    return '<div class="dmsv" title="'+esc(s)+'">'+esc(c)+'</div>';
  }
  function donutMultiHtml(items, centreBig, centreSmall){
    const total=items.reduce((a,i)=>a+i.value,0)||1;
    let acc=0; const segs=items.map(i=>{ const start=acc/total*360; acc+=i.value; const end=acc/total*360;
      return i.color+' '+start.toFixed(2)+'deg '+end.toFixed(2)+'deg'; }).join(',');
    const legend=items.map(i=>'<div class="pli"><i style="background:'+i.color+'"></i>'+esc(i.label)+
      '<span class="pv">'+esc(i.display!=null?i.display:i.value)+'</span>'+
      '<span class="pp">'+Math.round(i.value/total*100)+'%</span></div>').join('');
    return '<div class="piewrap"><div class="dms" style="--pie:conic-gradient('+segs+')">'+
      '<div class="dmshole"><div>'+holeFigure(centreBig)+
      '<div class="dmsk">'+esc(centreSmall)+'</div></div></div></div>'+
      '<div class="pielegend">'+legend+'</div></div>';
  }

  const cards = [];

  // 1. MITRE ATT&CK coverage (full width): the technique grid, which
  //    wireAttackGrid fills once the board is built; a snapshot without the
  //    attack model keeps the tactic bars.
  const mitreSec = findSecNum(/mitre/i, null);
  if(M.attack && M.attack.tactics && M.attack.tactics.length){
    const nOn=M.attack.rules.filter(r=>r.enabled).length;
    cards.push('<div class="ipanel full" id="akPanel"><h3>Detection coverage by MITRE ATT&amp;CK technique</h3>'+
      '<p class="note">Each column is a tactic; each cell a technique an analytics rule maps, shaded by the enabled rules that map it. Sub-techniques lists each one under its technique, shaded by its own rules. '+nOn+' of '+M.attack.rules.length+' rules are enabled. Select a technique or sub-technique for its rules.</p>'+
      '<div class="ak-tools"><div class="ak-seg" role="group" aria-label="Level"><button type="button" class="on" data-ak-level="tech">Techniques</button><button type="button" data-ak-level="sub">Sub-techniques</button></div>'+
      '<div class="ak-seg" role="group" aria-label="Rules"><button type="button" class="on" data-ak-rules="enabled">Enabled rules</button><button type="button" data-ak-rules="all">Include disabled</button></div>'+
      '<div class="ak-seg" role="group" aria-label="Techniques"><button type="button" class="on" data-ak-show="covered">Covered techniques</button><button type="button" data-ak-show="all">Every technique</button></div>'+
      '<input type="search" class="docsearch" id="akSearch" placeholder="Find a rule or technique" aria-label="Find a rule or technique">'+
      (mitreSec!=null?sbtn('Open the MITRE page','data-jump="'+mitreSec+'"',{go:true,cls:'ak-open'}):'')+'</div>'+
      '<div class="ak-keyrow"><span class="ak-key"><i class="h1"></i><i class="h2"></i><i class="h3"></i>technique<i class="s1"></i><i class="s2"></i><i class="s3"></i>sub-technique (1 rule, 2 to 3, 4 or more)<i class="off"></i>disabled rules only<i class="gap"></i>not covered</span></div>'+
      '<div class="ak-scroll"><div class="ak-grid" id="akGrid"></div></div><div id="akDetail" class="hidden"></div></div>');
  } else {
    const mMax = Math.max(1, ...M.mitre.map(t=>t.rules));
    const mcls = s => s==='Covered'?'cov':(s==='Thin'?'thin':'gap');
    const mrows = M.mitre.map(t=>{
      const cls=mcls(t.status);
      return '<div class="mrow '+cls+'"><div class="mt" title="'+esc(t.tactic)+'">'+esc(t.tactic)+'</div>'+
        '<div class="mheat"><div class="mfill" style="--w:'+Math.max(6,t.rules/mMax*100)+'%"></div>'+
        '<span class="mn">'+t.rules+'</span></div>'+
        '<span class="mstat">'+esc(t.status)+'</span></div>';
    }).join('');
    cards.push('<div class="ipanel full"><h3>Detection coverage by MITRE ATT&amp;CK tactic</h3>'+
      '<p class="note">'+M.mitreCovered+' of '+M.mitre.length+' tactics covered by at least '+(M.mitreCoveredThreshold||3)+' enabled analytics rules (Thin: 1-'+((M.mitreCoveredThreshold||3)-1)+', None: 0). Bar length = enabled rules mapped to each tactic.</p>'+
      '<div class="mitreg">'+mrows+'</div></div>');
  }

  // 2. Analytics rules enabled (donut)
  const enPct = c.rulesTotal? Math.round(c.rulesEnabled/c.rulesTotal*100):0;
  cards.push('<div class="ipanel"><h3>Analytics rules enabled</h3>'+
    '<p class="note">Enabled scheduled/NRT rules vs the full installed rule set.</p>'+
    '<div class="donutwrap">'+donutHtml(enPct, c.rulesEnabled+' / '+c.rulesTotal, enPct+'% on')+
    '<div class="dlegend"><div class="di"><i style="background:var(--brand)"></i>Enabled<b>'+c.rulesEnabled+'</b></div>'+
    '<div class="di"><i style="background:var(--line-2)"></i>Disabled / template<b>'+(c.rulesTotal-c.rulesEnabled)+'</b></div></div></div></div>');

  // 3. Findings by severity (pie)
  const sevOrder = ['Critical','Error','Warning','Info','Informational'];
  const sevColMap = {Critical:'#dc2626',Error:'#ea580c',Warning:'#d97706',Info:'#64748b',Informational:'#64748b'};
  const sevCount = {}; M.findings.items.forEach(f=>{ sevCount[f.severity]=(sevCount[f.severity]||0)+1; });
  const sevItems = sevOrder.filter(s=>sevCount[s]).map(s=>({label:s,value:sevCount[s],display:sevCount[s],color:sevColMap[s]||'#64748b'}));
  cards.push('<div class="ipanel"><h3>Findings by severity</h3>'+
    '<p class="note">'+M.findings.total+' open items from the best-practice gap analysis.</p>'+pieHtml(sevItems)+'</div>');

  // 3b. Findings by category (dynamic)
  const catCount = {}; M.findings.items.forEach(f=>{ const k=f.category||'Other'; catCount[k]=(catCount[k]||0)+1; });
  const catItems = Object.keys(catCount).map(k=>({label:k,value:catCount[k],display:catCount[k]})).sort((a,b)=>b.value-a.value);
  if(catItems.length){
    cards.push('<div class="ipanel"><h3>Findings by category</h3>'+
      '<p class="note">Where the gap-analysis findings concentrate across the workspace.</p>'+barsHtml(catItems,{theme:'violet'})+'</div>');
  }

  // Report pages that hold each card's full list.
  const secRulePerf=findSecNum(/^rule performance/i, null), secAlerts=findSecNum(/^alerts$/i, null),
        secHealth=findSecNum(/sentinel health/i, null), secAutomation=findSecNum(/^automation rules/i, null),
        secCostPage=findSecNum(/monthly cost/i, null);
  // 4. Top tables by 30-day volume
  if(cost && cost.topTables && cost.topTables.length){
    const ttSrc = (cost.allTables&&cost.allTables.length)? cost.allTables : cost.topTables;
    const tt = ttSrc.map(t=>({label:t.table,value:t.gb30d,display:fmt(t.gb30d)+' GB'}));
    cards.push('<div class="ipanel"><h3>Top tables by volume</h3>'+
      '<p class="note">Ingested GB over '+WIN.span()+' (cost-estimate snapshot).</p>'+barsHtml(tt,{theme:'teal',fill:{sec:secCostPage,label:'tables'}})+'</div>');
  }

  // 4b. Ingestion by billing plan — only when there are 2+ active plans (a single
  // plan makes a pointless one-bar chart), else show alert volume by severity.
  const activePlans = (cost && cost.byPlan ? cost.byPlan.filter(p=>p.gb30d>0) : []);
  // With the data lake enrolled the lake plan always shows (0 GB when no
  // table is lake-only), with a line for the mirror: every Analytics-plan
  // table is copied to the lake at no extra ingestion charge, so it is
  // described rather than drawn as a second bar of the same data.
  const DLp = M.dataLake||{}, lakeOn = !!(DLp.enrolled||M.dataLakeEnrolled);
  if(activePlans.length>=2 || (lakeOn && activePlans.length)){
    const pl = activePlans.filter(p=>!/^(datalake|lake)$/i.test(p.plan)).map(p=>({label:p.plan+' plan',value:p.gb30d,display:fmt(p.gb30d)+' GB'}));
    if(lakeOn){
      const lakePlan=(cost.byPlan||[]).find(p=>/^(datalake|lake)$/i.test(p.plan));
      const lakeGb=lakePlan? +lakePlan.gb30d||0 : +((DLp.cost||{}).lakeGb)||0;
      pl.push({label:'Data lake plan',value:lakeGb,display:fmt(lakeGb)+' GB',cls:'lake'});
    }
    const tiers=DLp.tiers||{}, mirrored=(+tiers.MirroredOnly||0)+(+tiers.MirroredExtended||0), extended=+DLp.extendedCount||0;
    const lakeLine = lakeOn? '<p class="note" style="margin:12px 0 0">Data lake enrolled: '+(mirrored? mirrored.toLocaleString()+' Analytics-plan table'+(mirrored===1?' is':'s are') : 'Analytics-plan tables are')+
      ' mirrored to it at no extra ingestion charge'+(extended? ', and '+extended.toLocaleString()+' keep data there beyond analytics retention' : '')+'.</p>' : '';
    cards.push('<div class="ipanel"><h3>Ingestion by billing plan</h3>'+
      '<p class="note">GB over '+WIN.span()+' split across the table plans'+(lakeOn?', the data lake included':'')+'.</p>'+barsHtml(pl,{theme:'amber'})+lakeLine+'</div>');
  } else if(M.topRules && M.topRules.length){
    const sevCol={High:'#ff4d1f',Medium:'#ffaa00',Low:'#fff100',Informational:'#8a8886',Other:'#94a3b8'};
    const sa={}; M.topRules.forEach(r=>{ const s=r.severity||'Other'; sa[s]=(sa[s]||0)+(r.alerts||0); });
    const order=['High','Medium','Low','Informational','Other'];
    const si=Object.keys(sa).map(s=>({label:s,value:sa[s],display:sa[s].toLocaleString(),color:sevCol[s]||sevCol.Other}))
      .sort((a,b)=>order.indexOf(a.label)-order.indexOf(b.label));
    const siTotal=si.reduce((a,i)=>a+i.value,0);
    cards.push('<div class="ipanel"><h3>Alert volume by severity ('+WIN.d()+')</h3>'+
      '<p class="note">Total alerts from the busiest rules, grouped by severity.</p>'+
      donutMultiHtml(si, siTotal.toLocaleString(), 'alerts')+'</div>');
  }

  // 5. Top alerting rules
  if(M.topRules && M.topRules.length){
    const tr = M.topRules.map(r=>({label:r.name,value:r.alerts,display:r.alerts.toLocaleString()}));
    cards.push('<div class="ipanel"><h3>Top alerting rules ('+WIN.d()+')</h3>'+
      '<p class="note">Rules producing the most alerts in '+WIN.span()+'.</p>'+barsHtml(tr,{theme:'indigo',fill:{sec:secRulePerf,label:'rules'}})+'</div>');
  }

  // 5a. Alerts by detection source — which security product generates the alert volume
  if(M.topRules && M.topRules.length){
    const prodName = p => ({
      'Microsoft Defender Advanced Threat Protection':'Defender for Endpoint',
      'Microsoft 365 Defender':'Microsoft 365 Defender',
      'Azure Sentinel':'Microsoft Sentinel',
      'Office 365':'Office 365'
    }[p] || p || 'Other');
    const ps={}; M.topRules.forEach(r=>{ const k=prodName(r.product); ps[k]=(ps[k]||0)+(r.alerts||0); });
    const pi=Object.keys(ps).map(k=>({label:k,value:ps[k],display:ps[k].toLocaleString()})).sort((a,b)=>b.value-a.value);
    if(pi.length){
      cards.push('<div class="ipanel"><h3>Alerts by detection source ('+WIN.d()+')</h3>'+
        '<p class="note">Share of alert volume by the security product that raised it.</p>'+barsHtml(pi,{theme:'rose',fill:{sec:secAlerts,label:'sources'}})+'</div>');
    }
  }

  // 5b. Operational health event mix (dynamic, from health rows)
  if(M.health && M.health.rows && M.health.rows.length){
    const agg={}; M.health.rows.forEach(r=>{ const k=(r.OperationName||'Other')+' · '+(r.Status||''); agg[k]=(agg[k]||0)+(parseInt(r.LogCount,10)||0); });
    const hi=Object.keys(agg).map(k=>({label:k,value:agg[k],display:agg[k].toLocaleString()})).sort((a,b)=>b.value-a.value);
    if(hi.length){
      cards.push('<div class="ipanel"><h3>Operational health event mix ('+WIN.d()+')</h3>'+
        '<p class="note">Sentinel health events by operation and status over '+WIN.span()+'.</p>'+barsHtml(hi,{theme:'cyan',fill:{sec:secHealth,label:'operations'}})+'</div>');
    }
  }

  // 6. Billed in full vs eligible for a data grant (split). A grant
  // (Microsoft 365 E5, Defender for Servers Plan 2) covers its tables up to
  // an allowance the Blueprint cannot see, so this is the most it covers.
  const billed = (M.flow.nodes.find(n=>n.col===3 && n.label==='Billed')||{}).value || 0;
  const free   = (M.flow.nodes.find(n=>n.col===3 && n.label==='Grant eligible')||{}).value || 0;
  if(billed+free>0 && free>0){
    const bp = Math.round(billed/(billed+free)*100), fp = 100-bp;
    cards.push('<div class="ipanel"><h3>Billed vs data grant eligible</h3>'+
      '<p class="note">Of ingested data, the share billed in full and the share a Microsoft 365 E5 or Defender for Servers Plan 2 data grant may cover, up to its allowance (5 MB per licensed user, or 500 MB per server, a day).</p>'+
      '<div class="split"><div class="seg" style="width:'+bp+'%;background:var(--amber)">'+fmt(billed)+' GB</div>'+
      '<div class="seg" style="width:'+fp+'%;background:var(--green)">'+fmt(free)+' GB</div></div>'+
      '<div class="dlegend" style="flex-direction:row;gap:18px;margin-top:12px">'+
      '<div class="di"><i style="background:var(--amber)"></i>Billed ('+bp+'%)</div>'+
      '<div class="di"><i style="background:var(--green)"></i>Grant eligible ('+fp+'%)</div></div></div>');
  }

  // 7. Content inventory (full)
  // Each tile opens its page in the Report tab.
  const secAt = n => (M.sections||[]).some(s=>s.num===n)? n : null;
  const inv = [
    {k:'Connectors', v:c.connectors, ic:ICON.ingest, sec:secAt(10)},
    {k:'Workbooks', v:c.workbooks, ic:ICON.gauge, sec:secAt(40)},
    {k:'Hunting queries', v:c.hunting, ic:ICON.crosshair, sec:secAt(30)},
    {k:'Watchlists', v:c.watchlists, ic:ICON.box, sec:secAt(50)},
    {k:'Automation rules', v:c.automationRules, ic:ICON.bolt, sec:secAt(60)},
    {k:'Data collection rules', v:c.dcrs, ic:ICON.database, sec:secAt(83)},
    {k:'Tables with data', v:c.tables, ic:ICON.database, sec:secAt(81)},
    {k:'Role assignments', v:c.rbac, ic:ICON.shieldCheck, sec:secAt(85)}
  ];
  const invHtml = inv.map(i=>'<div class="invc'+(i.sec!=null?' clickable" role="button" tabindex="0" data-jump="'+i.sec+'" title="Open in the Report tab':'')+'">'+
    (i.sec!=null?goArrow:'')+'<span class="iic">'+i.ic+'</span>'+
    '<div class="iv">'+i.v+'</div><div class="ik">'+esc(i.k)+'</div></div>').join('');
  cards.push('<div class="ipanel full"><h3>Content inventory</h3>'+
    '<p class="note">What is deployed in the workspace, at a glance.</p>'+
    '<div class="invg">'+invHtml+'</div></div>');

  // 7a. Incident outcomes (30d)
  if(M.incidentsByClassification && M.incidentsByClassification.length){
    const cc={TruePositive:'#dc2626',FalsePositive:'#d97706',BenignPositive:'#0d9488',Undetermined:'#64748b',Unclassified:'#94a3b8'};
    const items=M.incidentsByClassification.map(i=>({label:apiWords(i.label),value:+i.value||0,display:(+i.value||0).toLocaleString(),color:cc[i.label]||'#94a3b8'}));
    const tot=items.reduce((a,i)=>a+i.value,0);
    cards.push('<div class="ipanel"><h3>Incident outcomes ('+WIN.d()+')</h3>'+
      '<p class="note">How closed incidents were classified. Undetermined and unclassified closures give rule tuning nothing to work from.</p>'+
      donutMultiHtml(items,tot.toLocaleString(),'closed')+'</div>');
  }

  // 7b. Rule effectiveness (30d)
  if(M.effectiveness && M.effectiveness.length){
    const rows=M.effectiveness.map(e=>'<tr><td>'+esc(e.rule)+(e.source&&e.source!=='Analytics rule'?'<div class="note" style="margin:2px 0 0">'+esc(e.source)+'</div>':'')+'</td><td class="num">'+e.incidents+'</td><td class="num">'+e.closed+'</td>'+
      '<td class="num">'+e.tp+'</td><td class="num">'+e.fp+'</td><td class="num">'+e.fpRate+'%</td></tr>');
    cards.push('<div class="ipanel"><h3>Rule effectiveness ('+WIN.d()+')</h3>'+
      '<p class="note">Incidents per detection with their closure verdicts: Sentinel analytics rules first, then other products\' alerts (product shown under the name). FP rate is false positives over closed incidents.</p>'+
      (secRulePerf!=null
        ? '<table class="tbl"><thead><tr><th>Detection</th><th>Inc.</th><th>Closed</th><th>TP</th><th>FP</th><th>FP rate</th></tr></thead><tbody data-fill-list data-fill-total="'+rows.length+'">'+rows.slice(0,FILL_CAP).join('')+'</tbody></table>'+fillFoot(rows.length,secRulePerf,'detections')
        : moreTable('<table class="tbl"><thead><tr><th>Detection</th><th>Inc.</th><th>Closed</th><th>TP</th><th>FP</th><th>FP rate</th></tr></thead><tbody>'+trRows(rows,8)+'</tbody></table>',rows.length,8,'detections'))+'</div>');
  }

  // 7c. Daily ingestion trend (string-built SVG: area, line, average, three x labels)
  // opts.fit scales the axis to the values' own range rather than from
  // zero, so a change of a few points over weeks shows (the Progress tab);
  // a volume keeps its zero baseline.
  function trendHtml(points, opts){
    opts=opts||{}; const col=THEME[opts.theme]||THEME.brand; const unit=opts.unit||'';
    if(!points||points.length<2) return '<p class="note">Not enough points for a trend.</p>';
    const W=640,H=180,pl=44,pr=12,pt=14,pb=26;
    const vals=points.map(p=>+p.value||0); const vmax=Math.max(...vals), vmin=Math.min(...vals);
    const pad=opts.fit? Math.max((vmax-vmin)*0.15, Math.abs(vmax)*0.02, 0.01) : 0;
    const lo=opts.fit? vmin-pad : 0, max=opts.fit? vmax+pad : Math.max(vmax,0.01);
    const x=i=>pl+(W-pl-pr)*i/(points.length-1); const y=v=>pt+(H-pt-pb)*(1-(v-lo)/(max-lo));
    const line=vals.map((v,i)=>(i?'L':'M')+x(i).toFixed(1)+','+y(v).toFixed(1)).join(' ');
    const area=line+' L'+x(vals.length-1).toFixed(1)+','+y(lo).toFixed(1)+' L'+x(0).toFixed(1)+','+y(lo).toFixed(1)+' Z';
    const avg=vals.reduce((a,b)=>a+b,0)/vals.length;
    const lab=[0,Math.floor((points.length-1)/2),points.length-1].map(i=>'<text x="'+x(i).toFixed(1)+'" y="'+(H-8)+'" text-anchor="'+(i===points.length-1?'end':'middle')+'" font-size="10" fill="#9aa3af">'+esc(points[i].label)+'</text>').join('');
    return '<svg class="trend" viewBox="0 0 '+W+' '+H+'" role="img">'+
      '<path d="'+area+'" fill="'+col[0]+'" fill-opacity=".12"/><path d="'+line+'" fill="none" stroke="'+col[0]+'" stroke-width="2.2" stroke-linejoin="round"/>'+
      '<line x1="'+pl+'" y1="'+y(avg).toFixed(1)+'" x2="'+(W-pr)+'" y2="'+y(avg).toFixed(1)+'" stroke="'+col[1]+'" stroke-dasharray="4 4" stroke-width="1.2"/>'+
      '<text x="'+(W-pr)+'" y="'+(y(avg)-4).toFixed(1)+'" text-anchor="end" font-size="10" fill="'+col[1]+'">avg '+fmtN(avg)+unit+'</text>'+
      '<text x="'+(pl-6)+'" y="'+(pt+4)+'" text-anchor="end" font-size="10" fill="#9aa3af">'+fmtN(max)+unit+'</text>'+
      '<text x="'+(pl-6)+'" y="'+(y(lo)+4).toFixed(1)+'" text-anchor="end" font-size="10" fill="#9aa3af">'+(opts.fit? fmtN(lo)+unit : '0')+'</text>'+lab+'</svg>';
  }
