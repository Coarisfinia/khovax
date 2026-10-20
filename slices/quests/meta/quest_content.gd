class_name QuestContent
extends Content
## The quests' content data (#184), which the quests slice owns (#412): one JSONC file per quest
## directly in its data/ (its own kind, so no folder repeats the slice's name, #442), checked
## against quests.schema.json beside them in CI, and here against the species, the factions, the
## dialogs and the loot. Everything else reads the quests through this.

const DIR: String = "res://slices/quests/data/"

## Every species, by id, which the quests' steps were checked against.
var species: Dictionary[String, Species] = {}
## Every quest, by id.
var quests: Dictionary[String, QuestDefinition] = {}
## Every territory a quest hands over (#638), by the code a command hands it over by
## (Territory.code): the instance's name and the faction's id.
var handovers: Dictionary[int, PackedStringArray] = {}
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
	var known: SpeciesContent = SpeciesContent.load_species(species_directory)
	var content: QuestContent = QuestContent.new()
	content.species = known.species
	content._factions = FactionContent.load_factions(faction_directory)
	content._dialogs = DialogContent.load_dialogs(dialog_directory)
	content._tables = [
		LootContent.load_loot_tables(),
		LootContent.load_loot_tables(LootContent.HARVEST_DIR),
	]
	content.problem = known.problem + content._factions.problem + content._dialogs.problem
	for tables: LootContent in content._tables:
		content.problem += tables.problem
	if content.problem.is_empty():
		content.read(directory)
	return content


func add(file_id: String, text: String) -> String:
	var quest: QuestDefinition = QuestDefinition.parse(file_id, text, species)
	if quest.standing != null and not _factions.factions.has(quest.standing.faction):
		quest.problem = "its standing's faction must be one that exists"
	if quest.problem.is_empty():
		quest.problem = _answers_problem(quest, _dialogs)
	if quest.problem.is_empty():
		quest.problem = _items_problem(quest, _tables)
	if quest.problem.is_empty() and quest.territory != null:
		quest.problem = _code_territory(quest.territory)
	if quest.problem.is_empty():
		quests[quest.id] = quest
	return quest.problem


## Why an answered step or choice of `quest` names a dialog or an answer that no file in `dialogs`
## has, or "". The ones that exist get who speaks the dialog and what the answer says, to word them.
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
			if trigger.condition == QuestStep.OBTAINED and not _drops(trigger.item, tables):
				return "step %d: no loot or harvest table drops the item %s" % [index, trigger.item]
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
