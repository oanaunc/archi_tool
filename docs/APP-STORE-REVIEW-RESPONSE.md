# App Review responses

## Current issue — Guideline 2.4.5(i), 22 October 2026

Verified directly in App Store Connect on **23 October 2026**: version **1.0.2 (7)** is **Rejected**, submission `828a79cc-0290-4243-a979-f28df5571438` is **Unresolved Issues**, and the item lists **2.4.5 Performance: Hardware Compatibility (macOS)**. The conversation contains **six messages**. Apple acknowledged the previous information on **22 October at 7:37 PM Europe/Bucharest**, saying review would continue, then requested the network-server explanation again at **7:56 PM**. The currently listed issue is 2.4.5; this does not independently establish the disposition of every earlier finding.

The version page still contains the expanded local-server reviewer notes and the dedicated `com.apple.security.network.server` sandbox usage explanation saved on 16 October. Build 7, uploaded on 15 October, remains selected. The prior remedy was an explanation and same-build resubmission, not removal of the entitlement. The **1.0.3 (8)** website release fixes sheet viewport framing; its Developer ID notarization does not update the selected App Store build or resolve this entitlement question.

**Follow-up delivery status: draft only; not sent.** No store metadata was changed, no binary was uploaded and no review was restarted during this investigation.

### Follow-up reply to App Review (draft)

Hello App Review,

Thank you for continuing the review of Oanarina Archi Tool 1.0.2 (7). Following your October 22 request under Guideline 2.4.5(i), could you help us identify which step of the local agent server verification is failing?

The submitted build uses com.apple.security.network.server for an implemented, optional HTTP/JSON-RPC server. A local automation client connects to the app to inspect the drawing, run drawing commands and undo changes. The app accepts incoming connections on IPv4 loopback 127.0.0.1 only, default port 47800. The server is off by default and requires no AI provider, Claude installation, account or API key. Authenticated RPC requests use the random per-launch token shown in the app.

To find and test it in the submitted build:

1. Open the bundled Cedar House or a new drawing. A document window must be open.
2. Choose Oanarina Archi Tool > Agent Server... to open the agent settings, then click Start under LOCAL AGENT SERVER. Alternatively, use Settings > Agents or enter AGENTS in the in-app command line.
3. In Terminal run: curl http://127.0.0.1:47800/health
   The app returns JSON containing "status":"ok" and "rpc":"/rpc". This health check needs no token.
4. Click Copy Token in the same panel. Substitute it for PASTE_TOKEN_HERE below:

```sh
curl http://127.0.0.1:47800/rpc -H 'Authorization: Bearer PASTE_TOKEN_HERE' -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"run_command","params":{"command":"CIRCLE 0,0 500"}}'
```

A circle is added to the drawing. Edit > Undo removes it. Click Stop in the agent panel to end incoming connections. If the port has been changed, use the port displayed in that panel.

These steps are also saved in App Review Information > Notes and App Sandbox Information. We rechecked the sandbox preview with matching executable UUIDs to the uploaded build on October 23: incoming HTTP drawing commands and undo both passed. This was a local sandbox preview test, not an App Store-installed test.

The server entitlement is required to accept these incoming connections. Please let us know whether the difficulty is locating the panel, starting the listener, or receiving the response, and share any error you see so we can address it precisely.

Thank you,
Oana Rinaldi

### Fresh verification — 23 October 2026

