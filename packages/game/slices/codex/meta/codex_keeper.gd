class_name CodexKeeper
extends ProfileCompanion
## Keeps the names this machine's player has met (#1174), whose entries the codex book lists: a
## name with a codex page (TextTags.CODEX_KINDS) is met once a text has shown it to them, like a
## faction's name in a dialog's line. Kept in their profile's file beside the profile, whose
## companion it is (ProfileHolder.companions), as `codex_met`: each kind's word, then the ids met,
## in order.

## The save's key.
const KEY: String = "codex_met"

## The profile it's kept with.
@export var holder: ProfileHolder

## The ids met, by kind (TextTags.FACTION), each list in order.
var met: Dictionary[String, Array] = {}


## Whether the player has met the name of the thing of the kind `kind` with the id `id`.
func has_met(kind: String, id: String) -> bool:
	return met.has(kind) and (met[kind] as Array).has(id)


## The ids of the kind `kind` the player has met, in order.
func met_ids(kind: String) -> Array[String]:
	var known: Array = met.get(kind, [])
	var ids: Array[String] = []
	ids.assign(known)
	return ids


## Notes that the player met the name of the thing of the kind `kind` with the id `id`, saved with
## the profile; a kind without a codex page, or a name met before, changes nothing.
func meet(kind: String, id: String) -> void:
	if holder == null or not TextTags.CODEX_KINDS.has(kind) or has_met(kind, id):
		return
	holder.change(_add.bind(kind, id))


func migrate(data: Dictionary, format: int) -> void:
	# Format 17 to 18: the book starts with nothing met.
	if format < 18:
		data[KEY] = {}


func read(data: Dictionary) -> String:
	var raw: Variant = data.get(KEY)
	if not raw is Dictionary:
		return "the save lacks the names met"
	var loaded: Dictionary[String, Array] = {}
	var by_kind: Dictionary = raw
	for kind: Variant in by_kind:
		var ids: Variant = by_kind[kind]
		if not TextTags.CODEX_KINDS.has(kind) or not ids is Array:
			return "the names met in the save name a kind without a codex page"
		var kept: Array[String] = []
		for id: Variant in ids:
			var text: String = Content.text_of(id)
			if not Content.is_id(text) or kept.has(text):
				return "a name met in the save has no valid id or is there twice"
			kept.append(text)
		kept.sort()
		loaded[str(kind)] = kept
	met = loaded
	return ""


func started() -> void:
	met = {}


func beside() -> Dictionary:
	var by_kind: Dictionary = {}
	var kinds: Array[String] = []
	kinds.assign(met.keys())
	kinds.sort()
	for kind: String in kinds:
		by_kind[kind] = met[kind]
	return { KEY: by_kind }


## Adds the id `id` to the kind `kind`'s names met, in order; the profile itself doesn't change.
func _add(_profile: Profile, kind: String, id: String) -> void:
	var ids: Array[String] = met_ids(kind)
	ids.append(id)
	ids.sort()
	met[kind] = ids
