  // ---- tabs ----
  // A tab with data-tabs covers several views (Assessment: maturity and
  // findings); it reopens the one last shown.
  const lastOf={};
  const viewsOf=t=>(t.dataset.tabs||t.dataset.tab).split(' ');
  activateTab = function(name){
    curView=name; paintHeroCtx();
    document.querySelectorAll('.tab').forEach(x=>{ const on=viewsOf(x).includes(name); x.classList.toggle('active', on); if(on) lastOf[x.dataset.tab]=name; });
    document.querySelectorAll('[data-view]').forEach(el=>el.classList.toggle('hidden',el.dataset.view!==name));
    document.querySelectorAll('[data-views]').forEach(el=>el.classList.toggle('hidden',!el.dataset.views.split(' ').includes(name)));
    document.querySelectorAll('.subtab').forEach(x=>{ const on=x.dataset.sub===name; x.classList.toggle('active', on); x.setAttribute('aria-selected', on?'true':'false'); });
    balanceGrids(); markClamped();
    if(name==='sections') fillCards();
    if(name==='overview') fillQuickWins();
    if(name==='sectionsdoc' && window.layoutDoc) window.layoutDoc();
    // The Sankey was drawn while its tab was hidden: reveal it now.
    if(name==='flow' && big) revealSankey(big);
    if(typeof window.fitIframe==='function'){ window.fitIframe(); [60,180,400,800].forEach(t=>setTimeout(window.fitIframe,t)); }
  };
  document.querySelectorAll('.tab').forEach(t=>{
    const activate=()=>{ activateTab(lastOf[t.dataset.tab]||t.dataset.tab); bringTop(); };
    t.onclick=activate;
    t.tabIndex=0;
    t.onkeydown=e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); activate(); } };
  });
  document.querySelectorAll('.subtab').forEach(b=>{ b.onclick=()=>activateTab(b.dataset.sub); });
  // Each side of the switch carries its count.
  (function(){
    const setCount=(sub,text)=>{ const c=document.querySelector('.subtab[data-sub="'+sub+'"] .subcount'); if(c){ c.textContent=text; c.hidden=false; } };
    if(M.findings) setCount('findings', String(M.findings.items.length));
    if(M.maturity && M.maturity.overall && M.maturity.overall.score!=null) setCount('maturity', (+M.maturity.overall.score).toFixed(2)+' / 5');
  })();
  // After the slider's reload, reopen what was showing; the chosen window
  // stays for the next load.
  if(SAVED.back){
    saveWindow({days:WIN.days});
    const view=String(SAVED.view||'');
    if([...document.querySelectorAll('[data-view]')].some(el=>el.dataset.view===view)) activateTab(view);
    const doc=+SAVED.doc;
    if(view==='sectionsdoc' && gotoDocSection && (M.sections||[]).some(x=>x.num===doc)) gotoDocSection(doc);
  }
})();
