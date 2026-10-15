# Mac App Store edition

The Mac App Store candidate is a separate, sandboxed macOS build. The existing signed/notarized website DMG and its download links remain available. The store preparation scripts never replace `build/Oanarina Archi Tool.app`, the website DMG, or `dist/SHA256SUMS.txt`.

## Build and verify locally

```sh
scripts/package-app-store.sh prepare
python3 scripts/test-app-store.py
"build/app-store/prepare/Oanarina Archi Tool.app/Contents/MacOS/Oanarina Archi Tool" --sandbox-selftest
```

This builds both Apple silicon and Intel, with macOS 14 as the minimum. The store bundle keeps `com.oanarina.architool`, its `.archi` format, and the current marketing version. Its default build number is the website build number plus one; set `APP_STORE_BUILD_NUMBER` to an integer greater than every previously uploaded macOS build when preparing subsequent submissions.

The ZIP in `dist/app-store` is an **ad-hoc signed local sandbox preview**, not a notarized public download or a store-ready upload. Gatekeeper may block it when transferred to another computer. Test this local build on the build machine; use a properly provisioned development build or TestFlight for external testers.

`FILEACCESS` (`FA`, `GRANTFOLDER`), File → Allow Project Folder Access, and Tools → Navigation & Sheets → Allow Project Folder Access open the system folder picker. Select a project folder for linked images, textures, external references, scripts, backups and multi-file exports. The app remembers explicitly selected files/folders with security-scoped bookmarks in its own preferences, restores them on launch, and releases access on quit. These permissions are not stored in `.archi` files. An agent may invoke `run_command` with `FILEACCESS`; the human still selects the folder in the system picker.

The sandbox container holds settings, templates, scripts, recents and recovery data. macOS may migrate preferences when an existing app first adopts sandboxing; that does not grant access to external paths stored in those preferences. This preparation does not copy user libraries or drawing files. Use the file pickers to choose your existing documents and folders. Individual document grants may not cover sibling `.bak`, thumbnails, linked resources or OBJ/MTL sidecars; choose the containing project folder for those workflows.

The local JSON-RPC agent server remains available on loopback with its launch-specific bearer token. Its discovery file is inside the store app's container; Settings → Agents shows its actual path and a matching connection example. The bundled helper inherits the app sandbox, per Apple's helper requirements. Standalone `archi-cli --mcp` and the Python subprocess bridge belong to the website edition; the store edition's help explains this distinction. In-app JavaScript and the local agent API remain available.

## Distribution signing

An App Store purchasing account alone does not establish Apple Developer Program enrollment or App Store Connect access. The development and Developer ID identities found on this machine are not store distribution identities. Store signing requires:

- An active Apple Developer Program team and access to App Store Connect.
- The registered explicit macOS App ID `com.oanarina.architool` and a Mac App Store distribution provisioning profile for that team.
- An Apple Distribution / Mac App Distribution application certificate and private key, plus a Mac Installer Distribution certificate and private key.

Local account inspection on 15 October 2026: Xcode is already signed into the **OANA RINALDI Developer Team**, with Admin access. No macOS provisioning profiles or usable Mac App Store distribution signing identities were found on this Mac. No membership purchase, new account, certificate creation, agreement acceptance or store upload was performed.

### Signing setup created after authorization

Later on 15 October 2026, the user authorized creating the signing setup. Xcode created **Apple Distribution: OANA RINALDI (HBD3XXQK45)** and **3rd Party Mac Developer Installer: OANA RINALDI (HBD3XXQK45)**. Their private keys remain in the macOS keychain.

Xcode-managed export of an archive of the actual app obtained **Mac Team Store Provisioning Profile: com.oanarina.architool**, for platform `OSX` and explicit application identifier `HBD3XXQK45.com.oanarina.architool`. Local checks confirmed the profile authorizes the new application distribution certificate and expires on 15 October 2027. A local copy is at `build/app-store/profiles/ArchiTool-MacAppStore.provisionprofile`; it is ignored by Git.

The first local export reached code signing but failed with `errSecInternalComponent` while waiting for keychain authorization. The computer-use tool cannot operate the protected macOS SecurityAgent dialog. The human needs to approve the system's request to use the new signing key before retrying. No store upload or agreement acceptance occurred.

