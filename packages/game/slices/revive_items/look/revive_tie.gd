class_name ReviveTie
extends ReviveOffer
## Uses a revive item (#656) when this machine's player picks a fainted monster to revive
## (LocalInput's revive_chosen): spends it from their profile and posts the request to its outbox
## (#818) in one change, which the profile's tie (ProfileTie) sends in their next command. It also
## tells the input which fainted monsters an item may go to (`offered`), so the controls never name
## the revive item or the profile (#851). It lives here, not in the profile, so the profile never
## names the revive item either.

## Where the player picks the fainted monster to revive.
@export var input: LocalInput
## The profile the item is spent from.
@export var holder: ProfileHolder


func _ready() -> void:
	var _connected: int = input.revive_chosen.connect(_revive)


func _revive(short_id: String) -> void:
	holder.spend_on(ReviveItem.ID, OutboxEntry.REVIVE, ShortId.code(short_id))


## The fainted monsters of the player in `slot` a revive item may go to, while this machine's
## player's profile holds one: none an item is already on its way to (#818).
func offered(state: GameState, slot: int) -> PackedStringArray:
	var fainted: PackedStringArray = PackedStringArray()
	if ReviveItem.held(holder) <= 0:
		return fainted
	var on_the_way: PackedStringArray = ReviveItem.on_the_way(holder)
	for short_id: String in ReviveItemFeature.fainted(state, slot):
		if not on_the_way.has(short_id):
			var _added: bool = fainted.append(short_id)
	return fainted
