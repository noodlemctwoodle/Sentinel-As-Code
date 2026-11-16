  // ---- theme toggle ----
  const root=document.documentElement, TK='sac-theme';
  const saved=localStorage.getItem(TK);
  if(saved){ root.dataset.theme=saved; }
  else if(window.matchMedia&&matchMedia('(prefers-color-scheme: dark)').matches){ root.dataset.theme='dark'; }
  document.getElementById('themeBtn').onclick=()=>{
    const next=root.dataset.theme==='dark'?'light':'dark';
    root.dataset.theme=next; localStorage.setItem(TK,next);
    window.dispatchEvent(new Event('sac-theme'));
  };

  // ---- header ----
  const PRODUCT = M.product || 'iSOC Blueprint';
  const PRODUCT_SUB = 'Workspace documentation';
  // URL of a generated section page on the hosting SharePoint site, or null
  // when the dashboard is opened outside SharePoint (from disk, say). The
  // web part renders this page in a same-origin iframe, so the parent's
  // path tells us where the site's SitePages library is.
  function sitePageUrl(page){
    try{
      const p=window.parent.location; const i=p.pathname.toLowerCase().indexOf('/sitepages/');
      if(page && window.parent!==window && i>=0) return p.origin+p.pathname.substring(0,i)+'/SitePages/'+encodeURIComponent(page)+'.aspx';
    }catch(e){}
    return null;
  }
  document.getElementById('brandName').childNodes[0].nodeValue = PRODUCT;
  // The line under the product's name says when this was collected (the
  // provenance sits together: product, version, collection time).
  document.getElementById('brandSub').textContent = M.workspace&&M.workspace.generatedUtc? 'Collected '+fmtDate(M.workspace.generatedUtc,{time:true}) : PRODUCT_SUB;
  const w = M.workspace;
  // The header names the workspace (the product, its version and when this
  // was collected are the top bar's): where it lives (region, resource
  // group) above the name. No product label: the Blueprint is not only
  // Sentinel's.
  document.getElementById('title').textContent = w.name||PRODUCT;
  document.getElementById('heroEyebrow').innerHTML=[w.region? regionName(w.region) : '', w.resourceGroup||'']
    .filter(Boolean).map(s=>'<span>'+esc(s)+'</span>').join('');
  // The Blueprint version that built this, in the top bar by the product.
  const brandVer=document.getElementById('brandVer');
  if(brandVer && w.blueprintVer){ brandVer.textContent='v'+w.blueprintVer; brandVer.title='Built by iSOC Blueprint v'+w.blueprintVer; brandVer.hidden=false; }
  // How the workspace stands: the maturity score as a ring (amber below the
  // target level) and the open findings by severity; each opens its view
  // in the Assessment tab.
  const hMat=M.maturity&&M.maturity.overall, hMatOk=!!(hMat&&hMat.score!=null), hTarget=M.maturity&&M.maturity.targetLevel;
  const hSev=(M.findings&&M.findings.bySeverity)||{}, hC=+hSev.Critical||0, hW=+hSev.Warning||0, hI=+hSev.Info||0, hTotal=+(M.findings&&M.findings.total)||0;
  const hGo='<svg class="go" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14m-6-6 6 6-6 6"/></svg>';
  const heroFacts=document.getElementById('heroFacts');
  heroFacts.innerHTML=
    '<button type="button" class="hkpi" data-go="maturity"'+(hMatOk?'':' disabled')+' title="Open the maturity assessment">'+
      '<span class="hring" style="--p:'+(hMatOk? (+hMat.score/5*100).toFixed(1) : 0)+';--c:'+(hMatOk&&hTarget!=null&&+hMat.level<+hTarget? 'var(--amber)' : 'var(--brand)')+'"><b>'+(hMatOk? (+hMat.score).toFixed(2) : 'n/a')+'</b></span>'+
      '<span class="hkt"><span class="hkk">Maturity</span><span class="hkv">'+(hMatOk? esc(hMat.levelName||('Level '+hMat.level)) : 'Not assessed')+'</span>'+
      '<span class="hks">'+(hMatOk? 'Level '+esc(hMat.level)+' of 5'+(hTarget!=null? ', target '+esc(hTarget) : '') : 'No maturity.json in this run')+'</span></span>'+(hMatOk? hGo : '')+'</button>'+
    '<button type="button" class="hkpi" data-go="findings" title="Open the findings">'+
      '<span class="hbig">'+hTotal.toLocaleString('en-GB')+'</span>'+
      '<span class="hkt"><span class="hkk">Open findings</span>'+
      '<span class="hsev" aria-hidden="true">'+(hC?'<i class="c" style="flex:'+hC+'"></i>':'')+(hW?'<i class="w" style="flex:'+hW+'"></i>':'')+(hI?'<i class="n" style="flex:'+hI+'"></i>':'')+'</span>'+
      '<span class="hks">'+hC.toLocaleString('en-GB')+' critical &middot; '+hW.toLocaleString('en-GB')+' warning &middot; '+hI.toLocaleString('en-GB')+' info</span></span>'+hGo+'</button>';
  heroFacts.addEventListener('click',e=>{ const b=e.target.closest('[data-go]'); if(b && !b.disabled && activateTab) activateTab(b.dataset.go); });
  // The lead sentence under the name: what the view showing covers. A view
  // with its own registers it in HERO_CTX (Progress: the runs it compares);
  // the activity views name their days, and the Assessment and the Report
  // say they are as collected, whatever dates are chosen.
  const HERO_CTX={};
  function paintHeroCtx(){
    const el=document.getElementById('heroCtx'); if(!el) return;
    const v=curView;
    const yrs=WIN.startT!=null && new Date(WIN.startT).getUTCFullYear()!==new Date(WIN.endT).getUTCFullYear();
    const dates=WIN.startT==null? '' : WIN.startT===WIN.endT? fmtDate(WIN.endT) : fmtDate(WIN.startT,{year:yrs})+' to '+fmtDate(WIN.endT);
    const html= HERO_CTX[v]? HERO_CTX[v]() :
      ['overview','flow','sections'].includes(v)? 'Showing activity in <b>'+esc(WIN.span())+'</b>'+(dates? ', '+esc(dates) : '')+'.' :
      (v==='maturity'||v==='findings')? 'Assessed from the <b>'+esc(WIN.cw())+'</b> collected; the findings and the score do not follow the dates chosen.' :
      v==='sectionsdoc'? 'The full report as collected, over <b>'+esc(WIN.cw())+'</b>; it does not follow the dates chosen.' : '';
    el.innerHTML=html||''; el.hidden=!html;
  }
  paintHeroCtx();
  // Gap analysis is section 90; the findings tile opens it.
  const gapNum = (M.sections && (M.sections.find(s=>s.num===90) ||
                   M.sections.find(s=>/gap analysis/i.test(s.title)))||{}).num;
  // The footer: what produced this and that it must stay private.
  const genAt=String((M.workspace&&M.workspace.generatedUtc)||'').trim();
  document.getElementById('foot').innerHTML='<div class="privnote" role="note">'+
    '<span class="privicon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg></span>'+
    '<div><div class="privt">Confidential: tenant configuration</div>'+
    '<div class="privs">Generated by the iSOC Blueprint from this workspace'+(genAt? ' on '+esc(fmtDate(genAt,{time:true})) : '')+'. It holds workspace and subscription IDs, detection rules, role assignments and cost, so share it only as you would the workspace itself.</div></div></div>';

