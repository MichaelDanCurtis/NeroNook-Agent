"""Loopback-only UI fixture: real chat renderer, authored data, no providers."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import threading

root = Path(__file__).resolve().parents[1]
chat = root / 'Resources/Views/chat'
style_source = (root / 'Vendor/NookPluginSDK/Sources/NookPluginSDK/PluginConversationWeb.swift').read_text()
style = style_source.split('#"""', 1)[1].split('"""#', 1)[0]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = self.path.split('?', 1)[0]
        if route == '/':
            messages = [
                {'id': 'one', 'role': 'user', 'text': 'Please help improve Nero chat.', 'phase': 'complete'},
                {'id': 'two', 'role': 'assistant', 'text': 'We can improve **Nero** chat. Read [local docs](http://127.0.0.1:%d/docs-test).\n\nLiteral text: <script>not executable</script> and café 🌿.' % self.server.server_port, 'phase': 'complete'},
                {'id': 'three', 'role': 'assistant', 'text': 'Another Nero example, with a reusable local search.', 'phase': 'complete'},
            ]
            state = {'connected': True, 'busy': False, 'conversation': 'authored-one', 'messages': json.dumps(messages), 'history': json.dumps([{'id':'authored-one','title':'Nero design review'}, {'id':'authored-two','title':'Café project 🌿'}, {'id':'authored-three','title':'Weekend plans'}]), 'talk': '{}', 'status': 'Local UI fixture', 'speechProviders': '[]', 'models': '[]', 'toolReviews': '[]'}
            # Escape '<' before embedding the authored fixture as script data.
            payload = json.dumps(state).replace('<', '\\u003c')
            mock = '''<script>window.fixtureListeners=[];window.fixtureCalls=0;
window.fixtureState=PAYLOAD;
window.nero={emit:async(name)=>{document.getElementById('fixtureEvents').textContent='SDK requests: '+(++window.fixtureCalls)+' · '+name;},onState:fn=>{window.fixtureListeners.push(fn);fn(window.fixtureState);}};
document.getElementById('fixtureAppend').onclick=()=>{let m=JSON.parse(window.fixtureState.messages);m.push({id:'four',role:'assistant',text:'Streaming added another Nero reply.',phase:'complete'});window.fixtureState.messages=JSON.stringify(m);window.fixtureListeners.forEach(f=>f(window.fixtureState));};
document.getElementById('fixtureTalk').onclick=()=>{let t=JSON.parse(window.fixtureState.talk);t.active=!t.active;t.ready=true;t.phase=t.active?'listening':'idle';t.level=t.active?0.2:0;window.fixtureState.talk=JSON.stringify(t);window.fixtureListeners.forEach(f=>f(window.fixtureState));};
</script>'''.replace('PAYLOAD', payload)
            banner = '<aside style="padding:6px;font-size:12px" aria-label="Fixture controls">Local UI fixture · authored text only <button id="fixtureAppend">Append fixture reply</button> <button id="fixtureTalk">Toggle fixture Talk</button> <output id="fixtureEvents">SDK requests: 0</output></aside>'
            text = (chat / 'index.html').read_text().replace('</head>', '<style>html{background:#1e1d1b}' + style + '</style></head>')
            text = text.replace('<header class="nc-topbar">', banner + '<header class="nc-topbar">', 1)
            text = text.replace('<script src="chat.js">', mock + '<script src="chat.js">', 1)
            data, content = text.encode(), 'text/html; charset=utf-8'
        elif route in ['/chat.css', '/chat.js', '/chat-find.css', '/chat-find.js', '/chat-history.css', '/chat-history.js']:
            data = (chat / route[1:]).read_bytes()
            content = 'text/css' if route.endswith('.css') else 'application/javascript'
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', content)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path != '/shutdown':
            self.send_error(404)
            return
        self.send_response(200)
        self.end_headers()
        threading.Thread(target=self.server.shutdown, daemon=True).start()


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(f'http://127.0.0.1:{server.server_port}/', flush=True)
try:
    server.serve_forever()
finally:
    server.server_close()
