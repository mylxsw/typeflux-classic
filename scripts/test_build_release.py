"""Exercise the release build script with stubbed Apple tools, without a real build."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BuildReleaseTests(unittest.TestCase):
    def run_release(self, build_system_flag=True, help_status=0, sdk="26.5", otool_status=0, arch="native"):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scripts = root / "scripts"
            scripts.mkdir()
            shutil.copyfile(ROOT / "scripts/build_release.sh", scripts / "build_release.sh")
            audit = scripts / "audit_macho_minos.sh"
            audit.write_text("#!/bin/sh\nexit 0\n")
            audit.chmod(0o755)
            shutil.copytree(ROOT / "app", root / "app")
            products = root / "products"
            (products / "Typeflux_Typeflux.bundle").mkdir(parents=True)
            (products / "Typeflux").write_text("fixture")
            tools = root / "tools"
            tools.mkdir()
            for name, text in {
                "swift": """#!/bin/sh
case "$*" in
  *--help*) printf '%s\\n' "$FIXTURE_HELP"; exit "$FIXTURE_HELP_STATUS";;
esac
echo "$*" >> "$FIXTURE_SWIFT_LOG"
case "$*" in *--show-bin-path*) echo "$FIXTURE_PRODUCTS";; esac
""",
                "otool": """#!/bin/sh
[ "$1 $2 $3" = "-arch all -l" ] || exit 2
[ "$FIXTURE_OTOOL_STATUS" = 0 ] || exit "$FIXTURE_OTOOL_STATUS"
for sdk in $FIXTURE_SDK; do printf ' platform 1\\n    minos 13.0\\n      sdk %s\\n' "$sdk"; done
""",
                "lipo": "#!/bin/sh\necho arm64 x86_64\n",
                "ditto": "#!/bin/sh\nexit 0\n",
                "codesign": """#!/bin/sh
echo "$*" >> "$FIXTURE_SIGN_LOG"
""",
            }.items():
                path = tools / name
                path.write_text(text)
                path.chmod(0o755)
            env = {key: value for key, value in os.environ.items() if not key.startswith("TYPEFLUX_")}
            env.update(PATH=str(tools) + os.pathsep + env["PATH"],
                       TYPEFLUX_RELEASE_VARIANT="app-only", TYPEFLUX_RELEASE_ARCH=arch,
                       TYPEFLUX_CODESIGN_IDENTITY="Developer ID Application: fixture",
                       FIXTURE_HELP="  --build-system <build-system>" if build_system_flag else "  --arch <arch>",
                       FIXTURE_HELP_STATUS=str(help_status), FIXTURE_SDK=sdk,
                       FIXTURE_OTOOL_STATUS=str(otool_status), FIXTURE_PRODUCTS=str(products),
                       FIXTURE_SWIFT_LOG=str(root / "swift.log"), FIXTURE_SIGN_LOG=str(root / "sign.log"))
            result = subprocess.run(["bash", str(scripts / "build_release.sh")], env=env,
                                    capture_output=True, text=True, timeout=30)
            lines = lambda name: (root / name).read_text().splitlines() if (root / name).exists() else []
            return result, lines("swift.log"), lines("sign.log")

    def test_native_build_system_is_used_for_the_build_and_its_bin_path(self):
        for arch in ["native", "arm64", "x86_64"]:
            with self.subTest(arch=arch):
                result, builds, signatures = self.run_release(arch=arch)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(builds), 2)
                for call in builds:
                    self.assertIn("--build-system native", call)
                self.assertIn("Build system: native", result.stdout)
                self.assertIn("Main executable SDK: 26.5", result.stdout)
                self.assertTrue(signatures)

    def test_toolchain_without_build_system_flag_builds_with_its_default(self):
        for help_status in [0, 1]:
            with self.subTest(help_status=help_status):
                result, builds, _ = self.run_release(build_system_flag=False, help_status=help_status)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(builds), 2)
                for call in builds:
                    self.assertNotIn("--build-system", call)
                self.assertIn("toolchain default", result.stdout)

    def test_supported_sdk_versions_pass(self):
        for sdk in ["26", "26.0", "27.2", "26.5 27.2"]:
            with self.subTest(sdk=sdk):
                result, _, _ = self.run_release(sdk=sdk)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"Main executable SDK: {sdk}\n", result.stdout)

    def test_old_or_unreadable_sdk_stops_before_signing(self):
        cases = [({"sdk": "13.0"}, "has SDK 13.0"), ({"sdk": "25.9"}, "has SDK 25.9"),
                 ({"sdk": "27.2 13.0"}, "has SDK 13.0"), ({"sdk": "n/a"}, "has SDK n/a"),
                 ({"sdk": ""}, "no SDK version found"), ({"otool_status": 1}, "cannot read the load commands")]
        for kwargs, message in cases:
            with self.subTest(kwargs=kwargs):
                result, _, signatures = self.run_release(**kwargs)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn(message, result.stderr)
                self.assertEqual(signatures, [])
                self.assertNotIn("Release archive created", result.stdout)


if __name__ == "__main__":
    unittest.main()
