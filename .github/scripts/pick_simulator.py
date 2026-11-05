#!/usr/bin/env python3
"""Pick an available iPhone simulator on the newest iOS 26 runtime."""
import json
import re
import subprocess
import sys

PREFS = ["iPhone 17 Pro", "iPhone 17", "iPhone 16 Pro", "iPhone 16", "iPhone 15 Pro"]


def runtime_version(runtime_id: str):
    """Return a sortable version tuple for iOS runtimes, else None."""
    match = re.search(r"iOS-(\d+)-(\d+)", runtime_id)
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def main() -> int:
    data = json.loads(
        subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"])
    )

    ios26 = []
    for runtime, devices in data["devices"].items():
        version = runtime_version(runtime)
        if version and version[0] == 26:
            ios26.append((version, devices))
    ios26.sort(key=lambda item: item[0], reverse=True)

    for _version, devices in ios26:
        available = [(d["name"], d["udid"]) for d in devices if d.get("isAvailable")]
        for pref in PREFS:
            for name, udid in available:
                if name.startswith(pref):
                    print(udid)
                    return 0
        if available:
            print(available[0][1])
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
