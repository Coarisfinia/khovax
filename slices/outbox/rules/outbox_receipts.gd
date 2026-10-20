class_name OutboxReceipts
extends RefCounted
## The world's record of the requests it applied from players' outboxes (#771, Outbox): the short
## ids
## of the ones the feature carrying out their kind applied, kept in that feature's entry in the
## player's world store (#724), so they last between sessions and a request sent again is never
## applied twice. A feature carrying out a kind of request takes each one through `take`.

## The key of the applied ids in a feature's store entry.
const APPLIED: String = "applied"


## Takes the request `request` of the player in `slot` for the feature `feature_id`, inside its
## step: acknowledges it (RequestApplied) and returns whether it's new, so the feature carries it
## out, recording it as applied. A command without an id (Command.NO_REQUEST, #818) or with a code
## that's no short id's (ShortId.of_code) never comes from an outbox, so it's never applied.
static func take(state: GameState, slot: int, feature_id: String, request: int) -> bool:
	var id: String = ShortId.of_code(request)
	if id.is_empty():
		return false
	state.events.append(RequestApplied.new(slot, id))
	var entry: Dictionary = state.store(slot, feature_id)
	var applied: Array = entry.get(APPLIED, [])
	if applied.has(id):
		return false
	applied.append(id)
	entry[APPLIED] = applied
	return true
