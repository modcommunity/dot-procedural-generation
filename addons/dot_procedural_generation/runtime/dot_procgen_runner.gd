class_name DotProcGenRunner
extends Node

## Runs a pipeline, either all at once or a step per frame.
##
## [codeblock]
## var runner := DotProcGenRunner.new()
## runner.pipeline = my_pipeline
## add_child(runner)
## runner.finished.connect(_build)
## runner.begin(seed)                  # sliced across frames
## [/codeblock]
##
## [b]Sliced on the main thread, not threaded.[/b] `DotPlatform.has_threads()` is false on
## a web template that was not built for them, which is most of them, and a generator that
## only works on desktop is one this family cannot ship — the same reason `DotScheduler`
## slices inside a frame budget rather than assuming a worker.
##
## One step per frame is the granularity on purpose. A step is the unit that leaves the
## document consistent: half a room-carving pass is a document with a partial room in it,
## and the one thing worse than a slow generator is one that can be observed half-done.

const CHANNEL := "procgen"

## A step is about to run. [param index] of [param total].
signal step_started(name: StringName, index: int, total: int)

## Generation finished. [param doc] is null when it failed.
signal finished(doc: DotProcGenDoc, res: DotResult)

@export var pipeline: DotProcGenPipeline = null

## Milliseconds of one frame this may take before yielding.
##
## Only consulted between steps: a step is atomic here. A pipeline with one enormous step
## blocks for as long as that step takes however small this is, which is a reason to split
## a step rather than a reason to slice inside one.
@export_range(1, 200, 1) var frame_budget_ms: int = 8

var _running := false
var _doc: DotProcGenDoc = null
var _root: DotProcGenRandom = null
var _index := 0
var _attempt := 0
var _root_seed := 0
var _started_ms := 0


## Generates now, blocking. What a server and a suite want.
func generate_now(seed_value: int) -> DotResult:
	if pipeline == null:
		return DotResult.fail(DotError.CODE_STATE, "no pipeline")
	var res := pipeline.generate(seed_value)
	finished.emit(res.value_or(null), res)
	return res


## Starts a sliced run. [signal finished] carries the result.
func begin(seed_value: int) -> DotResult:
	if pipeline == null:
		return DotResult.fail(DotError.CODE_STATE, "no pipeline")
	if _running:
		return DotResult.fail(DotError.CODE_STATE, "already generating")
	var res := pipeline.validate()
	if not res.ok:
		return res

	_root_seed = seed_value
	if pipeline.seed_source != null and pipeline.seed_source.has_method("seed_for"):
		_root_seed = int(pipeline.seed_source.call("seed_for", pipeline.pipeline_name))
	_attempt = 0
	_running = true
	_begin_attempt()
	set_process(true)
	return DotResult.success(null)


func cancel() -> void:
	_running = false
	_doc = null
	set_process(false)


func running() -> bool:
	return _running


func progress() -> float:
	if not _running or pipeline == null or pipeline.steps.is_empty():
		return 1.0 if not _running else 0.0
	return float(_index) / float(pipeline.steps.size())


func _begin_attempt() -> void:
	var attempt_seed := DotProcGenRandom._mix(_root_seed ^ DotProcGenRandom._mix(_attempt))
	_doc = DotProcGenDoc.new()
	_doc.resize(pipeline.width, pipeline.height)
	_doc.meta["seed"] = _root_seed
	_doc.meta["attempt"] = _attempt
	_doc.meta["pipeline"] = String(pipeline.pipeline_name)
	_root = DotProcGenRandom.new(attempt_seed, pipeline.pipeline_name)
	_index = 0


func _process(_delta: float) -> void:
	if not _running:
		return
	_started_ms = Time.get_ticks_msec()

	while _index < pipeline.steps.size():
		var step := pipeline.steps[_index]
		_index += 1
		if step == null or not step.enabled:
			continue

		step_started.emit(step.step_name, _index, pipeline.steps.size())
		var res := step.apply(_doc, _root.stream(step.step_name))
		if not res.ok:
			_on_attempt_failed(res.wrap("step '%s'" % step.step_name))
			return

		# Between steps, never inside one. Half a carving pass is a document with a
		# partial room in it, and a half-generated document is the one thing worse than a
		# slow generator.
		if Time.get_ticks_msec() - _started_ms >= frame_budget_ms:
			return

	_running = false
	set_process(false)
	_doc.meta["fingerprint"] = _doc.fingerprint()
	finished.emit(_doc, DotResult.success(_doc))


func _on_attempt_failed(res: DotResult) -> void:
	_attempt += 1
	if _attempt >= pipeline.max_attempts:
		_running = false
		set_process(false)
		DotLog.warn(
			CHANNEL,
			"generation gave up",
			{"attempts": _attempt, "why": res.error.message}
		)
		finished.emit(null, res.wrap("gave up after %d attempts" % _attempt))
		return
	DotLog.debug(CHANNEL, "retrying on another seed", {"attempt": _attempt})
	_begin_attempt()


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("dot-procgen  %s" % ("running" if _running else "idle"))
	if _running:
		out.append("  attempt %d, step %d of %d" % [
			_attempt + 1, _index, pipeline.steps.size()
		])
	if pipeline != null:
		out.append_array(pipeline.describe_lines())
	return out
