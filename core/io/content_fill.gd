class_name ContentFill
extends RefCounted
## Fills the content cache (ContentCatalog) in the background (#816): content asked for ahead is
## read on a worker thread of Godot's WorkerThreadPool, one load after another in the order asked,
## so the main thread never waits on files for it. Reading never changes what a tick does: what's
## read is the same on every machine, and only whether it's read yet differs, which the commands
## carry (Command.waiting). Where the build has no threads (the web build), Godot's pool runs the
## task at once, on the thread that adds it.

## No task runs.
const NO_TASK: int = -1

## The loads still to run, in order: each reads one content through its `cached` (or asks for more).
static var _queue: Array[Callable] = []
## The key each queued load reads into, so nothing is queued twice; "" for one that only asks.
static var _queued: Array[String] = []
## Guards the queue and `_running`, held only for a moment.
static var _lock: Mutex = Mutex.new()
## Whether the worker task is still taking loads off the queue.
static var _running: bool = false
## The worker task's id (WorkerThreadPool), until it's waited for; NO_TASK when there's none.
static var _task: int = NO_TASK


## Whether the content of every key in `loads` (a key to the Callable reading it into the catalog)
## is kept already; the ones that aren't are queued to be read in the background, in `loads`' order.
static func have(loads: Dictionary[String, Callable]) -> bool:
	var all_kept: bool = true
	_lock.lock()
	for key: String in loads:
		if ContentCatalog.has(key):
			continue
		all_kept = false
		if not _queued.has(key):
			_queued.append(key)
			_queue.append(loads[key])
	_lock.unlock()
	_run()
	return all_kept


## Queues `asking`, which asks for more loads (`have`) once the ones queued before it are read: for
## loads that depend on content read before them.
static func then(asking: Callable) -> void:
	_lock.lock()
	_queued.append("")
	_queue.append(asking)
	_lock.unlock()
	_run()


## Waits until everything queued is read: for tests, whose walks must never hold for content.
static func wait() -> void:
	if _task != NO_TASK:
		var _waited: Error = WorkerThreadPool.wait_for_task_completion(_task)
		_task = NO_TASK
	_run()


## Starts the worker task if loads wait and none runs, after waiting for a finished one (Godot's
## pool frees a task only once it's waited for). Only the main thread starts it: a load asking for
## more runs while it's running.
static func _run() -> void:
	_lock.lock()
	var start: bool = not _running and not _queue.is_empty()
	var finished: int = _task if not _running else NO_TASK
	if start:
		_running = true
	_lock.unlock()
	if finished != NO_TASK:
		var _waited: Error = WorkerThreadPool.wait_for_task_completion(finished)
		_task = NO_TASK
	if start:
		_task = WorkerThreadPool.add_task(_drain, false, "content fill")


## The worker task: runs the queued loads until none is left.
static func _drain() -> void:
	while true:
		_lock.lock()
		if _queue.is_empty():
			_running = false
			_lock.unlock()
			return
		var next: Callable = _queue.pop_front()
		_queued.remove_at(0)
		_lock.unlock()
		next.call()
