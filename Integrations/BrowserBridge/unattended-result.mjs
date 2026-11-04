// The pinned agent-browser0.41.2 MCP adapter must report a completed successful
// command in its structured child-process result. Errors remain uncertain for
// the interactive qualification profile, even when they contain a response.
// This is not a Fuego authority receipt or proof external effects are settled.
export function requireUnattendedSuccess(result) {
 const s=result?.structuredContent,r=s?.response;
 if(!result||!Array.isArray(result.content)||(result.isError!==undefined&&result.isError!==false)||
    !s||s.exitCode!==0||!r||r.success!==true||r.error!==null||!r.data||typeof r.data!=='object'||Array.isArray(r.data)) {
  throw Error('Unattended browser command outcome is uncertain; retain reservation and do not replay.');
 }
 return result;
}
