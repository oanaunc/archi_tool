#!/usr/bin/env python3
"""Validate a decoded Mac App Store profile and merge its restricted signing entitlements."""
import datetime
import plistlib
import sys
from pathlib import Path


def prepare(profile, info, entitlements, certificate=None):
    if profile.get("ExpirationDate", datetime.datetime.min) <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError("Provisioning profile is expired")
    if profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
        raise ValueError("Use a Mac App Store distribution profile, not a development or Developer ID profile")
    if "OSX" not in profile.get("Platform", []):
        raise ValueError("Profile is not for macOS")
    allowed = profile.get("Entitlements", {})
    if allowed.get("get-task-allow") or allowed.get("com.apple.security.get-task-allow"):
        raise ValueError("Development debugging entitlement is not allowed")
    app_id = allowed.get("com.apple.application-identifier", "")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    if app_id not in [prefix + "." + info["CFBundleIdentifier"] for prefix in prefixes]:
        raise ValueError("Profile must explicitly match " + info["CFBundleIdentifier"])
    team = allowed.get("com.apple.developer.team-identifier")
    if not team or team not in profile.get("TeamIdentifier", []):
        raise ValueError("Profile has no matching team identifier")
    if certificate is not None and certificate not in profile.get("DeveloperCertificates", []):
        raise ValueError("Signing certificate is not authorized by this provisioning profile")
    result = dict(entitlements)
    result["com.apple.application-identifier"] = app_id
    result["com.apple.developer.team-identifier"] = team
    return result


if __name__ == "__main__":
    try:
        paths = [Path(p) for p in sys.argv[1:]]
        profile, info, entitlements = [plistlib.loads(p.read_bytes()) for p in paths[:3]]
        cert = paths[3].read_bytes() if len(paths) > 3 else None
        paths[2].write_bytes(plistlib.dumps(prepare(profile, info, entitlements, cert)))
    except (ValueError, KeyError, OSError) as error:
        sys.exit("Invalid App Store profile: " + str(error))
