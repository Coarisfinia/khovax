extends RefCounted
## Escort flow (#1588, #1553): a guide, a person whose seal the region places too, follows the
## player who talked to them, walking after them through the corridor while the player walks
## through them, and opens their seal once led near it: its boulders turn to ground and the guide
## raises `<their id>_opened`, so the player walks on through. A world saved mid-escort comes back
## the same. A player who leaves through the exit first leaves the guide to go ahead: alone, the
## guide is at the seal and opens it in that same tick; with another player still there, they walk
## there and open it. Either way the rules raise that the guide went ahead for the player who left.
## The player who left is told (#1589): a short notice at the top of their screen shows the guide's
## name and the guide's own line from their content, then eases out on its own; a guide went ahead
## for another player tells this one nothing, and a guide with no line says the plain one. It sits
## below the menu's open button while that shows.
## A seal on a tile anyone walks, one whose person the region piece doesn't place, or one its guide
## can't walk to, is refused.

const SEED: int = 5
const GUIDE: String = "teska_na_amvrel"
## Another person, who stands in the corridor in a refused layout.
const BYSTANDER: String = "someone_else"
## A corridor running east: the exit west of player 1's start, the guide east of it, player 2 (when
## there's one) further on, and the guide's seal, a boulder, with ground behind it.
const CORRIDOR: String = "🚪🔴🧙🟫🔵🟫🟫🟫🪨🟫🟫"
const LEGEND: String = """- `🔵`: where player 2 starts
- `🚪`: exit to the west
- `🧙`: a person to talk to, teska_na_amvrel
- `🪨`: boulder; sealed until teska_na_amvrel opens it
"""
const EAST: int = 0
const WEST: int = 3
## Each tile of the corridor, by its place from the west.
const EXIT_AT: int = 0
const START_AT: int = 1
const GUIDE_AT: int = 2
const SEAL_AT: int = 8
const PROFILE: String = "user://test_escort_profile.json"


func run(tree: SceneTree) -> String:
	var result: String = _lead_to_seal()
	if result.is_empty():
		result = _go_ahead_alone()
	if result.is_empty():
		result = _go_ahead_seen()
	if result.is_empty():
		result = await _told(tree)
	if result.is_empty():
		result = _refuse_bad_seals()
	return result


