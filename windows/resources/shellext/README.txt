Explorer thumbnail handler for .archi drawings (FILEPREVIEW), packaged into resources\shellext of the installed app:
  ArchiThumbnail-x64.dll, ArchiThumbnail-arm64.dll
Built by windows\native\build.cmd (MSVC) in .github/workflows/windows-app.yml; not in git. The installer
(packaging/installer.nsh) registers the DLL of Explorer's architecture per user. Source: windows/native/.
