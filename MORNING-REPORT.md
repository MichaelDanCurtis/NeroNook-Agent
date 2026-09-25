# Nero Agent morning report — September 25

**The first continual-Agent milestone is installed as 0.3.0.** Open Nero Agent and choose **Activity**. **Nero can see…** lets you choose a window or folder, preview its context and decide whether a chat may share it. Activity can follow an existing automation run, preserve that goal across restart and show its outcome once. Persistent chat and reviewed actions remain available.

The real review-only workflow completed and its watch survived a restart. A second restart did not duplicate the completion. Folder changes and an exact TextEdit window change appeared in local context. A real ChatGPT request received only the explicitly shared disposable folder inventory and correctly reported that it had no file contents. Test sources were removed; only local-only Nook automation activity remains selected. No physical device was operated.

**Keychain:** Agent rebuilt, updated and reconnected without another password prompt during these checks. Packaging now keeps the installed signing identity, checks update compatibility and refuses temporary-signature fallback. The host and Voice packagers use the same independently bundled helper. The host and Voice signed candidates also passed; their running installations were preserved. This prevents avoidable identity changes, but the exact cause of yesterday's prompts was not reproduced, so it is not a promise that macOS will never ask again. No password, private key or broad credential approval was collected or changed.

**Test evidence:** 15 Agent tests, seven Creator/signing tests, real-runtime isolation checks, final signed-package protocol checks and live installed workflow/context/account checks. [Detailed acceptance and limitations](ACCEPTANCE-0.3.md) distinguish fixtures from live behavior.

**Nothing is waiting on a protected approval.** You will need to choose your own observation sources. Some apps do not expose usable Accessibility text; exact windows require reselection after restarting Agent. Full OS lock/wake and extended energy testing remain acceptance work. This first goal type watches a chosen automation run; broader self-directed goals and visual/OCR observation are later work.

**Recommended next:** try this slice, then add optional local Kokoro replies with a voice audition, offline packaging and immediate Stop. Agent currently stays silent. Keep the wider Voice model/meeting upgrade separate, and keep Laya advisory until its narrower routing tasks pass measured evaluations.

Changes are committed locally in Agent, the host/Creator kit and Voice. Nothing was published or pushed. Existing unrelated host documentation/worktree changes were preserved.
