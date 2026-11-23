  // ---- SANKEY ----
  // The flow graph is rebuilt in the browser from every ingesting table
  // (M.flowTables): the default view keeps the nine largest tables and folds
  // the rest into "Other"; a family filter or "every table" shows them all.
  const FT = M.flowTables || [];
  let flowState = { family:null, all:false };
  function buildFlowGraph(tables, st){
    const topN=9, r3=v=>Math.round(v*1000)/1000;
    let rows=tables; if(st.family) rows=rows.filter(t=>t.family===st.family);
    const expand=st.all||!!st.family;
    const top=expand? rows : rows.slice(0,topN), rest=expand? [] : rows.slice(topN);
    const tableRows=top.map(t=>({table:t.table,family:t.family,gb:t.gb,parts:[{plan:t.plan,gb:t.gb,billedGb:t.billedGb}]}));
    if(rest.length){
      const parts={}; let gb=0;
      rest.forEach(t=>{ const p=parts[t.plan]||(parts[t.plan]={plan:t.plan,gb:0,billedGb:0}); p.gb+=t.gb; p.billedGb+=t.billedGb; gb+=t.gb; });
      Object.values(parts).forEach(p=>{ p.gb=r3(p.gb); p.billedGb=r3(p.billedGb); });
      tableRows.push({table:'Other (+'+rest.length+')',family:'Other',gb:r3(gb),parts:Object.values(parts),other:true});
    }
    const fam={}, plan={}, pb={}, bucket={'Billed':0,'Grant eligible':0};
    tableRows.forEach(row=>{
      fam[row.family]=(fam[row.family]||0)+row.gb;
      row.parts.forEach(pt=>{
        plan[pt.plan]=(plan[pt.plan]||0)+pt.gb;
        const free=r3(pt.gb-pt.billedGb); bucket['Billed']+=pt.billedGb; bucket['Grant eligible']+=free;
        [['Billed',pt.billedGb],['Grant eligible',free]].forEach(([k,v])=>{ if(v<=0) return; const key=pt.plan+'|'+k; pb[key]=(pb[key]||0)+v; });
      });
    });
    const nodes=[], links=[];
    Object.keys(fam).sort((a,b)=>fam[b]-fam[a]).forEach(f=>nodes.push({id:'f:'+f,col:0,label:f,value:r3(fam[f]),clickable:true}));
    tableRows.forEach(row=>nodes.push({id:'t:'+row.table,col:1,label:row.table,value:row.gb,other:!!row.other,clickable:!!row.other}));
    Object.keys(plan).sort((a,b)=>plan[b]-plan[a]).forEach(p=>nodes.push({id:'p:'+p,col:2,label:p,value:r3(plan[p]),lake:/Lake/.test(p)}));
    ['Billed','Grant eligible'].forEach(b=>{ if(bucket[b]>0) nodes.push({id:'b:'+b,col:3,label:b,value:r3(bucket[b])}); });
    tableRows.forEach(row=>{
      links.push({source:'f:'+row.family,target:'t:'+row.table,value:row.gb});
      row.parts.forEach(pt=>links.push({source:'t:'+row.table,target:'p:'+pt.plan,value:pt.gb}));
    });
    Object.keys(pb).forEach(k=>{ const i=k.lastIndexOf('|'); links.push({source:'p:'+k.slice(0,i),target:'b:'+k.slice(i+1),value:r3(pb[k])}); });
    return {nodes,links};
  }
  function renderFlowFilter(){
    const el=document.getElementById('flowFilter'); if(!el) return;
    if(!FT.length){ el.innerHTML=''; return; }
    const fams={}; FT.forEach(t=>{ const f=fams[t.family]||(fams[t.family]={n:0,gb:0}); f.n++; f.gb+=t.gb; });
    const chip=(label,active,attrs,sub)=>'<button type="button" class="fchip'+(active?' active':'')+'" '+attrs+'>'+esc(label)+(sub?'<span>'+esc(sub)+'</span>':'')+'</button>';
    let h=chip('Largest tables',!flowState.family&&!flowState.all,'data-flow="top"','top 9, rest as Other')+
          chip('Every table',flowState.all&&!flowState.family,'data-flow="all"',FT.length+' tables');
    const gbTxt=v=>(Math.round(v*100)/100).toLocaleString();
    Object.keys(fams).sort((a,b)=>fams[b].gb-fams[a].gb).forEach(f=>{ h+=chip(f,flowState.family===f,'data-flow="fam" data-fam="'+esc(f)+'"',fams[f].n+' table'+(fams[f].n===1?'':'s')+' · '+gbTxt(fams[f].gb)+' GB'); });
    el.innerHTML=h;
    el.querySelectorAll('[data-flow]').forEach(b=>b.addEventListener('click',()=>{
      const k=b.dataset.flow;
      flowState = k==='top' ? {family:null,all:false} : (k==='all' ? {family:null,all:true} : {family:b.dataset.fam,all:false});
      drawSankeys();
    }));
  }
  // The ingest and billing flow, in the alert lifecycle's and estate flow's
  // style: source families as glowing dots on the left, each table as a pill
  // tinted in its family's colour (its GB inside), each plan and tier as a
  // ring (its share of the GB shown, the GB under it), and the billed and
  // free outcomes as glowing nodes with their totals. Strands carry GB
  // (width on a square-root scale) with beads, in a group behind a clip
  // revealSankey widens from the left. A family filters to its tables, the
  // Other pill shows every table, and hovering a family spotlights it.
  function drawSankey(svgEl, opts){
    const graph = opts.graph || M.flow;
    const nodes = graph.nodes, links = graph.links;
    if(!nodes.length){ svgEl.parentNode.innerHTML='<p class="note" style="padding:16px">No ingesting tables in the cost snapshot.</p>'; return; }
    const ns='http://www.w3.org/2000/svg';
    while(svgEl.firstChild) svgEl.removeChild(svgEl.firstChild);
    svgEl.classList.remove('ib-dim');
    const mk=(tag,attrs,text,parent)=>{ const el=document.createElementNS(ns,tag); for(const k in attrs) el.setAttribute(k,attrs[k]); if(text!=null) el.textContent=text; (parent||svgEl).appendChild(el); return el; };
    const tip=(el,text)=>{ mk('title',{},text,el); return el; };
    const cols=[[],[],[],[]]; nodes.forEach(n=>cols[n.col].push(n));
    const byId={}; nodes.forEach(n=>byId[n.id]=n);
    const famOf={}; links.forEach(l=>{ const s=byId[l.source]; if(s && s.col===0) famOf[l.target]=s.label; });
    const colOf=n=> n.col===1? (famColor[famOf[n.id]]||'#64748b') : nodeFill(n);
    const LBL='letter-spacing:.14em;', HALO='paint-order:stroke;stroke:var(--panel);stroke-width:3px;stroke-linejoin:round;';
    const rowH=34, top=58, R=30, W=1200;
    const bodyH=Math.max(340, cols[1].length*rowH, cols[2].length*124, cols[0].length*50);
    const H=top+bodyH+20;
    svgEl.setAttribute('viewBox','0 0 '+W+' '+H); svgEl.setAttribute('width',W); svgEl.setAttribute('height',H);
    const fx=232, tx=384, tw=262, px=842, ox=1012;
    const place=(arr,gap)=>{ const g=arr.length>1? Math.min(gap,(bodyH-24)/(arr.length-1)) : 0, y0=top+bodyH/2-g*(arr.length-1)/2; arr.forEach((n,i)=>{ n._y=Math.round(y0+i*g); }); };
    place(cols[0],56); place(cols[1],rowH); place(cols[2],132); place(cols[3],170);
    const defs=mk('defs',{});
    const glow=mk('filter',{id:'ibGlow',x:'-50%',y:'-50%',width:'200%',height:'200%'},null,defs);
    glow.innerHTML='<feGaussianBlur stdDeviation="3.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>';
    const clipId='skClip'+(svgEl.id||''), clip=mk('clipPath',{id:clipId},null,defs);
    mk('rect',{x:0,y:0,width:W,height:H},null,clip);
    [['DATA SOURCE',fx,'end',0],['WORKSPACE TABLE',tx,'start',1],['PLAN AND TIER',px,'middle',2],['OUTCOME',ox,'start',3]].forEach(([t,x,a,ci])=>{
      if(cols[ci].length) mk('text',{x:x,y:26,'text-anchor':a,'font-size':'10','font-weight':'800',style:'fill:var(--faint);'+LBL},t); });
    // Strands, behind the nodes.
    const strands=mk('g',{'clip-path':'url(#'+clipId+')'});
    const maxGb=Math.max(0.001,...links.map(l=>+l.value||0));
    const sw=v=>Math.max(1.5,22*Math.sqrt((+v||0)/maxGb));
    const curve=(x0,y0,x1,y1)=>'M'+x0+','+y0+' C'+((x0+x1)/2)+','+y0+' '+((x0+x1)/2)+','+y1+' '+x1+','+y1;
    const outAt=n=> n.col===0? [fx+6,n._y] : n.col===1? [tx+tw,n._y] : [px+R+5,n._y];
    const inAt=n=> n.col===1? [tx,n._y] : n.col===2? [px-R-5,n._y] : [ox-10,n._y];
    links.forEach(l=>{
      const a=byId[l.source], b=byId[l.target]; if(!a||!b) return;
      const [x0,y0]=outAt(a), [x1,y1]=inAt(b), d=curve(x0,y0,x1,y1), w=sw(l.value), col=colOf(a);
      const fam=a.col===0? a.label : a.col===1? (famOf[a.id]||'') : '';
      tip(mk('path',{d:d,fill:'none',stroke:col,'stroke-opacity':'.42','stroke-width':w.toFixed(1),class:'ib-strand','data-fam':fam},null,strands),a.label+' to '+b.label+': '+fmtN(l.value)+' GB');
      if(w>=2.5){
        const bd=mk('path',{d:d,class:'sk-beads','data-fam':fam,stroke:col,'stroke-width':Math.max(1,w*0.3).toFixed(1),'stroke-dasharray':'3 21'},null,strands);
        bd.style.animationDuration=(3.4-1.8*Math.sqrt(Math.min(1,(+l.value||0)/maxGb))).toFixed(1)+'s';
      }
    });
    const spot=fam=>{ svgEl.classList.toggle('ib-dim',!!fam); svgEl.querySelectorAll('[data-fam]').forEach(el=>el.classList.toggle('ib-hot',!!fam && el.getAttribute('data-fam')===fam)); };
    const click=(g,n,text)=>{ tip(g,text); if(n.clickable && opts.onNode){ g.style.cursor='pointer'; g.addEventListener('click',()=>opts.onNode(n)); } };
    // Source families.
    cols[0].forEach(n=>{
      const g=mk('g',{class:'ib-src','data-fam':n.label});
      mk('circle',{cx:fx,cy:n._y,r:4.5,fill:nodeFill(n),filter:'url(#ibGlow)'},null,g);
      mk('text',{x:fx-14,y:n._y-1,'text-anchor':'end','font-size':'12','font-weight':'600',style:'fill:var(--ink-2);'+HALO},n.label,g);
      mk('text',{x:fx-14,y:n._y+13,'text-anchor':'end','font-size':'10',style:'fill:var(--muted);'+HALO},fmtN(n.value)+' GB',g);
      click(g,n,n.label+': '+fmtN(n.value)+' GB in '+WIN.span()+'.'+(n.clickable&&opts.onNode? ' Select to show every table in it.' : ''));
      g.addEventListener('mouseenter',()=>spot(n.label)); g.addEventListener('mouseleave',()=>spot(null));
    });
    // Tables: a pill each, the name truncated to fit with the full name in the tooltip.
    // Estimated width, with 8% to spare: the browser's text runs up to 6% wider.
    const estText=t=>1.08*[...String(t)].reduce((a,ch)=>a+(/[A-Z]/.test(ch)?7.9:/[ijl.,'| ]/.test(ch)?3.6:6.3),0);
    cols[1].forEach(n=>{
      const col=colOf(n), fam=famOf[n.id]||'', g=mk('g',{class:'ib-tbl','data-fam':fam}), val=fmtN(n.value)+' GB';
      mk('rect',{x:tx,y:n._y-12,width:tw,height:24,rx:12,fill:col,'fill-opacity':'.16',stroke:col,'stroke-opacity':'.55'},null,g);
      const avail=tw-24-val.length*5.9-10; let txt=n.label;
      if(estText(txt)>avail){ while(txt.length>1 && estText(txt+'…')>avail) txt=txt.slice(0,-1); txt+='…'; }
      mk('text',{x:tx+12,y:n._y+4,'font-size':'11.5','font-weight':'600',style:'fill:var(--ink)'},txt,g);
      mk('text',{x:tx+tw-12,y:n._y+4,'text-anchor':'end','font-size':'10',style:'fill:var(--muted)'},val,g);
      click(g,n,n.label+': '+val+' in '+WIN.span()+(fam? ' ('+fam+')' : '')+'.'+(n.other&&opts.onNode? ' Select to show every table.' : ''));
    });
    // Plans and tiers: a ring each, its share of the GB shown.
    const C=2*Math.PI*R, planGb=cols[2].reduce((a,n)=>a+(+n.value||0),0)||1;
    cols[2].forEach(n=>{
      const col=nodeFill(n), share=Math.min(1,(+n.value||0)/planGb), pct=Math.round(share*100), g=mk('g',{});
      mk('circle',{cx:px,cy:n._y,r:R,'stroke-width':'6',style:'fill:var(--panel);stroke:var(--ring-track)'},null,g);
      mk('circle',{cx:px,cy:n._y,r:R,fill:'none','stroke-width':'6','stroke-linecap':'round','stroke-dasharray':(C*share).toFixed(1)+' '+C.toFixed(1),transform:'rotate(-90 '+px+' '+n._y+')',filter:'url(#ibGlow)',style:'stroke:'+col},null,g);
      mk('text',{x:px,y:n._y+5,'text-anchor':'middle','font-size':'14','font-weight':'800',style:'fill:var(--ink)'},pct+'%',g);
      mk('text',{x:px,y:n._y-R-12,'text-anchor':'middle','font-size':'9.5','font-weight':'800',style:'fill:var(--faint);'+LBL+HALO},String(n.label).toUpperCase(),g);
      mk('text',{x:px,y:n._y+R+18,'text-anchor':'middle','font-size':'11','font-weight':'650',style:'fill:var(--ink-2);'+HALO},fmtN(n.value)+' GB',g);
      tip(g,n.label+': '+fmtN(n.value)+' GB in '+WIN.span()+', '+pct+'% of the GB shown.');
    });
    // Outcomes: billed in full and eligible for a data grant, with their totals.
    const outGb=cols[3].reduce((a,n)=>a+(+n.value||0),0)||1;
    cols[3].forEach(n=>{
      const col=nodeFill(n), pct=Math.round((+n.value||0)/outGb*100), g=mk('g',{});
      mk('circle',{cx:ox,cy:n._y,r:7,fill:col,filter:'url(#ibGlow)'},null,g);
      mk('text',{x:ox+18,y:n._y+7,'font-size':'22','font-weight':'800',style:'fill:var(--ink)'},fmtN(n.value)+' GB',g);
      mk('text',{x:ox+18,y:n._y+22,'font-size':'9.5','font-weight':'700',style:'fill:var(--muted);'+LBL},String(n.label).toUpperCase(),g);
      mk('text',{x:ox+18,y:n._y+36,'font-size':'10',style:'fill:var(--muted)'},pct+'% of the GB shown',g);
      tip(g,n.label+': '+fmtN(n.value)+' GB in '+WIN.span()+', '+pct+'% of the GB shown.');
    });
    revealSankey(svgEl);
    return {W,H};
  }
  // Widen the Sankey's ribbon clip from 0 to full width over 0.9 s. Skipped
  // for reduced motion and while the chart is hidden (its tab is closed);
  // activateTab calls it again when the Data flow tab opens.
  function revealSankey(svgEl){
    const rect=svgEl && svgEl.querySelector('clipPath rect'); if(!rect) return;
    const full=svgEl.viewBox.baseVal.width;
    if(svgEl._reveal) cancelAnimationFrame(svgEl._reveal);
    rect.setAttribute('width',full);
    if((window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) || !svgEl.getBoundingClientRect().width) return;
    const t0=performance.now(), dur=900;
    // A frame's timestamp can fall just before t0, so k starts at 0, never below.
    const step=now=>{ const k=Math.max(0,Math.min(1,(now-t0)/dur)), e=1-Math.pow(1-k,3); rect.setAttribute('width',(full*e).toFixed(1)); if(k<1) svgEl._reveal=requestAnimationFrame(step); else svgEl._reveal=null; };
    rect.setAttribute('width','0');
    svgEl._reveal=requestAnimationFrame(step);
  }
  const legendHtml = Object.keys(famColor).map(f=>'<span><i style="background:'+famColor[f]+'"></i>'+esc(f)+'</span>').join('')+
     '<span><i style="background:'+lakeColor+'"></i>Data lake tier</span><span><i style="background:#c2912b"></i>Billed</span><span><i style="background:#2e8b64"></i>Grant eligible</span>';
  document.getElementById('legendBig').innerHTML=legendHtml;
  let zoom=1; const big=document.getElementById('sankeyBig');
  let dim=null;
  // Both copies read the theme when drawn, so a theme toggle redraws them.
  function drawSankeys(){
    const graph = FT.length ? buildFlowGraph(FT, flowState) : M.flow;
    dim=drawSankey(big,{graph,onNode:n=>{
      if(n.col===0) flowState = { family:(flowState.family===n.label? null : n.label), all:false };
      else if(n.other) flowState = { family:null, all:true };
      drawSankeys();
    }});
    renderFlowFilter();
    applyZoom();
  }
  function applyZoom(){ if(!dim)return; big.setAttribute('width',dim.W*zoom); big.setAttribute('height',dim.H*zoom);
    document.getElementById('zoomPct').textContent=Math.round(zoom*100)+'%'; }
  drawSankeys();
  window.addEventListener('sac-theme',drawSankeys);
  document.getElementById('zoomIn').onclick=()=>{zoom=Math.min(2,zoom+.1);applyZoom();};
  document.getElementById('zoomOut').onclick=()=>{zoom=Math.max(.5,zoom-.1);applyZoom();};
  document.getElementById('zoomFit').onclick=()=>{zoom=1;applyZoom();};

