class_name ItemPicture
extends SubViewportContainer
## A piece of gear's picture beside its slot (#1581): its model (GearItem.model) on its own stage
## (ModelStage), or nothing while the slot is empty. Its side grows with the panel's text.

## How wide and high the picture is, in the panel's font sizes.
const SIDE_FONTS: float = 3.0

## The model shown, or "" for none; kept here so tests can read it.
var shown: String = ""
var _stage: ModelStage


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stage = ModelStage.new()
	add_child(_stage)


func _process(_delta: float) -> void:
	var side: float = roundf(get_theme_default_font_size() * SIDE_FONTS)
	if custom_minimum_size.x != side:
		custom_minimum_size = Vector2(side, side)


## Shows the model at `model`, a glTF model under assets/, or nothing for "".
func show_model(model: String) -> void:
	if model == shown:
		return
	shown = model
	var scene: PackedScene = load(model) as PackedScene if not model.is_empty() else null
	_stage.show_model(scene.instantiate() as Node3D if scene != null else null)
	# The space stays, so the slots' buttons line up whether they hold gear or not.
	modulate.a = 1.0 if scene != null else 0.0
