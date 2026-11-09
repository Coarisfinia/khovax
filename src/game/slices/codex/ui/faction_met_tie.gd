class_name FactionMetTie
extends Node
## Ties the faction names this machine's player has met (CodexKeeper) to the Character tab's
## standings (#1383): a faction they've met is listed at its standing even before anything moved
## it from its start (#1378), like the Odun Kragothai one rank below neutral. The panel's slice
## comes before the codex, so this hands the met names over instead of the panel asking for them.

## The menu whose Character tab lists the standings.
@export var menu: GameMenu
## Where the names met are kept.
@export var keeper: CodexKeeper


func _ready() -> void:
	# The menu builds its tabs when it's ready, which may be after this.
	if not menu.is_node_ready():
		await menu.ready
	menu.character.factions.met = keeper.met_ids.bind(TextTags.FACTION)
