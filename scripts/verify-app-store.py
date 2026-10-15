#!/usr/bin/env python3
"""Check the built bundle, including both architectures and actual signed entitlements."""
import plistlib
import re
import subprocess
import sys
from pathlib import Path


def read_entitlements(path):
    result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(path)], capture_output=True, check=True)
    return plistlib.loads(result.stdout)


def verify(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["ArchiDistributionChannel"] == "app-store", "Missing store channel"
    assert info["CFBundleSupportedPlatforms"] == ["MacOSX"], "Store build must be Mac-only"
    assert info["LSMinimumSystemVersion"] == "14.0", "Unexpected minimum macOS version"
    assert info["CFBundleIdentifier"] == "com.oanarina.architool", "Unexpected bundle identifier"
    assert info["LSApplicationCategoryType"], "Missing store category"
    assert info["NSHumanReadableCopyright"], "Missing copyright"
    assert info.get("ITSAppUsesNonExemptEncryption") is False, "Missing OS-only encryption declaration"
    palette_license = (app / "Contents/Resources/ThirdPartyLicenses/ezdxf-MIT.txt").read_text()
    assert "MIT License" in palette_license and "Copyright (c) 2020 Manfred Moitzi" in palette_license, "Missing palette license notice"
    assert "Permission is hereby granted" in palette_license and "THE SOFTWARE IS PROVIDED" in palette_license, "Incomplete palette license notice"
    permission = (app / "Contents/Resources/AppStoreDistributionPermission.txt").read_text()
    assert "Expressly approved by Oana Rinaldi on 15 October 2026" in permission, "Missing approved store distribution permission"
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    helper = app / "Contents/MacOS/archi-cli"
    for binary in (executable, helper):
        archs = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
        assert set(archs) == {"arm64", "x86_64"}, "Missing universal architecture: " + str(binary)
        versions = subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
        assert re.findall(r"\bminos (\S+)", versions) == ["14.0", "14.0"], "Wrong Mach-O deployment target"
        assert re.findall(r"\bsdk (\S+)", versions) == [info["DTPlatformVersion"]] * 2, "Mach-O SDK does not match bundle metadata"
    ent = read_entitlements(app)
    for key in ("app-sandbox", "files.user-selected.read-write", "files.bookmarks.app-scope", "network.client", "network.server", "print"):
        assert ent.get("com.apple.security." + key) is True, "Missing entitlement: " + key
    assert not ent.get("com.apple.security.get-task-allow"), "Debug entitlement in store build"
    assert read_entitlements(helper) == {"com.apple.security.app-sandbox": True, "com.apple.security.inherit": True}, "Helper must inherit sandbox"
    manifest = plistlib.loads((app / "Contents/Resources/PrivacyInfo.xcprivacy").read_bytes())
    assert manifest["NSPrivacyTracking"] is False, "Unexpected tracking"
    reasons = {e["NSPrivacyAccessedAPIType"] for e in manifest["NSPrivacyAccessedAPITypes"]}
    assert reasons == {"NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPICategorySystemBootTime"}, "Missing API reasons"
    print("PASS: Mac-only universal bundle, sandbox, helper inheritance, metadata and privacy manifest")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
