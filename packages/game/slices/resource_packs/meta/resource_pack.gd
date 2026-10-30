class_name ResourcePack
extends RefCounted
## A resource pack (#1860): a manifest naming the resources it provides by id, read and checked
## here the same way for every pack. The game's own resources are the `default` pack
## (ResourcePacks.DEFAULT); a player's pack (#1858) shares this format, and only how its files
## load differs.

## The manifest's fields, as resource_packs.schema.json beside the default pack lists them.
const FIELDS: Array[String] = [
	"id",
	"name",
	"version",
	"game_version",
	"textures",
	"models",
	"regions",
	"region_pieces",
	"realms",
]
## Each section of resources the manifest lists, one file per id, with the type its files load as;
## "" for a file read as text (a region file or a realm, #1861), which isn't checked to exist here:
## a build
## may leave a test-only region out (export_presets.cfg), and RegionFiles finds only the files there
## are.
const KINDS: Dictionary[String, String] = {
	"textures": "Texture2D",
	"models": "PackedScene",
	"regions": "",
	"realms": "",
}
## The section of regions arranged from pieces (#1861): each region's piece files by its id, read as
## text like the region files.
const PIECES: String = "region_pieces"
## The file endings each section takes, as resource_packs.schema.json lists them.
const ENDINGS: Dictionary[String, Array] = {
	"textures": ["svg", "png", "jpg", "jpeg", "webp"],
	"models": ["glb", "gltf"],
	"regions": ["md"],
	"realms": ["md"],
}
## A version: major.minor.patch.
const VERSION: String = "\\A[0-9]+\\.[0-9]+\\.[0-9]+\\z"

## The pack's id, name, its own version and the game version it targets.
var id: String = ""
var name: String = ""
var version: String = ""
var game_version: String = ""
## Each texture's file by its id, relative to `root`; empty while the pack has a problem.
var textures: Dictionary[String, String] = {}
## Each model's file (a .glb or .gltf, #1864) by its id, relative to `root`; empty while the pack
## has a problem.
var models: Dictionary[String, String] = {}
## Each region drawn whole in one file (#1861) by its id, relative to `root`.
var regions: Dictionary[String, String] = {}
## Each region arranged from pieces (#1861): its piece files by its id, relative to `root`.
var region_pieces: Dictionary[String, PackedStringArray] = {}
## Each realm's file (#1861) by its id, relative to `root`.
var realms: Dictionary[String, String] = {}
## Where the pack's files are named from: res:// for the default pack.
var root: String = ""
## Why the pack can't be used, or "" when it can.
var problem: String = ""


## The pack the manifest `text` describes, its files under `root`, with `problem` saying why it
## can't be used: a field missing or unknown, an id that isn't one, or a texture, model, region,
## region piece or realm whose file climbs out of `root`, has another kind's ending or (for a
## texture or
## model) doesn't exist.
static func parse(text: String, files_root: String) -> ResourcePack:
	var pack: ResourcePack = ResourcePack.new()
	pack.root = files_root
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		pack.problem = Content.NOT_AN_OBJECT
		return pack
	var data: Dictionary = parsed
	pack.problem = pack._read(data)
	return pack


## The texture `texture_id`, which the pack must have. The default pack's files load as Godot
## imported them, compressed for the GPU; reading a player's raw files is #1858's.
func texture(texture_id: String) -> Texture2D:
	return load(root + textures[texture_id]) as Texture2D


## The model `model_id`, which the pack must have, loaded as Godot imported it (texture).
func model(model_id: String) -> PackedScene:
	return load(root + models[model_id]) as PackedScene


## Reads the manifest's `data` into this; returns why it can't, or "".
func _read(data: Dictionary) -> String:
	var unknown: String = Content.unknown_field(data, FIELDS)
	if not unknown.is_empty():
		return unknown
	id = Content.text_of(data.get("id"))
	name = Content.text_of(data.get("name"))
	version = Content.text_of(data.get("version"))
	game_version = Content.text_of(data.get("game_version"))
	if not Content.is_id(id):
		return "its id must be lowercase words with underscores"
	if name.strip_edges().is_empty():
		return "it has no name"
	var versions: RegEx = RegEx.create_from_string(VERSION)
	if versions.search(version) == null or versions.search(game_version) == null:
		return "its version and game_version must be major.minor.patch"
	var found: Dictionary[String, Dictionary] = {}
	for kind: String in KINDS:
		var raw: Variant = data.get(kind)
		if not raw is Dictionary:
			return "its %s must be an object" % kind
		var entries: Dictionary = raw
		var files: Dictionary[String, String] = {}
		for key: Variant in entries:
			var path: String = Content.text_of(entries[key])
			var why: String = _entry_problem(kind, str(key), path)
			if not why.is_empty():
				return why
			files[str(key)] = path
		found[kind] = files
	var pieces: Dictionary[String, PackedStringArray] = {}
	var why_not: String = _read_pieces(data.get(PIECES), found["regions"], pieces)
	if not why_not.is_empty():
		return why_not
	# Only a pack read whole provides anything.
	textures.assign(found["textures"])
	models.assign(found["models"])
	regions.assign(found["regions"])
	realms.assign(found["realms"])
	region_pieces = pieces
	return ""


## Reads the regions arranged from pieces from `raw` into `pieces`; returns why it can't, or "": a
## region is drawn whole (one of `whole`) or in pieces, never both.
func _read_pieces(
	raw: Variant,
	whole: Dictionary,
	pieces: Dictionary[String, PackedStringArray],
) -> String:
	if not raw is Dictionary:
		return "its %s must be an object" % PIECES
	var entries: Dictionary = raw
	for key: Variant in entries:
		if whole.has(str(key)):
			return "region %s is both drawn whole and in pieces" % key
		var listed: Variant = entries[key]
		var named: Array = listed if listed is Array else []
		if named.is_empty():
			return "region %s's pieces must be a list of files" % key
		var files: PackedStringArray = []
		for file: Variant in named:
			var why: String = _entry_problem("regions", str(key), Content.text_of(file))
			if not why.is_empty():
				return why
			var _added: bool = files.append(Content.text_of(file))
		pieces[str(key)] = files
	return ""


## Why the resource `resource_id` of `kind` (one of KINDS) can't be the file at `path`, or "".
func _entry_problem(kind: String, resource_id: String, path: String) -> String:
	var noun: String = kind.trim_suffix("s")
	if not Content.is_id(resource_id):
		return "%s %s's id must be lowercase words with underscores" % [noun, resource_id]
	# A simplified relative path never climbs out of the root (`..`) or names another (`://`).
	var inside: bool = path.simplify_path() == path and path.is_relative_path()
	if not inside or path.begins_with("..") or path.contains("://"):
		return "%s %s's file %s must lie inside the pack" % [noun, resource_id, path]
	if not ENDINGS[kind].has(path.get_extension()):
		return "%s %s's file %s must end in one of %s" % [noun, resource_id, path, ENDINGS[kind]]
	if not KINDS[kind].is_empty() and not ResourceLoader.exists(root + path, KINDS[kind]):
		return "%s %s's file %s doesn't exist" % [noun, resource_id, path]
	return ""
