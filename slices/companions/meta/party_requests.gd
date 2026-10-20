class_name PartyRequests
extends RefCounted
## Tells the world who the player carries (#818): their profile keeps it, outside the simulation,
## so it rides to the world as a run of requests from the profile's outbox (#771, CarryRequest),
## which the world takes into their party (CompanionParty.take_request).


## Posts a run of requests bringing `party` to `outbox` when the world's party, `stored` (the
## player's entry of CompanionFeature in their world store) once the run it's taking and the
## outbox's waiting runs are whole, isn't it: for a world new to it, a profile whose party changed
## since, or a run that can't be whole anymore; returns whether it posted one, which takes the
## place of every run before it.
static func catch_up(party: CarriedMonsters, outbox: Outbox, stored: Dictionary) -> bool:
	var wanted: Array[int] = CarryRequest.values_of(party)
	if _values_after(outbox, stored) == wanted:
		return false
	for place: int in wanted.size():
		var data: int = CarryRequest.data_of(place, party.size(), wanted[place])
		var _posted: OutboxEntry = outbox.post(OutboxEntry.CARRY, data)
	return true


## The values of the party the world's `stored` entry will hold once the run it's taking goes on
## with the carry requests waiting in `outbox`: those of the last run that ends whole, or of its
## party now when none does.
static func _values_after(outbox: Outbox, stored: Dictionary) -> Array[int]:
	var last: Array[int] = CarryRequest.values_of(CompanionParty.of_entry(stored))
	var run: Array[int] = []
	var incoming: Variant = stored.get(CompanionParty.INCOMING, [])
	for value: Variant in incoming if incoming is Array else []:
		if value is int:
			run.append(value)
	for request: OutboxEntry in outbox.entries:
		if request.kind != OutboxEntry.CARRY:
			continue
		if CarryRequest.place_of(request.data) == 0:
			run = []
		if run.size() != CarryRequest.place_of(request.data):
			continue
		run.append(CarryRequest.value_of(request.data))
		if run.size() >= 2 * CarryRequest.count_of(request.data):
			last = run.duplicate()
	return last
