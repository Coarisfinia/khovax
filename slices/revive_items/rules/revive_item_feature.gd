class_name ReviveItemFeature
extends Feature
## Revive items (#656): a player who uses one brings back the fainted monster they carry that they
## picked (#780, LocalInput), wherever they are (CompanionParty.revive, #655), and MonsterRevived
## says so. Using one is a request from their profile's outbox (#818, OutboxEntry.REVIVE) whose data
## is the monster's short id's code, posted as the item is spent from the profile: the ids it
## applied are kept in its entry in the player's world store (OutboxReceipts), so one sent again
## revives nothing twice. On one that isn't carried or hasn't fainted anymore nothing happens, and
## the request is acknowledged all the same. The items are in the player's profile, outside the
## simulation, so whether they hold one is their own machine's to check (ProfileTie).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "revive_items"


func id() -> String:
	return ID


## After the companions, whose party it changes: a revived companion joins its player on the next
## tick.
func requires() -> Array[String]:
	var needed: Array[String] = [CompanionFeature.ID]
	return needed


## Revives the fainted monster each player here, in slot order, uses a revive item on, unless its
## request was applied before.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		var reviving: bool = command != null and command.request_kind == OutboxEntry.REVIVE
		if not reviving or state.player(slot) == null:
			continue
		if OutboxReceipts.take(state, slot, id(), command):
			_revive(state, slot, ShortId.of_code(command.request_data))


## Brings back the monster `short_id` the player in `slot` carries, if it has fainted, raising
## MonsterRevived.
static func _revive(state: GameState, slot: int, short_id: String) -> void:
	if fainted(state, slot).has(short_id):
		CompanionParty.revive(state, slot, short_id)
		var species: String = CompanionParty.species_of(state, slot, short_id)
		state.events.append(MonsterRevived.new(slot, short_id, species))


## The short ids of the monsters the player in `slot` carries that have fainted, in their carried
## order: the ones a revive item can bring back.
static func fainted(state: GameState, slot: int) -> PackedStringArray:
	var down: PackedStringArray = PackedStringArray()
	for short_id: String in CompanionParty.carried(state, slot):
		if CompanionParty.has_fainted(state, slot, short_id):
			var _added: bool = down.append(short_id)
	return down