- Archived distribution build `1.0.2 (7)` passes `scripts/verify-app-store.py` and strict deep signature verification. Its signed entitlements include `com.apple.security.network.server`.
- The existing ad-hoc signed sandbox preview has matching app executable UUIDs for both architectures: arm64 `A1AB3F1C-144D-3383-B520-6F31B2C3695E`; x86_64 `EF89DA89-8329-386C-9EAA-CE28FA01E641`.
- All **17 sandbox checks** passed again, including HTTP drawing commands and RPC undo. Log: `build/app-store/sandbox-runtime-review-2026-10-23.log` (ignored by Git). The optional outside-container denied-write probe was omitted. Runtime execution was on this Mac, not Apple's review device or an App Store-installed copy.
- Source inspection confirms `NWListener` binds IPv4 loopback with `acceptLocalOnly`; agent settings expose Start/Stop and Copy Token. Removing the entitlement would break the retained server feature in the sandbox.
- [Apple's entitlement reference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server) defines permission to listen for incoming connections. [Apple's review-status guidance](https://developer.apple.com/help/app-review/after-submitting-for-review/review-status) says an information request can be answered directly without restarting review when there are no other issues to resolve.

## Previous issue — Guideline 4.3(a), 16 October 2026

The owner supplied Apple's rejection message for version **1.0.2**, submission `828a79cc-0290-4243-a979-f28df5571438`. Apple alleges similar binary, metadata and/or concept, but identifies no comparison app or specific matching element. The message also includes an extended-review warning. App Store Connect was inspected after owner authorization to reply: version **1.0.2 (7)** shows **Rejected**, the submission shows **Unresolved Issues**, and the issue is listed as **4.3.0 Design: Spam**.

**Delivery status:** sent after the owner instructed “reply”, on **16 October 2026 at 9:56 PM Europe/Bucharest**. App Store Connect displays **Messages (4)** and the new **Oana Rinaldi — Today 9:56 PM** message with the response below. The submission remains **Unresolved Issues** and build **1.0.2 (7)** remains **Rejected** pending Apple's response. No appeal was filed and no new build was uploaded or resubmitted for this issue. The earlier entitlement reply below remains a historical record of a separate issue.

### Reply to App Review (sent as plain text)

Hello App Review,

Thank you for reviewing Oanarina Archi Tool 1.0.2. I would appreciate clarification and reconsideration of the Guideline 4.3(a) finding for submission 828a79cc-0290-4243-a979-f28df5571438.

Oanarina Archi Tool is a native macOS architectural authoring application. Its Swift ArchiCore engine implements the drawing and building model, geometry, command execution and document persistence; its macOS interface uses SwiftUI, AppKit and SceneKit. The Swift package has no external package dependencies. The application combines editable 2D drafting and 3D building elements, model-derived schedules, native .archi project files, and JavaScript and local agent automation operating on the same open drawing.

To inspect the implemented workflow in the submitted build:

1. Open the bundled Cedar House from the start screen and inspect the editable building in plan and 3D.
2. Enter SCHEDULE in the in-app command line, choose Doors, and press Return at the insertion-point prompt to print a schedule derived from the current model.
3. Enter CIRCLE 0,0 500 in the command line. The circle appears in the drawing; Edit > Undo removes it. The same command can be executed through the opt-in authenticated local agent API using the steps already provided in our review notes.
4. Save a project as .archi and reopen it to inspect its stored drawing and building data. Core authoring does not require an account or cloud service.

The project documents its open-source references and third-party attribution in THIRD-PARTY.md, included in the app's resources. Reference checkouts are not included by the app's build scripts. I can provide the relevant source and implementation details to help investigate a specific similarity.

Could you identify the app or apps being compared, if possible, and the particular binary components, assets, metadata or workflows considered substantially similar? This would help me address the finding with specific evidence or appropriate changes. Please also clarify whether the extended-review notice refers solely to this 4.3(a) finding or to any additional issue requiring action.

Thank you,
Oana Rinaldi

### Evidence and limits

- `app/Package.swift`: ArchiCore, ArchiApp and command-line targets; no external package dependencies. This alone does not establish originality of every source file or asset.
- `app/Sources/ArchiApp/StartView.swift`: bundled Cedar House entry and command-driven sample building.
- `app/Sources/ArchiCore/Commands/ArchitectureCommands.swift`: model-derived SCHEDULE command; `app/Tests/ArchiCoreTests/BIMSchedulesTests.swift` covers schedule behavior.
- `app/Sources/ArchiApp/AgentServer.swift` and the earlier entitlement response below: authenticated local command execution and undo. Prior sandbox runtime evidence is historical; no fresh runtime test was performed for this documentation change.
- `scripts/build.sh` and `scripts/package-app-store.sh`: explicit native target builds and resource copying, without bundling `other_projects/`. `docs/THIRD-PARTY.md` records references and adapted material. Do not claim the app has no third-party material.
- Apple's comparison target and the owner's full submission history across accounts are unknown. Do not assert that no similar app has ever been submitted or that Apple has made a proven error.
- The demo steps above are supported by source inspection; they have not been repeated interactively in this session. A short recording of the submitted build would strengthen a later reply or appeal; none was attached or promised in this reply.
- [Guideline 4.3](https://developer.apple.com/app-store/review/guidelines/#spam) addresses duplicate and insufficiently differentiated apps. [Apple's review guidance](https://developer.apple.com/distribute/app-review/#contacting-us) permits correspondence before resubmission and an appeal with specific compliance reasons. Obtain clarification before choosing changes or another submission; a cosmetic change alone would not establish a distinct product.

## Previous issue — network server entitlement

Sent on 16 October 2026 at **11:05 AM Europe/Bucharest** for macOS version **1.0.2 (7)**, submission `828a79cc-0290-4243-a979-f28df5571438`.

**Delivery status:** sent after owner authorization and sign-in. App Store Connect displays the reply as the second message. Expanded reviewer notes and dedicated `com.apple.security.network.server` usage information were saved and verified after reopening the version. Update Review and Resubmit to App Review succeeded; both the submission and macOS App 1.0.2 (7) then showed **Waiting for Review**. The original submission ID is retained. Apple approval and public availability are not yet confirmed.

## Reply to App Review (sent as plain text)

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

This demonstration requires no account, cloud service, API key or external AI software. We have saved these reproduction steps in App Review Information > Notes and added a dedicated com.apple.security.network.server usage explanation in App Sandbox Information.

Please continue review with the server entitlement retained for this implemented feature.

Thank you.

## App Review Information — replacement notes

The saved replacement text is the `reviewNotes` value in [APP-STORE-METADATA.json](APP-STORE-METADATA.json); the dedicated entitlement text is recorded under `sandboxUsageInformation`. The existing reviewer contact details, no-login setting and automatic release after approval were preserved. The [existing review submission](https://appstoreconnect.apple.com/apps/6823133541/distribution/reviewsubmissions/details/828a79cc-0290-4243-a979-f28df5571438) confirms resubmission of build 7 on 16 October 2026 at 11:05 AM and Waiting for Review.

## Verification and implementation evidence

- `app/Sources/ArchiApp/AgentServer.swift`: `NWListener`, loopback binding, local-only acceptance, HTTP health response, authenticated RPC and stop/cancel lifecycle.
- `app/Sources/ArchiApp/AgentSettings.swift`: Start/Stop, configurable port and Copy Token UI. `app/Sources/ArchiApp/Preferences.swift` defaults auto-start to false.
- `app/Sources/ArchiApp/AppCommands.swift`: `AGENTSETTINGS`, `AGENTS` and `AGENTSERVER` open agent settings.
- `app/ArchiTool-AppStore.entitlements` and the distribution-signed build 7 both contain client and server entitlements. Strict deep signature verification and `scripts/verify-app-store.py` passed again on 16 October 2026.
- The existing sandbox preview passed all **17 checks**, including an HTTP `run_command` request that creates a circle and an RPC `undo` request that removes it. Local log: `build/app-store/sandbox-runtime-review-2026-10-16.log` (ignored by Git). This run omitted the optional outside-container denied-write probe; the earlier build 7 run included it and passed 18 checks.
- Preview and distribution app executable UUIDs match for both architectures: arm64 `A1AB3F1C-144D-3383-B520-6F31B2C3695E`; x86_64 `EF89DA89-8329-386C-9EAA-CE28FA01E641`. Runtime results are from the ad-hoc signed sandbox preview, not an App Store-installed copy.
- Apple reference: [incoming network connection entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server).
