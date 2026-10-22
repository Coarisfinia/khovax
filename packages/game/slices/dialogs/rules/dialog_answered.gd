class_name DialogAnswered
extends RefCounted
## Event: a player chose an answer in a dialog this tick (#635). Quests can count it for that player
## (#636), like PlaceReached.

## The dialog's id and the chosen answer's, as the dialog's file names them.
var dialog: String
var answer: String
## The player's entity and slot.
var entity_id: int
var slot: int


func _init(dialog_id: String, answer_id: String, answering_id: int, player_slot: int) -> void:
	dialog = dialog_id
	answer = answer_id
	entity_id = answering_id
	slot = player_slot
