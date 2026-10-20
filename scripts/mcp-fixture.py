#!/usr/bin/env python3
"""Authored, local-only MCP fixture. No user files, credentials, capture or network services."""
import json, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

def result(m):
 method=m.get('method'); p=m.get('params',{})
 if method=='initialize': return {'protocolVersion':'2025-11-25','capabilities':{'tools':{},'resources':{},'prompts':{}},'serverInfo':{'name':'nero-qualification','version':'1.0'}}
 if method=='tools/list':
  if p.get('cursor')=='second':return {'tools':[{'name':'slow','description':'Wait for cancellation','inputSchema':{'type':'object','properties':{}}}]}
  return {'tools':[{'name':'echo','description':'Return authored text only','inputSchema':{'type':'object','properties':{'text':{'type':'string'}},'required':['text'],'additionalProperties':False},'annotations':{'readOnlyHint':True,'destructiveHint':False}}], 'nextCursor':'second'}
 if method=='tools/call':
  if p['name']=='slow':return None
  return {'content':[{'type':'text','text':'MCP receipt: '+p.get('arguments',{}).get('text','')}],'isError':False}
 if method=='resources/list':return {'resources':[{'uri':'nero-test://passage','name':'Authored passage','mimeType':'text/plain'}]}
 if method=='resources/read':return {'contents':[{'uri':'nero-test://passage','mimeType':'text/plain','text':'The blue notebook belongs to Ada.'}]}
 if method=='prompts/list':return {'prompts':[{'name':'describe','description':'Authored prompt','arguments':[{'name':'subject','required':True}]}]}
 if method=='prompts/get':return {'description':'Authored prompt','messages':[{'role':'user','content':{'type':'text','text':'Describe '+p.get('arguments',{}).get('subject','this')}}]}
 if method=='ping':return {}
 return {}

def handle(m):
 if 'id' not in m:return None
 r=result(m)
 return None if r is None else {'jsonrpc':'2.0','id':m['id'],'result':r}
if len(sys.argv)>1 and sys.argv[1]=='--http':
 class Handler(BaseHTTPRequestHandler):
  def log_message(self,*a): pass
  def do_GET(self):self.send_error(405)
  def do_DELETE(self):self.send_response(200);self.end_headers()
  def do_POST(self):
   assert self.headers.get('Accept') and 'application/json' in self.headers['Accept']
   m=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
   if m.get('method')!='initialize':assert self.headers.get('MCP-Protocol-Version')=='2025-11-25'
   if m.get('method')!='initialize':assert self.headers.get('Mcp-Session-Id')=='nero-synthetic'
   r=handle(m)
   if r is None:self.send_response(202);self.end_headers();return
   self.send_response(200)
   self.send_header('Mcp-Session-Id','nero-synthetic')
   data=('event: message\ndata: '+json.dumps(r)+'\n\n').encode() if self.path=='/sse' else json.dumps(r).encode()
   self.send_header('Content-Type','text/event-stream' if self.path=='/sse' else 'application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
 print(server.server_address[1],flush=True);server.serve_forever()
else:
 for line in sys.stdin:
  r=handle(json.loads(line))
  if r is not None:print(json.dumps(r),flush=True)
