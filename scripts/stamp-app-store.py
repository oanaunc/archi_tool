#!/usr/bin/env python3
"""Record the actual selected Xcode/SDK in a store bundle's metadata."""
import plistlib
import subprocess
import sys
from pathlib import Path

def command(*args): return subprocess.check_output(args, text=True).strip()

path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
sdk = command("xcrun", "--sdk", "macosx", "--show-sdk-version")
sdk_build = command("xcrun", "--sdk", "macosx", "--show-sdk-build-version")
xcode_lines = command("xcodebuild", "-version").splitlines()
version = [int(part) for part in xcode_lines[0].split()[1].split(".")]
version += [0] * (3 - len(version))
info.update({
    "CFBundleVersion": sys.argv[2], "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleSupportedPlatforms": ["MacOSX"], "ArchiDistributionChannel": "app-store",
    # Current native code uses OS-provided HTTPS/keychain services and no bundled cryptographic implementation.
    "ITSAppUsesNonExemptEncryption": False,
    "DTPlatformName": "macosx", "DTPlatformVersion": sdk, "DTPlatformBuild": sdk_build,
    "DTSDKName": "macosx" + sdk, "DTSDKBuild": sdk_build,
    "DTXcode": str(version[0] * 100 + version[1] * 10 + version[2]),
    "DTXcodeBuild": xcode_lines[1].split()[-1], "BuildMachineOSBuild": command("sw_vers", "-buildVersion"),
})
path.write_bytes(plistlib.dumps(info))
