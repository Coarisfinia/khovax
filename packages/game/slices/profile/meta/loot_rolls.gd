class_name LootRolls
extends RefCounted
## Which events carry loot every player rolls for themselves (owner, #124), named once (#947) for
## both the profile, which takes a player's roll (ProfileTie), and the quests, which count it
## (QuestFacts): a new loot source goes here, so neither misses it.


## The events that carry such loot, each a class the bus delivers by.
static func events() -> Array[Script]:
	return [ChestOpened, LootFound, DominationLoot, Harvested, TileHarvested]


## Every player's loot from `event`, by slot, {slot: {item id: amount}}: from an opened chest
## (#124), the ground (#203), a domination (#86), a felled wild monster (#629) or a tile harvested
## by hand (#696). None otherwise.
static func of(event: RefCounted) -> Dictionary[int, Dictionary]:
	var none: Dictionary[int, Dictionary] = {}
	if event is ChestOpened:
		return (event as ChestOpened).loot
	if event is LootFound:
		return (event as LootFound).loot
	if event is DominationLoot:
		return (event as DominationLoot).loot
	if event is Harvested:
		return (event as Harvested).loot
	if event is TileHarvested:
		return (event as TileHarvested).loot
	return none
