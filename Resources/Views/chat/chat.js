const $=id=>document.getElementById(id);let state={},lastMessages='',lastHistory='',conversation='',pendingDraft=null;
function emit(name,values={}){return nero.emit(name,values).catch(e=>{$('error').textContent=e.message||'This action could not be delivered.';$('error').hidden=false;throw e;});}
function el(tag,text,cls){let n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;}
// A deliberately small Markdown renderer. Never interpolate model text as HTML,
// load external images, or give generated links an executable destination.
function inline(parent,text){let re=/(\*\*[^*]+\*\*|`[^`]+`)/g,pos=0;for(let m; (m=re.exec(text));){parent.append(document.createTextNode(text.slice(pos,m.index)));parent.append(el(m[0][0]==='`'?'code':'strong',m[0].slice(m[0][0]==='`'?1:2,m[0][0]==='`'?-1:-2)));pos=re.lastIndex;}parent.append(document.createTextNode(text.slice(pos)));}
function markdown(parent,text){let code=false,buf=[],list=null;for(const line of text.split('\n')){if(line.startsWith('```')){if(code){parent.append(el('pre',buf.join('\n')));buf=[];}code=!code;list=null;continue;}if(code){buf.push(line);continue;}let m=line.match(/^\s*(?:[-*]|\d+\.)\s+(.+)/);if(m){if(!list){list=el(/^\s*\d/.test(line)?'ol':'ul');if(list.tagName==='OL')list.start=parseInt(line.trim(),10);parent.append(list);}let li=el('li');inline(li,m[1]);list.append(li);continue;}list=null;let n=el(/^#{1,3}\s/.test(line)?'h3':'p');inline(n,line.replace(/^#{1,3}\s/,''));parent.append(n);}if(code)parent.append(el('pre',buf.join('\n')));}
function send(){const text=$('draft').value.trim();if(!text||state.busy||!state.connected)return;if(new TextEncoder().encode(text).length>2048){$('error').textContent='Please keep this message under 2,048 bytes.';$('error').hidden=false;return;}pendingDraft=text;emit('send',{text,context:$('useContext').checked});}
$('send').onclick=send;$('stop').onclick=()=>emit('stop');$('new').onclick=()=>emit('new');$('settings').onclick=()=>emit('settings');$('open').onclick=()=>emit('open');$('review').onclick=()=>emit('review');$('retry').onclick=()=>emit('retry');$('historyButton').onclick=()=>{$('history').hidden=!$('history').hidden;};$('closeHistory').onclick=()=>{$('history').hidden=true;};
$('draft').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();send();}});$('draft').addEventListener('input',()=>{$('send').disabled=!state.connected||state.busy||!$('draft').value.trim();});
function contextHint(){$('contextHint').textContent=$('useContext').checked?`${state.contextCount||0} permitted tools · reads may be sent to ChatGPT`:'Only your message and conversation';}
$('useContext').onchange=contextHint;
for(const button of document.querySelectorAll('[data-prompt]'))button.onclick=()=>{$('draft').value=button.dataset.prompt;$('useContext').checked=button.dataset.context==='true';contextHint();$('draft').focus();$('send').disabled=!state.connected||state.busy;};
nero.onState(next=>{state=next;$('error').hidden=!state.historyError;$('error').textContent=state.historyError||'';
 if(conversation!==state.conversation){conversation=state.conversation;$('draft').value='';$('history').hidden=true;lastMessages='';pendingDraft=null;}
 let messages=[];try{messages=JSON.parse(state.messages||'[]');}catch{}
 if(pendingDraft&&messages.some(m=>m.role==='user'&&m.text===pendingDraft)&&state.busy){if($('draft').value.trim()===pendingDraft)$('draft').value='';pendingDraft=null;}
 if(lastMessages!==state.messages){let near=$('timeline').scrollHeight-$('timeline').scrollTop-$('timeline').clientHeight<70;lastMessages=state.messages;$('messages').replaceChildren();
 if(state.omitted)$('messages').append(el('p','Showing the most recent messages in this view.','notice'));
 for(const message of messages){let item=el('article',undefined,'message '+message.role),by=el('div',message.role==='user'?'You':'✳ Nero','byline');if(message.context)by.append(el('span','· Nook context'));item.append(by);
 for(const activity of message.activities||[])item.append(el('div',(activity.phase==='complete'?'✓ ':activity.phase==='failed'?'! ':'')+activity.title,'activity '+activity.phase));
 let body=el('div',undefined,'body');if(message.role==='assistant')markdown(body,message.text);else body.textContent=message.text;item.append(body);
 if(message.phase==='working'&&!message.text)item.append(el('div',state.status||'Thinking…','thinking'));else if(message.phase!=='complete'&&message.phase!=='working')item.append(el('span',message.phase,'phase'));
 if(message.role==='user'&&!state.busy){let tools=el('div',undefined,'messageTools'),edit=el('button','Edit & resend');edit.onclick=()=>{$('draft').value=message.text;$('useContext').checked=message.context;contextHint();$('draft').focus();$('send').disabled=!state.connected;};tools.append(edit);item.append(tools);}
 if(message.role==='assistant'&&message.text){let tools=el('div',undefined,'messageTools'),copy=el('button','Copy');copy.onclick=()=>emit('copy',{id:message.id});tools.append(copy);item.append(tools);}
 $('messages').append(item);}
 $('empty').hidden=messages.length>0;if(near||messages.length<=2)$('timeline').scrollTop=$('timeline').scrollHeight;
 }
 if(lastHistory!==state.history){lastHistory=state.history;$('conversations').replaceChildren();let chats=[];try{chats=JSON.parse(state.history||'[]');}catch{}for(const chat of chats){let b=el('button',chat.title,chat.id===state.conversation?'selected':'');b.disabled=state.busy;b.onclick=()=>emit('select',{id:chat.id});$('conversations').append(b);}}
 for(const b of $('conversations').querySelectorAll('button'))b.disabled=!!state.busy;
 $('retention').textContent=state.retention?`Kept on this Mac for ${state.retention} days.`:'Kept until you quit. Choose local history in Settings.';
 $('status').textContent=state.status||'Ready';$('stop').hidden=!state.busy;$('send').hidden=!!state.busy;$('send').disabled=!state.connected||state.busy||!$('draft').value.trim();$('new').disabled=!!state.busy;$('useContext').disabled=!!state.busy;$('retry').hidden=state.busy||!messages.length;$('proposal').hidden=!state.proposal;$('proposal').querySelector('pre').textContent=state.proposal||'';$('review').disabled=!!state.busy;contextHint();
});
