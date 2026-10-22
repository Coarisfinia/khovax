class_name SightTraitFeature
extends Feature
## Sight traits (#962, decided on #65): a player sees further while they carry a monster whose
## species has a sight trait, by the most steps any of their carried monsters gives (content data,
## the species' `sight`), fainted or not. It widens their sight in the fog (FogFeature.widen) every
## tick, as their party changes, and as they join an instance, so the fog follows at once; the fog's
## view eases it open and closed.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "sight_traits"

## Each species' sight trait, by species id, for the species that have one.
var sights: Dictionary[String, int] = {}


func _init(species_sights: Dictionary[String, int] = {}) -> void:
	sights = species_sights


func id() -> String:
	return ID


## After the fog, whose sight it widens.
func requires() -> Array[String]:
	var needed: Array[String] = [FogFeature.ID]
	return needed


## After the companions where the instance has them, so a party brought this tick counts at once.
func after() -> Array[String]:
	var read: Array[String] = [CompanionFeature.ID]
	return read


func start(state: GameState) -> void:
	_widen(state)


func step(state: GameState, _commands: Array[Command]) -> void:
	_widen(state)


## A player sees as far as their monsters let them from the moment they join.
func entity_added(state: GameState, added: Entity) -> void:
	if added.slot != Entity.NO_SLOT:
		_widen(state)


## The most steps any monster the player in `slot` carries widens their sight by, in `state`.
func sight_of(state: GameState, slot: int) -> int:
	var most: int = 0
	for species_id: String in CompanionParty.carried_species(state, slot):
		var steps: int = sights.get(species_id, 0)
		most = maxi(most, steps)
	return most


## Widens every player's sight by what their monsters give, in slot order.
func _widen(state: GameState) -> void:
	var fog: FogFeature = state.feature(FogFeature.ID) as FogFeature
	for slot: int in GameState.MAX_PLAYERS:
		if state.player(slot) != null:
			fog.widen(state, slot, sight_of(state, slot))
