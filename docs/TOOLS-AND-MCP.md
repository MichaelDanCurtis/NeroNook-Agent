# Agent tools and MCP · 0.5

The owner requested web browsing, Mac awareness/control and MCP access in both
typed and spoken conversation. Preserve the working 0.4 conversation and the
independent Voice provider. The host remains a generic router.

## Architecture and acceptance

The isolated managed Codex runtime remains the reasoning provider. It receives
only tools selected for the current interactive turn. SDK evidence-answer and
workflow-decision requests never inherit personal tools. Native web search uses
the documented per-thread live-search configuration. Third-party integrations
run through a separate MCP client using the official Swift SDK, pinned in
Package.resolved. Neither Codex desktop configuration nor its credentials are
imported. Local MCP servers are trusted programs running as the user; their
execution authority is distinct from a model's reviewed tool call.

MCP supports explicitly configured local stdio and Streamable HTTP servers,
paginated tools/resources, text and image results, cancellation and independent
sign-in. A server is disabled until explicitly connected. Every tool call is
reviewed unless the user explicitly trusts that server's declared read-only
tools; annotations alone never grant access. Missing annotations require review.
Configuration changes retire active calls and reviews. No automatic replay.

Mac tools inspect running apps, selected Accessibility windows and explicit
screenshots. Window element handles are short-lived and revalidated before use.
Press/type/scroll/open operations show exact targets and values before execution.
Secure fields and system identity prompts are excluded. Screen Recording and
Accessibility remain macOS-owned permissions. No background capture is added.

Tools has a primary-card entry and native configuration. Reviews appear in chat
with Allow once, Decline and Stop; changing permissions invalidates pending work.
Full/half duplex and local speech stay unchanged. Activity labels and safe source
links are shown; raw MCP results are not added to saved history.

Local 0.5.1 gives tool, resource and prompt requests individual cancellable
deadlines. Stop does not leave a timer that disconnects a reused connection.
Owned server-process exits clear connected state; HTTP failures surfaced by a
request do too. The pinned SDK does not expose every idle HTTP receive-stream
closure, so reconnect status for that case remains unqualified.

Chat shows one bounded review at a time. Long requests open the complete,
scrollable native Tools review before Allow; an excerpt cannot approve a call.
Mac control snapshots bind the reviewed label, identifier, values and ancestry
and reject a changed target after approval. Long chat text and playback metadata
are separated so a large reply cannot empty the visible conversation. These
changes have local regression coverage; they do not establish every app's AX
behavior or third-party authenticated transport compatibility.

Test cancellation/revocation/late results, cross-turn isolation, bounded data,
MCP pagination and real subprocess/HTTP interoperability. Qualify native web
search and Mac observation independently from fixtures. Test a reviewed reversible
Mac operation in a disposable document. Keep existing meeting/grant/account data.

## Availability boundary

This is not a promise to reproduce every private ChatGPT/Codex product service.
The public app-server exposes managed chat, dynamic tools and web search. Generic
MCP servers supply additional services after separate installation/sign-in.
Codex's private computer-control service, this chat's connectors, image generation,
hosted execution, ChatGPT memory and paid API products are not inherited.
Unsupported or unqualified capabilities must be shown explicitly, not advertised
as available because a setting exists. No silent API billing or audio upload.

References: [app-server](https://learn.chatgpt.com/docs/app-server),
[official MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk),
[MCP transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

Public release remains held until at least host 0.35.0.

## Local delivery and use

Agent **0.5.0** is installed locally on host **0.33.0 / build 46** with Voice
**0.19.0**. Open Agent → **Tools** for web, Mac permission links and MCP setup.
Web is enabled; on this Mac, on-demand Mac access is enabled and the public OpenAI
documentation endpoint is saved. Click Connect to reopen an MCP session after
quit/lock; there is no automatic call or mutation replay. Other services need their
own endpoint/installed program and, when required, their own sign-in. Use one
argument per line for a local executable. A bearer secret is kept in this plugin's
Keychain namespace; a local server receives it as MCP_API_KEY. OAuth tokens stay
in memory. No config/credential import from Codex desktop is performed.

Verified locally: 33 Swift checks; real stdio, HTTP/JSON and HTTP/SSE fixtures;
a real public MCP search/fetch with reviews; native live web search/open; exact
TextEdit observation and approved replacement; pending-review Stop with unchanged
text; a fresh Mac/MCP read after Stop. Existing meetings, other modules and
shared permission scopes/definitions were preserved.

Window screenshots/model image interpretation and third-party account OAuth are
implemented paths that still need live acceptance. Form elicitation, MCP roots,
sampling and legacy split HTTP+SSE are not supported; only URL elicitation is
advertised. Native keyboard/coordinate operations are not provided by these Mac
adapters; additional computer/browser MCPs can be connected independently.
OpenAI's documented account-app catalog/policy integration is a remaining gate;
private desktop services are not assumed to be public APIs. This is not blanket
ChatGPT/Codex parity.

[Detailed evidence and limits](../../NeroNook/reports/agent-tools-2026-10-16/README.md).


## Local flows · optional source candidate

Tools → Local flows → **Allow local flow tools in chat** is off by default. It
explicitly permits sending local flow source, literal values, fixtures and results
to this conversation's configured reasoning provider when Use Nook context is on.
The host separately grants Discover, Inspect, Author, Test, Publish and ordinary
published invocation. Inspect covers this Mac's whole local catalog, not just a
single selected flow. Do not enable this for definitions you cannot share with
that provider. Raw transfer handles remain memory-only; replies/provider retention
follow the selected conversation policy.

The active interactive turn receives nook_flow_catalog, nook_flow_call and
nook_flow_result. SDK ask/decision/evidence requests receive none. Source transfers
are checked, bounded and paged without truncation. Inspect existing source/schema
before patching. Draft save and immutable publication each retain complete native
review; publication never executes the flow. Newly published invocation normally
uses the next turn's ordinary proposal route. Fixtures simulate supplied results
and cannot dispatch live providers. Stop/timeout/authority changes retire original
requests; unknown mutation outcomes are not automatically replayed.

93 local Agent tests, final14client repeat and a separate two-test composition
qualify source and scripted runtime routing. No actual hosted-model authoring,
new installed app or grant was tested. Agent's whole-turn180-second bound can
expire during long transfer/reviews; individual service deadlines are not promises
of a longer Agent turn. Pages expire on catalog refresh. Native finiteDouble
source is not portable Flow/n8n compatibility. See the linked host evidence.
