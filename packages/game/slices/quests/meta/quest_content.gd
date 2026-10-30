class_name QuestContent
extends Content
## The quests' content data (#184), which the quests slice owns (#412): one JSONC file per quest
## directly in its data/ (its own kind, so no folder repeats the slice's name, #442), checked
## against quests.schema.json beside them in CI, and here against the species, the factions, the
## dialogs, the loot and the people. Everything else reads the quests through this.

const DIR: String = "res://slices/quests/data/"

## Every species, by id, which the quests' steps were checked against.
var species: Dictionary[String, Species] = {}
## Every quest, by id.
var quests: Dictionary[String, QuestDefinition] = {}
## Every territory a quest hands over (#638), by the code a command hands it over by
## (Territory.code): the instance's name and the faction's id.
var handovers: Dictionary[int, PackedStringArray] = {}
## Every event a quest emits (#575), by the code a command raises it in the world by (#755,
## CommandCodes.of).
var events: Dictionary[int, String] = {}
var _factions: FactionContent
var _dialogs: DialogContent
## The loot tables, chests' included, and the harvest tables.
var _tables: Array[LootContent] = []


## Every quest file in `directory`, read and checked; the species its steps name must be in
## `species_directory`, the faction whose standing it moves (#532), or that it hands its territory
## to (#638), in `faction_directory`, and the dialogs and answers its answered steps and choices
## name (#636) in `dialog_directory`. The item an obtained step asks for (#766) must drop from a
## loot or harvest table.
static func load_quests(
	directory: String = DIR,
	species_directory: String = SpeciesContent.DIR,
	faction_directory: String = FactionContent.DIR,
	dialog_directory: String = DialogContent.DIR,
) -> QuestContent:
	return _checked_against(
		directory,
		SpeciesContent.load_species(species_directory),
		FactionContent.load_factions(faction_directory),
		DialogContent.load_dialogs(dialog_directory),
		[LootContent.load_loot_tables(), LootContent.load_loot_tables(LootContent.HARVEST_DIR)],
	)


## The quests, read once per session (ContentCatalog), checked against the other kinds' cached
## content, so every reader sees the same species, factions, dialogs and loot.
static func cached() -> QuestContent:
	return ContentCatalog.kept(DIR, _from_cache)


static func _from_cache() -> QuestContent:
	return _checked_against(
		DIR,
		SpeciesContent.cached(),
		FactionContent.cached(),
		DialogContent.cached(),
		[LootContent.cached(), LootContent.cached(LootContent.HARVEST_DIR)],
	)


## Every quest file in `directory`, read and checked against `known` species, `factions`,
## `dialogs` and `tables` (the loot tables, chests' included, and the harvest tables); none when
## one of those didn't load.
static func _checked_against(
	directory: String,
	known: SpeciesContent,
	factions: FactionContent,
	dialogs: DialogContent,
	tables: Array[LootContent],
) -> QuestContent:
	var content: QuestContent = QuestContent.new()
	content.species = known.species
	content._factions = factions
	content._dialogs = dialogs
	content._tables = tables
	content.problem = known.problem + factions.problem + dialogs.problem
	for loot: LootContent in tables:
		content.problem += loot.problem
	if content.problem.is_empty():
		content.read(directory)
	return content


func add(file_id: String, text: String) -> String:
	var quest: QuestDefinition = QuestDefinition.parse(file_id, text, species)
	if quest.standing != null and not _factions.factions.has(quest.standing.faction):
		quest.problem = "its standing's faction must be one that exists"
	for aligned: QuestAlignment in quest.alignment:
		if quest.problem.is_empty() and not _factions.factions.has(aligned.faction):
			quest.problem = "its alignment's faction %s must be one that exists" % aligned.faction
	if quest.problem.is_empty():
		quest.problem = _answers_problem(quest, _dialogs)
	if quest.problem.is_empty():
		quest.problem = _items_problem(quest, _tables)
	if quest.problem.is_empty():
		quest.problem = _materials_problem(quest)
		quest.problem = quest.problem if not quest.problem.is_empty() else person_problem(quest)
	if quest.problem.is_empty() and quest.territory != null:
		quest.problem = _code_territory(quest.territory)
	if quest.problem.is_empty():
		quest.problem = _code_events(quest)
	if quest.problem.is_empty():
		quests[quest.id] = quest
	return quest.problem


