class_name UniqueItemTie
extends Node
## Ties the unique items this machine's player holds to the codex (#1449): holding one, gear of
## rarity bound, for the first time meets its name, so the codex book lists it, as entering a place
## lists that (PlaceTie). The keeper keeps it in their profile; this only watches what they own.

## The profile, whose gear says what the player owns.
@export var holder: ProfileHolder
## Where the names met are kept.
@export var keeper: CodexKeeper

## Every unique item's id, read once: they don't change while the game runs.
var _unique_ids: Array[String] = []


func _ready() -> void:
	for item: GearItem in GearContent.cached().items.values():
		if item.is_unique():
			_unique_ids.append(item.id)


func _process(_delta: float) -> void:
	if holder.keeper == null:
		return
	var owned: Dictionary[String, int] = holder.keeper.profile.gear.owned
	for id: String in _unique_ids:
		if owned.get(id, 0) > 0 and not keeper.has_met(TextTags.UNIQUE_ITEM, id):
			keeper.meet(TextTags.UNIQUE_ITEM, id)
