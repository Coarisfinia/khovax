class_name SceneContent
extends Content
## The scenes' content data (#2415), which the scenes slice owns (#412): one JSONC file per scene,
## checked against scenes.schema.json in CI. They're the resource packs' (#1888), so a player's
## pack can add or replace one; the default pack's lie in resourcepacks/default/scenes/.

## The scenes' key in the content cache (ContentCatalog).
const KEY: String = "scenes"
## The JSON Schema declaring the scene file's top-level fields.
const SCHEMA: String = "res://slices/scenes/data/scenes.schema.json"
## Allowed fields for each step kind.
const WAIT_FIELDS: Array[String] = ["kind", "ticks"]
const MOVE_FIELDS: Array[String] = ["kind", "actor", "to", "pace"]
const STRIKE_FIELDS: Array[String] = ["kind", "actor", "target", "amount", "lethal"]
const EMIT_FIELDS: Array[String] = ["kind", "event"]

## Every scene, by its id.
var scenes: Dictionary[String, SceneScript] = {}


## Every scene the resource packs list, read and checked.
static func load_scenes() -> SceneContent:
	return load_files(_scene_files())


## Every scene in `files` (each res:// path by its id), read and checked.
static func load_files(files: Dictionary[String, String]) -> SceneContent:
	var content: SceneContent = SceneContent.new()
	content.read_files(files)
	return content


## The scenes, read once per session (ContentCatalog).
static func cached() -> SceneContent:
	return ContentCatalog.kept(KEY, load_scenes)


## Every scene file across loaded resource packs, in lookup order (first pack wins per id).
static func _scene_files() -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for pack: ResourcePack in ResourcePacks.loaded():
		var listed: Dictionary[String, String] = pack.files_of(KEY)
		for resource_id: String in listed:
			if not found.has(resource_id):
				found[resource_id] = pack.root + listed[resource_id]
	found.sort()
	return found


## Whether any loaded scene applies to `instance_name` (targets it or targets any instance).
func has_for(instance_name: String) -> bool:
	for scene_id: String in scenes:
		var candidate: SceneScript = scenes[scene_id]
		if candidate.instance.is_empty() or candidate.instance == instance_name:
			return true
	return false


## Every scene that applies to `instance_name`, by scene id.
func for_instance(instance_name: String) -> Dictionary[String, SceneScript]:
	var matching: Dictionary[String, SceneScript] = {}
	for scene_id: String in scenes:
		var candidate: SceneScript = scenes[scene_id]
		if candidate.instance.is_empty() or candidate.instance == instance_name:
			matching[scene_id] = candidate
	return matching


func add(file_id: String, text: String) -> String:
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		return Content.NOT_AN_OBJECT
	var data: Dictionary = parsed
	var why: String = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	if not why.is_empty():
		return why
	var built: SceneScript = SceneScript.new()
	why = _read_header(file_id, data, built)
	if not why.is_empty():
		return why
	why = _read_steps(data.get("steps"), built.steps)
	if not why.is_empty():
		return why
	scenes[built.id] = built
	return ""


## Reads top-level scene metadata (`id`, `instance`, `on`, `once`) into `built`.
static func _read_header(file_id: String, data: Dictionary, built: SceneScript) -> String:
	built.id = Content.text_of(data.get("id"))
	var why: String = Content.id_problem(built.id, file_id)
	if not why.is_empty():
		return why
	if data.has("instance"):
		built.instance = Content.text_of(data.get("instance"))
		if not Content.is_id(built.instance):
			return "instance must be a valid id"
	built.on = Content.text_of(data.get("on"))
	if not Content.is_id(built.on):
		return "on must be a valid event id"
	if data.has("once"):
		if not data["once"] is bool:
			return "once must be a boolean"
		built.once = data["once"]
	return ""


## Reads the non-empty steps list `raw_steps` into `out_steps`.
static func _read_steps(raw_steps: Variant, out_steps: Array[SceneStep]) -> String:
	if not raw_steps is Array:
		return "steps must be a non-empty list"
	var step_list: Array = raw_steps
	if step_list.is_empty():
		return "steps must be a non-empty list"
	for index: int in step_list.size():
		var why: String = _append_step(step_list[index], out_steps)
		if not why.is_empty():
			return "step %d: %s" % [index, why]
	return ""


