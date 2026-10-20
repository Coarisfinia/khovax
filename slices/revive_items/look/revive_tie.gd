class_name ReviveTie
extends Node
## Uses a revive item (#656) when this machine's player picks a fainted monster to revive
## (LocalInput's revive_chosen): spends it from their profile and posts the request to its outbox
## (#818) in one change, which the profile's tie (ProfileTie) sends in their next command. It lives
## here, not in the profile, so the profile never names the revive item (#851).

## Where the player picks the fainted monster to revive.
@export var input: LocalInput
## The profile the item is spent from.
@export var holder: ProfileHolder


func _ready() -> void:
	var _connected: int = input.revive_chosen.connect(_revive)


func _revive(short_id: String) -> void:
	holder.spend_on(ReviveItem.ID, OutboxEntry.REVIVE, ShortId.code(short_id))
