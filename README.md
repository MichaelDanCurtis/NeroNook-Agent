**October 20 · local 0.5.19:** avatar tickle and playful Zoom use the current local speech selection through the shared SDK, with measured mouths, exact cancellation and a silent Wave/Twirl menu. Existing voice settings and action scopes are retained. [Installed checks and limits](../NeroNook/reports/avatar-playful-reactions-2026-10-20/README.md). Local only.

**October 19 · local 0.5.15 installed:** shared native/web avatar articulation adds larger pointer-following turns, tilt, lean and a floating offset. Eyes and speech remain independent. [Qualification and limits](../NeroNook/reports/avatar-articulation-2026-10-19/README.md). Local only.

**October 19 · local candidate 0.5.14:** shared avatar eyes/head follow the same-display pointer independently of speech. Built and tested; installation pending the owner's open-chat decision. [Evidence](../NeroNook/reports/avatar-pointer-2026-10-19/README.md).

**October 19 · local 0.5.13:** corrected primary conversation/dictation layout, direct shared microphone selection and quieter secondary controls. Installed locally; visual acceptance and full Wispr parity remain separate. [Evidence and limits](../NeroNook/reports/conversation-layout-2026-10-19/README.md).

**October 19 · local 0.5.12:** larger Talk avatar and playback-aware dotted meter. Shared SDK makes quiet output visible and closes immediately on Stop. The owner confirms installed Nero and Ember speech animation, spoken interruption and Stop work. Host evidence: `../NeroNook/reports/avatar-talk-2026-10-19/README.md`. Local only.

**October 19 · local 0.5.10:** approved elemental avatars and twenty paired palettes through the generic shared SDK. Conversation mouth animation follows Voice-owned speech playback, separately from microphone input; original-turn and Stop boundaries clear it. Local installation only; no publication or hosted conversation qualification. See the host’s `reports/elemental-avatars-2026-10-19/README.md`.

**October 19 · local 0.5.9:** Nearly Nothing refinement: softer shared glass and controls, compact fit review and paired Light/Dark. Voice surfaces use shared dotted input feedback. Local package installed; visual checks do not imply fresh audio, device or network acceptance. [Evidence and limits](../NeroNook/reports/nearly-nothing-refinement-2026-10-18/README.md). No public update.

**October 18 · local 0.5.8 installed:** optional Nero assistant identity, provider-authored review attention and shared reference-derived presence/glass; owned accounts, chat and speech remain independent. See [local qualification](../NeroNook/reports/presence-workspace-2026-10-18/README.md). No public update.

**October 18 · local 0.5.7 installed:** shared glass chrome, layered floating presence and leading-edge entrance; compact welcome visibility preserved. Nook/standalone rendering and prior permission scopes checked without Talk or a hosted question. [Evidence and limits](../NeroNook/reports/glass-motion-2026-10-18/README.md).

**October 17–18 · local 0.5.6 installed:** Compact welcome text no longer wraps into the hidden halo column. Installed native layouts on MacBook and Ark pass; stored data is unchanged and existing shared scopes were renewed through normal review. No new Talk or hosted question. [Evidence and limits](reports/compact-welcome-2026-10-17/README.md). No public update.

**October 17 · offline cloned Talk qualification:** exact `AgentTalk`, SDK and
Voice sources were exercised with a scripted local reasoning adapter. The owner
confirms physical interruption and a fresh cloned reply. Native Stop/restart,
late-response rejection and worker cleanup pass; the installed app and current
chat were not restarted. This is not a hosted-account cancellation test.
[Evidence](../NeroNook-Voice/reports/clone-talk-lifecycle-2026-10-17/README.md).

**October 17 · local 0.5.5 installed:** explicit Talk can request the exact shared
conversation action through the host-owned **Allow & Continue** popup on host
0.33.2. No Settings detour, automatic microphone start or broad action grant.
Stop/decline/expiry leave it stopped. Legacy hosts keep the previous fallback.
56 Agent tests, the Talk frontend fixture and signed accountless process checks
pass. Installed with host 0.33.2: real Talk popup and Not Now/retry verified;
the owner confirms live words and the Michael cloned reply both work. Sustained
Talk, acoustic barge-in and cloned-session Stop/restart remain separate checks.
[SDK contract](../NeroNook/SDK/ACTION-ACCESS.md) ·
[local verification](../NeroNook/reports/action-access-2026-10-17/README.md).

