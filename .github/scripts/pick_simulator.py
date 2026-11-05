#!/usr/bin/env python3
"""Pick an available iPhone simulator, preferring the iOS 26 runtime."""
import json
import subprocess
import sys

PREFS = ["iPhone 17 Pro", "iPhone 17", "iPhone 16 Pro", "iPhone 16", "iPhone 15 Pro"]


def main() -> int:
    data = json.loads(
        subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"])
    )

    for runtime, devices in data["devices"].items():
        if "iOS-26" not in runtime:
            continue
        available = [(d["name"], d["udid"]) for d in devices if d.get("isAvailable")]
        for pref in PREFS:
            for name, udid in available:
                if name.startswith(pref):
                    print(udid)
                    return 0

    for devices in data["devices"].values():
        for device in devices:
            if device.get("isAvailable") and "iPhone" in device["name"]:
                print(device["udid"])
                return 0

    print("no iPhone simulator found", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
