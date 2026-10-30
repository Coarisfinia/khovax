class_name KnownFormsTie
extends Node
## Ties what this machine's player has learned about each species (BestiaryKeeper) to the Character
## tab's monster details (#1801): the form a monster ascends into shows there, by its name and its
## first type's badge, once they've met one in a fight (Bestiary.MET), when its bestiary page shows
## its types too, and as a question mark until then. The list's slice comes before the codex, so
## this hands it what the player knows instead of the list asking for it.

## The menu whose Character tab lists the monsters.
@export var menu: GameMenu
## Where what the player has learned is kept.
@export var keeper: BestiaryKeeper


func _ready() -> void:
	# The menu builds its tabs when it's ready, which may be after this.
	if not menu.is_node_ready():
		await menu.ready
	menu.character.monsters.knows = _knows


## Whether the player knows `species` well enough to see its name and types: none while their
## profile's save can't be read.
func _knows(species: String) -> bool:
	var known: Bestiary = keeper.known()
	return known != null and known.level_of(species) >= Bestiary.MET
