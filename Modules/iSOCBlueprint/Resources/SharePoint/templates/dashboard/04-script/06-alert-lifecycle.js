  // ---- alert lifecycle ----
  // The SOC at a glance, left to right: source families, the alerts raised
  // in Sentinel (its analytics reading those families, strand width = GB)
  // and in Defender XDR (its products, a strand per family, width =
  // alerts), the incidents those became, and
  // how the incidents ended (closed by an automation rule, by an analyst, in
  // Defender XDR, by another identity, or still open; strand width =
  // incidents). A snapshot from before the ClosedBy capture shows Closed as
  // one branch. The particles in the middle are decoration: alerts drawn in,
  // fewer incidents let out, in proportion.
  (function(){
    const stage=document.getElementById('lcStage'); if(!stage) return;
    const E=M.estate||{}, C=M.alertLifecycle||{};
    const ns='http://www.w3.org/2000/svg';
    const W=1200, H=420, cy=196, cx=600;
    const n0=v=>Number(v)||0;
    // Exact counts, never abbreviated.
    const num=v=>n0(v).toLocaleString('en-GB');
    const win=WIN.span();
    const sources=(E.sources||[]).filter(s=>s&&n0(s.gb)>0).sort((a,b)=>n0(b.gb)-n0(a.gb));
    const alerts=n0(E.alerts), incidents=n0(E.incidents), closed=n0(E.incidentsClosed), open=n0(E.incidentsOpen);
    // Two alert nodes when the model splits them and Defender XDR raised any;
    // one (as before) otherwise.
    const aSen=E.alertsSentinel!=null? n0(E.alertsSentinel) : alerts, aXdr=n0(E.alertsXdr), split=aXdr>0;
    const yS=split? cy-88 : cy, yX=cy+88;
    // Split, the alert nodes sit further left, so their figures stay clear
    // of the core's rings. Strands end (jx) clear of the widest figure: a
    // 32-unit figure runs about 9.6 units either side of centre per character.
    const half=v=>num(v).length*9.6;
    const ax=split? 424 : 436, jx=Math.round(ax-half(split? Math.max(aSen,aXdr) : alerts)-22);
    const xdrByFam={}; (E.productAlerts||[]).forEach(p=>{ xdrByFam[p.family]=(xdrByFam[p.family]||0)+n0(p.alerts); });
    const hasSec=n=>(M.sections||[]).some(s=>s.num===n)? n : null;
    // Severity in the Defender XDR colours: High orange-red, Medium amber, Low yellow, Informational grey.
    const SEV=[['High','H','#ff4d1f'],['Medium','M','#ffaa00'],['Low','L','#fff100'],['Informational','I','#8a8886']];
    const cb=C.closedBy;
    const branches=(cb? [
        {label:'Closed by automation', v:n0(cb.AutomationRule), col:'#2dd4bf', go:hasSec(60)},
        {label:'Closed by analysts', v:n0(cb.Analyst), col:'#60a5fa', go:hasSec(15)},
        {label:'Closed in Defender XDR', v:n0(cb.DefenderXdr), col:'#a78bfa', go:hasSec(15)},
        {label:'Closed by other identities', v:n0(cb.Other), col:'#94a3b8', go:hasSec(15)}
      ] : [{label:'Closed', v:closed, col:'#2dd4bf', go:hasSec(15)}]).concat([{label:'Open', v:open, col:'#f59e0b', go:hasSec(15), open:true}]);

    document.getElementById('lcNote').textContent=split
      ? 'Source families to the alerts raised on them in Sentinel and in Defender XDR, the incidents those became and how the incidents were closed, over '+win+
        '. Strand width is GB into Sentinel, alerts into Defender XDR and incidents on the right. Select any part to open its page.'
      : 'Source families to the alerts they raised, the incidents those became and how the incidents were closed, over '+win+
        '. Strand width is GB on the left and incidents on the right. Select any part to open its page.';

    const svg=document.createElementNS(ns,'svg');
    svg.setAttribute('viewBox','0 0 '+W+' '+H);
    svg.setAttribute('role','img');
    svg.setAttribute('aria-label', (split? num(aSen)+' Sentinel alerts, '+num(aXdr)+' Defender XDR alerts' : num(alerts)+' alerts')+' and '+num(incidents)+' incidents over '+win+': '+
      branches.map(b=>b.label.charAt(0).toLowerCase()+b.label.slice(1)+' '+num(b.v)).join(', ')+'.');
    stage.appendChild(svg);
    const mk=(tag,attrs,text,parent)=>{ const el=document.createElementNS(ns,tag); for(const k in attrs) el.setAttribute(k,attrs[k]); if(text!=null) el.textContent=text; (parent||svg).appendChild(el); return el; };
    const go=(g,fn,title)=>{ g.setAttribute('class','lc-node'); g.setAttribute('tabindex','0'); g.setAttribute('role','link'); mk('title',{},title,g);
      g.addEventListener('click',fn); g.addEventListener('keydown',e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); fn(); } }); };
    const defs=mk('defs',{});
    const glow=mk('filter',{id:'lcGlow',x:'-50%',y:'-50%',width:'200%',height:'200%'},null,defs);
    mk('feGaussianBlur',{stdDeviation:'4',result:'b'},null,glow);
    const merge=mk('feMerge',{},null,glow); mk('feMergeNode',{in:'b'},null,merge); mk('feMergeNode',{in:'SourceGraphic'},null,merge);
    const core=mk('radialGradient',{id:'lcCore'},null,defs);
    mk('stop',{offset:'0%',class:'lc-glowstop','stop-opacity':'.22'},null,core); mk('stop',{offset:'100%',class:'lc-glowstop','stop-opacity':'0'},null,core);

    // Decoration: faint arcs behind the sources, the core's glow and rings.
    [300,345,390].forEach((r,i)=>mk('circle',{cx:-150,cy:cy,r:r,fill:'none',stroke:'rgba(148,163,184,'+(0.07-i*0.015)+')','stroke-width':'1.2'}));
    mk('circle',{cx:cx,cy:cy,r:118,fill:'url(#lcCore)'});
    mk('circle',{cx:cx,cy:cy,r:92,fill:'none','stroke-width':'1','stroke-dasharray':'2 7',class:'lc-spin lc-ring'});
    mk('circle',{cx:cx,cy:cy,r:104,fill:'none','stroke-width':'6','stroke-dasharray':'40 26',class:'lc-spin rev lc-ring2'});

    // Sources: one strand each into the alerts node.
    const strand=(d,col,w,speed)=>{
      mk('path',{d:d,fill:'none',stroke:col,'stroke-width':w.toFixed(1),'stroke-linecap':'round',class:'lc-strand'});
      const f=mk('path',{d:d,class:'lc-flow',stroke:col,'stroke-width':Math.max(1,w*0.3).toFixed(1),'stroke-dasharray':'3 21'});
      f.style.animationDuration=speed.toFixed(1)+'s';
    };
    const maxGb=Math.max(1,...sources.map(s=>n0(s.gb)));
    const maxXdr=Math.max(1,...sources.map(s=>n0(xdrByFam[s.category])));
    const top=sources.length>1? 48 : cy, gap=sources.length>1? (H-96-10)/(sources.length-1) : 0;
    const srcG=mk('g',{});
    sources.forEach((s,i)=>{
      const y=top+i*gap, k=Math.sqrt(n0(s.gb)/maxGb), w=3+20*k, col=famColor[s.category]||'#64748b';
      strand('M214 '+y.toFixed(1)+' C 300 '+y.toFixed(1)+', 310 '+yS+', '+jx+' '+yS, col, w, 3.2-1.8*k);
      // The alerts Defender XDR's products raised on this family.
      const xa=split? n0(xdrByFam[s.category]) : 0;
      if(xa>0){ const kx=Math.sqrt(xa/maxXdr); strand('M214 '+y.toFixed(1)+' C 290 '+y.toFixed(1)+', 300 '+yX+', '+jx+' '+yX, col, 2+12*kx, 3.2-1.8*kx); }
      mk('circle',{cx:210,cy:y,r:3.5,fill:col,filter:'url(#lcGlow)'},null,srcG);
      mk('text',{x:198,y:y-2,'text-anchor':'end','font-size':'13',class:'lc-src'},s.category,srcG);
      mk('text',{x:198,y:y+13,'text-anchor':'end','font-size':'10.5',class:'lc-sub'},fmtGb(n0(s.gb))+' GB',srcG);
    });
    if(sources.length){ go(srcG,()=>{ if(activateTab) activateTab('flow'); bringTop(); },'Open the data flow'); }
    else mk('text',{x:140,y:cy,'text-anchor':'middle','font-size':'12',class:'lc-sub'},'No billable ingestion');
    mk('text',{x:198,y:22,'text-anchor':'end','font-size':'10',class:'lc-lbl'},'DATA SOURCES');
    mk('circle',{cx:jx+4,cy:yS,r:4,class:'lc-junction',filter:'url(#lcGlow)'});
    if(split) mk('circle',{cx:jx+4,cy:yX,r:4,class:'lc-junction',filter:'url(#lcGlow)'});

    // Alerts and incidents nodes either side of the core.
    const bigNode=(x,value,label,title,fn,sub,y)=>{
      y=y==null? cy : y;
      const g=mk('g',{});
      // The figure's digits are centred on the node's line (y), so a strand
      // or junction beside it meets its middle.
      mk('rect',{x:x-66,y:y-27,width:132,height:sub?74:62,rx:10,fill:'transparent',class:'lc-hit'},null,g);
      mk('text',{x:x,y:y+11,'text-anchor':'middle','font-size':'32',class:'lc-num'},num(value),g);
      mk('text',{x:x,y:y+31,'text-anchor':'middle','font-size':'10.5',class:'lc-lbl'},label,g);
      if(sub) mk('text',{x:x,y:y+47,'text-anchor':'middle','font-size':'10.5',class:'lc-sub'},sub,g);
      if(fn) go(g,fn,title);
    };
    const alertsSec=hasSec(16), incSec=hasSec(15);
    if(split){
      bigNode(ax,aSen,'SENTINEL ALERTS','Open the alerts page',alertsSec!=null? ()=>jumpTo(alertsSec) : null,null,yS);
      bigNode(ax,aXdr,'DEFENDER XDR ALERTS','Open the alerts page',alertsSec!=null? ()=>jumpTo(alertsSec) : null,null,yX);
    }
    else bigNode(ax,alerts,'ALERTS','Open the alerts page',alertsSec!=null? ()=>jumpTo(alertsSec) : null);
    bigNode(764,incidents,'INCIDENTS','Open the incidents page',incSec!=null? ()=>jumpTo(incSec) : null,
      incidents>0? '1 per '+(alerts/incidents>=10? Math.round(alerts/incidents) : (alerts/incidents).toFixed(1))+' alerts' : null);

    // Outcomes: one strand per branch from the incidents node, from a
    // junction clear of its figure.
    const ix=Math.round(764+half(incidents)+18);
    const bTop=branches.length>1? 58 : cy, bGap=branches.length>1? (H-116-20)/(branches.length-1) : 0;
    branches.forEach((b,i)=>{
      const y=bTop+i*bGap, k=incidents>0? Math.sqrt(b.v/incidents) : 0, w=b.v>0? 2.5+22*k : 1;
      mk('circle',{cx:ix,cy:cy,r:4,class:'lc-junction',filter:'url(#lcGlow)'});
      strand('M'+(ix+2)+' '+cy+' C '+(ix+50)+' '+cy+', '+(ix+60)+' '+y.toFixed(1)+', 932 '+y.toFixed(1), b.col, w, 3.4-1.8*k);
      const g=mk('g',{});
      mk('rect',{x:928,y:y-24,width:266,height:b.open&&C.openBySeverity?66:48,rx:8,fill:'transparent',class:'lc-hit'},null,g);
      mk('circle',{cx:940,cy:y,r:7,fill:b.col,filter:'url(#lcGlow)'},null,g);
      mk('text',{x:958,y:y+7,'font-size':'22',class:'lc-num'},num(b.v),g);
      mk('text',{x:958,y:y+22,'font-size':'10',class:'lc-lbl'},b.label.toUpperCase(),g);
      if(b.open && C.openBySeverity){
        let x=958;
        SEV.forEach(([key,letter,col])=>{ const v=n0(C.openBySeverity[key]); if(!v) return;
          const t=letter+' '+v, wd=12+t.length*6.4;
          mk('rect',{x:x,y:y+30,width:wd,height:16,rx:4,fill:col},null,g);
          mk('text',{x:x+wd/2,y:y+42,'text-anchor':'middle','font-size':'10.5','font-weight':'800',fill:'#0b1220'},t,g);
          x+=wd+6; });
      }
      if(b.go!=null) go(g,()=>jumpTo(b.go),'Open the '+(b.go===60?'automation':'incidents')+' page');
    });

    // The core's particles: a canvas over the stage, drawn in viewBox units.
    const canvas=document.createElement('canvas'); stage.appendChild(canvas);
    const ctx=canvas.getContext('2d');
    const still=window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    const rnd=(a,b)=>a+Math.random()*(b-a);
    const ring=[]; for(let i=0;i<300;i++){ const r=rnd(12,88); ring.push({r:r, a:rnd(0,6.283), s:(r<50?1:-1)*rnd(0.002,0.007), z:rnd(0.9,2.1), g:Math.random()<0.25}); }
    const ratio=incidents>0? Math.min(1,Math.max(0.08,incidents/Math.max(alerts,1))) : 0.08;
    // Alerts drawn in from each alert node, in proportion to its alerts.
    const shareX=split? Math.min(0.85,Math.max(0.15,aXdr/Math.max(alerts,1))) : 0;
    const from=()=>Math.random()<shareX? yX : yS;
    const inflow=[]; for(let i=0;i<36;i++) inflow.push({t:Math.random(), y:rnd(-26,26), y0:from(), s:rnd(0.004,0.009)});
    const outflow=[]; for(let i=0;i<Math.max(3,Math.round(36*ratio));i++) outflow.push({t:Math.random(), y:rnd(-10,10), s:rnd(0.003,0.006)});
    let scale=1;
    function size(){ const r=canvas.getBoundingClientRect(); if(!r.width) return; const dpr=window.devicePixelRatio||1;
      canvas.width=Math.round(r.width*dpr); canvas.height=Math.round(r.height*dpr); scale=r.width/W; ctx.setTransform(scale*dpr,0,0,scale*dpr,0,0); }
    // Additive light on the dark screen; plain, deeper colours on light,
    // where adding light to white would wash the particles out.
    const PAL_DARK={teal:'94,234,212', green:'134,239,172', red:'248,113,113', mode:'lighter'};
    const PAL_LIGHT={teal:'13,148,136', green:'22,163,74', red:'220,38,38', mode:'source-over'};
    function frame(){
      const P=document.documentElement.dataset.theme==='dark'? PAL_DARK : PAL_LIGHT;
      ctx.clearRect(0,0,W,H);
      ctx.globalCompositeOperation=P.mode;
      ring.forEach(p=>{ if(!still) p.a+=p.s; const x=cx+p.r*Math.cos(p.a), y=cy+p.r*Math.sin(p.a)*0.94;
        ctx.fillStyle=p.g? 'rgba('+P.green+','+(0.85-p.r/120)+')' : 'rgba('+P.teal+','+(0.9-p.r/110)+')';
        ctx.beginPath(); ctx.arc(x,y,p.z,0,6.283); ctx.fill(); });
      inflow.forEach(p=>{ if(!still){ p.t+=p.s; if(p.t>1){ p.t=0; p.y=rnd(-26,26); p.y0=from(); } }
        const x0=split? 486 : 474, x=x0+(cx-22-x0)*p.t, y=p.y0+(cy-p.y0)*p.t+(split? p.y*0.4 : p.y)*(1-p.t);
        ctx.fillStyle='rgba('+P.red+','+(0.25+0.5*p.t)+')'; ctx.beginPath(); ctx.arc(x,y,1.4,0,6.283); ctx.fill(); });
      outflow.forEach(p=>{ if(!still){ p.t+=p.s; if(p.t>1){ p.t=0; p.y=rnd(-10,10); } }
        const x=cx+22+(726-cx-22)*p.t, y=cy+p.y*p.t;
        ctx.fillStyle='rgba('+P.teal+','+(0.9-0.6*p.t)+')'; ctx.beginPath(); ctx.arc(x,y,1.8,0,6.283); ctx.fill(); });
      ctx.globalCompositeOperation='source-over';
    }
    size(); frame();
    if(window.ResizeObserver) new ResizeObserver(()=>{ size(); frame(); }).observe(stage);
    window.addEventListener('sac-theme',frame);
    if(!still){
      // Skip drawing while the Overview is not on screen (another tab is
      // open, or the page is hidden); the loop itself costs nothing then.
      const loop=()=>{ if(!document.hidden && stage.offsetParent!==null){ if(!canvas.width) size(); frame(); } requestAnimationFrame(loop); };
      requestAnimationFrame(loop);
    }

    // The strip under the picture.
    // Every GB ingested a day, billable and free; the split is under it, as
    // the findings and the Progress tab quote the billable figure.
    const daily=(M.usageDaily||[]).map(d=>n0(d.billable)+n0(d.free));
    const avg=daily.length? daily.reduce((a,b)=>a+b,0)/daily.length : null;
    const avgOf=k=>(M.usageDaily||[]).reduce((a,d)=>a+n0(d[k]),0)/Math.max(1,(M.usageDaily||[]).length);
    const spark=pts=>{ if(pts.length<2) return ''; const mx=Math.max(...pts,0.001), w=200, h=30;
      const xy=pts.map((v,i)=>(i/(pts.length-1)*w).toFixed(1)+','+(h-2-(v/mx)*(h-4)).toFixed(1)).join(' ');
      return '<svg class="lc-spark" viewBox="0 0 '+w+' '+h+'" preserveAspectRatio="none" aria-hidden="true"><polyline points="'+xy+'" fill="none" stroke-width="1.6" vector-effect="non-scaling-stroke"/></svg>'; };
    const dur=m=>m==null? 'n/a' : m<60? Math.round(m)+'<small>min</small>' : m<1440? (m/60).toFixed(1)+'<small>hours</small>' : (m/1440).toFixed(1)+'<small>days</small>';
    const auto=cb? n0(cb.AutomationRule) : null;
    const chips=C.openBySeverity? '<div class="lc-chips">'+SEV.map(([key,letter,col])=>{ const v=n0(C.openBySeverity[key]); return v? '<span class="lc-chip" style="background:'+col+'" title="'+key+'">'+letter+' '+v+'</span>' : ''; }).join('')+'</div>' : '';
    // Incidents over the window, like the ingestion card beside it: the
    // average a day, and a line per severity (Defender XDR colours) of the
    // incidents each day, oldest on the left, on one scale; how many are
    // still open sits under it (the open branch above splits them by
    // severity). An incident counts on the day it was last updated, which
    // for a closed one is the day it closed. Past three weeks each line is
    // a trailing 7-day average, so the trend reads rather than the weekly
    // swing. A model without the daily series keeps the open count and its
    // severity chips.
    const incTrend=(function(){
      const D=M.daily; if(!D || !Array.isArray(D.incidents)) return null;
      const n=WIN.days, by={};
      D.incidents.forEach(i=>{ const a=by[i.sev]||(by[i.sev]=Array(n).fill(0));
        (i.d||[]).forEach(e=>{ const k=+e[0]; if(k>=0 && k<n) a[k]+=n0(e[1]); }); });
      const smooth=n>21;
      const ma=a=>a.map((v,i)=>{ const lo=Math.max(0,i-6), s=a.slice(lo,i+1); return s.reduce((x,y)=>x+y,0)/s.length; });
      const lines=SEV.filter(([key])=>by[key] && by[key].some(v=>v>0)).map(([key,letter,col])=>{ const raw=by[key].slice().reverse(); return {key, letter, col, raw, pts:smooth? ma(raw) : raw}; });
      if(!lines.length) return null;
      const total=lines.reduce((t,l)=>t+l.raw.reduce((a,b)=>a+b,0),0);
      const mx=Math.max(...lines.map(l=>Math.max(...l.pts)),1), w=200, h=30;
      const path=l=>l.pts.map((v,i)=>(n<2? 0 : i/(n-1)*w).toFixed(1)+','+(h-2-(v/mx)*(h-4)).toFixed(1)).join(' ');
      const tip=WIN.w()+(smooth? ' (7-day average lines)' : '')+': '+lines.map(l=>l.letter+' '+l.raw.reduce((a,b)=>a+b,0).toLocaleString('en-GB')).join(', ');
      const avg=total/n;
      return {
        value: (avg>=10? Math.round(avg).toLocaleString('en-GB') : avg.toFixed(1))+'<small>a day</small>',
        chart: '<svg class="lc-sev" viewBox="0 0 '+w+' '+h+'" preserveAspectRatio="none" role="img" aria-label="'+esc('Incidents a day by severity, '+tip)+'"><title>'+esc(tip)+'</title>'+
          lines.map(l=>'<polyline points="'+path(l)+'" fill="none" stroke="var(--lc-halo)" stroke-width="3" vector-effect="non-scaling-stroke"/>'+
            '<polyline points="'+path(l)+'" fill="none" stroke="'+l.col+'" stroke-width="1.6" vector-effect="non-scaling-stroke"/>').join('')+'</svg>'+
          '<div class="lc-axis"><span>'+esc(WIN.d())+' ago</span><span>Today</span></div>'
      };
    })();
    document.getElementById('lcStrip').innerHTML=
      '<div class="lc-kpi"><div class="k">Data ingestion</div><div class="v">'+(avg==null?'n/a':fmtGb(avg)+'<small>GB a day</small>')+'</div>'+
        (avg==null? '' : '<div class="s">'+fmtGb(avgOf('billable'))+' billable and '+fmtGb(avgOf('free'))+' free</div>')+spark(daily)+'</div>'+
      '<div class="lc-kpi"><div class="k">Alerts per incident</div><div class="v">'+(incidents>0?(alerts/incidents>=10?Math.round(alerts/incidents):(alerts/incidents).toFixed(1)):'n/a')+'</div><div class="s">'+
        (split? num(aSen)+' Sentinel, '+num(aXdr)+' XDR alerts' : num(alerts)+' alerts, '+num(incidents)+' incidents')+'</div></div>'+
      (incTrend? '<div class="lc-kpi"><div class="k">Incidents</div><div class="v">'+incTrend.value+'</div>'+incTrend.chart+'<div class="s">'+num(open)+' still open</div></div>'
               : '<div class="lc-kpi"><div class="k">Open incidents</div><div class="v">'+num(open)+'</div>'+chips+'</div>')+
      '<div class="lc-kpi"><div class="k">Mean time to resolve</div><div class="v">'+dur(C.mttrMinutes)+'</div><div class="s">Closed incidents, '+win+'</div></div>'+
      '<div class="lc-kpi"><div class="k">Closed by automation</div><div class="v">'+(auto==null? 'n/a' : closed>0? Math.round(auto/closed*100)+'<small>%</small>' : '0<small>%</small>')+'</div><div class="s">'+
        (auto==null? 'Not captured in this snapshot' : num(auto)+' of '+num(closed)+' closed')+'</div></div>';
  })();

  // Each capability area's score against the target, weakest first, for the
  // Overview's maturity card; an area below the target is amber, and a row
  // opens the Assessment with the criteria filtered to that area.
  function matAreasHtml(areas, tg){
    const scored=areas.filter(a=>a.score!=null).slice().sort((a,b)=>(+a.score)-(+b.score)||String(a.name).localeCompare(String(b.name)));
    const unscored=areas.filter(a=>a.score==null);
    if(!scored.length) return '';
    const row=a=>{ const s=+a.score, below=a.level<tg;
      return '<div class="ma'+(below?' below':'')+'" role="button" tabindex="0" data-area="'+esc(a.id)+'" title="'+esc(a.name+': '+s.toFixed(2)+' of 5'+(below?', below the target':'')+'. Show its criteria')+'">'+
        '<span class="man">'+esc(a.name)+'</span><span class="mab"><i style="--w:'+(s/5*100).toFixed(1)+'%"></i><b style="--t:'+(tg/5*100)+'%"></b></span><span class="mav">'+s.toFixed(1)+'</span></div>'; };
    return '<div class="mat-areas"><div class="mah">By area, weakest first</div>'+scored.map(row).join('')+
      (unscored.length? '<div class="mau">Not assessed: '+unscored.map(a=>esc(a.name)).join(', ')+'</div>' : '')+'</div>';
  }

  // fillQuickWins: the quick wins beside the maturity card show QW_MIN
  // entries, then as many more as fit without growing past that card, so
  // the two end level with their buttons in line. The rest sit behind Show
  // all; when every quick win fits, the button opens the roadmap instead.
  // Stacked on a narrow screen there is nothing to match, so QW_STACKED
  // show. Runs with the Overview shown, on resize and once fonts load.
  const QW_MIN=3, QW_STACKED=5;
  function fillQuickWins(){
    const card=document.getElementById('quickWinsCard'), mat=document.getElementById('maturityCard');
    const list=card&&card.querySelector('.qw'); if(!list || !mat || !card.clientWidth) return;
    const wrap=list.closest('.morewrap'); if(wrap.classList.contains('open')) return;
    const items=[...list.children], more=card.querySelector('.qwmore'), road=card.querySelector('.qwroad');
    const set=n=>{
      items.forEach((r,i)=>{ r.hidden=i>=n; if(i>=n) r.setAttribute('data-mr',''); else r.removeAttribute('data-mr'); });
      more.hidden=n>=items.length; road.hidden=n<items.length;
    };
    const grid=card.parentElement; grid.classList.add('filling');
    let n=Math.min(QW_MIN,items.length); set(n);
    if(card.offsetTop===mat.offsetTop){
      const target=mat.offsetHeight;
      while(n<items.length){ set(n+1); if(card.offsetHeight>target){ set(n); break; } n++; }
    } else set(Math.min(QW_STACKED,items.length));
    grid.classList.remove('filling');
    if(typeof window.fitIframe==='function') window.fitIframe();
  }

