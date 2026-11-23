  // moreChev(total,label,cls): Show all as a chevron, for tables and the
  // chip lists in their cells (see .morechev); moreTable is moreWrap for a
  // table, with the chevron in its header row (under the table only if it
  // has no header).
  const SBTN_CHEV='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>';
  function moreChev(total,label,cls){
    const all='Show all '+total+(label?' '+label:'');
    return sbtn(SBTN_CHEV,'data-more data-all="'+esc(all)+'" data-less="Show fewer" aria-label="'+esc(all)+'" title="'+esc(all)+'" aria-expanded="false"',{icon:true,cls:'morechev'+(cls?' '+cls:'')});
  }
  function moreTable(inner,total,shown,label){
    if(total<=shown) return '<div class="morewrap">'+inner+'</div>';
    const inHead=inner.replace(/<\/th>(\s*)<\/tr>(\s*)<\/thead>/, ()=>moreChev(total,label)+'</th></tr></thead>');
    return '<div class="morewrap">'+(inHead!==inner ? inHead : inner+moreChev(total,label,'tfoot'))+'</div>';
  }
  const trRows=(rows,show)=>rows.map((r,i)=> i<show ? r : r.replace(/^<tr\b/,'<tr data-mr hidden')).join('');
  // A card holding one table that opens further rows carries that table's
  // chevron in its own top-right corner (in its header when it has one),
  // where it reads as the card's. A card with two such tables keeps each in
  // its table. Kept up as cards redraw (the matrix on a filter, say).
  let chevSeq=0, liftQueued=false;
  function liftChevrons(){
    document.querySelectorAll('.cardchev').forEach(c=>{ const w=document.getElementById(c.dataset.wrap); if(!w || !w.isConnected || !w.querySelector('[data-mr]')) c.remove(); });
    document.querySelectorAll('.morewrap table thead .morechev').forEach(ch=>{
      const card=ch.closest('.ipanel, .panel'); if(!card || card.querySelectorAll('table thead .morechev').length!==1) return;
      const wrap=ch.closest('.morewrap'); if(!wrap.id) wrap.id='mw'+(++chevSeq);
      card.querySelectorAll('.cardchev').forEach(c=>c.remove());
      ch.dataset.wrap=wrap.id; ch.classList.add('cardchev');
      const head=card.querySelector(':scope > .phead');
      if(head) head.appendChild(ch); else { ch.classList.add('abs'); card.classList.add('has-cardchev'); card.appendChild(ch); }
    });
  }
  new MutationObserver(()=>{ if(liftQueued) return; liftQueued=true; requestAnimationFrame(()=>{ liftQueued=false; liftChevrons(); }); }).observe(document.body,{childList:true,subtree:true});
  // longText(text): three visible lines and an Expand control when there is
  // more; semicolon-separated lists expand as a bulleted list.
  function longText(t){
    t=String(t==null?'':t); const parts=t.split(/;\s+/).filter(x=>x.trim()); const list=parts.length>=4;
    return '<div class="ltx'+(list?' aslist':'')+'"><div class="ltx-body">'+esc(t)+'</div>'+
      (list?'<ul class="ltx-list">'+parts.map(x=>'<li>'+esc(x.trim())+'</li>').join('')+'</ul>':'')+
      sbtn('Expand','data-ltx',{cls:'ltx-btn'})+'</div>';
  }
  // One card per finding; used by the Assessment tab's findings view and the Overview.
  // A maturity lift as maturity.json stores it (up to three decimals), so the
  // dashboard and the Markdown pages show the same number.
  function fmtLift(v){ return '+'+String(Math.round((+v||0)*1000)/1000); }
  // What closing a finding does to the maturity score: the lift and area of
  // each criterion it decides, or Not scored for a hygiene or cost check.
  function maturityChip(f){
    const links=f.maturity||[];
    if(!links.length) return '<span class="fchip" title="No maturity criterion reads this finding">Not scored</span>';
    return links.map(l=>{
      const lift=(l.lift!=null&&l.lift>0)? ' '+fmtLift(l.lift) : '';
      const tip=(l.shared?'One of the findings behind ':'Decides ')+l.criterionId+' '+(l.name||'')+(l.status?' ('+l.status+')':'');
      return '<span class="fchip" title="'+esc(tip)+'">Maturity '+esc(l.area)+esc(lift)+'</span>';
    }).join('');
  }
  function findingCard(f){
    return '<div class="fcard e-'+esc(f.severity)+'" data-fid="'+esc(f.id)+'">'+
      '<div class="fc-head"><span class="sev '+esc(f.severity)+'">'+esc(f.severity)+'</span><b class="fc-id">'+esc(f.id)+'</b><span class="fc-title">'+esc(f.title)+'</span>'+
      '<span class="fc-actions"><button type="button" class="sbtn icon fc-expand" data-fcx aria-label="Show the full text" title="Show the full text">'+SBTN_CHEV+'</button></span></div>'+
      '<div class="fc-meta">'+(f.category?'<span class="fchip">'+esc(f.category)+'</span>':'')+(f.area?'<span class="fchip">Area '+esc(f.area)+'</span>':'')+maturityChip(f)+'</div>'+
      '<div class="fc-body"><div class="fc-block"><div class="flabel">Evidence</div>'+longText(f.evidence||'')+'<div class="fc-link"></div></div>'+
      '<div class="fc-block"><div class="flabel">Remediation</div>'+longText(f.remediation||'')+'<div class="fc-link">'+(f.learn?'<a href="'+esc(f.learn)+'" target="_blank" rel="noopener">Microsoft Learn &rarr;</a>':'')+'</div></div></div></div>';
  }
  const rowsMore=(rows,show,tag)=>rows.map((r,i)=> i<show ? r : r.replace(new RegExp('^<'+tag+'\\b'),'<'+tag+' data-mr hidden')).join('');
  function markClamped(root){
    (root||document).querySelectorAll('.ltx').forEach(w=>{
      if(w.classList.contains('open')) return;
      const b=w.querySelector('.ltx-body'); if(!b||!b.clientHeight) return;
      w.classList.toggle('clamped', b.scrollHeight>b.clientHeight+2);
    });
    (root||document).querySelectorAll('.fcard').forEach(c=>c.classList.toggle('has-more', !!c.querySelector('.ltx.clamped')));
  }
  function toggleCard(card){
    const open=card.classList.toggle('open');
    card.querySelectorAll('.ltx').forEach(w=>{ w.classList.toggle('open',open); if(open) w.classList.add('clamped'); });
    if(!open) markClamped(card);
    const b=card.querySelector('.fc-expand'); if(b){ const t=open?'Show less':'Show the full text'; b.setAttribute('aria-label',t); b.setAttribute('title',t); }
    if(typeof window.fitIframe==='function') window.fitIframe();
  }
  document.addEventListener('click',e=>{
    const b=e.target.closest('[data-fcx]');
    if(b){ toggleCard(b.closest('.fcard')); return; }
    const body=e.target.closest('.fcard.has-more:not(.open) .fc-block .ltx.clamped .ltx-body');
    if(body && !e.target.closest('a')) toggleCard(body.closest('.fcard'));
  });
  document.addEventListener('click',e=>{
    const b=e.target.closest('[data-ltx]'); if(!b) return;
    const w=b.closest('.ltx'); const open=w.classList.toggle('open');
    b.textContent=open?'Collapse':'Expand'; if(open) w.classList.add('clamped');
    if(typeof window.fitIframe==='function') window.fitIframe();
  });
  window.addEventListener('resize',()=>markClamped());
  document.addEventListener('click',e=>{
    const b=e.target.closest('[data-more]'); if(!b) return;
    const wrap=b.dataset.wrap? document.getElementById(b.dataset.wrap) : b.closest('.morewrap'); if(!wrap) return;
    const open=wrap.classList.toggle('open');
    wrap.querySelectorAll('[data-mr]').forEach(el=>{ if(el.closest('.morewrap')===wrap) el.hidden=!open; });
    const label=open ? (b.dataset.less||'Show fewer') : b.dataset.all;
    if(b.classList.contains('morechev')){ b.setAttribute('aria-label',label); b.title=label; b.setAttribute('aria-expanded',String(open)); }
    else b.textContent=label;
    markClamped(wrap);
    if(typeof window.fitIframe==='function') window.fitIframe();
  });
  // Figures as the report pages write them (Private/Format-BlueprintText.ps1):
  // separators, and a fraction to two places with its trailing zero
  // (13,448.90), so a column of GB reads alike; fmtGb always two places,
  // <0.01 for a trace.
  const fmtN = n => { const r=Math.round((+n||0)*100)/100; return Number.isInteger(r)? r.toLocaleString('en-GB') : r.toLocaleString('en-GB',{minimumFractionDigits:2,maximumFractionDigits:2}); };
  const fmtGb = n => { const v=+n||0; return v>0&&v<0.005? '<0.01' : v.toLocaleString('en-GB',{minimumFractionDigits:2,maximumFractionDigits:2}); };
  // Dates as the report pages write them: 15 Oct 2026, or with the time
  // 15 Oct 2026 21:03 UTC. Fixed month names, so no browser writes Sept. A
  // date-only string is a UTC day; the build's 'yyyy-MM-dd HH:mm UTC' reads too.
  const MONTHS=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const toDate=v=>{ if(v instanceof Date) return v; if(typeof v==='number') return new Date(v);
    const s=String(v==null?'':v).trim(); const m=/^(\d{4}-\d{2}-\d{2})(?:[ T](\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?))?\s*(Z|UTC)?$/i.exec(s);
    return m? new Date(m[1]+'T'+(m[2]||'00:00')+'Z') : new Date(s); };
  const fmtDate=(v,o)=>{ o=o||{}; const d=toDate(v); if(isNaN(d)) return String(v==null?'':v);
    const two=x=>String(x).padStart(2,'0');
    return d.getUTCDate()+' '+MONTHS[d.getUTCMonth()]+(o.year===false?'':' '+d.getUTCFullYear())+(o.time? ' '+two(d.getUTCHours())+':'+two(d.getUTCMinutes())+' UTC' : ''); };
  // Azure regions by the names the portal shows (as Get-BlueprintRegionName).
  const REGION_NAME={eastus:'East US',eastus2:'East US 2',centralus:'Central US',northcentralus:'North Central US',southcentralus:'South Central US',
    westcentralus:'West Central US',westus:'West US',westus2:'West US 2',westus3:'West US 3',canadacentral:'Canada Central',canadaeast:'Canada East',
    brazilsouth:'Brazil South',brazilsoutheast:'Brazil Southeast',mexicocentral:'Mexico Central',chilecentral:'Chile Central',northeurope:'North Europe',
    westeurope:'West Europe',uksouth:'UK South',ukwest:'UK West',francecentral:'France Central',francesouth:'France South',
    germanywestcentral:'Germany West Central',germanynorth:'Germany North',switzerlandnorth:'Switzerland North',switzerlandwest:'Switzerland West',
    norwayeast:'Norway East',norwaywest:'Norway West',swedencentral:'Sweden Central',swedensouth:'Sweden South',polandcentral:'Poland Central',
    italynorth:'Italy North',spaincentral:'Spain Central',austriaeast:'Austria East',belgiumcentral:'Belgium Central',denmarkeast:'Denmark East',
    finlandcentral:'Finland Central',greececentral:'Greece Central',eastasia:'East Asia',southeastasia:'Southeast Asia',japaneast:'Japan East',
    japanwest:'Japan West',koreacentral:'Korea Central',koreasouth:'Korea South',australiaeast:'Australia East',australiasoutheast:'Australia Southeast',
    australiacentral:'Australia Central',australiacentral2:'Australia Central 2',newzealandnorth:'New Zealand North',centralindia:'Central India',
    southindia:'South India',westindia:'West India',jioindiawest:'Jio India West',jioindiacentral:'Jio India Central',indonesiacentral:'Indonesia Central',
    malaysiawest:'Malaysia West',taiwannorth:'Taiwan North',uaenorth:'UAE North',uaecentral:'UAE Central',qatarcentral:'Qatar Central',
    israelcentral:'Israel Central',saudiarabiaeast:'Saudi Arabia East',southafricanorth:'South Africa North',southafricawest:'South Africa West',
    usgovvirginia:'US Gov Virginia',usgovarizona:'US Gov Arizona',usgovtexas:'US Gov Texas'};
  const regionName=r=>{ const k=String(r||'').replace(/\s/g,'').toLowerCase(); return REGION_NAME[k]||String(r||''); };
  // A CamelCase API value in words: BenignPositive reads Benign positive.
  const apiWords=v=>{ const s=String(v==null?'':v); if(!/^[A-Za-z][A-Za-z0-9]*$/.test(s) || !/[a-z][A-Z]|[A-Z]{2}[a-z]/.test(s)) return s;
    const p=s.split(/(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/); return [p[0]].concat(p.slice(1).map(x=>/^[A-Z]{2,}$/.test(x)? x : x.toLowerCase())).join(' '); };
  // Money in its currency with thousands separators, whole units from a
  // thousand up; an unknown currency code keeps the code in front.
  const fmtMoney = (cur, v) => {
    const n=+v||0, d=Math.abs(n)>=1000? 0 : 2;
    try { return new Intl.NumberFormat('en-GB',{style:'currency',currency:String(cur||''),minimumFractionDigits:d,maximumFractionDigits:d}).format(n); }
    catch(e){ return (cur? cur+' ' : '')+n.toLocaleString('en-GB',{minimumFractionDigits:d,maximumFractionDigits:d}); }
  };
  const svg = p => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'+p+'</svg>';
  const ICON = {
    globe:svg('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.3 2.5 15.7 0 18M12 3c-2.5 2.3-2.5 15.7 0 18"/>'),
    tag:svg('<path d="M3 12V5a2 2 0 0 1 2-2h7l9 9-9 9-9-9Z"/><circle cx="7.5" cy="7.5" r="1.3"/>'),
    history:svg('<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 4v4h4"/><path d="M12 8v4l3 2"/>'),
    gauge:svg('<path d="M4 15a8 8 0 1 1 16 0"/><path d="M12 15l4-4"/><circle cx="12" cy="15" r="1.3"/>'),
    ingest:svg('<path d="M12 3v11m0 0 4-4m-4 4-4-4"/><path d="M4 20h16"/>'),
    coins:svg('<ellipse cx="9" cy="7" rx="6" ry="3"/><path d="M3 7v5c0 1.7 2.7 3 6 3s6-1.3 6-3V7"/><path d="M15 11.8c3.3.1 6 1.4 6 3.2 0 1.7-2.7 3-6 3-1.3 0-2.6-.2-3.6-.6"/>'),
    shieldAlert:svg('<path d="M12 3 5 6v5c0 4.2 2.9 7.6 7 9 4.1-1.4 7-4.8 7-9V6l-7-3Z"/><line x1="12" y1="8" x2="12" y2="12"/><circle cx="12" cy="15.5" r=".7"/>'),
    shieldCheck:svg('<path d="M12 3 5 6v5c0 4.2 2.9 7.6 7 9 4.1-1.4 7-4.8 7-9V6l-7-3Z"/><path d="m9 12 2 2 4-4"/>'),
    pulse:svg('<path d="M3 12h4l2 6 4-14 2 8h6"/>'),
    scale:svg('<path d="M12 3v18M7 21h10"/><path d="M6 7h12l-3 6a3 3 0 0 1-6 0L6 7Z"/><path d="M12 7 6 5m6 2 6-2"/>'),
    home:svg('<path d="M3 11.5 12 4l9 7.5"/><path d="M5 10v9a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-9"/>'),
    database:svg('<ellipse cx="12" cy="6" rx="7" ry="3"/><path d="M5 6v12c0 1.7 3.1 3 7 3s7-1.3 7-3V6"/><path d="M5 12c0 1.7 3.1 3 7 3s7-1.3 7-3"/>'),
    box:svg('<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>'),
    crosshair:svg('<circle cx="12" cy="12" r="7"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3"/>'),
    bolt:svg('<path d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z"/>'),
    flag:svg('<path d="M5 21V4m0 0 5 2 4-2 5 2v9l-5-2-4 2-5-2"/>'),
    doc:svg('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>'),
    arrow:svg('<path d="M5 12h14m-6-6 6 6-6 6"/>')
  };

