class_name OutboxReceipts
extends RefCounted
## The world's record of the requests it applied from players' outboxes (#771, Outbox): the short
## ids
## of the ones the feature carrying out their kind applied, kept in that feature's entry in the
## player's world store (#724), so they last between sessions and a request sent again is never
## applied twice. A feature carrying out a kind of request takes each one through `take`.
##
## The record stays small (#942): every command carries the newest request id up to which the
## player's profile saw every request acknowledged (Command.acknowledged), and the feature keeps
## the highest such mark instead of the receipts at or below it, refusing any id at or below it
## that's sent again. A profile draws its ids in order (Outbox), so a mark covers exactly the
## requests it will never need applied again.

## The key of the applied ids in a feature's store entry.
const APPLIED: String = "applied"
## The key of the highest acknowledged mark (Command.acknowledged) in a feature's store entry.
const MARK: String = "acknowledged"


## Takes the request `command` of the player in `slot` carries for the feature `feature_id`,
## inside its step: acknowledges it (RequestApplied) and returns whether it's new, so the feature
## carries it out, recording it as applied, and forgets the receipts the command's mark covers. A
## command without an id (Command.NO_REQUEST, #818) or with a code that's no short id's
## (ShortId.of_code) never comes from an outbox, so it's never applied.
static func take(state: GameState, slot: int, feature_id: String, command: Command) -> bool:
	var id: String = ShortId.of_code(command.request)
	if id.is_empty():
		return false
	state.events.append(RequestApplied.new(slot, id))
	var entry: Dictionary = state.store(slot, feature_id)
	var marked: int = entry.get(MARK, Command.NO_REQUEST)
	var mark: int = marked
	# A mark that's no short id's code (ShortId.of_code) never comes from an outbox.
	if not ShortId.of_code(command.acknowledged).is_empty():
		mark = maxi(marked, command.acknowledged)
	var applied: Array = []
	for applied_id: Variant in entry.get(APPLIED, []):
		if ShortId.code(str(applied_id)) > mark:
			applied.append(applied_id)
	var fresh: bool = command.request > mark and not applied.has(id)
	if fresh:
		applied.append(id)
	if mark > Command.NO_REQUEST:
		entry[MARK] = mark
	if applied.is_empty():
		var _forgot: bool = entry.erase(APPLIED)
	else:
		entry[APPLIED] = applied
	return fresh


## The highest request code the world store `store` of a player holds, as a receipt or a mark, or
## Command.NO_REQUEST: the profile draws its next ids above it (Outbox.catch_up), so none is
## refused as one applied before.
static func highest(store: PlayerStore) -> int:
	var most: int = Command.NO_REQUEST
	for feature_id: String in store.entries:
		var entry: Dictionary = store.entries[feature_id]
		var marked: int = entry.get(MARK, Command.NO_REQUEST)
		most = maxi(most, marked)
		for applied_id: Variant in entry.get(APPLIED, []):
			most = maxi(most, ShortId.code(str(applied_id)))
	return most
