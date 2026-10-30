# khovax

`khovax` is the internal codename for this project. The player-facing game name is separate and can change at any time without renaming the repo.

A top-down, real-time ARPG on a hex grid. You dominate monsters by walking rings around them, and your companions do the fighting. The simulation is fully deterministic and supports co-op. Built with Godot 4 and GDScript for web, mobile and PC.

Status: pre-production. **[Play the latest build in your browser](https://coarisfinia.github.io/khovax/)**

## Download

**[Download the newest build](https://github.com/Coarisfinia/khovax/releases)**: every push to `main` that
passes all checks makes a dev release there (the newest is at the top), with each build as its own
file:
- **Android:** the `…-android.apk`. Copy it to the phone and open it; see [On an Android phone](#on-an-android-phone).
- **Windows:** the `…-windows-x86_64.exe`. Run it; see [On Windows](#on-windows).
- **Linux:** the `…-linux.x86_64`. Run `chmod +x` on it, then start it.
- **Web:** play it at https://coarisfinia.github.io/khovax/. The release also carries the web build's
  files (`index.html` and its neighbours), which run when served from one folder.

## License

The code is released into the public domain under [the Unlicense](LICENSE). Assets added later keep their own licenses, next to them.

## Running it

Install the tools with [scoop](https://scoop.sh) (Windows). The project targets Godot 4.7.x, the version CI pins:

```sh
scoop bucket add extras
scoop install godot gh git uv
scoop install "$(cygpath -w "$PWD/tools/scoop/gdstyle.json")"
```

On macOS and Linux, install uv with [Homebrew](https://brew.sh): `brew install uv`. uv runs the Python
tooling in `packages/` (`uv run packages/<package>/<script>.py`, from the repository's root) with the
Python version `pyproject.toml` pins, which it downloads itself.

The game is the Godot project in `packages/game/`; every command below runs from the repository's
root and names it with `--path packages/game`.

`gdstyle` (the GDScript linter and formatter) isn't in a scoop bucket, so the repository carries its
manifest, and scoop needs its absolute path (the `cygpath` above is for Git Bash).

Open the project in Godot (`godot --path packages/game --editor`), or run it directly with
`godot --path packages/game`.

## On an Android phone

CI builds a debug APK on every pull request and every push to `main`:
1. Download the newest dev release's `…-android.apk` ([Download](#download)), or, for a pull
   request's build, the `khovax-debug-apk` artifact from its `ci` run on the Actions tab (a zip with
   `khovax.apk` inside; kept for 14 days).
2. Copy the APK to the phone and open it. Android asks once to allow installs from that source (the file manager or browser).

It's signed with a throwaway debug key made in each CI run. Installing a newer build over an older one fails because the keys differ, so uninstall the old one first.

## On Windows

CI builds the Windows version on every pull request and every push to `main`: the dev release's `…-windows-x86_64.exe` ([Download](#download)), or a pull request's `khovax-windows` artifact on its run's page (a zip with one `khovax.exe`; kept for 14 days). Run the `.exe`. It isn't signed, so Windows SmartScreen asks once: "More info", then "Run anyway".

## On Linux

CI builds the Linux version (x86_64) on every pull request and every push to `main`, as the `khovax-linux` artifact (kept for 14 days). Downloads drop the executable bit, so after downloading the dev release's `…-linux.x86_64` ([Download](#download)) or unzipping the artifact: `chmod +x <file> && ./<file>`.

## In a browser

**Play it at https://coarisfinia.github.io/khovax/**: every push to `main` that passes all checks deploys there.

CI builds the web version on every pull request and every push to `main`, as the `khovax-web` artifact (kept for 14 days). Browsers won't run it from a file, so serve the unzipped folder: `python -m http.server 8000` inside it, then open http://localhost:8000. It's single-threaded, so it needs no special server headers. Every release attaches the same build's files.

## Cutting a release

The dev releases (`v<next>-dev.<run number>`, prereleases) are made by CI on its own. A nightly
(`v<next>-nightly.<date>`, a kept prerelease with the same files) is made by
`.github/workflows/nightly.yml` every night at 02:00 UTC, or with its "Run workflow" button on the
Actions tab: it runs every check on `main` and publishes a passing build, and it skips a night when
`main` hasn't changed since the last nightly, or when today's is out already. A prod
release (`v<x.y.z>`, a full GitHub release with the desktop and web builds attached) is made with
the button of `.github/workflows/release.yml`: on the Actions tab, pick "release", then "Run
workflow" on `main`, and choose the part of the version to bump (`patch`, `minor` or `major`). It
bumps the last prod release's version (the first prod release is `config/version` itself), checks
that `main`'s newest commit passed CI and that the tag is new, builds everything with the version
stamped in, and only then makes the tag and publishes the release. `config/version` is never
bumped by hand. Tick "Dry run" to do all of it but the release itself: the run's summary shows the
version, the notes and the files it would publish. The release notes list the merged pull
requests since the last prod release (the first prod release lists none). The Android APK is
attached once the release key's secrets exist (#1776), in the repository's Environment `release`,
which only `main` may deploy to; until then a prod release goes out without it, and says so. A
dry run never makes a tag, so the first real release is the first run to make a `v*` tag under
the "immutable release tags" ruleset.

## Tests

The e2e tests run headless. A fresh checkout needs one import first:

```sh
godot --headless --path packages/game --import
godot --headless --path packages/game -s res://tests/e2e/run_e2e.gd -- --seed=0
```

Every `packages/game/tests/e2e/test_*.gd` runs; the exit code is non-zero when one fails. CI runs the same on every
pull request and every push to `main`.

Every checkout of the project shares one `user://` folder, so runs in parallel worktrees overwrite
each other's files. Give each its own with `--user-dir=<name>` (the folder `khovax_<name>` in the
system's data folder), e.g. the branch name: `-- --seed=0 --user-dir=my-branch`. The game, the load
test and the other tools take it too.

### On the web build

CI also plays the device flow on the web test build in headless Chrome (`web-e2e`). To run it
yourself, with uv and a
[chrome-headless-shell](https://googlechromelabs.github.io/chrome-for-testing/) download (the
version CI pins in `.github/workflows/ci.yml`), from the repository's root. The run films itself
with Playwright's ffmpeg, which `playwright install ffmpeg` fetches once; `EXPECTED_HASH` is the
state hash the headless run of the same flow ends in:

```sh
godot --headless --path packages/game --export-release "Web Test" build/web-test/index.html
uv run --locked --package khovax-game-web-e2e playwright install ffmpeg
CHROME=<path to chrome-headless-shell> EXPECTED_HASH=<hash> \
  uv run --locked --package khovax-game-web-e2e packages/game-web-e2e/web_e2e.py packages/game/build/web-test
```

### Load test

The `thudren_orl` instance (a big region full of wild monsters, the game's own rules) under four
players walking by script. Headless it times every tick and each rule's share, and checks two passes
end in the same state; CI runs that on every push (2000 ticks) and compares the times with the base
branch's. Rendered, on demand, it times frames, uncapped:

```sh
godot --headless --path packages/game -s res://tools/godot/load_test.gd -- ticks=2000
godot --path packages/game -s res://tools/godot/load_test.gd -- rendered seconds=20
```

Measurements go into the pull request or issue that made them, not into docs.

## Linting

```sh
gdstyle fmt .      # format every GDScript file
gdstyle check .    # lint
```

Every gdstyle rule is an error (`gdstyle.toml`), and so is every Godot GDScript warning
(`project.godot`). A script with a warning fails to load. CI lints, checks the formatting, and checks
every script with `godot --headless --path packages/game --check-only -s res://<script>`.

## Translations

The game's texts are translated with gettext, the English text being the key (#1608).
`packages/game/translations/khovax.pot`, the template every language's `.po` starts from, is
written from the texts the player reads; CI fails when it's out of date. After changing a text,
write it again and commit it:

```sh
uv run --locked --package khovax-game-checks packages/game-checks/translations_pot.py
```

A new player-facing field in content data gets `"x-translate": true` in its schema, and a text in a
script goes through `tr()` with a literal string, so the template picks it up. CI fails on a text shown
to the player without it (`packages/game-checks/hardcoded_texts.py`, #1693); a deliberate
exception goes into its `ALLOWED` list with a reason.

A text with two or more values names them, so a translation can put them in its own order:
`tr("Carried {place}: {monster}").format({"place": place, "monster": shown})`, never
`tr("Carried %d: %s") % [place, shown]`, since `%` fills its values in the order written. A text
with one value may keep its `%`. CI fails on a `tr()` literal with two or more `%` placeholders
(`packages/game-checks/tr_placeholders.py`, #1704).
