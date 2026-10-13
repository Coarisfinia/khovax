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
const GOLDEN_GAMMA: int = 0x9e37_79b9

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


## A generator in exactly this state, e.g. to check it against the reference implementation.
static func from_words(state: Array[int]) -> Rng:
	var generator: Rng = Rng.new(0, 0)
	for i: int in generator.words.size():
		generator.words[i] = state[i] & MASK
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


## A value from `low` to `high`, both included, every one equally likely.
func between(low: int, high: int) -> int:
	return low + below(high - low + 1)


## True in `numerator` out of `denominator` cases, e.g. chance(3, 10) for 30 %.
func chance(numerator: int, denominator: int) -> bool:
	return below(denominator) < numerator


## An index into `weights`, each picked in proportion to its weight. Weights are 0 or more and
## add up to 1 to 2^32.
func pick_weighted(weights: Array[int]) -> int:
	var total: int = 0
	for weight: int in weights:
		total += weight
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
