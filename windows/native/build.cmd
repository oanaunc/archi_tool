@echo off
rem Oanarina Archi Tool - GPL-3.0-or-later
rem Builds the Explorer thumbnail handler for .archi drawings with MSVC (Visual Studio 2022 / Build Tools, C++ workload):
rem   build.cmd [dll-folder] [test-folder]
rem   dll-folder  (default ..\resources\shellext)   ArchiThumbnail-x64.dll and, when the ARM64 tools are installed,
rem                                                 ArchiThumbnail-arm64.dll (packaged by electron-builder.yml)
rem   test-folder (default ..\..\build\native)      thumbtest.exe (x64) and the object files
rem Static CRT (/MT): the DLL needs no Visual C++ redistributable in Explorer's thumbnail host.
setlocal
set "SRC=%~dp0"
set "OUT=%~1"
if "%OUT%"=="" set "OUT=%SRC%..\resources\shellext"
set "TMPD=%~2"
if "%TMPD%"=="" set "TMPD=%SRC%..\..\build\native"
if not exist "%OUT%" mkdir "%OUT%"
if not exist "%TMPD%" mkdir "%TMPD%"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (echo build.cmd: vswhere.exe not found, install Visual Studio 2022 or the Build Tools & exit /b 1)
set "VS="
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
if "%VS%"=="" (echo build.cmd: no Visual Studio with the C++ x64 tools & exit /b 1)
echo Visual Studio: %VS%
call :build x64 x64
if errorlevel 1 exit /b 1
call :build x64_arm64 arm64
if errorlevel 1 echo build.cmd: warning: no ARM64 build of the thumbnail handler (ARM64 C++ tools missing?)
dir /b "%OUT%\*.dll"
exit /b 0

:build
setlocal
set "ARCHDIR=%TMPD%\%2"
if not exist "%ARCHDIR%" mkdir "%ARCHDIR%"
call "%VS%\VC\Auxiliary\Build\vcvarsall.bat" %1 >nul
if errorlevel 1 (echo build.cmd: vcvarsall %1 failed & endlocal & exit /b 1)
set "CFLAGS=/nologo /O2 /MT /EHsc /W4 /utf-8 /std:c++17 /DUNICODE /D_UNICODE"
set "LIBS=ole32.lib oleaut32.lib shell32.lib shlwapi.lib windowscodecs.lib advapi32.lib gdi32.lib user32.lib uuid.lib"
echo === ArchiThumbnail-%2.dll
cl %CFLAGS% /LD "%SRC%ArchiThumbnail.cpp" "%SRC%ArchiPreview.cpp" /Fo"%ARCHDIR%\\" /Fe"%OUT%\ArchiThumbnail-%2.dll" /link /DEF:"%SRC%ArchiThumbnail.def" /IMPLIB:"%ARCHDIR%\ArchiThumbnail.lib" %LIBS%
if errorlevel 1 (echo build.cmd: ArchiThumbnail-%2.dll failed & endlocal & exit /b 1)
if "%2"=="x64" (
  echo === thumbtest.exe
  cl %CFLAGS% "%SRC%thumbtest.cpp" "%SRC%ArchiPreview.cpp" /Fo"%ARCHDIR%\\" /Fe"%TMPD%\thumbtest.exe" /link %LIBS%
  if errorlevel 1 (echo build.cmd: thumbtest.exe failed & endlocal & exit /b 1)
)
endlocal & exit /b 0
