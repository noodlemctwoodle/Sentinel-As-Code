  // ---- findings list ----
  const sevs=[...new Set(M.findings.items.map(f=>f.severity))];
  const sevSel=document.getElementById('sevSelect'), catSel=document.getElementById('catSelect'), findQ=document.getElementById('findSearch');
  sevs.forEach(s=>{const o=document.createElement('option');o.value=s;o.textContent=s;sevSel.appendChild(o);});
  [...new Set(M.findings.items.map(f=>f.category).filter(Boolean))].sort().forEach(c=>{const o=document.createElement('option');o.value=c;o.textContent=c;catSel.appendChild(o);});
  const matSel=document.getElementById('matSelect'), areaSel=document.getElementById('areaSelect'), findClear=document.getElementById('findClear');
  // Areas: the maturity area each finding belongs to, from the rule, else
  // from its SAC-<AREA>-NN id ('-' when neither gives one).
  const fAreaNames={}; ((M.maturity&&M.maturity.areas)||[]).forEach(a=>fAreaNames[a.id]=a.name);
  M.findings.items.forEach(f=>(f.maturity||[]).forEach(m=>{ if(m.area&&m.areaName&&!fAreaNames[m.area]) fAreaNames[m.area]=m.areaName; }));
  const fArea=f=>{ if(f.area) return f.area; const m=/^SAC-([A-Z]+)-\d+$/.exec(f.id||''); return m?m[1]:'-'; };
  const fAreaLabel=id=>id==='-'?'No area':(fAreaNames[id]?id+' '+fAreaNames[id]:id);
  [...new Set(M.findings.items.map(fArea))].sort().forEach(a=>{const o=document.createElement('option');o.value=a;o.textContent=fAreaLabel(a);areaSel.appendChild(o);});
  function renderFindings(){
    const sv=sevSel.value, cv=catSel.value, mv=matSel.value, av=areaSel.value, q=(findQ.value||'').trim().toLowerCase();
    const scored=f=>(f.maturity||[]).length>0;
    const rows=M.findings.items.filter(f=>(!sv||f.severity===sv)&&(!cv||f.category===cv)&&(!av||fArea(f)===av)&&(!mv||(mv==='scored')===scored(f))&&(!q||(f.id+' '+(f.legacyId||'')+' '+f.title+' '+(f.evidence||'')+' '+(f.remediation||'')).toLowerCase().includes(q)));
    findClear.hidden=!(sv||cv||mv||av||q);
    const list=document.getElementById('findList');
    list.innerHTML=rows.length? rows.map(findingCard).join('') : '<p class="note" style="padding:16px 18px">No findings match.</p>';
    document.getElementById('findCount').textContent=rows.length+' of '+M.findings.items.length+' findings';
    markClamped(list);
  }
  const clearFindingFilters=()=>{ sevSel.value=''; catSel.value=''; matSel.value=''; areaSel.value=''; findQ.value=''; };
  sevSel.onchange=renderFindings; catSel.onchange=renderFindings; matSel.onchange=renderFindings; areaSel.onchange=renderFindings; findQ.addEventListener('input',renderFindings);
  findClear.onclick=()=>{ clearFindingFilters(); renderFindings(); };
  renderFindings();
  // Open the Assessment tab's findings view on one finding (used by the criteria cards).
  window.showFinding=function(id){ clearFindingFilters(); findQ.value=id; if(activateTab) activateTab('findings'); renderFindings();
    bringTop(document.querySelector('[data-view="findings"] .filters')); };

  // ---- findings summary: the same kind of picture the maturity view gives ----
  (function(){
    const el=document.getElementById('findingsBoard'); if(!el) return;
    const items=M.findings.items||[];
    if(!items.length){ el.innerHTML='<div class="panel"><div class="phead"><div><h2>No open findings</h2><p class="note">Every best-practice check that ran passed.</p></div></div></div>'; return; }
    const sevOrder=['Critical','Error','Warning','Info','Informational'];
    const sevCol={Critical:'#dc2626',Error:'#ea580c',Warning:'#d97706',Info:'#64748b',Informational:'#64748b'};
    const sevList=[...sevOrder.filter(s=>items.some(f=>f.severity===s)), ...[...new Set(items.map(f=>f.severity))].filter(s=>s&&!sevOrder.includes(s))];
    const colOf=s=>sevCol[s]||'#64748b';
    const sevRank=f=>{ const i=sevList.indexOf(f.severity); return i<0?99:i; };
    const scored=f=>(f.maturity||[]).length>0;
    const nScored=items.filter(scored).length;
    const pick=(k,v)=>'data-fk="'+k+'" data-fv="'+esc(v)+'"';
    function donut(rows,big,small){
      const total=rows.reduce((a,x)=>a+x.value,0)||1; let acc=0;
      const segs=rows.map(x=>{ const st=acc/total*360; acc+=x.value; return x.color+' '+st.toFixed(2)+'deg '+(acc/total*360).toFixed(2)+'deg'; }).join(',');
      return '<div class="piewrap"><div class="dms" style="--pie:conic-gradient('+segs+')"><div class="dmshole"><div><div class="dmsv">'+esc(big)+'</div><div class="dmsk">'+esc(small)+'</div></div></div></div>'+
        '<div class="pielegend">'+rows.map(x=>'<button type="button" class="fpick" '+pick(x.k,x.v)+' title="List these findings"><i style="background:'+x.color+'"></i>'+esc(x.label)+
          '<span class="pv">'+x.value+'</span><span class="pp">'+Math.round(x.value/total*100)+'%</span></button>').join('')+'</div></div>';
    }
    // Bars stacked by severity, one row per group; the longest row fills the track.
    function stacked(groupOf,labelOf,k){
      const keys=[...new Set(items.map(groupOf))];
      const rows=keys.map(g=>({g, n:items.filter(f=>groupOf(f)===g).length})).sort((a,b)=>b.n-a.n||String(a.g).localeCompare(String(b.g)));
      const max=Math.max(1,...rows.map(x=>x.n));
      return '<div class="fbars">'+rows.map(x=>{
        const segs=sevList.map(sv=>{ const n=items.filter(f=>groupOf(f)===x.g&&f.severity===sv).length;
          return n?'<span style="width:'+(n/max*100)+'%;background:'+colOf(sv)+'" title="'+esc(sv)+': '+n+'"></span>':''; }).join('');
        return '<div class="fbar" '+pick(k,x.g)+' title="List these findings"><div class="fl" title="'+esc(labelOf(x.g))+'">'+esc(labelOf(x.g))+'</div><div class="ft">'+segs+'</div><div class="fv">'+x.n+'</div></div>';
      }).join('')+'</div>';
    }
    const key='<div class="fkey">'+sevList.map(sv=>'<span><i style="background:'+colOf(sv)+'"></i>'+esc(sv)+'</span>').join('')+'</div>';
    let html='<div class="panel"><div class="phead"><div><h2>Open findings</h2><p class="note">'+items.length+' items from the best-practice gap analysis. Click a legend entry, a bar or a row to list those findings below.</p></div></div>'+
      '<div class="fsum"><div><h3>By severity</h3>'+donut(sevList.map(sv=>({label:sv,value:items.filter(f=>f.severity===sv).length,color:colOf(sv),k:'sev',v:sv})),String(items.length),'findings')+'</div>'+
      '<div><h3>Effect on the maturity score</h3>'+donut([
        {label:'Moves the score',value:nScored,color:'#2563eb',k:'mat',v:'scored'},
        {label:'Not scored',value:items.length-nScored,color:'#94a3b8',k:'mat',v:'unscored'}],String(nScored),'move the score')+
      '<p class="note" style="margin-top:10px">Not scored: hygiene and cost checks that no maturity criterion reads.</p></div></div></div>';
    html+='<div class="fgrid2">'+
      '<div class="panel"><div class="phead"><div><h2>By area</h2><p class="note">The maturity area each finding belongs to, split by severity.</p></div></div>'+key+stacked(fArea,fAreaLabel,'area')+'</div>'+
      '<div class="panel"><div class="phead"><div><h2>By category</h2><p class="note">The kind of problem each finding is, split by severity.</p></div></div>'+key+stacked(f=>f.category||'Other',g=>g,'cat')+'</div></div>';
    const impact=[]; items.forEach(f=>(f.maturity||[]).forEach(m=>impact.push({f,m})));
    impact.sort((a,b)=>((+b.m.lift||0)-(+a.m.lift||0))||(sevRank(a.f)-sevRank(b.f))||String(a.f.id).localeCompare(String(b.f.id)));
    if(impact.length){
      html+='<div class="panel"><div class="phead"><div><h2>Score impact</h2><p class="note">Every finding that decides a maturity criterion, ordered by how much closing it lifts the overall score. Shared: the criterion also needs other findings closed. '+
        (items.length-nScored===1?'1 further finding is a hygiene or cost check':(items.length-nScored)+' further findings are hygiene or cost checks')+' the score does not count.</p></div></div>'+
        moreTable('<table class="tbl"><thead><tr><th>Finding</th><th>Severity</th><th>Criterion</th><th>Area</th><th class="num">Lift</th></tr></thead><tbody>'+
          trRows(impact.map(x=>'<tr class="frow" '+pick('id',x.f.id)+' title="Show this finding"><td><b class="cid">'+esc(x.f.id)+'</b> '+esc(x.f.title)+'</td>'+
            '<td><span class="sev '+esc(x.f.severity)+'">'+esc(x.f.severity)+'</span></td>'+
            '<td><b class="cid">'+esc(x.m.criterionId)+'</b> '+esc(x.m.name)+(x.m.shared?' <span class="note">(shared)</span>':'')+'</td>'+
            '<td>'+esc(x.m.areaName||x.m.area)+'</td><td class="num">'+(x.m.lift!=null&&+x.m.lift>0?fmtLift(x.m.lift):'none')+'</td></tr>'),10)+
          '</tbody></table>',impact.length,10,'scored findings')+'</div>';
    }
    el.innerHTML=html;
    el.addEventListener('click',e=>{
      if(e.target.closest('[data-more]')) return;
      const t=e.target.closest('[data-fk]'); if(!t||!el.contains(t)) return;
      const k=t.dataset.fk, v=t.dataset.fv;
      clearFindingFilters();
      if(k==='sev') sevSel.value=v; else if(k==='cat') catSel.value=v; else if(k==='mat') matSel.value=v; else if(k==='area') areaSel.value=v; else if(k==='id') findQ.value=v;
      renderFindings();
      const bar=document.querySelector('[data-view="findings"] .filters'); if(bar) bar.scrollIntoView({behavior:'smooth',block:'start'});
    });
  })();

