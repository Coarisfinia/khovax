class_name PackScene
extends RefCounted
## Whether an imported scene in a resource pack's .pck (#1870) is data, read before it's mounted
## (PackCheck): a binary PackedScene, compressed or not, that names no script and points only at
## its own sub-resources and the pack's own files. Godot's binary resource format, as this Godot
## writes it: a header, the string table, then the external resources it loads.

## A compressed resource's magic, and an uncompressed binary one's.
const COMPRESSED: String = "RSCC"
const BINARY: String = "RSRC"
## The compressed resource's header: its magic, mode, block size and full size, as 32-bit words.
const COMPRESSED_HEADER: int = 16
## The largest scene, packed or unpacked, the check reads, so a pack can't make it read without end.
const MAX_SIZE: int = 256 * 1024 * 1024
## The only type a scene may be.
const SCENE_TYPE: String = "PackedScene"
## The header's flags: a uid after each external resource's path, and a script class named.
const FLAG_UIDS: int = 2
const FLAG_SCRIPT_CLASS: int = 8
## The unused 32-bit words after the header.
const RESERVED_FIELDS: int = 11
## A uid that names nothing, as an external resource stores it.
const NO_UID: int = -1
## What a scene names when it holds a script.
const SCRIPT: String = "Script"


## Why the scene `bytes` can't be mounted, with `files` the pack's (PackFile.files) and `own` its
## folder (packs/<id>/): not a binary scene, a script in it, or an external resource that isn't
## one of the pack's own files or its imported ones. Or "".
static func problem(bytes: PackedByteArray, files: Dictionary, own: String) -> String:
	var magic: String = bytes.slice(0, 4).get_string_from_ascii()
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	# A compressed resource's own magic stands in for the binary one; the body follows.
	if magic == COMPRESSED:
		body.data_array = _decompressed(bytes)
	elif magic == BINARY:
		body.data_array = bytes.slice(4)
	var refused: String = _header_problem(body)
	if not refused.is_empty():
		return refused
	# A script, embedded or loaded, names its class (GDScript, CSharpScript and the like) as its
	# type, which a binary resource stores as plain text.
	if _contains(body.data_array, SCRIPT.to_ascii_buffer()):
		return "holds a script"
	for _index: int in _count(body):
		var _name: String = _string(body)
	return _external_problem(body, files, own)


## Why the header doesn't read as a binary scene's, leaving `body` after it. Or "".
static func _header_problem(body: StreamPeerBuffer) -> String:
	# Its endianness (little), number size, version and format.
	if body.get_size() == 0 or body.get_u32() != 0:
		return "isn't a binary scene"
	for _word: int in 4:
		var _skipped: int = body.get_u32()
	if _string(body) != SCENE_TYPE:
		return "isn't a binary scene"
	var _import_metadata: int = body.get_u64()
	var flags: int = body.get_u32()
	var _uid: int = body.get_u64()
	if flags & FLAG_SCRIPT_CLASS:
		return "holds a script"
	if not flags & FLAG_UIDS:
		return "is in a binary format this game doesn't read"
	for _word: int in RESERVED_FIELDS:
		var _reserved: int = body.get_u32()
	return ""


## Why one of the scene's external resources, read from `body`, isn't one of `files` under `own`
## or the imported ones. Or "".
static func _external_problem(body: StreamPeerBuffer, files: Dictionary, own: String) -> String:
	for _index: int in _count(body):
		var _type: String = _string(body)
		var path: String = _string(body)
		var uid: int = body.get_u64()
		# Godot loads by the uid first, when it names a file the game has.
		if uid != NO_UID and ResourceUID.has_id(uid):
			return "points at one of the game's files: " + ResourceUID.id_to_text(uid)
		var in_pack: String = path.trim_prefix("res://")
		var held: bool = files.has(in_pack) or files.has(in_pack + ".import")
		var placed: bool = in_pack.begins_with(own) or in_pack.begins_with(PackCheck.IMPORTED)
		if (not path.begins_with("res://")
				or in_pack.simplify_path() != in_pack
				or not held
				or not placed):
			return "points outside the pack: " + path
		if body.get_position() >= body.get_size():
			return "isn't a binary scene"
	return ""


## A count at the body's position, or 0 when the bytes left can't hold that many entries, each
## at least a 32-bit word: a broken count can't make the check loop without end.
static func _count(body: StreamPeerBuffer) -> int:
	var count: int = body.get_u32()
	return count if count * 4 <= body.get_size() - body.get_position() else 0


## The string at the body's position: its length with the ending zero, then its bytes.
static func _string(body: StreamPeerBuffer) -> String:
	var length: int = body.get_u32()
	if length <= 0 or length > body.get_size() - body.get_position():
		body.seek(body.get_size())
		return ""
	var text: String = body.get_utf8_string(length - 1)
	var _zero: int = body.get_u8()
	return text


## The resource compressed in blocks (Godot's RSCC format: its mode, the block size, the full size
## and each block's compressed size, then the blocks), or nothing when it's broken.
static func _decompressed(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() < COMPRESSED_HEADER:
		return PackedByteArray()
	var mode: int = bytes.decode_u32(4)
	var block_size: int = bytes.decode_u32(8)
	var total: int = bytes.decode_u32(12)
	if block_size <= 0 or total > MAX_SIZE:
		return PackedByteArray()
	var blocks: int = ceili(float(total) / block_size)
	var at: int = COMPRESSED_HEADER + 4 * blocks
	# Each block's size is a 32-bit word in the table, which must fit in the bytes.
	if at > bytes.size():
		return PackedByteArray()
	var whole: PackedByteArray = PackedByteArray()
	for block: int in blocks:
		if COMPRESSED_HEADER + 4 * block + 4 > bytes.size():
			return PackedByteArray()
		var size: int = bytes.decode_u32(COMPRESSED_HEADER + 4 * block)
		if at + size > bytes.size():
			return PackedByteArray()
		var plain: int = mini(block_size, total - block * block_size)
		whole.append_array(bytes.slice(at, at + size).decompress(plain, mode))
		at += size
	return whole if whole.size() == total else PackedByteArray()


## Whether `bytes` holds `part` anywhere.
static func _contains(bytes: PackedByteArray, part: PackedByteArray) -> bool:
	var at: int = bytes.find(part[0])
	while at >= 0:
		if bytes.slice(at, at + part.size()) == part:
			return true
		at = bytes.find(part[0], at + 1)
	return false
