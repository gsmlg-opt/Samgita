"""Functional regression for an interrupted owned fixture connection."""
import json
from pathlib import Path
import shutil
import socket
import tempfile
import threading
import unittest

from git_marketplace_fixture import GitFixture


class GitFixtureLifecycleTest(unittest.TestCase):
    def test_pending_connection_closes_and_consumes_an_attempt(self):
        with tempfile.TemporaryDirectory(prefix="samgita-git-fixture-close-") as directory:
            root = Path(directory)
            repository = root / "fixture.git"
            # No Git request is sent in this lifecycle case. Native integration
            # separately uses a real repository and the actual HTTP backend.
            (repository / ".git").mkdir(parents=True)
            journal = root / "journal.json"
            fixture = GitFixture(repository, shutil.which("git"), journal)
            accepted = threading.Event()
            closed = threading.Event()
            errors = []
            original_accept = fixture.server.get_request

            def observed_accept():
                result = original_accept()
                accepted.set()
                return result

            def close_fixture():
                try:
                    fixture.close()
                except BaseException as error:
                    errors.append(error)
                finally:
                    closed.set()

            fixture.server.get_request = observed_accept
            fixture.thread.start()
            closer = threading.Thread(target=close_fixture, daemon=True)
            client = None
            try:
                client = socket.create_connection(
                    ("127.0.0.1", fixture.server.server_port), timeout=1
                )
                self.assertTrue(accepted.wait(1), "owned connection never accepted")
                closer.start()
                bounded = closed.wait(3)
            finally:
                if client is not None:
                    client.close()
                if closer.ident is None:
                    closer.start()
                closer.join(timeout=4)
                fixture.thread.join(timeout=1)
            self.assertFalse(closer.is_alive())
            self.assertFalse(fixture.thread.is_alive())
            self.assertEqual(errors, [])
            self.assertTrue(bounded, "fixture close blocked on an unfinished connection")
            self.assertEqual(json.loads(journal.read_text()), {
                "failure": None, "attempts": 1, "entries": []
            })


if __name__ == "__main__":
    unittest.main()
