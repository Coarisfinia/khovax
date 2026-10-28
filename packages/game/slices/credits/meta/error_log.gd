class_name ErrorLog
extends Logger
## The error log (#1510): a file in `user://` that a player attaches to a bug report by hand.
## Nothing
## is sent anywhere. It starts with the build's version and the platform, then holds what Godot
## logs from then on (prints, warnings and errors, with their backtraces), each launch in a fresh
## file, the launch before kept beside it, so a crash's log survives the restart that finds it. It
## holds no personal data: the folders a path could name the player by (the user folder, the
## game's own and the home folder) are written as `user://`, `res://` and `~`. Not on the web,
## where `user://` is the browser's storage and no player could pick the file up.

## Where the log is, and where the launch before's is kept.
const PATH: String = "user://logs/errors.log"
const PREVIOUS: String = "user://logs/errors.previous.log"
## How long the log grows at most, so an error repeated every frame can't fill the disk; the cut
## counts characters, so text beyond ASCII may take it a little past.
const MAX_BYTES: int = 1 << 20
const CUT: String = "[The log stops here: it reached its size limit.]\n"
## How each kind of error is headed, by Logger's ErrorType.
const KINDS: PackedStringArray = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]

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
## whether it's written: never on the web, nor where the file can't be made.
static func start() -> bool:
	if _started != null or OS.has_feature("web"):
		return _started != null
	var _made: Error = DirAccess.make_dir_recursive_absolute(_absolute(PATH.get_base_dir()))
	if FileAccess.file_exists(PATH):
		# Removed first: a rename doesn't replace an existing file everywhere.
		var _removed: Error = DirAccess.remove_absolute(_absolute(PREVIOUS))
		var _kept: Error = DirAccess.rename_absolute(_absolute(PATH), _absolute(PREVIOUS))
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	_started = ErrorLog.new(file)
	_started._write(header())
	OS.add_logger(_started)
	return true


## Where the log is on this device, for the player to find it, or "" when there's none.
static func location() -> String:
	return _absolute(PATH) if _started != null else ""


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
		var shown: String = scrubbed(text)
		var size: int = shown.to_utf8_buffer().size()
		if _bytes + size >= MAX_BYTES:
			shown = shown.left(MAX_BYTES - _bytes) + CUT
		_bytes += size
		var _stored: bool = _file.store_string(shown)
		_file.flush()
		_writing = false
	_mutex.unlock()


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
