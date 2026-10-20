const fs=require('fs'),vm=require('vm'),assert=require('assert');
const nodes=new Map();function node(){return {value:'',checked:false,textContent:'',hidden:false,disabled:false,dataset:{},style:{setProperty(){}},setAttribute(k,v){this[k]=v},children:[],scrollHeight:0,scrollTop:0,clientHeight:0,append(...v){this.children.push(...v)},add(v){this.children.push(v)},replaceChildren(...v){this.children=v},querySelector(selector){this.selectors??={};return this.selectors[selector]??=node()},querySelectorAll(){return []},addEventListener(){},focus(){}}}
const document={body:{classList:{toggle(){}}},addEventListener(){},getElementById(id){if(!nodes.has(id))nodes.set(id,node());return nodes.get(id)},querySelectorAll(){return []},createElement(){return node()},createTextNode(s){return {textContent:s}}};
let listeners=[],update,events=[];const context={document,Option:function(text,value){return {text,value}},TextEncoder,nero:{onState(f){listeners.push(f);update=s=>listeners.forEach(fn=>fn(s))},emit(name,values){events.push({name,values});return Promise.resolve()}},console};vm.createContext(context);vm.runInContext(fs.readFileSync('Resources/Views/chat/chat.js','utf8'),context);
function state(talk,extra={}){update({connected:true,busy:false,messages:'[]',history:'[]',models:'[]',toolReviews:'[]',speechProviders:'[]',talk:JSON.stringify({providers:'[]',...talk}),...extra})}
state({accessAvailable:true});assert.equal(nodes.get('talkStart').disabled,false,'Talk must be usable before a grant');assert.equal(nodes.get('talkProvider').hidden,true,'Do not show an empty permissions selector');
nodes.get('talkStart').onclick();assert.equal(events.at(-1).name,'talk');assert.equal(events.at(-1).values.command,'start');
state({accessAvailable:false});assert.equal(nodes.get('talkStart').disabled,true,'Legacy host cannot send an unnegotiated request');
state({accessAvailable:true,active:true,status:'Waiting for your permission…',phase:'permission'});assert.equal(nodes.get('talkStop').hidden,false);assert.equal(nodes.get('talkStart').hidden,true);assert.equal(nodes.get('talkState').textContent,'Waiting for your permission…');
state({accessAvailable:true},{connected:false});assert.equal(nodes.get('talkStart').disabled,true);
state({accessAvailable:true},{busy:true});assert.equal(nodes.get('talkStart').disabled,true);
state({accessAvailable:false,provider:'test.voice/speech_conversation',providers:JSON.stringify([{key:'test.voice/speech_conversation',name:'Voice'}])});assert.equal(nodes.get('talkStart').disabled,false);
console.log('PASS: Talk before first grant, explicit click event, legacy/disconnected/busy guards, waiting Stop, existing provider path, no empty provider dropdown.');

state({active:true,phase:'speaking',level:0.01,outputLevel:0.75});assert.equal(nodes.get('talkMeter').value,0.75);assert.equal(nodes.get('talkMeter')['aria-label'],'Speech playback level');
state({active:true,phase:'listening',level:0.2,outputLevel:0});assert.equal(nodes.get('talkMeter').value,0.2);
state({active:false,phase:'idle',outputLevel:0});assert.equal(nodes.get('talkMeter').value,0);
console.log('PASS: playback meter uses output while speaking and clears on Stop');

state({accessAvailable:true,active:true,ready:true,phase:'listening',mode:'full'});assert.equal(nodes.get('talkBar').hidden,false);assert.equal(nodes.get('timeline').hidden,true);assert.equal(nodes.get('composer').hidden,true);assert.equal(nodes.get('fullDuplex')['aria-pressed'],'true');nodes.get('talkSettings').onclick();assert.equal(events.at(-1).values.command,'settings');nodes.get('typeInstead').onclick();assert.equal(events.at(-1).values.command,'stop');state({active:false,phase:'idle'});assert.equal(nodes.get('timeline').hidden,false);assert.equal(nodes.get('composer').hidden,false);console.log('PASS: focused voice stage, explicit typing transition, duplex and primary microphone routing');

state({accessAvailable:true,active:true,ready:true,phase:'listening',mode:'full',controls:JSON.stringify({version:1,microphone:'Fixture microphone',recognition:'Fixture ASR',sensitivity:50})});
assert.equal(nodes.get('talkMicrophoneName').textContent,'Fixture microphone');assert.equal(nodes.get('talkSensitivity').disabled,false);
nodes.get('talkSensitivity').value='20';nodes.get('talkSensitivity').onchange();assert.equal(events.at(-1).values.command,'sensitivity');assert.equal(events.at(-1).values.value,'20');
state({accessAvailable:true,active:true,ready:true,phase:'listening',mode:'full'});assert.equal(nodes.get('talkSensitivity').disabled,true,'Legacy providers must not receive unsupported controls');
console.log('PASS: visible microphone, live sensitivity event and legacy capability guard');

let prevented=0;const panel=nodes.get('talkVoiceControls'),toggle=panel.querySelector('summary');
panel.open=false;toggle.onclick({preventDefault(){prevented++}});assert.equal(panel.open,true);toggle.onclick({preventDefault(){prevented++}});assert.equal(panel.open,false);assert.equal(prevented,2);
console.log('PASS: explicit Voice panel open/close suppresses the native default toggle');
