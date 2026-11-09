class_name DominatedMonster
extends RefCounted
## A monster the player dominated and owns (a `dominated_monster`, #45), kept in the profile between
## sessions. Its species is an id into the content data (#72), and its short id the one it had in
## the wild (#700): its one id, which tells it apart from every other monster in the world and in
## the profile, which keys it on it (#754). It grows in levels (#1251) by earning progress, which
## the profile hands it (Profile.apply), and each level it gains lets it take a node of its
## species' development web (#1417, Profile.take_node).

## How much progress a level needs, times the level: from level L to L + 1 takes this times L.
const PROGRESS_PER_LEVEL: int = 3

var species: String = ""
## Unique in the profile (#754).
var short_id: String = ""
var level: int = 1
## The progress toward its next level, always below what its level needs (progress_needed).
var progress: int = 0
## The development web's nodes it has taken (#1417), by node id, in the order taken: at most one
## for each level it gained.
var taken: Array[String] = []


func _init(
	species_id: String = "",
	start_level: int = 1,
	monster_short_id: String = "",
	start_progress: int = 0,
) -> void:
	species = species_id
	level = start_level
	short_id = monster_short_id
	progress = start_progress


func to_data() -> Dictionary[String, Variant]:
	var data: Dictionary[String, Variant] = {
		"species": species,
		"short_id": short_id,
		"level": level,
		"progress": progress,
		"taken": taken,
	}
	return data


## The progress a monster at `at_level` needs to reach the next level.
static func progress_needed(at_level: int) -> int:
	return PROGRESS_PER_LEVEL * at_level


## How many nodes of its web it may still take: one for each level it gained, less those taken.
func picks_left() -> int:
	return level - 1 - taken.size()


## Adds `points` of progress, going up a level each time it reaches what its level needs.
func earn(points: int) -> void:
	progress += points
	while progress >= progress_needed(level):
		progress -= progress_needed(level)
		level += 1
