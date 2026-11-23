  // ---- balanced card grids ----
  // auto-fill packs as many columns as fit and leaves a short last row
  // (six cards, then four). For each card grid, take the column count that
  // fits, work out how many rows that needs, and spread the cards evenly
  // over those rows instead: ten cards at six wide become five and five.
  // Full-width panels (.full) span every column and are left out of the
  // count. Re-run on resize and when a hidden tab is shown.
  const BALANCED=[['#contents',250],['#heroPills',150],['.pgtiles',150],['.pgcards',380],['#estateRings',220],['#outcomes',290],['.iband',380],['.csfgrid',200],['.invg',130]];
  // Rows are balanced (5 cards become 3 + 2, never 4 + 1), and when the last
  // row is still short by two or more cards, its cards widen to fill the row
  // instead of leaving a hole: the grid uses lcm(cols, k) tracks, regular
  // cards span lcm/cols and last-row cards span lcm/k. A single leftover card
  // keeps its normal width.
  const gcd=(a,b)=>b? gcd(b,a%b) : a;
  function balanceGrids(){
    BALANCED.forEach(([sel,min])=>{
      document.querySelectorAll(sel).forEach(el=>{
        const w=el.clientWidth;
        if(!w){                                                    // hidden tab, measure when shown
          const view=el.closest('[data-view]');
          if(!(view&&view.classList.contains('hidden')) && !el._bgRetry){ el._bgRetry=true; requestAnimationFrame(()=>{ el._bgRetry=false; balanceGrids(); }); }
          return;
        }
        const kids=[...el.children].filter(c=>!c.classList.contains('full'));
        const n=kids.length;
        if(!n) return;
        const gap=parseFloat(getComputedStyle(el).columnGap)||12;
        const maxCols=Math.max(1,Math.floor((w+gap)/(min+gap)));
        const rows=Math.ceil(n/maxCols);
        const cols=Math.max(1,Math.ceil(n/rows));
        const k=n%cols;
        const justify=k>=2;
        const L=justify? cols*k/gcd(cols,k) : cols;
        el.style.gridTemplateColumns='repeat('+L+',minmax(0,1fr))';
        kids.forEach((c,i)=>{ c.style.gridColumn = L===cols? '' : 'span '+((justify && i>=n-k)? L/k : L/cols); });
      });
    });
  }
  balanceGrids(); markClamped();
  window.addEventListener('resize',balanceGrids);
  if(window.ResizeObserver){
    const ro=new ResizeObserver(()=>balanceGrids());
    BALANCED.forEach(([sel])=>document.querySelectorAll(sel).forEach(el=>ro.observe(el)));
  }