**October 16 · local 0.5.4:** primary Agent model picker backed by the connected
account's catalog. Choices persist for interactive chat/Talk; switching waits for
the current reply. Missing models fail visibly, with no provider/billing fallback.
Catalog preparation sends no prompt. Eight live choices and actual native replies
from GPT-6-Luna and GPT-6.1-Sol verified; Account default restored. 56 tests pass.
[Evidence](../NeroNook/reports/model-readiness-2026-10-16/README.md).

**October 16 · local 0.5.3:** Quicker replies / Model default is on the primary
Talk card. Only spoken turns request low reasoning effort, and only when the
same selected model explicitly advertises it; typed/evidence replies keep their
policy. Six authored same-model requests yielded median first text 2.28 s versus
3.61 s. Concise spoken instructions are enabled with quick replies. 53 tests
pass; physical conversation and broad quality remain separate acceptance.
[Evidence and reversible controls](../NeroNook/reports/conversation-speed-2026-10-16/index.html).

**October 16 · local 0.5.2:** a closed streamed JSON reply string is speakable
before remaining response fields and runtime completion. Decimal/abbreviation
boundaries and rewrite rejection remain; a drained spoken preview cannot reopen
listening before the model actually completes. 52 tests pass. Three text-only
managed-account comparisons preserve the same stream for old/new queues;
physical Talk and acoustic end-to-end timing remain pending.
[Local measurements](../NeroNook/reports/speech-latency-2026-10-16/index.html).

**October 16 · local 0.5.1 reliability build:** tracked MCP cancellation and
per-request deadlines, connection-loss reporting, exact Mac control snapshots,
complete native reviews and byte-bounded chat presentation. Streamed speech
keeps decimal and abbreviation tokens intact. 50 tests and the actual app-state
fixture pass; the rendered complete-review/Decline/Stop fixture also passes.
[Source and local evidence](../NeroNook/reports/reliability-2026-10-16/agent/verification.json).
Actual third-party AX behavior, idle HTTP closure detection and complete latency
remain qualified separately. Public distribution stays held.

**October 16 · Agent 0.5.0:** primary **Tools** controls for live web search,
on-demand reviewed Mac tools and independent MCP connections. Verified native
web lookup, reviewed public MCP search/fetch, exact TextEdit read/change and
Stop/recovery. Voice remains shared with independent Nero Voice.
[Usage, availability and remaining gates](docs/TOOLS-AND-MCP.md) ·
[local evidence](../NeroNook/reports/agent-tools-2026-10-16/README.md).
No public release or blanket ChatGPT/Codex parity claim.

**October 15 · conversational speech:** explicit shared Talk sessions and a primary Full/Half duplex toggle are implemented through the optional generic SDK. Audio and selected ASR/TTS stay in the independent Voice plugin; Agent keeps text and its existing account. See [usage and qualification](../NeroNook/docs/AGENT-TALK.md).

**October 13 · 0.3.4:** adds the optional generic answer_evidence_chat action.
The caller supplies a bounded visible recent conversation plus current evidence;
history resolves follow-up references and never establishes facts. Each answer
cites current source IDs. Every request uses a fresh ephemeral, tool-free thread;
personal Agent conversations are neither inherited nor overwritten. Voice owns
meeting retrieval and persistent chat. Old answer_evidence remains available.
Twenty-five tests, signed accountless registration/EOF and three synthetic real
managed-ChatGPT answers pass. [SDK](../NeroNook/SDK/EVIDENCE-ANSWERS.md)
· [delivery](../NeroNook-Voice/reports/meeting-chat-2026-10-13/README.md).

**October 13 · Agent 0.3.3:** optional generic `answer_evidence` SDK action
answers explicitly supplied text with validated source IDs. This isolated request
has no prior chat, context tools or action proposal. It uses the existing managed
ChatGPT account; early cancellation restores that account without opening a login
browser. 24 tests and real synthetic answer/insufficient/cancel checks pass.
[Shared contract](../NeroNook/SDK/EVIDENCE-ANSWERS.md) · [evidence](../NeroNook-Voice/reports/ask-meeting-2026-10-13/README.md).

**October 13 · Agent 0.3.2 installed:** shared Read aloud / Stop is verified
using a completed real reply through the installed Voice 0.10.2 provider. Fresh
managed browser sign-in completed. Codex 0.162.0 passed restricted configuration,
file/exec containment and forged-request checks, and its offered gpt-6.1-sol
completed the synthetic reply. Old 0.142.5 models failed with this account even
after sign-in; the redacted negative receipts are retained. Both exact runtime
versions remain recognized; unknown versions fail closed. Twenty-three tests
pass. Package, receipt lifecycle, EOF and installed signature checks pass.
[Delivery evidence](../NeroNook-Voice/reports/shared-speech-notetaker-2026-10-13/README.md).

