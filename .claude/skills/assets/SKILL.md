---
name: assets
description: Use when you need assets like sound, 3D models, textures, icons or fonts for khovax. Contains info on importing, downloading, obtaining, licensing and otherwise working with assets. Use it whenever a task finds, downloads, evaluates or imports a sound, music track, model, texture or other third-party or generated file, or asks whether a source or its license may be used here, even if it never says "asset".
---

# Assets

Where an asset comes from and what must stay next to it. This skill routes each kind of asset to
its guide, and holds the license and source rules they share.

## Which guide

| You need | Go to |
|---|---|
| A 3D model, rig, clip or texture: request, import or fix | `.claude/skills/model/SKILL.md`, and AGENTS.md's "If you need a new model" |
| Sound effects, music or ambience | [`references/audio.md`](references/audio.md) |
| Anything else (icons, fonts, images) | The rules below; `resourcepacks/default/textures/game-icons/` shows a pack of them |

The rules for requesting a model stay there, and nothing here changes them. A prop or scenery model
from a free source also passes the license rules below.

## Before you download anything

1. **Look for what's already here**, in `resourcepacks/default/models/`, `resourcepacks/default/textures/` and
   `src/game-models/textures/`.
   Reusing an asset costs no new license review.
2. **Check the license of the exact file, on its source's own page.** A site's general statement
   tells you where to look, not what this file is under, and terms change: the Quaternius case
   (#1954, refused by `tools/godot/credits.gd`) was a source that relicensed its files. Note the
   date you checked.
3. **Check what we do with it, not only that it's "free".** The repository is public and resource
   packs are shared, so the file itself gets redistributed, usually adapted. Permission to use a
   sound in a finished video or game doesn't by itself cover that.

**Allowed here** (AGENTS.md, #1511): CC0, CC BY with credit, or the Unlicense for what the project
itself owns. Prefer CC0, then CC BY. Anything else (CC BY-NC, CC BY-SA, Sampling+, a site's own
license, a public-domain claim without a CC0 or license file) isn't on the list: find another file,
or put the choice to the owner in a `question` issue. The root Unlicense never covers a third
party's file.

**A file the project owns**, because it was built in the repository or the owner made or generated
it for khovax (such as a model from a paid Meshy plan under its Private license, #1476), follows
AGENTS.md's project-owned rule: it is under the Unlicense, its `LICENSE.md` is a copy of the root
`LICENSE`, and its `SOURCE.md` names the project (or its contributors) as the author and says how
the file was made.

**If you couldn't verify something, say so** on the issue or pull request, and in `Checked` below.
A file's license or its publisher's right to grant it, left unverified, blocks the import until
there is independent provenance or the owner's decision in a `question` issue. A source's general
disclaimer, such as a site giving no warranty, doesn't block a file whose own page is complete.
A claim on a source's page is the source's claim, so word it that way.

## What stays next to the file

Each pack lives in the default pack's own folder of its kind, `resourcepacks/default/<kind>/<pack>/`
(`models`, `textures` or `audio`, #1978), with only what the game uses, never a whole
download:

- **`LICENSE.md`:** the license's text, or the pack's own notice if it came with one.
- **Godot's `.import` file:** committed beside the file it describes. Godot writes it only on an
  import, so after adding the file run `godot --headless --path src/game --import` from the
  repository's root (as for `.uid` files in AGENTS.md's "Testing and CI"). It generates files
  rather than checking anything, so it isn't a rerun of CI.
- **`SOURCE.md`:** a title, then the three lines `tools/godot/credits.gd` turns into `CREDITS.md`,
  then the rest of the file's history. Never edit `CREDITS.md` by hand: CI fails when it differs.

```markdown
# <Title>

- **Author:** <name, as the source asks to be credited, with a link>
- **Source:** <URL of the exact file's page> (`<file>` from `<download>`)
- **License:** <name and version, with its URL>, see `LICENSE.md` next to this file
- **Used for:** <what, and the issue>
- **Checked:** <date>: <what the source's page says, and what couldn't be verified>
- **SHA-256:** `<hash of the file as downloaded>` (`<file>`)
- **Modifications:** <what changed and with what command, or "none: unchanged">
```

A pack of several files names each file within those same lines, continued on indented lines
(`game-icons/SOURCE.md` lists its authors that way), because `credits.gd` takes only the first of
each. CC BY requires keeping the creator's credit, the license notice and a note of any change, so
they go wherever the file goes, into a built resource pack as well.

`src/game-checks/unused_assets.py` fails on a file nothing uses, so an import arrives together
with what uses it. New content goes into the default resource pack when it belongs there (#1860).
