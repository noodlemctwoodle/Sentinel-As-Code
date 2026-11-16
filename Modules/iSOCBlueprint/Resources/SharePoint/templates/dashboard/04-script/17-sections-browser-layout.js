    const ICONN2={ info: svg('<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><circle cx="12" cy="8" r=".6"/>'),
      success: svg('<circle cx="12" cy="12" r="9"/><path d="m8 12.5 2.5 2.5L16 9.5"/>'),
      warning: svg('<path d="M10.3 3.9 2.4 18a2 2 0 0 0 1.7 3h15.8a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4"/><circle cx="12" cy="17" r=".6"/>'),
      critical: svg('<path d="M8.6 2.5h6.8l4.9 4.9v6.8l-4.9 4.9H8.6l-4.9-4.9V7.4z"/><path d="M12 8v5"/><circle cx="12" cy="16" r=".6"/>') };

    // Page layout (layoutDoc): no Report page runs past the bottom of the
    // contents list beside it.
    // 1. A page that fits reads top to bottom, its scrolling tables (cut off
    //    at 620px) growing into any space left above the list's foot.
    // 2. A taller page with two or more main sections (## in the Markdown)
    //    shows a tab at a time. A section with DOC_TAB_SMALL or more table
    //    rows starts a tab; a smaller one (a short table or only text) joins
    //    the tab before it while it fits, keeping its heading; small
    //    sections at the start make an Overview tab. The intro stays above
    //    the tabs unless it is tall, when it opens the Overview tab.
    // 3. A tab or page still too tall shrinks its tallest tables first, to
    //    DOC_TABLE_MIN, and as a last resort scrolls inside the panel.
    // It runs when a page or tab opens, on resize and when the contents
    // search changes the list. In one column (a narrow screen) the page
    // reads top to bottom. Returning to a page reopens its last tab.
    const DOC_TAB_SMALL=20, DOC_TABLE_MIN=200, DOC_STRIP=76, lastDocTab={};
    let curDocNum=null;
    // A tab shows its heading without a closing qualifier in brackets
    // ("Playbook runs (last 7d)" reads "Playbook runs"); the full heading
    // is its tooltip and opens the tab's content.
    const shortLabel=l=>{ const s2=l.replace(/\s*\([^()]*\)\s*$/,'').trim(); return s2||l; };
    const outerH=x=>{ const st=getComputedStyle(x); return x.getBoundingClientRect().height+(parseFloat(st.marginTop)||0)+(parseFloat(st.marginBottom)||0); };
    // Where the visible content of an element ends: its last shown child and
    // that child's bottom margin.
    const contentEnd=el=>[...el.children].filter(x=>x.offsetParent).reduce((m,x)=>Math.max(m, x.getBoundingClientRect().bottom+(parseFloat(getComputedStyle(x).marginBottom)||0)), el.getBoundingClientRect().top);
    function docLimit(panel){
      const navBox=document.querySelector('.docwrap>.docnav'), cs=getComputedStyle(panel);
      return navBox.getBoundingClientRect().bottom-(parseFloat(cs.paddingBottom)||0)-(parseFloat(cs.borderBottomWidth)||0);
    }
    // Grow the scrolling tables in scope into the space above limit, in page
    // order; when the content ends below limit, shrink the tallest first.
    function fitTables(scope, limit, end){
      const boxes=[...scope.querySelectorAll('.doctscroll')].filter(x=>x.offsetParent);
      boxes.forEach(x=>{ x.style.maxHeight=''; });
      let slack=limit-end();
      if(slack>1){
        for(const x of boxes){
          if(slack<=1) break;
          const need=x.scrollHeight-x.clientHeight; if(need<=0) continue;
          const add=Math.min(need,slack); x.style.maxHeight=(x.clientHeight+add)+'px'; slack-=add;
        }
      } else if(slack< -1){
        let over=-slack;
        for(const x of boxes.slice().sort((a,b)=>b.clientHeight-a.clientHeight)){
          if(over<=1) break;
          const can=x.clientHeight-Math.min(DOC_TABLE_MIN, x.scrollHeight); if(can<=0) continue;
          const cut=Math.min(can,over); x.style.maxHeight=(x.clientHeight-cut)+'px'; over-=cut;
        }
      }
    }
    // The last resort: scope scrolls inside the panel, down to limit.
    function contain(scope, limit, end){
      if(end()-limit>1){ scope.style.maxHeight=Math.max(160, limit-scope.getBoundingClientRect().top)+'px'; scope.style.overflow='auto'; }
    }
    function unTab(body){
      body.classList.remove('tabbed');
      [...body.querySelectorAll(':scope > .docpane')].forEach(p=>{ [...p.children].forEach(c=>{ c.classList.remove('lead'); body.appendChild(c); }); p.remove(); });
      const strip=body.querySelector(':scope > .doctabs'); if(strip) strip.remove();
      const refs=body.querySelector(':scope > .docrefs'); if(refs) body.appendChild(refs);
    }
    // Tables on screen together with the same columns (Microsoft References'
    // topic tables, the Conventions KQL tables) share their column widths so
    // they line up. Each column takes the most it needs in any of them, as
    // the browser lays it out on its own: a column that keeps to one line
    // holds that width, and the columns that wrap share what is left. A table
    // on its own, or in another tab, keeps the browser's layout. Run when a
    // page or tab is laid out, so it follows a resize.
    function alignTables(scope){
      const groups={};
      scope.querySelectorAll('table.doct').forEach(t=>{
        const cg=t.querySelector(':scope > colgroup.samecols'); if(cg) cg.remove();
        t.style.tableLayout=''; t.style.width='';
        t.querySelectorAll('.flexw').forEach(c=>c.classList.remove('flexw'));
        if(!t.offsetParent || !t.tHead) return;
        const sig=[...t.tHead.rows[0].cells].map(th=>th.textContent.trim()).join('|');
        (groups[sig]=groups[sig]||[]).push(t);
      });
      Object.values(groups).forEach(ts=>{
        if(ts.length<2) return;
        const n=ts[0].tHead.rows[0].cells.length, need=new Array(n).fill(0), flex=new Array(n).fill(false);
        ts.forEach(t=>{
          t.style.width='auto';
          [...t.tHead.rows[0].cells].forEach((th,i)=>{ if(i<n){ need[i]=Math.max(need[i], Math.ceil(th.getBoundingClientRect().width)); if(th.classList.contains('wrap')) flex[i]=true; } });
          t.querySelectorAll('tbody td.wrap').forEach(td=>{ if(td.cellIndex<n) flex[td.cellIndex]=true; });
          t.style.width='';
        });
        const room=Math.min(...ts.map(t=>t.parentElement.clientWidth));
        const fixed=need.reduce((a,x,i)=>a+(flex[i]?0:x),0), flexNeed=need.reduce((a,x,i)=>a+(flex[i]?x:0),0);
        const left=Math.max(flex.filter(Boolean).length*180, room-fixed);
        const px=need.map((x,i)=>flex[i]? Math.max(180, Math.floor(flexNeed? left*x/flexNeed : 0)) : x);
        ts.forEach(t=>{
          const cg=document.createElement('colgroup'); cg.className='samecols';
          px.forEach(w=>{ const c=document.createElement('col'); c.style.width=w+'px'; cg.appendChild(c); });
          t.insertBefore(cg, t.firstChild); t.style.tableLayout='fixed';
          // Every cell of a column that wraps may wrap, short ones included.
          t.querySelectorAll('tr').forEach(tr=>[...tr.cells].forEach(c=>{ if(c.cellIndex<n && flex[c.cellIndex]) c.classList.add('flexw'); }));
        });
      });
    }
    // A pane that gains a scrollbar once it is fitted narrows its tables; the
    // shared widths are worked out again for the room that is left.
    function realign(scope){
      if([...scope.querySelectorAll('table.doct')].some(t=>t.style.tableLayout==='fixed' && t.offsetParent && t.offsetWidth>t.parentElement.clientWidth+1)) alignTables(scope);
    }
    function showTab(body, i, focus){
      const tabs=[...body.querySelectorAll(':scope > .doctabs .doctab')], panes=[...body.querySelectorAll(':scope > .docpane')];
      if(!tabs.length) return;
      i=Math.max(0, Math.min(i, tabs.length-1));
      tabs.forEach((b,j)=>{ const on=j===i; b.setAttribute('aria-selected',on); b.tabIndex=on?0:-1; panes[j].hidden=!on; panes[j].style.maxHeight=''; panes[j].style.overflow=''; });
      lastDocTab[curDocNum]=i;
      const panel=body.closest('.docpanel'), limit=docLimit(panel), end=()=>contentEnd(body);
      alignTables(panes[i]);
      fitTables(panes[i], limit, end);
      contain(panes[i], limit, end);
      realign(panes[i]);
      if(focus) tabs[i].focus();
    }
    function layoutDoc(){
      const panel=content.querySelector('.docpanel'), body=panel&&panel.querySelector('.docbody'), navBox=document.querySelector('.docwrap>.docnav');
      if(!body || !navBox || !content.offsetParent) return;
      const done=()=>{ if(typeof fitIframe==='function') fitIframe(); };
      // Back to the flat page.
      unTab(body);
      const parts=[...body.querySelectorAll(':scope > .docintro, :scope > .docsec')];
      [body, ...parts].forEach(x=>{ x.style.maxHeight=''; x.style.overflow=''; });
      body.querySelectorAll('.doctscroll').forEach(x=>{ x.style.maxHeight=''; });
      // One column: the page reads top to bottom.
      if(navBox.getBoundingClientRect().right > content.getBoundingClientRect().left+1){ alignTables(body); return done(); }
      const limit=docLimit(panel), end=()=>contentEnd(body);
      const secEls=parts.filter(x=>x.classList.contains('docsec')), introEl=parts.find(x=>x.classList.contains('docintro'));
      if(end()<=limit+1 || secEls.length<2){ alignTables(body); fitTables(body, limit, end); contain(body, limit, end); realign(body); return done(); }
      // Pack the sections into tabs no taller than the space under the strip.
      const firstTop=(introEl||secEls[0]).getBoundingClientRect().top;
      const introAbove=!!introEl && outerH(introEl) <= (limit-firstTop)*0.3;
      const cap=limit-firstTop-(introAbove?outerH(introEl):0)-DOC_STRIP;
      const items=((introEl&&!introAbove)? [{el:introEl, rows:0, label:'Overview', big:false, h:outerH(introEl)}] : [])
        .concat(secEls.map(el=>({el, rows:+el.dataset.rows||0, label:el.dataset.label||'', big:(+el.dataset.rows||0)>=DOC_TAB_SMALL, h:outerH(el)})));
      const tabsDef=[]; let cur=null;
      items.forEach(it=>{
        if(!cur || (it.big && cur.items.length) || cur.h+it.h>cap){ cur={items:[], h:0}; tabsDef.push(cur); }
        cur.items.push(it); cur.h+=it.h;
      });
      if(tabsDef.length<2){ alignTables(body); fitTables(body, limit, end); contain(body, limit, end); realign(body); return done(); }
      tabsDef.forEach((t,i)=>{ t.full=t.items[0].big? t.items[0].label : (i===0? 'Overview' : t.items[0].label); t.rows=t.items.reduce((a,x)=>a+x.rows,0); });
      // Build the strip and the panes; a tab's own section heading is its
      // label, so that heading hides inside the tab.
      const panes=tabsDef.map((t,i)=>{
        const p=document.createElement('div'); p.className='docpane'; p.setAttribute('role','tabpanel'); p.id='dpane'+i; p.setAttribute('aria-labelledby','dtab'+i);
        t.items.forEach((it,j)=>{ if(j===0 && it.label===t.full && shortLabel(t.full)===t.full) it.el.classList.add('lead'); p.appendChild(it.el); });
        return p;
      });
      const strip=document.createElement('div'); strip.className='doctabs'; strip.setAttribute('role','tablist'); strip.setAttribute('aria-label','Sections of this page');
      tabsDef.forEach((t,i)=>{
        const b=document.createElement('button'), short=shortLabel(t.full);
        b.type='button'; b.className='doctab'; b.id='dtab'+i; b.setAttribute('role','tab'); b.setAttribute('aria-controls','dpane'+i);
        if(short!==t.full) b.title=t.full;
        b.innerHTML=esc(short)+(t.rows?'<span class="dtn">'+t.rows.toLocaleString()+'</span>':'');
        b.onclick=()=>{ showTab(body, i, false); bringTop(strip,true); done(); };
        b.onkeydown=e=>{
          const k={ArrowRight:(i+1)%tabsDef.length, ArrowLeft:(i-1+tabsDef.length)%tabsDef.length, Home:0, End:tabsDef.length-1}[e.key];
          if(k!=null){ e.preventDefault(); showTab(body, k, true); done(); }
        };
        strip.appendChild(b);
      });
      body.appendChild(strip); panes.forEach(p=>body.appendChild(p));
      const refs=body.querySelector(':scope > .docrefs'); if(refs) body.appendChild(refs);
      body.classList.add('tabbed');
      showTab(body, lastDocTab[curDocNum]||0, false);
      done();
    }
    window.layoutDoc=layoutDoc;
    // A paragraph of figures ("**MTTA:** 2130.4 min  ·  **MTTR:** ...") reads
    // as tiles: the label, the value (a duration in minutes made readable,
    // the exact figure in the tooltip) and a closing bracketed qualifier as
    // a caption. "**439** tables with data" puts the number as the value.
    // Only when at least half the values are figures: a finding's severity
    // and category line stays as text.
    const KV_SEG=/^\s*<strong>([^<]{1,80}?)\s*:?\s*<\/strong>\s*:?\s*(.*?)\s*$/;
    const fmtMinutes=n=>{ const m=Math.round(n), d=Math.floor(m/1440), h=Math.floor(m%1440/60), mi=m%60; return d? d+'d '+h+'h' : h? h+'h '+mi+'m' : mi+' min'; };
    function kvTiles(html){
      const parts=String(html).split(/\s+·\s+/); if(parts.length<2) return '';
      const segs=parts.map(x=>KV_SEG.exec(x)); if(segs.some(x=>!x)) return '';
      const plain=x=>x.replace(/<[^>]+>/g,'').trim();
      const tiles=segs.map(x=>{
        let k=x[1].trim(), v=x[2].trim(), cap='', tip='';
        if(/^[\d.,]+%?$/.test(plain(k)) && v){ const n=k; k=v; v=n; }
        const c=/^(.*?)\s*\(([^()]+)\)\s*$/.exec(v); if(c && c[1]){ v=c[1]; cap=c[2]; }
        const mm=/^([\d.,]+)\s*min$/.exec(plain(v)); if(mm){ const n=parseFloat(mm[1].replace(/,/g,'')); if(n>=60){ tip=plain(v); v=fmtMinutes(n); } }
        if(/^\d{5,}$/.test(plain(v))) v=Number(plain(v)).toLocaleString();
        return {k,v,cap,tip};
      });
      if(tiles.filter(x=>/^[£$€]?\s*\d/.test(plain(x.v))).length*2 < tiles.length) return '';
      return '<div class="kvtiles">'+tiles.map(x=>'<div class="kvt"'+(x.tip?' title="'+esc(x.tip)+'"':'')+'><div class="kvk">'+x.k+'</div><div class="kvv">'+x.v+'</div>'+(x.cap?'<div class="kvc">'+x.cap+'</div>':'')+'</div>').join('')+'</div><!--/kv-->';
    }
    // A paragraph or list that holds only links (the Microsoft Learn pointers
    // that close a page, a finding's "Reference:", "See A and B.") reads as a
    // card of link tiles, each with the page title and the product area it
    // belongs to, rather than a run of links side by side.
    const REF_AREAS=[[/^azure\/sentinel/,'Microsoft Sentinel'],[/^azure\/azure-monitor/,'Azure Monitor'],[/^defender-xdr/,'Microsoft Defender XDR'],
      [/^unified-secops/,'Unified security operations'],[/^azure\/azure-resource-manager/,'Azure Resource Manager'],[/^rest\/api/,'Azure REST API'],
      [/^entra/,'Microsoft Entra'],[/^graph/,'Microsoft Graph'],[/^azure\/developer\/github/,'GitHub Actions'],[/^azure\/logic-apps/,'Azure Logic Apps'],
      [/^azure\/role-based-access-control/,'Azure RBAC'],[/^azure\/defender-for-cloud/,'Defender for Cloud'],[/^kusto/,'Kusto Query Language'],
      [/^azure\/governance/,'Azure governance'],[/^purview/,'Microsoft Purview'],[/^copilot/,'Security Copilot']];
    function refArea(href){
      try{
        const u=new URL(href);
        if(!/(^|\.)learn\.microsoft\.com$/i.test(u.hostname)) return u.hostname.replace(/^www\./,'');
        const path=u.pathname.replace(/^\/+/,'').replace(/^[a-z]{2}-[a-z]{2}\//i,'');
        const hit=REF_AREAS.find(a=>a[0].test(path)); if(hit) return hit[1];
        const seg=path.split('/').filter(Boolean), one=(seg[0]==='azure'&&seg[1])? seg[1] : (seg[0]||'');
        return one? one.replace(/-/g,' ').replace(/^./,c=>c.toUpperCase()) : 'Microsoft Learn';
      }catch(e){ return ''; }
    }
    const REF_BOOK='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 4h6a4 4 0 0 1 4 4v13a3 3 0 0 0-3-3H2z"/><path d="M22 4h-6a4 4 0 0 0-4 4v13a3 3 0 0 1 3-3h7z"/></svg>';
    const REF_LINK='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/></svg>';
    const REF_GO='<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 17 17 7M8 7h9v9"/></svg>';
    function refLinks(html, heading){
      const A=/<a\b[^>]*>[\s\S]*?<\/a>/g, src=String(html||''), links=src.match(A);
      if(!links) return '';
      const rest=src.replace(A,' ').replace(/<[^>]+>/g,' ').trim()
        .replace(/^(see also|see|references?|docs|further reading|read more)\s*:?/i,'').replace(/\band\b|&middot;|[·,;.:\s]/gi,'');
      if(rest) return '';
      const seen=new Set(), items=[];
      for(const a of links){
        const href=((/\shref="([^"]*)"/.exec(a)||[])[1]||'').replace(/&amp;/g,'&');
        if(!/^https?:\/\//i.test(href)) return '';
        if(seen.has(href)) continue; seen.add(href);
        const title=a.replace(/^<a\b[^>]*>|<\/a>$/g,'').replace(/\s*\((?:Microsoft Learn|[a-z0-9-]+\.(?:org|com|io|net))\)\s*$/i,'').trim();
        items.push({href, title:title||esc(href), area:refArea(href), learn:/(^|\.)learn\.microsoft\.com$/i.test((()=>{ try{ return new URL(href).hostname; }catch(e){ return ''; } })())});
      }
      if(!items.length) return '';
      const head=heading || (items.every(x=>x.learn)? 'Microsoft Learn' : 'Further reading');
      return '<div class="refs"><div class="refs-h">'+REF_BOOK+head+'</div><div class="refl">'+
        items.map(x=>'<a class="refa" href="'+esc(x.href)+'" target="_blank" rel="noopener"><span class="refi">'+(x.learn?REF_BOOK:REF_LINK)+'</span>'+
          '<span class="reft"><span class="refn">'+x.title+'</span>'+(x.area?'<span class="refsub">'+esc(x.area)+'</span>':'')+'</span><span class="refgo">'+REF_GO+'</span></a>').join('')+
        '</div></div><!--/refs-->';
    }
    let layoutDocTimer=null;
    window.addEventListener('resize',()=>{ clearTimeout(layoutDocTimer); layoutDocTimer=setTimeout(layoutDoc,150); });
