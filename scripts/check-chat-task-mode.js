const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const task=require('../Resources/Views/chat/chat-task-mode.js');
assert.equal(task.request('Hello','chat'),'Hello');assert.match(task.request('Apple','search'),/\[Nero task focus: Search the web\]/);assert.match(task.request('Type','browser'),/\[Nero task focus: Use my browser\]/);assert.equal(task.request('Hello','unknown'),'Hello');
assert(task.acknowledge({draft:'Type',sent:task.request('Type','browser')},[{role:'user',text:task.request('Type','browser')}],'Type'));assert(!task.acknowledge({draft:'Type',sent:'sent'},[{role:'user',text:'sent'}],'New text'));assert(!task.acknowledge({draft:'Type',sent:'sent'},[{role:'assistant',text:'sent'}],'Type'));assert(task.modes.search.hint.includes('Does not open'));
const source=fs.readFileSync(require.resolve('../Resources/Views/chat/chat.js'),'utf8');const send=source.split('\n').find(x=>x.startsWith('function send()'));
function setup(draft,mode){const nodes={draft:{value:draft},useContext:{checked:false},error:{}};const calls=[];const c={state:{busy:false,connected:true},pendingDraft:null,TextEncoder,window:{NeroTaskMode:{request:t=>task.request(t,mode),acknowledge:task.acknowledge}},$:id=>nodes[id],emit:(...args)=>calls.push(args)};vm.runInNewContext(send+';send()',c);return {c,nodes,calls};}
let s=setup('Open local lab','browser');assert.equal(s.calls.length,1);assert.match(s.calls[0][1].text,/\[Nero task focus: Use my browser\]/);assert.equal(s.c.pendingDraft.draft,'Open local lab');
const ack=source.split('\n').find(x=>x.includes('if(pendingDraft&&messages.some'));
s.c.messages=[{role:'user',text:s.calls[0][1].text}];vm.runInNewContext(ack,s.c);assert.equal(s.nodes.draft.value,'');assert.equal(s.c.pendingDraft,null);
s=setup('x'.repeat(2048),'browser');assert.equal(s.calls.length,0);assert.equal(s.nodes.error.hidden,false);assert.equal(s.nodes.draft.value.length,2048);
s=setup('Hello','chat');assert.equal(s.calls[0][1].text,'Hello');s.nodes.draft.value='new draft';s.c.messages=[{role:'user',text:'Hello'}];vm.runInNewContext(ack,s.c);assert.equal(s.nodes.draft.value,'new draft');
console.log('Task focus: 8 policy/presentation assertions and 4 real-send/echo/limit scenarios passed.');

assert.equal(task.display(task.request('Open my page','browser')),'Open my page');assert.equal(task.display('ordinary user text'),'ordinary user text');assert(task.request('Heading first','browser').startsWith('Heading first'));assert.match(task.request('Open','browser'),/Do not substitute/);console.log('4 display/title/routing-guidance checks passed');
