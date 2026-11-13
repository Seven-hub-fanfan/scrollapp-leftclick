"""Real WindowServer integration checks. Temporarily changes global cursors.

Usage: python3 scripts/verify_cursor_service.py --global HELPER PAYLOAD_DIRECTORY
PAYLOAD_DIRECTORY must contain frog.plist.
All sessions restore on reset, EOF or owner death; results are saved there.
"""
import json
import os
import pathlib
import plistlib
import signal
import subprocess
import sys
import struct


def response(service):
    line = service.stdout.readline()
    if not line:
        raise AssertionError(f"Service exited: {service.poll()}")
    return json.loads(line)


def send(service, **command):
    service.stdin.write(json.dumps(command) + "\n")
    service.stdin.flush()
    return response(service)


def main():
    assert len(sys.argv) == 4 and sys.argv[1] == "--global", __doc__
    helper, directory = sys.argv[2], pathlib.Path(sys.argv[3])
    journal = directory / "test-recovery.plist"
    results = []
    service = subprocess.Popen([helper, str(journal), str(os.getpid())],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    assert response(service)["ready"]
    try:
        # Malformed images, invalid hotspot, reserved semantic state: reject
        # before making a backup or changing any system cursor.
        source = plistlib.loads((directory / "frog.plist").read_bytes())
        for kind in ["hotspot", "image", "reserved", "fallback-extra-fields"]:
            bad = plistlib.loads(plistlib.dumps(source))
            entry = bad["Cursors"]["com.apple.coregraphics.Arrow"]
            if kind == "hotspot":
                entry["HotSpotX"] = 100
            elif kind == "image":
                entry["Representations"] = [b"broken", b"broken"]
            elif kind == "reserved":
                bad["Cursors"]["com.apple.coregraphics.Wait"] = entry
            else:
                bad["Cursors"]["com.apple.coregraphics.Arrow"] = {
                    "RestoreOriginal": True, "Unexpected": True}
            path = directory / f"invalid-{kind}.plist"
            path.write_bytes(plistlib.dumps(bad))
            result = send(service, action="apply", path=str(path))
            assert not result["ok"] and not journal.exists(), result
            results.append({"test": f"reject-{kind}", **result})

        for scale in [0.4, 8.1]:
            result = send(service, action="apply", path=str(directory / "frog.plist"), scale=scale)
            assert not result["ok"] and not journal.exists(), result
            results.append({"test": f"reject-scale-{scale}", **result})

        for theme in ["frog", "frog"]:
            result = send(service, action="apply", path=str(directory / f"{theme}.plist"))
            assert result["ok"], result
            verified = send(service, action="verify")
            assert verified["ok"] and verified["verified"] == result["applied"], verified
            results.append({"test": f"apply-{theme}", **result, "readback": verified})
        if (directory / "xiaoqi.plist").exists():
            baseline = plistlib.loads(journal.read_bytes())
            fallback_names = ["com.apple.cursor.42", "com.apple.cursor.43"]
            for scale in [1.0, 2.0, 4.0, 8.0]:
                result = send(service, action="apply", path=str(directory / "xiaoqi.plist"), scale=scale)
                assert result["ok"], result
                verified = send(service, action="verify", names=fallback_names)
                source_qi = plistlib.loads((directory / "xiaoqi.plist").read_bytes())["Cursors"]["com.apple.coregraphics.Arrow"]
                width = round(source_qi["PointsWide"] * scale)
                height = round(source_qi["PointsHigh"] * scale)
                expected_spot = [
                    struct.unpack("f", struct.pack("f", source_qi["HotSpotX"] * width / source_qi["PointsWide"]))[0],
                    struct.unpack("f", struct.pack("f", source_qi["HotSpotY"] * height / source_qi["PointsHigh"]))[0]]
                assert verified["ok"] and verified["arrowPoints"] == [width, height], verified
                assert verified["arrowHotSpot"] == expected_spot, verified
                if scale == 1:
                    for name in fallback_names:
                        original = dict(baseline["Names"][name].get("Original", {}))
                        original.pop("Representations", None)
                        assert verified["namedReadback"][name] == original, (name, verified)
                else:
                    assert send(service, action="system", names=list(source["Cursors"]), scale=scale)["ok"]
                    system = send(service, action="verify", names=fallback_names)
                    assert system["ok"] and system["namedReadback"] == verified["namedReadback"], (system, verified)
                results.append({"test": f"apply-xiaoqi-{scale}", **result, "readback": verified})
        baseline = plistlib.loads(journal.read_bytes())
        for theme, scale in [("frog", 0.5), ("frog", 1.5), ("frog", 3.0), ("frog", 4.0), ("frog", 6.0), ("frog", 8.0)]:
            result = send(service, action="apply", path=str(directory / f"{theme}.plist"),
                          scale=scale)
            assert result["ok"], result
            verified = send(service, action="verify")
            original = plistlib.loads((directory / f"{theme}.plist").read_bytes())["Cursors"]["com.apple.coregraphics.Arrow"]
            width = round(original["PointsWide"] * scale)
            height = round(original["PointsHigh"] * scale)
            assert verified["ok"] and verified["arrowPoints"] == [width, height], verified
            expected_spot = [original["HotSpotX"] * width / original["PointsWide"],
                             original["HotSpotY"] * height / original["PointsHigh"]]
            assert verified["arrowHotSpot"] == expected_spot, verified
            results.append({"test": f"resize-{theme}-{scale}", **result, "readback": verified})
        names = list(source["Cursors"])
        for scale in [0.5, 1.5, 3.0, 4.0, 6.0, 8.0]:
            result = send(service, action="system", names=names, scale=scale)
            assert result["ok"], result
            verified = send(service, action="verify")
            arrow = baseline["Names"]["com.apple.coregraphics.Arrow"]["Original"]
            assert verified["ok"] and verified["arrowPoints"] == [
                round(arrow["PointsWide"] * scale), round(arrow["PointsHigh"] * scale)], verified
            assert verified["legacyFrames"] == baseline["Names"]["com.apple.cursor.14"]["Original"]["FrameCount"], verified
            results.append({"test": f"resize-original-system-{scale}", **result, "readback": verified})
        result = send(service, action="reset")
        assert result["ok"] and result["coreVerified"] >= 40 and not journal.exists(), result
        results.append({"test": "reset-pixels-and-metadata", **result})

        # A second service cannot overwrite the recovery journal.
        assert send(service, action="apply", path=str(directory / "frog.plist"), scale=8)["ok"]
        rival = subprocess.run([helper, str(journal), str(os.getpid())],
                               input="", capture_output=True, text=True, timeout=10)
        result = json.loads(rival.stdout.splitlines()[0])
        assert result["error"] == "anotherInstance", result
        results.append({"test": "single-owner-lock", **result})
    finally:
        service.stdin.close()
        service.wait(timeout=15)
    result = plistlib.loads(pathlib.Path(str(journal) + ".result").read_bytes())
    assert result["ok"] and not journal.exists(), result
    results.append({"test": "EOF-recovery", **result})

    # Kill a disposable owner, rather than killing the helper. The helper must
    # recover independently after its owner disappears. Its inherited stdout
    # keeps communicate() open until the helper has finished restoring.
    crash_journal = directory / "crash-recovery.plist"
    owner_code = """
import subprocess,sys,os,json,signal
child=subprocess.Popen([sys.argv[1],sys.argv[2],str(os.getpid())],stdin=subprocess.PIPE)
child.stdin.write((json.dumps({"action":"apply","path":sys.argv[3]})+"\\n").encode())
child.stdin.flush()
signal.pause()
"""
    owner = subprocess.Popen([sys.executable, "-c", owner_code, helper, str(crash_journal),
                              str(directory / "frog.plist")], stdout=subprocess.PIPE, text=True)
    assert json.loads(owner.stdout.readline())["ready"]
    assert json.loads(owner.stdout.readline())["ok"]
    owner.kill()
    owner.communicate(timeout=15)
    result = plistlib.loads(pathlib.Path(str(crash_journal) + ".result").read_bytes())
    assert result["ok"] and result["restored"] >= 40 and not crash_journal.exists(), result
    results.append({"test": "SIGKILL-owner-recovery", **result})

    # A stopped service leaves a durable journal. A replacement must recover
    # it before emitting 'ready' or applying another skin.
    interrupted = directory / "interrupted-recovery.plist"
    child = subprocess.Popen([helper, str(interrupted), str(os.getpid())],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    assert response(child)["ready"]
    assert send(child, action="apply", path=str(directory / "frog.plist"), scale=8)["ok"]
    child.kill()
    child.wait(timeout=10)
    assert interrupted.exists()
    replacement = subprocess.Popen([helper, str(interrupted), str(os.getpid())],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    assert response(replacement)["ready"] and not interrupted.exists()
    replacement.stdin.close()
    replacement.wait(timeout=15)
    results.append({"test": "stale-journal-recovery", "ok": True})
    (directory / "service-verification.json").write_text(json.dumps(results, indent=2))
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
