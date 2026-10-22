class_name BestiaryKeeper
extends ProfileCompanion
## Keeps what this machine's player has learned about each species (Bestiary, #1173) in their
## profile's file, beside the profile (BestiarySave), whose companion it is
## (ProfileHolder.companions), so the two are saved together. What they learn (BestiaryTie) is
## taken at once and saved like a gain.

## The profile the bestiary is kept with.
@export var holder: ProfileHolder

var bestiary: Bestiary = Bestiary.new()


## What this player has learned, or null while their profile's save can't be read: the bestiary
## pages show nothing learned then, and nothing is learned.
func known() -> Bestiary:
	return bestiary if holder != null and holder.keeper != null else null


## What the player whose profile `profile_holder` holds has learned, from the bestiary kept beside
## it, or null without one or while their profile's save can't be read.
static func of(profile_holder: ProfileHolder) -> Bestiary:
	if profile_holder == null:
		return null
	for companion: ProfileCompanion in profile_holder.companions:
		if companion is BestiaryKeeper:
			return (companion as BestiaryKeeper).known()
	return null


## Learns `species` at `level` (Bestiary.SEEN, MET or KNOWN) in the instance `where`, saved with
## the profile, when it teaches this player anything new.
func learn(species: String, level: int, where: String) -> void:
	if known() != null and bestiary.teaches(species, level, where):
		holder.change(_learn.bind(species, level, where))


func _learn(_profile: Profile, species: String, level: int, where: String) -> void:
	bestiary.learn(species, level, where)


func migrate(data: Dictionary, format: int) -> void:
	BestiarySave.migrate(data, format)


func read(data: Dictionary) -> String:
	var loaded: Bestiary = Bestiary.new()
	var problem: String = BestiarySave.read(loaded, data)
	if problem.is_empty():
		bestiary = loaded
	return problem


func started() -> void:
	bestiary = Bestiary.new()


func beside() -> Dictionary:
	return BestiarySave.beside(bestiary)
