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
## monster saved before short ids existed (its profile id), or a carried one an old replay names
## (its place). The same number always gives the same one.
static func stand_in(number: int) -> String:
	return drawn(Rng.new(number, STAND_IN_STREAM))


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
