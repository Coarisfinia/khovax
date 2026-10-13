class_name Rng
extends RefCounted
## A deterministic random number generator: xoshiro128**, in integers only, the same on every
## platform and engine version (never Godot's RandomNumberGenerator, whose algorithm and seeding
## could change under us). Every value stays below 2^63, so GDScript's signed 64-bit ints never
## overflow: that is why it is xoshiro128** on 32-bit words rather than a 64-bit generator.
##
## Each system that rolls owns its own stream, seeded from the run's seed and a stream number
## (a feature uses its id: `Rng.new(state.rng_seed, id())` in `start`), keeps it in its state and
## puts `hash_values()` into its own. Adding a roll to one system never shifts another's rolls.
## Draw only inside a tick's step, so the order of draws is the feature order.

const MASK: int = 0xffff_ffff
## 2^32: how many values one draw can give.
const SPAN: int = 0x1_0000_0000
## 2^32 divided by the golden ratio (0x9e3779b9), written in decimal: in hex, CI's check for float
## literals would read its digits as an exponent.
const GOLDEN_GAMMA: int = 2_654_435_769

## The generator's four 32-bit words.
var words: Array[int] = [0, 0, 0, 0]


func _init(seed_value: int, stream: int) -> void:
	# Both 32-bit halves of the seed, then the stream, mixed into one key.
	var key: int = _fmix(_fmix(seed_value & MASK) ^ ((seed_value >> 32) & MASK))
	key = _fmix(key ^ (stream & MASK))
	# Four steps of a counter through the murmur3 finalizer, a bijection on 32 bits: consecutive
	# keys never all map to zero, so the generator never gets the one state it can't leave.
	for i: int in words.size():
		key = (key + GOLDEN_GAMMA) & MASK
		words[i] = _fmix(key)


## A generator in exactly this state, to check it against the reference implementation; rules
## seed theirs with `new`. Null (with an error) unless `state` is four 32-bit words, not all zero:
## the generator can never leave the all-zero state.
static func from_words(state: Array[int]) -> Rng:
	var valid: bool = state.size() == 4
	var nonzero: bool = false
	for word: int in state:
		valid = valid and word >= 0 and word <= MASK
		nonzero = nonzero or word != 0
	if not valid or not nonzero:
		push_error("Rng.from_words needs four 32-bit words, not all zero: %s" % [state])
		return null
	var generator: Rng = Rng.new(0, 0)
	generator.words.assign(state)
	return generator


## The next 32-bit value, 0 to 2^32 - 1.
func next_u32() -> int:
	var result: int = (_rotl((words[1] * 5) & MASK, 7) * 9) & MASK
	var shifted: int = (words[1] << 9) & MASK
	words[2] ^= words[0]
	words[3] ^= words[1]
	words[1] ^= words[2]
	words[0] ^= words[3]
	words[2] ^= shifted
	words[3] = _rotl(words[3], 11)
	return result


## A value from 0 to `count` - 1, every one equally likely: draws that would favor the low values
## (the remainder of 2^32 by `count`) are drawn again rather than folded in with modulo. `count`
## is 1 to 2^32.
func below(count: int) -> int:
	if count < 1 or count > SPAN:
		push_error("Rng.below needs a count from 1 to 2^32, not %d" % count)
		return 0
	var limit: int = SPAN - SPAN % count
	var drawn: int = next_u32()
	while drawn >= limit:
		drawn = next_u32()
	return drawn % count


## A value from `low` to `high`, both included, every one equally likely. At most 2^32 values
## apart; `low` (with an error) otherwise.
func between(low: int, high: int) -> int:
	# Checked without computing high - low first, which overflows for far-apart signed bounds:
	# with low below zero, low + SPAN - 1 can't overflow, and with both at or above zero,
	# high - low can't.
	var too_wide: bool = high > low + SPAN - 1 if low < 0 else high - low >= SPAN
	if high < low or too_wide:
		push_error("Rng.between needs low <= high, at most 2^32 values: %d, %d" % [low, high])
		return low
	return low + below(high - low + 1)


## True in `numerator` out of `denominator` cases, e.g. chance(3, 10) for 30 %. The denominator
## is 1 to 2^32 and the numerator 0 to the denominator; false (with an error) otherwise.
func chance(numerator: int, denominator: int) -> bool:
	if numerator < 0 or numerator > denominator or denominator < 1 or denominator > SPAN:
		push_error("Rng.chance needs 0 <= %d <= %d <= 2^32" % [numerator, denominator])
		return false
	return below(denominator) < numerator


## An index into `weights`, each picked in proportion to its weight. Weights are 0 or more and
## add up to 1 to 2^32; 0 (with an error) otherwise.
func pick_weighted(weights: Array[int]) -> int:
	var total: int = 0
	for weight: int in weights:
		# Each check before adding, so the total never overflows.
		if weight < 0 or weight > SPAN - total:
			total = SPAN + 1
			break
		total += weight
	if total < 1 or total > SPAN:
		push_error("Rng.pick_weighted needs weights of 0 or more adding up to 1 to 2^32")
		return 0
	var roll: int = below(total)
	for i: int in weights.size():
		if roll < weights[i]:
			return i
		roll -= weights[i]
	return weights.size() - 1


## The generator's state, for the hash of whatever owns it.
func hash_values() -> Array[int]:
	var values: Array[int] = []
	values.assign(words)
	return values


static func _rotl(value: int, bits: int) -> int:
	return ((value << bits) | (value >> (32 - bits))) & MASK


## The murmur3 finalizer: mixes every input bit into every output bit.
static func _fmix(value: int) -> int:
	var h: int = value
	h ^= h >> 16
	h = _mul(h, 0x85eb_ca6b)
	h ^= h >> 13
	h = _mul(h, 0xc2b2_ae35)
	h ^= h >> 16
	return h


## a × b modulo 2^32 for 32-bit values, in 16-bit halves of b so no product reaches 2^63.
static func _mul(a: int, b: int) -> int:
	var low: int = a * (b & 0xffff)
	var high: int = ((a * (b >> 16)) & 0xffff) << 16
	return (low + high) & MASK
