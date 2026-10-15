# Oanarina Archi Tool privacy policy source

Published and verified on 15 October 2026 at https://www.oanarinaldi.com/archi-tool-privacy.html. This source note does not replace the App Store Connect questionnaire.

Oanarina Archi Tool provides local architectural drawing, CAD and BIM tools. Its core modeling, drawing, saving and rendering features work without a cloud account or an internet connection.

## Local documents and settings

Drawings and exported files are stored in the locations you choose. The Mac App Store edition uses macOS App Sandbox. Its preferences, libraries, recovery data and other internal files use the app's container. Files and project folders selected through macOS dialogs can be remembered with security-scoped bookmarks. Those access permissions are stored in local app preferences and are not embedded in `.archi` documents.

The app does not include an advertising or analytics SDK, and does not automatically send telemetry or its local crash reports to the developer. macOS and the App Store may separately offer system diagnostic sharing under Apple's privacy settings.

## Optional AI assistance

When you choose the Anthropic assistant, the app sends your conversation, requests and a drawing summary to Anthropic's API. That summary includes the drawing name, units, layer and level names, object counts and selection identifiers. Anything you include in a prompt or conversation is also sent. The app uses the API key you configure for your provider account. That key is stored in the macOS keychain and is used to authenticate requests to the provider.

The local-model option accepts only loopback endpoints on this Mac and rejects remote server addresses. When you choose Anthropic instead, its own privacy and retention terms apply. Do not send project information to a provider you are not authorized to use for that information.

## Other optional connections

Online dictionary lookups send the search information needed for the requested lookup. BCF server connections and configured automation webhooks send the project, collaboration or automation data needed for the actions you request to the server addresses you configure. Their operators may process network connection information and retain submitted data under their own terms.

The optional local agent server accepts token-authenticated connections on this Mac's loopback interface. A client with that token can inspect and modify the open drawing using the supported API. Enable it only for clients you choose, keep the token private, and stop the server when it is no longer needed.

## Your choices

You can use local drawing and modeling without enabling online services. You can switch assistant providers, change provider settings, and stop the local agent server through the app's settings. You can remove the stored Anthropic API key using macOS Keychain Access (service com.oanarina.architool.assistant). You control the drawings and exports you save. Deleting the app does not necessarily delete project files or exported files you saved elsewhere.

Support website: https://www.oanarinaldi.com/archi-tool.html.

## Store declaration status

App Store Connect responses have been prepared for Emails or Text Messages, Other User Content, Search History, Other Usage Data and User ID, for App Functionality, potentially linked to the user's account or identifying content, without tracking. This conservatively includes provider-bound conversations/drawing summaries, BCF comments, dictionary queries, configured automation reports and provider-account authentication. The owner expressly approved the five-type publishing declaration on 15 October 2026, and it was published in App Store Connect.
