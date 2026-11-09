class_name PeopleContent
extends Content
## The people's content data (#1005), which the npcs slice owns (#412): one JSONC file per person in
## its data/people/, checked against people.schema.json beside it in CI. Everything else reads the
## people through this.

const DIR: String = "res://slices/npcs/data/people/"

## Every person, by id.
var people: Dictionary[String, Person] = {}


## Every person file in `directory`, read and checked.
static func load_people(directory: String = DIR) -> PeopleContent:
	var content: PeopleContent = PeopleContent.new()
	content.read(directory)
	return content


## The people, read once per session (ContentCatalog).
static func cached() -> PeopleContent:
	return ContentCatalog.kept(DIR, load_people)


func add(file_id: String, text: String) -> String:
	var person: Person = Person.parse(file_id, text)
	if person.problem.is_empty():
		people[person.id] = person
	return person.problem
