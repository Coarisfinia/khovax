class_name PackCheck
extends RefCounted
## Whether a resource pack's .pck (#1870) is data, never code (#1859), read before it's mounted:
## the same allow-list the pack builder holds packs to (#1869), on what the builder writes. A pack's
## own files lie under packs/<id>/ (its manifest, Markdown, JSONC and the .import files that point
## at its imported resources), its imported textures and scenes under .godot/imported/, and only
## the project files every export carries besides, which never replace the game's own.

## The folder a pack's own files lie in, as packs/<id>/.
const PACKS: String = "packs/"
## A pack's manifest, in its folder.
const MANIFEST: String = "pack.jsonc"


## The pack's id: the one folder under packs/ with a manifest in it, or "" when there isn't
## exactly one.
static func pack_id(pack: PackFile) -> String:
	var ids: Array[String] = []
	for path: String in pack.files:
		var parts: PackedStringArray = path.split("/")
		if parts.size() == 3 and parts[0] + "/" == PACKS and parts[2] == MANIFEST:
			ids.append(parts[1])
	return ids[0] if ids.size() == 1 else ""
