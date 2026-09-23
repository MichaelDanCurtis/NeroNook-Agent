# Nero Agent — independent preview

A separate native module using the documented Codex app-server with managed ChatGPT sign-in. Your existing account is used through its own sign-in flow; the Codex desktop's tokens, conversations, configuration and tools are never copied. No API key or silent separately billed API fallback is used. Voice remains outside this batch.

The 16:9 module has a Conversation form, streamed reply sections, Stop, a Context preview and a gear button for the module's account/runtime settings. It receives only action/state capabilities granted through the shared SDK. Receiving context locally does not send it to ChatGPT: each message explicitly chooses None or one fresh state attachment. Permitted action definitions are supplied so the assistant can propose a valid action. Proposals are revalidated against the current catalog before invocation, and changes go through NeroNook's immutable action review.

Two generic actions are registered: Ask ChatGPT (bounded reply) and Evaluate a condition with ChatGPT (boolean decision plus bounded reply). This lets a workflow use a decision in a typed condition without embedding OpenAI logic in the host. An AI decision does not execute a proposed action. Output replies sent over the action bus are limited to 500 characters; the module conversation can display a longer reply.

## Runtime and isolation

This preview accepts native Codex **0.142.5** only; a different runtime requires renewed compatibility/containment checks. It uses the locally installed native executable, not a copied binary or the Node launcher. Settings allows choosing that executable. Redistribution/automatic runtime installation is not implemented.

Each connection rewrites a minimal configuration under this plugin's own application-support directory. Shell, unified execution, hooks, connectors, plugins, browser/computer tools, memories and other inherited integrations are disabled. Project instructions and persistent conversation history are disabled. Runtime-managed credentials remain within its mode-700 directory; plugin code does not extract them.

An outer macOS sandbox denies user-file content outside the plugin runtime, writes outside its directory, and arbitrary executable launches. It allows the native executable, directory metadata, macOS support locations and networking needed for account/model service communication. This is a scoped preview boundary, not a claim of a fully sandboxed third-party native plugin or constrained network destinations. The installed module remains trusted native software. Runtime configuration is checked at startup. All server-initiated tool, credential and permission requests receive a refusal; the client exposes no approval callback.

Threads are ephemeral and read-only. Generated JSON is validated as data; it cannot authorize SDK grants, invoke a missing action or alter reviewed values. Context expiry and catalog changes are checked before sending a request or applying a proposal. Stop interrupts a known turn; if startup has not provided a turn identity, the owned runtime is stopped and must reconnect. Cancelling sign-in invalidates late login results.

## Build and checks

- `swift test`: response/proposal validation and partial streamed JSON decoding.
- `swift run AgentCheck`: accountless real-runtime handshake/effective configuration, outside-file read/write canaries, blocked arbitrary execution, no inherited desktop login and five forged server requests denied through the actual client.
- `python3 Tools/nook.py pack . --identity <identity>`: independent signed local package using the vendored SDK.
- `python3 scripts/check-process.py /absolute/app/path`: actual signed-process handshake, two panels, disabled unsigned-in prompt, message identity/sequence and EOF shutdown. It does not start Codex or load a login.

Nero Agent **0.1.2** is installed and Running. Managed browser sign-in completed; a real reply, partial streaming and Stop were verified. The installed update restores its own existing login through the runtime at startup, without a browser or credential extraction. Invalid/missing login requires explicit sign-in in Settings; a failed connection stops the child. Sign-out is disabled during connection setup. Protocol-test mode skips restoration.

Actual workflow acceptance: Ask ChatGPT returned a reply through the SDK; the host bound it into Creator Demo's message, showed the exact values for review and applied them only after confirmation. Decline stopped an earlier attempt. After the 0.1.2 update this worked without manual reconnect. A direct model-generated proposal was reviewed in the Nook and its count 9 / “Agent proposal verified” values were read back from the demo. No physical device was controlled. The two unit tests and signed-process handshake/EOF check pass for this build.

Real boolean decision branching, expired-login recovery, live selected-context expiry and broader adversarial model testing remain acceptance gates. Existing accountless configuration/canary/forged-request checks are separate evidence. Public distribution, licensing and notarization remain separate work.

Official protocol reference: https://learn.chatgpt.com/docs/app-server
