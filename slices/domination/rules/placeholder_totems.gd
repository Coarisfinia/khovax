class_name PlaceholderTotems
extends RefCounted
## Every player's placeholder totem (#423), until totem items exist (#424): a player arriving in
## the instance holds one with CHARGES charges, and placing it on a ring that waits for a totem
## spends one. Its charges don't refill yet (#424). DominationFeature keeps it per instance, so a
## player arriving in another instance holds a full one there.

## The charges a placeholder totem starts with. A placeholder, to tune.
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
	var ids: Array[int] = []
	ids.assign(charges.keys())
	ids.sort()
	var values: Array[int] = []
	for each: int in ids:
		values.append_array([each, charges[each]])
	return values


## Restores the totems from `values` (as `flat` gives them); returns why they can't be, or "":
## each must be a player's in `state`, in increasing id order, with 0 to CHARGES charges, and every
## player there must have one.
func load_flat(state: GameState, values: Array[int]) -> String:
	charges.clear()
	if values.size() % 2 != 0:
		return "a totem's charges are cut off"
	for i: int in range(0, values.size(), 2):
		var holder: Entity = state.entity(values[i])
		var in_order: bool = i == 0 or values[i] > values[i - 2]
		if holder == null or holder.slot == Entity.NO_SLOT or not in_order:
			return "totem of %d isn't one player's, or is out of order" % values[i]
		if values[i + 1] < 0 or values[i + 1] > CHARGES:
			return "totem of %d has %d charges" % [values[i], values[i + 1]]
		charges[values[i]] = values[i + 1]
	for entity: Entity in state.entities:
		if entity.slot != Entity.NO_SLOT and not charges.has(entity.id):
			return "player %d has no totem" % entity.id
	return ""
