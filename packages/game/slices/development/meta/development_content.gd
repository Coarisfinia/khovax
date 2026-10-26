class_name DevelopmentContent
extends Content
## The development webs' content data (#677), which the development slice owns (#412): one JSONC
## file per species directly in its data/ (its own kind, #442), named after the species, checked
## against its schema there in CI. Everything else reads them through this.

const DIR: String = "res://slices/development/data/"

## Every web, by its species' id.
var webs: Dictionary[String, DevelopmentWeb] = {}


## Every web file in `directory`, read and checked.
static func load_webs(directory: String = DIR) -> DevelopmentContent:
	var content: DevelopmentContent = DevelopmentContent.new()
	content.read(directory)
	return content


## The webs, read once per session (ContentCatalog).
static func cached() -> DevelopmentContent:
	return ContentCatalog.kept(DIR, load_webs)


func add(file_id: String, text: String) -> String:
	var web: DevelopmentWeb = DevelopmentWeb.parse(file_id, text)
	if web.problem.is_empty():
		webs[web.species] = web
	return web.problem
