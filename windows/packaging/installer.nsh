; Oanarina Archi Tool — GPL-3.0-or-later
; NSIS additions for electron-builder (packaging/electron-builder.yml nsis.include).
; Per-user install only: no "for all users" page and no UAC prompt, so people without administrator rights can install.
!macro customInstallMode
  StrCpy $isForceCurrentInstall "1"
!macroend

; Explorer thumbnails of .archi drawings (FILEPREVIEW; windows/native/ArchiThumbnail.cpp, docs/WINDOWS-FILEPREVIEW.md):
; an in-process COM thumbnail handler registered per user (HKCU\Software\Classes, no administrator rights) for the
; IThumbnailProvider handler key {e357fccd-a995-4576-b01f-234630154e96} of .archi. The DLL must match Explorer's
; architecture (x64 or ARM64), not the app's: both are packaged in resources\shellext. Unsigned until the app has a
; code-signing certificate.
!define ARCHI_THUMB_CLSID "{9D934CB7-4E6D-404F-A240-C5DBE6F0CAC0}"
!define ARCHI_THUMB_CLSID_KEY "Software\Classes\CLSID\${ARCHI_THUMB_CLSID}"
!define ARCHI_THUMB_SHELLEX_KEY "Software\Classes\.archi\ShellEx\{e357fccd-a995-4576-b01f-234630154e96}"
!define ARCHI_THUMB_APPROVED_KEY "Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved"

!macro archiRegisterThumbnailHandler
  Push $R0
  Push $R1
  ; The installer is a 32-bit process: PROCESSOR_ARCHITEW6432 names the native architecture (AMD64 or ARM64).
  ReadEnvStr $R0 PROCESSOR_ARCHITEW6432
  StrCmp $R0 "" 0 +2
    ReadEnvStr $R0 PROCESSOR_ARCHITECTURE
  StrCpy $R1 "$INSTDIR\resources\shellext\ArchiThumbnail-x64.dll"
  StrCmp $R0 "ARM64" 0 +2
    StrCpy $R1 "$INSTDIR\resources\shellext\ArchiThumbnail-arm64.dll"
  IfFileExists "$R1" 0 archi_thumb_done
    SetRegView 64
    WriteRegStr HKCU "${ARCHI_THUMB_CLSID_KEY}" "" "Oanarina Archi Tool thumbnail handler"
    WriteRegStr HKCU "${ARCHI_THUMB_CLSID_KEY}\InprocServer32" "" "$R1"
    WriteRegStr HKCU "${ARCHI_THUMB_CLSID_KEY}\InprocServer32" "ThreadingModel" "Apartment"
    WriteRegStr HKCU "${ARCHI_THUMB_SHELLEX_KEY}" "" "${ARCHI_THUMB_CLSID}"
    WriteRegStr HKCU "${ARCHI_THUMB_APPROVED_KEY}" "${ARCHI_THUMB_CLSID}" "Oanarina Archi Tool thumbnail handler"
  archi_thumb_done:
  Pop $R1
  Pop $R0
!macroend

!macro archiUnregisterThumbnailHandler
  SetRegView 64
  DeleteRegKey HKCU "${ARCHI_THUMB_SHELLEX_KEY}"
  DeleteRegKey HKCU "${ARCHI_THUMB_CLSID_KEY}"
  DeleteRegValue HKCU "${ARCHI_THUMB_APPROVED_KEY}" "${ARCHI_THUMB_CLSID}"
!macroend

; Explorer's thumbnail host may still have the handler of the installed version loaded; a loaded DLL cannot be replaced
; or deleted but can be renamed, so the uninstaller (also run by an update, before the new files are copied) moves it
; aside in $INSTDIR first; a moved copy still in use is removed by the next update or uninstall.
; (Not in customInit: the first round-5 installer, which did this in .onInit, crashed on CI before copying any file.)
!macro archiMoveThumbnailHandlerAside
  Delete "$INSTDIR\resources\shellext\ArchiThumbnail-x64.dll.old"
  Delete "$INSTDIR\resources\shellext\ArchiThumbnail-arm64.dll.old"
  IfFileExists "$INSTDIR\resources\shellext\ArchiThumbnail-x64.dll" 0 +2
    Rename "$INSTDIR\resources\shellext\ArchiThumbnail-x64.dll" "$INSTDIR\resources\shellext\ArchiThumbnail-x64.dll.old"
  IfFileExists "$INSTDIR\resources\shellext\ArchiThumbnail-arm64.dll" 0 +2
    Rename "$INSTDIR\resources\shellext\ArchiThumbnail-arm64.dll" "$INSTDIR\resources\shellext\ArchiThumbnail-arm64.dll.old"
  ClearErrors
!macroend

; Tell Explorer that file associations changed (.archi / .dxf / .ifc icons and "Open with", the .archi thumbnail
; handler) right after installing and after uninstalling, instead of on the next sign-in.
!macro customInstall
  !insertmacro archiRegisterThumbnailHandler
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
!macroend
!macro customUnInstall
  !insertmacro archiUnregisterThumbnailHandler
  !insertmacro archiMoveThumbnailHandlerAside
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
!macroend
