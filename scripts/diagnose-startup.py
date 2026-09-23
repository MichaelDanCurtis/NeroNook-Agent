import json, os, selectors, subprocess, tempfile, time
from pathlib import Path
binary=Path('/Users/michaelcurtis/.local/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex')
profile=subprocess.check_output(['.build/debug/AgentCheck','--profile'],text=True)
# Read only the fixed source configuration used by our own test client.
src=Path('Sources/ModuleCore/CodexClient.swift').read_text();config=src.split('configuration = """',1)[1].split('"""',1)[0]
with tempfile.TemporaryDirectory(prefix='nero-isolation-',dir=Path.home()/'Library/Caches') as folder:
 root=Path(folder);(root/'workspace').mkdir();(root/'tmp').mkdir();(root/'config.toml').write_text(config)
 import re
 profile=re.sub(r'/Users/[^"\n]+/Library/Caches/nero-agent-check-[^"\n]+',folder,profile)
 env={'HOME':str(Path.home()),'CODEX_HOME':folder,'PATH':'/usr/bin:/bin','TMPDIR':str(root/'tmp')}
 for label,policy in [('allow-required-exec',profile.replace('(deny process-exec)','')),('allow-required-read',profile.replace('(deny file-read-data)',''))]:
  p=subprocess.Popen(['/usr/bin/sandbox-exec','-p',policy,str(binary),'app-server','--strict-config'],cwd=root/'workspace',env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  p.stdin.write((json.dumps({'id':1,'method':'initialize','params':{'clientInfo':{'name':'nero_isolation_probe','version':'0.1.0'}}})+'\n').encode());p.stdin.flush()
  sel=selectors.DefaultSelector();sel.register(p.stdout,selectors.EVENT_READ);sel.register(p.stderr,selectors.EVENT_READ)
  deadline=time.monotonic()+5;chunks=[]
  while time.monotonic()<deadline and p.poll() is None:
   for key,_ in sel.select(.2):
    d=os.read(key.fileobj.fileno(),4096)
    if d:chunks.append(d.decode(errors='replace')[:800])
   if any('"id":1' in c for c in chunks):break
  print(label,p.poll(),chunks[:4]);p.stdin.close()
  try:p.wait(timeout=2)
  except subprocess.TimeoutExpired:p.kill();p.wait()
  sel.close()
