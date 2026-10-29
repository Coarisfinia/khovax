extends RefCounted
## Bestiary flow (#1173): what this machine's player learns about each species, which a species'
## codex page shows. Before they've seen one, its page shows only its name and what the name means,
## and says what's still to learn, with no picture in its place; once seen, it shows its picture,
## the model its monsters wear (#1190). Every wild monster drawn on their screen is seen, in the
## instance they're in, and one not drawn isn't. A wild monster that strikes the player is met: its
## page then shows its types, its abilities by name and where they came across it; one striking the
## trail isn't. A realm's instance in that habitat line is a link, and selecting it turns the page
## to that place's (#1175); the playground, which no realm draws, is plain words. Their own
## domination of one teaches its lore, which the page shows; another player's
## doesn't. What they learned goes into the profile's file with its next save, never asking for one
## itself (so a domination's gain is still saved at once), and reads back as it was. A save whose
## bestiary is malformed is refused, and one from before the bestiary starts with nothing learned.

const PROFILE: String = "user://test_bestiary_profile.json"
## The instance the flows play, which the habitat names.
const HABITAT: String = "Found in: Senwel Sael"

var _driver: GameDriver
var _bus: EventBus
var _keeper: BestiaryKeeper
var _page: CodexPage


func run(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start_held(tree, PROFILE)
	_driver = FlowGame.held_driver(main)
	_bus = main.get_node("EventBus") as EventBus
	_keeper = main.get_node("BestiaryKeeper") as BestiaryKeeper
	_page = main.get_node("Hud/CodexPage") as CodexPage
	# As a fresh profile has it, whatever the session's start already showed.
	_keeper.started()
	var result: String = _check_unseen()
	if result.is_empty():
		result = _check_seen()
	if result.is_empty():
		result = _check_met()
	if result.is_empty():
		result = _check_habitat_link()
	if result.is_empty():
		result = _check_known()
	if result.is_empty():
		result = _check_saved(FlowGame.holder(main))
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(PROFILE)
	if result.is_empty():
		result = _check_refused()
	return result


## A species the player hasn't seen shows its name, what the name means and what's still to learn.
func _check_unseen() -> String:
	var unseen: String = _unseen_species()
	if unseen.is_empty():
		return "the player had seen every species before the first tick"
	var species: Species = SpeciesContent.cached().species[unseen]
	var expected: Array[String] = [
		BestiaryEntry.not_seen_text(),
		BestiaryEntry.not_met_text(),
		BestiaryEntry.not_known_text(),
	]
	var problem: String = _page_problem(species, expected)
	return "an unseen species' page: " + problem if not problem.is_empty() else ""


## After a few ticks every wild monster on screen is seen in Senwel Sael; a species none of
## whose monsters is on screen isn't.
func _check_seen() -> String:
	_tick(3)
	var state: GameState = _driver.state
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var on_screen: Array[String] = []
	for monster_id: int in wild.monsters:
		if WildMonsterView.is_shown(state, monster_id):
			on_screen.append(wild.species_of(monster_id))
	if on_screen.is_empty():
		return "no wild monster was on screen to be seen"
	var known: Bestiary = _keeper.known()
	for id: String in SpeciesContent.cached().species:
		var seen: bool = on_screen.has(id)
		if known.level_of(id) != (Bestiary.SEEN if seen else 0):
			return "%s was learned at level %d, on screen: %s" % [id, known.level_of(id), seen]
		if seen and known.habitat_of(id) != [FlowSteps.BASIC]:
			return "%s was seen in %s" % [id, known.habitat_of(id)]
	var species: Species = SpeciesContent.cached().species[on_screen[0]]
	var expected: Array[String] = [BestiaryEntry.not_met_text(), BestiaryEntry.not_known_text()]
	var problem: String = _page_problem(species, expected)
	return "a seen species' page: " + problem if not problem.is_empty() else ""


## A wild monster striking the trail meets nobody; striking the player meets its species, whose
## page then shows its types, abilities and habitat.
func _check_met() -> String:
	var monster_id: int = _shown_monster()
	var species: Species = _species_of(monster_id)
	_emit(WildMonsterStruck.new(monster_id, 0, Vector2i.ZERO, 1))
	if _keeper.known().level_of(species.id) != Bestiary.SEEN:
		return "a strike on the trail met %s" % species.id
	var player: Entity = _driver.state.player(_driver.input.slot)
	_emit(WildMonsterStruck.new(monster_id, player.id, player.tile, 1))
	if _keeper.known().level_of(species.id) != Bestiary.MET:
		return "a strike on the player didn't meet %s" % species.id
	var abilities: Dictionary[String, Ability] = AbilityContent.cached().abilities
	var expected: Array[String] = [
		BestiaryEntry.types_heading() + " " + ", ".join(species.types),
		BestiaryEntry.special_text(TextTags.shown(abilities[species.special].name)),
		BestiaryEntry.player_passive_text(TextTags.shown(abilities[species.player_passive].name)),
		BestiaryEntry.self_passive_text(TextTags.shown(abilities[species.self_passive].name)),
		HABITAT,
		BestiaryEntry.not_known_text(),
	]
	var problem: String = _page_problem(species, expected)
	return "a met species' page: " + problem if not problem.is_empty() else ""


## A species met in a realm's instance too names it as a link in its habitat line, after the
## playground in plain words; selecting the link turns the page to that place's.
func _check_habitat_link() -> String:
	var species: Species = _species_of(_shown_monster())
	var place: String = Realms.start()
	_keeper.known().learn(species.id, Bestiary.MET, place)
	if not _page.open(TextTags.MONSTER, species.id):
		return "a met species' page didn't open"
	var line: NameLinks = _page.beast.habitat_line
	var link: String = TextTags.PLACE + NameLinks.META_SEPARATOR + place
	var read: String = HABITAT + ", " + Realms.name_of(place)
	if (line == null
			or line.links.size() != 1
			or line.links[0] != link
			or line.get_parsed_text() != read):
		var links: Array[String] = line.links if line != null else []
		_page.close()
		return "the habitat line linked %s, not %s" % [links, link]
	line.select(link)
	var turned: bool = (_page.is_open()
			and _page.heading.text == CodexPage.heading_of(TextTags.PLACE)
			and _page.title.text == Realms.name_of(place))
	_page.close()
	return "" if turned else "selecting %s showed %s" % [place, _page.title.text]


## Another player's domination teaches this player nothing; their own teaches its lore.
func _check_known() -> String:
	var species: Species = _species_of(_shown_monster())
	var slot: int = _driver.input.slot
	_emit(WildMonsterDominated.new(90, 9, slot + 1, Vector2i.ZERO, species.id))
	if _keeper.known().level_of(species.id) != Bestiary.MET:
		return "another player's domination taught %s's lore" % species.id
	_emit(WildMonsterDominated.new(91, 1, slot, Vector2i.ZERO, species.id))
	if _keeper.known().level_of(species.id) != Bestiary.KNOWN:
		return "the player's domination didn't teach %s's lore" % species.id
	if not _page.open(
		TextTags.MONSTER,
		species.id,
	) or _page.beast.shown.back() != species.codex_entry():
		return "a known species' page showed %s" % [_page.beast.shown]
	_page.close()
	return ""


## What the player learned is in the profile's file once it's flushed, read back as it was.
func _check_saved(holder: ProfileHolder) -> String:
	holder.flush()
	var quests: QuestKeeper = QuestKeeper.new()
	var loaded: BestiaryKeeper = BestiaryKeeper.new()
	var problem: String = ProfileStore.load_from(PROFILE, [quests, loaded]).problem
	var kept: Bestiary = _keeper.known()
	var same: bool = loaded.bestiary.levels == kept.levels
	same = same and loaded.bestiary.habitats == kept.habitats
	quests.free()
	loaded.free()
	if not problem.is_empty() or not same:
		return "the bestiary didn't read back as saved: " + problem
	return ""


## A malformed bestiary in a save is refused; a save from before it has nothing learned.
func _check_refused() -> String:
	var cases: Dictionary[String, String] = {
		"[]": "lacks",
		"{\"Ombulumo\": {\"level\": 1, \"habitat\": []}}": "malformed",
		"{\"ombulumo\": {\"level\": 4, \"habitat\": []}}": "malformed",
		"{\"ombulumo\": {\"level\": 1.5, \"habitat\": []}}": "malformed",
		"{\"ombulumo\": {\"level\": 1}}": "malformed",
		"{\"ombulumo\": {\"level\": 1, \"habitat\": [], \"x\": 1}}": "malformed",
		"{\"ombulumo\": {\"level\": 1, \"habitat\": [\"a\", \"a\"]}}": "habitat",
		"{\"ombulumo\": {\"level\": 1, \"habitat\": [7]}}": "habitat",
	}
	for stored: String in cases:
		var refused: String = _read_bestiary(stored)
		if not refused.contains(cases[stored]):
			return "the bestiary %s wasn't refused: %s" % [stored, refused]
	var keeper: BestiaryKeeper = BestiaryKeeper.new()
	keeper.bestiary.learn("ombulumo", Bestiary.KNOWN, "")
	var text: String = ProfileSave.to_text(Profile.new(), [keeper])
	var old: Dictionary = JSON.parse_string(text)
	# Written before the bestiary's format change (#801).
	var changes: Array = old[FormatChanges.KEY]
	changes.erase(BestiarySave.SINCE)
	var _dropped: bool = old.erase(BestiarySave.KEY)
	var problem: String = ProfileSave.parse(JSON.stringify(old), [keeper]).problem
	var learned: int = keeper.bestiary.levels.size()
	keeper.free()
	if not problem.is_empty() or learned != 0:
		return "a save from before the bestiary read as %d learned: %s" % [learned, problem]
	return ""


## Why the bestiary saved as `stored` can't be read, or "".
static func _read_bestiary(stored: String) -> String:
	return BestiarySave.read(Bestiary.new(), { BestiarySave.KEY: JSON.parse_string(stored) })


## Why `species`' page isn't its bestiary entry showing `expected`, or "".
func _page_problem(species: Species, expected: Array[String]) -> String:
	if not _page.open(TextTags.MONSTER, species.id):
		return "it didn't open"
	var shown: Array[String] = _page.beast.shown.duplicate()
	var gloss: String = _page.gloss.get_parsed_text()
	var picture: SpeciesPicture = _page.beast.picture
	_page.close()
	var seen: bool = expected.front() != BestiaryEntry.not_seen_text()
	if (picture != null) != seen:
		return "its picture was %s, seen: %s" % ["shown" if picture != null else "missing", seen]
	if seen and picture.model.scene_file_path != species.model:
		return "its picture showed %s, not %s" % [picture.model.scene_file_path, species.model]
	if (_page.heading.text != CodexPage.heading_of(TextTags.MONSTER)
			or _page.title.text != species.name
			or gloss != "%s: %s" % [species.name, species.codex_gloss()]):
		return "it showed %s, %s, %s" % [_page.heading.text, _page.title.text, gloss]
	return "" if shown == expected else "it showed %s" % [shown]


## A species the player hasn't learned anything about, or "".
func _unseen_species() -> String:
	for id: String in SpeciesContent.cached().species:
		if _keeper.known().level_of(id) == 0:
			return id
	return ""


## The first wild monster on screen.
func _shown_monster() -> int:
	var state: GameState = _driver.state
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for monster_id: int in wild.monsters:
		if WildMonsterView.is_shown(state, monster_id):
			return monster_id
	return 0


func _species_of(monster_id: int) -> Species:
	var state: GameState = _driver.state
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	return SpeciesContent.cached().species[wild.species_of(monster_id)]


## Steps the world `ticks` ticks, its events handed out.
func _tick(ticks: int) -> void:
	for _step: int in ticks:
		_driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	_bus.flush()


## Hands `event` to the bus as one the instance the player is in raised, then flushes it.
func _emit(event: RefCounted) -> void:
	_driver.state.events.append(event)
	var events: Array[RefCounted] = [event]
	_driver.ticked.emit(_driver.state.tick, events)
	_bus.flush()
