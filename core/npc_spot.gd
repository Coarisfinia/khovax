class_name NpcSpot
extends RefCounted
## What a region piece's legend says about a person standing on one of its tiles (#557), a humanoid
## who never fights (owner's worldbuilding rules): their id, which quests and the profile name them
## by, and the dialog talking to them opens ("" for none, #635).

var id: String = ""
var dialog: String = ""


func _init(npc_id: String = "", dialog_id: String = "") -> void:
	id = npc_id
	dialog = dialog_id
