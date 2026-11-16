  // ---- detection matrix ----
  // Every enabled rule and custom detection that reads a table (the model's
  // detectionOutcomes): one row each, a column per source family (or per
  // table), its health and its incidents by verdict. Rows run Failing,
  // Working, Silent, the most incidents first; the first 25 show and the
  // header's chevron (the site's moreChev) shows the rest. Chips filter by
  // source and health, the search box by rule or table name.
  (function(){
    const box=document.getElementById('dmBox'), table=document.getElementById('dmTable');
    if(!box || !table) return;
    const all=(M.detectionOutcomes||[]), FAMOF=(M.detectionTableFamily||{});
    const panel=document.getElementById('detMatrixPanel');
    if(!all.length){ ['dmSummary','dmLegend'].forEach(id=>{ const e=document.getElementById(id); if(e) e.innerHTML=''; }); const t=panel.querySelector('.dm-tools'); if(t) t.remove();
      box.outerHTML='<p class="note" style="padding:16px">No enabled analytics rule or custom detection reads a workspace table in this snapshot.</p>'; return; }
    const FIRST=25, HEALTH=[['Failing','var(--red)'],['Working','var(--green)'],['Silent','var(--slate)']];
    const OUT=[['tp','True positive','#16a34a'],['fp','False positive','#dc2626'],['bp','Benign positive','#3b82f6'],['undetermined','Undetermined','#a78bfa'],['unclassified','Closed, unclassified','#64748b'],['open','Still open','#d97706']];
    const n0=v=>Number(v)||0, rank={Failing:0,Working:1,Silent:2}, famOf=t=>FAMOF[t]||'Other';
    // A bubble's number in white or near-black, whichever contrasts more with its colour.
    const lum=hex=>{ const c=String(hex).replace('#',''); const v=[0,2,4].map(k=>parseInt(c.substr(k,2),16)/255).map(x=>x<=0.03928? x/12.92 : Math.pow((x+0.055)/1.055,2.4)); return 0.2126*v[0]+0.7152*v[1]+0.0722*v[2]; };
    const inkOn=hex=>{ const L=lum(hex); return 1.05/(L+0.05) >= (L+0.05)/0.0567 ? '#ffffff' : '#0b1220'; };
    let st={src:'all', health:null, mode:'family', q:''};
    function columns(rows){
      // Families, or every table grouped by family; each ordered by how many rules read it.
      const use={}; rows.forEach(r=>(r.tables||[]).forEach(t=>{ use[t]=(use[t]||0)+1; }));
      const famUse={}; Object.keys(use).forEach(t=>{ const f=famOf(t); famUse[f]=(famUse[f]||0)+use[t]; });
      const fams=Object.keys(famUse).sort((a,b)=>famUse[b]-famUse[a]||a.localeCompare(b));
      if(st.mode==='family') return fams.map(f=>({label:f, fam:f, tables:Object.keys(use).filter(t=>famOf(t)===f)}));
      return fams.flatMap(f=>Object.keys(use).filter(t=>famOf(t)===f).sort((a,b)=>use[b]-use[a]||a.localeCompare(b)).map(t=>({label:t, fam:f, tables:[t]})));
    }
    const chip=(grp,val,label,sub,active,dot)=>'<button type="button" class="fchip'+(active?' active':'')+'" data-dm="'+grp+'" data-v="'+esc(val)+'" aria-pressed="'+active+'">'+(dot?'<i style="background:'+dot+'"></i>':'')+esc(label)+(sub!=null?'<span>'+sub+'</span>':'')+'</button>';
    function render(){
      const q=st.q.trim().toLowerCase();
      const match=r=>!q || String(r.name).toLowerCase().includes(q) || (r.tables||[]).some(t=>t.toLowerCase().includes(q));
      const srcOk=r=>st.src==='all' || (st.src==='sentinel'? r.source!=='Defender XDR' : r.source==='Defender XDR');
      const base=all.filter(r=>match(r) && srcOk(r));
      const rows=base.filter(r=>!st.health || r.health===st.health).sort((a,b)=>rank[a.health]-rank[b.health]||n0(b.incidents)-n0(a.incidents)||String(a.name).localeCompare(String(b.name)));
      const cnt=h=>base.filter(r=>r.health===h).length;
      // Summary: the rules shown by source, each health state, and their incidents by verdict.
      const tot={}; OUT.forEach(([k])=>tot[k]=rows.reduce((a,r)=>a+n0(r[k]),0)); const allInc=Object.values(tot).reduce((a,b)=>a+b,0);
      document.getElementById('dmSummary').innerHTML=
        '<div class="dm-sm"><div class="k">Rules and detections</div><div class="v">'+base.length.toLocaleString()+'</div><div class="s">'+base.filter(r=>r.source!=='Defender XDR').length+' analytics rules, '+base.filter(r=>r.source==='Defender XDR').length+' custom detections</div></div>'+
        HEALTH.map(([h,c])=>'<div class="dm-sm"><div class="k" style="color:'+c+'">'+h+'</div><div class="v">'+cnt(h).toLocaleString()+'</div><div class="s">'+Math.round(100*cnt(h)/Math.max(1,base.length))+'% of rules</div></div>').join('')+
        '<div class="dm-sm"><div class="k">Incidents in '+WIN.span()+' by verdict</div><div class="dm-vbar">'+(allInc? OUT.map(([k,l,c])=>tot[k]? '<i style="width:'+(100*tot[k]/allInc)+'%;background:'+c+'" title="'+l+': '+tot[k].toLocaleString()+'"></i>':'').join('') : '')+'</div>'+
        '<div class="dm-vleg">'+OUT.map(([k,l,c])=>'<span><i style="background:'+c+'"></i>'+l+' '+tot[k].toLocaleString()+'</span>').join('')+'</div></div>';
      // Chips.
      const srcBase=all.filter(match);
      document.getElementById('dmSrc').innerHTML=chip('src','all','All',srcBase.length,st.src==='all')+chip('src','sentinel','Analytics rules',srcBase.filter(r=>r.source!=='Defender XDR').length,st.src==='sentinel')+chip('src','xdr','Custom detections',srcBase.filter(r=>r.source==='Defender XDR').length,st.src==='xdr');
      document.getElementById('dmHealth').innerHTML=chip('health','all','All',base.length,!st.health)+HEALTH.map(([h,c])=>chip('health',h,h,cnt(h),st.health===h,c)).join('');
      document.getElementById('dmMode').innerHTML=chip('mode','family','By source family',null,st.mode==='family')+chip('mode','table','Every table',null,st.mode==='table');
      // The matrix.
      const cols=columns(rows), maxInc=Math.max(1,...rows.map(r=>n0(r.incidents)));
      // Angled table names need room for the longest: about 6.9px a character, at 64 degrees.
      const labH=Math.ceil(Math.max(1,...cols.map(c=>c.label.length))*6.9*Math.sin(64*Math.PI/180))+30;
      // The last names lean past the last column; a spacer column of that width
      // keeps them clear of the Health heading.
      const over=st.mode==='table'? Math.max(0,Math.ceil(Math.max(...cols.map((c,i)=>i*40+33+c.label.length*6.9*Math.cos(64*Math.PI/180)))-cols.length*40)) : 0;
      const spacer=over? '<td class="dm-sp" style="width:'+over+'px;min-width:'+over+'px"></td>' : '';
      let h='<thead><tr><th class="dm-rn">Rule or detection</th>'+(st.mode==='family'
          ? cols.map((c,i)=>'<th class="dm-fcol" data-c="'+i+'" title="'+esc(c.label+': '+c.tables.join(', '))+'"><i style="background:'+(famColor[c.fam]||'#64748b')+'"></i><span class="dm-fn">'+esc(c.label)+'</span><small>'+c.tables.length+' table'+(c.tables.length===1?'':'s')+'</small></th>').join('')
          : '<th class="dm-tl" colspan="'+(cols.length+(over?1:0))+'"><div class="dm-tlab" style="width:'+(cols.length*40+over)+'px;height:'+labH+'px">'+cols.map((c,i)=>'<span style="left:'+(i*40+20)+'px" data-c="'+i+'" title="'+esc(c.label+' ('+c.fam+')')+'"><i style="background:'+(famColor[c.fam]||'#64748b')+'"></i>'+esc(c.label)+'</span>').join('')+'</div></th>')+
        '<th class="dm-h">Health</th><th class="dm-h">Incidents by verdict</th><th class="dm-n">'+WIN.w()+(rows.length>FIRST? moreChev(rows.length,'rules') : '')+'</th></tr></thead><tbody>';
      rows.forEach((r,ri)=>{
        const isX=r.source==='Defender XDR', inc=n0(r.incidents), closed=Math.max(0,inc-n0(r.open)), tbls=r.tables||[];
        h+='<tr'+(ri>=FIRST? ' data-mr hidden':'')+'><td class="dm-rn"><div class="dm-name"><span class="dm-src '+(isX?'X':'S')+'" title="'+(isX?'Defender XDR custom detection':'Sentinel analytics rule')+'">'+(isX?'XDR':'SEN')+'</span>'+
          '<div class="dm-rtxt"><button type="button" class="dm-open" data-rule="'+esc(r.name)+'" data-alerts="'+n0(r.alerts)+'" data-incidents="'+inc+'" title="Open '+esc(r.name)+' in Rule Performance"><b>'+esc(r.name)+'</b></button><small>'+esc(r.kind||r.source)+' · '+tbls.length+' table'+(tbls.length===1?'':'s')+(n0(r.failures)? ' · '+n0(r.failures)+' run failure'+(n0(r.failures)===1?'':'s'):'')+'</small></div></div></td>';
        cols.forEach((c,i)=>{ const hit=tbls.filter(t=>c.tables.includes(t)), col=famColor[c.fam]||'#64748b';
          h+='<td class="dm-c" data-c="'+i+'"'+(hit.length? ' title="'+esc(hit.join(', '))+'"':'')+'>'+(hit.length? (hit.length>1? '<i style="background:'+col+';--g:'+col+';color:'+inkOn(col)+'">'+hit.length+'</i>' : '<i class="one" style="background:'+col+';--g:'+col+'"></i>') : '')+'</td>'; });
        h+=spacer;
        h+='<td class="dm-h"><span class="dm-pill '+esc(r.health)+'">'+esc(r.health)+'</span></td><td class="dm-v">'+(inc
            ? '<div class="dm-bar" style="width:'+Math.max(30,Math.round(168*Math.sqrt(inc/maxInc)))+'px">'+OUT.map(([k,l,c])=>n0(r[k])? '<i style="width:'+(100*n0(r[k])/inc)+'%;background:'+c+'" title="'+l+': '+n0(r[k])+'"></i>':'').join('')+'</div>'
            : '<span class="note" style="font-size:11.5px">'+(n0(r.alerts)? n0(r.alerts).toLocaleString()+' alerts, no incidents' : 'no incidents')+'</span>')+'</td>'+
          '<td class="dm-n"'+(inc? ' title="'+(closed? Math.round(100*n0(r.tp)/closed)+'% of its '+closed+' closed incidents were true positives; ' : 'No incident closed yet; ')+n0(r.open)+' still open"' : '')+'>'+
            (inc? inc.toLocaleString()+' incident'+(inc===1?'':'s')+' · '+(closed? Math.round(100*n0(r.tp)/closed)+'% TP' : 'none closed') : '')+'</td></tr>';
      });
      h+='</tbody><tfoot><tr><td class="dm-rn">Rules reading it</td>'+cols.map((c,i)=>'<td data-c="'+i+'">'+rows.filter(r=>(r.tables||[]).some(t=>c.tables.includes(t))).length+'</td>').join('')+(over? '<td></td>' : '')+'<td colspan="3"></td></tr></tfoot>';
      box.classList.remove('open');
      table.className='dm'+(st.mode==='family'? ' dm-fam':'');
      table.innerHTML=h;
      document.getElementById('dmLegend').innerHTML=Object.keys(famColor).map(f=>'<span><i style="background:'+famColor[f]+';border-radius:50%"></i>'+esc(f)+'</span>').join('')+
        '<span><i style="background:#64748b;border-radius:50%;width:16px;height:16px;display:inline-grid;place-items:center;font-style:normal;font-size:9.5px;font-weight:800;color:#ffffff">2</i>reads that many of the family\'s tables</span>'+
        '<span><b class="dm-src S">SEN</b>Sentinel analytics rule</span><span><b class="dm-src X">XDR</b>Defender XDR custom detection</span>';
      if(typeof window.fitIframe==='function') window.fitIframe();
    }
    panel.addEventListener('click',e=>{
      const c=e.target.closest('[data-dm]'); if(!c) return;
      const g=c.dataset.dm, v=c.dataset.v;
      if(g==='src') st.src=v; else if(g==='health') st.health=(v==='all' || st.health===v)? null : v; else st.mode=v;
      render();
    });
    document.getElementById('dmQ').addEventListener('input',e=>{ st.q=e.target.value; render(); });
    table.addEventListener('mouseover',e=>{ const c=e.target.closest('[data-c]'); table.querySelectorAll('.dm-hot').forEach(x=>x.classList.remove('dm-hot')); if(c) table.querySelectorAll('td[data-c="'+c.dataset.c+'"]').forEach(x=>x.classList.add('dm-hot')); });
    table.addEventListener('mouseleave',()=>table.querySelectorAll('.dm-hot').forEach(x=>x.classList.remove('dm-hot')));
    // A rule's row (or its name, from the keyboard) opens it in Rule Performance.
    table.addEventListener('click',e=>{ const tr=e.target.closest('tbody tr'), b=tr&&tr.querySelector('.dm-open'); if(b && typeof window.openRuleReport==='function') window.openRuleReport(b.dataset.rule, {alerts:+b.dataset.alerts||0, incidents:+b.dataset.incidents||0}); });
    render();
  })();

