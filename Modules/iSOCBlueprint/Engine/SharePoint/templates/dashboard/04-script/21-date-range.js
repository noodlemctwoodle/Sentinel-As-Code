  // ---- the date range ----
  // One control for every view: the window pill opens a calendar of the
  // collected days (the daily span), where a first and a last day choose
  // the window, as when booking dates; one day alone is a window too. The
  // activity cards count the chosen days and the Progress tab compares the
  // runs kept at either end. The quick choices take the last 7, 30 or every
  // collected day at once. Applying
  // reloads the dashboard for the window and reopens the view showing.
  const DAY_MS=864e5;
  const fmtDay=(t,y)=>fmtDate(t,{year:!!y});
  const winDates=()=>WIN.startT==null? '' : WIN.startT===WIN.endT? fmtDay(WIN.endT,true) :
    fmtDay(WIN.startT, new Date(WIN.startT).getUTCFullYear()!==new Date(WIN.endT).getUTCFullYear())+' to '+fmtDay(WIN.endT, true);
  const saveWindow=o=>{ try{ window.name='sacDash:'+JSON.stringify(o); }catch(e){} };
  (function(){
    const box=document.getElementById('winWrap'), btn=document.getElementById('winBtn'), pop=document.getElementById('winPop');
    if(!DAILY || !box || !btn || !pop || WIN.lastT==null) return;
    const span=+DAILY.span, minT=WIN.lastT-(span-1)*DAY_MS, maxT=WIN.lastT;
    const daysEl=document.getElementById('winDays'), datesEl=document.getElementById('winDates');
    daysEl.textContent=WIN.ago? WIN.words(WIN.days) : 'Last '+WIN.words(WIN.days);
    datesEl.textContent=winDates();
    btn.setAttribute('aria-label','Days shown: '+daysEl.textContent+', '+datesEl.textContent+'. Choose the dates');
    box.hidden=false;
    const MONTH_NAMES=['January','February','March','April','May','June','July','August','September','October','November','December'];
    const monthOf=t=>{ const d=new Date(t); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1); };
    const addMonths=(t,n)=>{ const d=new Date(t); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth()+n, 1); };
    const shown=()=>(window.matchMedia && matchMedia('(max-width: 600px)').matches)? 1 : 2;
    const nDays=(a,b)=>Math.round((b-a)/DAY_MS)+1;
    let lo=WIN.startT, hi=WIN.endT, pending=false, hover=null, lastMonth=monthOf(hi);
    const range=()=>pending&&hover!=null? [Math.min(lo,hover), Math.max(lo,hover)] : [lo,hi];
    function monthHtml(first){
      const d=new Date(first), y=d.getUTCFullYear(), m=d.getUTCMonth(), len=new Date(Date.UTC(y,m+1,0)).getUTCDate(), lead=(d.getUTCDay()+6)%7;
      let cells=''; for(let i=0;i<lead;i++) cells+='<span></span>';
      for(let i=1;i<=len;i++){
        const t=Date.UTC(y,m,i), off=t<minT||t>maxT;
        cells+='<button type="button" class="calday'+(t===maxT?' last':'')+'" data-t="'+t+'"'+(off?' disabled':'')+' tabindex="-1" aria-label="'+esc(fmtDate(t))+'"><span class="n">'+i+'</span></button>';
      }
      return '<div class="calm"><div class="calmh">'+MONTH_NAMES[m]+' '+y+'</div><div class="calgrid">'+
        ['Mo','Tu','We','Th','Fr','Sa','Su'].map(x=>'<span class="caldow" aria-hidden="true">'+x+'</span>').join('')+cells+'</div></div>';
    }
    // The chosen days painted onto the open months (and, while the last day
    // is being chosen, up to the day under the pointer), and the line that
    // names them.
    function paint(){
      const [a,b]=range();
      pop.querySelectorAll('.calday').forEach(c=>{ const t=+c.dataset.t, inr=t>=a&&t<=b;
        c.classList.toggle('inr',inr); c.classList.toggle('st',t===a); c.classList.toggle('en',t===b); c.setAttribute('aria-pressed',String(inr)); });
      const sel=pop.querySelector('.calsel');
      if(sel) sel.textContent=pending? 'Now choose the last day' : (a===b? fmtDate(a) : fmtDate(a)+' to '+fmtDate(b))+', '+WIN.words(nDays(a,b));
      const ap=pop.querySelector('[data-cal-apply]'); if(ap) ap.disabled=pending;
      // A quick choice lights up only while it is what the days chosen are.
      pop.querySelectorAll('[data-cal-last]').forEach(q=>{ const on=!pending && b===maxT && nDays(a,b)===+q.dataset.calLast; q.classList.toggle('active',on); q.setAttribute('aria-pressed',String(on)); });
    }
    function render(focusT){
      const k=shown(), months=[]; for(let i=k-1;i>=0;i--) months.push(addMonths(lastMonth,-i));
      const presets=[7,30,span].filter((v,i,l)=>v<=span && l.indexOf(v)===i);
      const nav=(dir,dis)=>'<button type="button" class="iconbtn" data-cal-nav="'+dir+'" aria-label="'+(dir<0?'Earlier months':'Later months')+'"'+(dis?' disabled':'')+'>'+
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="'+(dir<0?'m15 18-6-6 6-6':'m9 18 6-6-6-6')+'"/></svg></button>';
      pop.innerHTML='<div class="calhead"><div class="subtabs calpre" role="group" aria-label="Quick choices">'+
        presets.map(p=>'<button type="button" class="pgtab" data-cal-last="'+p+'">'+(p===span&&p>30? 'All '+p+' days' : 'Last '+p+' days')+'</button>').join('')+'</div>'+
        '<div class="calnav">'+nav(-1, months[0]<=monthOf(minT))+nav(1, lastMonth>=monthOf(maxT))+'</div></div>'+
        '<div class="calmonths">'+months.map(monthHtml).join('')+'</div>'+
        '<div class="calfoot"><span class="calsel" aria-live="polite"></span>'+
        sbtn('Cancel','data-cal-cancel',{cls:'quiet'})+sbtn('Apply','data-cal-apply')+'</div>';
      paint();
      const f=pop.querySelector('.calday[data-t="'+(focusT!=null? focusT : hi)+'"]:not([disabled])')||pop.querySelector('.calday:not([disabled])');
      if(f){ f.tabIndex=0; if(focusT!=null) f.focus(); }
    }
    const outside=e=>{ if(!box.contains(e.target)) close(false); };
    function open(){
      lo=WIN.startT; hi=WIN.endT; pending=false; hover=null; lastMonth=monthOf(hi);
      render(); pop.hidden=false; btn.setAttribute('aria-expanded','true'); document.addEventListener('mousedown',outside,true);
      const f=pop.querySelector('.calday[tabindex="0"]'); if(f) f.focus();
      if(typeof window.fitIframe==='function') window.fitIframe();
    }
    function close(back){ pop.hidden=true; btn.setAttribute('aria-expanded','false'); document.removeEventListener('mousedown',outside,true); if(back) btn.focus(); }
    function apply(n, ago){
      close(false); if(n===WIN.days && ago===WIN.ago) return;
      saveWindow({days:n, ago:ago, back:1, view:curView, doc:curDoc()});
      box.classList.add('busy'); location.reload();
    }
    btn.addEventListener('click',()=>{ if(pop.hidden) open(); else close(true); });
    pop.addEventListener('click',e=>{
      const d=e.target.closest('.calday');
      if(d){ if(d.disabled) return; const t=+d.dataset.t;
        if(!pending){ lo=hi=t; pending=true; } else { if(t<lo){ hi=lo; lo=t; } else hi=t; pending=false; }
        hover=null; paint(); return; }
      const p=e.target.closest('[data-cal-last]'); if(p){ apply(+p.dataset.calLast, 0); return; }
      const nv=e.target.closest('[data-cal-nav]'); if(nv){ if(!nv.disabled){ lastMonth=addMonths(lastMonth, +nv.dataset.calNav); render(); } return; }
      if(e.target.closest('[data-cal-cancel]')){ close(true); return; }
      if(e.target.closest('[data-cal-apply]') && !pending) apply(nDays(lo,hi), Math.round((maxT-hi)/DAY_MS));
    });
    pop.addEventListener('mouseover',e=>{ if(!pending) return; const d=e.target.closest('.calday'); if(d && !d.disabled && +d.dataset.t!==hover){ hover=+d.dataset.t; paint(); } });
    // Keys: the arrows move a day or a week, Home and End to the first and
    // last collected day; Enter or Space chooses; Escape closes.
    pop.addEventListener('keydown',e=>{
      if(e.key==='Escape'){ e.preventDefault(); close(true); return; }
      const d=e.target.closest('.calday'); if(!d) return;
      const step={ArrowLeft:-1, ArrowRight:1, ArrowUp:-7, ArrowDown:7}[e.key];
      let t=step!=null? +d.dataset.t+step*DAY_MS : e.key==='Home'? minT : e.key==='End'? maxT : null;
      if(t==null) return;
      e.preventDefault(); t=Math.min(Math.max(t,minT),maxT);
      const k=shown(); if(t<addMonths(lastMonth,1-k)) lastMonth=addMonths(monthOf(t),k-1); else if(t>=addMonths(lastMonth,1)) lastMonth=monthOf(t);
      if(pending) hover=t;
      render(t);
    });
  })();

