class_name Territory
extends RefCounted
## A faction's territory (#637, decided on #548): instances, each held by one faction or by none.
## Who holds an instance is a world flag naming both, HELD_<instance>_BY_<faction>, kept, saved and
## hashed with the World's other flags (#529), so it lasts between sessions. Instance names and
## faction ids are lowercase (Content.is_id), so the upper-case parts split the flag unambiguously.
## Who holds what when a world starts is the factions' content data (Faction.territory); the
## territory quests (#638) will move it.

const FLAG_START: String = "HELD_"
const FLAG_BY: String = "_BY_"


## The flag saying the faction `faction_id` holds the instance `instance_name`.
static func flag(instance_name: String, faction_id: String) -> String:
	return FLAG_START + instance_name + FLAG_BY + faction_id


## The id of the faction holding the instance `instance_name` by the world's `flags` (sorted), or ""
## when none does. Should two flags name holders, the first in sorted order holds it.
static func holder(flags: Array[String], instance_name: String) -> String:
	var start: String = FLAG_START + instance_name + FLAG_BY
	for held: String in flags:
		if held.begins_with(start):
			return held.substr(start.length())
	return ""


## The flags a fresh world starts with: every faction's territory in `content`, by faction id.
static func starting_flags(content: FactionContent) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(content.factions.keys())
	ids.sort()
	var flags: Array[String] = []
	for faction_id: String in ids:
		for instance_name: String in content.factions[faction_id].territory:
			flags.append(flag(instance_name, faction_id))
	return flags
