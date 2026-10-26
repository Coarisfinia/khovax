class_name CarryRequest
extends RefCounted
## The monsters a player carries, as requests from their profile's outbox (#818,
## OutboxEntry.CARRY): their profile holds them, outside the simulation, and the world takes them
## into the player's party (CompanionParty.take_request). A request's data holds one whole number,
## too few bits for a monster's short id and its species together, so a party is a run of
## requests: each monster's species' code (species_code) with its level (`species_value`, #1255),
## then its short id's code (ShortId.code), in carried order. Each request's data also says its
## place in the run and how many monsters the run brings, so the world knows where a run starts and
## ends; a run of none is one request. A value's bits past VALUE_BITS (a level above 1) go above
## the count, so a monster at level 1 is sent as before levels.

## How many bits a value takes in a request's data: a short id's code, or a species' code.
const VALUE_BITS: int = 35
## How many dominated monsters a player carries (#53): always three, never more. The profile's
## limit (Profile.CARRY_LIMIT) and the swap keys (LocalInput.SWAP_ACTIONS) follow it.
const MOST_CARRIED: int = 3
## How many bits a request's place in its run takes: enough for a run of MOST_CARRIED monsters,
## two requests each, so a place never wraps to 0 and restarts the run (the world flow checks it).
const PLACE_BITS: int = 3
## How many bits the count of monsters a run brings takes: enough for MOST_CARRIED.
const COUNT_BITS: int = 2
## The highest level a request carries: a monster above it is sent at it. Its bits above the count
## keep a request's data within what a save holds (DataReader.MOST).
const MOST_LEVEL: int = 1000


## The values a run of requests for `party` carries, in order: each monster's species' code with
## its level, and its short id's code; one value, 0, for none.
static func values_of(party: CarriedMonsters) -> Array[int]:
	var values: Array[int] = []
	for place: int in party.size():
		values.append(species_value(party.species[place], party.levels[place]))
		values.append(ShortId.code(party.short_ids[place]))
	if values.is_empty():
		values.append(0)
	return values


## The data of the request at `place` in a run that brings `count` monsters, carrying `value`.
static func data_of(place: int, count: int, value: int) -> int:
	var above: int = value >> VALUE_BITS
	var below: int = value & ((1 << VALUE_BITS) - 1)
	return (((((above << COUNT_BITS) + count) << PLACE_BITS) + place) << VALUE_BITS) + below


## The place in its run of the request with the data `data`.
static func place_of(data: int) -> int:
	return (data >> VALUE_BITS) & ((1 << PLACE_BITS) - 1)


## How many monsters the run of the request with the data `data` brings.
static func count_of(data: int) -> int:
	return (data >> (VALUE_BITS + PLACE_BITS)) & ((1 << COUNT_BITS) - 1)


## The value the request with the data `data` carries.
static func value_of(data: int) -> int:
	var above: int = data >> (VALUE_BITS + PLACE_BITS + COUNT_BITS)
	return (above << VALUE_BITS) + (data & ((1 << VALUE_BITS) - 1))


## The value a run carries for a monster of the species `species_id` at `level`, from 1 up to
## MOST_LEVEL: its species' code, and its level above 1 past VALUE_BITS.
static func species_value(species_id: String, level: int) -> int:
	return ((clampi(level, 1, MOST_LEVEL) - 1) << VALUE_BITS) + species_code(species_id)


## The species' code in a monster's `value` (species_value).
static func code_in(value: int) -> int:
	return value & ((1 << VALUE_BITS) - 1)


## The level in a monster's `value` (species_value), from 1.
static func level_in(value: int) -> int:
	return (value >> VALUE_BITS) + 1


## The code a request carries for the species `species_id` (CommandCodes): never NONE for a
## species, whose content the companions file with CommandCodes.file.
static func species_code(species_id: String) -> int:
	return CommandCodes.of(species_id)
