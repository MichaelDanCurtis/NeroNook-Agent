const $=id=>document.getElementById(id);let state={},lastMessages='',lastHistory='',conversation='',pendingDraft=null;
function emit(name,values={}){return nero.emit(name,values).catch(e=>{$('error').textContent=e.message||'This action could not be delivered.';$('error').hidden=false;throw e;});}
function el(tag,text,cls){let n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;}
// A deliberately small Markdown renderer. Never interpolate model text as HTML,
// load external images, or give generated links an executable destination.
function inline(parent,text){let re=/(\[[^\]\n]{1,200}\]\(https?:\/\/[^\s)]+\)|\*\*[^*]+\*\*|`[^`]+`)/g,pos=0;for(let m;(m=re.exec(text));){parent.append(document.createTextNode(text.slice(pos,m.index)));let link=m[0].match(/^\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)$/);if(link){let a=el('a',link[1]);a.href=link[2];a.onclick=e=>{e.preventDefault();emit('link',{url:link[2]});};parent.append(a);}else parent.append(el(m[0][0]==='`'?'code':'strong',m[0].slice(m[0][0]==='`'?1:2,m[0][0]==='`'?-1:-2)));pos=re.lastIndex;}parent.append(document.createTextNode(text.slice(pos)));}
function markdown(parent,text){let code=false,buf=[],list=null;for(const line of text.split('\n')){if(line.startsWith('```')){if(code){parent.append(el('pre',buf.join('\n')));buf=[];}code=!code;list=null;continue;}if(code){buf.push(line);continue;}let m=line.match(/^\s*(?:[-*]|\d+\.)\s+(.+)/);if(m){if(!list){list=el(/^\s*\d/.test(line)?'ol':'ul');if(list.tagName==='OL')list.start=parseInt(line.trim(),10);parent.append(list);}let li=el('li');inline(li,m[1]);list.append(li);continue;}list=null;let n=el(/^#{1,3}\s/.test(line)?'h3':'p');inline(n,line.replace(/^#{1,3}\s/,''));parent.append(n);}if(code)parent.append(el('pre',buf.join('\n')));}
function send(){const text=$('draft').value.trim();if(!text||state.busy||!state.connected)return;if(new TextEncoder().encode(text).length>2048){$('error').textContent='Please keep this message under 2,048 bytes.';$('error').hidden=false;return;}pendingDraft=text;emit('send',{text,context:$('useContext').checked});}
$('speechProvider').onchange=()=>emit('speech_provider',{key:$('speechProvider').value});$('stopSpeech').onclick=()=>emit('stop_speech');
$('send').onclick=send;$('stop').onclick=()=>emit('stop');$('new').onclick=()=>emit('new');$('tools').onclick=()=>emit('tools');$('settings').onclick=()=>emit('settings');$('open').onclick=()=>emit('open');$('review').onclick=()=>emit('review');$('retry').onclick=()=>emit('retry');$('historyButton').onclick=()=>{$('history').hidden=!$('history').hidden;};$('closeHistory').onclick=()=>{$('history').hidden=true;};
$('draft').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();send();}});$('draft').addEventListener('input',()=>{$('send').disabled=!state.connected||state.busy||!$('draft').value.trim();});
function contextHint(){$('contextHint').textContent=$('useContext').checked?`${state.contextCount||0} tools · only permitted, shareable context`:'Only your message and conversation';}
$('useContext').onchange=contextHint;
for(const button of document.querySelectorAll('[data-prompt]'))button.onclick=()=>{$('draft').value=button.dataset.prompt;$('useContext').checked=button.dataset.context==='true';contextHint();$('draft').focus();$('send').disabled=!state.connected||state.busy;};
$('agentModel').onchange=()=>emit('settings',{command:'model',id:$('agentModel').value});
$('previousModels').onclick=()=>emit('settings',{command:'model_page',id:String(Math.max(0,(state.modelPage||0)-1))});
$('nextModels').onclick=()=>emit('settings',{command:'model_page',id:String((state.modelPage||0)+1)});
$('refreshModels').onclick=()=>emit('settings',{command:'refresh_models'});
nero.onState(next=>{state=next;
 $('previousModels').hidden=(state.modelPages||1)<=1;$('nextModels').hidden=(state.modelPages||1)<=1;$('previousModels').disabled=(state.modelPage||0)<=0;$('nextModels').disabled=(state.modelPage||0)+1>=(state.modelPages||1);
 let models=[];try{models=JSON.parse(state.models||'[]');}catch{}
 const modelChoices=JSON.stringify([models,state.selectedModel]);
 if($('agentModel').dataset.choices!==modelChoices){$('agentModel').dataset.choices=modelChoices;$('agentModel').replaceChildren(new Option('Account default',''));for(const m of models)$('agentModel').add(new Option(m.name,m.id));if(state.selectedModel&&!models.some(m=>m.id===state.selectedModel))$('agentModel').add(new Option('Unavailable · '+state.selectedModel,state.selectedModel));}
 $('agentModel').value=state.selectedModel||'';$('agentModel').disabled=!!state.busy||!state.connected||!!state.modelsLoading;
 $('refreshModels').disabled=!!state.busy||!state.connected||!!state.modelsLoading;$('modelStatus').textContent=state.modelsLoading?'Preparing model choices…':(state.modelStatus||'');

 $('toolSummary').textContent=state.toolSummary||'';
 if($('toolReviews').dataset.value!==state.toolReviews){$('toolReviews').dataset.value=state.toolReviews;$('toolReviews').replaceChildren();let reviews=[];try{reviews=JSON.parse(state.toolReviews||'[]');}catch{}
 $('toolReviews').hidden=!reviews.length;
 for(const review of reviews){let box=el('div',undefined,'toolReview');box.append(el('strong',review.title),el('pre',review.detail),el('p',review.consequence));if(review.waiting>1)box.append(el('p',`${review.waiting} requests waiting · reviewed one at a time`));let yes=el('button',review.requiresFullReview?'Open full request…':'Allow once'),no=el('button','Decline');yes.onclick=()=>review.requiresFullReview?emit('tools'):emit('tool_review',{id:review.id,allow:true});no.onclick=()=>emit('tool_review',{id:review.id,allow:false});if(review.requiresFullReview)box.append(el('p','This is a preview. Open the full request to review every argument before allowing it.'));box.append(yes,no);$('toolReviews').append(box);}}

 let talk={};try{talk=JSON.parse(state.talk||'{}');}catch{}
 let talkProviders=[];try{talkProviders=JSON.parse(talk.providers||'[]');}catch{}
 const talkChoices=JSON.stringify(talkProviders);if($('talkProvider').dataset.choices!==talkChoices){$('talkProvider').dataset.choices=talkChoices;$('talkProvider').replaceChildren(new Option('Choose voice provider…',''));for(const p of talkProviders)$('talkProvider').add(new Option(p.name,p.key));}
 $('talkProvider').value=talk.provider||'';$('talkProvider').hidden=talkProviders.length<2;$('talkProvider').disabled=!!talk.active;
 $('talkSettings').disabled=!talk.accessAvailable&&!talkProviders.some(p=>p.key===talk.provider);$('talkStart').hidden=!!talk.active;$('talkStart').disabled=!state.connected||!!state.busy||(!talk.accessAvailable&&!talkProviders.some(p=>p.key===talk.provider));$('talkStop').hidden=!talk.active;
 $('replyPace').value=talk.replyPace||'quick';
 let voiceControls=null;try{voiceControls=JSON.parse(talk.controls||'null');}catch{}
 $('talkMicrophoneName').textContent=talk.active&&voiceControls?.microphone?voiceControls.microphone:'Microphone';
 $('talkSettings').title=talk.active?'Change microphone · stops Talk':'Choose microphone and speech recognition';
 $('talkExpression').checked=!!talk.expressionEnabled;$('talkExpression').disabled=!talk.ready;
 $('talkVoiceEngine').textContent=voiceControls?.recognition||'Shared local speech for Nero and Ember';
 const sensitivity=$('talkSensitivity');sensitivity.disabled=!talk.ready||!voiceControls;
 if(document.activeElement!==sensitivity)sensitivity.value=String(voiceControls?.sensitivity??50);
 $('talkSensitivityValue').textContent=voiceControls?sensitivity.value+'%':'—';
 $('talkSensitivityHint').textContent=talk.ready&&voiceControls?(talk.mode==='full'?'Changes apply immediately.':'Used in Full duplex. Half duplex waits until the reply ends.'):'Start Talk to adjust live, or open voice settings below.';
 document.body.classList.toggle('nc-talking',!!talk.active);

 $('duplex').value=talk.mode||'half';$('duplex').disabled=!!talk.active&&!talk.ready;$('talkState').textContent=talk.active?(talk.phase==='permission'?(talk.status||'Waiting for voice permission…'):(talk.phase||'starting')):(talk.status||'Press Talk to start');
 $('talkWords').textContent=talk.partial||(talk.active?talk.status:'');$('talkWords').hidden=!$('talkWords').textContent;
 window.NookAvatar?.setBusy?.(!!talk.active||(!!state.speechActive&&!state.reactionSpeaking));document.querySelectorAll('.nook-presence').forEach(el=>{window.NookAvatar?.speech(el,talk.outputLevel||0,talk.active&&talk.phase==='speaking');let pose={};try{pose=JSON.parse(talk.expression||'{}')}catch{}window.NookAvatar?.expression(el,pose);});
 $('talkMeter').hidden=!talk.active;
 $('talkMeter').value=talk.active ? (talk.phase==='speaking' ? (talk.outputLevel||0):(talk.level||0)):0;
 $('talkMeter').setAttribute('aria-label',talk.phase==='speaking'?'Speech playback level':'Microphone level');
 $('voiceOrb').className='nook-presence nc-presence '+(talk.active?talk.phase:'idle');
 $('talkBar').hidden=!talk.active;$('timeline').hidden=!!talk.active;$('composer').hidden=!!talk.active;$('typeInstead').hidden=!talk.active;
 const phase=talk.phase||'preparing',titles={listening:'I’m listening.',thinking:'Let me think.',speaking:'Here’s what I think.',preparing:'Getting ready…',permission:'Connect your voice.'};
 $('talkHeading').textContent=titles[phase]||'Talk with Nero.';
 $('talkSubtitle').textContent=phase==='listening'?'Take your time.':phase==='speaking'?(talk.mode==='full'?'You can interrupt me.':'I’ll listen when I finish.'):'One moment.';
 let spoken=[];try{spoken=JSON.parse(state.messages||'[]');}catch{}
 const recent=spoken.filter(m=>m.role===(phase==='speaking'?'assistant':'user')).at(-1);
 $('talkWords').textContent=talk.partial||(phase==='speaking'||phase==='thinking'?recent?.text||'':'');$('talkWords').hidden=!$('talkWords').textContent;
 $('talkState').textContent=phase==='permission'?talk.status||'Waiting for your approval…':'';
 for(const [id,mode] of [['fullDuplex','full'],['halfDuplex','half']]){$(id).setAttribute('aria-pressed',String((talk.mode||'half')===mode));$(id).disabled=!!talk.active&&!talk.ready;}


 let providers=[];try{providers=JSON.parse(state.speechProviders||'[]');}catch{}
 const choices=JSON.stringify(providers);if($('speechProvider').dataset.choices!==choices){$('speechProvider').dataset.choices=choices;$('speechProvider').replaceChildren(new Option('Choose provider…',''));for(const p of providers)$('speechProvider').add(new Option(p.name,p.key));}
 $('speechProvider').value=state.speechProvider||'';$('speechStatus').textContent=state.speechStatus||'';$('stopSpeech').hidden=!state.speechActive;
 for(const b of document.querySelectorAll('.readAloud'))b.disabled=!providers.some(p=>p.key===state.speechProvider)||state.speechActive;
$('presence').textContent=talk.active?({listening:'Listening',thinking:'Thinking',speaking:'Speaking',preparing:'Preparing',permission:'Needs approval'}[talk.phase]||'Starting'):state.busy?'Working':(state.presence||'Ready');$('presence').dataset.capturing=String(!!talk.ready&&(talk.mode==='full'||talk.phase==='listening'));$('talkWaveLabel').textContent=talk.phase==='speaking'?'Voice':'Live words';$('error').hidden=!state.historyError;$('error').textContent=state.historyError||'';
 if(conversation!==state.conversation){conversation=state.conversation;$('draft').value='';$('history').hidden=true;lastMessages='';pendingDraft=null;}
 let messages=[];try{messages=JSON.parse(state.messages||'[]');}catch{}
 if(pendingDraft&&messages.some(m=>m.role==='user'&&m.text===pendingDraft)&&state.busy){if($('draft').value.trim()===pendingDraft)$('draft').value='';pendingDraft=null;}
 if(lastMessages!==state.messages){let near=$('timeline').scrollHeight-$('timeline').scrollTop-$('timeline').clientHeight<70;lastMessages=state.messages;$('messages').replaceChildren();
 if(state.omitted)$('messages').append(el('p','Showing recent messages and excerpts. Copy retrieves the full original message.','notice'));
 for(const message of messages){let item=el('article',undefined,'message '+message.role),by=el('div',message.role==='user'?'You':'✳ Nero','byline');if(message.context)by.append(el('span','· Nook context'));item.append(by);
 for(const activity of message.activities||[])item.append(el('div',(activity.phase==='complete'?'✓ ':activity.phase==='failed'?'! ':'')+activity.title,'activity '+activity.phase));
 let body=el('div',undefined,'body');if(message.role==='assistant')markdown(body,message.text);else body.textContent=message.text;item.append(body);if(message.excerpt)item.append(el('p','Message excerpt · Copy for the full text.','notice'));
 if(message.phase==='working'&&!message.text)item.append(el('div',state.status||'Thinking…','thinking'));else if(message.phase!=='complete'&&message.phase!=='working')item.append(el('span',message.phase,'phase'));
 if(message.role==='user'&&!state.busy){let tools=el('div',undefined,'messageTools'),edit=el('button','Edit & resend'),copy=el('button',message.excerpt?'Copy full message':'Copy');edit.disabled=!!message.excerpt;edit.title=message.excerpt?'Copy the full original message before editing.':'';edit.onclick=()=>{$('draft').value=message.text;$('useContext').checked=message.context;contextHint();$('draft').focus();$('send').disabled=!state.connected;};copy.onclick=()=>emit('copy',{id:message.id});tools.append(edit,copy);item.append(tools);}
 if(message.role==='assistant'&&message.text){let tools=el('div',undefined,'messageTools'),copy=el('button','Copy');copy.onclick=()=>emit('copy',{id:message.id});tools.append(copy);if(message.phase==='complete'){let read=el('button','Read aloud');read.disabled=!state.speechProvider||!JSON.parse(state.speechProviders||'[]').some(p=>p.key===state.speechProvider)||state.speechActive;read.className='readAloud';read.onclick=()=>emit('read',{id:message.id});tools.append(read);}item.append(tools);}
 $('messages').append(item);}
 $('empty').hidden=messages.length>0;if(!messages.length)$('timeline').scrollTop=0;else if(near||messages.length<=2)$('timeline').scrollTop=$('timeline').scrollHeight;
 }
 if(lastHistory!==state.history){lastHistory=state.history;$('conversations').replaceChildren();let chats=[];try{chats=JSON.parse(state.history||'[]');}catch{}for(const chat of chats){let b=el('button',chat.title,chat.id===state.conversation?'selected':'');b.disabled=state.busy;b.onclick=()=>emit('select',{id:chat.id});$('conversations').append(b);}}
 for(const b of $('conversations').querySelectorAll('button'))b.disabled=!!state.busy;
 $('retention').textContent=state.retention?`Kept on this Mac for ${state.retention} days.`:'Kept until you quit. Choose local history in Settings.';
 $('status').textContent=state.status||'Ready';$('stop').hidden=!state.busy;$('send').hidden=!!state.busy;$('send').disabled=!state.connected||state.busy||!$('draft').value.trim();$('new').disabled=!!state.busy;$('useContext').disabled=!!state.busy||!!talk.active;$('retry').hidden=state.busy||!messages.length;$('proposal').hidden=!state.proposal;$('proposal').querySelector('pre').textContent=state.proposal||'';$('review').disabled=!!state.busy;contextHint();
});

