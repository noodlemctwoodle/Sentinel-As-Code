  // ---- maturity board ----
  (function(){
    const el=document.getElementById('maturityBoard');
    if(!MAT){
      el.innerHTML='<div class="panel"><h2>Maturity not assessed</h2><p class="note">This snapshot has no maturity.json. The collector writes it after the gap analysis.</p></div>';
      return;
    }
    const sc=MAT.overall.score, tg=MAT.targetLevel;
    const pct=sc==null?0:Math.round(sc/5*100);
    const confCls=c=>c==='Good'?'good':(c==='Moderate'?'moderate':'');
    // The badge is the confidence in the score (how many of the area's
    // criteria this run could assess), not the score: it says so.
    const confText=c=>!c||c==='Not assessed'? (c||'n/a') : c+' confidence';
    const areaName={}; (MAT.areas||[]).forEach(a=>areaName[a.id]=a.name);
    function areaBarsHtml(areas,target){
      return '<div class="areabars">'+areas.map(a=>{
        const s=a.score==null?0:+a.score; const below=a.score!=null&&a.level<target;
        return '<div class="abar" style="--c1:'+(below?'#d97706':'#2563eb')+';--c2:'+(below?'#f59e0b':'#6d5efc')+'"><div class="al"><b>'+esc(a.id)+'</b> '+esc(a.name)+'</div>'+
          '<div class="at"><div class="af" style="--w:'+(s/5*100).toFixed(1)+'%"></div><div class="am" style="--t:'+(target/5*100)+'%"></div></div>'+
          '<div class="av">'+(a.score==null?'n/a':(+a.score).toFixed(2))+'</div><span class="matbadge '+confCls(a.confidence)+'" title="Confidence in this score: how many of the area\'s criteria this run could assess">'+esc(confText(a.confidence))+'</span></div>';
      }).join('')+'</div>';
    }
    let html='';
    html+='<div class="panel"><div class="phead"><div><h2>'+esc(MAT.methodology.name)+'</h2>'+
      '<p class="note">Eleven capability areas scored 0 to 5 from the gap outcomes and the captured configuration. Unknown criteria (inputs not captured in this run) never count against the workspace.</p></div></div>'+
      ((MAT.methodology.basis||MAT.methodology.scope)?'<div class="matscope">'+
        (MAT.methodology.basis?'<div class="ms"><div class="msh">'+ICON.scale+'Basis</div><p>'+esc(MAT.methodology.basis)+'</p></div>':'')+
        (MAT.methodology.scope?'<div class="ms"><div class="msh">'+ICON.crosshair+'Scope</div><p>'+esc(MAT.methodology.scope)+'</p></div>':'')+'</div>':'')+
      '<div class="donutwrap">'+donutHtml(pct, sc==null?'n/a':(+sc).toFixed(2)+' / 5', sc==null?'not assessed':MAT.overall.levelName)+
      '<div class="dlegend"><div class="di"><i style="background:var(--green)"></i>Met<b>'+MAT.totals.met+'</b></div>'+
      '<div class="di"><i style="background:var(--red)"></i>Gap<b>'+MAT.totals.gap+'</b></div>'+
      '<div class="di"><i style="background:var(--slate)"></i>Unknown<b>'+MAT.totals.unknown+'</b></div>'+
      '<div class="di" style="margin-top:6px"><i style="background:var(--amber)"></i>Target level '+tg+' ('+esc(MAT.targetLevelName)+')<b>'+
      (MAT.targetMet?'met':(MAT.areasBelowTarget||[]).length+' areas below')+'</b></div></div></div></div>';
    html+='<div class="panel"><div class="phead"><div><h2>Areas</h2><p class="note">Dashed marker = target level. Amber bars are below it. The badge is the confidence in the score: how many of the area\'s criteria this run could assess.</p></div></div>'+areaBarsHtml(MAT.areas||[],tg)+'</div>';
    html+='<div class="panel" id="maturityTrend" style="display:none"><div class="phead"><div><h2>Score over time</h2><p class="note">One point per published run.</p></div></div><div id="maturityTrendBody"></div></div>';
    if(MAT.csf&&MAT.csf.functions&&MAT.csf.functions.length){
      html+='<div class="panel"><div class="phead"><div><h2>NIST CSF 2.0 rollup</h2><p class="note">Criteria per function, by status.</p></div></div><div class="csfgrid">'+
        MAT.csf.functions.map(f=>'<div class="csfc"><h4>'+esc(f.id)+' '+esc(f.name)+'</h4>'+
          (f.criteria?donutMultiHtml([{label:'Met',value:f.met,color:'#16a34a'},{label:'Gap',value:f.gap,color:'#dc2626'},{label:'Unknown',value:f.unknown,color:'#64748b'}],String(f.criteria),'criteria'):'<p class="note">No criteria mapped.</p>')+'</div>').join('')+
        '</div><p class="note" style="margin-top:12px">'+esc(MAT.csf.source||'NIST CSF 2.0')+'. Subcategory identifiers are NIST\'s; the mapping and the outcome paraphrases are this project\'s own.</p></div>';
    }
    if(MAT.roadmap&&MAT.roadmap.length){
      html+='<div class="panel" id="matRoadmap"><div class="phead"><div><h2>Roadmap</h2><p class="note">Every gap ordered by how much closing it lifts the overall score, then by effort. Projected = the overall score after this and every entry above it.</p></div></div>'+
        moreTable('<table class="tbl"><thead><tr><th>#</th><th>Criterion</th><th>Area</th><th>Effort</th><th>Lift</th><th>Projected</th></tr></thead><tbody>'+
        trRows(MAT.roadmap.map(r=>'<tr class="frow" role="button" tabindex="0" data-crit="'+esc(r.criterionId)+'" title="Show this criterion and the findings behind it"><td>'+r.priority+'</td><td><b class="cid">'+esc(r.criterionId)+'</b> '+esc(r.name)+'<div class="note" style="margin:3px 0 0">'+longText(r.guidance||'')+'</div></td>'+
          '<td>'+esc(areaName[r.area]||r.area)+'</td><td>'+esc(r.effort)+'</td><td class="num">'+fmtLift(r.overallLift)+'</td><td class="num">'+(+r.projectedScore||0).toFixed(2)+'</td></tr>'),10)+
        '</tbody></table>',MAT.roadmap.length,10,'gaps')+'</div>';
    }
    html+='<div class="panel"><div class="phead"><div><h2>Criteria</h2><p class="note">Every criterion with its status and the evidence that decided it.</p></div>'+
      '<div class="filters" style="margin:0"><select id="matStatus"><option value="">All statuses</option><option>Met</option><option>Gap</option><option>Unknown</option></select>'+
      '<select id="matArea"><option value="">All areas</option>'+(MAT.areas||[]).map(a=>'<option value="'+esc(a.id)+'">'+esc(a.name)+'</option>').join('')+'</select>'+
      '<input type="search" class="docsearch" id="matSearch" placeholder="Search criteria…" style="margin:0;width:220px">'+
      '<button type="button" class="sbtn" id="matClear" hidden>Clear filters</button></div></div>'+
      '<div class="fcards" id="matList" style="margin-top:14px"></div></div>';
    el.innerHTML=html;
    const tb=el.querySelector('#matList'), sel=el.querySelector('#matStatus'), ar=el.querySelector('#matArea'), q=el.querySelector('#matSearch'), clr=el.querySelector('#matClear');
    const findingIds=new Set((M.findings&&M.findings.items||[]).map(f=>f.id));
    // The findings a criterion reads: each opens in the findings view with
    // its evidence, remediation and references.
    const findingsByCrit={};
    ((M.findings&&M.findings.items)||[]).forEach(f=>(f.maturity||[]).forEach(l=>{ (findingsByCrit[l.criterionId]||(findingsByCrit[l.criterionId]=[])).push(f); }));
    function critFindingLinks(c){
      const fl=(findingsByCrit[c.id]||[]).slice();
      if(findingIds.has(c.id) && !fl.some(f=>f.id===c.id)) fl.unshift({id:c.id,title:'Open finding'});
      if(!fl.length) return '';
      return '<div class="critfind"><span class="flabel">'+(fl.length===1?'Finding':'Findings')+'</span>'+fl.map(f=>sbtn(esc(f.id),'data-showfind="'+esc(f.id)+'" title="'+esc(f.title||'')+'"',{go:true})).join('')+'</div>';
    }
    function renderCriteria(){
      const st=sel.value, av=ar.value, s=(q.value||'').trim().toLowerCase();
      // A criterion id on its own (as a roadmap entry sets it) matches that
      // criterion only, not others whose text mentions it.
      const exact=!!s && (MAT.criteria||[]).some(c=>c.id.toLowerCase()===s);
      const rows=(MAT.criteria||[]).filter(c=>(!st||c.status===st)&&(!av||c.area===av)&&(!s||(exact? c.id.toLowerCase()===s : (c.id+' '+c.name+' '+(c.evidence||'')+' '+(c.guidance||'')+' '+(areaName[c.area]||c.area)).toLowerCase().includes(s))));
      if(clr) clr.hidden=!(st||av||s);
      tb.innerHTML=rows.map(c=>'<div class="fcard e-'+esc(c.status)+'" data-cid="'+esc(c.id)+'">'+
        '<div class="fc-head"><span class="st '+esc(c.status)+'">'+esc(c.status)+'</span><b class="fc-id">'+esc(c.id)+'</b><span class="fc-title">'+esc(c.name)+'</span>'+
        '<span class="fc-actions"><button type="button" class="sbtn icon fc-expand" data-fcx aria-label="Show the full text" title="Show the full text">'+SBTN_CHEV+'</button></span></div>'+
        '<div class="fc-meta"><span class="fchip">'+esc(areaName[c.area]||c.area)+'</span>'+(c.kind?'<span class="fchip">'+esc(c.kind)+'</span>':'')+(c.effort?'<span class="fchip">'+esc(c.effort)+' effort</span>':'')+'</div>'+
        '<p class="fc-impact">'+esc(c.impact||'')+'</p>'+
        '<div class="fc-body"><div class="fc-block"><div class="flabel">Evidence</div>'+longText(c.evidence||'')+'<div class="fc-link">'+critFindingLinks(c)+'</div></div>'+
        '<div class="fc-block"><div class="flabel">Guidance</div>'+longText(c.guidance||'')+'<div class="fc-link"></div></div></div></div>').join('')||'<p class="note" style="padding:16px 18px">No criteria match.</p>';
      tb.querySelectorAll('[data-showfind]').forEach(a=>a.addEventListener('click',()=>window.showFinding(a.dataset.showfind)));
      markClamped(tb);
      if(typeof window.fitIframe==='function') window.fitIframe();
    }
    sel.addEventListener('change',renderCriteria); ar.addEventListener('change',renderCriteria); q.addEventListener('input',renderCriteria); renderCriteria();
    if(clr) clr.onclick=()=>{ sel.value=''; ar.value=''; q.value=''; renderCriteria(); };
    // A roadmap entry or quick win filters the criteria list to its criterion,
    // as a finding does in the findings view: the card opens, with the
    // findings behind it, and Clear filters brings the full list back.
    // An area picked on the Overview's maturity card filters the criteria to it.
    // The Overview's quick wins open the roadmap when every one is showing.
    window.showRoadmap=function(){
      if(activateTab) activateTab('maturity');
      bringTop(document.getElementById('matRoadmap')||tb.closest('.panel'));
    };
    window.showMaturityArea=function(areaId){
      if(activateTab) activateTab('maturity');
      sel.value=''; q.value=''; ar.value=areaId; renderCriteria();
      bringTop(tb.closest('.panel'));
    };
    window.showCriterion=function(id){
      if(activateTab) activateTab('maturity');
      sel.value=''; ar.value=''; q.value=id; renderCriteria();
      const card=tb.querySelector('[data-cid]');
      if(card && !card.classList.contains('open')) toggleCard(card);
      if(card){ card.classList.remove('flash'); void card.offsetWidth; card.classList.add('flash'); }
      bringTop(tb.closest('.panel'));
    };
    el.querySelectorAll('tr[data-crit]').forEach(r=>{
      r.addEventListener('click',e=>{ if(e.target.closest('[data-ltx],[data-more],a,button')) return; window.showCriterion(r.dataset.crit); });
      r.addEventListener('keydown',e=>{ if(e.target===r && (e.key==='Enter'||e.key===' ')){ e.preventDefault(); window.showCriterion(r.dataset.crit); } });
    });
    // Score history: the publisher writes maturity-history.json beside the
    // live dashboard on the site. From disk there is nothing to read.
    try{
      if(SNAP.read){
        SNAP.read('maturity-history.json').then(h=>{
          const entries=(h&&h.entries)||[]; if(entries.length<2) return;
          const pts=entries.map(e=>({label:(e.publishedUtc||'').slice(0,10),value:(e.overall&&e.overall.score)||0}));
          document.getElementById('maturityTrendBody').innerHTML=trendHtml(pts,{theme:'indigo',unit:''});
          document.getElementById('maturityTrend').style.display='';
          if(typeof window.fitIframe==='function') window.fitIframe();
        }).catch(()=>{});
      }
    }catch(e){}
  })();

