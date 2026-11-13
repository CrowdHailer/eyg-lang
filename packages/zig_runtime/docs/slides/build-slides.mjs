// Native @oai/artifact-tool authoring helper for the accompanying Slides Page.
// Called by the Pages execute_artifact_code callback with its current model.
const C={ink:'#E8E9E3',muted:'#A8B0BA',bg:'#111820',accent:'#E6B865',cyan:'#8BD5CA',line:'#35424E'};
function text(slide,name,value,x,y,w,h,size=28,color=C.ink,bold=false,mono=false){
 const o=slide.shapes.add({geometry:'textbox',name,position:{left:x,top:y,width:w,height:h},fill:'none',line:{style:'solid',fill:'none',width:0}});
 o.text=value;o.text.style={typeface:mono?'DejaVu Sans Mono':'DejaVu Sans',fontSize:size,color,bold,verticalAlignment:'top',alignment:'left',autoFit:'none',wrap:'square',insets:0};return o;
}
function ensureTableStyles(presentation){
 presentation.theme.defaultFont='DejaVu Sans';
 const existing=new Set(presentation.styles.describe().map(s=>s.name));
 for(const [name,size,color,bold] of [['EygTableHeader',23,C.accent,true],['EygTableBody',25,C.ink,false]]){
  if(existing.has(name))continue;
  const style=presentation.styles.add(name);style.fontSize=size;style.color=color;style.bold=bold;style.alignment='left';
 }
}
function table(presentation,slide,rows,x=64,y=230,w=1152,h=300,widths){
 ensureTableStyles(presentation);
 const t=slide.tables.add({rows:rows.length,columns:rows[0].length,left:x,top:y,width:w,height:h,values:rows,columnWidths:widths||rows[0].map(()=>w/rows[0].length)});
 for(let r=0;r<rows.length;r++)for(let c=0;c<rows[r].length;c++){
  const cell=t.getCell(r,c);cell.fill=C.bg;cell.text.style=r===0?'EygTableHeader':'EygTableBody';
 }
 return t;
}
function base(slide,d,i){slide.background.fill=C.bg;if(d.layout==='cover')return;text(slide,'title',d.title,64,46,1152,112,44,C.ink,true);if(d.kicker)text(slide,'scope',d.kicker,64,165,1150,50,23,C.accent);text(slide,'page',String(i+1).padStart(2,'0'),1165,670,50,26,18,C.muted);}
function flow(slide,nodes,edges){
 const objs=nodes.map((n,j)=>{const o=text(slide,'node-'+j,n.text,n.x,n.y,n.w,n.h,n.size||28,n.color||C.ink,n.bold??true,n.mono||false);o.text.insets={left:18,right:8,top:0,bottom:0};return o;});
 for(const e of edges||[])slide.shapes.connect(objs[e[0]],objs[e[1]],{kind:'elbow',fromSide:e[2]||'right',toSide:e[3]||'left',line:{style:'solid',fill:C.cyan,width:2},tail:{type:'arrow',width:'med',length:'med'}});
}
export function appendSlides(presentation,data,{start=0,end=data.length,imageRefs={}}={}){
 const made=[];
 for(let i=start;i<end;i++){
  const d=data[i];const s=i===0?presentation.slides.getItem(0):presentation.slides.add();base(s,d,i);
  if(d.layout==='cover'){
   text(s,'headline',d.title,64,170,1010,220,68,C.ink,true);
   text(s,'subtitle',d.subtitle,68,430,1050,130,29,C.muted);
   text(s,'wordmark','EYG',830,20,380,130,98,C.accent,true,true);
  }else if(d.layout==='columns'){
   text(s,'left-head',d.leftTitle||'',64,235,535,60,30,C.accent,true);
   text(s,'left-body',d.left,64,315,535,270,d.size||28,C.ink,false,d.monoLeft);
   text(s,'right-head',d.rightTitle||'',680,235,535,60,30,C.cyan,true);
   text(s,'right-body',d.right,680,315,535,280,d.size||28,C.ink,false,d.monoRight);
  }else if(d.layout==='flow'){
   flow(s,d.nodes,d.edges);if(d.caption)text(s,'caption',d.caption,64,574,1135,70,25,C.muted);
  }else if(d.layout==='table'){
   table(presentation,s,d.rows,64,d.tableY||240,1152,d.tableH||320,d.widths);
   if(d.caption)text(s,'caption',d.caption,64,590,1135,65,23,C.muted);
  }else if(d.layout==='performance'){
   text(s,'mechanism',d.mechanism,64,236,510,310,28);
   table(presentation,s,d.rows,625,236,590,d.tableH||260,d.widths||[240,175,175]);
   if(d.result)text(s,'result',d.result,625,530,590,90,27,C.cyan,true);
   if(d.caption)text(s,'caption',d.caption,64,626,1090,50,20,C.muted);
  }else if(d.layout==='code'){
   text(s,'code',d.code,64,240,1150,260,d.codeSize||30,C.cyan,false,true);
   if(d.caption)text(s,'caption',d.caption,64,550,1135,95,27,C.ink);
  }else if(d.layout==='image'){
   s.images.add({path:imageRefs[d.image],alt:d.alt||'',fit:'contain',position:d.imagePosition||{left:64,top:220,width:790,height:420}});
   text(s,'image-explanation',d.body,900,240,310,350,27);
  }else if(d.layout==='statement'){
   text(s,'statement',d.body,64,250,1120,280,52,C.accent,true);
   if(d.caption)text(s,'caption',d.caption,64,570,1135,70,28,C.ink);
  }else{
   text(s,'body',d.body,64,240,1140,370,d.size||32);
  }
  if(d.url){const z=text(s,'link',d.linkText||d.url,64,630,1080,35,22,C.cyan);z.text.get(d.linkText||d.url).link={uri:d.url,isExternal:true};}
  s.speakerNotes.text=d.notes||'';made.push({index:i,id:s.id,title:d.title});
 }
 return made;
}

export async function compactTables(presentation,data,{start=0,end=data.length}={}){
 const out=[];
 for(let i=start;i<end;i++){if(!['performance','table'].includes(data[i].layout))continue;
  const rr=(await presentation.inspect({select:'$.slides['+i+'].elements[*]',include:['id','kind']})).records;
  const old=rr.find(r=>r.kind==='table');const d=data[i];const perf=d.layout==='performance';
  table(presentation,presentation.slides.getItem(i),d.rows,perf?625:64,perf?236:(d.tableY||240),perf?590:1152,d.tableH||(perf?260:320),d.widths||(perf?[240,175,175]:undefined));
  presentation.delete(old.id);out.push(i);
 }return out;
}
