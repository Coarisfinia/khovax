# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (lists the rule change files, #736)
class_name RulesChanges
extends RefCounted
## The id of the rules (#736, #876), held by every world save and every replay the game records (a
## golden replay holds only its inputs): a digest of the rule changes, one file each in
## core/rules_changes/. A change that makes existing replays play out
## differently adds its file there, `<issue>-<slug>.md` with the issue in its frontmatter and one
## line on what plays differently: CI fails a change that plays the reference replays differently
## from its parent without one (tools/replays/rules_compare.py), and a replay recorded under older
## rules then fails with a clear message, not a mismatch.
## Adding the file is the change of id, so two parallel rule changes never claim the same id, and
## the folder is append-only (tools/checks/rules_changes_check.py): a file is never deleted or
## renamed. Git keeps when each arrived and its pull request
## (`git log --diff-filter=A -- core/rules_changes/`, #758).

const FOLDER: String = "res://core/rules_changes/"
## How many hex characters of the digest the id keeps.
const LENGTH: int = 16

static var _id: String = ""


## The id of the rules: the first LENGTH hex characters of the SHA-256 of the rule change files'
## names, sorted and one per line. Worked out once, then remembered.
static func id() -> String:
	if _id.is_empty():
		var names: Array[String] = []
		for file_name: String in DirAccess.get_files_at(FOLDER):
			if file_name.ends_with(".md"):
				names.append(file_name)
		names.sort()
		_id = "\n".join(PackedStringArray(names)).sha256_text().left(LENGTH)
	return _id
