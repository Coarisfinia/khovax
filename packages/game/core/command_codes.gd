class_name CommandCodes
extends RefCounted
## The whole numbers a command carries for ids (#818): a command holds integers only, so an id
## content names (a dialog's answer, a territory, a piece of gear) reaches the simulation as its
## code, the same on every machine. NONE is no id's: a field holding it carries nothing. A code is a
## hash, so two ids can share one, or one can be NONE; content files every code with `file`, which
## refuses both, so a command never mistakes one id for another or for none. A short id's code
## (ShortId.code) is the one exception: it's the id's own digits, so it can be read back, and it's
## never NONE or shared by construction.

## The code no id has: a command field holding it carries nothing.
const NONE: int = 0


## The code of the id `id`: a whole number from its characters, or NONE for no id ("").
static func of(id: String) -> int:
	return StateHash.name_code(id) if not id.is_empty() else NONE


## Files `value` in `by_code` under `code`, the code of the id it stands for; false, filing nothing,
## when a command couldn't tell it from none (NONE) or from another value already filed there.
static func file(by_code: Dictionary, code: int, value: Variant) -> bool:
	if code == NONE or (by_code.has(code) and by_code[code] != value):
		return false
	by_code[code] = value
	return true
