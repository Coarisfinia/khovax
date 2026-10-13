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
```

Open the project in Godot (`godot --path . --editor`), or run it directly with `godot --path .`.

## Tests

The e2e tests run headless. A fresh checkout needs one import first:

```sh
godot --headless --path . --import
godot --headless --path . -s res://tests/e2e/run_e2e.gd
```

Every `tests/e2e/test_*.gd` runs; the exit code is non-zero when one fails. CI runs the same on every
pull request and every push to `main`.
