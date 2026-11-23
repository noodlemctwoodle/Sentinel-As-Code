  // ---- top tables / rules ----
  if(cost&&cost.topTables.length){
    document.getElementById('topTables').innerHTML='<table class="tbl"><thead><tr><th>Table</th><th>Plan</th><th class="num">GB / '+WIN.d()+'</th><th class="num">Monthly cost</th></tr></thead><tbody>'+
      cost.topTables.map(t=>'<tr><td>'+esc(t.table)+'</td><td>'+esc(t.plan)+'</td><td class="num">'+fmtGb(t.gb30d)+'</td><td class="num">'+esc(fmtMoney(cost.currency,t.cost))+'</td></tr>').join('')+'</tbody></table>';
  }
  // The eight busiest rules here; Rule Performance lists every one.
  (function(){
    const el=document.getElementById('topRules'), sec=findSecNum(/^rule performance/i, null);
    const rows=M.topRules.map(r=>'<tr><td>'+esc(r.name)+'</td><td>'+esc(r.product)+'</td><td><span class="sev '+esc(r.severity)+'">'+esc(r.severity)+'</span></td><td class="num">'+r.alerts.toLocaleString()+'</td></tr>');
    const head='<table class="tbl"><thead><tr><th>Rule</th><th>Product</th><th>Sev</th><th>Alerts</th></tr></thead><tbody>';
    el.innerHTML = sec!=null
      ? head+rows.slice(0,8).join('')+'</tbody></table>'+(rows.length>8? sbtn('All '+rows.length.toLocaleString()+' rules in the report','data-jump="'+sec+'"',{go:true,cls:'morebtn'}) : '')
      : moreTable(head+trRows(rows,8)+'</tbody></table>', rows.length, 8, 'rules');
    el.querySelectorAll('[data-jump]').forEach(b=>b.addEventListener('click',()=>jumpTo(+b.dataset.jump)));
  })();

  // ---- top findings ----
  // Only the critical findings here; the button opens the findings view,
  // which lists every one.
  const allF = M.findings.items||[], topF = allF.filter(f=>f.severity==='Critical');
  const topEl = document.getElementById('topFindings');
  topEl.innerHTML=(topF.length? '<div class="fcards">'+topF.map(findingCard).join('')+'</div>' : '<p class="note">No critical findings in this run.</p>')+
    (allF.length? sbtn('All '+allF.length.toLocaleString()+' findings in the assessment','data-go="findings"',{go:true,cls:'morebtn'}) : '');
  topEl.querySelectorAll('[data-go]').forEach(b=>b.addEventListener('click',()=>{ if(activateTab) activateTab(b.dataset.go); bringTop(); }));
  markClamped(topEl);

