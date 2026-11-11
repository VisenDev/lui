"""Test toolchain setup orchestration without downloading or compiling tools."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ToolchainTests(unittest.TestCase):
    def test_download_reuse_and_overrides(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            shutil.copyfile(ROOT / "scripts/build-ecl-toolchain.sh",
                            root / "scripts/build-ecl-toolchain.sh")
            tools = root / "bin"
            tools.mkdir()
            log = root / "calls"
            fake = tools / "fake"
            fake.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(name + " " + " ".join(args) + "\\n")
if name == "git":
    dest = pathlib.Path(args[1])
    action = args[2]
    if action == "init":
        (dest / ".git").mkdir()
    if action == "rev-parse":
        sys.exit(0 if (dest / ".git/ready").exists() else 1)
    if action == "checkout":
        (dest / ".git/ready").touch()
        if dest.name == "emsdk":
            (dest / "emsdk").symlink_to(pathlib.Path(sys.argv[0]).resolve())
            (dest / "emsdk_env.sh").write_text(":\\n")
        else:
            (dest / "src/gmp").mkdir(parents=True, exist_ok=True)
            configure = dest / "src/configure"
            if not configure.exists():
                configure.symlink_to(pathlib.Path(sys.argv[0]).resolve())
            for file in ("gmp/config.guess",):
                script = dest / "src" / file
                script.write_text("#!/bin/sh\\necho fixture\\n")
                script.chmod(0o755)
''')
            fake.chmod(0o755)
            for name in ("git", "make", "emmake", "emconfigure", "cc", "c++"):
                (tools / name).symlink_to(fake)
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       CALL_LOG=str(log))
            for name in ("ECL_SOURCE", "EMSDK_ENV"):
                env.pop(name, None)

            def run():
                subprocess.run(["bash", "scripts/build-ecl-toolchain.sh"],
                               cwd=root, env=env, check=True, capture_output=True)
                calls = log.read_text()
                log.write_text("")
                return calls

            first = run()
            self.assertIn("855f93431bab0e972fad816a8e0437afdc1de245", first)
            self.assertIn("1693ce7359fc9694f198694f902a2cc061239b86", first)
            self.assertIn("emsdk install 4.0.12", first)
            self.assertIn("emsdk activate 4.0.12", first)
            self.assertIn("--disable-threads", first)
            self.assertIn("--host=wasm32-unknown-emscripten", first)
            second = run()
            self.assertNotIn(" fetch ", second)
            self.assertNotIn(" checkout ", second)
            # A failed initial fetch can be retried without replacing the tree.
            (root / "build/deps/ecl-source/.git/ready").unlink()
            self.assertIn(" fetch ", run())
            env["ECL_SOURCE"] = str(root / "build/deps/ecl-source")
            env["EMSDK_ENV"] = str(root / "build/deps/emsdk/emsdk_env.sh")
            overridden = run()
            self.assertNotIn("git ", overridden)
            self.assertNotIn("emsdk install", overridden)


if __name__ == "__main__":
    unittest.main(verbosity=2)
