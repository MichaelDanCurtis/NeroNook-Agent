const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const mode=require('../../Resources/Views/chat/chat-task-mode.js');
test('selected browser modes identify different explicit connections',()=>{
 assert(mode.request('Open the fixture','browser').includes('Use my browser · Browser MCP'));
 assert(mode.request('Open the fixture','unattended').includes('Unattended browser · agent-browser'));
 assert.equal(mode.request('Hello','chat'),'Hello');
});
test('visible history strips current and previous annotations',()=>{
 for(const key of ['chat','browser','unattended','search']) assert.equal(mode.display(mode.request('Original user words',key)),'Original user words');
 const old='Original user words\n\n[Nero task focus: Use my browser]\nUse the connected Chrome DevTools MCP browser tools. Discover its tools if necessary and verify browser state. Do not substitute a web search or a Mac open-URL action. If the browser connection is unavailable, explain that.';
 assert.equal(mode.display(old),'Original user words');
 assert.equal(mode.display('A user says Browser MCP.'),'A user says Browser MCP.');
});
test('composer acknowledgement cannot clear a newly edited draft',()=>{
 const pending={sent:mode.request('old','browser'),draft:'old'};
 assert(mode.acknowledge(pending,[{role:'user',text:pending.sent}],'old'));
 assert(!mode.acknowledge(pending,[{role:'user',text:pending.sent}],'new draft'));
});
test('every mode has a corresponding primary card control',()=>{
 const html=fs.readFileSync(path.join(__dirname,'../../Resources/Views/chat/index.html'),'utf8');
 for(const key of Object.keys(mode.modes)) assert(html.includes(`id="mode-${key}"`));
});
