class_name StateHash
extends RefCounted
## The fingerprints' arithmetic, the same on every platform (#828): 32-bit FNV-1a, which
## GameState.state_hash and World.state_hash mix their values with, and the name codes that turn
## an id into a number for them.

## Where every fingerprint starts: FNV-1a's 32-bit offset basis.
const OFFSET: int = 2_166_136_261
const _PRIME: int = 16_777_619
const _LOW_BITS: int = 0xffff_ffff


## One step of 32-bit FNV-1a: `word`'s low 32 bits mixed into `current`.
static func mix(current: int, word: int) -> int:
	return ((current ^ (word & _LOW_BITS)) * _PRIME) & _LOW_BITS


## A fingerprint of `values` in order, each mixed in as both of its 32-bit halves, low first.
static func of_values(values: Array[int]) -> int:
	var result: int = OFFSET
	for value: int in values:
		result = mix(mix(result, value), value >> 32)
	return result


## A 32-bit number for a name or id: its characters, mixed in.
static func name_code(text: String) -> int:
	var code: int = OFFSET
	for i: int in text.length():
		code = mix(code, text.unicode_at(i))
	return code


## `keys` as names, sorted: the order fingerprints and saves go through a dictionary in.
static func sorted(keys: Array) -> Array[String]:
	var names: Array[String] = []
	names.assign(keys)
	names.sort()
	return names
