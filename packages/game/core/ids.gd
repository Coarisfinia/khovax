class_name Ids
extends RefCounted
## What an id looks like (#944), the one check for every id: a content file's, and every id a
## region's legend or a quest names (a place, a person, a dialog, an event, a species). Pure, so the
## rules and the lasting data both ask it.


## Whether `text` is an id: a lowercase letter, then lowercase letters, digits and underscores.
static func is_id(text: String) -> bool:
	# \A and \z, since $ would also match before a last newline.
	return RegEx.create_from_string("\\A[a-z][a-z0-9_]*\\z").search(text) != null
