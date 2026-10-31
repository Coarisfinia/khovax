# The pack builder

Builds a resource pack for the game: textures, models, regions, realms, quests, species, tile kinds
and translations that add to or replace the game's own. A pack is data, never code. The builder
refuses anything else, and the game checks every pack again before it loads it.

## What you need

- Python 3.14.
- Godot, in the version `godot.json` names. The builder looks for it in `GODOT`, then
  `~/godot/godot`, then `godot` on the `PATH`. On Linux x86_64, if none of them is that version, it
  downloads that version to `~/godot/godot` and checks it against the checksum in `godot.json`.

Use the builder from the same release as the game: a pack is built with that game's Godot version.

## A pack's folder

```text
my_pack/
  pack.jsonc        the manifest
  textures/...      images: .png, .jpg, .jpeg, .webp, .svg
  models/...        models: .glb, or .gltf with its .bin
  regions/...       regions and region pieces: .md
  realms/...        realms: .md
  quests/...        quests: .jsonc, in the game's quest format
  species/...       species: .jsonc, in the game's species format
  tiles/...         tile kinds: .jsonc, in the game's tile blueprint format
  translations/...  translation catalogues: gettext .po, one per language
```

Only those file types are allowed, plus `.jsonc` and Godot's `.import` files. A `.import` file may
use only the texture or scene importer, and it may name no script and no path. A glTF may point only
at plain files inside the pack. Anything else gets the whole pack refused.

## The manifest, `pack.jsonc`

```jsonc
{
	"id": "my_pack",          // lowercase letters, digits and underscores, starting with a letter
	"name": "My pack",
	"version": "1.0.0",
	"game_version": "0.1.0",  // the game version it's made for
	"textures": { "my_texture": "textures/stone.png" },
	"models": { "my_model": "models/rock.glb" },
	"regions": { "my_region": "regions/my_region.md" },
	"region_pieces": { "my_region_parts": ["regions/my_region_parts/start.md"] },
	"realms": { "my_realm": "realms/my_realm.md" },
	"quests": { "my_quest": "quests/my_quest.jsonc" },
	"species": { "my_species": "species/my_species.jsonc" },
	"translations": { "de": "translations/de.po" },
	"tiles": { "my_tile": "tiles/my_tile.jsonc" }
}
```

`translations` names one gettext catalogue per language, by its locale (`de`, `pt_br`). Its
`msgid`s are the game's own English texts, as in the game's `khovax.pot` template. A text the
catalogue leaves out shows in English. A pack's catalogue for a language the game has too replaces the
game's whole catalogue for it.

Paths are relative to the pack's folder. An id the game already uses replaces the game's resource
with yours. A tile kind's traits are rules: a pack that adds a tile kind or changes one changes how
the game plays, so replays and co-op hold only between games with the same packs.

## Building

```sh
python3 build_pack.py my_pack out
```

This writes `out/my_pack.desktop.pck` and `out/my_pack.mobile.pck`: the same pack, with textures
compressed for desktop and for mobile.
