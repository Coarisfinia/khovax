class_name PackFile
extends RefCounted
## A resource pack's .pck file (#1870), read before Godot mounts it: the files it holds and their
## bytes, so PackCheck can refuse it before any of it reaches res://. It reads Godot's pack format
## as this Godot writes it (the pack builder's and PCKPacker's, #1869): a header, then a directory
## of files at its offset.

## "GDPC", the format's magic number.
const MAGIC: int = 0x43504447
## The format versions with the directory at an offset, as this Godot reads them.
const FORMATS: Array[int] = [3, 4]
## The header's flag for an encrypted directory, which can't be read without its key.
const ENCRYPTED_DIRECTORY: int = 1
## The header's flag for file offsets counted from the file base rather than the file's start.
const RELATIVE_FILE_BASE: int = 2
## How many files a pack may hold, and how long a file's path may be, so a broken directory
## can't hang the reading or ask for a huge buffer.
const MAX_FILES: int = 100_000
const MAX_PATH: int = 4096

## Why the file can't be read as a pack, or "" when it can.
var problem: String = ""
## Each file's place in the pack by its path from res:// (without the scheme): its offset from
## the file base, its size and its flags (encrypted, or a removal of a file).
var files: Dictionary[String, PackedInt64Array] = {}
var _path: String = ""
var _file_base: int = 0


## The pack in the .pck file at `pck_path`, with `problem` saying why it can't be read: no such
## file, another format or Godot version, an encrypted directory, or a truncated directory.
static func open(pck_path: String) -> PackFile:
	var pack: PackFile = PackFile.new()
	pack._path = pck_path
	var file: FileAccess = FileAccess.open(pck_path, FileAccess.READ)
	if file == null:
		pack.problem = "can't be opened"
		return pack
	pack.problem = pack._read_directory(file)
	return pack


## The bytes of the file `file_path`, which the pack must hold.
func read(file_path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var place: PackedInt64Array = files[file_path]
	file.seek(_file_base + place[0])
	return file.get_buffer(place[1])


## Reads the header and the directory from `file`; returns why it can't, or "".
func _read_directory(file: FileAccess) -> String:
	if file.get_32() != MAGIC:
		return "isn't a Godot pack"
	var format: int = file.get_32()
	var version: Array[int] = [file.get_32(), file.get_32(), file.get_32()]
	var flags: int = file.get_32()
	var file_base: int = file.get_64()
	var directory: int = file.get_64()
	if not FORMATS.has(format):
		return "is in pack format %d, which this game doesn't read" % format
	var engine: Dictionary = Engine.get_version_info()
	if version != [engine["major"], engine["minor"], engine["patch"]]:
		return "was built with another Godot than the game's"
	if flags & ENCRYPTED_DIRECTORY:
		return "has an encrypted directory"
	# Any other flag (a sparse bundle reads its files from elsewhere) means Godot would mount bytes
	# that weren't checked here.
	if flags & ~RELATIVE_FILE_BASE:
		return "has pack flags this game doesn't read"
	_file_base = file_base if flags & RELATIVE_FILE_BASE else 0
	file.seek(directory)
	var count: int = file.get_32()
	if count > MAX_FILES:
		return "holds too many files"
	for _index: int in count:
		if not _read_entry(file):
			return "has a broken directory: a file's path or place is off, or named twice"
	return ""


## Reads one file's entry of the directory from `file`; whether it was all there.
func _read_entry(file: FileAccess) -> bool:
	var length: int = file.get_32()
	if length > MAX_PATH:
		return false
	var name_bytes: PackedByteArray = file.get_buffer(length)
	var offset: int = file.get_64()
	var size: int = file.get_64()
	var _md5: PackedByteArray = file.get_buffer(16)
	var file_flags: int = file.get_32()
	# Each part is checked on its own, so no sum of huge values can wrap around.
	var length_left: int = file.get_length() - _file_base
	if file.get_position() > file.get_length() or _file_base < 0 or offset < 0 or size < 0:
		return false
	if offset > length_left or size > length_left - offset:
		return false
	# The name is padded with zeros to whole words.
	var end: int = name_bytes.find(0)
	if end >= 0:
		name_bytes = name_bytes.slice(0, end)
	var file_name: String = name_bytes.get_string_from_utf8().trim_prefix("res://")
	if files.has(file_name):
		return false
	files[file_name] = PackedInt64Array([offset, size, file_flags])
	return true
