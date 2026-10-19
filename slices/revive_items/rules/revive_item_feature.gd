class_name ReviveItemFeature
extends Feature
## Revive items (#656): a player who uses one (Command.revive) brings back the first monster they
## carry, in their carried order, that has fainted (CompanionParty.revive, #655), wherever they
## are, and MonsterRevived says so, which spends the item from their profile. With none fainted
## nothing happens, so nothing is spent. The items are in the player's profile, outside the
## simulation, so whether they hold one is their own machine's to check (LocalInput). It keeps no
## state of its own.


func id() -> int:
	return Features.REVIVE_ITEMS


## After the companions, whose party it changes: a revived companion joins its player on the next
## tick.
func requires() -> Array[int]:
	var needed: Array[int] = [Features.COMPANIONS]
	return needed


## Revives one fainted monster for every player here, in slot order, who uses a revive item.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		if command != null and command.revive and state.player(slot) != null:
			_revive(state, slot)


## Brings back the first fainted monster the player in `slot` carries, if any, raising
## MonsterRevived.
static func _revive(state: GameState, slot: int) -> void:
	var short_id: String = revivable(state, slot)
	if not short_id.is_empty():
		CompanionParty.revive(state, slot, short_id)
		var species: String = CompanionParty.species_of(state, slot, short_id)
		state.events.append(MonsterRevived.new(slot, short_id, species))


## The short id of the monster a revive item brings back for the player in `slot`: the first they
## carry, in their carried order, that has fainted, or "" when none has.
static func revivable(state: GameState, slot: int) -> String:
	for short_id: String in CompanionParty.carried(state, slot):
		if CompanionParty.has_fainted(state, slot, short_id):
			return short_id
	return ""