## Why an answered step or choice of `quest` names a dialog or an answer that no file in `dialogs`
## has, or one that isn't marked as committing (#891): a quest counting it gives it effects. The
## ones that exist get who speaks the dialog and what the answer says, to word them.
static func _answers_problem(quest: QuestDefinition, dialogs: DialogContent) -> String:
	for index: int in quest.steps.size():
		for trigger: QuestStep in quest.steps[index].triggers():
			if trigger.condition != QuestStep.ANSWERED:
				continue
			var asked: QuestAnswer = trigger.answer
			var dialog: Dialog = dialogs.dialogs.get(asked.dialog)
			var answer: DialogAnswer = dialog.answer_of(asked.id) if dialog != null else null
			if answer == null:
				return "step %d: the dialog %s has no answer %s" % [
					index, asked.dialog, asked.id,
				]
			if not answer.commits:
				return "step %d: the answer %s of the dialog %s has effects, so it must commit" % [
					index, asked.id, asked.dialog,
				]
			asked.speaker = dialog.speaker
			asked.text = answer.text
	return ""


## Why an obtained step or choice of `quest` asks for an item (a material or gear) that no table in
## `tables` (the loot tables, chests' included, and the harvest tables) can drop
## (#766), or "": no player could ever finish it. The items are read from the tables themselves, so
## the check never drifts from what drops.
static func _items_problem(quest: QuestDefinition, tables: Array[LootContent]) -> String:
	for index: int in quest.steps.size():
		for trigger: QuestStep in quest.steps[index].triggers():
			var item: String = trigger.awaited
			if trigger.condition == QuestStep.OBTAINED and not _drops(item, tables):
				return "step %d: no loot or harvest table drops the item %s" % [index, item]
	return ""


## Why `quest` gives a material (#1348) that isn't one (MaterialContent), or "".
static func _materials_problem(quest: QuestDefinition) -> String:
	for material: String in quest.materials:
		if not MaterialContent.cached().ids.has(material):
			return "it gives %s, which is no material" % material
	return ""


## Why `quest` starts on talking to a person (#1592) who isn't one (PeopleContent), or "".
static func person_problem(quest: QuestDefinition) -> String:
	var start: QuestStep = quest.starts_on
	if start != null and start.condition == QuestStep.TALKED:
		if not PeopleContent.cached().people.has(start.awaited):
			return "it starts on talking to %s, who is no person" % start.awaited
	return ""


## Whether a table in `tables` holds `item`.
static func _drops(item: String, tables: Array[LootContent]) -> bool:
	for data: LootContent in tables:
		for table: LootTable in data.loot_tables.values():
			if table.items.has(item):
				return true
	return false


## Files `territory` by its code (#638); why it can't be, or "": its faction doesn't exist, or a
## command couldn't tell it from none, or from another territory with the same code.
func _code_territory(territory: QuestTerritory) -> String:
	if not _factions.factions.has(territory.faction):
		return "its territory's faction must be one that exists"
	var handed: PackedStringArray = PackedStringArray([territory.instance, territory.faction])
	var by: int = Territory.code(territory.instance, territory.faction)
	if not CommandCodes.file(handovers, by, handed):
		return "its territory's code is taken: hand over another instance or faction"
	return ""


## Files every event `quest`'s steps and choices emit by its code (#755); why one can't be, or "":
## a command couldn't tell it from none, or from another event with the same code.
func _code_events(quest: QuestDefinition) -> String:
	for step: QuestStep in quest.steps:
		var emitters: Array[QuestStep] = [step]
		emitters.append_array(step.choices)
		for emitter: QuestStep in emitters:
			var event: String = emitter.emits
			if (not event.is_empty()
					and not CommandCodes.file(events, CommandCodes.of(event), event)):
				return "the code of its event %s is taken: name the event otherwise" % event
	return ""
