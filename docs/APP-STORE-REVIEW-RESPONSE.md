# Network server entitlement — review response

Prepared on 16 October 2026 for macOS version **1.0.2 (7)**, submission `828a79cc-0290-4243-a979-f28df5571438`.

**Delivery status:** prepared locally; neither this reply nor the expanded reviewer notes have been sent/saved in App Store Connect. The owner must authorize sending the reply. Keep the server entitlement: the submitted app implements an incoming TCP listener for its opt-in local agent API. No replacement binary is needed for this explanation; Apple determines whether it resolves the review blocker.

## Reply to App Review

Hello App Review,

Oanarina Archi Tool 1.0.2 (7) uses `com.apple.security.network.server` for its built-in local agent server. When enabled by the user, the app listens for incoming HTTP connections on `127.0.0.1:47800` and responds to JSON-RPC 2.0 requests at `/rpc`. Local automation tools use this API to inspect the open drawing, execute CAD/BIM commands and undo edits, with changes visible in the app.

The listener is implemented with Network.framework's `NWListener` and is bound to IPv4 loopback with `acceptLocalOnly` enabled. It accepts connections only from this Mac. The server is off by default; every `/rpc` request requires a random per-launch bearer token displayed in Settings > Agents. The client entitlement is also present for outgoing requests, but does not replace the incoming listener permission.

To verify the functionality in the submitted build:

1. Launch the app and open a new drawing or the bundled Cedar House sample.
2. Choose Oanarina Archi Tool > Settings… (Command-comma), select Agents, and click Start under LOCAL AGENT SERVER. The panel displays the listening URL, port and token controls. The in-app command `AGENTSETTINGS` (alias `AGENTS`) opens the same panel.
3. In Terminal, run `curl http://127.0.0.1:47800/health`. The app responds with JSON containing `"status":"ok"` and `"rpc":"/rpc"`. This health endpoint does not require a token.
4. Click Copy Token in Settings > Agents. Replace PASTE_TOKEN_HERE below with that token and run:

```sh
curl http://127.0.0.1:47800/rpc \
  -H 'Authorization: Bearer PASTE_TOKEN_HERE' \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"run_command","params":{"command":"CIRCLE 0,0 500"}}'
```

The app returns a JSON-RPC result and adds a circle to the open drawing. Undo it with Edit > Undo. Click Stop in Settings > Agents to stop accepting connections. If a different port is configured in the panel, use that port in the examples.

This demonstration requires no account, cloud service, API key or external AI software. Please continue review with the server entitlement retained for this implemented feature.

Thank you.

## App Review Information — replacement notes

The full replacement text is the `reviewNotes` value in [APP-STORE-METADATA.json](APP-STORE-METADATA.json). Preserve the existing reviewer contact details and no-login setting. Save those notes and send the reply in the [existing review submission](https://appstoreconnect.apple.com/apps/6823133541/distribution/reviewsubmissions/details/828a79cc-0290-4243-a979-f28df5571438) after owner authorization. Do not claim either action is complete until confirmed by App Store Connect.

## Verification and implementation evidence

- `app/Sources/ArchiApp/AgentServer.swift`: `NWListener`, loopback binding, local-only acceptance, HTTP health response, authenticated RPC and stop/cancel lifecycle.
- `app/Sources/ArchiApp/AgentSettings.swift`: Start/Stop, configurable port and Copy Token UI. `app/Sources/ArchiApp/Preferences.swift` defaults auto-start to false.
- `app/Sources/ArchiApp/AppCommands.swift`: `AGENTSETTINGS`, `AGENTS` and `AGENTSERVER` open agent settings.
- `app/ArchiTool-AppStore.entitlements` and the distribution-signed build 7 both contain client and server entitlements. Strict deep signature verification and `scripts/verify-app-store.py` passed again on 16 October 2026.
- The existing sandbox preview passed all **17 checks**, including an HTTP `run_command` request that creates a circle and an RPC `undo` request that removes it. Local log: `build/app-store/sandbox-runtime-review-2026-10-16.log` (ignored by Git). This run omitted the optional outside-container denied-write probe; the earlier build 7 run included it and passed 18 checks.
- Preview and distribution app executable UUIDs match for both architectures: arm64 `A1AB3F1C-144D-3383-B520-6F31B2C3695E`; x86_64 `EF89DA89-8329-386C-9EAA-CE28FA01E641`. Runtime results are from the ad-hoc signed sandbox preview, not an App Store-installed copy.
- Apple reference: [incoming network connection entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server).
