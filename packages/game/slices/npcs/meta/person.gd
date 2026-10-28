class_name Person
extends RefCounted
## A person (#1005), read from content data (the npcs slice's data/people/, #72, #412): a humanoid
## who never fights (owner's worldbuilding rules), with a player-facing name and a codex entry
## (#959). Region legends place them by id (NpcSpot), and the dialogs they speak name them by it.

## Its schema, which says the fields a person file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/npcs/data/people.schema.json"

var id: String = ""
## The player-facing name.
var name: String = ""
## Their codex entry (#959): a short text about them and where their name comes from.
var codex_entry: String = ""
## What their name means, hand-written (#959), e.g. "Teska, sworn to the guild".
var codex_gloss: String = ""
## What they say when they go ahead to their seal without their player (#1589), shown as a notice
## (GuideNoticeTie); "" for a person who guides nobody, or one who says the plain line.
var went_ahead: String = ""
## Why the person couldn't be read, or "" when it could.
var problem: String = ""


## A person read from a person file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> Person:
	var person: Person = Person.new()
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		person.problem = Content.NOT_AN_OBJECT
		return person
	var data: Dictionary = parsed
	person.id = Content.text_of(data.get("id"))
	person.name = Content.text_of(data.get("name"))
	var codex: Dictionary = data.get("codex") if data.get("codex") is Dictionary else {}
	person.codex_entry = Content.text_of(codex.get("entry"))
	person.codex_gloss = Content.text_of(codex.get("gloss"))
	person.went_ahead = Content.text_of(data.get("went_ahead"))
	person.problem = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	if person.problem.is_empty():
		person.problem = Content.id_problem(person.id, file_id)
	if person.problem.is_empty() and person.name.strip_edges().is_empty():
		person.problem = "it needs a name"
	var entry_blank: bool = person.codex_entry.strip_edges().is_empty()
	if person.problem.is_empty() and (entry_blank or person.codex_gloss.strip_edges().is_empty()):
		person.problem = "it needs a codex entry and gloss (#959)"
	return person
