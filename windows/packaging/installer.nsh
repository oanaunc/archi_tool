; Oanarina Archi Tool — GPL-3.0-or-later
; NSIS additions for electron-builder (packaging/electron-builder.yml nsis.include).
; Per-user install only: no "for all users" page and no UAC prompt, so people without administrator rights can install.
!macro customInstallMode
  StrCpy $isForceCurrentInstall "1"
!macroend

; Tell Explorer that file associations changed (.archi / .dxf / .ifc icons and "Open with") right after installing and
; after uninstalling, instead of on the next sign-in.
!macro customInstall
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
!macroend
!macro customUnInstall
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
!macroend
