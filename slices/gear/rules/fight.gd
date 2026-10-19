class_name Fight
extends RefCounted
## Whether a player is in a fight (#690): gear changes only outside one (owner, #223). A player is
## (owner, 1+3 on #690) while a wild monster that isn't hiding (nobody sees it, #202) stands within
## REACH tiles of them or of their companion, close enough to strike or be struck; while any wild
## monster in their instance is enraged (#220); and while their ring is sealing wild monsters in
## (#409). It only reads the state.

## How near a wild monster has to be, in tiles, for a fight.
const REACH: int = 2


## Whether the player in `slot` is in a fight in `state`.
static func involves(state: GameState, slot: int) -> bool:
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	if wild == null:
		return false
	var hiding: HidingFeature = state.feature(Features.HIDING) as HidingFeature
	var tiles: Array[Vector2i] = _tiles_of(state, slot)
	for monster_id: int in wild.monsters:
		var monster: Entity = state.entity(monster_id)
		if monster == null:
			continue
		if wild.rage_of(monster_id) > 0:
			return true
		var hidden: bool = hiding != null and hiding.is_hidden(monster_id)
		if not hidden and _near(monster.tile, tiles):
			return true
	return _sealing(state, slot)


## Whether `tile` is within REACH tiles of any of `tiles`.
static func _near(tile: Vector2i, tiles: Array[Vector2i]) -> bool:
	for other: Vector2i in tiles:
		if Hex.distance(tile, other) <= REACH:
			return true
	return false


## Whether the ring of the player in `slot` is sealing wild monsters in.
static func _sealing(state: GameState, slot: int) -> bool:
	var domination: DominationFeature = state.feature(Features.DOMINATION) as DominationFeature
	var player: Entity = state.player(slot)
	if domination == null or player == null or not domination.seals.has(player.id):
		return false
	return not domination.seals[player.id].monsters.is_empty()


## The tiles of the player in `slot` and of their companion, where they have one here.
static func _tiles_of(state: GameState, slot: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var player: Entity = state.player(slot)
	if player != null:
		tiles.append(player.tile)
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	var companion: Entity = null
	if companions != null:
		companion = state.entity(companions.companion_of(slot))
	if companion != null:
		tiles.append(companion.tile)
	return tiles
