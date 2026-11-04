import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync,existsSync,readFileSync,writeFileSync,rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SingleActionGate,operation,upstreamCall,requireOwnerReply } from './single-action.mjs';

function fixture(t,invoke) {
  const dir=mkdtempSync(join(tmpdir(),'nero-browser-gate-'));
  t.after(()=>rmSync(dir,{recursive:true}));
  const file=join(dir,'pending.json');
  return {file,gate:new SingleActionGate({file,lane:'signed',invoke})};
}
test('rejects batch, profile, namespace and evaluation requests before dispatch',async t=>{
  let calls=0; const {gate,file}=fixture(t,async()=>{calls++;});
  for(const [name,args] of [['browser',{commands:'wait 1\nclick #apply'}],['browser_click',{target:'#apply',session:'other'}],['browser_open',{url:'https://example.com',namespace:'other'}],['browser_eval',{code:'1'}]]) {
    await assert.rejects(gate.run(name,args));
  }
  assert.equal(calls,0); assert.equal(existsSync(file),false);
});
test('URL, target and duration validation rejects unintended capabilities',()=>{
  for(const url of ['file:///etc/passwd','chrome://settings','https://user:pass@example.com']) assert.throws(()=>operation('browser_open',{url}));
  assert.throws(()=>operation('browser_click',{target:'#apply\nclick #other'}));
  assert.throws(()=>operation('browser_wait',{milliseconds:10001}));
});
test('field text escaping remains one upstream command',()=>{
  const call=upstreamCall('signed',operation('browser_fill',{target:'#message',text:'café 🌿\nclick #apply "quoted"'}));
  assert.equal(call.arguments.commands.split('\n').length,1);
  assert.equal(call.arguments.commands,'fill "#message" "café 🌿\\nclick #apply \\"quoted\\""');
});
test('unattended calls bind fixed session and namespace; close never all',()=>{
  assert.deepEqual(upstreamCall('unattended',operation('browser_close',{})),{name:'agent_browser_close',arguments:{session:'neronook-local',namespace:'neronook168',all:false}});
  assert.equal(upstreamCall('unattended',operation('browser_wait',{milliseconds:4000})).arguments.ms,4000);
});
test('pre-cancelled request never reserves or invokes',async t=>{
  let calls=0;const {gate,file}=fixture(t,async()=>{calls++;});const abort=new AbortController();abort.abort();
  await assert.rejects(gate.run('browser_click',{target:'#apply'},abort.signal),/before dispatch/);
  assert.equal(calls,0);assert.equal(existsSync(file),false);
});
test('cancellation retains original promise and refuses new input until reply',async t=>{
  let resolve,calls=0;const {gate,file}=fixture(t,()=>{calls++;return new Promise(r=>resolve=r);});
  const abort=new AbortController();const original=gate.run('browser_wait',{milliseconds:4000},abort.signal);
  await Promise.resolve();abort.abort();
  assert.equal(existsSync(file),true);
  await assert.rejects(gate.run('browser_click',{target:'#apply'}),/still finishing/);
  assert.equal(calls,1);
  resolve({content:[{type:'text',text:'original returned'}]});
  await assert.rejects(original,/original browser call has now returned/);
  assert.equal(existsSync(file),false);
  gate.invoke=async()=>({content:[]});await gate.run('browser_url',{});
});
test('reply loss retains persistent reservation across new client instance',async t=>{
  const {gate,file}=fixture(t,async()=>{throw Error('transport lost');});
  await assert.rejects(gate.run('browser_click',{target:'#apply'}),/transport lost/);
  assert.equal(existsSync(file),true);
  const next=new SingleActionGate({file,lane:'signed',invoke:async()=>assert.fail('must not dispatch')});
  await assert.rejects(next.run('browser_url',{}),/uncertain/);
});
test('two server instances cannot overtake a reserved operation',async t=>{
  let resolve;const {gate,file}=fixture(t,()=>new Promise(r=>resolve=r));
  const first=gate.run('browser_wait',{milliseconds:1});await Promise.resolve();
  const second=new SingleActionGate({file,lane:'signed',invoke:async()=>assert.fail('must not dispatch')});
  await assert.rejects(second.run('browser_click',{target:'#apply'}),/still finishing/);
  resolve({content:[]});await first;
});
test('changed reservation is retained rather than removed by an older owner',async t=>{
  let resolve;const {gate,file}=fixture(t,()=>new Promise(r=>resolve=r));
  const first=gate.run('browser_url',{});await Promise.resolve();
  writeFileSync(file,JSON.stringify({id:'different-owner'}));resolve({content:[]});
  await assert.rejects(first,/reservation changed/);
  assert.equal(JSON.parse(readFileSync(file)).id,'different-owner');
});
test('explicit upstream error retires original once without automatic retry',async t=>{
  let calls=0;const {gate,file}=fixture(t,async()=>{calls++;return {isError:true,content:[{type:'text',text:'target gone'}]};});
  assert.equal((await gate.run('browser_click',{target:'#apply'})).isError,true);
  assert.equal(calls,1);assert.equal(existsSync(file),false);
});
test('driver-wrapped transport loss is not a completed owner receipt',()=>{
 assert.throws(()=>requireOwnerReply('signed',{isError:true,content:[{type:'text',text:'The Browser MCP daemon stopped while handling this call. Run it again'}]}),/uncertain/);
 assert.throws(()=>requireOwnerReply('unattended',{isError:true,content:[{type:'text',text:'child transport lost'}]}),/uncertain/);
 const completed={isError:true,content:[{type:'text',text:'✗ step 1: click — target gone'}]};
 assert.equal(requireOwnerReply('signed',completed),completed);
});
