const assert=require('node:assert/strict'), fs=require('node:fs'), vm=require('node:vm');
function setup(){
 const nodes=new Map(), listeners=[];
 function node(id){if(!nodes.has(id))nodes.set(id,{id,hidden:false,open:false,disabled:false,value:'',textContent:'',children:[],focus(){this.focused=true},select(){this.selected=true},addEventListener(){},querySelectorAll(){return []}});return nodes.get(id)}
 node('chatFind').hidden=true; node('history').hidden=false; node('historyButton').onclick=()=>{node('history').hidden=!node('history').hidden};
 const context={document:{getElementById:node,body:{classList:{contains(){return false}}},addEventListener(name,fn){if(name==='keydown')listeners.push(fn)}},MutationObserver:class{observe(){}disconnect(){}},requestAnimationFrame(){throw Error('No redraw expected')},cancelAnimationFrame(){},NodeFilter:{SHOW_TEXT:4}};
 for(const file of ['chat-find.js','chat-history.js'])vm.runInNewContext(fs.readFileSync(require.resolve('../Resources/Views/chat/'+file),'utf8'),context);
 function key(key,extras={}){const e={key,defaultPrevented:false,preventDefault(){this.defaultPrevented=true},stopPropagation(){},...extras};for(const f of listeners)f(e);return e}
 return {node,key};
}
let failures=0;
function check(name,fn){try{fn();console.log('PASS '+name)}catch(e){failures++;console.error('FAIL '+name+': '+e.message)}}
check('Find menu closes history before showing message results',()=>{const {node}=setup();node('findConversation').onclick();assert.equal(node('history').hidden,true);assert.equal(node('chatFind').hidden,false);assert.ok(node('chatFindQuery').focused)});
check('Cmd-F from history shows results; Escape restores visible composer',()=>{const {node,key}=setup();key('f',{metaKey:true});assert.equal(node('history').hidden,true);assert.equal(node('chatFind').hidden,false);key('Escape');assert.equal(node('chatFind').hidden,true);assert.ok(node('draft').focused);assert.equal(node('history').hidden,true)});
check('History Escape does not cancel an active IME composition',()=>{const {node,key}=setup();const e=key('Escape',{isComposing:true});assert.equal(node('history').hidden,false);assert.equal(e.defaultPrevented,false)});
check('Find Escape does not cancel an active IME composition',()=>{const {node,key}=setup();node('findConversation').onclick();const e=key('Escape',{isComposing:true});assert.equal(node('chatFind').hidden,false);assert.equal(e.defaultPrevented,false)});
check('Find Enter allows IME confirmation rather than match navigation',()=>{const {node}=setup();let prevented=false;node('chatFindQuery').onkeydown({key:'Enter',isComposing:true,preventDefault(){prevented=true}});assert.equal(prevented,false)});
check('Composing Cmd-F does not replace the composing field',()=>{const {node,key}=setup();const e=key('f',{metaKey:true,isComposing:true});assert.equal(node('chatFind').hidden,true);assert.equal(e.defaultPrevented,false)});
check('Opening history closes Find and focuses title search',()=>{const {node,key}=setup();node('findConversation').onclick();node('historyButton').onclick();assert.equal(node('chatFind').hidden,true);assert.equal(node('history').hidden,false);assert.ok(node('historyQuery').focused);key('Escape');assert.equal(node('history').hidden,true);assert.ok(node('historyButton').focused)});
check('History toggle still closes an open drawer',()=>{const {node}=setup();node('historyButton').onclick();assert.equal(node('history').hidden,true)});
if(failures)process.exitCode=1;
