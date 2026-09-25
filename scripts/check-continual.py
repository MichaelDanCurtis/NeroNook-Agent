#!/usr/bin/env python3
"""Accountless packaged-process watch lifecycle using an explicit synthetic SDK provider."""
import datetime, json, os, selectors, subprocess, sys, time, uuid
from pathlib import Path
app=Path(sys.argv[1]).resolve(); session=str(uuid.uuid4()); run_id=str(uuid.uuid4())
checker=Path(subprocess.check_output(['swift','build','-c','release','--show-bin-path'],text=True).strip())/'PluginCheck'
p=subprocess.Popen([str(app/'Contents/MacOS/ModuleApp'),'--neronook-plugin','--protocol-test'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
sel=selectors.DefaultSelector();sel.register(p.stdout,selectors.EVENT_READ)
buffer=b''; last=-1; state={}; phase='running'; reads=0; snapshots=0
def send(kind,**kw):
    p.stdin.write((json.dumps(dict(type=kind,apiVersion=1,pluginID='cafe.nero.plugin.agent',session=session,sequence=0,**kw))+'\n').encode());p.stdin.flush()
def event(name,**values):send('viewEvent',viewEvent=dict(panelID='awareness',revision='awareness1',name=name,values=values))
def catalog(enabled):
    fields=lambda entries:dict(fields=[dict(name=n,kind=k,required=True) for n,k in entries])
    action=dict(id='read_runs',title='Fixture automation progress',input={'fields':[dict(name='offset',kind='number',required=False,minimum=0,maximum=10000)]},output=fields([('items','string'),('next','number'),('total','number'),('observed_at','string')]),effect='readOnly',cancellable=False,timeoutSeconds=30)
    entries=[dict(address=dict(plugin='local.neronook.workspace',name='read_runs'),action=action)] if enabled else []
    send('bus',bus=dict(operation='catalog',requestID=str(uuid.uuid4()),catalog=entries,complete=True))
def pump(until,timeout=8):
    global buffer,last,state,reads,snapshots
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        if p.poll() is not None:raise AssertionError('Packaged process exited')
        for key,_ in sel.select(.1):
            chunk=os.read(key.fileobj.fileno(),65536)
            if not chunk:raise AssertionError('Unexpected EOF')
            buffer+=chunk
            while b'\n' in buffer:
                line,buffer=buffer.split(b'\n',1);m=json.loads(line)
                assert uuid.UUID(m['session'])==uuid.UUID(session) and m['sequence']>last
                last=m['sequence']
                if m['type']=='snapshot':
                    subprocess.run([str(checker)],input=line+b'\n',check=True,stdout=subprocess.DEVNULL)
                    state=next(x['customView']['state'] for x in m['snapshot']['panels'] if x['id']=='awareness');snapshots+=1
                bus=m.get('bus',{})
                if bus.get('operation')=='invoke':
                    assert bus['address']==dict(plugin='local.neronook.workspace',name='read_runs')
                    reads+=1
                    rows=[dict(id=run_id,kind='workflow',title='Controlled overnight fixture',phase=phase,step='Fixture step')]
                    send('bus',bus=dict(operation='update',requestID=bus['requestID'],update=dict(phase='succeeded',message='Fixture observation',values=dict(items=json.dumps(rows),next=-1,total=1,observed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds').replace('+00:00','Z')))))
        if until():return
    raise AssertionError('Timed out waiting for verified state')
try:
    send('hello',features=['panels-v1','actions-v1','forms-v1','custom-views-v1'])
    pump(lambda: bool(state)); assert state['phase']=='Ready'
    catalog(True);event('nook')
    pump(lambda: len(json.loads(state.get('runs','[]')))==1)
    assert json.loads(state['sources'])[0]['scope']=='Local only'
    event('watch',id=run_id)
    pump(lambda: len(json.loads(state.get('watches','[]')))==1)
    phase='completed';event('refresh')
    pump(lambda: json.loads(state.get('watches','[]'))[0]['terminalSeen'])
    assert sum(a['attention'] for a in json.loads(state['activities']))==1
    old=reads;event('refresh');pump(lambda: reads>old and state['status']=='Context checked locally')
    assert sum(a['attention'] for a in json.loads(state['activities']))==1
    event('pause');pump(lambda: state.get('paused'));old=reads;old_snapshots=snapshots
    event('refresh');pump(lambda: snapshots>old_snapshots);assert reads==old
    catalog(False);event('pause');pump(lambda: not state.get('paused') and not json.loads(state.get('runs','[]')))
    pump(lambda: 'No access is assumed' in state.get('sources',''))
    p.stdin.close();p.wait(timeout=3);assert p.returncode==0
    print('PASS: signed packaged process; SDK-validated views; exact-run lifecycle; completion once; local-only source; pause stops reads; revocation clears context; clean EOF. Synthetic provider only; no account or device action.')
finally:
    sel.close()
    if p.poll() is None:p.kill();p.wait()
