import os
import socket
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
HOME_SCRIPT = PROJECT / "system/rootfs/usr/lib/pivista/home.sh"


class HomeScriptTests(unittest.TestCase):
    def test_sends_home_to_launcher_socket(self):
        if not HOME_SCRIPT.is_file():
            self.skipTest("home.sh not present")

        with tempfile.TemporaryDirectory() as runtime:
            socket_path = os.path.join(runtime, "pivista-home.sock")
            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            server.bind(socket_path)
            server.listen(1)
            server.settimeout(5)
            received = []
            failure = []

            def accept():
                try:
                    connection, _ = server.accept()
                    with connection:
                        received.append(connection.recv(64))
                except OSError as exc:  # pragma: no cover - diagnostic path
                    failure.append(exc)

            thread = threading.Thread(target=accept, daemon=True)
            thread.start()
            env = dict(os.environ)
            env["XDG_RUNTIME_DIR"] = runtime
            env.pop("SWAYSOCK", None)
            completed = subprocess.run(
                ["bash", str(HOME_SCRIPT)],
                env=env,
                capture_output=True,
                timeout=10,
            )
            thread.join(6)
            server.close()

            self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors="replace"))
            self.assertFalse(failure, failure)
            self.assertEqual(received, [b"home\n"])


if __name__ == "__main__":
    unittest.main()
