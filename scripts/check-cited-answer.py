#!/usr/bin/env python3
"""Explicit account check with authored synthetic text; no credentials are read.

Run manually against a signed app. Uses its existing managed ChatGPT account,
never API billing. Saves only synthetic questions, validated answers and timing.
"""
import hashlib, json, os, selectors, subprocess, sys, time, uuid
from pathlib import Path

app, receipt = Path(sys.argv[1]), Path(sys.argv[2])
session = str(uuid.uuid4()); plugin = 'cafe.nero.plugin.agent'
p = subprocess.Popen([str(app/'Contents/MacOS/ModuleApp'), '--neronook-plugin'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
sel = selectors.DefaultSelector(); sel.register(p.stdout, selectors.EVENT_READ)
buffer = b''; sequence = 0; collected = []
def send(kind, **values):
    global sequence
    sequence += 1
    p.stdin.write((json.dumps(dict(type=kind, apiVersion=1, pluginID=plugin, session=session, sequence=sequence, **values))+'\n').encode()); p.stdin.flush()
def messages(seconds):
    global buffer
    end = time.monotonic()+seconds
    while time.monotonic()<end:
        if p.poll() is not None: raise RuntimeError('Agent exited')
        for key,_ in sel.select(.2):
            data=os.read(key.fileobj.fileno(),65536)
            if not data: raise RuntimeError('Unexpected EOF')
            buffer+=data
            if len(buffer)>262144: raise RuntimeError('Oversized message')
            while b'\n' in buffer:
                line, buffer=buffer.split(b'\n',1); yield json.loads(line)
def wait_connected():
    for m in messages(25):
        if m['type']=='snapshot' and m['snapshot']['panels'][0]['customView']['state'].get('connected'): return
    raise RuntimeError('Existing managed account did not become ready; no browser login was requested')
sources = [dict(id='s1', label='00:00:04 · Microphone', text='We agreed to launch the website on Friday.'),
           dict(id='s2', label='00:00:12 · Call audio', text='Alex will send the copy draft on Thursday.'),
           dict(id='s3', label='00:00:20 · Microphone', text='Jordan will review the draft before the Friday launch.'),
           dict(id='s4', label='00:00:28 · Call audio', text='We have not decided the colors yet.')]
def execute(question):
    request=str(uuid.uuid4()).upper(); digest=hashlib.sha256(json.dumps(sources,sort_keys=True).encode()).hexdigest()
    values=dict(question=question,snapshot=digest,sources_0=json.dumps(sources,ensure_ascii=False,separators=(',',':')))
    send('bus',bus=dict(operation='execute',requestID=request,address=dict(plugin=plugin,name='answer_evidence'),values=values))
    return request, digest
try:
    send('hello', features=['actions-v1','custom-views-v1','forms-v1','panels-v1'])
    wait_connected()
    for question, expected in [('When is launch, and who prepares and reviews the copy?', 'answered'), ('What budget amount did we approve?', 'insufficient')]:
        start=time.monotonic(); request,digest=execute(question)
        for m in messages(180):
            b=m.get('bus',{}); u=b.get('update',{})
            if b.get('requestID')!=request or u.get('phase') not in ['succeeded','failed','cancelled']: continue
            assert u['phase']=='succeeded', 'Provider failed; raw errors are deliberately not logged'
            answer=json.loads(u['values']['answer']); assert answer['snapshot']==digest and answer['disposition']==expected
            assert len(json.dumps(answer,ensure_ascii=False,separators=(',',':')).encode())<=2048
            for statement in answer['statements']:
                assert statement['citations'] and set(statement['citations'])<=set(s['id'] for s in sources)
            collected.append(dict(question=question,answer=answer,seconds=round(time.monotonic()-start,3))); break
        else: raise RuntimeError('Answer timed out')
    request,_=execute('Explain the launch plan briefly.')
    send('bus',bus=dict(operation='cancel',requestID=request))
    for m in messages(10):
        b=m.get('bus',{}); u=b.get('update',{})
        if b.get('requestID')==request and u.get('phase')=='cancelled': break
    else: raise RuntimeError('Cancellation was not acknowledged')
    receipt.parent.mkdir(parents=True,exist_ok=True)
    receipt.write_text(json.dumps(dict(source='authored synthetic meeting; transcript text only', answers=collected, cancellation='acknowledged', account='existing managed account; credentials opaque', no_tools=True),indent=2)+'\n')
    print('PASS: real cited answer, insufficient evidence, cancellation; synthetic text only')
finally:
    sel.close()
    if p.poll() is None:
        p.stdin.close();p.stdin=None
        try:p.communicate(timeout=5)
        except subprocess.TimeoutExpired:p.kill();p.wait()
