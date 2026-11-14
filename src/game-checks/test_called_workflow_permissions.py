"""Tests called_workflow_permissions.py (#2352) on small workflows: a caller granting less than a
called job asks for is refused, by scope and level, a job without its own permissions has its
workflow's, and a form the reader can't read raises rather than passing.

    uv run --locked --package khovax-game-checks src/game-checks/test_called_workflow_permissions.py
"""

import unittest

from called_workflow_permissions import problems, read

CALLED = """name: called
on:
  workflow_call:
permissions:
  contents: read

jobs:
  plain:
    runs-on: ubuntu-26.04
    steps:
      - run: echo "permissions: none"
  deploy:
    # Its own permissions.
    permissions:
      contents: read
      deployments: read  # which build is live
      pages: write
    steps:
      - uses: ./.github/actions/setup-uv
"""

CALLER = """name: caller
permissions:
  contents: read
jobs:
  check:
    runs-on: ubuntu-26.04
  ci:
    needs: check
    uses: ./.github/workflows/called.yml
    permissions:
      contents: write
{extra}
"""


def found(extra: str) -> list[tuple[str, str]]:
    return problems({"called.yml": read(CALLED), "caller.yml": read(CALLER.format(extra=extra))})


class CalledWorkflowPermissionsTest(unittest.TestCase):
    def test_reads_jobs_permissions_and_calls(self) -> None:
        called = read(CALLED)
        self.assertEqual(called.permissions, {"contents": "read"})
        self.assertEqual(called.jobs["plain"], (None, None))
        self.assertEqual(
            called.jobs["deploy"], ({"contents": "read", "deployments": "read", "pages": "write"}, None)
        )
        self.assertEqual(read(CALLER.format(extra="")).jobs["ci"], ({"contents": "write"}, "called.yml"))

    def test_granting_every_scope_passes(self) -> None:
        self.assertEqual(found("      deployments: write\n      pages: write"), [])

    def test_a_missing_scope_is_named(self) -> None:
        self.assertEqual(
            found("      pages: write"),
            [
                (
                    "caller.yml",
                    "job ci calls called.yml, whose job deploy asks for more than it grants: "
                    "deployments: read (granted none)",
                )
            ],
        )

    def test_a_lower_level_is_named(self) -> None:
        listed = found("      deployments: read\n      pages: read")
        self.assertIn("pages: write (granted read)", listed[0][1])

    def test_a_caller_job_without_permissions_grants_its_workflows(self) -> None:
        caller = read(CALLER.format(extra="").replace("    permissions:\n      contents: write\n", ""))
        self.assertEqual(caller.jobs["ci"], (None, "called.yml"))
        listed = problems({"called.yml": read(CALLED), "caller.yml": caller})
        messages = [message for _name, message in listed]
        self.assertEqual(len(messages), 1)
        self.assertIn("deployments: read (granted none), pages: write (granted none)", messages[0])

    def test_a_caller_naming_no_permissions_is_refused(self) -> None:
        text = CALLER.format(extra="").replace("    permissions:\n      contents: write\n", "")
        caller = read(text.replace("permissions:\n  contents: read\n", ""))
        self.assertEqual(caller.permissions, None)
        listed = problems({"called.yml": read(CALLED), "caller.yml": caller})
        self.assertEqual(
            listed,
            [("caller.yml", "job ci calls called.yml without naming permissions: name them to check them")],
        )

    def test_a_called_job_without_any_permissions_gets_the_callers(self) -> None:
        called = read(CALLED.replace("permissions:\n  contents: read\n\n", ""))
        self.assertEqual(called.jobs["plain"], (None, None))
        listed = problems({"called.yml": called, "caller.yml": read(CALLER.format(extra=""))})
        self.assertEqual([message for _name, message in listed if "job plain" in message], [])
        self.assertEqual(len(listed), 1)

    def test_a_quoted_call_is_read(self) -> None:
        path = "./.github/workflows/called.yml"
        caller = read(CALLER.format(extra="").replace(f"uses: {path}", f'uses: "{path}"'))
        self.assertEqual(caller.jobs["ci"], ({"contents": "write"}, "called.yml"))

    def test_an_unknown_called_workflow_is_refused(self) -> None:
        listed = problems({"caller.yml": read(CALLER.format(extra=""))})
        self.assertEqual(listed, [("caller.yml", "job ci calls called.yml, which isn't in the workflows")])

    def test_a_form_it_cant_read_raises(self) -> None:
        with self.assertRaises(ValueError):
            read("permissions: read-all\n")
        with self.assertRaises(ValueError):
            read("jobs:\n  a:\n    permissions:\n      contents: maybe\n")


if __name__ == "__main__":
    unittest.main()
