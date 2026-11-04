import { existsSync, openSync, writeFileSync, closeSync, readFileSync, unlinkSync, mkdirSync, fsyncSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { dirname } from 'node:path';

const text = (description, maxLength=1000) => ({type:'string',description,minLength:1,maxLength});
export const tools = [
  ['browser_open','Open an HTTP(S) URL in this connection’s browser.',{url:text('URL',4096)}],
  ['browser_snapshot','Read this browser’s current interactive accessibility snapshot.',{}],
  ['browser_click','Click one target in the current page. This can submit a form.',{target:text('CSS selector or element ref from the latest snapshot')}],
  ['browser_fill','Replace one field with text.',{target:text('CSS selector or latest element ref'),text:{type:'string',maxLength:8000}}],
  ['browser_press','Press one key/chord in the current page.',{key:text('Key, for example Enter or Control+a',100)}],
  ['browser_read','Read visible text of one target.',{target:text('CSS selector or latest element ref')}],
  ['browser_url','Read the current URL.',{}],
  ['browser_wait','Wait at most ten seconds. Cancellation prevents new input until this original wait retires.',{milliseconds:{type:'integer',minimum:1,maximum:10000}}],
  ['browser_reload','Reload the current page.',{}],
  ['browser_close','Close this connection’s owned tab/browser session; does not close unrelated browsers.',{}]
].map(([name,description,properties])=>({name,description,inputSchema:{type:'object',properties,required:Object.keys(properties),additionalProperties:false},annotations:{readOnlyHint:['browser_snapshot','browser_read','browser_url','browser_wait'].includes(name),openWorldHint:true}}));

export function operation(name,args={}) {
  const tool=tools.find(t=>t.name===name);
  if(!tool) throw Error('Unknown browser operation. Raw command batches, evaluation and file operations are not exposed.');
  if(!args||typeof args!=='object'||Array.isArray(args)||Object.keys(args).some(k=>!Object.hasOwn(tool.inputSchema.properties,k))) throw Error('Unexpected arguments; session, profile and execution settings are fixed by this connection.');
  for(const [key,schema] of Object.entries(tool.inputSchema.properties)) {
    const value=Object.hasOwn(args,key)?args[key]:undefined;
    if(schema.type==='string'&&(typeof value!=='string'||value.length<(schema.minLength??0)||value.length>schema.maxLength)) throw Error(`Invalid ${key}`);
    if(schema.type==='integer'&&(!Number.isInteger(value)||value<schema.minimum||value>schema.maximum)) throw Error(`Invalid ${key}`);
    if(key!=='text'&&typeof value==='string'&&/[\u0000-\u001f]/u.test(value)) throw Error(`Control characters not allowed in ${key}`);
  }
  if(name==='browser_open') {
    const u=new URL(args.url);
    if(!['http:','https:'].includes(u.protocol)||u.username||u.password) throw Error('Use an HTTP(S) URL without embedded credentials.');
  }
  return {name,args};
}

// Deployment-owned only: never accepted in the public tool argument schema.
export function fixedUnattendedBinding(binding={session:'neronook-local',namespace:'neronook168'}) {
  if(!binding||typeof binding!=='object'||Array.isArray(binding)||Object.keys(binding).some(k=>!['session','namespace'].includes(k))) throw Error('Invalid fixed browser binding');
  for(const key of ['session','namespace']) if(!Object.hasOwn(binding,key)||typeof binding[key]!=='string'||! /^[a-z][a-z0-9-]{0,63}$/.test(binding[key])) throw Error('Invalid fixed browser binding');
  return Object.freeze({session:binding.session,namespace:binding.namespace});
}

export function upstreamCall(lane,op,binding) {
  const a=op.args,q=JSON.stringify;
  if(lane==='signed') {
    const commands={browser_open:()=>`goto ${q(a.url)}`,browser_snapshot:()=> 'snapshot -i',
      browser_click:()=>`click ${q(a.target)}`,browser_fill:()=>`fill ${q(a.target)} ${q(a.text)}`,
      browser_press:()=>`press ${q(a.key)}`,browser_read:()=>`get text ${q(a.target)}`,
      browser_url:()=> 'get url',browser_wait:()=>`wait ${a.milliseconds}`,browser_reload:()=> 'reload',browser_close:()=> 'tab close'};
    return {name:'browser',arguments:{commands:commands[op.name]()}};
  }
  const common=fixedUnattendedBinding(binding);
  const calls={browser_open:['open',{url:a.url}],browser_snapshot:['snapshot',{interactive:true}],
    browser_click:['click',{selector:a.target}],browser_fill:['fill',{selector:a.target,text:a.text}],
    browser_press:['press',{key:a.key}],browser_read:['get_text',{selector:a.target}],
    browser_url:['get_url',{}],browser_wait:['wait_ms',{ms:a.milliseconds}],
    browser_reload:['reload',{}],browser_close:['close',{all:false}]};
  const [suffix,args]=calls[op.name];
  return {name:`agent_browser_${suffix}`,arguments:{...common,...args}};
}

export function requireOwnerReply(lane,result) {
  if(!result || !Array.isArray(result.content)) throw Error('Browser reply missing; outcome remains uncertain.');
  if(result.isError) {
    const message=result.content.filter(x=>x.type==='text').map(x=>x.text).join('\n');
    const wrappedTransport=lane==='signed'
      ? /^(The Browser MCP daemon stopped while handling this call|Connection closed|RPC[^\n]*timed out|Request timed out)/i.test(message)
      : !result.structuredContent?.response;
    if(wrappedTransport) throw Error('Browser transport outcome is uncertain. The reservation is retained; do not replay the operation.');
  }
  return result;
}

// Cancellation retires the caller, not already emitted browser input. Keep the
// actual upstream promise and persistent reservation until a response is received.
export class SingleActionGate {
  constructor({file,lane,invoke,audit=()=>{},binding}) { Object.assign(this,{file,lane,invoke,audit}); this.binding=lane==='unattended'?fixedUnattendedBinding(binding):undefined; this.active=null; }
  async run(name,args,signal) {
    if(signal?.aborted) throw Error('Cancelled before dispatch');
    const op=operation(name,args);
    if(this.active||existsSync(this.file)) throw Error('The prior browser operation is still finishing or its outcome is uncertain. No new input was sent. Do not retry a mutation.');
    mkdirSync(dirname(this.file),{recursive:true,mode:0o700});
    const record={id:randomUUID(),lane:this.lane,operation:name,started:new Date().toISOString()};
    const fd=openSync(this.file,'wx',0o600);
    try { writeFileSync(fd,JSON.stringify(record)); fsyncSync(fd); } finally { closeSync(fd); }
    const parent=openSync(dirname(this.file),'r');try{fsyncSync(parent);}finally{closeSync(parent);}
    const cancelled=()=>this.audit({event:'caller-cancelled',...record});
    signal?.addEventListener('abort',cancelled,{once:true});
    this.audit({event:'dispatched',...record});
    // Admission is synchronous through the reservation. No operation queue exists.
    const pending=Promise.resolve().then(()=>{
      if(signal?.aborted) return {notDispatched:true};
      return this.invoke(upstreamCall(this.lane,op,this.binding));
    });
    this.active=pending;
    let received=false;
    try {
      const result=await pending;
      received=true;
      this.audit({event:result.notDispatched?'cancelled-before-dispatch':'upstream-returned',...record});
      if(signal?.aborted) throw Error('Cancelled; original browser call has now returned. Already emitted effects were not undone.');
      return result;
    } finally {
      signal?.removeEventListener('abort',cancelled);
      if(received) {
        const current=JSON.parse(readFileSync(this.file,'utf8'));
        if(current.id!==record.id) throw Error('Browser reservation changed; retained for operator review.');
        unlinkSync(this.file);
      } else this.audit({event:'upstream-unknown-reservation-retained',...record});
      this.active=null;
    }
  }
}
