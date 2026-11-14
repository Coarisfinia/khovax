extends RefCounted
## Tonic trait flow (#2312, the potion design on #2049, sections 3 and 6): the two traits that
## change when and whom a brew helps. A Slow-release moss draught starts healing 5 s after the
## drink, and a Slow-release berry draught lands its Mend 5 s after the drink; a knockdown
## or a replacement during the wait cancels it. A Shared brew reaches every other player within 3
## tiles of the drinker and nobody farther: a Shared Ward wards each in reach, and a Shared Mend
## mends each hurt one in reach even when the drinker isn't hurt, and is refused when nobody in
## reach is.

## Slow-release's wait in seconds (section 3).
const DELAY_SECONDS: int = 5
## The rules drinking needs: the rest are switched off, so nothing else moves the players or
## changes their HP.
const DRINK_RULES: Array[String] = [
	"host_settings",
	"movement",
	"knockdown",
	"health",
	"tonic_effects",
	"companions",
	"drinking",
]


## Each trait's case on its own, so each one that's wrong is named.
func run(_tree: SceneTree) -> String:
	var wrong: Array[String] = []
	for why: String in [
		_check_slow_regrowth(),
		_check_slow_mend(),
		_check_slow_mend_knocked_down(),
		_check_slow_mend_replaced(),
		_check_shared_ward(),
		_check_shared_mend(),
	]:
		if not why.is_empty():
			wrong.append(why)
	return "; ".join(wrong)


## A Slow-release moss draught (37 thousandths for 20 s) drunk at 1 HP starts 5 s after the drink,
## where a moss draught starts on the next tick: it heals at the end of every second from then for
## 20 s, and no more after.
func _check_slow_regrowth() -> String:
	var state: GameState = _players_at([Vector2i.ZERO])
	var player: Entity = state.player(0)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var _hurt: bool = health.hurt(state, player.id, HealthFeature.PLAYER_HP - 1)
	var profile: Profile = Profile.new()
	profile.materials.assign({ "draught_moss_slow_release": 1 })
	var why: String = _drunk_by(profile, state, 0, "draught_moss_slow_release")
	var each: int = maxi(1, Fixed.scale(HealthFeature.PLAYER_HP, 37))
	var delay: int = DELAY_SECONDS * Simulation.TICKS_PER_SECOND
	var seen: Array[int] = []
	var expected: Array[int] = [1, 1 + each, 1 + 20 * each, 1 + 20 * each]
	for ticks: int in [
		delay + Simulation.TICKS_PER_SECOND - 2,
		1,
		19 * Simulation.TICKS_PER_SECOND,
		Simulation.TICKS_PER_SECOND,
	]:
		_idle_all(state, ticks)
		seen.append(health.hp_of(state, player.id))
	if why.is_empty() and seen != expected:
		why = "a Slow-release moss draught left the player %s HP over 26 s, not %s" % [
			seen,
			expected,
		]
	return why


## A Slow-release berry draught (450 thousandths) drunk at 1 HP mends the player 5 s after the
## drink, not a tick before.
func _check_slow_mend() -> String:
	var state: GameState = _players_at([Vector2i.ZERO])
	var player: Entity = state.player(0)
	var why: String = _drank_slow_berry(state, 0)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var delay: int = DELAY_SECONDS * Simulation.TICKS_PER_SECOND
	_idle_all(state, delay - 1)
	var waiting: int = health.hp_of(state, player.id)
	_idle_all(state, 1)
	var landed: int = health.hp_of(state, player.id)
	var expected: int = 1 + Fixed.scale(HealthFeature.PLAYER_HP, 450)
	if why.is_empty() and (waiting != 1 or landed != expected):
		why = "a Slow-release berry draught left the player %d HP, then %d at 5 s, not 1, %d" % [
			waiting,
			landed,
			expected,
		]
	return why


## A Slow-release berry draught's waiting Mend ends once its player is knocked down: nothing is
## left of it once its 5 s are up.
func _check_slow_mend_knocked_down() -> String:
	var state: GameState = _players_at([Vector2i.ZERO])
	var player: Entity = state.player(0)
	var why: String = _drank_slow_berry(state, 0)
	var effects: TonicEffectsFeature = state.feature(TonicEffectsFeature.ID) as TonicEffectsFeature
	if why.is_empty() and effects.effect_of(player.id) == null:
		why = "a Slow-release berry draught left no Mend waiting"
	var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
	knockdown.knock_down(player.id)
	_idle_all(state, 1)
	if why.is_empty() and effects.effect_of(player.id) != null:
		why = "a knocked-down player's waiting Mend didn't end"
	return why


## A Slow-release berry draught's waiting Mend ends when another drink replaces it: player 1's,
## replaced by player 0's Shared pondweed draught a tick later, never lands, and player 1 has the
## Ward instead.
func _check_slow_mend_replaced() -> String:
	var state: GameState = _players_at([Vector2i.ZERO, Vector2i(1, 0)])
	var other: Entity = state.player(1)
	var why: String = _drank_slow_berry(state, 1)
	var profile: Profile = Profile.new()
	profile.materials.assign({ "draught_pondweed_shared": 1 })
	if why.is_empty():
		why = _drunk_by(profile, state, 0, "draught_pondweed_shared")
	_idle_all(state, DELAY_SECONDS * Simulation.TICKS_PER_SECOND)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var ward: int = TonicEffectReads.strength_of(state, other.id, TonicEffectsFeature.WARD)
	if why.is_empty() and (health.hp_of(state, other.id) != 1 or ward != 100):
		why = "a replaced waiting Mend left player 1 %d HP and a Ward of %d, not 1 and 100" % [
			health.hp_of(state, other.id),
			ward,
		]
	return why


