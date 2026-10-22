# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (reads schema files, #591)
class_name SchemaFields
extends RefCounted
## The fields a content kind's JSON Schema allows (#825), read from the schema beside its files, so
## a reader never keeps its own copy of them that a new schema field would leave behind. Each schema
## is read once and kept: they don't change while the game runs.

static var _schemas: Dictionary[String, Dictionary] = {}


## The fields the object at `pointer` (a JSON pointer into the schema, like
## "/properties/steps/items"; "" for a file's own fields) of the schema at `path` allows: its
## properties, and those of the schemas it refers to ($ref) or combines (allOf, anyOf, oneOf).
static func at(path: String, pointer: String = "") -> Array[String]:
	var schema: Dictionary = _schema(path)
	var fields: Array[String] = []
	_collect(schema, _resolve(schema, pointer), fields)
	if fields.is_empty():
		push_error("%s allows no fields at \"%s\"" % [path, pointer])
	return fields


## The schema at `path`, read on first use; empty when it can't be read.
static func _schema(path: String) -> Dictionary:
	if not _schemas.has(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_schemas[path] = parsed if parsed is Dictionary else {}
	return _schemas[path]


## The part of `schema` that `pointer` points at, or null when there's none.
static func _resolve(schema: Dictionary, pointer: String) -> Variant:
	var node: Variant = schema
	for part: String in pointer.split("/", false):
		if node is Dictionary:
			var object: Dictionary = node
			node = object.get(part)
		elif node is Array:
			var list: Array = node
			if not part.is_valid_int() or int(part) < 0 or int(part) >= list.size():
				return null
			node = list[int(part)]
		else:
			return null
	return node


## Adds the fields `node`, a part of `schema`, allows to `fields`, each once.
static func _collect(schema: Dictionary, node: Variant, fields: Array[String]) -> void:
	if not node is Dictionary:
		return
	var object: Dictionary = node
	var properties: Variant = object.get("properties", {})
	if properties is Dictionary:
		for key: Variant in properties:
			if not fields.has(str(key)):
				fields.append(str(key))
	var target: String = Content.text_of(object.get("$ref"))
	if target.begins_with("#"):
		_collect(schema, _resolve(schema, target.substr(1)), fields)
	elif not target.is_empty():
		# Reading another file's schema isn't needed yet, so one that's referred to fails loudly
		# instead of leaving its fields out.
		push_error("a schema refers to another file (%s), which SchemaFields doesn't read" % target)
	for combined: String in ["allOf", "anyOf", "oneOf"]:
		var branches: Variant = object.get(combined, [])
		if branches is Array:
			for branch: Variant in branches:
				_collect(schema, branch, fields)