Historical 0.3.1 delivery below precedes the account/runtime correction.

**October 13 · Agent 0.3.1 installed:** explicit Read aloud on completed
assistant messages and Stop use an optional shared SDK speech provider. Voice
owns synthesis/voice preferences; this plugin has no microphone or synthesizer.
Speech entries are excluded from model tools, so playback requires a user button.
22 tests and release packaged receipt/history lifecycle checks pass. The earlier
source-only follow-ups below are now included in 0.3.1; their original receipts
remain historical. The system Codex runtime advanced to 0.162.0; this Mac now
selects a separate official 0.142.5 runtime, avoiding global CLI changes. A fresh
managed-account sign-in is required after the old login failed a real reply.
[Shared SDK](../NeroNook/SDK/SPEECH.md) · [delivery evidence](../NeroNook-Voice/reports/shared-speech-notetaker-2026-10-13/README.md).

# Nero Agent — independent preview

**Source-only decision-evidence follow-up (not installed):** the permitted
state-channel path now retains a transient publish ID, exact catalog-entry
digest, local catalog generation, typed values, observation time and expiry.
It rejects schema-invalid updates and prevents a replay of the same publish ID
from renewing freshness. Catalog changes and revoked subscriptions clear the
receipt. The ChatGPT tool still returns only values, and no compact memory
model, durable archive or automatic action uses this metadata yet. Debug and
release `swift build` plus four receipt tests pass; accountless synthetic
process checks on both binaries confirm
subscribe, update, replay expiry, replacement and revocation. The full test
suite has one pre-existing storage test blocked by macOS file protection on a
temporary file in this environment; the other 21 tests pass. The installed
Nero Agent remains unchanged.

An additional local-only envelope method and synthetic fixture now let the
independent decision testbed check this receipt contract across Swift and
Python. The bridge needs a separate
current catalog entry and grant, and it does not connect this source to an
installed decision runtime or send receipt metadata to ChatGPT.

**Recent typed-state history (source only):** the module process now retains
up to 64 recent field versions per state channel for at most five minutes in
memory. It can identify a continuous same-field replacement, but clears the
chain after expiry, omission or any completed host catalog refresh, including
an identical catalog returned after a possible provider restart. Three
history-specific tests pass; both builds and synthetic debug/release process
checks pass. This is not a durable memory feature or an installed update.

**0.3.0 adds continual activity:** exact automation-run goals/watches, a durable outcome timeline and **Nero can see** controls for selected windows, immediate workspace inventories and permitted Nook automation activity. Open Activity to watch a run or manage sources. See [0.3.0 acceptance](ACCEPTANCE-0.3.md) and the [morning report](MORNING-REPORT.md).

A separate native module using the documented Codex app-server with managed ChatGPT sign-in. Your existing account is used through its own sign-in flow; the Codex desktop's tokens, conversations, configuration and tools are never copied. No API key or silent separately billed API fallback is used. Voice remains outside this batch.

The 16:9 module and larger window now share a proper conversation view: streamed Markdown replies, a scrolling timeline, new chat, history drawer, edit-and-resend, retry, Copy and Stop. Keep conversations until quit (default), or opt into 7/30-day local history in Settings. Up to 20 chats and 40 messages per chat are retained, with bounded context supplied to each new turn. SDK workflow asks and decisions are isolated from personal chat history.

Enable **Use Nook context** for a message to let the model discover and read currently permitted Nook tools. This may send returned workspace/module data to ChatGPT. With it off, tool calls are unavailable; conversation text still carries forward. Context reads and their outcomes appear in the conversation. The generic host Workspace provider can expose active modules per display, installed-module inventory, workflow names and current run progress, each behind its own SDK grant. Device content needs separate provider grants. Fresh state is checked at read time; changed/revoked access discards pending results. Proposed changes remain separate and require the Nook's existing action review.

Four generic actions are registered: Ask ChatGPT, Evaluate a condition with
ChatGPT, Answer supplied evidence, and Answer supplied evidence with recent
conversation. The two cited-answer adapters have no tools or proposals. This lets a workflow use a decision in a typed condition without embedding OpenAI logic in the host. An AI decision does not execute a proposed action. Output replies sent over the action bus are limited to 500 characters; the module conversation can display a longer reply.

## Runtime and isolation

This preview accepts native Codex **0.142.5** and **0.162.0** only; a different runtime requires renewed compatibility/containment checks. Current account acceptance uses 0.162.0; 0.142.5's catalog was rejected on this Mac. It uses the locally installed native executable, not a copied binary or the Node launcher. Settings allows choosing that executable. Redistribution/automatic runtime installation is not implemented.

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