## The game shows this machine's player a guide who went ahead for them as a notice with the guide's
## name and line, which leaves by itself; one who went ahead for another player shows nothing.
static func _told(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start_held(tree, PROFILE)
	var driver: GameDriver = FlowGame.held_driver(main)
	var notice: NoticeScreen = main.get_node("Hud/NoticeScreen") as NoticeScreen
	var result: String = _notice_follows(driver, notice)
	if result.is_empty():
		result = _clear_of_menu(main.get_node("Hud/GameMenu") as GameMenu, notice)
	if result.is_empty():
		var shown_for: float = NoticeScreen.SHOW_SECONDS + 2.0 * NoticeScreen.FADE_SECONDS
		await tree.create_timer(shown_for + 0.5).timeout
		if notice.is_showing():
			result = "the guide's notice didn't ease out on its own"
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(PROFILE)
	return result


## While the menu's open button shows (on touch screens, or while a knot waits), the notice doesn't
## overlap it or its badge, wherever the screen's shape puts it, and goes back to the top once it's
## gone.
static func _clear_of_menu(menu: GameMenu, notice: NoticeScreen) -> String:
	var button: Button = menu.open_button()
	var shown: bool = button.visible
	var screen: Vector2 = notice.get_viewport_rect().size
	button.visible = true
	menu.lay_out(screen)
	notice.lay_out(screen)
	var covered: Rect2 = GameMenu.with_badge(button)
	covered.position += button.position
	var clear: bool = not notice.card_rect().intersects(covered)
	button.visible = false
	notice.lay_out(screen)
	var back: bool = notice.card_rect().position.y == NoticeScreen.MARGIN
	button.visible = shown
	if not clear or not back:
		return "the notice didn't keep clear of the menu's open button: %s" % notice.card_rect()
	return ""


static func _notice_follows(driver: GameDriver, notice: NoticeScreen) -> String:
	var slot: int = driver.input.slot
	driver.announce(1, [GuideWentAhead.new(GUIDE, 1, slot + 1)])
	if notice.is_showing():
		return "a guide who went ahead for another player showed this one a notice"
	driver.announce(2, [GuideWentAhead.new(GUIDE, 1, slot)])
	var person: Person = PeopleContent.cached().people[GUIDE]
	if not notice.is_showing() or notice.shown_title() != person.name:
		return "the guide who went ahead showed no notice with their name: " + notice.shown_title()
	if person.went_ahead.is_empty() or notice.shown_text() != person.went_ahead:
		return "the notice didn't show the guide's own line: %s" % notice.shown_text()
	if GuideNoticeTie.line_of("nobody_at_all") != GuideNoticeTie.PLAIN_LINE:
		return "a guide with no line of their own didn't say the plain one"
	return ""


## Walking into the guide talks to them, and they follow; the player walks through them to two
## tiles from the seal, the guide walks after and opens it, and the player walks on through. A save
## made while the guide follows loads back the same.
static func _lead_to_seal() -> String:
	var state: GameState = _corridor(1)
	var events: Array[RefCounted] = FlowSteps.step(state, EAST)
	if _escort(state).escorts != { _guide(state): 0 } or state.player(0).tile != _at(START_AT):
		return "talking to the guide didn't make them follow: %s" % [_escort(state).escorts]
	events.append_array(FlowSteps.step(state, EAST))
	events.append_array(FlowSteps.step(state, EAST))
	# The escort goes on from a save made while the guide follows.
	state = _reloaded(state)
	if state == null:
		return "a world saved mid-escort didn't load back the same"
	for _tile: int in SEAL_AT - 2 - _place_of(state.player(0).tile):
		events.append_array(FlowSteps.step(state, EAST))
	for _tick: int in MovementFeature.MOVE_TICKS * 6:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		events.append_array(state.events)
	if state.region.terrain[_at(SEAL_AT)] != Region.GROUND or _opened(events) != 1:
		return "the guide led to their seal didn't open it once: %d" % _opened(events)
	if _went_ahead(events) != 0 or state.entity(_guide(state)).tile != _at(SEAL_AT - 1):
		return "the guide went ahead, or stands on %s" % state.entity(_guide(state)).tile
	for _tile: int in 3:
		events.append_array(FlowSteps.step(state, EAST))
	if state.player(0).tile != _at(SEAL_AT + 1):
		return "the player didn't walk through the open seal: %s" % state.player(0).tile
	return ""


## The world saved from `state` with the guide following, loaded back: null unless its hash is
## the same.
static func _reloaded(state: GameState) -> GameState:
	var loaded: GameState = FlowSteps.rules_on(FlowSteps.BASIC, _ground(), SEED)
	var data: DataReader = DataReader.new(state.to_data())
	if loaded.load_changed_tiles(data):
		loaded.load_data(data)
	# The world's time and its players' stores aren't the instance's to save: the World hands them
	# to a loaded one (#1215, #724).
	loaded.world_tick = state.world_tick
	loaded.stores = state.stores
	return loaded if not data.failed() and loaded.state_hash() == state.state_hash() else null


## Alone, the player who talked to the guide walks out through the exit: in that tick the rules
## raise that the guide went ahead for them, and the guide is beside the seal with it open.
static func _go_ahead_alone() -> String:
	var state: GameState = _corridor(1)
	var _talked: Array[RefCounted] = FlowSteps.step(state, EAST)
	var _out: Array[RefCounted] = FlowSteps.step(state, WEST)
	Simulation.step(state, FlowSteps.command(WEST))
	if not state.events.any(func(event: RefCounted) -> bool: return event is ExitTaken):
		return "the player didn't walk out through the exit"
	if _went_ahead(state.events) != 1 or _opened(state.events) != 1:
		return "leaving alone didn't send the guide ahead to open the seal at once"
	if state.entity(_guide(state)).tile != _at(SEAL_AT - 1):
		return "the guide gone ahead stands on %s" % state.entity(_guide(state)).tile
	return ""


## With player 2 still in the corridor, player 1 talks to the guide and walks out: the guide goes
## ahead walking, step by step, and opens the seal once there.
static func _go_ahead_seen() -> String:
	var state: GameState = _corridor(2)
	var _talked: Array[RefCounted] = FlowSteps.step(state, EAST, 2)
	var _out: Array[RefCounted] = FlowSteps.step(state, WEST, 2)
	Simulation.step(state, FlowSteps.commands([WEST, Command.NO_MOVE]))
	if _went_ahead(state.events) != 1 or _opened(state.events) != 0:
		return "leaving with player 2 still there didn't send the guide ahead on foot"
	var events: Array[RefCounted] = state.events.duplicate()
	for _tick: int in MovementFeature.MOVE_TICKS * (SEAL_AT + 2):
		Simulation.step(state, FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
		events.append_array(state.events)
	var moved: int = 0
	for event: RefCounted in events:
		if event is EntityMoved and (event as EntityMoved).entity_id == _guide(state):
			moved += 1
	if moved != SEAL_AT - 1 - GUIDE_AT or _opened(events) != 1:
		return "the guide gone ahead took %d steps and opened %d times" % [moved, _opened(events)]
	return ""


## A seal on ground, one whose person the corridor doesn't place, one walled in by rock, one
## another person stands in the way to, with nowhere for the guide to reach, and one whose guide
## stands in the corridor twice are refused.
static func _refuse_bad_seals() -> String:
	var on_ground: String = LEGEND.replace("boulder; sealed", "ground; sealed")
	if FlowSteps.region(CORRIDOR, on_ground).problem.is_empty():
		return "a seal on ground was read"
	var nobody: String = LEGEND.replace("until teska_na_amvrel", "until nobody_here")
	if FlowSteps.region(CORRIDOR, nobody).problem.is_empty():
		return "a seal of a person the corridor doesn't place was read"
	if FlowSteps.region(CORRIDOR.replace("🟫🪨🟫", "⬛🪨⬛"), LEGEND).problem.is_empty():
		return "a seal walled in by rock was read"
	var blocked: String = LEGEND + "- `🧍`: a person to talk to, %s\n" % BYSTANDER
	if FlowSteps.region(CORRIDOR.replace("🔵", "🧍"), blocked).problem.is_empty():
		return "a seal another person stands in the way to was read"
	var twice: String = LEGEND + "- `🧍`: a person to talk to, %s\n" % GUIDE
	if FlowSteps.region(CORRIDOR.replace("🔵", "🧍"), twice).problem.is_empty():
		return "a seal whose guide stands in the corridor twice was read"
	return ""


## The corridor with the playground's rules, its exit leading to the glade, and `players` players
## on their starts.
static func _corridor(players: int) -> GameState:
	var state: GameState = FlowSteps.rules_on(FlowSteps.BASIC, _ground(), SEED)
	for slot: int in players:
		var _player: Entity = state.add_entity(slot, state.region.starts[slot])
	return state


## The corridor's region, its exit leading to the glade.
static func _ground() -> Region:
	var ground: Region = FlowSteps.region(CORRIDOR, LEGEND)
	ground.exit_blueprints[0] = FlowSteps.GLADE
	return ground


## The corridor's tile `place` tiles east of its exit.
static func _at(place: int) -> Vector2i:
	return _ground_exit() + Vector2i(place - EXIT_AT, 0)


## How many tiles east of the exit `tile` is.
static func _place_of(tile: Vector2i) -> int:
	return tile.x - _ground_exit().x + EXIT_AT


## The corridor's exit tile.
static func _ground_exit() -> Vector2i:
	var exit: Vector3i = FlowSteps.region(CORRIDOR, LEGEND).exits[0]
	return Vector2i(exit.x, exit.y)


static func _escort(state: GameState) -> EscortFeature:
	return state.feature(EscortFeature.ID) as EscortFeature


## The guide's entity id.
static func _guide(state: GameState) -> int:
	return (state.feature(NpcFeature.ID) as NpcFeature).npcs[0]


## How often `events` say the guide opened their seal.
static func _opened(events: Array[RefCounted]) -> int:
	var count: int = 0
	for event: RefCounted in events:
		if event is EventEmitted and (event as EventEmitted).event_name == GUIDE + "_opened":
			count += 1
	return count


## How often `events` say the guide went ahead for player 1.
static func _went_ahead(events: Array[RefCounted]) -> int:
	var count: int = 0
	for event: RefCounted in events:
		var ahead: GuideWentAhead = event as GuideWentAhead
		if ahead != null and ahead.npc == GUIDE and ahead.slot == 0:
			count += 1
	return count
