"""Fault-injection checks using real journals and WindowServer state.

Run only after quitting Scrollapp:
python3 scripts/verify_cursor_recovery.py --global HELPER PAYLOAD_DIRECTORY
The directory must contain frog.plist. Original backups are preserved in it.
"""
import copy
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess
import sys

from verify_cursor_service import response, send


def main():
    assert len(sys.argv) == 4 and sys.argv[1] == "--global", __doc__
    helper, directory = sys.argv[2], pathlib.Path(sys.argv[3])
    journal = directory / "fault-recovery.plist"
    payload = directory / "frog.plist"
    results = []
    baseline = None
    child = None

    def launch():
        return subprocess.Popen([helper, str(journal), str(os.getpid())],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def stop():
        nonlocal child
        child.stdin.close()
        child.wait(timeout=15)
        child = None

    try:
        child = launch()
        assert response(child)["ready"]
        assert send(child, action="apply", path=str(payload))["ok"]
        baseline = plistlib.loads(journal.read_bytes())
        (directory / "fault-original-baseline.plist").write_bytes(journal.read_bytes())
        child.kill()
        child.wait(timeout=10)
        child = None

        # CoreCursorCopyImages describes a cache Scrollapp never wrote directly.
        # A display or accessibility change may regenerate one native descriptor.
        drifted = copy.deepcopy(baseline)
        index = next(iter(drifted["CoreImages"]))
        drifted["CoreImages"][index]["HotSpotX"] += 0.25
        journal.write_bytes(plistlib.dumps(drifted))
        child = launch()
        ready = response(child)
        assert ready["ok"] and ready["ready"] and not ready["recoveryRequired"], ready
        assert f"core.{index}" in ready["warnings"] and ready["archive"], ready
        assert not journal.exists()
        archive = directory / "recovery-archives" / ready["archive"]
        assert plistlib.loads(archive.read_bytes()) == drifted
        results.append({"test": "core-cache-drift-recovers-with-archive", **ready})
        stop()

        # Unwritable original metadata is a genuine named-entry failure.
        broken = copy.deepcopy(baseline)
        name = "com.apple.coregraphics.Arrow"
        broken["Names"][name]["Original"]["FrameCount"] = 0
        journal.write_bytes(plistlib.dumps(broken))
        digest = hashlib.sha256(journal.read_bytes()).hexdigest()
        child = launch()
        paused = response(child)
        assert not paused["ok"] and paused["recoveryRequired"], paused
        assert child.poll() is None
        for action in ["apply", "system"]:
            result = send(child, action=action, path=str(payload), scale=1)
            assert not result["ok"] and result["recoveryRequired"], result
        assert hashlib.sha256(journal.read_bytes()).hexdigest() == digest
        retry = send(child, action="reset")
        assert not retry["ok"] and retry["recoveryRequired"]
        diagnostics = send(child, action="diagnostics")
        assert diagnostics["hasBackup"] and diagnostics["history"]["events"], diagnostics
        fallback = send(child, action="nativeReset")
        assert fallback["ok"] and not fallback["recoveryRequired"], fallback
        archive = directory / "recovery-archives" / fallback["archive"]
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == digest
        assert not journal.exists()
        assert send(child, action="apply", path=str(payload))["ok"]
        assert send(child, action="reset")["ok"]
        results.append({"test": "invalid-original-paused-retry-reset-and-reapply", **fallback})
        stop()

        # A structurally valid but changed named descriptor must not be dismissed
        # as cache drift. Non-float-exact metadata exposes readback mismatch.
        broken = copy.deepcopy(baseline)
        broken["Names"][name]["Original"]["HotSpotX"] += 0.123456789
        journal.write_bytes(plistlib.dumps(broken))
        child = launch()
        paused = response(child)
        assert paused["error"] == "restoreFailed" and paused["recoveryRequired"], paused
        assert any(item["name"] == name for item in paused["details"]), paused
        assert not send(child, action="apply", path=str(payload))["ok"]
        assert send(child, action="nativeReset")["ok"]
        results.append({"test": "named-readback-mismatch-remains-recovery-required", **paused})
        stop()

        journal.write_bytes(b"not a valid property list")
        raw = journal.read_bytes()
        child = launch()
        paused = response(child)
        assert paused["error"] == "invalidBackup" and paused["recoveryRequired"], paused
        assert journal.read_bytes() == raw
        fallback = send(child, action="nativeReset")
        assert fallback["ok"] and not journal.exists()
        archive = directory / "recovery-archives" / fallback["archive"]
        assert archive.read_bytes() == raw
        results.append({"test": "unreadable-backup-preserved-byte-for-byte", **fallback})
        stop()
    finally:
        if child is not None:
            child.stdin.close()
            child.wait(timeout=15)
        # Fault tests explicitly exercise a native reset. Restore the original
        # baseline afterwards so other cursor customization is also preserved.
        if baseline is not None:
            if journal.exists():
                saved = directory / "failed-test-journal.plist"
                saved.write_bytes(journal.read_bytes())
            journal.write_bytes(plistlib.dumps(baseline))
            cleanup = launch()
            restored = response(cleanup)
            cleanup.stdin.close()
            cleanup.wait(timeout=15)
            assert restored["ok"] and restored["ready"], restored
    path = directory / "recovery-verification.json"
    path.write_text(json.dumps(results, indent=2))
    print(json.dumps({"checks": len(results), "passed": True, "results": str(path)}, indent=2))


if __name__ == "__main__":
    main()
