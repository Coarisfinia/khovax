"""The tracked files, as the checks read them."""

import subprocess


def git_files(*pathspecs: str) -> list[str]:
    """The tracked files the pathspecs match, as git lists them."""
    listing = subprocess.run(
        ["git", "ls-files", "-z", "--", *pathspecs], check=True, capture_output=True, text=True
    ).stdout
    return [path for path in listing.split("\0") if path]
