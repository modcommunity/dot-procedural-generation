@tool
class_name DotProcGenPipeline
extends Resource

## An ordered list of steps, a seed, and the two things that make it safe to ship.
##
## [codeblock]
## var p := DotProcGenPipeline.new()
## p.width = 64
## p.height = 64
## p.add(rooms_step).add(connect_step).add(spawns_step).add(validate_step)
##
## var res := p.generate(seed)
## if res.ok:
##     build_world(res.value as DotProcGenDoc)
## [/codeblock]
##
## [b]1. It refuses an unfinishable map rather than shipping one.[/b] A validate step
## floods the document from a spawn and fails if anything it should reach is cut off, and
## the pipeline then **retries on a different seed** up to [member max_attempts]. That is
## the whole difference between procedural generation being a feature and being a source
## of unplayable rounds, and this family has the lesson written down from the other
## direction: eight imported maps passed 168 assertions about their zones while five of
## them could not be finished. *A map that loads is not a level.*
##
## [b]2. It has a fingerprint.[/b] Two peers compare [method fingerprint] and a seed, not
## a map. Same idea as dot-net's message schema hash — and the same failure if it is got
## wrong, because a check that exists to catch a mismatch is the one thing that can hide
## one. Every step's settings go into it, in list order, with nothing sorted by
## [StringName]: Godot compares those by their interned pointer, which gave two peers two
## different orders and two different wire ids the last time anybody sorted a list of them.

const CHANNEL := "procgen"

@export var width: int = 64
@export var height: int = 64

@export var steps: Array[DotProcGenStep] = []

## How many seeds to try before giving up.
##
## [b]Not one.[/b] A generator with a validate step and no retries fails outright on the
## unlucky seed, which on a server is a map change that does not happen. Ten is generous:
## a pipeline that fails ten seeds in a row is misconfigured rather than unlucky, and
## saying so is more useful than trying a hundred.
@export_range(1, 1000, 1) var max_attempts: int = 10

## A name mixed into every seed, so two pipelines on one seed are two different worlds.
@export var pipeline_name: StringName = &"world"

## Anything with [code]seed_for(name) -> int[/code]. dot-randomness' manager, duck-typed.
##
## How a generated world comes out of the session's seed rather than out of one of its
## own, without this addon depending on that one. Null means the seed passed to
## [method generate] is used directly.
var seed_source: Object = null


func add(step: DotProcGenStep) -> DotProcGenPipeline:
	steps.append(step)
	return self


func validate() -> DotResult:
	if width <= 0 or height <= 0:
		return DotResult.fail(DotError.CODE_INVALID, "a pipeline with no size")
	if steps.is_empty():
		return DotResult.fail(
			DotError.CODE_INVALID,
			"a pipeline with no steps",
			"it would produce a solid block, which is a legitimate document and never what anybody meant"
		)
	var names := {}
	for s in steps:
		if s == null:
			return DotResult.fail(DotError.CODE_INVALID, "a null step in the pipeline")
		var res := s.validate()
		if not res.ok:
			return res.wrap("step '%s'" % s.step_name)
		if names.has(s.step_name):
			# Two steps sharing a name share a stream, so the second one continues where
			# the first left off -- which is not wrong, exactly, but it means reordering
			# them changes both, and nobody expects that from a rename.
			return DotResult.fail(
				DotError.CODE_INVALID,
				"two steps are both called '%s'" % s.step_name,
				"a step's name is its random stream; two with one name share it"
			)
		names[s.step_name] = true
	return DotResult.success(null)


## Generates a document, retrying on a new seed when a step refuses the result.
##
## The returned document carries [code]meta.seed[/code] and [code]meta.attempts[/code],
## because "which seed did this come from" is the first question about any generated world
## and the answer being in the document is the difference between a reproducible bug report
## and a story.
func generate(base_seed: int) -> DotResult:
	var res := validate()
	if not res.ok:
		return res

	var root := base_seed
	if seed_source != null and seed_source.has_method("seed_for"):
		root = int(seed_source.call("seed_for", pipeline_name))

	var last_failure := DotResult.fail(DotError.CODE_STATE, "nothing ran")
	for attempt in range(max_attempts):
		# The attempt is mixed into the seed rather than added. Adding gives seed+1, which
		# is somebody else's world -- so a failure on seed 41 quietly hands a player the
		# map that seed 42 should have produced, and two people comparing notes disagree.
		var attempt_seed := DotProcGenRandom._mix(root ^ DotProcGenRandom._mix(attempt))
		var out := _run_once(attempt_seed, root, attempt)
		if out.ok:
			return out
		last_failure = out
		DotLog.debug(
			CHANNEL,
			"generation refused, trying another seed",
			{"attempt": attempt + 1, "why": out.error.message}
		)

	return last_failure.wrap(
		"gave up after %d attempts" % max_attempts
	)


func _run_once(attempt_seed: int, root_seed: int, attempt: int) -> DotResult:
	var doc := DotProcGenDoc.new()
	doc.resize(width, height)
	doc.meta["seed"] = root_seed
	doc.meta["attempt"] = attempt
	doc.meta["pipeline"] = String(pipeline_name)

	var root := DotProcGenRandom.new(attempt_seed, pipeline_name)
	for s in steps:
		if not s.enabled:
			continue
		var res := s.apply(doc, root.stream(s.step_name))
		if not res.ok:
			return res.wrap("step '%s'" % s.step_name)

	doc.meta["fingerprint"] = doc.fingerprint()
	return DotResult.success(doc)


## What two peers compare, alongside the seed.
##
## Covers the size, every step's name and every step's own settings, in list order. A
## disabled step is still in it, because a pipeline with a step disabled is a different
## pipeline and two peers disagreeing about *that* is exactly the case this is for.
func fingerprint() -> String:
	var parts := PackedStringArray(["%d:%dx%d" % [max_attempts, width, height], String(pipeline_name)])
	for s in steps:
		parts.append(s.fingerprint() if s != null else "null")
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("|".join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 32)


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("pipeline '%s' %dx%d, %d steps" % [pipeline_name, width, height, steps.size()])
	for s in steps:
		out.append("  %s" % (s.describe_line() if s != null else "<null>"))
	out.append("  fingerprint %s" % fingerprint())
	return out
