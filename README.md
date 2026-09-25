# Nero Agent — independent preview

**0.3.0 adds continual activity:** exact automation-run goals/watches, a durable outcome timeline and **Nero can see** controls for selected windows, immediate workspace inventories and permitted Nook automation activity. Open Activity to watch a run or manage sources. See [0.3.0 acceptance](ACCEPTANCE-0.3.md) and the [morning report](MORNING-REPORT.md).

A separate native module using the documented Codex app-server with managed ChatGPT sign-in. Your existing account is used through its own sign-in flow; the Codex desktop's tokens, conversations, configuration and tools are never copied. No API key or silent separately billed API fallback is used. Voice remains outside this batch.

The 16:9 module and larger window now share a proper conversation view: streamed Markdown replies, a scrolling timeline, new chat, history drawer, edit-and-resend, retry, Copy and Stop. Keep conversations until quit (default), or opt into 7/30-day local history in Settings. Up to 20 chats and 40 messages per chat are retained, with bounded context supplied to each new turn. SDK workflow asks and decisions are isolated from personal chat history.

Enable **Use Nook context** for a message to let the model discover and read currently permitted Nook tools. This may send returned workspace/module data to ChatGPT. With it off, tool calls are unavailable; conversation text still carries forward. Context reads and their outcomes appear in the conversation. The generic host Workspace provider can expose active modules per display, installed-module inventory, workflow names and current run progress, each behind its own SDK grant. Device content needs separate provider grants. Fresh state is checked at read time; changed/revoked access discards pending results. Proposed changes remain separate and require the Nook's existing action review.

Two generic actions are registered: Ask ChatGPT (bounded reply) and Evaluate a condition with ChatGPT (boolean decision plus bounded reply). This lets a workflow use a decision in a typed condition without embedding OpenAI logic in the host. An AI decision does not execute a proposed action. Output replies sent over the action bus are limited to 500 characters; the module conversation can display a longer reply.

## Runtime and isolation

This preview accepts native Codex **0.142.5** only; a different runtime requires renewed compatibility/containment checks. It uses the locally installed native executable, not a copied binary or the Node launcher. Settings allows choosing that executable. Redistribution/automatic runtime installation is not implemented.

Each connection rewrites a minimal configuration under this plugin's own application-support directory. Shell, unified execution, hooks, connectors, plugins, browser/computer tools, memories and other inherited integrations are disabled. Project instructions and runtime-persisted conversation history are disabled. Optional local conversation storage belongs to this plugin, outside the model runtime directory. Runtime-managed credentials remain within its mode-700 directory; plugin code does not extract them.

An outer macOS sandbox denies user-file content outside the plugin runtime, writes outside its directory, and arbitrary executable launches. It allows the native executable, directory metadata, macOS support locations and networking needed for account/model service communication. This is a scoped preview boundary, not a claim of a fully sandboxed third-party native plugin or constrained network destinations. The installed module remains trusted native software. Runtime configuration is checked at startup. Four registered dynamic tools are handled for the current context-enabled interactive turn. They provide permission-filtered discovery, fresh state, read-only action calls and selected local context through `nero_context`. All other server-initiated execution, tool, credential and permission requests receive a refusal; the client exposes no approval callback. The documented dynamic-tool route is experimental and checked against the pinned runtime schema.

Threads are ephemeral and read-only. Generated JSON is validated as data; it cannot authorize SDK grants, invoke a missing action or alter reviewed values. Context expiry and catalog changes are checked before sending a request or applying a proposal. Stop interrupts a known turn; if startup has not provided a turn identity, the owned runtime is stopped and must reconnect. Cancelling sign-in invalidates late login results.

## Build and checks

- `swift test`: response/proposal validation, partial streamed JSON decoding, bounded conversation persistence/recovery and tool-scope enforcement.
- `swift run AgentCheck`: accountless real-runtime handshake/effective configuration, outside-file read/write canaries, blocked arbitrary execution, no inherited desktop login and five forged server requests denied through the actual client, plus registered-tool routing and stale/unknown call rejection.
- `python3 Tools/nook.py pack . --identity <identity>`: independent signed local package using the vendored SDK.
- `python3 scripts/check-process.py /absolute/app/path`: actual signed-process handshake, custom chat panel, disabled unsigned-in prompt, message identity/sequence and EOF shutdown. It does not start Codex or load a login.

Nero Agent **0.2.0** established the prior baseline: live chat continuity, Stop, optional saved-history recovery, registered capability discovery and same-value reviewed demo execution passed. The four workspace read grants are enabled and live paginated workspace/module/workflow/run reads passed on September 24. The following paragraph records the earlier **0.1.2** account baseline. See [0.2.0 acceptance](ACCEPTANCE-0.2.md) for the current chat/tools build. Managed browser sign-in completed; a real reply, partial streaming and Stop were verified. The installed update restores its own existing login through the runtime at startup, without a browser or credential extraction. Invalid/missing login requires explicit sign-in in Settings; a failed connection stops the child. Sign-out is disabled during connection setup. Protocol-test mode skips restoration.

Actual workflow acceptance: Ask ChatGPT returned a reply through the SDK; the host bound it into Creator Demo's message, showed the exact values for review and applied them only after confirmation. Decline stopped an earlier attempt. After the 0.1.2 update this worked without manual reconnect. A direct model-generated proposal was reviewed in the Nook and its count 9 / “Agent proposal verified” values were read back from the demo. No physical device was controlled. The earlier baseline passed its two unit tests and signed-process handshake/EOF check; 0.2.0 now has five core tests plus expanded tool fixtures.

Real boolean decision branching, expired-login recovery, live selected-context expiry and broader adversarial model testing remain acceptance gates. Existing accountless configuration/canary/forged-request checks are separate evidence. Public distribution, licensing and notarization remain separate work.

Official protocol reference: https://learn.chatgpt.com/docs/app-server

## Continual context and watch controls

Selected context starts local-only. Both **Available to ChatGPT** on the source and **Use Nook context** on the message are required to share it. Nook automation reads cannot bypass a local-only source through the older read-action tool. Other existing Nook grants retain their explicit per-message control. Observation is separate from action permission; source content is data, never authority.

Context is transient, bounded and expires after 30 seconds. Failed reads remove cached context; source changes, Pause and lock invalidate pending results. Workspace observations contain immediate filenames/times, not file contents. Windows use Accessibility text from the exact selected element, exclude secure fields and require reselection after restart. OCR/screenshots and automatic browser-domain selection are not implemented.

Watches persist exact run identities and report terminal outcomes once. The first goal type is “report this automation run's final outcome”; arbitrary natural-language autonomous goals remain future work. Quiet mode retains outcomes without an attention badge. Unchanged observations do not call ChatGPT. Laya remains advisory in its independent evaluation project and does not authorize commands. Optional Kokoro replies are deferred; this Agent build makes no audio or microphone request.

`python3 scripts/check-continual.py /absolute/app/path` checks the packaged-process watch lifecycle, SDK view validation, local-only scope, pause, revocation and deduplication using a synthetic provider. `swift test` includes the real selected-folder inventory adapter and durable watch boundaries.

Installable packaging inherits the current installed signing certificate when `--identity` is omitted, or uses `NERONOOK_SIGNING_IDENTITY`. Missing/ad hoc identities are rejected. The candidate must satisfy the previous package's designated requirement. No Keychain credential values or private keys are read by packaging. Protocol-only test packages have their own `.protocol-test` bundle identity.
