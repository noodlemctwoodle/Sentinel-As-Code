    function render(num){
      const s=secs.find(x=>x.num===num)||secs[0];
      // A page opens on its first tab; the tab it is on is kept only while it stays open (a resize).
      if(s.num!==curDocNum) delete lastDocTab[s.num];
      curDocNum=s.num;
      curDoc=()=>curDocNum;
      wpCharts.length=0;
      let ti=0;
      const ownCharts=(s.blocks||[]).some(b=>b.t==='chart');
      const blockHtml=b=>{
        if(b.t==='h') return (b.lvl>=4?'<h4>':'<h3>')+b.html+(b.lvl>=4?'</h4>':'</h3>');
        if(b.t==='p') return kvTiles(b.html) || refLinks(b.html) || '<p>'+b.html+'</p>';
        if(b.t==='note') return noteHtml(b);
        if(b.t==='ul') return refLinks((b.items||[]).join(' · ')) || '<ul>'+b.items.map(it=>'<li>'+it+'</li>').join('')+'</ul>';
        if(b.t==='chart') return chartHtml(b);
        if(b.t==='table') return (ownCharts?'':chartFromTable(b))+tableHtml(b, ti++);
        return '';
      };
      // Lines of figures one after another share one grid of tiles. Only a
      // tile grid's own end (marked) joins the next: a chart card before a
      // line of figures keeps its own end, and the tiles their own row.
      // Link cards one after another merge the same way, under the first's heading.
      const blocksHtml=list=>list.map(blockHtml).join('').replace(/<\/div><!--\/kv--><div class="kvtiles">/g,'')
        .replace(/<\/div><\/div><!--\/refs--><div class="refs"><div class="refs-h">[\s\S]*?<\/div><div class="refl">/g,'');
      // The intro, then one block per main section, which layoutDoc may
      // gather into tabs.
      const intro=[], groups=[];
      (s.blocks||[]).forEach(b=>{
        if(b.t==='h' && b.lvl===2) groups.push({head:b, blocks:[]});
        else (groups.length? groups[groups.length-1].blocks : intro).push(b);
      });
      const label=g=>g.head.html.replace(/<[^>]+>/g,'').trim();
      // The page's References (every reference link it gives, gathered at
      // its foot by the renderer) is a link card under the tabs, on every tab.
      const refIx=groups.findIndex(g=>/^references$/i.test(label(g)) && g.blocks.length && g.blocks.every(b=>(b.t==='ul'||b.t==='p') && refLinks(b.t==='ul'? (b.items||[]).join(' · ') : b.html)));
      const refsCard=refIx<0? '' : refLinks(groups[refIx].blocks.map(b=>b.t==='ul'? (b.items||[]).join(' · ') : b.html).join(' · '), 'References').replace(/<!--\/refs-->$/,'');
      if(refIx>=0) groups.splice(refIx,1);
      const rowsIn=g=>g.blocks.filter(b=>b.t==='table').reduce((a,b)=>a+(b.rows||[]).length,0);
      // The page's description, its opening paragraph, always sits under the
      // title, above any tabs.
      let desc='';
      if(intro.length && intro[0].t==='p' && !kvTiles(intro[0].html) && !refLinks(intro[0].html)){ desc='<p class="docdesc">'+intro[0].html+'</p>'; intro.shift(); }
      const body=desc+(intro.length? '<div class="docintro">'+blocksHtml(intro)+'</div>' : '')+
        groups.map(g=>'<section class="docsec" data-rows="'+rowsIn(g)+'" data-label="'+label(g).replace(/"/g,'&quot;')+'"><h3 class="dsech">'+g.head.html+'</h3>'+blocksHtml(g.blocks)+'</section>').join('')+
        (refsCard? '<div class="docrefs">'+refsCard+'</div>' : '');
      // summary stat chips
      const stats=statsForSection(s);
      let chips='';
      if(stats.length){ chips='<div class="docstats">'+stats.map(c=>
        '<div class="docstat"><span class="si">'+ICONN.rows+'</span><div><div class="sv">'+c.v+'</div><div class="sk">'+esc(c.k)+'</div></div></div>').join('')+'</div>'; }
      const pageUrl=sitePageUrl(s.page);
      const openLink=pageUrl?sbtn('Open as a page','target="_top"',{go:true,cls:'dpage',href:pageUrl}):'';
      // The MITRE page links to the ATT&CK grid on the Insights tab.
      const akLink=(M.attack && /mitre/i.test(s.title||''))? sbtn('Open the ATT&amp;CK grid','data-akopen',{go:true,cls:'dpage'}) : '';
      content.innerHTML='<div class="docpanel"><div class="dhead"><span class="dbadge">'+esc(s.family)+'</span>'+akLink+openLink+'</div>'+
        '<h2 class="dtitle">'+esc(cleanTitle(s.title))+'</h2>'+chips+'<div class="docbody">'+(body||'<p class="docempty">No content.</p>')+'</div></div>';
      nav.querySelectorAll('.docitem').forEach(el=>el.classList.toggle('active', +el.dataset.num===s.num));
      content.querySelectorAll('[data-akopen]').forEach(a=>a.addEventListener('click',()=>{ if(activateTab) activateTab('sections'); bringTop(document.getElementById('akPanel')); }));
      // A long code token in a table (a resource path, a URL) may break after
      // a slash or a dot, so its column wraps there rather than mid-word.
      content.querySelectorAll('table.doct td code').forEach(c=>{
        if(c.children.length || c.textContent.length<=24) return;
        c.innerHTML=c.textContent.split(/(?<=[\/.?=&])/).map(esc).join('<wbr>');
      });
      // wire per-table sorting and filters
      content.querySelectorAll('table.doct thead th').forEach(th=>{ const b=th.querySelector('.thsort'); if(b) b.onclick=()=>sortTable(th.closest('table'), th); });
      content.querySelectorAll('.doctable-tools input').forEach(inp=>{ inp.oninput=()=>docFilter(inp.dataset.for); });
      content.querySelectorAll('.chipkey .fchip').forEach(k=>{ k.onclick=()=>{
        const on=!k.classList.contains('active');
        k.parentNode.querySelectorAll('.fchip').forEach(x=>{ x.classList.remove('active'); x.setAttribute('aria-pressed','false'); });
        if(on){ k.classList.add('active'); k.setAttribute('aria-pressed','true'); }
        docFilter(k.parentNode.dataset.for);
      }; });
      linkSolutionChips();
      linkGroupRows();
      layoutDoc();
      if(typeof fitIframe==='function') fitIframe();
    }

    // Filters a report table by its search box (every word, or "quoted
    // phrase", must appear in the row) and by its chip key when it has one.
    function docFilter(tid){
      const t=document.getElementById(tid); if(!t) return;
      const inp=content.querySelector('.doctable-tools input[data-for="'+tid+'"]');
      const q=inp? inp.value : '';
      const words=(q.toLowerCase().match(/"[^"]*"|\S+/g)||[]).map(w=>w.replace(/"/g,'').trim()).filter(Boolean);
      const k=content.querySelector('.chipkey[data-for="'+tid+'"] .fchip.active'), want=k? k.dataset.ck : '';
      // A solution chip pins the template list to its solution and table, exactly.
      const pin=t.dataset.pinSol!=null? {sol:t.dataset.pinSol, tbl:t.dataset.pinTbl} : null;
      const h=pin? headsOf(t) : [], iS=h.indexOf('solution'), iTb=h.indexOf('tables');
      const pinned=tr=>!pin || (tr.children[iS].textContent.trim()===pin.sol && tr.children[iTb].textContent.toLowerCase().split(',').map(x=>x.trim()).includes(pin.tbl.toLowerCase()));
      // A summary value picked above pins the table to the rows that hold it.
      const gp=t.dataset.pinCol!=null? {i:+t.dataset.pinCol, v:String(t.dataset.pinVal||'').trim().toLowerCase()} : null;
      const grouped=tr=>!gp || (!!tr.children[gp.i] && tr.children[gp.i].textContent.trim().toLowerCase()===gp.v);
      const rows=t.querySelectorAll('tbody tr'); let shown=0;
      rows.forEach(tr=>{ const txt=tr.textContent.toLowerCase(); const m=words.every(w=>txt.includes(w)) && (!want || tr.dataset[want]==='1') && pinned(tr) && grouped(tr); tr.style.display=m?'':'none'; if(m) shown++; });
      const c=document.getElementById(tid+'c'); if(c) c.textContent=(words.length||want||pin||gp? shown+' / ' : '')+rows.length+' rows';
      // With the key on, each row's chips narrow to that kind, every one of
      // them, so the row shows what is (or is not) installed; off, the first
      // chips and the chevron come back as they were.
      t.querySelectorAll('.cellchips').forEach(w=>{
        const chev=w.querySelector(':scope > .morechev');
        w.querySelectorAll('.chipl > .tagpill').forEach(ch=>{
          const ready=ch.classList.contains('inst');
          ch.hidden=want? (want==='ready'? !ready : ready) : (ch.hasAttribute('data-mr') && !w.classList.contains('open'));
        });
        if(chev) chev.hidden=!!want;
      });
      if(typeof fitIframe==='function') fitIframe();
    }
    // A chip in a From solutions column names a solution and how many of the
    // row's templates it ships; the page's template list (a table with
    // Template, Solution and Tables columns) says which. The chip lists them
    // in its tooltip and, selected, opens that list filtered to them.
    const headsOf=t=>[...t.querySelectorAll('thead th')].map(th=>th.textContent.trim().toLowerCase());
    function templateList(){
      return [...content.querySelectorAll('table.doct')].find(t=>{ const h=headsOf(t); return h.includes('template') && h.includes('solution') && h.includes('tables'); });
    }
    function linkSolutionChips(){
      const list=templateList(); if(!list) return;
      const lh=headsOf(list), iT=lh.indexOf('template'), iS=lh.indexOf('solution'), iTb=lh.indexOf('tables');
      // Table names compare without case, as the renderer counts them.
      const tpl=[...list.querySelectorAll('tbody tr')].map(tr=>({name:tr.children[iT].textContent.trim(), sol:tr.children[iS].textContent.trim(), tables:tr.children[iTb].textContent.toLowerCase().split(',').map(x=>x.trim())}));
      content.querySelectorAll('table.doct').forEach(t=>{
        const h=headsOf(t), iSrc=h.indexOf('from solutions'), iTab=h.indexOf('table'); if(iSrc<0 || iTab<0) return;
        t.querySelectorAll('tbody tr').forEach(tr=>{
          const tbl=tr.children[iTab].textContent.trim();
          tr.children[iSrc].querySelectorAll('.tagpill').forEach(ch=>{
            const m=/^(.*?) \((\d+)(?:,\s*installed)?\)$/.exec(ch.textContent.trim()); if(!m) return;
            const names=tpl.filter(x=>x.sol===m[1] && x.tables.includes(tbl.toLowerCase())).map(x=>x.name); if(!names.length) return;
            ch.classList.add('chiplink'); ch.tabIndex=0; ch.setAttribute('role','button');
            ch.dataset.sol=m[1]; ch.dataset.tbl=tbl;
            ch.title=names.join('\n')+'\n\nSelect to list '+(names.length===1?'it':'them')+' with severity, tactics and tables';
          });
        });
      });
    }
    function openTemplates(sol, tbl){
      const list=templateList(); if(!list) return;
      const pane=list.closest('.docpane');
      if(pane && pane.hidden){ const tab=document.getElementById(pane.getAttribute('aria-labelledby')); if(tab) tab.click(); }
      list.dataset.pinSol=sol; list.dataset.pinTbl=tbl;
      const wrap=list.closest('.doctable-wrap');
      let tools=wrap && wrap.querySelector('.doctable-tools');
      if(wrap && !tools){ tools=document.createElement('div'); tools.className='doctable-tools'; wrap.insertBefore(tools, wrap.firstChild); }
      if(tools){
        let chip=tools.querySelector('[data-unpin]');
        if(!chip){ chip=document.createElement('button'); chip.type='button'; chip.className='fchip active'; chip.setAttribute('data-unpin',''); tools.insertBefore(chip, tools.querySelector('.dtc')); }
        chip.innerHTML=esc(tbl)+' &middot; '+esc(sol)+'<span aria-hidden="true">&times;</span>';
        chip.title='The templates for '+tbl+' from '+sol+'. Select to show every template again.';
        chip.onclick=()=>{ delete list.dataset.pinSol; delete list.dataset.pinTbl; chip.remove(); docFilter(list.id); };
      }
      docFilter(list.id);
      bringTop(wrap||list);
    }
    content.addEventListener('click',e=>{ const ch=e.target.closest('.chiplink'); if(ch) openTemplates(ch.dataset.sol, ch.dataset.tbl); });
    content.addEventListener('keydown',e=>{ const ch=e.target.closest('.chiplink'); if(ch && (e.key==='Enter' || e.key===' ')){ e.preventDefault(); openTemplates(ch.dataset.sol, ch.dataset.tbl); } });

    // A small summary table whose first column groups a bigger table on the
    // same page (Summary by plan over the operational tables, by Plan): each
    // of its values opens the bigger table at the rows that hold it, so a
    // count always leads to what is behind it. The bigger table must repeat
    // values in that column, so a list never links to itself row by row.
    function tableTitleOf(t){
      const pane=t.closest('.docpane');
      if(pane){ const tab=document.getElementById(pane.getAttribute('aria-labelledby')); if(tab) return tab.textContent.trim(); }
      // Its section's heading (a chart's own heading is not one), else the
      // nearest heading above it.
      const el=t.closest('.doctable-wrap')||t, sec=el.closest('.docsec'), h=sec && sec.querySelector('.dsech');
      if(h) return h.textContent.trim();
      for(let p=el.previousElementSibling;p;p=p.previousElementSibling){ if(/^H[2-4]$/.test(p.tagName)) return p.textContent.trim(); }
      return '';
    }
    function linkGroupRows(){
      const tables=[...content.querySelectorAll('table.doct')];
      const norm=v=>String(v==null?'':v).trim().toLowerCase();
      tables.forEach(sum=>{
        const key=headsOf(sum)[0], sumRows=[...sum.querySelectorAll('tbody tr')];
        if(!key || !sumRows.length) return;
        // A summary has one row a value; a list that repeats them is not one.
        const sumVals=sumRows.map(tr=>norm(tr.children[0] && tr.children[0].textContent));
        if(new Set(sumVals).size!==sumVals.length) return;
        let best=null;
        tables.forEach(det=>{
          if(det===sum) return;
          const j=headsOf(det).indexOf(key); if(j<0) return;
          const vals=[...det.querySelectorAll('tbody tr')].map(tr=>norm(tr.children[j] && tr.children[j].textContent));
          if(vals.length<=sumRows.length || new Set(vals).size===vals.length) return;
          if(!best || vals.length>best.vals.length) best={det, j, vals};
        });
        if(!best) return;
        const where=tableTitleOf(best.det), th=best.det.querySelectorAll('thead th')[best.j], col=th? th.textContent.trim() : key;
        sumRows.forEach(tr=>{
          const cell=tr.children[0]; if(!cell || cell.querySelector('a,button,.grouplink,.tagpill')) return;
          const v=cell.textContent.trim(), n=best.vals.filter(x=>x===norm(v)).length; if(!v || !n) return;
          const g=document.createElement('span'); g.className='grouplink'; g.tabIndex=0; g.setAttribute('role','button');
          g.dataset.gdet=best.det.id; g.dataset.gcol=String(best.j); g.dataset.gval=v;
          g.title='Show the '+n.toLocaleString()+' row'+(n===1?'':'s')+(where? ' of '+where : '')+' whose '+col+' is '+v;
          while(cell.firstChild) g.appendChild(cell.firstChild);
          cell.appendChild(g);
        });
      });
    }
    function openGroup(detId, col, val){
      const det=document.getElementById(detId); if(!det) return;
      const pane=det.closest('.docpane');
      if(pane && pane.hidden){ const tab=document.getElementById(pane.getAttribute('aria-labelledby')); if(tab) tab.click(); }
      det.dataset.pinCol=String(col); det.dataset.pinVal=val;
      const wrap=det.closest('.doctable-wrap');
      let tools=wrap && wrap.querySelector('.doctable-tools');
      if(wrap && !tools){ tools=document.createElement('div'); tools.className='doctable-tools'; wrap.insertBefore(tools, wrap.firstChild); }
      if(tools){
        let chip=tools.querySelector('[data-ungroup]');
        if(!chip){ chip=document.createElement('button'); chip.type='button'; chip.className='fchip active'; chip.setAttribute('data-ungroup',''); tools.insertBefore(chip, tools.querySelector('.dtc')); }
        const th=det.querySelectorAll('thead th')[col], name=th? th.textContent.trim() : '';
        chip.innerHTML=esc(name)+': '+esc(val)+'<span aria-hidden="true">&times;</span>';
        chip.title='Only the rows whose '+name+' is '+val+'. Select to show every row again.';
        chip.onclick=()=>{ delete det.dataset.pinCol; delete det.dataset.pinVal; chip.remove(); docFilter(det.id); };
      }
      docFilter(det.id);
      bringTop(wrap||det);
    }
    content.addEventListener('click',e=>{ const g=e.target.closest('.grouplink'); if(g) openGroup(g.dataset.gdet, +g.dataset.gcol, g.dataset.gval); });
    content.addEventListener('keydown',e=>{ const g=e.target.closest('.grouplink'); if(g && (e.key==='Enter' || e.key===' ')){ e.preventDefault(); openGroup(g.dataset.gdet, +g.dataset.gcol, g.dataset.gval); } });

    // Links to another section open it here; links to a finding open it in
    // the findings view, or its section when this run's list does not hold
    // it. Both start at the top of what they open.
    const listedFindings=new Set(((M.findings&&M.findings.items)||[]).map(f=>f.id));
    content.addEventListener('click',e=>{
      // A diagram node linking to a section or a finding (/#sac-section-NN,
      // /#sac-finding-ID) opens it here, as a text link does.
      const wa=e.target.closest('.wpchart a'), wm=wa && /#sac-(section|finding)-(.+)$/.exec(wa.getAttribute('href')||'');
      if(wm){
        e.preventDefault();
        if(wm[1]==='finding' && listedFindings.has(wm[2]) && typeof window.showFinding==='function'){ window.showFinding(wm[2]); return; }
        const n=wm[1]==='section'? +wm[2] : 90;
        if(secs.some(x=>x.num===n)){ gotoDocSection(n); bringTop(content,true); }
        return;
      }
      const a=e.target.closest('a.xref'); if(!a||!content.contains(a)) return;
      e.preventDefault();
      if(a.dataset.xfind && listedFindings.has(a.dataset.xfind) && typeof window.showFinding==='function'){ window.showFinding(a.dataset.xfind); return; }
      const num=+a.dataset.xsec;
      if(a.dataset.xsec!=null && secs.some(x=>x.num===num)){ gotoDocSection(num); bringTop(content,true); }
    });
    function wireNav(){
      nav.querySelectorAll('.docitem').forEach(el=>el.onclick=()=>{ render(+el.dataset.num); bringTop(content,true); });
    }
    nav.innerHTML=navHtml('');
    wireNav();
    render(secs[0].num);
    search.oninput=()=>{ nav.innerHTML=navHtml(search.value); wireNav(); layoutDoc();
      const first=nav.querySelector('.docitem'); if(first && !nav.querySelector('.docitem.active')){ /* keep current */ } };
    // expose for cross-tab jumps (e.g. the gap-analysis buttons)
    gotoDocSection = function(num){
      if(search.value){ search.value=''; nav.innerHTML=navHtml(''); wireNav(); }
      render(num);
      const el = nav.querySelector('.docitem[data-num="'+num+'"]');
      if(el) el.scrollIntoView({block:'nearest'});
    };
    // A rule picked in the detection matrix opens Rule Performance with its
    // tables filtered to that rule, on the tab where it shows: its incidents
    // by verdict when it has any, else its alert volume. A table too short to
    // have a filter keeps its rows and marks the rule's.
    window.openRuleReport = function(name, counts){
      const sec=secs.find(x=>/^rule performance$/i.test(cleanTitle(x.title||'')));
      if(!sec) return false;
      if(activateTab) activateTab('sectionsdoc');
      gotoDocSection(sec.num);
      const want=String(name||'').replace(/"/g,'').trim(), low=want.toLowerCase();
      let best=null;
      content.querySelectorAll('table.doct').forEach(t=>{
        const inp=content.querySelector('.doctable-tools input[data-for="'+t.id+'"]');
        if(inp){ inp.value='"'+want+'"'; docFilter(t.id); }
        const hit=[...t.querySelectorAll('tbody tr')].find(tr=>tr.style.display!=='none' && tr.textContent.toLowerCase().includes(low));
        const inc=headsOf(t).includes('incidents');
        if(hit && (!best || (inc && !best.inc))) best={t, tr:hit, inc};
      });
      // A note above the tabs says which rule the tables show, and clears it.
      const c=counts||{}, nA=+c.alerts||0, nI=+c.incidents||0, body=content.querySelector('.docbody');
      const why=best? '' : (nA||nI)
        ? ' No table here lists it by this name: its '+(nA? nA.toLocaleString()+' alert'+(nA===1?'':'s') : 'alerts')+' in '+WIN.span()+' carry the alert names it gives them, in the alert volume table.'
        : ' It raised no alerts or incidents in the last '+WIN.cw()+', so no table here lists it.';
      if(body){
        const note=document.createElement('div'); note.className='docnote rulepin';
        note.innerHTML='<span>Rule Performance for <b>'+esc(want)+'</b>.'+esc(why)+'</span>'+sbtn('Show every rule','data-unpin-rule');
        const desc=body.querySelector(':scope > .docdesc'); body.insertBefore(note, desc? desc.nextSibling : body.firstChild);
        note.querySelector('[data-unpin-rule]').onclick=()=>{ content.querySelectorAll('.doctable-tools input[data-for]').forEach(i=>{ i.value=''; docFilter(i.dataset.for); }); note.remove(); };
      }
      if(!best){ bringTop(content); return true; }
      const pane=best.t.closest('.docpane');
      if(pane && pane.hidden){ const tab=document.getElementById(pane.getAttribute('aria-labelledby')); if(tab) tab.click(); }
      best.tr.classList.add('rowpick'); setTimeout(()=>best.tr.classList.remove('rowpick'),2600);
      bringTop(best.t.closest('.doctable-wrap')||best.t);
      return true;
    };
  })();

