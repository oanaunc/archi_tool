// Oanarina Archi Tool — GPL-3.0-or-later.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const hook = require('../packaging/prepare-nsis.cjs');
const templatePath = path.join(path.dirname(require.resolve('app-builder-lib/package.json')), 'templates/nsis/multiUser.nsh');
const source = fs.readFileSync(templatePath, 'utf8');

test('the pinned builder template uses a sized Unicode read and preserves registers', () => {
  const patched = hook.patchTemplate(source);
  assert.match(patched, /lstrlenW\(p r2\) i\.r3/);
  assert.match(patched, /IntOp \$3 \$3 \+ 1/);
  assert.match(patched, /\$3 <= \$\{NSIS_MAX_STRLEN\}/);
  assert.ok(patched.includes("System::Call '*$2(&w$3 .r0)'"));
  assert.ok(!patched.includes("System::Call '*$2(&w${NSIS_MAX_STRLEN} .s)'"));
  assert.ok(!patched.includes('System::Store'));
  const block = patched.slice(patched.indexOf('# ARCHI_BOUNDED_KNOWN_FOLDER'), patched.indexOf('# allow /D'));
  for (const register of ['$0', '$1', '$2', '$3']) {
    assert.equal(block.split(`Push ${register}`).length, 2);
    assert.equal(block.split(`Pop ${register}`).length, 2);
  }
  assert.ok(patched.includes('ReadRegStr $perUserInstallationFolder HKCU'));
  assert.ok(patched.includes('${StdUtils.GetParameter} $R0 "D" ""'));
});

test('the hook is idempotent for multiple architectures and preserves CRLF', () => {
  const patched = hook.patchTemplate(source);
  assert.equal(hook.patchTemplate(patched), patched);
  const crlf = source.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
  const patchedCRLF = hook.patchTemplate(crlf);
  assert.equal(patchedCRLF.replaceAll('\r\n', '\n'), patched.replaceAll('\r\n', '\n'));
  assert.ok(!patchedCRLF.replaceAll('\r\n', '').includes('\n'));
});

test('unknown or incomplete dependency templates stop packaging', () => {
  assert.throws(() => hook.patchTemplate('a changed dependency'), /Unexpected NSIS/);
  assert.throws(() => hook.patchTemplate(hook.patchTemplate(source).replace('lstrlenW', 'wrong')), /Unexpected NSIS/);
});
