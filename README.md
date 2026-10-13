# khovax

`khovax` is the internal codename for this project. The player-facing game name is separate and can change at any time without renaming the repo.

A top-down, real-time ARPG on a hex grid. You catch monsters by walking rings around them, and your companions do the fighting. The simulation is fully deterministic and supports co-op. Built with Godot 4 and GDScript for web, mobile and PC.

The design report lives in [`docs/design.html`](docs/design.html).

Status: pre-production.

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

## Tests

The e2e tests run headless. A fresh checkout needs one import first:

```sh
godot --headless --path . --import
godot --headless --path . -s res://tests/e2e/run_e2e.gd
```

Every `tests/e2e/test_*.gd` runs; the exit code is non-zero when one fails. CI runs the same on every
pull request and every push to `main`.

## Linting

```sh
gdstyle fmt .      # format every GDScript file
gdstyle check .    # lint
```

Every gdstyle rule is an error (`gdstyle.toml`), and so is every Godot GDScript warning
(`project.godot`). A script with a warning fails to load. CI lints, checks the formatting, and checks
every script with `godot --headless --path . --check-only -s res://<script>`.
