class_name WaterRipples
extends RefCounted
## The water shader's ripples, run on the CPU (#2269): the headless renderer draws no shader, so the
## boot flow evaluates the shader's own lines here instead, with Godot's Expression. It reads the
## `ripples()` function's body and the arguments the fragment passes it, so it runs the math the
## GPU runs. Not a flow itself: the runner runs only the `test_*.gd` files.

## How long the ripples are watched, in shader time, and how often.
const WATCH_TIME: float = 600.0
const WATCH_STEP: float = 0.5
## Where on the surface they are watched, in ripple space (the first argument of `ripples()`).
const WATCH_SPAN: float = 3.0
const WATCH_POINTS: int = 4

var _problem: String = ""
var _parameters: Array[String] = []
## The body's `float name = expression;` lines and its `return expression;`, in order.
var _lines: Array[Expression] = []
## The fragment's expression for each argument after `at` and `time`.
var _extra_arguments: Array[Expression] = []


## Parses `code`, a water shader's source. `problem()` says what it couldn't read.
func _init(code: String) -> void:
	var lines: PackedStringArray = code.split("\n")
	var start: int = -1
	for line: int in lines.size():
		if lines[line].begins_with("float ripples("):
			start = line
	if start < 0:
		_problem = "has no ripples() function"
		return
	var signature: String = lines[start].get_slice("(", 1).get_slice(")", 0)
	for parameter: String in signature.split(","):
		_parameters.append(parameter.strip_edges().get_slice(" ", 1))
	var names: Array[String] = _parameters.duplicate()
	for line: int in range(start + 1, lines.size()):
		var text: String = lines[line].strip_edges()
		if text == "}":
			break
		var expression: String = ""
		if text.begins_with("return "):
			expression = text.trim_prefix("return ").trim_suffix(";")
		elif text.begins_with("float ") and text.contains(" = "):
			expression = text.get_slice(" = ", 1).trim_suffix(";")
		else:
			continue
		var parsed: Expression = _parse(expression, names, "ripples() line %d" % (line + 1))
		if parsed == null:
			return
		_lines.append(parsed)
		if text.begins_with("float "):
			names.append(text.get_slice(" ", 1))
	_read_call(lines)


## What kept the shader from being read, or "" when it was.
func problem() -> String:
	return _problem


## How much the ripples drift, for a surface with `flow`: the largest time average of the ripple
## field over a grid of points, while it's watched. A standing pattern (only the shimmer moving it)
## keeps a time average of about half its height at most points; one that drifts along the flow
## moves through every phase at each point, which averages it out to about 0 everywhere.
func standing(flow: Vector2) -> float:
	var extra: Array = []
	var glsl: GlslMath = GlslMath.new()
	for argument: Expression in _extra_arguments:
		extra.append(argument.execute([flow], glsl))
		if argument.has_execute_failed():
			_problem = "can't evaluate a ripples() argument: %s" % argument.get_error_text()
			return 0.0
	var largest: float = 0.0
	for column: int in WATCH_POINTS:
		for row: int in WATCH_POINTS:
			var at: Vector2 = Vector2(column, row) * WATCH_SPAN / WATCH_POINTS
			var sum: float = 0.0
			var samples: int = int(WATCH_TIME / WATCH_STEP)
			for sample: int in samples:
				sum += _ripple(at, sample * WATCH_STEP, extra)
			largest = maxf(largest, absf(sum / samples))
	return largest


## The fragment's call of `ripples()`: each argument after `at` and `time`, as an expression of the
## surface's `flow_direction`, a bare name standing for the fragment's line that defines it.
func _read_call(lines: PackedStringArray) -> void:
	var called: String = ""
	var defined: Dictionary[String, String] = {}
	for text: String in lines:
		var stripped: String = text.strip_edges()
		if stripped.begins_with("float ") and stripped.contains(" = "):
			defined[stripped.get_slice(" ", 1)] = stripped.get_slice(" = ", 1).trim_suffix(";")
		if stripped.contains(" ripples(") and not stripped.begins_with("float ripples("):
			called = stripped.get_slice(" ripples(", 1).trim_suffix(";").trim_suffix(")")
	if called.is_empty():
		_problem = "never calls ripples()"
		return
	var arguments: Array[String] = _split_arguments(called)
	if arguments.size() != _parameters.size():
		_problem = "calls ripples() with %d arguments for its %d parameters" % [
			arguments.size(),
			_parameters.size(),
		]
		return
	for index: int in range(2, arguments.size()):
		var argument: String = arguments[index].strip_edges()
		var source: String = defined.get(argument, argument)
		var parsed: Expression = _parse(
			source,
			["flow_direction"],
			"the ripples() argument " + argument,
		)
		if parsed == null:
			return
		_extra_arguments.append(parsed)


## `source` parsed with the inputs `names`, or null, saying in `problem()` that `what` can't be
## read.
func _parse(source: String, names: Array[String], what: String) -> Expression:
	var parsed: Expression = Expression.new()
	if parsed.parse(source, PackedStringArray(names)) != OK:
		_problem = "can't read %s: %s" % [what, parsed.get_error_text()]
		return null
	return parsed


## `arguments`, split at the commas outside parentheses.
static func _split_arguments(arguments: String) -> Array[String]:
	var split: Array[String] = []
	var depth: int = 0
	var current: String = ""
	for character: String in arguments:
		if character == "(":
			depth += 1
		elif character == ")":
			depth -= 1
		if character == "," and depth == 0:
			split.append(current)
			current = ""
		else:
			current += character
	split.append(current)
	return split


func _ripple(at: Vector2, time: float, extra: Array) -> float:
	var values: Array = [at, time]
	values.append_array(extra)
	var result: float = 0.0
	for line: Expression in _lines:
		result = float(line.execute(values))
		values.append(result)
	return result


## The shader functions the fragment's lines use that Expression doesn't know.
class GlslMath:
	func length(vector: Vector2) -> float:
		return vector.length()
