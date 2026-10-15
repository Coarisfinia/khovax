class_name ErrorCounter
extends Logger
## Counts every error Godot logs (script errors, push_error, engine errors), once added with
## OS.add_logger. The e2e runs read it: a function that hits a script error returns its type's
## default, which for a flow's String result is "", the same as a pass.

var count: int = 0


# The parameters are Logger's virtual method signature, fixed by the engine.
# gdstyle:ignore=quality/max-parameters
func _log_error(
	_function: String,
	_file: String,
	_line: int,
	_code: String,
	_rationale: String,
	_editor_notify: bool,
	_error_type: int,
	_script_backtraces: Array[ScriptBacktrace],
) -> void:
	count += 1
