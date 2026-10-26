class_name SoakWindow
extends RefCounted
## One window of frames the soak test measured (#1311): its median frame time, the median time of
## the reference work beside it, both in microseconds, and its median draw calls a frame.

var frame_usec: int = 0
var reference_usec: int = 1
var draws: int = 0


func _init(frame: int, reference_time: int, draw_calls: int) -> void:
	frame_usec = frame
	reference_usec = maxi(reference_time, 1)
	draws = draw_calls


## The frame time in references: how many times the reference work would fit into a frame.
func relative() -> float:
	return float(frame_usec) / reference_usec


func line() -> String:
	return "frame %6d us (%5.1f references of %4d us), %4d draw calls" % [
		frame_usec,
		relative(),
		reference_usec,
		draws,
	]


## The middle sample, or of an even count the mean of the two middle ones (rounded down); 0 for
## none.
static func median(samples: Array[int]) -> int:
	if samples.is_empty():
		return 0
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var middle: int = sorted.size() >> 1
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return (sorted[middle - 1] + sorted[middle]) >> 1
