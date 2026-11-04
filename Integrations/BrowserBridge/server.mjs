import { appendFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { SingleActionGate,tools,requireOwnerReply } from './single-action.mjs';

const lane=process.argv[2];
if(!['signed','unattended'].includes(lane)) throw Error('Choose one installed browser lane');
const base=dirname(fileURLToPath(import.meta.url));
const sdk=pathToFileURL(join(base,'node_modules/@modelcontextprotocol/sdk/dist/esm')).href+'/';
const [{Server},{StdioServerTransport},{Client},{StdioClientTransport},types]=await Promise.all([
  import(sdk+'server/index.js'),import(sdk+'server/stdio.js'),import(sdk+'client/index.js'),import(sdk+'client/stdio.js'),import(sdk+'types.js')]);
const upstream=new Client({name:`Nero ${lane==='signed'?'signed-in':'unattended'} browser`,version:'168'},{capabilities:{}});
const command=lane==='signed'?join(base,'upstream-signed'):join(base,'upstream-unattended');
const transport=new StdioClientTransport({command,env:{HOME:process.env.HOME,USER:process.env.USER,PATH:process.env.PATH,TMPDIR:process.env.TMPDIR||'/tmp'},stderr:'inherit'});
await upstream.connect(transport);
const state=join(base,'bridge-state');mkdirSync(state,{recursive:true,mode:0o700});
const gate=new SingleActionGate({file:join(state,`${lane}.pending.json`),lane,
  invoke:async params=>requireOwnerReply(lane,await upstream.callTool(params,undefined,{timeout:60000})),
  audit:row=>appendFileSync(join(state,`${lane}.jsonl`),JSON.stringify({...row,at:new Date().toISOString()})+'\n',{mode:0o600})});
const server=new Server({name:`Nero ${lane==='signed'?'signed-in':'unattended'} browser`,version:'168'},{capabilities:{tools:{}}});
let closing=false;
server.setRequestHandler(types.ListToolsRequestSchema,async()=>({tools}));
server.setRequestHandler(types.CallToolRequestSchema,async(request,extra)=>{
  try {
    if(closing) throw Error('Browser connection is closing. No new input sent.');
    return await gate.run(request.params.name,request.params.arguments,extra.signal);
  } catch(error) { return {isError:true,content:[{type:'text',text:String(error.message||error)}]}; }
});
let shutdown;
async function close() {
  if(shutdown) return shutdown;
  closing=true;
  shutdown=(async()=>{
    try { await gate.active; } catch {}
    await upstream.close();
    await server.close();
  })();
  return shutdown;
}
server.onclose=()=>{void close();};
process.stdin.on('close',()=>{void close();});
process.on('SIGTERM',()=>{void close();});
process.on('SIGINT',()=>{void close();});
await server.connect(new StdioServerTransport());
