class_name MoveHintKeeper
extends ProfileCompanion
## Keeps whether this machine's player has walked yet (#1222): the move hint (MoveHint) shows until
## they first do, once per profile. Kept in their profile's file beside the profile, whose companion
## it is (ProfileHolder.companions), as `walked`.

## The profile save format the move hint starts in (ProfileSave.FORMAT then).
const SINCE_FORMAT: int = 25
## The save's key.
const KEY: String = "walked"

## The profile it's kept with.
@export var holder: ProfileHolder

## Whether the player has walked since the profile began.
var walked: bool = false


## Notes that the player walked, saved with the profile's next save; once is enough.
func walk() -> void:
	if walked:
		return
	if holder != null:
		holder.note(_walk)
	walked = true


func migrate(data: Dictionary, format: int) -> void:
	# Format 24 to 25: a profile saved before has played, so the hint for a new game stays away.
	if format < SINCE_FORMAT:
		data[KEY] = true


func read(data: Dictionary) -> String:
	var raw: Variant = data.get(KEY)
	if not raw is bool:
		return "the save lacks whether the player has walked"
	walked = raw
	return ""


func started() -> void:
	walked = false


func beside() -> Dictionary:
	return { KEY: walked }


## Notes the walk; the profile itself doesn't change.
func _walk(_profile: Profile) -> void:
	walked = true
