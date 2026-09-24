# Agent chat and live tools — 0.2.0

Independent plugin upgrade plus generic host 0.22.0 Workspace service. No plugin-specific host branch. The plugin vendors the public custom-view SDK; its 16:9 Nook chat and larger native window use the same packaged local view.

Implemented: conversation timeline, incremental replies, Markdown text/code/lists, Stop, edit-and-resend, retry, copy, new chat, conversation selector, optional 7/30-day local history (default until quit), bounded history recovery, visible tool activity and proposal review. Editing appends a new message; it does not rewrite past turns. Conversation content is carried into subsequent requests in a bounded 24 KB window. Runtime threads are ephemeral and isolated per request; SDK workflow asks/decisions receive none of the personal conversation.

Registered tools: permitted capability discovery, fresh permitted state reads, and explicitly permitted read-only action calls. A per-message Nook context control enables tools. Runtime tool calls must match the active thread/turn, permitted tool name and strict arguments; replay and per-turn call limits apply. SDK permission/definition changes invalidate results and proposals; cancellation discards late results. Writes remain model proposals followed by the host's immutable review. Unknown tools, execution, permission and credential requests remain refused.

Build and protocol verification:
- Five core tests pass: proposal/schema checks, incremental JSON decoding, history save/load/corruption/limits/interruption, and tool identity/scope/write rejection.
- Real pinned Codex 0.142.5 accepts the dynamic tool definitions. Accountless sandbox file/exec canaries pass; no desktop login inherited. Protocol fixture allows one registered call, refuses stale/unknown calls and retains denial of five forged runtime tool/credential/permission requests.
- Independent signed release, current and legacy host handshakes, SDK validation, three snapshots and clean EOF pass.
- Host workspace pagination/Unicode/schema/grant/revoke tests and existing workspace/custom-view regressions pass (9 tests).

Installed acceptance on September 23, 2026:
- Signed final package `cafe.nero.plugin.agent-0.2.0-31b227396e97.app` installed through the normal host review; 0.2.0 is Running. Final signed-process check passes. Existing plugin-owned ChatGPT login restores without credential extraction.
- Real two-turn conversation remembered the harmless word “marigold.” Both turns remained visible. New chat, history selection and reopening the earlier conversation worked.
- Stop preserved the partial reply and marked it stopped; no late append was observed. Opt-in seven-day history recovered the conversation and stopped reply across a package restart. Retention was returned to Until quit afterward. Previously saved test history remains untouched, as explained in Settings.
- Native window and Odyssey Ark's 16:9 Nook chat were visually inspected. Single-panel selector and duplicate generic action buttons are absent. Final fresh chat is Ready with Use Nook context unchecked.
- With zero SDK grants, the actual model called `nook_capabilities`; visible activity read “Checking available Nook tools” and the reply correctly reported zero permitted capabilities. This tests the live dynamic-tool route without reading workspace or device data.
- A real model proposal set Creator Demo to its already-current count 0 and message “Your first module.” The host displayed exact values for review; confirmation completed with “Demo updated.” No physical device was controlled. This was a same-value demo check, not a general device-write acceptance.
- The update's invalidated pre-existing grants were restored with unchanged scope: Agent to Creator Demo edit, Voice to Agent ask, and Automations to Agent ask/decide. The Voice working draft was restored locally without sending it.

September 24 follow-up: after the owner said Proceed to the pending permission request, all four Workspace grants were enabled. A real ChatGPT turn visibly invoked all four read actions and followed pagination. It reported the actual two display selections, 14 installed modules, two unarmed workflows and no active run. This live workspace-read gate is accepted. Files, mail, desktop UI and device content are outside these new host services. A future Mac Workspace provider, broad adversarial testing, expired-login recovery, full multi-display/accessibility coverage and public distribution remain separate work.

The tool API is documented as experimental. Sources: https://learn.chatgpt.com/docs/app-server and the installed 0.142.5 experimental JSON schema. Compatibility remains pinned; no runtime/model/account migration was performed.
