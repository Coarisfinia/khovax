# The pack builder

Builds a resource pack for the game: textures, models, sounds, regions, realms, quests, species, tile kinds,
translations, loot tables, harvest tables and materials that add to or replace the game's own. A pack is data,
never code. The builder refuses anything else, and the game checks every pack again before it
loads it.

## What you need

- Python 3.14.
- Godot, in the version `godot.json` names. The builder looks for it in `GODOT`, then
  `~/godot/godot`, then `godot` on the `PATH`. On Linux x86_64, if none of them is that version, it
  downloads that version to `~/godot/godot` and checks it against the checksum in `godot.json`.

Use the builder from the same release as the game: a pack is built with that game's Godot version.

## A pack's folder

The game's own default pack, `resourcepacks/default/` at the repository's root, is laid out this way
and is the reference example.

```text
my_pack/
  pack.jsonc        the manifest
  textures/...      images: .png, .jpg, .jpeg, .webp, .svg
  models/...        models: .glb, or .gltf with its .bin
  audio/...         sounds: .ogg
  regions/...       regions and region pieces: .md
  realms/...        realms: .md
  quests/...        quests: .jsonc, in the game's quest format
  species/...       species: .jsonc, in the game's species format
  tiles/...         tile kinds: .jsonc, in the game's tile blueprint format
  translations/...  translation catalogues: gettext .po, one per language
  harvest_tables/... harvest tables: .jsonc, in the game's loot table format, by species id
  loot_tables/...   loot tables: .jsonc, in the game's loot table format
  materials/...     materials: .jsonc, in the game's material format
```

Only those file types are allowed, plus `.jsonc` and Godot's `.import` files. A `.import` file may
use only the texture, scene or Ogg Vorbis importer, and it may name no script and no path. A glTF
may point only at plain files inside the pack. Anything else gets the whole pack refused.

## The manifest, `pack.jsonc`

```jsonc
{
	"id": "my_pack",          // lowercase letters, digits and underscores, starting with a letter
	"name": "My pack",
	"version": "1.0.0",
	"game_version": "0.1.0",  // the game version it's made for
	"textures": { "my_texture": "textures/stone.png" },
	"models": { "my_model": "models/rock.glb" },
	"audio": { "music_exploration": "audio/my_theme.ogg" },
	"regions": { "my_region": "regions/my_region.md" },
	"region_pieces": { "my_region_parts": ["regions/my_region_parts/start.md"] },
	"realms": { "my_realm": "realms/my_realm.md" },
	"quests": { "my_quest": "quests/my_quest.jsonc" },
	"species": { "my_species": "species/my_species.jsonc" },
	"translations": { "de": "translations/de.po" },
	"tiles": { "my_tile": "tiles/my_tile.jsonc" },
	"loot_tables": { "my_loot": "loot_tables/my_loot.jsonc" },
	"harvest_tables": { "my_species": "harvest_tables/my_species.jsonc" },
	"materials": { "my_material": "materials/my_material.jsonc" }
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

## Where a player puts a pack

A player puts the built `.pck` into the game's packs folder and starts the game. The game loads the
packs there in their file names' order, before its own: where two packs give the same id, the one
whose file name sorts first wins. Put only one of a pack's two files there, the one for the
platform: a second `.pck` with the same pack id is refused.

- **Linux:** `~/.local/share/godot/app_userdata/khovax/packs/`, with `<id>.desktop.pck`.
- **Windows:** `%APPDATA%\Godot\app_userdata\khovax\packs\`, with `<id>.desktop.pck`.
- **Android:** `Android/data/io.github.coarisfinia.khovax/files/packs/` on the phone's shared
  storage, with `<id>.mobile.pck`. Connect the phone to a computer over USB and copy the file there
  (the game makes the folder on its first start).
- **Web:** the game looks in the browser's storage for the site, but there is no way yet to put a
  pack there (#2088).

On Linux and Windows, make the `packs` folder if it isn't there yet.
