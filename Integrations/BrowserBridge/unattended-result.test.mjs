import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,existsSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {requireUnattendedSuccess} from './unattended-result.mjs';
import {SingleActionGate} from './single-action.mjs';
const ok=()=>({content:[{type:'text',text:'Authored result'}],isError:false,structuredContent:{exitCode:0,response:{success:true,error:null,data:{clicked:'#apply'}}}});
test('positive pinned-driver command completion is distinct from merely receiving MCP JSON',()=>{
 const r=ok();assert.equal(requireUnattendedSuccess(r),r);
 for(const value of [null,{}, {content:[]},{...ok(),isError:true}, {...ok(),isError:'false'},
  {...ok(),structuredContent:{exitCode:1,response:{success:true,error:null,data:{}}}},
  {...ok(),structuredContent:{exitCode:0,response:{success:false,error:'lost connection',data:{}}}},
  {...ok(),structuredContent:{exitCode:0,response:{success:true,data:{}}}},
  {...ok(),structuredContent:{exitCode:0,response:{success:true,error:null,data:[]}}}])assert.throws(()=>requireUnattendedSuccess(value),/uncertain/);
});
test('structured driver error retains gate reservation across a fresh adapter',async t=>{
 const dir=mkdtempSync(join(tmpdir(),'nero-fuego-outcome169-'));t.after(()=>rmSync(dir,{recursive:true}));
 const file=join(dir,'pending.json'),binding={session:'fuego-task169',namespace:'fuego169'};
 let calls=0;
 const first=new SingleActionGate({file,lane:'unattended',binding,invoke:async()=>{calls++;return requireUnattendedSuccess({...ok(),isError:true});}});
 await assert.rejects(first.run('browser_click',{target:'#apply'}),/uncertain/);assert(existsSync(file));
 const second=new SingleActionGate({file,lane:'unattended',binding,invoke:async()=>{calls++;return ok();}});
 await assert.rejects(second.run('browser_click',{target:'#apply'}),/uncertain/);assert.equal(calls,1);
});
