class_name CompanionPassives
extends RefCounted
## Which passives work now (#616): a monster's passives (#222) work only while it is out, as its
## player's companion here (CompanionFeature): its species' own, and the one a passive node it took
## on its web grants it (#1472, CompanionParty.passive_of), helping whom that passive helps. The
## monsters a
## player carries in reserve give none. What a passive does is read where it acts (e.g. a guard,
## WildAttackFeature).


## The passives that help the player in `slot` now, in `state`: their companion's, while it is out
## here; none while it isn't, whatever they carry in reserve.
static func of_player(state: GameState, companions: CompanionFeature, slot: int) -> Array[String]:
	return _passives(
		state,
		companions,
		companions.player_passives,
		true,
		companions.companion_of(slot),
	)


## The passives that help the companion `companion_id` itself, in `state`: its species' own and its
## web's; none for an entity that's no companion here.
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
	if companions.helps_player.has(granted) and companions.helps_player[granted] == player:
		working.append(granted)
	return working