## Parses one step and appends it to `out_steps`, returning why it's invalid or "".
static func _append_step(raw: Variant, out_steps: Array[SceneStep]) -> String:
	var step_result: SceneStep = SceneStep.new()
	var why: String = _read_step(raw, step_result)
	if why.is_empty():
		out_steps.append(step_result)
	return why


## Reads one step dictionary into `out`, returning why it's invalid or "".
static func _read_step(raw: Variant, out: SceneStep) -> String:
	if not raw is Dictionary:
		return "must be an object"
	var data: Dictionary = raw
	var kind: String = Content.text_of(data.get("kind"))
	match kind:
		SceneStep.WAIT:
			return _read_wait(data, out)
		SceneStep.MOVE:
			return _read_move(data, out)
		SceneStep.STRIKE:
			return _read_strike(data, out)
		SceneStep.EMIT:
			return _read_emit(data, out)
		_:
			return "unknown step kind %s" % kind


static func _read_wait(data: Dictionary, out: SceneStep) -> String:
	var why: String = Content.unknown_field(data, WAIT_FIELDS)
	if not why.is_empty():
		return why
	var ticks: int = JsonNumbers.whole(data.get("ticks"), 1, DataReader.MOST, 0)
	if ticks == 0:
		return "ticks must be a positive integer"
	out.kind = SceneStep.WAIT
	out.ticks = ticks
	return ""


static func _read_move(data: Dictionary, out: SceneStep) -> String:
	var why: String = Content.unknown_field(data, MOVE_FIELDS)
	if not why.is_empty():
		return why
	var actor: String = Content.text_of(data.get("actor"))
	if not Content.is_id(actor):
		return "actor must be a valid id"
	var coords: Variant = data.get("to")
	if not coords is Array:
		return "to must be [q, r]"
	var pair: Array = coords
	if pair.size() != 2:
		return "to must be [q, r]"
	var invalid: int = DataReader.MOST + 1
	var q: int = JsonNumbers.whole(pair[0], -DataReader.MOST, DataReader.MOST, invalid)
	var r: int = JsonNumbers.whole(pair[1], -DataReader.MOST, DataReader.MOST, invalid)
	if q == invalid or r == invalid:
		return "to coordinates must be whole integers"
	var pace: int = 0
	if data.has("pace"):
		pace = JsonNumbers.whole(data.get("pace"), 1, DataReader.MOST, 0)
		if pace == 0:
			return "pace must be a positive integer"
	out.kind = SceneStep.MOVE
	out.actor = actor
	out.to = Vector2i(q, r)
	out.pace = pace
	return ""


static func _read_strike(data: Dictionary, out: SceneStep) -> String:
	var why: String = Content.unknown_field(data, STRIKE_FIELDS)
	if not why.is_empty():
		return why
	var actor: String = Content.text_of(data.get("actor"))
	var target: String = Content.text_of(data.get("target"))
	if not Content.is_id(actor) or not Content.is_id(target):
		return "actor and target must be valid ids"
	var damage: int = JsonNumbers.whole(data.get("amount"), 1, Fixed.MAX_AMOUNT, 0)
	if damage == 0:
		return "amount must be a positive integer"
	var is_lethal: bool = false
	if data.has("lethal"):
		if not data["lethal"] is bool:
			return "lethal must be a boolean"
		is_lethal = data["lethal"]
	out.kind = SceneStep.STRIKE
	out.actor = actor
	out.target = target
	out.amount = damage
	out.lethal = is_lethal
	return ""


static func _read_emit(data: Dictionary, out: SceneStep) -> String:
	var why: String = Content.unknown_field(data, EMIT_FIELDS)
	if not why.is_empty():
		return why
	var event_name: String = Content.text_of(data.get("event"))
	if not Content.is_id(event_name):
		return "event must be a valid id"
	out.kind = SceneStep.EMIT
	out.event = event_name
	return ""
