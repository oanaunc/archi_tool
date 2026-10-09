// Oanarina Archi Tool — GPL-3.0-or-later.
// Patches electron-builder's MIT-licensed multiUser.nsh (Copyright (c) 2015 Loopline Systems).
// Full upstream notice: electron-builder-LICENSE.txt. See docs/THIRD-PARTY.md.
// https://github.com/electron-userland/electron-builder/issues/7921
// SHGetKnownFolderPath allocates only the returned string, not NSIS_MAX_STRLEN WCHARs.
// Reading the latter as a fixed array can cross an allocation boundary and crash before install.
const fs = require('node:fs/promises');
const path = require('node:path');

const original = String.raw`      StrCpy $0 "$LocalAppData\Programs"
      System::Store S
      # Win7 has a per-user programfiles known folder and this can be a non-default location
      System::Call 'SHELL32::SHGetKnownFolderPath(g "${'${FOLDERID_UserProgramFiles}'}", i ${'${KF_FLAG_CREATE}'}, p 0, *p .r2)i.r1'
      ${'${If}'} $1 == 0
        System::Call '*$2(&w${'${NSIS_MAX_STRLEN}'} .s)'
        StrCpy $0 $1
        System::Call 'OLE32::CoTaskMemFree(p r2)'
      ${'${endif}'}
      System::Store L
      StrCpy $INSTDIR "$0${'\\'}${'${APP_FILENAME}'}"`;

const replacement = String.raw`      # ARCHI_BOUNDED_KNOWN_FOLDER: Copyright (c) 2015 Loopline Systems, MIT; modified by Oana Rinaldi.
      Push $0
      Push $1
      Push $2
      Push $3
      StrCpy $0 "$LocalAppData\Programs"
      StrCpy $2 0
      System::Call 'SHELL32::SHGetKnownFolderPath(g "${'${FOLDERID_UserProgramFiles}'}", i ${'${KF_FLAG_CREATE}'}, p 0, *p .r2)i.r1'
      ${'${If}'} $1 == 0
      ${'${AndIf}'} $2 != 0
        System::Call 'kernel32::lstrlenW(p r2) i.r3'
        IntOp $3 $3 + 1
        ${'${If}'} $3 <= ${'${NSIS_MAX_STRLEN}'}
          # Read exactly the allocated string including its terminator, into the destination register.
          System::Call '*$2(&w$3 .r0)'
        ${'${EndIf}'}
      ${'${EndIf}'}
      ${'${If}'} $2 != 0
        System::Call 'OLE32::CoTaskMemFree(p r2)'
      ${'${EndIf}'}
      StrCpy $INSTDIR "$0${'\\'}${'${APP_FILENAME}'}"
      Pop $3
      Pop $2
      Pop $1
      Pop $0`;

function patchTemplate(source) {
  const eol = source.includes('\r\n') ? '\r\n' : '\n';
  const normalized = source.replaceAll('\r\n', '\n');
  if (normalized.includes(replacement) && !normalized.includes(original)) return source;
  if (normalized.split(original).length !== 2 || normalized.includes('ARCHI_BOUNDED_KNOWN_FOLDER')) {
    throw new Error('Unexpected NSIS per-user template: review the known-folder fix before packaging.');
  }
  return normalized.replace(original, replacement).replaceAll('\n', eol);
}

async function beforePack(context) {
  if (context.electronPlatformName !== 'win32') return;
  const packagePath = require.resolve('app-builder-lib/package.json');
  const version = JSON.parse(await fs.readFile(packagePath, 'utf8')).version;
  if (version !== '25.1.8') throw new Error(`Review the NSIS known-folder fix for app-builder-lib ${version}.`);
  const templatePath = path.join(path.dirname(packagePath), 'templates/nsis/multiUser.nsh');
  const source = await fs.readFile(templatePath, 'utf8');
  const patched = patchTemplate(source);
  if (patched !== source) await fs.writeFile(templatePath, patched);
  console.log('NSIS per-user known-folder read is bounded to the returned string; registers preserved.');
}

module.exports = beforePack;
module.exports.patchTemplate = patchTemplate;
