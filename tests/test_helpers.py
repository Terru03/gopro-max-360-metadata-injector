"""Run real PowerShell helpers against disposable files and fake tool output.

No GoPro media, ExifTool, ffprobe, recycling, or live watch folders are used.
Set POWERSHELL_EXE to check another supported PowerShell runtime.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = os.environ.get("POWERSHELL_EXE") or shutil.which("powershell") or shutil.which("pwsh")


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


@unittest.skipUnless(POWERSHELL, "PowerShell is required")
class HelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gopro-helper-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.dest = self.root / "dest"
        self.source.mkdir()
        self.dest.mkdir()

    def run_ps(self, text):
        wrapper = self.root / "test-wrapper.ps1"
        wrapper.write_text(text, encoding="utf-8-sig")
        return subprocess.run([POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(wrapper)],
                              capture_output=True, text=True, timeout=20)

    def move_once(self, before=""):
        # Stop the existing loop at its first sleep; filesystem operations stay real.
        return self.run_ps(before + "\nfunction Start-Sleep { throw 'TEST_END' }\ntry { & " +
                           quote(ROOT / "safe_move.ps1") + " -SourceDir " + quote(self.source) +
                           " -DestDir " + quote(self.dest) +
                           " } catch { if ($_.Exception.Message -ne 'TEST_END') { throw } }\n")

    def test_move_ready_file_preserves_bytes(self):
        (self.source / "clip.mp4").write_bytes(b"synthetic video bytes")
        result = self.move_once()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.source / "clip.mp4").exists())
        self.assertEqual((self.dest / "clip.mp4").read_bytes(), b"synthetic video bytes")

    def test_move_never_overwrites_existing_destination(self):
        (self.source / "clip.mp4").write_bytes(b"new source")
        (self.dest / "clip.mp4").write_bytes(b"existing destination")
        self.move_once()
        self.assertEqual((self.dest / "clip.mp4").read_bytes(), b"existing destination")
        self.assertEqual((self.source / "clip.mp4").read_bytes(), b"new source")

    def test_move_treats_brackets_as_literal_filename(self):
        (self.source / "clip[1].mp4").write_bytes(b"literal filename")
        self.move_once()
        self.assertTrue((self.dest / "clip[1].mp4").exists())
        self.assertEqual((self.dest / "clip[1].mp4").read_bytes(), b"literal filename")
        self.assertFalse((self.source / "clip[1].mp4").exists())

    def test_move_skips_locked_file(self):
        source = self.source / "locked.mp4"
        source.write_bytes(b"still writing")
        self.move_once("$lock = [IO.File]::Open(" + quote(source) + ", 'Open', 'ReadWrite', 'None')")
        self.assertEqual(source.read_bytes(), b"still writing")
        self.assertFalse((self.dest / "locked.mp4").exists())

    def test_move_skips_jpg(self):
        (self.source / "photo.JPG").write_bytes(b"photo")
        self.move_once()
        self.assertTrue((self.source / "photo.JPG").exists())
        self.assertEqual(list(self.dest.iterdir()), [])

    def probe(self, reference=None, candidate=None, spherical=False, fail=False):
        default = {"codec_name": "hevc", "width": 4096, "height": 2048, "r_frame_rate": "30000/1001",
                   "duration": "10.000", "nb_frames": "300"}
        fixture = self.root / "probe.json"
        fixture.write_text(json.dumps([{"streams": [{**default, **(reference or {})}]},
                                       {"streams": [{**default, **(candidate or {})}]}]), encoding="utf-8")
        for name in ("reference.mp4", "candidate.mp4"):
            (self.root / name).write_bytes(b"synthetic probe target")
        return self.run_ps("$global:fixtures = Get-Content -Raw -LiteralPath " + quote(fixture) +
                           " | ConvertFrom-Json\n$global:probeIndex = 0\nfunction ffprobe {\n" +
                           "$global:LASTEXITCODE = " + ("1" if fail else "0") +
                           "\n$global:fixtures[$global:probeIndex] | ConvertTo-Json -Depth 10\n$global:probeIndex++\n}\n& " +
                           quote(ROOT / "verify_video_integrity.ps1") + " -Reference " + quote(self.root / "reference.mp4") +
                           " -Candidate " + quote(self.root / "candidate.mp4") + (" -RequireSpherical" if spherical else "") + "\nexit $LASTEXITCODE")

    def test_integrity_accepts_matching_video(self):
        result = self.probe()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("OK:", result.stdout)

    def test_integrity_rejects_changed_stream_properties(self):
        for change in ({"codec_name": "h264"}, {"width": 1920}, {"r_frame_rate": "25/1"},
                       {"duration": "10.2"}, {"nb_frames": "290"}):
            with self.subTest(change=change):
                result = self.probe(candidate=change)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_integrity_requires_spherical_only_when_requested(self):
        self.assertEqual(self.probe(spherical=True).returncode, 2)
        metadata = {"side_data_list": [{"side_data_type": "Spherical Mapping", "projection": "equirectangular"}]}
        self.assertEqual(self.probe(candidate=metadata, spherical=True).returncode, 0)

    def test_integrity_rejects_probe_failure(self):
        self.assertEqual(self.probe(fail=True).returncode, 3)

    def test_integrity_rejects_nonfinite_duration(self):
        for duration in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(duration=duration):
                self.assertEqual(self.probe(candidate={"duration": duration}).returncode, 3)

    def test_integrity_accepts_unknown_frame_count_with_other_checks(self):
        self.assertEqual(self.probe(candidate={"nb_frames": "N/A"}).returncode, 0)

    def gps(self, lines, culture="en-US", tool_exit=0, filename="telemetry.360"):
        source = self.root / filename
        source.write_bytes(b"synthetic telemetry target")
        fake = self.root / "gps-output.txt"
        fake.write_text("\n".join(lines), encoding="utf-8")
        return self.run_ps("[Threading.Thread]::CurrentThread.CurrentCulture = " + quote(culture) +
                           "\nfunction exiftool { $global:LASTEXITCODE = " + str(tool_exit) +
                           "; Get-Content -LiteralPath " + quote(fake) + " }\n& " +
                           quote(ROOT / "extract_first_locked_gps.ps1") + " -InputFile " + quote(source) + "\nexit $LASTEXITCODE")

    def test_gps_uses_first_3d_fix(self):
        result = self.gps(["2,12,24,0", "3,-12.25,24.5,-3.125", "3,44,55,10"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["-12.25,24.5,-3.125", "-12.25+024.5-3.125/"])

    def test_gps_no_lock_returns_failure(self):
        result = self.gps(["2,12,24,0"])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.strip(), "")

    def test_gps_accepts_equator_and_literal_filename(self):
        result = self.gps(["3,0,10,5"], filename="telemetry[1].360")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["0,10,5", "+00+010+5/"])

    def test_gps_output_uses_invariant_decimal_separator(self):
        result = self.gps(["3,4.25,-12.5,3.75"], culture="ro-RO")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["4.25,-12.5,3.75", "+04.25-012.5+3.75/"])

    def test_gps_skips_invalid_samples(self):
        result = self.gps(["3,nope,24,0", "3,91,24,0", "3,12,181,0", "3,NaN,24,0", "3,12,24,Infinity", "3,12,24,5"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["12,24,5", "+12+024+5/"])

    def test_gps_tool_failure_never_accepts_partial_output(self):
        result = self.gps(["3,12,24,5"], tool_exit=1)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
