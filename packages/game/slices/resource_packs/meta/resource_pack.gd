class_name ResourcePack
extends RefCounted
## A resource pack (#1860): a manifest naming the resources it provides by id, read and checked
## here the same way for every pack. The game's own resources are the `default` pack
## (ResourcePacks.DEFAULT); a player's pack (#1858) shares this format, and only how its files
## load differs.

## The manifest's fields, as resource_packs.schema.json beside the default pack lists them.
const FIELDS: Array[String] = ["id", "name", "version", "game_version", "textures"]
## A version: major.minor.patch.
const VERSION: String = "\\A[0-9]+\\.[0-9]+\\.[0-9]+\\z"

## The pack's id, name, its own version and the game version it targets.
var id: String = ""
var name: String = ""
var version: String = ""
var game_version: String = ""
## Each texture's file by its id, relative to `root`; empty while the pack has a problem.
var textures: Dictionary[String, String] = {}
## Where the pack's files are named from: res:// for the default pack.
var root: String = ""
## Why the pack can't be used, or "" when it can.
var problem: String = ""


## The pack the manifest `text` describes, its files under `root`, with `problem` saying why it
## can't be used: a field missing or unknown, an id that isn't one, or a texture whose file
## doesn't exist or climbs out of `root`.
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
	var raw: Variant = data.get("textures")
	if not raw is Dictionary:
		return "its textures must be an object"
	var entries: Dictionary = raw
	var found: Dictionary[String, String] = {}
	for key: Variant in entries:
		var path: String = Content.text_of(entries[key])
		var why: String = _texture_problem(str(key), path)
		if not why.is_empty():
			return why
		found[str(key)] = path
	textures = found
	return ""


## Why the texture `texture_id` can't be the file at `path`, or "".
func _texture_problem(texture_id: String, path: String) -> String:
	if not Content.is_id(texture_id):
		return "texture %s's id must be lowercase words with underscores" % texture_id
	# A simplified relative path never climbs out of the root (`..`) or names another (`://`).
	var inside: bool = path.simplify_path() == path and path.is_relative_path()
	if not inside or path.begins_with("..") or path.contains("://"):
		return "texture %s's file %s must lie inside the pack" % [texture_id, path]
	if not ResourceLoader.exists(root + path, "Texture2D"):
		return "texture %s's file %s doesn't exist" % [texture_id, path]
	return ""
