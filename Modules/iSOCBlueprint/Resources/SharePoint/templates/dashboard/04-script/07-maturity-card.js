  // ---- maturity card + quick wins ----
  const MAT = M.maturity || null;
  const lvlNames = (MAT&&MAT.levels&&MAT.levels.length)? MAT.levels.map(l=>l.name) : ['Not in place','Initial','Developing','Established','Measured','Optimised'];
  (function(){
    const card=document.getElementById('maturityCard');
    if(MAT && MAT.overall && MAT.overall.score!=null){
      const sc=+MAT.overall.score, lv=MAT.overall.level, tg=MAT.targetLevel;
      const below=(MAT.areasBelowTarget||[]).length, total=(MAT.areas||[]).length;
      card.innerHTML='<div class="phead"><div><h2>Maturity</h2><p class="note">'+esc(MAT.methodology.name)+' v'+esc(MAT.methodology.version)+(MAT.methodology.basis?', based on SOC-CMM':'')+' &middot; scored from the Sentinel workspace only (configuration and '+WIN.cw()+' of activity); people and processes were not assessed.</p></div></div>'+
        '<div class="matbig">'+sc.toFixed(2)+'<small>/ 5 &middot; '+esc(MAT.overall.levelName)+'</small></div>'+
        '<div class="mat-band">'+lvlNames.map((n,i)=>'<div class="lvl'+(i===lv?' on':'')+(i===tg?' target':'')+'"><b>'+i+'</b>'+esc(n)+'</div>').join('')+'</div>'+
        '<div class="meter"><div class="mf" style="--w:'+(sc/5*100).toFixed(1)+'%"></div><div class="mt" style="--t:'+(tg/5*100)+'%"></div></div>'+
        '<div class="matcap">Target level '+tg+' ('+esc(MAT.targetLevelName)+'): '+(MAT.targetMet?'met in every area.':below+' of '+total+' areas below target.')+' '+
        MAT.totals.met+' criteria met &middot; '+MAT.totals.gap+' gaps &middot; '+MAT.totals.unknown+' unknown.</div>'+
        matAreasHtml(MAT.areas||[], tg)+
        sbtn('Open the assessment','data-go="maturity"',{go:true,cls:'btn'});
    } else {
      card.innerHTML='<div class="phead"><div><h2>Maturity</h2><p class="note">Not assessed in this snapshot.</p></div></div>'+
        '<p class="note">The collector writes maturity.json after the gap analysis. This run has none, or no criterion could be evaluated.</p>';
    }
    card.querySelectorAll('[data-go]').forEach(b=>b.addEventListener('click',()=>{ if(activateTab) activateTab(b.dataset.go); bringTop(); }));
    card.querySelectorAll('.ma[data-area]').forEach(r=>{
      const go=()=>{ if(typeof window.showMaturityArea==='function') window.showMaturityArea(r.dataset.area); };
      r.addEventListener('click',go);
      r.addEventListener('keydown',e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); go(); } });
    });
    const qw=document.getElementById('quickWins');
    if(MAT && MAT.quickWins && MAT.quickWins.length){
      const qwItems=MAT.quickWins.map((q,i)=>'<div class="qwi" role="button" tabindex="0" data-crit="'+esc(q.criterionId)+'" title="Show this criterion and the findings behind it"><span class="qwn">'+(i+1)+'</span><div><div class="qwt"><span class="cid">'+esc(q.criterionId)+'</span> &middot; '+esc(q.name)+'</div>'+
        '<div class="qwg">'+longText(q.guidance||'')+'</div></div><span class="qwl">'+esc(q.area)+' &middot; '+fmtLift(q.overallLift)+'</span></div>');
      const qwAll='Show all '+qwItems.length+' quick wins';
      qw.innerHTML='<div class="morewrap"><div class="qw">'+qwItems.join('')+'</div>'+
        sbtn(qwAll,'data-more data-all="'+qwAll+'" data-less="Show fewer" hidden',{cls:'qwfoot qwmore'})+
        sbtn('Open the roadmap','hidden',{go:true,cls:'qwfoot qwroad'})+'</div>';
      qw.querySelector('.qwroad').addEventListener('click',()=>{ if(typeof window.showRoadmap==='function') window.showRoadmap(); });
      qw.querySelectorAll('.qwi[data-crit]').forEach(r=>{
        const go=()=>{ if(typeof window.showCriterion==='function') window.showCriterion(r.dataset.crit); };
        r.addEventListener('click',e=>{ if(e.target.closest('[data-ltx],[data-more],a,button')) return; go(); });
        r.addEventListener('keydown',e=>{ if(e.target===r && (e.key==='Enter'||e.key===' ')){ e.preventDefault(); go(); } });
      });
    } else { qw.innerHTML='<p class="note">'+(MAT?'No Low-effort gaps remain; the rest of the roadmap is Medium or High effort.':'Not assessed in this snapshot.')+'</p>'; }
    fillQuickWins();
    if(document.fonts && document.fonts.ready) document.fonts.ready.then(fillQuickWins);
    let qwTimer=null;
    window.addEventListener('resize',()=>{ clearTimeout(qwTimer); qwTimer=setTimeout(fillQuickWins,150); });
  })();