$('talkStart').onclick=()=>emit('talk',{command:'start',context:$('useContext').checked});
$('talkStop').onclick=()=>emit('talk',{command:'stop'});
$('duplex').onchange=()=>emit('talk',{command:'mode',value:$('duplex').value});
$('replyPace').onchange=()=>emit('talk',{command:'pace',value:$('replyPace').value});
$('talkProvider').onchange=()=>emit('talk',{command:'provider',value:$('talkProvider').value});

$('talkSettings').onclick=()=>emit('talk',{command:'settings'});

for(const [id,mode] of [['fullDuplex','full'],['halfDuplex','half']])$(id).onclick=()=>{$('duplex').value=mode;$('duplex').onchange();};
$('typeInstead').onclick=()=>{emit('talk',{command:'stop'});$('composer').hidden=false;$('draft').focus();};
for(const id of ['tools','settings','open','talkSettings']){const handler=$(id).onclick;$(id).onclick=()=>{$('agentMenu').open=false;handler();};}

$('connectNero').onclick=()=>$('settings').onclick();
nero.onState(s=>{$('connectNero').hidden=!!s.connected;$('welcomeHeading').textContent=s.connected?'What’s on your mind?':'Connect Nero.';$('welcomeSubtitle').textContent=s.connected?'Write a message, or talk with Nero.':'Use your ChatGPT sign-in to get started.';});

$('activity').onclick=()=>{$('agentMenu').open=false;emit('open',{page:'activity'});};

$('talkSensitivity').oninput=()=>{$('talkSensitivityValue').textContent=$('talkSensitivity').value+'%';};
$('talkSensitivity').onchange=()=>emit('talk',{command:'sensitivity',value:$('talkSensitivity').value});
$('talkAllVoiceSettings').onclick=()=>{$('talkVoiceControls').open=false;emit('talk',{command:'settings'});};
document.addEventListener('pointerdown',e=>{if(!$('talkVoiceControls').contains(e.target))$('talkVoiceControls').open=false;});
document.addEventListener('keydown',e=>{if(e.key==='Escape')$('talkVoiceControls').open=false;});

// Explicit click handling also supports nonactivating Nook panels.
$('talkVoiceControls').querySelector('summary').onclick=e=>{e.preventDefault();$('talkVoiceControls').open=!$('talkVoiceControls').open;};

$('talkExpression').onchange=()=>emit('talk',{command:'expression',value:String($('talkExpression').checked)});
