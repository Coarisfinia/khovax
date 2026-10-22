class_name PlaceholderTotems
extends RefCounted
## Every player's placeholder totem (#423), until totem items exist (#424): a player arriving in
## the instance holds one with CHARGES charges, and placing it on a ring that waits for a totem
## spends one. Its charges don't refill yet (#424). DominationFeature keeps it per instance, so a
## player arriving in another instance holds a full one there.

## The charges a placeholder totem starts with. A placeholder to tune (#960).
const CHARGES: int = 3

## Charges left, by the player's entity id.
var charges: Dictionary[int, int] = {}


## Gives the arriving player `player_id` a full totem.
func add(player_id: int) -> void:
	charges[player_id] = CHARGES


## Drops the totem of a player who left.
func drop(player_id: int) -> void:
	var _dropped: bool = charges.erase(player_id)


## Spends one of the player's charges; returns whether they had one to spend.
func spend(player_id: int) -> bool:
	if charges.get(player_id, 0) <= 0:
		return false
	charges[player_id] -= 1
	return true


## The charges the player `player_id` has left, 0 without a totem.
func charges_of(player_id: int) -> int:
	return charges.get(player_id, 0)


## Every totem as [entity id, charges, ...], in id order: for the save and the hash.
func flat() -> Array[int]:
	return DataReader.flat_pairs(charges)


## Restores the totems from `saved` (as `flat` gives them, read by `DataReader.pairs`); returns why
## they can't be, or "": each must be a player's in `state`, with 0 to CHARGES charges, and every
## player there must have one.
func load_flat(state: GameState, saved: Dictionary[int, int]) -> String:
	charges.clear()
	for holder_id: int in saved:
		var holder: Entity = state.entity(holder_id)
		if holder == null or holder.slot == Entity.NO_SLOT:
			return "totem of %d isn't one player's" % holder_id
		if saved[holder_id] < 0 or saved[holder_id] > CHARGES:
			return "totem of %d has %d charges" % [holder_id, saved[holder_id]]
		charges[holder_id] = saved[holder_id]
	for entity: Entity in state.entities:
		if entity.slot != Entity.NO_SLOT and not charges.has(entity.id):
			return "player %d has no totem" % entity.id
	return ""
