  // ---- ATT&CK coverage grid (Insights) ----
  // A Navigator-style matrix from M.attack: one column per tactic in
  // kill-chain order, a cell per technique shaded by the enabled rules that
  // map it. "Techniques" shows a technique's mapped sub-techniques as chips;
  // "Sub-techniques" lists each under its technique, shaded by its own rules.
  // "Include disabled" adds the disabled rules (a cell only they cover is
  // dashed: covered once they are enabled); "Every technique" adds the
  // uncovered techniques and, in the sub-technique view, the uncovered
  // sub-techniques, to show the gaps. Selecting a cell or a sub-technique
  // lists the rules mapped to it.
  const akState={rules:'enabled', show:'covered', level:'tech', q:'', sel:null};
  function renderAttackGrid(){
    const A=M.attack, grid=document.getElementById('akGrid'); if(!A||!grid) return;
    const R=A.rules, on=i=>R[i].enabled, q=akState.q.trim().toLowerCase();
    const all=akState.rules==='all', every=akState.show==='all', subLevel=akState.level==='sub';
    const byTac={}; A.cells.forEach(c=>{ (byTac[c.tactic]||(byTac[c.tactic]={}))[c.technique]=c; });
    const techs={}; A.techniques.forEach(t=>techs[t.id]=t);
    const sname=id=>(A.subNames&&A.subNames[id])||id;
    const hit=s=>!!q && (s.id+' '+sname(s.id)).toLowerCase().includes(q);
    // Tactics a rule names that the Enterprise matrix does not have (ATT&CK
    // for ICS ones, say) get columns of their own after it, so every mapped
    // technique is shown.
    const known=new Set(A.tactics.map(t=>t.short));
    const extra=[...new Set(A.cells.map(c=>c.tactic).filter(t=>!known.has(t)))].sort()
      .map(s=>({id:'', name:s.replace(/([a-z])([A-Z])/g,'$1 $2'), short:s, other:true}));
    const cols=A.tactics.concat(extra).map(tac=>{
      const here=byTac[tac.short]||{};
      const inTactic=A.techniques.filter(t=>(t.tactics||[]).indexOf(tac.short)>=0);
      let ids=Object.keys(here);
      if(every) inTactic.forEach(t=>{ if(ids.indexOf(t.id)<0) ids.push(t.id); });
      const rows=ids.map(id=>{
        const c=here[id], t=techs[id]||{id:id,name:id,subTotal:0,subs:[]};
        const en=c? c.rules.filter(on).length : 0, dis=c? c.rules.length-en : 0;
        let subs=c? c.subs.map(s=>({id:s.id, en:s.rules.filter(on).length, all:s.rules.length})) : [];
        if(subLevel && every){
          const have=new Set(subs.map(s=>s.id));
          subs=subs.concat((t.subs||[]).filter(s=>!have.has(s)).map(s=>({id:s, en:0, all:0}))).sort((a,b)=>a.id.localeCompare(b.id));
        }
        const match=!q || (id+' '+t.name).toLowerCase().includes(q) || (c && c.rules.some(i=>R[i].name.toLowerCase().includes(q))) || subs.some(hit);
        return {id, t, c, en, dis, subs, match};
      }).filter(r=>r.match && (r.en>0 || (all && r.dis>0) || every))
        .sort((a,b)=>(b.en-a.en)||(all?b.dis-a.dis:0)||a.id.localeCompare(b.id));
      const coveredHere=Object.keys(here).filter(id=>here[id].rules.some(on)).length;
      const subsHere=new Set(); Object.keys(here).forEach(id=>here[id].subs.forEach(s=>{ if(s.rules.some(on)) subsHere.add(s.id); }));
      const subTotal=inTactic.reduce((n,t)=>n+(t.subTotal||0),0);
      return {tac, rows, coveredHere, total:inTactic.length, subsHere:subsHere.size, subTotal};
    });
    const heat=n=>n>=4?'h3':n>=2?'h2':n>=1?'h1':'';
    // Wide enough that every tactic name, ICS ones included, fits two lines.
    const cw=subLevel? 150 : 126;
    grid.style.gridTemplateColumns='repeat('+cols.length+',minmax('+cw+'px,1fr))';
    grid.style.minWidth=(cols.length*(cw+4))+'px';
    const sel=akState.sel;
    grid.innerHTML=cols.map(col=>{
      const n=subLevel? col.subsHere : col.coveredHere, d=subLevel? col.subTotal : col.total;
      const pct=d? Math.round(n/d*100) : 0;
      const sub=col.tac.other? 'ICS or other matrix' : n+' of '+d+(subLevel?' sub-techniques':' techniques');
      return '<div class="ak-col"><div class="ak-th" title="'+esc((col.tac.id?col.tac.id+' ':'')+col.tac.name)+'"><b>'+esc(col.tac.name)+'</b><span>'+sub+'</span>'+(col.tac.other?'':'<i style="--p:'+pct+'%"></i>')+'</div>'+
        col.rows.map(r=>{
          const cls=r.en>0? heat(r.en) : (r.dis>0 && all)? 'off' : 'gap';
          const mine=sel&&sel.tactic===col.tac.short&&sel.technique===r.id;
          const count=r.en>0||r.dis>0? (r.en+(all&&r.dis? '<span class="ak-dis">+'+r.dis+'</span>' : '')) : '';
          const mapped=r.subs.filter(s=>s.en||(all&&s.all));
          const tip=r.id+' '+r.t.name+': '+r.en+' enabled rule'+(r.en===1?'':'s')+(r.dis? ', '+r.dis+' disabled' : '')+(r.t.subTotal? '; '+mapped.length+' of '+r.t.subTotal+' sub-techniques mapped' : '');
          let body='';
          if(subLevel){
            const list=every? r.subs : mapped;
            body=list.length? '<div class="ak-sublist">'+list.map(s=>{
              const off=s.all-s.en, scls=s.en>0? heat(s.en) : (all&&s.all>0)? 'off' : 'gap';
              const sct=s.en>0||(all&&s.all)? s.en+(all&&off? '<span class="ak-dis">+'+off+'</span>' : '') : '';
              const stip=s.id+' '+sname(s.id)+': '+s.en+' enabled rule'+(s.en===1?'':'s')+(off? ', '+off+' disabled' : '');
              return '<div class="ak-subrow '+scls+(mine&&sel.sub===s.id?' sel':'')+(hit(s)?' hit':'')+'" '+(s.all>0?'role="button" tabindex="0" ':'')+'data-aksub="'+esc(s.id)+'" title="'+esc(stip)+'">'+
                '<div class="sh"><span class="sid">'+esc(s.id)+'</span><span class="ct">'+sct+'</span></div><div class="snm">'+esc(sname(s.id))+'</div></div>';
            }).join('')+'</div>' : (r.c&&r.t.subTotal? '<div class="ak-subnone">No sub-technique mapped</div>' : '');
          } else {
            const chips=mapped.map(s=>'<span class="ak-sub'+(s.en?'':' off')+'" title="'+esc(s.id+' '+sname(s.id))+'">'+esc(s.id)+'</span>').join('');
            if(chips) body='<div class="ak-subs">'+chips+'</div>';
          }
          return '<div class="ak-cell '+cls+(mine&&!(subLevel&&sel.sub)?' sel':'')+'" '+(r.c?'role="button" tabindex="0" ':'')+'data-ak="'+esc(col.tac.short)+'|'+esc(r.id)+'" title="'+esc(tip)+'">'+
            '<div class="id"><span>'+esc(r.id)+'</span><span class="ct">'+count+'</span></div><div class="nm">'+esc(r.t.name)+'</div>'+body+'</div>';
        }).join('')+'</div>';
    }).join('');
    const choose=(tactic,technique,sub)=>{ const s=akState.sel; akState.sel=(s&&s.tactic===tactic&&s.technique===technique&&(s.sub||null)===(sub||null))? null : {tactic,technique,sub:sub||null}; renderAttackGrid(); renderAttackDetail(); };
    const keys=(el,fn)=>el.addEventListener('keydown',e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); e.stopPropagation(); fn(); } });
    grid.querySelectorAll('.ak-cell[role="button"]').forEach(el=>{
      const pick=()=>{ const [tactic,technique]=el.dataset.ak.split('|'); choose(tactic,technique,null); };
      el.addEventListener('click',pick); keys(el,pick);
    });
    grid.querySelectorAll('.ak-subrow[role="button"]').forEach(el=>{
      const pick=()=>{ const [tactic,technique]=el.closest('.ak-cell').dataset.ak.split('|'); choose(tactic,technique,el.dataset.aksub); };
      el.addEventListener('click',e=>{ e.stopPropagation(); pick(); }); keys(el,pick);
    });
    if(typeof window.fitIframe==='function') window.fitIframe();
  }
  function renderAttackDetail(){
    const A=M.attack, el=document.getElementById('akDetail'); if(!A||!el) return;
    const s=akState.sel; if(!s){ el.classList.add('hidden'); el.innerHTML=''; if(typeof window.fitIframe==='function') window.fitIframe(); return; }
    const c=A.cells.find(x=>x.tactic===s.tactic&&x.technique===s.technique); if(!c){ akState.sel=null; return renderAttackDetail(); }
    const t=A.techniques.find(x=>x.id===c.technique)||{name:c.technique,subTotal:0}, tac=A.tactics.find(x=>x.short===c.tactic)||{name:c.tactic.replace(/([a-z])([A-Z])/g,'$1 $2')};
    const sname=id=>(A.subNames&&A.subNames[id])||id;
    const url=id=>'https://attack.mitre.org/techniques/'+id.replace('.','/')+'/';
    // A selected sub-technique lists only the rules that map it.
    const sub=s.sub? c.subs.find(x=>x.id===s.sub) : null;
    const idx=sub? sub.rules : c.rules;
    const order=idx.slice().sort((a,b)=>(A.rules[b].enabled-A.rules[a].enabled)||A.rules[a].name.localeCompare(A.rules[b].name));
    const rows=order.map(i=>{ const r=A.rules[i]; const subs=c.subs.filter(x=>x.rules.indexOf(i)>=0).map(x=>'<a href="'+esc(url(x.id))+'" target="_blank" rel="noopener" title="'+esc(sname(x.id))+'">'+esc(x.id)+'</a>').join(', ');
      return '<tr><td>'+esc(r.name)+'</td><td><span class="st '+(r.enabled?'Met':'Gap')+'">'+(r.enabled?'Enabled':'Disabled')+'</span></td><td>'+esc(r.severity||'')+'</td><td>'+esc(r.kind||'')+'</td><td>'+(subs||'<span class="note">None</span>')+'</td></tr>'; });
    const en=idx.filter(i=>A.rules[i].enabled).length;
    const head=sub? '<a href="'+esc(url(sub.id))+'" target="_blank" rel="noopener">'+esc(sub.id+' '+sname(sub.id))+'</a>' : '<a href="'+esc(url(c.technique))+'" target="_blank" rel="noopener">'+esc(c.technique+' '+t.name)+'</a>';
    el.innerHTML='<div class="esdetail"><div class="esd-head"><h3>'+head+'</h3>'+
      '<p class="note">'+esc(tac.name)+(sub? ' &middot; a sub-technique of '+esc(c.technique+' '+t.name) : '')+' &middot; '+en+' enabled and '+(idx.length-en)+' disabled rule'+(idx.length===1?'':'s')+(!sub&&t.subTotal? ' &middot; '+c.subs.length+' of '+t.subTotal+' sub-techniques mapped' : '')+'</p>'+
      (sub? sbtn('All of '+esc(c.technique),'data-ak-parent') : '')+sbtn('Close','data-ak-close')+'</div>'+
      '<table class="tbl"><thead><tr><th>Rule</th><th>Status</th><th>Severity</th><th>Kind</th><th>Sub-techniques</th></tr></thead><tbody>'+rows.join('')+'</tbody></table></div>';
    el.classList.remove('hidden');
    el.querySelector('[data-ak-close]').addEventListener('click',()=>{ akState.sel=null; renderAttackGrid(); renderAttackDetail(); });
    const up=el.querySelector('[data-ak-parent]'); if(up) up.addEventListener('click',()=>{ akState.sel={tactic:s.tactic, technique:s.technique, sub:null}; renderAttackGrid(); renderAttackDetail(); });
    if(typeof window.fitIframe==='function') window.fitIframe();
  }
  function wireAttackGrid(){
    const panel=document.getElementById('akPanel'); if(!panel) return;
    panel.querySelectorAll('[data-ak-rules]').forEach(b=>b.addEventListener('click',()=>{ akState.rules=b.dataset.akRules; panel.querySelectorAll('[data-ak-rules]').forEach(x=>x.classList.toggle('on',x===b)); renderAttackGrid(); renderAttackDetail(); }));
    panel.querySelectorAll('[data-ak-show]').forEach(b=>b.addEventListener('click',()=>{ akState.show=b.dataset.akShow; panel.querySelectorAll('[data-ak-show]').forEach(x=>x.classList.toggle('on',x===b)); renderAttackGrid(); }));
    panel.querySelectorAll('[data-ak-level]').forEach(b=>b.addEventListener('click',()=>{ akState.level=b.dataset.akLevel; panel.querySelectorAll('[data-ak-level]').forEach(x=>x.classList.toggle('on',x===b)); if(akState.sel&&akState.level!=='sub') akState.sel.sub=null; renderAttackGrid(); renderAttackDetail(); }));
    const s=panel.querySelector('#akSearch'); if(s) s.addEventListener('input',()=>{ akState.q=s.value; renderAttackGrid(); });
    renderAttackGrid();
  }

  // fillCards: each list card shows FILL_MIN entries, then as many more as
  // fit without growing past the tallest card in its grid row, and its
  // report button shows when entries are left over. Runs when the Insights
  // tab shows, on resize and once fonts load; a hidden board is skipped.
  function fillCards(){
    const b=document.getElementById('insightsBoard'); if(!b || !b.clientWidth) return;
    const lists=[...b.querySelectorAll('[data-fill-list]')]; if(!lists.length) return;
    const setN=(list,n)=>{
      [...list.children].forEach((r,i)=>{ r.hidden=i>=n; });
      const card=list.closest('.ipanel'), btn=card&&card.querySelector('.fillmore');
      if(btn) btn.hidden=!(btn.hasAttribute('data-keep') || n<+list.dataset.fillTotal);
    };
    b.classList.add('filling');
    lists.forEach(l=>setN(l,FILL_MIN));
    b.querySelectorAll('.iband').forEach(band=>{
      const rows={};
      [...band.children].forEach(c=>{ (rows[c.offsetTop]||(rows[c.offsetTop]=[])).push(c); });
      Object.values(rows).forEach(cards=>{
        const target=Math.max(...cards.map(c=>c.offsetHeight));
        cards.forEach(c=>c.querySelectorAll('[data-fill-list]').forEach(list=>{
          const max=list.children.length; let n=Math.min(FILL_MIN,max);
          while(n<max){ setN(list,n+1); if(c.offsetHeight>target){ setN(list,n); break; } n++; }
        }));
      });
    });
    b.classList.remove('filling');
    if(typeof window.fitIframe==='function') window.fitIframe();
  }

