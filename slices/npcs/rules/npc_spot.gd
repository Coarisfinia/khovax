class_name NpcSpot
extends RefCounted
## What a region piece's legend says about a person standing on one of its tiles (#557), a humanoid
## who never fights (owner's worldbuilding rules): their id, which quests and the profile name them
## by, and the dialog talking to them opens ("" for none, #635). The legend says
## `a person to talk to, <npc id>`, with `, saying <dialog id>` after it for a dialog, e.g.
## `a person to talk to, teska_na_amvrel, saying teska_na_amvrel_greeting`.

## How a person's legend meaning begins, and what it says before the dialog they open.
const NPC: String = "a person to talk to, "
const SAYING: String = ", saying "

var id: String = ""
var dialog: String = ""


func _init(npc_id: String = "", dialog_id: String = "") -> void:
	id = npc_id
	dialog = dialog_id


## The person a legend `meaning` places, or null when it places none.
static func read(meaning: String) -> NpcSpot:
	if not meaning.begins_with(NPC):
		return null
	var said: PackedStringArray = meaning.trim_prefix(NPC).split(SAYING)
	var dialog_id: String = said[1] if said.size() == 2 else ""
	var named: bool = said.size() <= 2 and said[0].is_valid_ascii_identifier()
	if named and (dialog_id.is_empty() or dialog_id.is_valid_ascii_identifier()):
		return NpcSpot.new(said[0], dialog_id)
	return null
