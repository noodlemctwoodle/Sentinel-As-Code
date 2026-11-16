  // ---- glance stat tiles ----
  const c = M.counts, cost = M.cost;
  const findSecNum = (re, fb) => { const s=(M.sections||[]).find(x=>re.test(x.title||'')); return s?s.num:fb; };
  const secOverview = (((M.sections||[]).find(s=>s.num===0)) || (M.sections||[])[0] || {}).num;
  const secRetention = findSecNum(/retention/i, secOverview);
  const secCost = findSecNum(/monthly cost/i, secOverview);
  const secInventory = findSecNum(/workspace inventory/i, secOverview);
  const jumpTo = num => { if(num==null) return; if(activateTab) activateTab('sectionsdoc'); if(gotoDocSection) gotoDocSection(num); bringTop(); };
  // The pricing tier in words, the API's SKU name or the tier's size under it.
  const SKU_NAME={PerGB2018:'Pay-as-you-go', CapacityReservation:'Commitment tier', LACluster:'Dedicated cluster', Free:'Free tier',
    Standalone:'Standalone (legacy)', PerNode:'Per node (legacy)', Premium:'Premium (legacy)', Standard:'Standard (legacy)'};
  const skuCap=+w.skuCapacity||0;
  const skuSub=(w.sku==='CapacityReservation'||w.sku==='LACluster') && skuCap? skuCap.toLocaleString('en-GB')+' GB a day' : (SKU_NAME[w.sku]? w.sku : '');
  const pills = [
    {k:'Region', v:regionName(w.region)||'n/a', s:(w.region&&regionName(w.region)!==w.region? w.region : ''), ic:ICON.globe, sec:secOverview},
    {k:'SKU', v:SKU_NAME[w.sku]||w.sku||'n/a', s:skuSub, ic:ICON.tag, sec:secOverview},
    {k:'Retention', v:w.retentionDays+' days', ic:ICON.history, sec:secRetention},
    {k:'Daily cap', v:w.dailyCap, ic:ICON.gauge, sec:secInventory},
    {k:'Ingestion', v:w.pnaIngestion, ic:ICON.ingest, sec:secOverview},
    {k:'Monthly cost', v:cost? fmtMoney(cost.currency, cost.monthlyTotal):'n/a', s:cost? 'projected from '+WIN.span() : '', ic:ICON.coins, sec:secCost},
    {k:'Open findings', v:M.findings.total, ic:ICON.shieldAlert,
      badge:M.findings.total>0?'badge-red':'badge-green', sec:(gapNum!=null?gapNum:secOverview)},
    {k:'Maturity', v:(M.maturity&&M.maturity.overall&&M.maturity.overall.score!=null)? (M.maturity.overall.score+' / 5'):'n/a', ic:ICON.gauge,
      sec:((M.sections||[]).some(s=>s.num===91)?91:secOverview)},
    {k:'Alerts ('+WIN.d()+')', v:(M.estate? (M.estate.alerts||0).toLocaleString():'n/a'), ic:ICON.bolt, sec:findSecNum(/^analytics rules/i, secOverview)},
    {k:'Data lake', v:(M.dataLake? (M.dataLake.enrolled?'Enrolled':'Not enrolled'):'n/a'), ic:ICON.database, sec:findSecNum(/data lake/i, secOverview)}
  ];
  const goArrow = '<svg class="pgo" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m13 6 6 6-6 6"/></svg>';
  document.getElementById('heroPills').innerHTML = pills.map(p=>
    '<div class="pill'+(p.badge?' '+p.badge:'')+(p.sec!=null?' clickable':'')+'"'+
      (p.sec!=null?' role="button" tabindex="0" data-sec="'+p.sec+'" title="Open in the Report tab"':'')+'>'+
      (p.sec!=null?goArrow:'')+
      '<span class="kic">'+p.ic+'</span>'+
      '<div class="k">'+esc(p.k)+'</div>'+
      '<div class="v">'+esc(p.v)+'</div>'+(p.s?'<div class="s">'+esc(p.s)+'</div>':'')+'</div>').join('');
  document.querySelectorAll('#heroPills .pill.clickable').forEach(el=>{
    const n = +el.dataset.sec;
    el.addEventListener('click', ()=>jumpTo(n));
    el.addEventListener('keydown', e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); jumpTo(n); } });
  });

  // ---- posture cards ----
  const mitreTotal = M.mitre.length;
  const covPct = mitreTotal? Math.round(M.mitreCovered/mitreTotal*100):0;
  const outcomes = [
    {grad:'linear-gradient(135deg,#2563eb,#4f46e5)', ic:ICON.shieldCheck, h:'Detection coverage',
      big:M.mitreCovered+' / '+mitreTotal, unit:'MITRE ATT&CK tactics',
      s:c.rulesEnabled+' of '+c.rulesTotal+' analytics rules enabled', ring:covPct},
    {grad:'linear-gradient(135deg,#0d9488,#16a34a)', ic:ICON.pulse, h:'Operational health',
      big:M.health.pct+'%', unit:WIN.days+'-day success rate',
      s:M.health.totalEvents.toLocaleString()+' health events processed', ring:Math.round(M.health.pct)},
    {grad:'linear-gradient(135deg,#7c3aed,#9333ea)', ic:ICON.scale, h:'Cost &amp; governance',
      big:cost? fmtMoney(cost.currency, cost.monthlyTotal):'n/a', unit:cost?'per month at public list prices, projected from '+WIN.span():'',
      s:M.findings.total+' open findings &middot; '+c.rbac+' role assignments', ring:null}
  ];
  document.getElementById('outcomes').innerHTML = outcomes.map(o=>
    '<div class="outcome" style="background:'+o.grad+'">'+
      '<div class="row"><div><div class="oic">'+o.ic+'</div></div>'+
        (o.ring!=null?'<div class="ring" style="--p:'+o.ring+'"><span>'+o.ring+'%</span></div>':'')+'</div>'+
      '<h3 style="margin-top:14px">'+o.h+'</h3>'+
      '<div class="big">'+o.big+'</div>'+(o.unit?'<div class="unit">'+o.unit+'</div>':'')+
      '<div class="s">'+o.s+'</div></div>').join('');

  // ---- estate pipeline figures ----
  // The four pipeline measures as a strip under the estate flow (as the
  // alert lifecycle carries its figures): value of total, the share as a
  // bar in the ring's tone, and a click through to the page behind it.
  const E = M.estate || null;
  const ringTone = f => f>=.8 ? 'var(--green)' : (f>=.65 ? 'var(--brand)' : 'var(--amber)');
  (function(){
    const el=document.getElementById('estateRings');
    if(!E || !E.rings){ el.innerHTML='<p class="note">Estate pipeline not available in this snapshot.</p>'; return; }
    const R=E.rings;
    const defs=[
      {k:'ingestion', h:'Ingestion', unit:'tables still receiving data', s:'of the tables with data in '+WIN.span(), sec:findSecNum(/table plans/i,null)},
      {k:'detection', h:'Detection', unit:'active tables read by a rule', s:fmtN(E.uncoveredGb)+' GB ingested with no detection', sec:findSecNum(/detection opportunities/i,null)},
      {k:'alerts', h:(+E.alertsXdr||0)>0? 'Sentinel alerts' : 'Alerts', unit:'enabled rules that fired ('+WIN.d()+')', s:(E.ruleAlerts!=null? E.ruleAlerts : (E.alerts||0)).toLocaleString()+' Sentinel alerts in '+WIN.span(), sec:findSecNum(/^analytics rules/i,null)},
      // Defender XDR's alerts, as the flow splits them: their share of every
      // alert, in the Defender XDR colour (a share, not a score).
      ...((+E.alertsXdr||0)>0? [{k:'xdr', h:'Defender XDR alerts', unit:'of every alert ('+WIN.d()+')', s:'raised by Defender XDR and the Microsoft products feeding it', sec:findSecNum(/^alerts/i,null),
        ring:{value:+E.alertsXdr, max:+E.alerts||+E.alertsXdr, pct:Math.round(100*(+E.alertsXdr)/Math.max(+E.alerts||+E.alertsXdr,1))}, tone:famColor['Defender XDR']}] : []),
      {k:'incidents', h:'Incidents', unit:'closed of created ('+WIN.d()+')', s:(E.incidentsOpen||0).toLocaleString()+' still open', sec:findSecNum(/^incidents/i,null)}
    ];
    el.innerHTML=defs.map(d=>{
      const r=d.ring||R[d.k]||{value:0,max:0,pct:null};
      const pct=r.pct==null?null:Math.round(r.pct);
      const tone=d.tone||(pct==null?'var(--slate)':ringTone(pct/100));
      return '<div class="lc-kpi es-kpi"'+(d.sec!=null?' role="button" tabindex="0" data-sec="'+d.sec+'" title="Open in the Report tab"':'')+'>'+
        '<div class="k">'+esc(d.h)+'</div>'+
        '<div class="v">'+Number(r.value).toLocaleString()+'<small>/ '+Number(r.max).toLocaleString()+'</small>'+(pct==null?'':'<span class="es-pct" style="color:'+tone+'">'+pct+'%</span>')+'</div>'+
        '<div class="es-bar"><i style="width:'+(pct||0)+'%;background:'+tone+'"></i></div>'+
        '<div class="s">'+esc(d.unit)+'; '+esc(d.s)+'</div></div>';
    }).join('');
    el.querySelectorAll('[data-sec]').forEach(k=>{
      const n=+k.dataset.sec;
      k.addEventListener('click',()=>jumpTo(n));
      k.addEventListener('keydown',e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); jumpTo(n); } });
    });
  })();

