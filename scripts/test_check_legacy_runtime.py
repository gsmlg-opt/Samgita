import unittest

from check_legacy_runtime import violations


class LegacyRuntimeScanTest(unittest.TestCase):
    def test_intentional_history_and_negative_assertions(self):
        self.assertEqual([], violations("preservation_test.exs", "# pgvector history is retained\n"))
        self.assertEqual([], violations("consumer_test.exs",
                                       "refute app in [\n :samgita_provider, :samgita_memory\n]\n"))

    def test_runtime_and_test_integration_still_fail(self):
        for path in ["lib/example.ex", "test/example_test.exs", "priv/repo/migrations/expand.exs", "mix.exs"]:
            for code in ["alias SamgitaProvider\n", "Horde.Registry.start_link([])\n",
                         "{:samgita_memory, in_umbrella: true}\n", 'System.get_env("CLAUDE_COMMAND")\n']:
                self.assertEqual(1, len(violations(path, code)))

    def test_negative_context_cannot_hide_an_integration(self):
        code = "refute app in [:samgita_memory]\nSamgitaMemory.start_link([])\n"
        self.assertEqual(1, len(violations("consumer_test.exs", code)))
        self.assertEqual(2, len(violations("runtime.ex", code)))


if __name__ == "__main__":
    unittest.main()
