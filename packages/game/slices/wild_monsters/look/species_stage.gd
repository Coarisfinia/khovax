class_name SpeciesStage
extends ModelStage
## A species' picture (#1190, #722): its model (the one its monsters wear, SpeciesModels) idling on
## its own stage (ModelStage), its eyes glowing in its type's colour. Its texture is what shows:
## framed on a bestiary page (SpeciesPicture), and in a roster's square (RosterHud).

var _species_id: String = ""


func _init(species_id: String) -> void:
	super()
	_species_id = species_id


func _ready() -> void:
	var shown: Node3D = WildMonsterView.model_of(_species_id)
	EyeGlow.of(shown).color = TypeGlow.of(_species_id)
	show_model(shown)
	WildMonsterView.idle(shown)
