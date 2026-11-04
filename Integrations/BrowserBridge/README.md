# Local browser integration

Local cycle168, November 3,2026. These are independent Agent MCP adapters; no
Nook host or shared SDK implementation is embedded here. The signed-in lane
wraps Browser MCP2.4.0/Chrome extension2.2.1. The unattended lane wraps the
agent-browser0.41.2 native Rust executable and an independent headless session.

Current local files live under
`~/Library/Application Support/NeroNook-Plugins/cafe.nero.plugin.agent/browser-tools-168/`.
The two normal Nero Tools connections point to `neronook-signed-browser` and
`neronook-unattended-browser`. Both expose ten typed operations; all calls remain
reviewed. Chat’s Use my browser and Unattended browser controls provide routing
guidance, not a security boundary.

The npm lockfile pins packages; installation used `--ignore-scripts`, with no
global npm changes or startup `npx` downloads. The native darwin-arm64 binary is
used directly; its JavaScript launcher's Node24 requirement is not claimed
satisfied by this Mac's Node22 runtime. Node22 runs Browser MCP and this adapter.
`upstream-signed` and `upstream-unattended` are fixed locally generated launchers.
Do not overwrite them with a wrapper that calls itself.

## Why the adapter exists

Raw Browser MCP2.4.0 continued a `wait → fill → submit` batch after the MCP caller
cancelled. The independent local fixture recorded the late submission. Therefore
Nero exposes one typed action per request, no raw batches, evaluation, upload,
filesystem output, arbitrary profile discovery or session/namespace overrides.
The unattended connection has a fixed isolated session and namespace. The signed
connection uses the currently paired Browser MCP profile; multiple-profile
identity binding is not qualified by this implementation.

`SingleActionGate` holds the real upstream promise after caller cancellation.
Other calls are refused while that promise is active. A private, synced pending
record reserves the lane across adapter instances and ordinary process restarts.
Transport exceptions retain that record; the server also recognizes the inspected
Browser MCP wrapper's connection-loss response and unstructured agent-browser
transport errors. Never delete a retained record as routine reconnect cleanup.
It requires operator reconciliation against the original operation and owner.
Do not treat this limited normalization as a complete third-party outcome taxonomy.

A completed upstream request, including a normal command error, is not proof
that external effects were undone. No retry or mutation replay is performed.
Stop blocks new actions; already emitted input may still take effect. This is
not a sandbox against hostile software running as the same macOS user.

## Local checks

`node --test Integrations/BrowserBridge/single-action.test.mjs Integrations/BrowserBridge/task-mode.test.cjs`

The cycle report contains real stdio/browser tests, independent HTTP receipts,
the original cancellation failure, native Nero checks, final pins and limitations:
`../../../NeroNook/reports/browser-local-integration-2026-11-03/README.md`.

Fuego receives this as a local source/API/evidence handoff, not a shared adopted
profile. Its actor/org/account/device/session/input-lease authority and the
existing distributed-MCP bridge remain mandatory. The old read-only/five-second
profile does not qualify this interactive implementation. No SDK/wire, server,
public download or notarization change is included.

## Nero169 · shared review preparation

`fixedUnattendedBinding` copies and freezes a deployment-owned session/namespace
pair at gate construction. The default remains Nero168; a Fuego worker must
provide a distinct, locally pinned pair and separate durable reservation. Public
tool arguments cannot set the pair. Own-key validation rejects prototype-named
extras and inherited required fields.

`unattended-result.mjs` is an opt-in, conservative agent-browser0.41.2 result
check for the interactive qualification: only a shaped positive command result
is accepted; every error or missing result retains uncertainty through the gate.
It is not a Fuego authorization receipt or proof that downstream page effects
are finished. The installed168 server and its connections are unchanged.

All four local test files can be run with:
`node --test Integrations/BrowserBridge/*.test.mjs Integrations/BrowserBridge/task-mode.test.cjs`

The169 report separately records direct local real-browser evidence and actual
Fuego-dispatched acceptance. The former must never be presented as the latter.
