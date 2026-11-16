  // ---- estate flow ----
  // Source families on the left, the four pipeline rings across the middle,
  // closed and open incidents on the right. Strands carry GB; a red strand
  // is data no enabled rule reads, pooled under "Not monitored".
  function drawEstateFlow(svgEl, E, opts){
    opts=opts||{};
    const ns='http://www.w3.org/2000/svg';
    while(svgEl.firstChild) svgEl.removeChild(svgEl.firstChild);
    // With Defender XDR alerts, the band splits after detection: Defender
    // XDR's alerts above the line, Sentinel's below, merging into incidents;
    // the pool drops by poolDrop to clear the Sentinel ring's caption.
    const xdr=(E&&+E.alertsXdr)||0, splitY=xdr>0? 90 : 0, poolDrop=xdr>0? 26 : 0;
    const W=1200, H=440+poolDrop;
    svgEl.setAttribute('viewBox','0 0 '+W+' '+H);
    const mk=(tag,attrs,text)=>{ const el=document.createElementNS(ns,tag); for(const k in attrs) el.setAttribute(k,attrs[k]); if(text!=null) el.textContent=text; svgEl.appendChild(el); return el; };
    // Text drawn over strands gets a panel-coloured halo so it stays legible;
    // long captions wrap onto short lines instead of running into each other.
    const HALO='paint-order:stroke;stroke:var(--panel);stroke-width:3px;stroke-linejoin:round;';
    const wrapLines=(t,max)=>{ const out=[]; let cur=''; String(t||'').split(/\s+/).forEach(w=>{ if((cur+' '+w).trim().length>max && cur){ out.push(cur); cur=w; } else cur=(cur+' '+w).trim(); }); if(cur) out.push(cur); return out; };
    const mkLines=(x,y,lines,attrs,lh)=>{ const t=mk('text',Object.assign({x:x,y:y},attrs)); lines.forEach((ln,i)=>{ const ts=document.createElementNS(ns,'tspan'); ts.setAttribute('x',x); ts.setAttribute('dy',i?String(lh||12):'0'); ts.textContent=ln; t.appendChild(ts); }); return t; };
    const sources=(E&&E.sources?E.sources:[]);
    if(!E || !sources.length || !(E.totalGb>0)){
      mk('text',{x:W/2,y:H/2,'text-anchor':'middle','font-size':'14',style:'fill:var(--muted)'},'No billable ingestion in '+WIN.span()+', so there is no flow to draw.');
      return;
    }
    const maxGb=Math.max(...sources.map(s=>s.gb),0.01);
    const strand=gb=>Math.max(2,Math.min(28,28*Math.sqrt(gb/maxGb)));
    // A soft glow for the source dots, the rings' arcs and the outcome nodes,
    // as in the alert lifecycle.
    const glowDefs=mk('defs',{}), glow=document.createElementNS(ns,'filter');
    glow.setAttribute('id','esGlow'); glow.setAttribute('x','-50%'); glow.setAttribute('y','-50%'); glow.setAttribute('width','200%'); glow.setAttribute('height','200%');
    glow.innerHTML='<feGaussianBlur stdDeviation="3.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>';
    glowDefs.appendChild(glow);
    const LBL='letter-spacing:.14em;';
    // A bead overlay on a strand: k (0 to 1) is its share of the largest
    // flow and sets the speed. Beads take no pointer events, so the strand
    // under them keeps its tooltip and click.
    const beads=(tag,attrs,col,w,k,fam)=>{
      const b=mk(tag,Object.assign({class:'es-beads',stroke:col,'stroke-width':Math.max(1,w*0.3).toFixed(1),'stroke-dasharray':'3 21'},attrs));
      if(fam) b.setAttribute('data-bead-fam',fam);
      b.style.animationDuration=(3.4-1.8*Math.max(0,Math.min(1,k))).toFixed(1)+'s';
      return b;
    };
    const srcX=230, poolY=398+poolDrop, cy=200, r=36;
    // The "Not monitored" pool sits low and right of the ingestion ring, sized
    // to its own text; unmonitored strands drop early and run in from the
    // left, below the rings and their captions, instead of crossing them.
    const poolTitle='No detection rule', poolText=fmtN(E.uncoveredGb||0)+' GB read by no Sentinel rule or custom detection';
    const poolW=Math.max(170, Math.round(Math.max(poolTitle.length*7, poolText.length*5.8)+28)), poolCx=620, poolLeft=poolCx-poolW/2;
    const rings=[{k:'ingestion',x:410,label:'Ingestion'},{k:'detection',x:590,label:'Detection'},{k:'alerts',x:770,y:cy+splitY,label:xdr>0? 'Sentinel alerts' : 'Alerts'},{k:'incidents',x:950,label:'Incidents'}];
    const trunc=s=>String(s||'');
    const curve=(x0,y0,x1,y1)=>'M'+x0+','+y0+' C'+((x0+x1)/2)+','+y0+' '+((x0+x1)/2)+','+y1+' '+x1+','+y1;
    const gap=Math.min(44,(H-90)/Math.max(sources.length,1));
    const top=cy-(sources.length-1)*gap/2;
    mk('text',{x:srcX-22,y:cy-r-14-Math.max(0,(sources.length-1)*gap/2-r),'text-anchor':'end','font-size':'10','font-weight':'800',style:'fill:var(--faint);'+LBL},'SOURCE FAMILY (GB / '+WIN.d().toUpperCase()+')');
    const tip=(el,text)=>{ const t=document.createElementNS(ns,'title'); t.textContent=text; el.appendChild(t); return el; };
    sources.forEach((s,i)=>{
      const y=top+i*gap; const col=famColor[s.category]||'#64748b';
      const cov=+s.coveredGb||0, unc=Math.max(0,(+s.gb||0)-cov);
      const fp=(E.productAlerts||[]).filter(p=>p.family===s.category); const fpAlerts=fp.reduce((a,p)=>a+(+p.alerts||0),0);
      const tipText=s.category+': '+fmtN(s.gb)+' GB in '+WIN.span()+', '+s.covered+' of '+s.tables+' tables read by an enabled Sentinel rule or custom detection'+(unc>0?', '+fmtN(unc)+' GB with no detection rule':'')+(fpAlerts?'; '+fpAlerts.toLocaleString()+' alert(s) from first-party detections ('+fp.map(p=>p.product).join(', ')+')':'')+'. Click for the tables.';
      // Covered strands are solid in the family colour; unmonitored strands
      // keep the family colour but run dashed into the pool.
      if(cov>0){
        tip(mk('path',{class:'es-strand','data-fam':s.category,d:curve(srcX,y,rings[0].x-r,cy),fill:'none',stroke:col,'stroke-opacity':'.42','stroke-width':strand(cov).toFixed(1),'stroke-linecap':'round'}),tipText);
        beads('path',{d:curve(srcX,y,rings[0].x-r,cy)},col,strand(cov),Math.sqrt(cov/maxGb),s.category);
      }
      if(unc>0) tip(mk('path',{class:'es-strand es-unc','data-fam':s.category,d:'M'+srcX+','+y+' C'+(srcX+90)+','+y+' '+(poolLeft-120)+','+poolY+' '+poolLeft+','+poolY,fill:'none',stroke:col,'stroke-opacity':'.34','stroke-width':strand(unc).toFixed(1),'stroke-linecap':'butt','stroke-dasharray':'12 7'}),tipText);
      tip(mk('circle',{class:'es-src','data-fam':s.category,cx:srcX-8,cy:y,r:4.5,fill:col,filter:'url(#esGlow)'}),tipText);
      tip(mk('text',{class:'es-src','data-fam':s.category,x:srcX-22,y:y+4,'text-anchor':'end','font-size':'12','font-weight':'600',style:'fill:var(--ink-2);'+HALO},trunc(s.category)),tipText);
      tip(mk('text',{class:'es-src','data-fam':s.category,x:srcX-22,y:y+17,'text-anchor':'end','font-size':'10',style:'fill:var(--muted);'+HALO},fmtN(s.gb)+' GB · '+s.covered+' of '+s.tables+' tables read'),tipText);
    });
    if(E.uncoveredGb>0){
      const poolTip='Tables ingested and billed but read by no enabled Sentinel rule or Defender custom detection. Product alerts are not counted here. Click for the list.';
      mk('rect',{x:poolLeft,y:poolY-19,width:poolW,height:38,rx:10,style:'fill:var(--panel)'});
      tip(mk('rect',{class:'es-pool',x:poolLeft,y:poolY-19,width:poolW,height:38,rx:10,fill:'#dc2626','fill-opacity':'.12',stroke:'#dc2626','stroke-opacity':'.55'}),poolTip);
      tip(mk('text',{class:'es-pool',x:poolCx,y:poolY-3,'text-anchor':'middle','font-size':'11','font-weight':'700',fill:'#dc2626'},poolTitle),poolTip);
      tip(mk('text',{class:'es-pool',x:poolCx,y:poolY+11,'text-anchor':'middle','font-size':'10',fill:'#dc2626'},poolText),poolTip);
    }
    const bandW=Math.max(3,strand(+E.coveredGb||0));
    const ry=rg=>rg.y==null? cy : rg.y;
    const C=2*Math.PI*r;
    const arcs=[];
    for(let i=0;i<rings.length-1;i++){
      const a=rings[i], b=rings[i+1], k=Math.sqrt((+E.coveredGb||0)/maxGb);
      if(ry(a)===ry(b)){
        mk('line',{x1:a.x+r,y1:ry(a),x2:b.x-r,y2:ry(b),'stroke-opacity':'.35','stroke-width':bandW.toFixed(1),style:'stroke:var(--brand)'});
        beads('line',{x1:a.x+r,y1:ry(a),x2:b.x-r,y2:ry(b)},'#2563eb',bandW,k);
      } else {
        const d=curve(a.x+r,ry(a),b.x-r,ry(b));
        mk('path',{d:d,fill:'none','stroke-opacity':'.35','stroke-width':bandW.toFixed(1),style:'stroke:var(--brand)'});
        beads('path',{d:d},'#2563eb',bandW,k);
      }
    }
    // Defender XDR's alerts (its products, which read no workspace table):
    // the upper branch of the split, a ring mirroring Sentinel's below it
    // (Defender XDR's share of every alert, in its colour: a share, not a
    // score), merging into the incidents, which count both. Drawn before the
    // stage rings, with square ends, so the rings sit over the strands.
    const allAlerts=+E.alerts||0;
    if(xdr>0){
      const det=rings[1], al=rings[2], inc=rings[3], xx=al.x, xy=cy-splitY, xcol=famColor['Defender XDR']||'#0d9488';
      const share=allAlerts>0? Math.min(1,xdr/allAlerts) : 1, pctX=Math.round(share*100);
      const xw=Math.max(3,Math.min(24,bandW*Math.sqrt(xdr/Math.max(+E.ruleAlerts||+E.alertsSentinel||1,1))));
      const xTip='Defender XDR alerts: '+xdr.toLocaleString()+' raised in Defender XDR and the Microsoft security products feeding it in '+WIN.span()+', '+pctX+'% of the '+allAlerts.toLocaleString()+' alerts. They read no workspace table, so the rings to the left do not count them; the incidents do. Click to open the alerts page.';
      [curve(det.x+r,cy,xx-r,xy), curve(xx+r,xy,inc.x-r,cy)].forEach(d=>{
        tip(mk('path',{'data-xdr':'1',d:d,fill:'none',stroke:xcol,'stroke-opacity':'.42','stroke-width':xw.toFixed(1),'stroke-linecap':'butt'}),xTip);
        beads('path',{d:d},xcol,xw,Math.min(1,xw/24));
      });
      tip(mk('circle',{'data-xdr':'1',cx:xx,cy:xy,r:r,'stroke-width':'7',style:'fill:var(--panel);stroke:var(--ring-track)'}),xTip);
      const xarc=tip(mk('circle',{'data-xdr':'1',class:'es-arc',cx:xx,cy:xy,r:r,fill:'none','stroke-width':'7','stroke-linecap':'round','stroke-dasharray':(C*share).toFixed(1)+' '+C.toFixed(1),
        transform:'rotate(-90 '+xx+' '+xy+')',filter:'url(#esGlow)',style:'stroke:'+xcol}),xTip);
      arcs.push({el:xarc, to:(C*share).toFixed(1)+' '+C.toFixed(1), from:'0 '+C.toFixed(1)});
      tip(mk('text',{'data-xdr':'1',x:xx,y:xy+6,'text-anchor':'middle','font-size':'17','font-weight':'800',style:'fill:var(--ink)'},pctX+'%'),xTip);
      mk('text',{x:xx,y:xy-r-14,'text-anchor':'middle','font-size':'10','font-weight':'800',style:'fill:var(--faint);'+LBL},'DEFENDER XDR ALERTS');
      tip(mk('text',{'data-xdr':'1',x:xx,y:xy+r+20,'text-anchor':'middle','font-size':'11','font-weight':'650',style:'fill:var(--ink-2);'+HALO},xdr.toLocaleString()+' of '+allAlerts.toLocaleString()),xTip);
      tip(mk('text',{'data-xdr':'1',x:xx,y:xy+r+35,'text-anchor':'middle','font-size':'10',style:'fill:var(--muted);'+HALO},'alerts from Defender XDR'),xTip);
    }
    rings.forEach(rg=>{
      const d=(E.rings&&E.rings[rg.k])||{value:0,max:0,pct:null};
      const frac=d.pct==null?0:Math.max(0,Math.min(1,d.pct/100));
      const ringTip=rg.label+': '+(d.pct==null?'not measured':d.pct+'%')+' ('+Number(d.value).toLocaleString()+' of '+Number(d.max).toLocaleString()+'). '+(d.label||'')+(opts.ringPage&&opts.ringPage(rg.k)!=null?' Click to open the page.':'');
      const y=ry(rg);
      tip(mk('circle',{'data-ring':rg.k,cx:rg.x,cy:y,r:r,'stroke-width':'7',style:'fill:var(--panel);stroke:var(--ring-track)'}),ringTip);
      const arc=tip(mk('circle',{'data-ring':rg.k,class:'es-arc',cx:rg.x,cy:y,r:r,fill:'none','stroke-width':'7','stroke-linecap':'round','stroke-dasharray':(C*frac).toFixed(1)+' '+C.toFixed(1),
        transform:'rotate(-90 '+rg.x+' '+y+')',filter:'url(#esGlow)',style:'stroke:'+(d.pct==null?'var(--slate)':ringTone(frac))}),ringTip);
      arcs.push({el:arc, to:(C*frac).toFixed(1)+' '+C.toFixed(1), from:'0 '+C.toFixed(1)});
      tip(mk('text',{'data-ring':rg.k,x:rg.x,y:y+6,'text-anchor':'middle','font-size':'17','font-weight':'800',style:'fill:var(--ink)'},d.pct==null?'n/a':d.pct+'%'),ringTip);
      mk('text',{x:rg.x,y:y-r-14,'text-anchor':'middle','font-size':'10','font-weight':'800',style:'fill:var(--faint);'+LBL},rg.label.toUpperCase());
      mk('text',{x:rg.x,y:y+r+20,'text-anchor':'middle','font-size':'11','font-weight':'650',style:'fill:var(--ink-2);'+HALO},Number(d.value).toLocaleString()+' of '+Number(d.max).toLocaleString());
      mkLines(rg.x,y+r+35,wrapLines(d.label||'',24),{'text-anchor':'middle','font-size':'10',style:'fill:var(--muted);'+HALO},12);
    });
    const last=rings[rings.length-1];
    const boxes=[{l:'Closed',v:+E.incidentsClosed||0,col:'#16a34a',y:cy-40},{l:'Open',v:+E.incidentsOpen||0,col:'#d97706',y:cy+40}];
    boxes.forEach(b=>{
      const share=(+E.incidents||0)>0? b.v/(+E.incidents): .5;
      mk('path',{d:curve(last.x+r,cy,1092,b.y),fill:'none',stroke:b.col,'stroke-opacity':'.35','stroke-width':Math.max(3,bandW*share).toFixed(1)});
      beads('path',{d:curve(last.x+r,cy,1092,b.y)},b.col,Math.max(3,bandW*share),share);
      const incTip=b.l+' incidents in '+WIN.span()+'. Click to open the incidents page.';
      tip(mk('rect',{'data-inc':b.l,x:1088,y:b.y-18,width:104,height:40,rx:8,fill:'transparent'}),incTip);
      tip(mk('circle',{'data-inc':b.l,cx:1098,cy:b.y,r:6.5,fill:b.col,filter:'url(#esGlow)'}),incTip);
      tip(mk('text',{'data-inc':b.l,x:1114,y:b.y+6,'font-size':'19','font-weight':'800',style:'fill:var(--ink)'},b.v.toLocaleString()),incTip);
      tip(mk('text',{'data-inc':b.l,x:1114,y:b.y+20,'font-size':'9.5','font-weight':'700',style:'fill:var(--muted);'+LBL},b.l.toUpperCase()),incTip);
    });
    // The rings' arcs draw in from empty, once; not for reduced motion.
    if(!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)){
      arcs.forEach(a=>{ a.el.style.strokeDasharray=a.from; });
      requestAnimationFrame(()=>requestAnimationFrame(()=>arcs.forEach(a=>{ a.el.style.strokeDasharray=a.to; })));
    }
    // Interaction: spotlight a family on hover; click through on everything.
    const spot=fam=>{ svgEl.classList.toggle('es-dim',!!fam);
      svgEl.querySelectorAll('.es-strand,.es-src').forEach(el=>el.classList.toggle('es-hot',!!fam&&el.getAttribute('data-fam')===fam));
      svgEl.querySelectorAll('.es-beads').forEach(el=>el.classList.toggle('es-hot',!!fam&&el.getAttribute('data-bead-fam')===fam)); };
    svgEl.querySelectorAll('[data-fam]').forEach(el=>{
      el.addEventListener('mouseenter',()=>spot(el.getAttribute('data-fam')));
      el.addEventListener('mouseleave',()=>spot(null));
      el.addEventListener('click',()=>{ if(opts.onFamily) opts.onFamily(el.getAttribute('data-fam')); });
    });
    svgEl.querySelectorAll('.es-pool').forEach(el=>el.addEventListener('click',()=>{ if(opts.onPool) opts.onPool(); }));
    svgEl.querySelectorAll('[data-ring]').forEach(el=>el.addEventListener('click',()=>{ if(opts.onRing) opts.onRing(el.getAttribute('data-ring')); }));
    svgEl.querySelectorAll('[data-inc]').forEach(el=>el.addEventListener('click',()=>{ if(opts.onIncidents) opts.onIncidents(el.getAttribute('data-inc')); }));
    svgEl.querySelectorAll('[data-xdr]').forEach(el=>{ el.style.cursor='pointer'; el.addEventListener('click',()=>{ if(opts.onXdr) opts.onXdr(); }); });
  }
  // Detail panel under the flow: the tables behind a family or the pool.
  function showEstateDetail(sel){
    const el=document.getElementById('estateDetail'); if(!el||!E) return;
    const all=E.tables||[];
    const rows=sel.family? all.filter(t=>t.family===sel.family) : all.filter(t=>!t.covered);
    const gb=rows.reduce((a,t)=>a+(+t.gb||0),0), covered=rows.filter(t=>t.covered).length;
    const title=sel.family? sel.family : 'No detection rule';
    const sub=sel.family? (rows.length+' table'+(rows.length===1?'':'s')+' receiving data, '+fmtN(gb)+' GB in '+WIN.span()+', '+covered+' read by an enabled Sentinel rule or custom detection')
                        : (rows.length+' table'+(rows.length===1?'':'s')+' with '+fmtN(gb)+' GB in '+WIN.span()+' that no enabled Sentinel rule or custom detection reads');
    const cd=E.customDetections||{};
    const cdLine=cd.captured? '<p class="note" style="margin:0 0 6px">Defender XDR custom detections: '+(cd.enabled||0)+' enabled of '+(cd.total||0)+' defined; an enabled one counts as coverage for the tables it queries.</p>'
                            : '<p class="note" style="margin:0 0 6px">Defender XDR custom detections were not captured in this run (the identity needs CustomDetection.Read.All), so coverage here counts Sentinel rules only.</p>';
    const fp=(E.productAlerts||[]).filter(p=>sel.family? p.family===sel.family : true);
    const fpLine=fp.length? '<p class="note" style="margin:0 0 10px">First-party detections on '+(sel.family?'this family':'these families')+' in '+WIN.span()+': '+fp.map(p=>esc(p.product)+' '+(+p.alerts||0).toLocaleString()+' alert'+(p.alerts==1?'':'s')+' from '+p.detections+' detection'+(p.detections==1?'':'s')).join('; ')+'. These run inside the product and do not read workspace tables, so they are not counted as Sentinel coverage.</p>'
                         : '<p class="note" style="margin:0 0 10px">No first-party product alerts on '+(sel.family?'this family':'these families')+' in '+WIN.span()+' either.</p>';
    const opNum=findSecNum(/detection opportunities/i,null);
    const trs=rows.map(t=>'<tr><td>'+esc(t.table)+'</td><td>'+esc(t.family)+'</td><td class="num">'+fmtN(t.gb)+'</td><td class="num">'+(t.rules||0)+'</td><td class="num">'+(t.customDetections||0)+'</td><td>'+
      ((t.rules||0)>0&&(t.customDetections||0)>0?'<span class="st Met">Rule and custom detection</span>':(t.rules||0)>0?'<span class="st Met">Sentinel rule reads it</span>':(t.customDetections||0)>0?'<span class="st Met">Custom detection reads it</span>':'<span class="st Gap">No detection rule</span>')+'</td></tr>');
    el.innerHTML='<div class="esdetail"><div class="esd-head"><h3>'+esc(title)+'</h3><p class="note">'+esc(sub)+'</p>'+(opNum!=null&&!sel.family?sbtn('Detection opportunities','data-jump="'+opNum+'"',{go:true}):'')+sbtn('Close','data-esd-close')+'</div>'+cdLine+fpLine+
      (rows.length? moreTable('<table class="tbl"><thead><tr><th>Table</th><th>Family</th><th class="num">GB / '+WIN.d()+'</th><th class="num">Sentinel rules</th><th class="num">Custom detections</th><th>Coverage</th></tr></thead><tbody>'+trRows(trs,10)+'</tbody></table>',rows.length,10,'tables') : '<p class="note">No tables.</p>')+'</div>';
    el.classList.remove('hidden');
    el.querySelector('[data-esd-close]').addEventListener('click',()=>{ el.classList.add('hidden'); el.innerHTML=''; if(typeof window.fitIframe==='function') window.fitIframe(); });
    el.querySelectorAll('[data-jump]').forEach(a=>a.addEventListener('click',()=>jumpTo(+a.dataset.jump)));
    if(typeof window.fitIframe==='function') window.fitIframe();
  }
  const ringPage=k=>({ingestion:findSecNum(/table plans/i,null),detection:findSecNum(/detection opportunities/i,null),alerts:findSecNum(/^analytics rules/i,null),incidents:findSecNum(/^incidents/i,null)})[k];
  drawEstateFlow(document.getElementById('estateFlow'), E, {
    ringPage,
    onFamily:f=>showEstateDetail({family:f}),
    onPool:()=>showEstateDetail({uncovered:true}),
    onRing:k=>{ const n=ringPage(k); if(n!=null) jumpTo(n); },
    onIncidents:()=>{ const n=findSecNum(/^incidents/i,null); if(n!=null) jumpTo(n); },
    onXdr:()=>{ const n=findSecNum(/^alerts/i,null); if(n!=null) jumpTo(n); }
  });
  document.getElementById('estateLegend').innerHTML=Object.keys(famColor).map(f=>'<span><i style="background:'+famColor[f]+'"></i>'+esc(f)+'</span>').join('')+
    '<span><i class="dash"></i>No detection rule (dashed, family colour)</span><span><i style="background:var(--green)"></i>Strong (80%+)</span>'+
    '<span><i style="background:var(--brand)"></i>Fair (65%+)</span><span><i style="background:var(--amber)"></i>Weak</span>';