## A Shared pondweed draught (100 thousandths for 30 s) drunk by player 0 wards them and player 1,
## 3 tiles away, and not player 2, 4 tiles away.
func _check_shared_ward() -> String:
	var state: GameState = _players_at([Vector2i.ZERO, Vector2i(3, 0), Vector2i(-4, 0)])
	var profile: Profile = Profile.new()
	profile.materials.assign({ "draught_pondweed_shared": 1 })
	var why: String = _drunk_by(profile, state, 0, "draught_pondweed_shared")
	_idle_all(state, 1)
	var wards: Array[int] = []
	for slot: int in 3:
		var player: Entity = state.player(slot)
		wards.append(TonicEffectReads.strength_of(state, player.id, TonicEffectsFeature.WARD))
	if why.is_empty() and wards != [100, 100, 0]:
		why = "a Shared pondweed draught warded the players by %s, not [100, 100, 0]" % [wards]
	return why


## A Shared berry draught (150 thousandths) drunk by player 0 at full HP is refused while only
## player 2, 4 tiles away, is hurt; once player 1, 3 tiles away, is hurt too, it mends player 1
## and leaves player 2 as they were.
func _check_shared_mend() -> String:
	var state: GameState = _players_at([Vector2i.ZERO, Vector2i(3, 0), Vector2i(-4, 0)])
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var far: Entity = state.player(2)
	var _far_hurt: bool = health.hurt(state, far.id, HealthFeature.PLAYER_HP - 1)
	var profile: Profile = Profile.new()
	profile.materials.assign({ "draught_berry_shared": 1 })
	var why: String = TonicDrinks.refused(
		profile,
		state,
		"draught_berry_shared",
		"a Shared Mend nobody near needs",
	)
	var near: Entity = state.player(1)
	var _near_hurt: bool = health.hurt(state, near.id, HealthFeature.PLAYER_HP - 1)
	if why.is_empty():
		why = _drunk_by(profile, state, 0, "draught_berry_shared")
	var seen: Array[int] = []
	for slot: int in 3:
		seen.append(health.hp_of(state, state.player(slot).id))
	var expected: Array[int] = [
		HealthFeature.PLAYER_HP,
		1 + Fixed.scale(HealthFeature.PLAYER_HP, 150),
		1,
	]
	if why.is_empty() and seen != expected:
		why = "a Shared berry draught left the three players %s HP, not %s" % [seen, expected]
	return why


## Hurts the player in `slot` of `state` down to 1 HP and has them drink a Slow-release berry
## draught; returns why that went wrong, or "".
func _drank_slow_berry(state: GameState, slot: int) -> String:
	var player: Entity = state.player(slot)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var _hurt: bool = health.hurt(state, player.id, HealthFeature.PLAYER_HP - 1)
	var profile: Profile = Profile.new()
	profile.materials.assign({ "draught_berry_slow_release": 1 })
	return _drunk_by(profile, state, slot, "draught_berry_slow_release")


## The basic blueprint's rules on a disc of radius 5, with a player on each of `tiles`, in slot
## order, and only DRINK_RULES on.
func _players_at(tiles: Array[Vector2i]) -> GameState:
	var state: GameState = FlowSteps.rules_on(FlowSteps.BASIC, Region.disc(5), 42)
	for each: Feature in state.features:
		state.set_enabled(each.id(), DRINK_RULES.has(each.id()))
	for slot: int in tiles.size():
		var _player: Entity = state.add_entity(slot, tiles[slot])
	return state


## Drinks one `brew` from `profile` for the player in `slot` of `state` and sends its request in
## their next command, every other player standing; returns why that went wrong, or "".
func _drunk_by(profile: Profile, state: GameState, slot: int, brew: String) -> String:
	var held: int = profile.materials.get(brew, 0)
	var refusal: String = TonicDrinking.drink(profile, state, slot, brew)
	if not refusal.is_empty() or profile.materials.get(brew, 0) != held - 1:
		return "drinking %s was refused or spent nothing: %s" % [brew, refusal]
	var commands: Array[Command] = _standing()
	profile.outbox.entries[0].fill(commands[slot])
	var _dropped: bool = profile.outbox.drop(profile.outbox.entries[0].id)
	Simulation.step(state, commands)
	return ""


## Steps `state` `ticks` times with every player standing.
static func _idle_all(state: GameState, ticks: int) -> void:
	for _tick: int in ticks:
		Simulation.step(state, _standing())


## A standing command for each of the GameState.MAX_PLAYERS slots.
static func _standing() -> Array[Command]:
	var commands: Array[Command] = [Command.new(), Command.new(), Command.new(), Command.new()]
	return commands
