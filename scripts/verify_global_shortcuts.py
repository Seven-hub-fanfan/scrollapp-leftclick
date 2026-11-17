#!/usr/bin/env python3
"""Native Carbon vs PID verification using actual Scrollapp delivery, no clipboard."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
import time


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def read(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def until(check, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.025)
    raise RuntimeError("Timed out waiting for the native receiver")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New external directory for binaries and evidence")
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if options.output:
        output = options.output.expanduser().resolve()
        if output == root or root in output.parents:
            parser.error("Use an external directory, not the source repository")
        output.mkdir(parents=True, exist_ok=False)
    else:
        output = Path(tempfile.mkdtemp(prefix="scrollapp-global-shortcuts-"))
    print(f"Evidence: {output}", flush=True)
    app = output / "ShortcutReceiver.app"
    executable = app / "Contents/MacOS/ShortcutFixture"
    executable.parent.mkdir(parents=True)
    sources = ["Scrollapp/ShortcutSequence.swift", "Scrollapp/ShortcutEngine.swift",
               "Scrollapp/Localization.swift", "scripts/verify_global_shortcuts.swift"]
    run(["xcrun", "swiftc", "-O", *[str(root / name) for name in sources], "-o", str(executable)])
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "com.scrollapp.shortcut-fixture",
        "CFBundleName": "ShortcutReceiver", "CFBundleExecutable": "ShortcutFixture",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
        "LSUIElement": False, "NSHighResolutionCapable": True,
    }))
    run(["codesign", "--force", "--sign", "-", str(app)])
    state = output / "receiver-state.json"
    old_front = subprocess.run([str(executable), "--frontmost"], capture_output=True, text=True)
    original_pid = None
    results = []
    checks = 0
    def count(events, kind, **filters):
        return sum(e.get("kind") == kind and all(e.get(k) == v for k, v in filters.items()) for e in events)

    try:
        run(["open", "-n", str(app), "--args", "--receiver", str(state)])
        ready = until(lambda: read(state))
        original_pid = ready.get("pid")
        if not ready.get("ready"):
            raise RuntimeError(f"Carbon registration failed/conflicted: {ready}")
        pid = ready["pid"]

        def send(label, scope, key, modifiers, amount=1, cancel=0, target=None):
            before = len(read(state)["events"])
            result_file = output / f"{label}.json"
            completed = subprocess.run([str(executable), "--send", str(target or pid),
                scope, str(key), str(modifiers), str(amount), str(cancel), str(result_file)],
                capture_output=True, text=True)
            result = read(result_file)
            if result is None:
                raise RuntimeError(f"Sender failed: {completed.stderr}")
            if result.get("blocked"):
                raise PermissionError("Test sender needs Accessibility, or Secure Input is active")
            if completed.returncode:
                raise RuntimeError(f"Sender exited {completed.returncode}: {completed.stderr}")
            # Bounded quiescence read: ensure delayed duplicate events are included.
            deadline = time.monotonic() + 0.25
            timeout = time.monotonic() + 5
            last = before
            while time.monotonic() < deadline:
                if time.monotonic() >= timeout:
                    raise RuntimeError("Receiver input did not become idle")
                current = len(read(state)["events"])
                if current != last:
                    last = current
                    deadline = time.monotonic() + 0.25
                time.sleep(0.025)
            events = read(state)["events"][before:]
            result["label"] = label
            result["events"] = events
            result["carbonDown"] = count(events, "carbon", down=True)
            result["carbonUp"] = count(events, "carbon", down=False)
            result["localDown"] = count(events, "local", type=10, key=key)
            result["localUp"] = count(events, "local", type=11, key=key)
            results.append(result)
            return result

        def expect(condition, message):
            nonlocal checks
            if not condition:
                raise AssertionError(message)
            checks += 1
            print(f"PASS {message}", flush=True)

        def probe(label):
            result = send(label, "systemHotkey", 64, 0)  # Unregistered F17.
            keys = [e for e in result["events"] if e.get("kind") == "local" and e.get("key") == 64]
            expect(result["submitted"] == 1 and result["localDown"] == result["localUp"] == 1
                   and all(e["modifiers"] == 0 for e in keys) and result["modifiersAfter"] == 0,
                   f"{label}: all modifiers released, next key unmodified")

        app_result = send("application-control", "application", 79, 11)
        expect(app_result["submitted"] == 1 and app_result["localDown"] == app_result["localUp"] == 1
               and app_result["carbonDown"] == app_result["carbonUp"] == 0,
               "PID route reaches the window but bypasses Carbon")
        probe("after-application")

        global_result = send("system-control", "systemHotkey", 79, 11)
        expect(global_result["submitted"] == 1 and global_result["carbonDown"] == global_result["carbonUp"] == 1
               and global_result["localDown"] == 0, "HID route triggers Carbon exactly once")
        probe("after-system")

        burst = send("system-burst", "systemHotkey", 79, 11, amount=12)
        expect(burst["submitted"] == burst["carbonDown"] == burst["carbonUp"] == 12 and burst["localDown"] == 0,
               "12 loop executions at 40 Hz produce exactly 12 hotkeys")
        probe("after-burst")
        for label, key, modifiers in [("all-modifiers", 80, 15), ("option", 35, 2)]:
            result = send(label, "systemHotkey", key, modifiers)
            expect(result["carbonDown"] == result["carbonUp"] == result["submitted"] == 1,
                   f"{label}: Carbon sees the intended chord")
            probe(f"after-{label}")
        ordinary = send("ordinary-key", "systemHotkey", 35, 11)
        expect(ordinary["submitted"] == ordinary["carbonDown"] == ordinary["carbonUp"] == 1
               and ordinary["localDown"] == 0, "Ordinary key triggers Carbon once")
        probe("after-ordinary-key")
        # Inject the foreground change at successive pre-key-down checks inside
        # the real delivery. No key-down may escape; cleanup uses real HID input.
        for cancel in [2, 3, 4, 5]:
            result = send(f"focus-cancel-{cancel}", "systemHotkey", 79, 11, cancel=cancel)
            expect(result["submitted"] == 0 and result["carbonDown"] == result["localDown"] == 0
                   and result["position"] == 0 and result["issue"] == "shortcuts.sendFailed",
                   f"focus-cancel-{cancel}: main key not submitted, progress retained")
            probe(f"after-cancel-{cancel}")
        wrong = send("stale-target", "systemHotkey", 79, 11, target=os.getpid())
        expect(wrong["submitted"] == 0 and not wrong["events"] and wrong["issue"] == "shortcuts.focusChanged",
               "Stale foreground PID causes no input")
        report = {"status": "PASS", "checks": checks, "results": results,
                  "limitations": ["Native Carbon dispatch only; ClipSlots paste workflow not exercised",
                                  "Mid-chord focus changes injected at production guard checks"]}
        (output / "report.json").write_text(json.dumps(report, indent=2))
        print(f"PASS — report: {output / 'report.json'}")
        return 0
    except PermissionError as error:
        (output / "report.json").write_text(json.dumps({"status": "BLOCKED", "reason": str(error), "results": results}, indent=2))
        print(f"BLOCKED: {error}\nEvidence: {output}", flush=True)
        return 3
    except Exception as error:
        (output / "report.json").write_text(json.dumps({"status": "FAIL", "reason": str(error), "results": results}, indent=2))
        print(f"FAIL: {error}\nEvidence: {output}", flush=True)
        return 1
    finally:
        if original_pid:
            try:
                os.kill(original_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if old_front.returncode == 0 and old_front.stdout.strip():
            subprocess.run(["open", "-b", old_front.stdout.strip()], capture_output=True)


if __name__ == "__main__":
    raise SystemExit(main())
