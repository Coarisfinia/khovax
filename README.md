# khovax

`khovax` is the internal codename for this project. The player-facing game name is separate and can change at any time without renaming the repo.

A top-down, real-time ARPG on a hex grid. You dominate monsters by walking rings around them, and your companions do the fighting. The simulation is fully deterministic and supports co-op. Built with Godot 4 and GDScript for web, mobile and PC.

Status: pre-production. **[Play the latest build in your browser](https://coarisfinia.github.io/khovax/)**

## License

The code is released into the public domain under [the Unlicense](LICENSE). Assets added later keep their own licenses, next to them.

## Running it

Install the tools with [scoop](https://scoop.sh) (Windows). The project targets Godot 4.7.x, the version CI pins:

```sh
scoop bucket add extras
scoop install godot gh git
scoop install "$(cygpath -w "$PWD/tools/scoop/gdstyle.json")"
```

`gdstyle` (the GDScript linter and formatter) isn't in a scoop bucket, so the repository carries its
manifest, and scoop needs its absolute path (the `cygpath` above is for Git Bash).

Open the project in Godot (`godot --path . --editor`), or run it directly with `godot --path .`.

## On an Android phone

CI builds a debug APK on every pull request and every push to `main`:
1. Open the `ci` workflow's latest result on the repository's Actions tab.
2. Download the `khovax-debug-apk` artifact (a zip with `khovax.apk` inside; kept for 14 days).
3. Copy the APK to the phone and open it. Android asks once to allow installs from that source (the file manager or browser).

It's signed with a throwaway debug key made in each CI run. Installing a newer build over an older one fails because the keys differ, so uninstall the old one first.

## On Windows

CI builds the Windows version on every pull request and every push to `main`, as the `khovax-windows` artifact on the run's page (a zip with one `khovax.exe`; kept for 14 days). Unzip it and run the `.exe`. It isn't signed, so Windows SmartScreen asks once: "More info", then "Run anyway".

## On Linux

CI builds the Linux version (x86_64) on every pull request and every push to `main`, as the `khovax-linux` artifact (kept for 14 days). GitHub's artifact zips drop the executable bit, so after unzipping: `chmod +x khovax.x86_64 && ./khovax.x86_64`. Releases attach a `.tar.gz` that keeps it.

## In a browser

**Play it at https://coarisfinia.github.io/khovax/**: every push to `main` that passes all checks deploys there.

CI builds the web version on every pull request and every push to `main`, as the `khovax-web` artifact (kept for 14 days). Browsers won't run it from a file, so serve the unzipped folder: `python -m http.server 8000` inside it, then open http://localhost:8000. It's single-threaded, so it needs no special server headers. Every release attaches the same build as a zip.

## Cutting a release

A release is a GitHub release with the desktop and web builds attached, made by `.github/workflows/release.yml`:
1. Set the new version in `project.godot` (`config/version="0.2.0"` under `[application]`), in a pull request like any change.
2. Once that's merged, tag that commit on `main` with the same version and push the tag:
   `git tag v0.2.0 && git push origin v0.2.0`.
3. The workflow checks the tag against `config/version`, exports the build, and creates the release with a zip named after the game. The release notes list the merged pull requests.

## Tests

The e2e tests run headless. A fresh checkout needs one import first:

```sh
godot --headless --path . --import
godot --headless --path . -s res://tests/e2e/run_e2e.gd -- --seed=0
```

Every `tests/e2e/test_*.gd` runs; the exit code is non-zero when one fails. CI runs the same on every
pull request and every push to `main`.

Every checkout of the project shares one `user://` folder, so runs in parallel worktrees overwrite
each other's files. Give each its own with `--user-dir=<name>` (the folder `khovax_<name>` in the
system's data folder), e.g. the branch name: `-- --seed=0 --user-dir=my-branch`. The game, the load
test and the other tools take it too.

### On the web build

CI also plays the device flow on the web test build in headless Chrome (`web-e2e`). To run it
yourself, with Bun (`scoop install bun`) and a
[chrome-headless-shell](https://googlechromelabs.github.io/chrome-for-testing/) download (the
version CI pins in `.github/workflows/ci.yml`):

```sh
godot --headless --path . --export-release "Web Test" build/web-test/index.html
bun install --cwd tests/web
CHROME=<path to chrome-headless-shell> bun tests/web/web_e2e.ts build/web-test
```

### Load test

On demand, not in CI: the `thudren_orl` instance (a big region full of wild monsters, the game's own
rules) under four players walking by script. Headless it times every tick and each rule's share, and checks
two passes end in the same state; rendered it times frames, uncapped:

```sh
godot --headless --path . -s res://tools/load_test.gd -- ticks=2000
godot --path . -s res://tools/load_test.gd -- rendered seconds=20
```

Measurements go into the pull request or issue that made them, not into docs.

## Linting

```sh
gdstyle fmt .      # format every GDScript file
gdstyle check .    # lint
```

Every gdstyle rule is an error (`gdstyle.toml`), and so is every Godot GDScript warning
(`project.godot`). A script with a warning fails to load. CI lints, checks the formatting, and checks
every script with `godot --headless --path . --check-only -s res://<script>`.
