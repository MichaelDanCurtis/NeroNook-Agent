const assert=require('node:assert/strict');
const show=require('../Resources/Views/chat/chat-presence.js');
const cases=[
 ['background review does not masquerade as chat failure',{connected:true,presence:'Needs you'}, {}, 'Ready'],
 ['disconnected account is explicit',{connected:false,presence:'Watching'}, {}, 'Connect ChatGPT'],
 ['sending remains working',{connected:true,busy:true,presence:'Needs you'}, {}, 'Working'],
 ['history failure is not hidden',{connected:true,historyError:'disk failure'}, {}, 'History needs attention'],
 ['listening is authoritative',{connected:true}, {active:true,phase:'listening'}, 'Listening'],
 ['speaking is authoritative',{connected:true}, {active:true,phase:'speaking'}, 'Speaking'],
 ['voice approval remains explicit',{connected:true}, {active:true,phase:'permission'}, 'Needs approval'],
 ['unknown voice phase does not say ready',{connected:true}, {active:true,phase:'new-phase'}, 'Starting']
];
for(const [name,state,talk,label] of cases){assert.equal(show(state,talk).label,label,name); console.log('PASS '+name)}
assert.match(show({connected:true,presence:'Needs you'}).activityLabel,/Needs review/);
assert.doesNotMatch(show({connected:true,presence:'Watching'}).activityLabel,/Needs review/);
console.log('PASS background attention remains reachable without stale badge');
