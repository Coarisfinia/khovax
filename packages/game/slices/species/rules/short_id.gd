class_name ShortId
extends RefCounted
## A monster's short id (#700): LENGTH characters every monster gets when its instance is
## generated, drawn from the instance's seeded stream (never a system uuid), so co-op machines and
## replays give every monster the same one. A dominated monster keeps it in the profile, so two
## monsters of one species stay two. The alphabet leaves out the characters that read like others:
## i, j, l and 1, o and 0, and the dash.

const LENGTH: int = 7
const ALPHABET: String = "abcdefghkmnpqrstuvwxyz23456789"
## The stream stand-in ids are drawn from, seeded with the number they stand in for.
const STAND_IN_STREAM: int = 700


## A new short id, drawn from `rng`.
static func drawn(rng: Rng) -> String:
	var id: String = ""
	for _i: int in LENGTH:
		id += ALPHABET[rng.below(ALPHABET.length())]
	return id


## The short id standing in for the monster numbered `number` where none was drawn: a dominated
## monster saved before short ids existed (its old profile number), one a gain brought without a
## short id or with one the profile already holds (#754), or a carried one an old replay names (its
## place). The same number always gives the same one.
static func stand_in(number: int) -> String:
	return drawn(Rng.new(number, STAND_IN_STREAM))


## The short id `short_id` as a whole number from 1 (#771), for a command, which holds whole
## numbers only: its characters' places in the alphabet as the digits of a number in its base, plus
## one, so it's never 0. `of_code` turns it back.
static func code(short_id: String) -> int:
	var number: int = 0
	for i: int in short_id.length():
		number = number * ALPHABET.length() + ALPHABET.find(short_id[i])
	return number + 1


## The short id whose `code` is `number`, or "" when no short id has it.
static func of_code(number: int) -> String:
	var rest: int = number - 1
	var id: String = ""
	for _i: int in LENGTH:
		if rest < 0:
			return ""
		var place: int = Fixed.div_floor(rest, ALPHABET.length())
		id = ALPHABET[rest - place * ALPHABET.length()] + id
		rest = place
	return id if rest == 0 else ""


## Whether `value` is a short id: text of LENGTH characters of the alphabet.
static func is_valid(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = value
	if text.length() != LENGTH:
		return false
	for i: int in text.length():
		if not ALPHABET.contains(text[i]):
			return false
	return true
