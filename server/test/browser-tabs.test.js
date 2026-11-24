import test from 'node:test';
import assert from 'node:assert/strict';
import {chromeTabs} from '../src/browser-tabs.js';
const pkg='com.android.chrome',sessionId='12345678-1234-4234-8234-123456789abc',snapshotId='12345678-1234-4234-8234-123456789abd';
const bounds=[10,10,100,100],node=(nodeId,viewId,extra={})=>({nodeId,viewId:pkg+':id/'+viewId,bounds,...extra});
const screen=nodes=>({packageName:pkg,sessionId,snapshotId,nodes});
const grid=screen([node('0.1','tab_list_recycler_view'),node('0.2','toolbar_action_button',{description:'Nova guia',clickable:true}),node('0.3','content_view',{clickable:true}),node('0.3.1','tab_title',{text:'Example',parent:'0.3',clickNodeId:'0.3'}),node('0.3.2','action_button',{description:'Fechar guia Example',parent:'0.3',clickable:true})]);
const page=screen([node('0.1','tab_switcher_button',{clickable:true})]);
const args={packageName:pkg,sessionId,_ownerKey:'a'.repeat(64)};
test('tab listing uses visible native Chrome nodes and no click if already in grid',async()=>{
 const ops=[];const out=await chromeTabs(async(op,a)=>{ops.push(op);return grid;},{...args,action:'list'});
 assert.deepEqual(ops,['snapshot']);assert.equal(out.tabs[0].title,'Example');assert.equal(out.visibleOnly,true);
});
test('select exact tab card and observe page without claiming page identity',async()=>{
 const ops=[];let reads=0;
 const out=await chromeTabs(async(op,a)=>{ops.push({op,a});return op==='click'?{performed:true}:reads++===0?grid:page;},{...args,action:'select',title:'Example',tabNodeId:'0.3.1'});
 assert.equal(ops[1].a.nodeId,'0.3');assert.equal(ops[1].a.snapshotId,snapshotId);
 assert.equal(out.completed,true);assert.equal(out.requiresPageVerification,true);
});
test('duplicate titles, incorrect session, missing grid and mismatched ID send no click',async()=>{
 for(const value of [screen([...grid.nodes,node('0.4.1','tab_title',{text:'Example'})]),{...grid,sessionId:'wrong'},page]){
  const ops=[];await assert.rejects(chromeTabs(async(op)=>{ops.push(op);return value;},{...args,action:'close',title:'Example',tabNodeId:'0.3.1'}));assert.deepEqual(ops,['snapshot']);
 }
 const ops=[];await assert.rejects(chromeTabs(async(op)=>{ops.push(op);return grid;},{...args,action:'select',title:'Example',tabNodeId:'0.9'}));assert.deepEqual(ops,['snapshot']);
});
test('new tab only uses a recognized native new-tab label',async()=>{
 const ops=[];let reads=0;
 const out=await chromeTabs(async(op,a)=>{ops.push({op,a});return op==='click'?{performed:true}:reads++===0?grid:page;},{...args,action:'new'});
 assert.equal(ops[1].a.nodeId,'0.2');assert.equal(out.requiresPageVerification,true);
});
