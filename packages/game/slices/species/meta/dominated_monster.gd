class_name DominatedMonster
extends RefCounted
## A monster the player dominated and owns (a `dominated_monster`, #45), kept in the profile between
## sessions. Its species is an id into the content data (#72), and its short id the one it had in
## the wild (#700): its one id, which tells it apart from every other monster in the world and in
## the profile, which keys it on it (#754). It grows in levels (#1251) by earning progress, which
## the profile hands it (Profile.apply).

## How much progress a level needs, times the level: from level L to L + 1 takes this times L.
const PROGRESS_PER_LEVEL: int = 3

var species: String = ""
## Unique in the profile (#754).
var short_id: String = ""
var level: int = 1
## The progress toward its next level, always below what its level needs (progress_needed).
var progress: int = 0


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
	}
	return data


## The progress a monster at `at_level` needs to reach the next level.
static func progress_needed(at_level: int) -> int:
	return PROGRESS_PER_LEVEL * at_level


## Adds `points` of progress, going up a level each time it reaches what its level needs.
func earn(points: int) -> void:
	progress += points
	while progress >= progress_needed(level):
		progress -= progress_needed(level)
		level += 1
