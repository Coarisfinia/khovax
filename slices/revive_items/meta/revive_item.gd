class_name ReviveItem
extends RefCounted
## The revive item (#656): a herb that brings back one fainted carried monster, anywhere. It drops
## from chests and loot tables like any other item (the loot slice's data/loot_tables/), each
## player rolling their own into their own profile (#74, #124), where it's counted with their
## materials; crafting it at the base is #657. Using one is a request from the player's profile's
## outbox (#818, ProfileTie), posted while their profile holds one, in the same change as it's
## spent from it; the simulation revives (ReviveItemFeature).

## The item's id, in the loot tables and the profile.
const ID: String = "revive_herb"


## How many revive items the profile `holder` holds: none without one, or while its save can't be
## read.
static func held(holder: ProfileHolder) -> int:
	if holder == null or holder.keeper == null:
		return 0
	var count: int = holder.keeper.profile.materials.get(ID, 0)
	return count


## The short ids of the monsters a revive item the profile `holder` used is on its way to (#818):
## its revive requests the world hasn't acknowledged yet, so another item isn't wasted on them.
static func on_the_way(holder: ProfileHolder) -> PackedStringArray:
	var reviving: PackedStringArray = PackedStringArray()
	if holder == null or holder.keeper == null:
		return reviving
	for request: OutboxEntry in holder.keeper.profile.outbox.entries:
		if request.kind == OutboxEntry.REVIVE:
			var _added: bool = reviving.append(ShortId.of_code(request.data))
	return reviving
