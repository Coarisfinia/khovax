class_name ReviveItemFeature
extends Feature
## Revive items (#656): a player who uses one (Command.revive) brings back the fainted monster they
## carry that they picked (#780, LocalInput), wherever they are (CompanionParty.revive, #655), and
## MonsterRevived says so, which spends the item from their profile. On one that isn't carried or
## hasn't fainted nothing happens, so nothing is spent. The items are in the player's profile,
## outside the simulation, so whether they hold one is their own machine's to check (LocalInput).
## It keeps no state of its own.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "revive_items"


func id() -> String:
	return ID


## After the companions, whose party it changes: a revived companion joins its player on the next
## tick.
func requires() -> Array[String]:
	var needed: Array[String] = [CompanionFeature.ID]
	return needed


## Revives the fainted monster each player here, in slot order, uses a revive item on.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		if command != null and command.revive != Command.NO_REVIVE and state.player(slot) != null:
			_revive(state, slot, ShortId.of_code(command.revive))


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
