  if(M.usageDaily && M.usageDaily.length>=2){
    const pts=M.usageDaily.map(u=>({label:(u.day||'').slice(5),value:u.billable}));
    cards.push('<div class="ipanel"><h3>Daily ingestion (billable GB)</h3>'+
      '<p class="note">'+M.usageDaily.length+' days from the Usage table. A step up that no connector change explains is the first sign of a runaway source.</p>'+
      trendHtml(pts,{theme:'teal',unit:' GB'})+'</div>');
  }

  // 7d. Detection opportunities (section 28)
  const opNum=(M.sections||[]).some(s=>s.num===28)?28:null;
  if(M.detectionOpportunities && M.detectionOpportunities.length){
    const PILLS=3;
    const rows=M.detectionOpportunities.map(o=>'<tr><td>'+esc(o.table)+'<div class="note" style="margin:2px 0 0">'+esc(o.family)+'</div></td><td class="num">'+fmtN(o.gb30d)+' GB</td><td>'+
      (o.templates&&o.templates.length? '<div class="oppl morewrap"><div class="chipl">'+o.templates.map((t,i)=>'<span class="tagpill"'+(i>=PILLS?' data-mr hidden':'')+(t.solution?' title="'+esc(t.solution+(t.installed===true?' (installed)':t.installed===false?' (solution not installed)':''))+'"':'')+'>'+esc(t.name)+(t.severity?' · '+esc(t.severity):'')+'</span>').join('')+'</div>'+
        (o.templates.length>PILLS?moreChev(o.templates.length,'templates'):'')+'</div>':'<span class="note">no template reads this table</span>')+'</td></tr>');
    cards.push('<div class="ipanel full"><h3>Detection opportunities</h3>'+
      '<p class="note">Tables with data that no enabled rule reads, with the undeployed, non-deprecated templates that would cover them.</p>'+
      // The first twelve here; every table on the report page.
      (opNum
        ? '<table class="tbl"><thead><tr><th>Table</th><th>GB / '+WIN.d()+'</th><th>Templates ready to enable</th></tr></thead><tbody>'+rows.slice(0,12).join('')+'</tbody></table>'+
          (rows.length>12? fillFoot(rows.length,opNum,'tables',false,true) : '')
        : moreTable('<table class="tbl"><thead><tr><th>Table</th><th>GB / '+WIN.d()+'</th><th>Templates ready to enable</th></tr></thead><tbody>'+trRows(rows,12)+'</tbody></table>',rows.length,12,'tables'))+'</div>');
  }

  // 7e. Playbook health (7d)
  if(M.playbookHealth && M.playbookHealth.runs7d>0){
    const ph=M.playbookHealth; const ok=ph.runs7d-ph.failed7d;
    const items=[{label:'Succeeded',value:ok,display:ok.toLocaleString()},{label:'Failed',value:ph.failed7d,display:ph.failed7d.toLocaleString(),cls:'sev-Critical'}];
    const fl=(ph.failing||[]).map(f=>({label:f.playbook,value:f.failed,display:f.failed+' of '+f.runs,cls:'sev-Critical'}));
    cards.push('<div class="ipanel"><h3>Playbook health ('+WIN.d()+')</h3>'+
      '<p class="note">'+ph.runs7d.toLocaleString()+' runs across '+ph.playbooks+' playbook'+(ph.playbooks===1?'':'s')+'; '+(ph.failing||[]).length+' with failures'+(ph.unavailable?'; run history unavailable for '+ph.unavailable:'')+'.</p>'+
      barsHtml(items,{theme:'teal'})+(fl.length?'<p class="note" style="margin:14px 0 8px">Failing playbooks</p>'+barsHtml(fl,{theme:'rose',fill:{sec:secAutomation,label:'failing playbooks'}}):'')+'</div>');
  }

  // 7f. Threat intelligence by source (30d)
  if(M.tiBySource && M.tiBySource.length){
    const pal=['#7a5a9e','#3b6fb0','#0d9488','#d97706','#64748b','#94a3b8'];
    const items=M.tiBySource.map((t,i)=>({label:t.source,value:+t.count||0,display:(+t.count||0).toLocaleString(),color:pal[i%pal.length]}));
    const tot=items.reduce((a,i)=>a+i.value,0);
    cards.push('<div class="ipanel"><h3>Threat intelligence by source ('+WIN.cd()+')</h3>'+
      '<p class="note">Indicators observed per feed'+((WIN.days!==WIN.collected||WIN.ago>0)? ', over the collected '+WIN.cw()+': the dates chosen at the top do not re-scope this card' : '')+'. One feed is a single point of failure for every TI detection.</p>'+
      donutMultiHtml(items,tot.toLocaleString(),'indicators')+'</div>');
  }

  // 7g. Sentinel data lake: enrolment, tier distribution, extended-retention tables
  if(M.dataLake){
    const DL=M.dataLake, T=DL.tiers||{};
    const lakeNum=findSecNum(/data lake/i, null);
    const tierItems=[
      {label:'Analytics only',value:+T.AnalyticsOnly||0,color:'#64748b'},
      {label:'Analytics + Lake mirror',value:+T.MirroredOnly||0,color:'#3b6fb0'},
      {label:'Analytics + Lake extended',value:+T.MirroredExtended||0,color:'#7c3aed'},
      {label:'Lake only',value:+T.LakeOnly||0,color:'#0d9488'}
    ].filter(i=>i.value>0).map(i=>({...i,display:i.value.toLocaleString()}));
    const ext=(DL.extendedTables||[]).map(t=>({label:t.table,value:t.lakeOnlyDays,display:t.lakeOnlyDays.toLocaleString()+' d'}));
    const status=DL.enrolled
      ? 'Enrolled'+(DL.region?' ('+esc(DL.region)+')':'')+': every Analytics-plan table is mirrored to the lake; '+(DL.extendedCount||0)+' table'+(DL.extendedCount===1?'':'s')+' keep data beyond analytics retention and '+((DL.signals&&DL.signals.lakeOnlyTables)||0)+' route to the lake only.'
      : 'Not enrolled: all '+(DL.operationalTables||0)+' operational tables stay on the analytics tier with no lake mirror.';
    const costLine=(DL.cost&&(+DL.cost.lakeGb>0||+DL.cost.lakeCost>0))?'<p class="note" style="margin:12px 0 0">Lake-only ingest '+fmtGb(DL.cost.lakeGb)+' GB in '+WIN.span()+' ('+esc(fmtMoney(DL.cost.currency,DL.cost.lakeCost))+' a month) beside '+fmtGb(DL.cost.analyticsGb)+' GB on Analytics ('+esc(fmtMoney(DL.cost.currency,DL.cost.analyticsCost))+' a month).</p>':'';
    cards.push('<div class="ipanel" id="dataLakePanel"><h3>Sentinel data lake</h3>'+
      // The button under the table list opens the data lake page; without a
      // list, the link sits in the description instead.
      '<p class="note">'+status+(lakeNum!=null&&!ext.length?sbtn('Open the data lake page','data-jump="'+lakeNum+'"',{go:true}):'')+'</p>'+
      (tierItems.length? donutMultiHtml(tierItems,String(DL.operationalTables||0),'tables') : '<p class="note">No operational tables to classify.</p>')+costLine+
      (ext.length?'<p class="note" style="margin:14px 0 8px">Top tables by lake-only retention</p>'+barsHtml(ext,{theme:'violet',fill:{sec:lakeNum,label:'tables',keep:true}}):'')+'</div>');
  }

  // Bands group cards of similar height so a long table never shares a row
  // with a short donut. Full-width panels separate the bands. A card whose
  // title is not listed lands in a trailing band rather than disappearing.
  const BANDS=[
    {titles:['Analytics rules enabled','Findings by severity','Findings by category','Incident outcomes','Billed vs data grant eligible','Ingestion by billing plan','Alert volume by severity','Threat intelligence by source']},
    {full:'Content inventory'},
    {titles:['Top tables by volume','Alerts by detection source','Operational health event mix','Playbook health','Daily ingestion']},
    {full:'Detection coverage by MITRE'},
    {full:'Detection opportunities'},
    {titles:['Rule effectiveness','Top alerting rules','Sentinel data lake']},
    {full:'What'}
  ];
  const titleOf=h=>{ const m=/<h3>(.*?)<\/h3>/.exec(h); return m? m[1].replace(/<[^>]+>/g,'').replace(/&amp;/g,'&').replace(/&rsquo;/g,'\u2019') : ''; };
  const pool=cards.map(h=>({h,t:titleOf(h),used:false}));
  const take=pred=>pool.filter(c=>!c.used&&pred(c.t)).map(c=>{ c.used=true; return c.h; });
  const out=[];
  BANDS.forEach(b=>{
    if(b.full){ out.push(...take(t=>t.startsWith(b.full))); return; }
    const members=[]; b.titles.forEach(tt=>members.push(...take(t=>t.startsWith(tt))));
    if(members.length) out.push('<div class="insights iband">'+members.join('')+'</div>');
  });
  const rest=pool.filter(c=>!c.used);
  const restFull=rest.filter(c=>/class="ipanel full"/.test(c.h)).map(c=>c.h), restCards=rest.filter(c=>!/class="ipanel full"/.test(c.h)).map(c=>c.h);
  if(restCards.length) out.push('<div class="insights iband">'+restCards.join('')+'</div>');
  out.push(...restFull);
  board.innerHTML = out.join('');
  board.querySelectorAll('[data-jump]').forEach(a=>a.addEventListener('click',()=>jumpTo(+a.dataset.jump)));
  board.querySelectorAll('[data-jump][role="button"]').forEach(a=>a.addEventListener('keydown',e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); jumpTo(+a.dataset.jump); } }));
  wireAttackGrid();
  fillCards();
  if(document.fonts && document.fonts.ready) document.fonts.ready.then(fillCards);
  let fillTimer=null;
  window.addEventListener('resize',()=>{ clearTimeout(fillTimer); fillTimer=setTimeout(fillCards,150); });

