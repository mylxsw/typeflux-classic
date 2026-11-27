import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class AccountSyncTests(unittest.TestCase):
    def test_updates_and_checks_an_upstream_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            upstream = root / "upstream"
            upstream.mkdir()
            scripts = root / "scripts"
            scripts.mkdir()
            script = scripts / "sync_account_module.sh"
            shutil.copy(Path(__file__).with_name(script.name), script)
            env = dict(os.environ, TYPEFLUX_UPSTREAM_REPO=str(upstream))

            def git(*args):
                subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.org",
                                *args], cwd=upstream, check=True, capture_output=True)

            def sync(arg):
                return subprocess.run([str(script), arg], cwd=root, env=env, capture_output=True)

            git("init")
            first = Path("Sources/Typeflux/Auth/First.swift")
            second = first.with_name("Second.swift")
            (upstream / first).parent.mkdir(parents=True)
            (upstream / "scripts").mkdir()
            manifest = upstream / "scripts/account_module_files.txt"
            for target in (first, second):
                manifest.write_text(f"{target}\n")
                (upstream / target).write_bytes(b"// preserved\r\n")
                git("add", ".")
                git("commit", "-m", str(target))
                self.assertEqual(sync("HEAD").returncode, 0)
                self.assertEqual((root / target).read_bytes(), b"// preserved\r\n")
                self.assertEqual(sync("--check").returncode, 0)
            self.assertFalse((root / first).exists())
            (root / second).write_text("// changed\n")
            self.assertNotEqual(sync("--check").returncode, 0)


if __name__ == "__main__":
    unittest.main()
