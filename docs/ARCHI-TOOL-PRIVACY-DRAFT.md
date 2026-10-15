# Oanarina Archi Tool privacy policy — draft

Prepared 15 October 2026 from the current macOS source. This draft is not published and is not a completed App Store privacy questionnaire.

Oanarina Archi Tool provides local architectural drawing, CAD and BIM tools. Its core modeling, drawing, saving and rendering features work without a cloud account or an internet connection.

## Local documents and settings

Drawings and exported files are stored in the locations you choose. The Mac App Store edition uses macOS App Sandbox. Its preferences, libraries, recovery data and other internal files use the app's container. Files and project folders selected through macOS dialogs can be remembered with security-scoped bookmarks. Those access permissions are stored in local app preferences and are not embedded in `.archi` documents.

The app does not include an advertising or analytics SDK, and does not automatically send telemetry or its local crash reports to the developer. macOS and the App Store may separately offer system diagnostic sharing under Apple's privacy settings.

## Optional AI assistance

When you choose the Anthropic assistant, the app sends your conversation, requests and a drawing summary to Anthropic's API. That summary includes the drawing name, units, layer and level names, object counts and selection identifiers. Anything you include in a prompt or conversation is also sent. The app uses the API key you configure for your provider account. That key is stored in the macOS keychain and is used to authenticate requests to the provider.

The default local-model endpoint is on this Mac. If you change the endpoint to a remote server, the assistant's requests and drawing context are sent to that server instead. The provider or server operator's own privacy and retention terms apply. Do not send project information to a provider you are not authorized to use for that information.

## Other optional connections

Online dictionary lookups send the search information needed for the requested lookup. BCF server connections and configured automation webhooks send the project, collaboration or automation data needed for the actions you request to the server addresses you configure. Their operators may process network connection information and retain submitted data under their own terms.

The optional local agent server accepts token-authenticated connections on this Mac's loopback interface. A client with that token can inspect and modify the open drawing using the supported API. Enable it only for clients you choose, keep the token private, and stop the server when it is no longer needed.

## Your choices

You can use local drawing and modeling without enabling online services. You can change or remove provider settings, remove the configured Anthropic key, and stop the local agent server through the app's settings. You control the drawings and exports you save. Deleting the app does not necessarily delete project files or exported files you saved elsewhere.

Support website: https://www.oanarinaldi.com/archi-tool.html.

## Publication review still needed

Confirm a public privacy-policy URL, support contact details, the data/retention behavior of supported service providers, and the final App Store data-category answers. The optional remote features mean the store questionnaire must not be completed merely by asserting that every workflow stays on the Mac.
