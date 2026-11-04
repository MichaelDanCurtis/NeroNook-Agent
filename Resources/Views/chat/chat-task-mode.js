(function(root){
 const modes={
 chat:{label:'Chat',hint:'Conversation with Nero.',prefix:''},
 search:{label:'Search the web',hint:'Searches and reads sources. Does not open or control Chrome.',prefix:'\n\n[Nero task focus: Search the web]\nSearch and read sources using web search. Do not open or control a browser for this request.'},
 browser:{label:'Use my browser',hint:'Uses your signed-in Chrome through Browser MCP. Actions need review.',prefix:'\n\n[Nero task focus: Use my browser]\nUse only the explicitly connected Use my browser · Browser MCP connection for browser actions. Discover its tools and verify the page after acting. Do not substitute unattended browsing, Chrome DevTools, a web search, or a Mac open-URL action. If this connection is unavailable, explain that.'},
 unattended:{label:'Unattended browser',hint:'Uses a separate headless browser through agent-browser. Actions need review.',prefix:'\n\n[Nero task focus: Unattended browser]\nUse only the explicitly connected Unattended browser · agent-browser connection. Discover its tools and verify the page after acting. This browser has separate state from my signed-in Chrome. Do not substitute my personal browser, a web search, or a Mac open-URL action. If this connection is unavailable, explain that.'}
 };
 const legacyPrefixes=['\n\n[Nero task focus: Use my browser]\nUse the connected Chrome DevTools MCP browser tools. Discover its tools if necessary and verify browser state. Do not substitute a web search or a Mac open-URL action. If the browser connection is unavailable, explain that.'];
 function request(text,mode){return text+(modes[mode]||modes.chat).prefix;}
 function display(text){for(const prefix of [...Object.values(modes).map(m=>m.prefix),...legacyPrefixes]){if(prefix&&text.endsWith(prefix))return text.slice(0,-prefix.length);}return text;}
 function acknowledge(pending,messages,current){return !!pending&&messages.some(m=>m.role==='user'&&m.text===pending.sent)&&current.trim()===pending.draft;}
 if(typeof module!=='undefined'&&module.exports){module.exports={modes,request,display,acknowledge};return;}
 let chosen='chat';
 function select(mode){chosen=mode;for(const key of Object.keys(modes))document.getElementById('mode-'+key).setAttribute('aria-pressed',String(key===chosen));document.getElementById('taskHint').textContent=modes[chosen].hint;}
 root.NeroTaskMode={request:text=>request(text,chosen),display,acknowledge};
 function start(){for(const key of Object.keys(modes))document.getElementById('mode-'+key).onclick=()=>{select(key);document.getElementById('draft').focus();};select('chat');}
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();
})(globalThis);
