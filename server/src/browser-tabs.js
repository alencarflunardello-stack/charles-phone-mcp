// Chrome UI adapter: never inject JavaScript or connect to an unapproved debugging port.
const PREFIX='com.android.chrome:id/';
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const visible=n=>Array.isArray(n?.bounds)&&n.bounds.length===4&&n.bounds[2]>n.bounds[0]&&n.bounds[3]>n.bounds[1];
const exact=(screen,name)=>screen.nodes?.filter(n=>n.viewId===PREFIX+name&&visible(n))??[];
const unique=(nodes,label)=>{if(nodes.length!==1)throw Error('Chrome '+label+' not uniquely visible. No action sent.');return nodes[0];};
const grid=screen=>exact(screen,'tab_list_recycler_view').length===1;
const tabList=screen=>exact(screen,'tab_title').filter(n=>typeof n.text==='string'&&n.text.length>0).map(n=>({
  title:n.text,nodeId:n.nodeId,description:n.description??'',bounds:n.bounds
}));
const newTabLabel=new Set(['Nova guia','New tab','Nueva pestaña','Nouvel onglet','Neuer Tab']);
export async function chromeTabs(command,args){
  const selected={packageName:'com.android.chrome',sessionId:args.sessionId,_ownerKey:args._ownerKey};
  const read=async()=>{
    const value=await command('snapshot',{...selected,limit:350,detail:'full'});
    if(value?.packageName!=='com.android.chrome'||value.sessionId!==args.sessionId||!value.snapshotId||!Array.isArray(value.nodes))throw Error('Chrome observation identity mismatch.');
    return value;
  };
  const click=async(screen,node)=>{
    if(!node?.clickable||!visible(node))throw Error('Chrome target is not a visible clickable native control.');
    const result=await command('click',{...selected,snapshotId:screen.snapshotId,nodeId:node.nodeId});
    if(result?.performed!==true)throw Error('Chrome action not acknowledged. Inspect session; do not replay.');
    return result;
  };
  let screen=await read(),enteredGrid=false;
  if(!grid(screen)){
    // Only list/new may open the tab grid; select/close must use a fresh visible tab inventory.
    if(['select','close'].includes(args.action))throw Error('List visible Chrome tabs before selecting or closing one.');
    const control=unique(exact(screen,'tab_switcher_button'),'tab switcher');
    await click(screen,control);enteredGrid=true;
    for(let i=0;i<4;i++){await pause(150);screen=await read();if(grid(screen))break;}
    if(!grid(screen))return {sessionId:args.sessionId,action:args.action,completed:false,reason:'tab_grid_not_observed',enteredGrid,observation:screen,replayed:false};
  }
  if(args.action==='list')return {sessionId:args.sessionId,action:'list',completed:true,enteredGrid,tabs:tabList(screen),snapshotId:screen.snapshotId,visibleOnly:true,sharedProfile:true,observation:screen};
  let target;
  if(args.action==='new'){
    target=unique(exact(screen,'toolbar_action_button').filter(n=>newTabLabel.has(n.description??n.text)),'new tab');
  }else{
    const matches=exact(screen,'tab_title').filter(n=>n.text===args.title&&n.nodeId===args.tabNodeId);
    const title=unique(matches,'requested tab');
    if(exact(screen,'tab_title').filter(n=>n.text===args.title).length!==1)throw Error('Duplicate visible tab titles; no action sent.');
    if(args.action==='select'){
      target=unique(screen.nodes.filter(n=>n.nodeId===(title.clickNodeId??title.parent)&&n.clickable&&visible(n)),'tab card');
      if(!target.viewId?.startsWith(PREFIX)||!title.nodeId.startsWith(target.nodeId+'.'))throw Error('Tab card identity mismatch.');
    }else{
      target=unique(exact(screen,'action_button').filter(n=>n.parent===title.parent&&n.clickable),'tab close button');
      if(!target.description?.includes(args.title))throw Error('Close control does not identify the requested tab.');
    }
  }
  await click(screen,target);
  let final;
  try{await pause(250);final=await read();}catch(error){return {sessionId:args.sessionId,action:args.action,completed:false,performed:true,uncertain:true,error:String(error.message),replayed:false};}
  const expected=args.action==='close'?grid(final)&&!tabList(final).some(n=>n.title===args.title):!grid(final);
  return {sessionId:args.sessionId,action:args.action,completed:expected,performed:true,applicationEffectVerified:args.action==='close'&&expected,requiresPageVerification:args.action!=='close',visibleTabs:grid(final)?tabList(final):undefined,observation:final,replayed:false,sharedProfile:true};
}
