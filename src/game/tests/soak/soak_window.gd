class_name SoakWindow
extends RefCounted
## One window of frames the soak test measured (#1311): its median frame time, the median time of
## the reference work beside it, the median time of a frame's tick (#2084), all in microseconds,
## and its median draw calls a frame. Or the middle of several windows' measures (`middle`, #2293).

var frame_usec: int = 0
var reference_usec: int = 1
var tick_usec: int = 0
var draws: int = 0
## The frame and the tick time in references: of one window, its own; of several, the middle ones.
var _relative: float = 0.0
var _relative_tick: float = 0.0


func _init(frame: int, reference_time: int, tick: int, draw_calls: int) -> void:
	frame_usec = frame
	reference_usec = maxi(reference_time, 1)
	tick_usec = tick
	draws = draw_calls
	_relative = float(frame_usec) / reference_usec
	_relative_tick = float(tick_usec) / reference_usec


## The frame time in references: how many times the reference work would fit into a frame.
func relative() -> float:
	return _relative


## The tick's time in references.
func relative_tick() -> float:
	return _relative_tick


func line() -> String:
	return "frame %6d us (%5.1f references of %4d us), tick %5d us (%5.1f), %4d draw calls" % [
		frame_usec,
		relative(),
		reference_usec,
		tick_usec,
		relative_tick(),
		draws,
	]


## The middle of `windows`' measures, each on its own: the times, the draw calls and the times in
## references, so one window a busy runner slowed, or sped its reference, doesn't decide (#2293).
static func middle(windows: Array[SoakWindow]) -> SoakWindow:
	var frames: Array[int] = []
	var references: Array[int] = []
	var ticks: Array[int] = []
	var draw_calls: Array[int] = []
	var relatives: Array[float] = []
	var relative_ticks: Array[float] = []
	for window: SoakWindow in windows:
		frames.append(window.frame_usec)
		references.append(window.reference_usec)
		ticks.append(window.tick_usec)
		draw_calls.append(window.draws)
		relatives.append(window.relative())
		relative_ticks.append(window.relative_tick())
	var middle_one: SoakWindow = SoakWindow.new(
		median(frames),
		median(references),
		median(ticks),
		median(draw_calls),
	)
	middle_one._relative = median_of(relatives)
	middle_one._relative_tick = median_of(relative_ticks)
	return middle_one


## The middle sample, or of an even count the mean of the two middle ones (rounded down); 0 for
## none.
static func median(samples: Array[int]) -> int:
	var values: Array[float] = []
	for sample: int in samples:
		values.append(sample)
	return floori(median_of(values))


## The middle value, or of an even count the mean of the two middle ones; 0 for none.
static func median_of(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var middle_at: int = sorted.size() >> 1
	if sorted.size() % 2 == 1:
		return sorted[middle_at]
	return (sorted[middle_at - 1] + sorted[middle_at]) / 2.0
