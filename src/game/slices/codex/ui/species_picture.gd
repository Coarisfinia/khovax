class_name SpeciesPicture
extends SubViewportContainer
## A species' picture on its bestiary page (#1190): its idling model on its own stage
## (SpeciesStage), the way the codex page shows a species the player has seen. Its side grows with
## the page's text.

## How wide and high the picture is, in the page's font sizes.
const SIDE_FONTS: float = 12.0

## The model shown, kept here so tests can read it.
var model: Node3D
var _species_id: String = ""


func _init(species_id: String) -> void:
	_species_id = species_id
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	var stage: SpeciesStage = SpeciesStage.new(_species_id)
	add_child(stage)
	model = stage.model


func _process(_delta: float) -> void:
	var side: float = roundf(get_theme_default_font_size() * SIDE_FONTS)
	if custom_minimum_size.x != side:
		custom_minimum_size = Vector2(side, side)
