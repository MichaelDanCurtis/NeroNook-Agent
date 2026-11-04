import test from 'node:test';
import assert from 'node:assert/strict';
import {operation,upstreamCall,fixedUnattendedBinding,SingleActionGate} from './single-action.mjs';

test('prototype-named extra keys are rejected rather than accepted as schema members',()=>{
 for(const key of ['constructor','toString','__proto__']) {
  const args=JSON.parse(`{"url":"http://127.0.0.1/fixture","${key}":"override"}`);
  assert.throws(()=>operation('browser_open',args),/Unexpected arguments/);
 }
});
test('required arguments must be own values, not inherited from a prototype',()=>{
 assert.throws(()=>operation('browser_open',Object.create({url:'http://127.0.0.1/fixture'})),/Invalid url/);
});

import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

test('trusted unattended binding is copied, fixed and separate from default Nero168',()=>{
 const source={session:'fuego-task169',namespace:'fuego169'};
 const binding=fixedUnattendedBinding(source);source.session='changed';
 assert(Object.isFrozen(binding));
 const op=operation('browser_close',{});
 assert.deepEqual(upstreamCall('unattended',op,binding).arguments,{session:'fuego-task169',namespace:'fuego169',all:false});
 assert.deepEqual(upstreamCall('unattended',op).arguments,{session:'neronook-local',namespace:'neronook168',all:false});
 assert.throws(()=>operation('browser_close',{session:'fuego-task169'}));
 for(const bad of [{session:'a'},{session:'../a',namespace:'b'},{session:'a',namespace:'b',profile:'personal'},Object.create(source)]) assert.throws(()=>fixedUnattendedBinding(bad));
});
test('gate binds invocation to its constructor rather than later deployment-object edits',async t=>{
 const dir=mkdtempSync(join(tmpdir(),'nero-fuego-binding169-'));t.after(()=>rmSync(dir,{recursive:true}));
 const binding={session:'fuego-task169',namespace:'fuego169'},calls=[];
 const gate=new SingleActionGate({file:join(dir,'fuego.pending.json'),lane:'unattended',binding,invoke:async call=>{calls.push(call);return {content:[]};}});
 binding.session='neronook-local';binding.namespace='neronook168';
 await gate.run('browser_fill',{target:'#message',text:'authored café 🌿'});
 assert.equal(calls.length,1);assert.equal(calls[0].arguments.session,'fuego-task169');assert.equal(calls[0].arguments.namespace,'fuego169');
});
