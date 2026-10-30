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
## The endings of a pack's own files.
const OWN_ENDINGS: Array[String] = ["md", "jsonc", "import"]
## Where Godot keeps what it imported, and the endings it may hold: textures and scenes.
const IMPORTED: String = ".godot/imported/"
const IMPORTED_ENDINGS: Array[String] = ["ctex", "scn"]
## The project files every exported pack carries; mounted without replacing, they never reach
## the game.
const PROJECT_FILES: Array[String] = [
	"project.binary",
	".godot/global_script_class_cache.cfg",
	".godot/uid_cache.bin",
]
## The importers a pack's .import may name.
const IMPORTERS: Array[String] = ['importer="texture"', 'importer="scene"']
## Where a pack's .import may point a resource: at its own imported files.
const REMAP_TARGET: String = "res://" + IMPORTED
## An imported texture's magic.
const TEXTURE: String = "GST2"
## The largest own file (a manifest, Markdown, JSONC or .import) the check or the loader reads.
const MAX_TEXT: int = 4 * 1024 * 1024
## What a pack's id looks like, as a manifest names it.
const ID: String = "\\A[a-z][a-z0-9_]*\\z"


## The pack's id: the one folder under packs/ with a manifest in it, named as an id, or "" when
## there isn't exactly one.
static func pack_id(pack: PackFile) -> String:
	var ids: Array[String] = []
	var id_pattern: RegEx = RegEx.create_from_string(ID)
	for path: String in pack.files:
		var parts: PackedStringArray = path.split("/")
		if parts.size() == 3 and parts[0] + "/" == PACKS and parts[2] == MANIFEST:
			ids.append(parts[1])
	return ids[0] if ids.size() == 1 and id_pattern.search(ids[0]) != null else ""


## Why the pack can't be mounted, one reason per file, or none when it's all data.
static func problems(pack: PackFile) -> PackedStringArray:
	var found: Array[String] = []
	var id: String = pack_id(pack)
	if id.is_empty():
		return PackedStringArray(["holds no single packs/<id>/%s" % MANIFEST])
	var own: String = PACKS + id + "/"
	for path: String in pack.files:
		var problem: String = _file_problem(pack, path, own)
		if not problem.is_empty():
			found.append("%s %s" % [path, problem])
	return PackedStringArray(found)


## Why the pack's file `path` keeps it from being mounted, or "".
static func _file_problem(pack: PackFile, path: String, own: String) -> String:
	if pack.files[path][2] != 0:
		return "is encrypted or removes a file"
	# Godot finds a file by its simplified path, so only a path that is already simple is the file
	# checked here.
	if path.simplify_path() != path or path.contains("//"):
		return "isn't a simple path"
	if PROJECT_FILES.has(path):
		return ""
	if path.begins_with(IMPORTED):
		return _imported_problem(pack, path)
	if (not path.begins_with(own)
			or path.contains("..")
			or not OWN_ENDINGS.has(path.get_extension())):
		return "isn't one of the pack's own files (%s under %s)" % [", ".join(OWN_ENDINGS), own]
	if pack.files[path][1] > MAX_TEXT:
		return "is too large to read"
	if path.get_extension() == "import":
		return _remap_problem(pack, pack.read(path).get_string_from_utf8())
	return ""


## Why an imported file of the pack can't be mounted: it isn't a texture or a scene, or the scene
## holds a script. Or "".
static func _imported_problem(pack: PackFile, path: String) -> String:
	var file_name: String = path.trim_prefix(IMPORTED)
	if file_name.contains("/") or not IMPORTED_ENDINGS.has(file_name.get_extension()):
		return "isn't an imported texture or scene"
	if pack.files[path][1] > PackScene.MAX_SIZE:
		return "is too large to check"
	if file_name.get_extension() == "ctex":
		var magic: String = pack.read(path).slice(0, 4).get_string_from_ascii()
		return "" if magic == TEXTURE else "isn't an imported texture"
	var own: PackedStringArray = ["res://" + PACKS + pack_id(pack) + "/", REMAP_TARGET]
	return PackScene.problem(pack.read(path), own)


## Why a .import of the pack can't be mounted: another importer, or a line that points anywhere
## but at the pack's own imported files (a uid is only an id). Or "".
static func _remap_problem(pack: PackFile, text: String) -> String:
	if not IMPORTERS.any(text.contains):
		return "imports with neither the texture nor the scene importer"
	for line: String in text.split("\n"):
		if not line.contains("://") or line.begins_with('uid="uid://'):
			continue
		var target: String = line.get_slice('"', 1)
		var points: bool = line.begins_with("path") and target.begins_with(REMAP_TARGET)
		if not points or not pack.files.has(target.trim_prefix("res://")):
			return "points outside the pack's imported files: " + line
	return ""
