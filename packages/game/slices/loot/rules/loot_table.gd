class_name LootTable
extends RefCounted
## What a roll can give (#90), read from content data (the loot slice's data/loot_tables/, #72,
## #412) by LootTableFile.
## Each entry is an item in an amount from `min` to `max`, or the blank, with a chance in
## thousandths; the chances add up to Fixed.ONE (100 %). A species table (rolled on a domination,
## #86) and a harvest table (rolled on a felled wild monster, #687, in data/harvest_tables/) always
## hold one blank, which rolls on the instance's table instead, so a blank is never nothing (owner,
## #90). An instance table holds none, and neither does a chest table (what an instance's chests
## hold, #694: crafting supplies and basic gear, by the gear's id), nor a tile table (what a
## harvested tile drops, #696). Rolls draw from the Rng they're given, so the same stream rolls the
## same loot.

const SPECIES: String = "species"
const HARVEST: String = "harvest"
const INSTANCE: String = "instance"
const CHEST: String = "chest"
const TILE: String = "tile"
const KINDS: Array[String] = [SPECIES, HARVEST, INSTANCE, CHEST, TILE]

var id: String = ""
var kind: String = ""
## Each entry's item id, or "" for the blank.
var items: Array[String] = []
## Each entry's chance, in thousandths.
var chances: Array[int] = []
## Each entry's smallest and largest amount (both 0 for the blank).
var mins: Array[int] = []
var maxes: Array[int] = []
## Why the table couldn't be read, or "" when it could.
var problem: String = ""


## Rolls one entry: its item and amount, as {item: amount}. A blank rolls on `instance_table`, or
## gives nothing without one.
func roll(rng: Rng, instance_table: LootTable) -> Dictionary[String, int]:
	var picked: int = rng.pick_weighted(chances)
	var none: Dictionary[String, int] = {}
	if items[picked].is_empty():
		return instance_table.roll(rng, null) if instance_table != null else none
	return { items[picked]: rng.between(mins[picked], maxes[picked]) }


## Rolls `times` times, adding up what each roll gave, as {item: amount}.
func roll_times(rng: Rng, times: int, instance_table: LootTable) -> Dictionary[String, int]:
	var found: Dictionary[String, int] = {}
	for _roll: int in times:
		var drawn: Dictionary[String, int] = roll(rng, instance_table)
		for item: String in drawn:
			var had: int = found.get(item, 0)
			found[item] = had + drawn[item]
	return found
