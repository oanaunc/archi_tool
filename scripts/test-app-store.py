#!/usr/bin/env python3
"""Regression checks for rejecting the wrong signing profile before producing a store installer."""
import copy
import datetime
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("profile_check", Path(__file__).with_name("app-store-profile.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StoreProfileTests(unittest.TestCase):
    def setUp(self):
        self.info = {"CFBundleIdentifier": "com.oanarina.architool"}
        self.entitlements = {"com.apple.security.app-sandbox": True}
        self.profile = {
            "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=30),
            "Platform": ["OSX"], "ApplicationIdentifierPrefix": ["PREFIX"], "TeamIdentifier": ["TEAM"],
            "DeveloperCertificates": [b"authorized certificate"],
            "Entitlements": {"com.apple.application-identifier": "PREFIX.com.oanarina.architool", "com.apple.developer.team-identifier": "TEAM"},
        }

    def test_store_profile_merges_team_and_app_identifier_without_losing_sandbox(self):
        result = module.prepare(self.profile, self.info, self.entitlements, b"authorized certificate")
        self.assertTrue(result["com.apple.security.app-sandbox"])
        self.assertEqual(result["com.apple.developer.team-identifier"], "TEAM")
        self.assertNotIn("com.apple.developer.team-identifier", self.entitlements)

    def test_rejects_development_and_direct_distribution(self):
        for key, value in (("ProvisionedDevices", ["a-device"]), ("ProvisionsAllDevices", True)):
            profile = copy.deepcopy(self.profile)
            profile[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                module.prepare(profile, self.info, self.entitlements)

    def test_rejects_expired_profile(self):
        self.profile["ExpirationDate"] = datetime.datetime.now() - datetime.timedelta(days=1)
        with self.assertRaises(ValueError): module.prepare(self.profile, self.info, self.entitlements)

    def test_rejects_wrong_bundle_and_wildcard(self):
        for identifier in ("PREFIX.other.app", "PREFIX.*"):
            self.profile["Entitlements"]["com.apple.application-identifier"] = identifier
            with self.subTest(identifier=identifier), self.assertRaises(ValueError):
                module.prepare(self.profile, self.info, self.entitlements)

    def test_rejects_wrong_platform(self):
        self.profile["Platform"] = ["iOS"]
        with self.assertRaises(ValueError): module.prepare(self.profile, self.info, self.entitlements)

    def test_rejects_debug_entitlement(self):
        for key in ("get-task-allow", "com.apple.security.get-task-allow"):
            profile = copy.deepcopy(self.profile)
            profile["Entitlements"][key] = True
            with self.subTest(key=key), self.assertRaises(ValueError): module.prepare(profile, self.info, self.entitlements)

    def test_rejects_team_mismatch(self):
        self.profile["TeamIdentifier"] = ["OTHER"]
        with self.assertRaises(ValueError): module.prepare(self.profile, self.info, self.entitlements)

    def test_rejects_certificate_not_in_profile(self):
        with self.assertRaises(ValueError): module.prepare(self.profile, self.info, self.entitlements, b"different certificate")


if __name__ == "__main__": unittest.main()
