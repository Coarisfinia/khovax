class_name ErrorLog
extends Logger
## The error log (#1510): a file in `user://` that a player attaches to a bug report by hand.
## Nothing
## is sent anywhere. It starts with the build's version and the platform, then holds what Godot
## logs from then on (prints, warnings and errors, with their backtraces), each launch in a fresh
## file, the launch before kept beside it, so a crash's log survives the restart that finds it. It
## holds no personal data: the folders a path could name the player by (the user folder, the
## game's own and the home folder) are written as `user://`, `res://` and `~`. On the web,
## `user://` is the browser's storage, where no player could pick the file up, so the Credits tab
## saves it as a file for them instead (#1541, `saved()`).

## Where the log is, and where the launch before's is kept.
const PATH: String = "user://logs/errors.log"
const PREVIOUS: String = "user://logs/errors.previous.log"
## How long the log grows at most, in bytes, so an error repeated every frame can't fill the disk.
const MAX_BYTES: int = 1 << 20
const CUT: String = "[The log stops here: it reached its size limit.]\n"
## How each kind of error is headed, by Logger's ErrorType.
const KINDS: PackedStringArray = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]
## What heads the launch before's log where the two are saved as one file.
const BEFORE: String = "[The launch before:]"

## The log once started, so it's started once however often start() is called.
static var _started: ErrorLog

var _file: FileAccess
## The absolute folders written as their stand-ins, in order: the user folder lies in the home one.
var _stand_ins: Dictionary[String, String] = {}
var _bytes: int = 0
## Godot logs from any thread, and a failing write may log again from inside one: Godot's Mutex
## is reentrant, so that nested call gets through the lock and `_writing` skips it.
var _mutex: Mutex = Mutex.new()
var _writing: bool = false


func _init(file: FileAccess) -> void:
	_file = file
	_hide(OS.get_user_data_dir(), "user:/")
	_hide(ProjectSettings.globalize_path("res://").trim_suffix("/"), "res:/")
	_hide(OS.get_executable_path().get_base_dir(), "res:/")
	for home: String in [OS.get_environment("HOME"), OS.get_environment("USERPROFILE")]:
		_hide(home, "~")


## Starts the log, once, after the launch options have moved `user://` (LaunchMode). Returns
## whether it's written: not where the file can't be made.
static func start() -> bool:
	if _started != null:
		return true
	var _made: Error = DirAccess.make_dir_recursive_absolute(_absolute(PATH.get_base_dir()))
	var file: FileAccess = _opened()
	if file == null:
		return false
	_started = ErrorLog.new(file)
	_started._bytes = file.get_position()
	_started._write(header())
	OS.add_logger(_started)
	return true


## The log's file, fresh with the launch before's kept as PREVIOUS (a rename replaces the
## older one); or, where it can't be moved aside, the launch before's own, written on at its end
## rather than lost, unless that one is full: then there's no log, not one that takes no lines.
static func _opened() -> FileAccess:
	if not FileAccess.file_exists(PATH):
		return FileAccess.open(PATH, FileAccess.WRITE)
	if DirAccess.rename_absolute(_absolute(PATH), _absolute(PREVIOUS)) == OK:
		return FileAccess.open(PATH, FileAccess.WRITE)
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ_WRITE)
	if file == null or file.get_length() >= MAX_BYTES:
		return null
	file.seek_end()
	return file


## Whether the log is written in this launch.
static func written() -> bool:
	return _started != null


## Where the log is on this device, for the player to find it, or "" when there's none, nor on
## the web, where no player could find it in the browser's storage.
static func location() -> String:
	return _absolute(PATH) if written() and not OS.has_feature("web") else ""


## The log as the player saves it as a file: this launch's, then the launch before's, which holds
## what went wrong before a crash, since a crashed web page is simply loaded again.
static func saved() -> PackedByteArray:
	var text: String = FileAccess.get_file_as_string(PATH)
	var before: String = FileAccess.get_file_as_string(PREVIOUS)
	if not before.is_empty():
		text += "\n%s\n%s" % [BEFORE, before]
	return text.to_utf8_buffer()


## The log's first lines: the game and the build's version, then the platform and the engine.
static func header() -> String:
	return "%s %s\n%s %s, Godot %s\n\n" % [
		ProjectSettings.get_setting("application/config/name"),
		BuildVersion.version(),
		OS.get_name(),
		OS.get_version(),
		Engine.get_version_info().string,
	]


func _log_message(message: String, _error: bool) -> void:
	_write(message)


# The parameters are Logger's virtual method signature, fixed by the engine.
# gdstyle:ignore=quality/max-parameters
func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	script_backtraces: Array[ScriptBacktrace],
) -> void:
	var kind: String = KINDS[error_type] if error_type < KINDS.size() else KINDS[0]
	var what: String = rationale if not rationale.is_empty() else code
	var entry: String = "%s: %s\n   at: %s (%s:%d)\n" % [kind, what, function, file, line]
	for backtrace: ScriptBacktrace in script_backtraces:
		if not backtrace.is_empty():
			entry += backtrace.format(3, 3) + "\n"
	_write(entry)


## Appends `text` with the folders hidden, and flushes, so a crash right after loses nothing.
func _write(text: String) -> void:
	_mutex.lock()
	if not _writing and _bytes < MAX_BYTES:
		_writing = true
		var shown: PackedByteArray = scrubbed(text).to_utf8_buffer()
		if _bytes + shown.size() >= MAX_BYTES:
			shown = _cut(shown, MAX_BYTES - _bytes - CUT.length())
			shown.append_array(CUT.to_utf8_buffer())
		_bytes += shown.size()
		var _stored: bool = _file.store_buffer(shown)
		_file.flush()
		_writing = false
	_mutex.unlock()


## The first `budget` bytes of `utf8` at most, ending on a whole character.
static func _cut(utf8: PackedByteArray, budget: int) -> PackedByteArray:
	var end: int = clampi(budget, 0, utf8.size())
	# A byte 10xxxxxx continues a character, so the cut moves back to where one starts.
	while end > 0 and end < utf8.size() and utf8[end] & 0xc0 == 0x80:
		end -= 1
	return utf8.slice(0, end)


## `text` with every absolute folder that could name the player replaced by its stand-in, in any
## case: Windows and macOS spell a path in any case, and elsewhere a few more hidden letters harm
## nothing.
func scrubbed(text: String) -> String:
	var shown: String = text
	for folder: String in _stand_ins:
		shown = shown.replacen(folder, _stand_ins[folder])
	return shown


## Writes `folder` as `stand_in`, with either kind of slash, unless it's empty or the root.
func _hide(folder: String, stand_in: String) -> void:
	if folder.length() < 2:
		return
	_stand_ins[folder] = stand_in
	_stand_ins[folder.replace("\\", "/")] = stand_in
	_stand_ins[folder.replace("/", "\\")] = stand_in


static func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)
