  // ---- sections browser (full documentation) ----
  (function(){
    const nav = document.getElementById('docNav');
    const content = document.getElementById('docContent');
    const search = document.getElementById('docSearch');
    const secs = M.sections || [];
    if(!secs.length){ content.innerHTML='<div class="docpanel"><p class="docempty">No sections in this snapshot.</p></div>'; return; }

    // group by family, preserving first-seen order
    const fams=[]; const byFam={};
    secs.forEach(s=>{ if(!byFam[s.family]){byFam[s.family]=[];fams.push(s.family);} byFam[s.family].push(s); });

    // strip "(TOC 4.8)"-style suffixes and the "Microsoft Sentinel " prefix noise for tidy labels
    const cleanTitle = t => (t||'').replace(/\s*\(TOC[^)]*\)\s*$/i,'').trim();
    function navHtml(filter){
      const q=(filter||'').toLowerCase();
      let html='';
      fams.forEach(f=>{
        const items=byFam[f].filter(s=> !q || s.title.toLowerCase().includes(q) || String(s.num).includes(q) || f.toLowerCase().includes(q));
        if(!items.length) return;
        html+='<div class="docfam">'+esc(f)+'</div>';
        items.forEach(s=>{
          html+='<div class="docitem" data-num="'+s.num+'">'+
            '<span class="dtt" title="'+esc(cleanTitle(s.title))+'">'+esc(cleanTitle(s.title))+'</span></div>';
        });
      });
      return html || '<div class="docempty">No matches.</div>';
    }

    const NUM_PREFIX=/^-?\s*(?:[A-Z]{2,3}\$|[A-Z]{3} |[£$€¥₹₩]|<)\s*/;
    const isNum = v => v!=='' && v!=null && !isNaN(String(v).trim().replace(NUM_PREFIX,'').replace(/[, %]/g,''));
    const toNum = v => parseFloat(String(v).trim().replace(NUM_PREFIX,'').replace(/[, %]/g,''))||0;
    const ICONN = {
      stat: svg('<path d="M3 3v18h18"/><path d="m7 14 3-3 3 3 5-6"/>'),
      rows: svg('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M9 4v16"/>')
    };

    // Build an auto bar-chart from a table whose first text column labels a single
    // numeric column — but only when it's genuinely chartable (few rows, varied values).
    function chartFromTable(b){
      if(!b.rows.length || b.rows.length>12) return '';
      const numCols=[]; 
      for(let ci=0;ci<b.headers.length;ci++){
        const vals=b.rows.map(r=>r[ci]);
        const allNum = vals.every(v=>isNum(v));
        if(allNum){ numCols.push(ci); }
      }
      // label column = first non-numeric column
      let labelCol=-1;
      for(let ci=0;ci<b.headers.length;ci++){ if(numCols.indexOf(ci)<0){ labelCol=ci; break; } }
      if(labelCol<0 || numCols.length===0) return '';
      // pick the numeric column with the most spread / meaning (prefer GB/cost/count-ish)
      let valCol = numCols.find(ci=>/gb|cost|count|total|alerts|events|rows|tables|value|usd|£|\$/i.test(b.headers[ci]));
      // No column that clearly holds an amount: no chart. Falling back to the
      // last number column charted whatever it held (an Unknown count, say).
      if(valCol==null) return '';
      const items=b.rows.map(r=>({label:r[labelCol].replace(/<[^>]+>/g,''), v:toNum(r[valCol]), disp:r[valCol].replace(/<[^>]+>/g,'')}))
        .filter(x=>x.label);
      const max=Math.max(...items.map(x=>x.v),0);
      if(max<=0) return '';
      const distinct=new Set(items.map(x=>x.v)).size; if(distinct<2 && items.length<3) return '';
      const bars=items.map(x=>'<div class="cbar"><div class="cl" title="'+x.label+'">'+x.label+'</div>'+
        '<div class="ct"><div class="cf" style="--w:'+Math.max(2,x.v/max*100)+'%"></div></div>'+
        '<div class="cv">'+esc(x.disp)+'</div></div>').join('');
      return '<div class="docchart"><div class="cct">'+esc(b.headers[labelCol])+' &middot; '+esc(b.headers[valCol])+'</div>'+
        '<div class="ccn">Visualised from the table below.</div>'+bars+'</div>';
    }

    // The section model's own charts (pie and xy; the other kinds are drawn
    // by the chart web part on the section's SharePoint page).
    const PAL=['#2563eb','#6d5efc','#0d9488','#d97706','#db2777','#16a34a','#0891b2','#a16207','#64748b','#dc2626'];
    const SEVC={High:'#ff4d1f',Medium:'#ffaa00',Low:'#fff100',Informational:'#8a8886',Info:'#64748b',Warning:'#d97706',Critical:'#991b1b'};
    const fmtNum=v=>{ const n=+v; if(!isFinite(n)) return String(v==null?'':v); return Number.isInteger(n)? n.toLocaleString('en-GB') : n.toLocaleString('en-GB',{maximumFractionDigits:2}); };
    const oneLine=s=>String(s==null?'':s).replace(/\s*\n\s*/g,' ');
    function pieChartHtml(b){
      const sl=((b.data&&b.data.slices)||[]).filter(x=>+x.value>0);
      if(!sl.length) return '';
      const total=sl.reduce((a,x)=>a+(+x.value),0);
      const items=sl.map((x,i)=>({label:oneLine(x.label), value:+x.value, display:fmtNum(x.value), color:SEVC[oneLine(x.label)]||PAL[i%PAL.length]}));
      return '<div class="docchart"><div class="cct">'+esc(oneLine(b.title))+'</div>'+
        donutMultiHtml(items, fmtNum(total), 'total')+'</div>';
    }
    function xyChartHtml(b){
      const d=b.data||{}, labels=((d.xAxis&&d.xAxis.labels)||[]).map(oneLine);
      const series=(d.series||[]).filter(x=>x&&x.values&&x.values.length);
      if(!labels.length||!series.length) return '';
      const peak=Math.max(0,...series.map(x=>Math.max(0,...x.values.map(v=>+v||0))));
      const yMax=(d.yAxis&&+d.yAxis.max>0)? Math.max(+d.yAxis.max,peak) : peak;
      if(!(yMax>0)) return '';
      const multi=series.length>1;
      const col=si=>SEVC[series[si].name]||PAL[si%PAL.length];
      const rows=labels.map((lbl,i)=>{
        const bars=series.map((x,si)=>{ const v=+x.values[i]||0;
          return '<div class="ct'+(multi?' thin':'')+'"><div class="cf'+(multi?' solid':'')+'" style="--w:'+(v>0?Math.max(2,v/yMax*100):0)+'%'+(multi?';--c:'+col(si):'')+'"></div></div>'; }).join('');
        return '<div class="cbar"><div class="cl" title="'+esc(lbl)+'">'+esc(lbl)+'</div><div class="cts">'+bars+'</div>'+
          '<div class="cv">'+series.map(x=>esc(fmtNum(x.values[i]))).join(' / ')+'</div></div>';
      }).join('');
      const legend=multi? '<div class="legend">'+series.map((x,si)=>'<span><i style="background:'+col(si)+'"></i>'+esc(x.name||('Series '+(si+1)))+'</span>').join('')+'</div>' : '';
      const axis=d.yAxis&&d.yAxis.title? esc(oneLine(d.yAxis.title))+(d.yAxis.max!=null&&+d.yAxis.max>0&&+d.yAxis.min===0?', 0 to '+esc(fmtNum(d.yAxis.max)):'') : '';
      // The key goes above the bars, where it is read first.
      return '<div class="docchart"><div class="cct">'+esc(oneLine(b.title))+'</div>'+(axis?'<div class="ccn">'+axis+'</div>':'')+(legend?legend.replace('class="legend"','class="legend top"'):'')+'<div class="cbars">'+rows+'</div></div>';
    }
    // Every other kind (state, journey, flowchart, sankey, gantt, timeline,
    // mindmap, class, sequence) is drawn by the chart web part's renderers,
    // bundled in as window.SacCharts, in the page's own colours, so a
    // diagram looks the same here and on its SharePoint page. They redraw
    // when the theme changes.
    const wpCharts=[];
    function wpTheme(){
      const cs=getComputedStyle(document.documentElement), v=n=>cs.getPropertyValue(n).trim();
      return {text:v('--ink'), muted:v('--muted'), line:v('--line'), surface:v('--panel'), accent:v('--brand'), dark:document.documentElement.dataset.theme==='dark'};
    }
    if(window.SacCharts && SacCharts.setTextMeasurer){
      const cx=document.createElement('canvas').getContext('2d');
      if(cx) SacCharts.setTextMeasurer((text,size,bold)=>{ cx.font=(bold?'600 ':'')+size+'px '+SacCharts.FONT; return cx.measureText(text).width; });
    }
    function wpChartHtml(b){
      if(!(window.SacCharts && SacCharts.renderChart)) return '';
      const i=wpCharts.push({kind:b.kind, title:b.title, data:b.data, source:b.source})-1;
      return '<div class="wpchart" data-wpc="'+i+'">'+SacCharts.renderChart(wpCharts[i], wpTheme())+'</div>';
    }
    window.addEventListener('sac-theme',()=>{
      if(!window.SacCharts) return;
      content.querySelectorAll('.wpchart[data-wpc]').forEach(el=>{ const c=wpCharts[+el.dataset.wpc]; if(c) el.innerHTML=SacCharts.renderChart(c, wpTheme()); });
    });
    const chartHtml=b=> b.kind==='pie'? pieChartHtml(b) : b.kind==='xy'? xyChartHtml(b) : wpChartHtml(b);

    // Summary stat chips: only clean, meaningful ones — a numeric key/value table
    // (e.g. "Connectors 3") yields a chip per row; generic data tables do not.
    function statsForSection(s){
      const chips=[];
      (s.blocks||[]).forEach(b=>{
        if(b.t!=='table' || b.headers.length!==2) return;
        // KV shape: col0 = short noun label, col1 = a number, few rows
        if(b.rows.length<2 || b.rows.length>8) return;
        const labels=b.rows.map(r=>r[0].replace(/<[^>]+>/g,'').trim());
        const vals=b.rows.map(r=>r[1].replace(/<[^>]+>/g,'').trim());
        const allNumVals=vals.every(v=>isNum(v));
        const shortLabels=labels.every(l=>l && l.length<=22 && /[a-z]/i.test(l));
        if(!allNumVals || !shortLabels) return;
        b.rows.forEach(r=>{ const k=r[0].replace(/<[^>]+>/g,'').trim(), v=r[1].replace(/<[^>]+>/g,'').trim();
          if(k && v && toNum(v)>0) chips.push({v:v, k:k}); });
      });
      const seen={}; const uniq=[];
      chips.forEach(c=>{ const key=c.k.toLowerCase(); if(!seen[key]){seen[key]=1;uniq.push(c);} });
      return uniq.slice(0,6);
    }

    // Column sorting: selecting a column title sorts the table by it,
    // ascending, then descending, then back to the page's order. A column
    // whose cells are all numbers (commas, a currency sign, a percent, or a
    // unit such as GB or d allowed; KB to TB scaled) sorts by value, any
    // other in natural text order (Rule 2 before Rule 10). Empty cells go
    // last either way. The row filter keeps working on the sorted rows.
    const SORT_UNITS={kb:1e3,mb:1e6,gb:1e9,tb:1e12};
    // A date as the pages write it (15 Oct 2026, 15 Oct 2026 21:03 UTC)
    // sorts by time; an amount by value whatever its currency (£, US$,
    // SEK); a trace (<0.01) as its bound.
    const SORT_DATE=/^(\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4})(?: (\d{2}):(\d{2}))?(?: UTC)?$/;
    const sortNum=s=>{ const dm=SORT_DATE.exec(String(s).trim()); if(dm) return Date.UTC(+dm[3], MONTHS.indexOf(dm[2]), +dm[1], +(dm[4]||0), +(dm[5]||0));
      const m=/^\s*(-)?\s*(?:[A-Z]{2,3}\$|[A-Z]{3} |[£$€¥₹₩])?\s*<?\s*([+-]?[\d,]*\.?\d+)\s*(%|[a-z]{1,4})?\s*$/i.exec(s); if(!m) return null;
      const v=parseFloat(m[2].replace(/,/g,'')); if(isNaN(v)) return null; return (m[1]?-1:1)*v*(SORT_UNITS[(m[3]||'').toLowerCase()]||1); };
    const sortCollator=new Intl.Collator(undefined,{numeric:true,sensitivity:'base'});
    function sortTable(table, th){
      const tb=table.tBodies[0]; if(!tb) return;
      const ci=th.cellIndex, rows=[...tb.rows];
      rows.forEach((r,i)=>{ if(r.dataset.i==null) r.dataset.i=i; });
      const next={none:'ascending',ascending:'descending',descending:'none'}[th.getAttribute('aria-sort')||'none'];
      table.querySelectorAll('thead th').forEach(h=>h.setAttribute('aria-sort','none'));
      th.setAttribute('aria-sort',next);
      let order;
      if(next==='none'){ order=rows.slice().sort((a,b)=>a.dataset.i-b.dataset.i); }
      else {
        const vals=rows.map(r=>(r.cells[ci]?r.cells[ci].textContent:'').trim()), filled=vals.filter(v=>v!=='');
        const numeric=filled.length>0 && filled.every(v=>sortNum(v)!==null), dir=next==='ascending'?1:-1;
        order=rows.map((r,i)=>({r, v:vals[i], n:numeric?sortNum(vals[i]):0, i:+r.dataset.i}))
          .sort((a,b)=>{
            if(a.v===''||b.v==='') return (a.v==='')-(b.v==='') || a.i-b.i;
            const c=numeric? a.n-b.n : sortCollator.compare(a.v,b.v);
            return c? c*dir : a.i-b.i;
          }).map(k=>k.r);
      }
      const frag=document.createDocumentFragment(); order.forEach(r=>frag.appendChild(r)); tb.appendChild(frag);
    }
    function tableHtml(b, idx){
      const many = b.rows.length>12;
      const wrapCols = b.headers.map(h=>/name|title|data ?types|role|remediation|evidence|finding|description|principal|resource|query|source|identifier|statuses|surface|applies ?to|capability|meter|tags/i.test(h));
      // A column is numeric when every non-empty cell is a number; its header
      // and cells then right-align together so the figures sit under the title.
      const plain=v=>String(v==null?'':v).replace(/<[^>]+>/g,'').trim();
      const numCols = b.headers.map((h,ci)=> !wrapCols[ci] && b.rows.some(r=>plain(r[ci])!=='') && b.rows.every(r=>plain(r[ci])===''||isNum(plain(r[ci]))));
      // A key/value table ('| | |' in the Markdown) has no column names: no
      // header row, as on the site's pages, rather than a band of sort arrows.
      const thead=b.headers.every(h=>plain(h)==='')? '' : '<thead><tr>'+b.headers.map((h,ci)=>'<th class="'+(wrapCols[ci]?'wrap':'')+(numCols[ci]?' num':'')+'" aria-sort="none"><button type="button" class="thsort" title="Sort by this column">'+h+'<span class="sorti" aria-hidden="true"></span></button></th>').join('')+'</tr></thead>';
      // A column with a long cell wraps, every cell of it, so a short cell
      // on one line does not hold the column wider than the long ones need.
      const formatted=b.rows.map(r=>r.map((c,ci)=>formatCell(c, b.headers[ci])));
      const longCols=b.headers.map((h,ci)=> !numCols[ci] && formatted.some(r=>String(r[ci]==null?'':r[ci]).replace(/<[^>]+>/g,'').length>28));
      const cellsHtml=formatted.map(r=>r.map((cell,ci)=>{
          const num = numCols[ci];
          const wrap = wrapCols[ci] || longCols[ci];
          return '<td class="'+(wrap?'wrap':'')+(num?' num':'')+'">'+cell+'</td>';
        }).join(''));
      // Which chip kinds a row holds, for the key's filter.
      const kinds=cellsHtml.map(h=>({ready:h.indexOf('class="tagpill inst"')>=0, notinst:h.indexOf('class="tagpill"')>=0}));
      const body=cellsHtml.map((h,ri)=>'<tr'+(kinds[ri].ready?' data-ready="1"':'')+(kinds[ri].notinst?' data-notinst="1"':'')+'>'+h+'</tr>').join('');
      const tid='dt'+idx;
      const nReady=kinds.filter(k=>k.ready).length;
      const key=nReady ? chipKey(tid, nReady, kinds.filter(k=>k.notinst).length) : '';
      return '<div class="doctable-wrap">'+
        (many?'<div class="doctable-tools"><input type="search" data-for="'+tid+'" placeholder="Filter '+b.rows.length+' rows…">'+key+'<span class="dtc" id="'+tid+'c">'+b.rows.length+' rows</span></div>'
          : key?'<div class="doctable-tools">'+key+'</div>':'')+
        '<div class="doctscroll"><table class="doct" id="'+tid+'">'+thead+'<tbody>'+body+'</tbody></table></div></div>';
    }

    // Render an ugly serialized cell ("description=…, tactics=A,B, techniques=T1,T2")
    // as clean text + labelled pills. Leaves ordinary cells untouched.
    // A list of four or more items in a cell, separated by "; " (template
    // names, the solutions they come from), reads as chips: the first
    // CELL_CHIPS, then Show all for the rest, so nothing is hidden and the
    // row stays short. A template source that is ready to enable (a solution
    // marked "installed", or Built-in) is tinted green; one whose solution
    // is not installed stays grey. Tables with tinted chips carry a key.
    const CELL_CHIPS=3;
    const readyChip=x=>/,\s*installed\)$/.test(x) || /^Built-in \(\d+\)$/.test(x.replace(/<[^>]+>/g,'').trim());
    function chipKey(tid,nReady,nNot){
      const k=(ck,label,n,tip)=>'<button type="button" class="fchip" data-ck="'+ck+'" aria-pressed="false" title="'+tip+'"><i class="ck-'+ck+'" aria-hidden="true"></i>'+label+'<span>'+n+'</span></button>';
      return '<span class="chipkey" data-for="'+tid+'" role="group" aria-label="Filter by where the templates come from">'+
        k('ready','Installed or built in',nReady,'Show the rows with templates ready to enable: their solution is installed, or they ship with Sentinel')+
        k('notinst','Not installed',nNot,'Show the rows with templates whose Content Hub solution is not installed')+'</span>';
    }
    const CRIT_STATE=/^(SAC-[A-Z]{2,4}-\d{2})\s+(met|gap|unknown|not assessed)$/i;
    const CRIT_CLS={met:'c-met', gap:'c-gap', unknown:'c-unknown', 'not assessed':'c-na'};
    const CRIT_TIP={met:'Met on this workspace', gap:'A gap on this workspace', unknown:'Could not be evaluated on this workspace', 'not assessed':'Not assessed in this run'};
    // A criterion and its state shows as the criterion in the state's colour,
    // the state in its tooltip and for a screen reader.
    function critChip(x, hidden){
      const m=CRIT_STATE.exec(x.replace(/<[^>]+>/g,'').trim()); if(!m) return '';
      const st=m[2].toLowerCase(), id=x.replace(/\s+(met|gap|unknown|not assessed)\s*$/i,'');
      return '<span class="tagpill crit '+CRIT_CLS[st]+'" title="'+esc(m[1]+': '+CRIT_TIP[st])+'"'+(hidden?' data-mr hidden':'')+'>'+id+'<span class="vh">, '+esc(st)+'</span></span>';
    }
    function listCell(c, head){
      const items=String(c).split(/(?<!&[a-z0-9#]{1,8});\s+/i).map(x=>x.trim()).filter(Boolean);
      // A cell naming criteria and their states is chips even for one.
      const critCol=items.some(x=>CRIT_STATE.test(x.replace(/<[^>]+>/g,'').trim()));
      // A From solutions column ("Name (N, installed)") is chips even for one
      // solution, so every row shows its colour.
      const solCol=/^from solutions?$/i.test(String(head||'').replace(/<[^>]+>/g,'').trim()) && items.length>0 &&
        items.every(x=>/\(\d+(,\s*installed)?\)$/.test(x.replace(/<[^>]+>/g,'').trim()));
      // Two or three short items are chips too; a sentence with a
      // semicolon in it (longer parts) stays text.
      if(!solCol && !critCol && (items.length<2 || (items.length<4 && items.some(x=>x.replace(/<[^>]+>/g,'').length>60)))) return '';
      // A lead-in before the list ("146 rule(s) disabled: ...") stays text.
      let lead='';
      const m=(solCol||critCol)? null : /^(.{3,120}?:)\s+(.+)$/.exec(items[0]); if(m && !/<a\b/i.test(m[1])){ lead='<div class="cellp">'+m[1]+'</div>'; items[0]=m[2]; }
      return lead+'<div class="morewrap cellchips"><div class="chipl">'+items.map((x,i)=>critChip(x, i>=CELL_CHIPS) || '<span class="tagpill'+(readyChip(x)?' inst':'')+'"'+(i>=CELL_CHIPS?' data-mr hidden':'')+'>'+x+'</span>').join('')+'</div>'+
        (items.length>CELL_CHIPS? moreChev(items.length) : '')+'</div>';
    }
    // Status words in a table cell read as pills: green for fine, amber to
    // act on, red for something that no longer works or is risky.
    const STATUS_PILL={'Up to date':'Met','Current':'Met','Update available':'Warn','Stale':'Warn','Deprecated':'Gap','Not in catalogue':'Gap','Stale, used by rules':'Gap',
      'Generally available':'Met','Preview':'Info','Retiring':'Gap','Action needed':'Warn'};
    function formatCell(c, head){
      const stc=STATUS_PILL[String(c==null?'':c).trim()]; if(stc) return '<span class="st '+stc+'">'+String(c).trim()+'</span>';
      const chips=c? listCell(c, head) : ''; if(chips) return chips;
      if(!c || !/^[a-z][a-z0-9]*=/i.test(c)) return c;
      const parts = c.split(/,\s*(?=[a-zA-Z][a-zA-Z0-9]*=)/);
      if(parts.length<2 && !/^(description|tactics|techniques)=/i.test(c)) return c;
      let out='';
      parts.forEach(p=>{
        const m=p.match(/^([a-zA-Z][a-zA-Z0-9]*)=([\s\S]*)$/); if(!m){ out+='<div>'+p+'</div>'; return; }
        const key=m[1], val=m[2].trim(); if(!val) return;
        const label=key.replace(/([A-Z])/g,' $1').replace(/^./,s=>s.toUpperCase());
        if(/^(description|notes?)$/i.test(key)){ out+='<div class="cellp">'+val+'</div>'; }
        else {
          const pills=val.split(',').map(x=>x.trim()).filter(Boolean)
            .map(x=>'<span class="tagpill">'+esc(x.replace(/<[^>]+>/g,''))+'</span>').join('');
          out+='<div class="cellkv"><span class="cellk">'+esc(label)+'</span>'+pills+'</div>';
        }
      });
      return out||c;
    }

    // A callout in the colour of how serious it is (the renderer's tone):
    // blue to note, green for good news, amber to act on, red for something
    // broken or at risk. The icon and a screen-reader word carry it too.
    const NOTE_TONE={info:'', success:'Good news', warning:'Warning', critical:'Critical'};
    function noteHtml(b){
      const tone=NOTE_TONE.hasOwnProperty(b.tone)? b.tone : 'info';
      let inner='';
      if(b.title){ inner+='<div class="nt">'+esc(b.title.replace(/<[^>]+>/g,''))+'</div>'; }
      if(b.paras && b.paras.length){ inner+=b.paras.map(p=>'<p>'+p+'</p>').join(''); }
      if(b.items && b.items.length){ inner+='<ul>'+b.items.map(it=>'<li>'+it+'</li>').join('')+'</ul>'; }
      if(!inner && b.html){ inner='<p>'+b.html+'</p>'; }
      return '<div class="docnote dn t-'+tone+'"><span class="dni" aria-hidden="true">'+ICONN2[tone]+'</span><div class="dnb">'+
        (NOTE_TONE[tone]? '<span class="vh">'+NOTE_TONE[tone]+': </span>' : '')+inner+'</div></div>';
    }
