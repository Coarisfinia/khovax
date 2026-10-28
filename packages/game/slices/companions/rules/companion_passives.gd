class_name CompanionPassives
extends RefCounted
## Which passives work now (#616): a monster's passives (#222) work only while it is out, as its
## player's companion here (CompanionFeature): its species' own, and the one a passive node it took
## on its web grants it (#1472, CompanionParty.passive_of), helping whom that passive helps. The
## monsters a player carries in reserve give none, unless gear in their ward slot keeps the passives
## on (#617, GearItem.keeps_passives): then every monster they carry that hasn't fainted helps them,
## out or not. The gear is in their profile, so whether it's there comes in as a request
## (OutboxEntry.PASSIVES_KEPT), which CompanionFeature takes and `keep` notes in the companions'
## entry of the player's world store, so it lasts between sessions and goes with them from instance
## to instance. What a passive does is read where it acts (e.g. a guard, WildAttackFeature).

## The key in the companions' store entry while the player's passives are kept on: 1, or none.
const KEPT: String = "kept"


## The passives that help the player in `slot` now, in `state`: their companion's, while it is out
## here; none while it isn't, whatever they carry in reserve. With their passives kept on, every
## carried monster's that hasn't fainted, in carried order.
static func of_player(state: GameState, companions: CompanionFeature, slot: int) -> Array[String]:
	if not kept(state.stored(slot, CompanionFeature.ID)):
		return _passives(
			state,
			companions,
			companions.player_passives,
			true,
			companions.companion_of(slot),
		)
	var working: Array[String] = []
	for short_id: String in CompanionParty.carried(state, slot):
		if CompanionParty.has_fainted(state, slot, short_id):
			continue
		var species: String = CompanionParty.species_of(state, slot, short_id)
		var passive: String = companions.player_passives.get(species, "")
		if not passive.is_empty():
			working.append(passive)
		var granted: String = CompanionParty.passive_of(state, slot, short_id)
		if _helps(companions, granted, true):
			working.append(granted)
	return working


## The passives that help the companion `companion_id` itself, in `state`: its species' own and its
## web's; none for an entity that's no companion here. A monster in reserve isn't here to be
## helped, kept on or not.
static func of_companion(
	state: GameState,
	companions: CompanionFeature,
	companion_id: int,
) -> Array[String]:
	return _passives(
		state,
		companions,
		companions.self_passives,
		false,
		companion_id,
	)


## Whether the companions' store entry `entry` of a player keeps their passives on.
static func kept(entry: Dictionary) -> bool:
	return entry.get(KEPT, 0) == 1


## Keeps the passives of the player in `slot` on, or stops, as their request says (`data`, 1 or
## 0), inside a tick.
static func keep(state: GameState, slot: int, data: int) -> void:
	var entry: Dictionary = state.store(slot, CompanionFeature.ID)
	if data == 1:
		entry[KEPT] = 1
	else:
		var _stopped: bool = entry.erase(KEPT)


## The passive `by_species` names for the species of the companion `companion_id`, if any, and the
## one its web grants it, if that one helps the player (`player`) or the monster itself.
static func _passives(
	state: GameState,
	companions: CompanionFeature,
	by_species: Dictionary[String, String],
	player: bool,
	companion_id: int,
) -> Array[String]:
	var working: Array[String] = []
	var passive: String = by_species.get(companions.species_of(companion_id), "")
	if not passive.is_empty():
		working.append(passive)
	if not companions.owners.has(companion_id):
		return working
	var slot: int = companions.owners[companion_id]
	var granted: String = CompanionParty.passive_of(
		state,
		slot,
		companions.short_id_of(companion_id),
	)
	if _helps(companions, granted, player):
		working.append(granted)
	return working


## Whether the web passive `granted` helps the player (`player`) or, if not, the monster itself.
static func _helps(companions: CompanionFeature, granted: String, player: bool) -> bool:
	return companions.helps_player.has(granted) and companions.helps_player[granted] == player
