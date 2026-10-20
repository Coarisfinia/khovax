class_name ReviveItem
extends RefCounted
## The revive item (#656): a herb that brings back one fainted carried monster, anywhere. It drops
## from chests and loot tables like any other item (the loot slice's data/loot_tables/), each
## player rolling their own into their own profile (#74, #124), where it's counted with their
## materials; crafting it at the base is #657. Using one is a press (Command.revive) that the
## player's own machine sends only while their profile holds one; the simulation revives
## (ReviveItemFeature), and the profile spends one on the MonsterRevived it raises (ProfileTie).

## The item's id, in the loot tables and the profile.
const ID: String = "revive_herb"


## How many revive items the profile `holder` holds: none without one, or while its save can't be
## read.
static func held(holder: ProfileHolder) -> int:
	if holder == null or holder.keeper == null:
		return 0
	var count: int = holder.keeper.profile.materials.get(ID, 0)
	return count
