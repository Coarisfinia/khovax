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
## A compressed resource's magic, and an uncompressed binary one's.
const COMPRESSED: String = "RSCC"
const BINARY: String = "RSRC"
## An imported texture's magic.
const TEXTURE: String = "GST2"
## The type a scene's body names after its header (its endianness, number size, version and
## format, each a 32-bit word), as its length with the ending zero, then the name.
const SCENE_TYPE: String = "PackedScene"
const SCENE_TYPE_AT: int = 20
## The largest imported scene, packed or unpacked, the check reads, so a pack can't make it read
## without end.
const MAX_SCENE: int = 256 * 1024 * 1024
## What a pack's id looks like, as a manifest names it.
const ID: String = "\\A[a-z][a-z0-9_]*\\z"
## The compressed resource's header: its magic, mode, block size and full size, as 32-bit words.
const COMPRESSED_HEADER: int = 16
## What a scene names when it holds a script, whichever kind: GDScript, CSharpScript and the like.
const SCRIPT: String = "Script"


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
	if path.get_extension() == "import":
		return _remap_problem(pack, pack.read(path).get_string_from_utf8())
	return ""


## Why an imported file of the pack can't be mounted: it isn't a texture or a scene, or the scene
## holds a script. Or "".
static func _imported_problem(pack: PackFile, path: String) -> String:
	var file_name: String = path.trim_prefix(IMPORTED)
	if file_name.contains("/") or not IMPORTED_ENDINGS.has(file_name.get_extension()):
		return "isn't an imported texture or scene"
	if pack.files[path][1] > MAX_SCENE:
		return "is too large to check"
	if file_name.get_extension() == "ctex":
		var magic: String = pack.read(path).slice(0, 4).get_string_from_ascii()
		return "" if magic == TEXTURE else "isn't an imported texture"
	return _scene_problem(pack.read(path))


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


## Why an imported scene can't be mounted: it isn't a binary resource, compressed or not, or it
## names a script. Or "".
static func _scene_problem(bytes: PackedByteArray) -> String:
	var magic: String = bytes.slice(0, 4).get_string_from_ascii()
	if magic == COMPRESSED:
		# A compressed resource's own magic stands in for the binary one; the body follows.
		bytes = _decompressed(bytes)
	elif magic == BINARY:
		bytes = bytes.slice(4)
	else:
		bytes = PackedByteArray()
	var type: PackedByteArray = SCENE_TYPE.to_ascii_buffer()
	var named: PackedByteArray = bytes.slice(SCENE_TYPE_AT + 4, SCENE_TYPE_AT + 4 + type.size())
	if bytes.size() < SCENE_TYPE_AT + 4 or bytes.decode_u32(SCENE_TYPE_AT) != type.size() + 1:
		return "isn't a binary scene"
	if named != type:
		return "isn't a binary scene"
	if _contains(bytes, SCRIPT.to_ascii_buffer()):
		return "holds a script"
	return ""


## The resource compressed in blocks (Godot's RSCC format: its mode, the block size, the full size
## and each block's compressed size, then the blocks), or nothing when it's broken.
static func _decompressed(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() < COMPRESSED_HEADER:
		return PackedByteArray()
	var mode: int = bytes.decode_u32(4)
	var block_size: int = bytes.decode_u32(8)
	var total: int = bytes.decode_u32(12)
	if block_size <= 0 or total > MAX_SCENE:
		return PackedByteArray()
	var blocks: int = ceili(float(total) / block_size)
	var at: int = COMPRESSED_HEADER + 4 * blocks
	var whole: PackedByteArray = PackedByteArray()
	for block: int in blocks:
		if COMPRESSED_HEADER + 4 * block + 4 > bytes.size():
			return PackedByteArray()
		var size: int = bytes.decode_u32(COMPRESSED_HEADER + 4 * block)
		var plain: int = mini(block_size, total - block * block_size)
		whole.append_array(bytes.slice(at, at + size).decompress(plain, mode))
		at += size
	return whole if whole.size() == total else PackedByteArray()


## Whether `bytes` holds `part` anywhere, searched in their hex text at whole bytes.
static func _contains(bytes: PackedByteArray, part: PackedByteArray) -> bool:
	var text: String = bytes.hex_encode()
	var needle: String = part.hex_encode()
	var at: int = text.find(needle)
	while at >= 0:
		if at % 2 == 0:
			return true
		at = text.find(needle, at + 1)
	return false
