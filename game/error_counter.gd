class_name ErrorCounter
extends Logger
## Counts every error Godot logs (script errors, push_error, engine errors), once added with
## OS.add_logger. The e2e runs read it: a function that hits a script error returns its type's
## default, which for a flow's String result is "", the same as a pass. Warnings count too, unless
## a flow said it expects one (`expect`): the game warns about what it handles, such as a world save
## it refuses (#119), and a flow provokes that on purpose.

var count: int = 0
## A fragment of each warning a flow expects and hasn't seen yet; each skips one matching warning.
var expected: Array[String] = []


## Skips the next warning containing `fragment` instead of counting it.
func expect(fragment: String) -> void:
	expected.append(fragment)


# The parameters are Logger's virtual method signature, fixed by the engine.
# gdstyle:ignore=quality/max-parameters
func _log_error(
	_function: String,
	_file: String,
	_line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace],
) -> void:
	if error_type == ERROR_TYPE_WARNING:
		for i: int in expected.size():
			if (code + rationale).contains(expected[i]):
				expected.remove_at(i)
				return
	count += 1