To generate the real signed installer after that authorization:

```sh
APP_STORE_APPLICATION_IDENTITY='Apple Distribution: OANA RINALDI (HBD3XXQK45)' \
APP_STORE_INSTALLER_IDENTITY='3rd Party Mac Developer Installer: OANA RINALDI (HBD3XXQK45)' \
APP_STORE_PROFILE="$PWD/build/app-store/profiles/ArchiTool-MacAppStore.provisionprofile" \
APP_STORE_BUILD_NUMBER=7 \
scripts/package-app-store.sh package
```

Browser sign-in was subsequently completed. The macOS-only App Store Connect record was created successfully: **Oanarina Archi Tool**, Apple ID **6823133541**, bundle ID `com.oanarina.architool`, SKU `oanarina-archi-tool-macos`, primary language English (U.S.). [Open the draft](https://appstoreconnect.apple.com/apps/6823133541/distribution/macos/version/inflight).

Version **1.0.2** is in **Prepare for Submission**. Its description, keywords, support/marketing URLs, reviewer notes and no-sign-in setting were saved. At the owner’s subsequent request, the release setting was changed to automatic release after Apple approval. General App Information confirmed **Saved** for the subtitle and Graphics & Design category. App Review contact information was subsequently supplied by the owner and saved in App Store Connect. The personal phone and email values are kept in Apple’s review form rather than the repository. No build was uploaded. Add for Review was used only to obtain validation errors; Apple did not add the incomplete submission for review. A local screenshot of the saved version header is at `build/app-store/evidence/app-store-draft.jpg` (ignored by Git).

App Store Connect displays an account-level requirement to review and accept the updated **Paid Applications Schedule (Schedule 2)** in Business. The account holder must review this binding agreement; no agreement was accepted here. The actual packaging command was also retried with the new profile, reached signing, and failed with `errSecInternalComponent` after protected keychain authorization timed out. A fresh signing attempt needs the human present to approve that macOS dialog. No signing-key permissions were bypassed or weakened.

Saved listing fields and remaining requirements are recorded in `docs/APP-STORE-METADATA.json`; privacy policy source is in `docs/ARCHI-TOOL-PRIVACY.md`. The public privacy policy is now published and verified; the app is not submitted.

In Xcode → Settings → Accounts, select the enrolled team and manage the distribution certificates. Create/download the Mac App Store distribution profile from Certificates, Identifiers & Profiles. Keep private keys and profiles out of Git.

```sh
APP_STORE_APPLICATION_IDENTITY='3rd Party Mac Developer Application: YOUR NAME (TEAMID)' \
APP_STORE_INSTALLER_IDENTITY='3rd Party Mac Developer Installer: YOUR NAME (TEAMID)' \
APP_STORE_PROFILE='/absolute/path/to/store.provisionprofile' \
APP_STORE_BUILD_NUMBER=7 \
scripts/package-app-store.sh package
```

Use the certificate names actually installed in your keychain. The script rejects expired, development, Developer ID, mismatched-platform, mismatched-team and mismatched-bundle profiles, validates the application's signing certificate against the profile, verifies both signed universal binaries and entitlements, and checks the installer signature. The resulting `.pkg` can be uploaded using Apple's Transporter app after the remaining submission items below are resolved. The script does not upload, enroll an account, purchase membership, or accept agreements.

## Submission items still required

**Licensing:** the repository remains GPL-3.0-or-later. On the owner’s instruction to remove incompatible copied material, the LibreCAD ACI table was replaced by the MIT-licensed ezdxf palette, pinned to commit `7c64bce52c9d60b9db2dad4d2793c1168c8d3f64`. Its full notice is preserved in the Swift file and app resources; `docs/THIRD-PARTY.md` records the change and the original table’s historical credit. Color indices and document schemas remain unchanged, while some indexed shades use the newer default display palette. Source/header and recorded-credit inspection found no other declared copied GPL material in the current native app; study references and independently implemented algorithms retain their credits. This is a source audit, not proof of every copyright interest. Git records Oana Rinaldi as the sole committing author. The owner expressly approved the alternative permission for original code/assets in `docs/APP-STORE-PERMISSION.txt` on 15 October 2026; it is bundled in the store candidate. No original-code license or third-party license has been silently changed.

**Privacy:** `PrivacyInfo.xcprivacy` declares no tracking and the reasons for app-specific preferences, document/container timestamps and event timing. It does not assert a completed App Store Connect data-collection questionnaire. Review the optional Anthropic assistant (which sends prompts and drawing summaries to the user's provider account), configured BCF servers/webhooks, online dictionary queries and any server retention before finalizing privacy labels and a public privacy-policy URL. Local modeling needs no cloud account; crash reports are stored locally and are not sent automatically.

**Review:** the macOS-only record and factual text metadata are saved. The English (U.S.) listing now has two actual 2880 × 1800 Mac screenshots and a calculated 4+ rating (collaboration messaging is disclosed). Free pricing and availability in all 175 current/future storefronts are configured to match the free website edition. The policy URL is saved; five conservative online-data disclosures were expressly approved by the owner and published. Content Rights Information is saved. Supply the build-derived icon by uploading revised build 7, finish export-compliance answers, then validate and submit. Test outside-container files across an actual quit/relaunch, moved/deleted files, linked assets, Save As, backups, sidecar export, custom script folders, printing, local/cloud AI and loopback agents. Local checks cannot confirm Apple's server validation or review approval.

## Draft listing

Name: **Oanarina Archi Tool**  
Subtitle: **Architecture, CAD and BIM**  
Primary category: **Graphics & Design**  
Marketing/support website: **https://www.oanarinaldi.com**

Oanarina Archi Tool is a native Mac workspace for architectural drawing, 3D modeling and building information modeling. Draw with precise coordinates, snaps and familiar command aliases. Build projects with levels, walls, doors, windows, floors, roofs, stairs and rooms, then arrange sheets and export drawings or schedules.

Work in 2D and 3D, edit materials, render views, and exchange models using implemented formats including DXF, IFC, OBJ, STL and GLB. Save projects in the native `.archi` format. Automate work through the built-in JavaScript console and opt-in local agent API.

Core drawing and modeling work offline. Online lookups and a configured AI provider require a connection. Select project folders to access linked resources and multi-file exports in the sandboxed Mac App Store edition. Standalone command-line MCP and Python tooling are available in the website edition.

Draft review notes: Mac-only app, macOS 14+, Apple silicon and Intel. Start with Help → Sample House. File → Allow Project Folder Access selects a folder for linked assets and batch exports. Settings → Agents enables the token-protected loopback server. AI services are optional and use the user's own configured provider. No login is required for local CAD/BIM work.

## Local validation on 15 October 2026

- Universal optimized preview built successfully. Signed-bundle verification confirmed both architectures, minimum OS, actual SDK metadata, sandbox entitlements, helper inheritance and privacy manifest.
- Eight profile-validator regression tests passed.
- The full release-mode core run completed 1,047 tests, with 1,046 passes and one failure because the new opt-in loopback diagnostic was not yet in the network allowlist. After updating that allowlist, all six `AnalysisAgentAPITests` passed, including the offline/no-telemetry guard. Logs: `build/test-release.log` and `build/test-app-store-privacy.log`.
- Eighteen focused checks passed inside the actual app sandbox: drawing edits, undo, native persistence, DXF exchange, bookmarks, invalid bookmark handling, inherited helper launch, denied ungranted writes, loopback agent commands/undo and JavaScriptCore.
- Manual UI check: opened a disposable outside-container drawing through Open, quit and relaunched, reopened it from Open Recent without another picker, granted its test folder through File → Allow Project Folder Access, added a circle and saved. The saved drawing contained two entities and its `.bak` retained the prior one-entity drawing.
- The bundled Cedar House opened with 408 drawing objects and 59 building elements, and its textured SceneKit 3D viewport rendered inside the sandbox.
- The website `Oanarina-Archi-Tool-1.0.2.dmg` still matches its existing published SHA-256 checksum.

These are local preview checks. The distribution-signed installer, App Store Connect validation, TestFlight, cloud-provider behavior, and Apple review remain unverified.

## Apple references

- [macOS distribution and required sandboxing](https://developer.apple.com/macos/distribution/)
- [Embedding a command-line helper](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)
- [Required reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Developer Program enrollment](https://developer.apple.com/programs/enroll/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [FSF's explanation of GPL/App Store conflicts](https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement) (historical context; confirm current terms for this submission)

## Current continuation

The most recent distribution packaging attempt built the app but failed at helper signing with `errSecInternalComponent` when human keychain authorization timed out. The protected dialog cannot be operated by computer-use tools. A fresh attempt should be made with the human ready to approve it. Build 6 is superseded locally by revised build 7 (MIT palette replacement and explicit confirmation before each Anthropic request). No build is uploaded or submitted.

The account Business screen shows **Free Apps Agreement: Active** through 19 July 2027. The paid agreement has a new version available, but no paid agreement was accepted; this candidate is priced Free.

The owner expressly approved both the five-type privacy publishing declaration and the separate copyright permission on 15 October 2026. The privacy declaration is published and the permission is recorded in `docs/APP-STORE-PERMISSION.txt`.

The revised store bundle declares `ITSAppUsesNonExemptEncryption = false`. Source inspection found OS-provided URLSession HTTPS and keychain access, with no embedded custom encryption implementation; see [Apple’s OS-encryption guidance](https://developer.apple.com/documentation/Security/complying-with-encryption-export-regulations). This records the current implementation; Apple’s server processing and any additional export questions still need completion after upload. Bundle verification also requires the full ezdxf MIT notice.

## Revised-candidate checks

- Fourteen release-mode DXF tests passed after the palette replacement, including indexed/true-color, transparency, XDATA and layout round trips (`build/app-store/test-dxf-mit-palette.log`).
- The current native app binary passed all 955 in-app checks in an isolated local test bundle. The new checks confirm denied Anthropic sharing queues no request/history entry, asks again on a later request, and leaves loopback model requests free of cloud permission prompts (`build/app-store/selftest-7.log`). No cloud request is sent by these checks.
- All eight provisioning-profile regression tests passed again.
- Production universal build 7 completed successfully. All 955 in-app checks and 18 sandbox runtime checks passed on the actual universal sandbox bundle; manual cancellation of Anthropic sharing retained the unsent draft. Logs: `build/app-store/selftest-7-sandbox.log` and `build/app-store/sandbox-runtime-7.log`. These results do not assert distribution signing, upload or Apple review succeeded.

## Latest Apple validation

After publishing the approved privacy declaration and saving Content Rights Information, Apple’s Add for Review validation listed only an uploaded build selection and completion of screenshot processing. The listing now contains two replacement 2880 × 1800 screenshots captured from revised build 7. Automatic release after approval remains selected. The revised distribution signing attempt timed out with `errSecInternalComponent` while waiting for human approval of the protected keychain prompt; no build has been uploaded or submitted. A fresh attempt requires the human present.

The screenshot captures were JPEG data despite their initial `.png` filenames. They were uploaded again with correct `.jpg` extensions, the failed filename uploads were removed from the listing, and both actual previews rendered successfully. A subsequent Add for Review check reported only **You must choose a build**. The local preview was regenerated with the approved permission, and complete bundle/signature verification passed again (`build/app-store/prepare-7.log`).

## Signing completed after human approval

On 15 October 2026 the owner approved the macOS signing prompts. The universal build 7 app and installer were signed successfully with the team’s Apple Distribution and 3rd Party Mac Developer Installer identities. Strict deep signature verification, signed entitlements/metadata verification, the profile-to-actual-signing-certificate comparison and `pkgutil --check-signature` passed. The installer is `dist/app-store/Oanarina-Archi-Tool-1.0.2-7.pkg`. The packaging script now avoids `grep -q`/`pipefail` premature pipe closure and passes the optional certificate-extraction prefix with `=`.

A new archive under `build/app-store/upload-7/` contains the actual signed build 7 app and matching archive metadata; the earlier managed-signing build 6 archive was not used for upload. Xcode export with destination `upload` has started using the signed-in developer account. Server validation, processing and final review submission remain pending until the upload result is confirmed.
