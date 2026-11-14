extends RefCounted
## The model render's framing (render_in_game.gd, #2366): what its still shots frame of every
## model in the default pack holds all of the model as the shots show it, idling on its Idle's
## first frame. A model whose rest pose stands elsewhere, as the Nuvvoluvvo's does, is otherwise
## framed off its body: the face close-up shows its chest and legs.

const RenderInGame: GDScript = preload("res://tools/models/render_in_game.gd")
const MODELS: String = "res://resourcepacks/default/models"
## How far a shown vertex may lie outside the framed box, in metres: float noise only.
const SLACK: float = 0.001


func run(tree: SceneTree) -> String:
	var checked: int = 0
	for folder: String in DirAccess.get_directories_at(MODELS):
		var path: String = MODELS.path_join(folder).path_join(folder + ".glb")
		if not ResourceLoader.exists(path):
			continue
		var model: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		tree.root.add_child(model)
		var problem: String = _unframed(model)
		model.free()
		if problem == "-":
			continue
		if not problem.is_empty():
			return "%s: %s" % [folder, problem]
		checked += 1
	return "" if checked > 0 else "no model with an Idle found in " + MODELS


## What of `model`, idling as the shots show it, lies outside what they frame, "" when nothing
## does, or "-" when it has no Idle to show.
func _unframed(model: Node3D) -> String:
	var animations: AnimationPlayer = model.find_child("AnimationPlayer") as AnimationPlayer
	if animations == null or not animations.has_animation(&"Idle"):
		return "-"
	var framed: PackedVector3Array = RenderInGame.framed_points(model)
	if framed.is_empty():
		return "no vertices framed"
	var box: AABB = AABB(framed[0], Vector3.ZERO)
	for point: Vector3 in framed:
		box = box.expand(point)
	box = box.grow(SLACK)
	animations.play(&"Idle")
	animations.seek(0.0, true)
	var shown: PackedVector3Array = RenderInGame.points_of(model)
	var outside: int = 0
	var farthest: Vector3 = Vector3.ZERO
	for point: Vector3 in shown:
		if not box.has_point(point):
			outside += 1
			farthest = point
	if outside == 0:
		return ""
	return "%d of its %d vertices on Idle's first frame lie outside the framed %s, e.g. %s" % [
		outside,
		shown.size(),
		box,
		farthest,
	]
