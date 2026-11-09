class_name Might
extends RefCounted
## A player's Might (#508, decided on #504): their power as one number, never called a level. It's
## summed from parts, each worked out by its own rule, integers only. The carried monsters weigh
## most, so their part counts in full. Gear, abilities and one-time boons add their own parts once
## they exist (#223, #512). Each player's Might is their own, from their own profile.

## How much a monster's strength counts next to its HP and speed in its part: it's what hits.
const STRENGTH_WEIGHT: int = 2


## `profile`'s Might, with the species' stats from `species` (by id).
static func of(profile: Profile, species: Dictionary[String, Species]) -> int:
	return monsters_part(profile, species)


## The carried monsters' part: for each, its species' HP, twice its strength and its speed, times
## its level. A monster of a species the data lacks adds nothing.
static func monsters_part(profile: Profile, species: Dictionary[String, Species]) -> int:
	var total: int = 0
	for monster: DominatedMonster in profile.dominated_monsters:
		var stats: Species = species.get(monster.species)
		if not profile.carried.has(monster.short_id) or stats == null:
			continue
		total += (stats.hp + STRENGTH_WEIGHT * stats.strength + stats.speed) * monster.level
	return total
