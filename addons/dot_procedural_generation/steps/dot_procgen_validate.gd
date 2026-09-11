@tool
class_name DotProcGenValidate
extends DotProcGenStep

## Floods the document from a marker and refuses a map that cannot be finished.
##
## [b]This is the step that makes runtime generation safe to ship, and the one every
## implementation leaves out.[/b] Generation is easy; generation that cannot produce an
## unplayable round is the whole problem. A cellular-automata cave has sealed pockets by
## construction, a room placer can put a start behind a wall it carved later, and a
## scattered objective lands in a chamber with no door about one seed in thirty.
##
## Every one of those is invisible to every other kind of check. The map is well formed,
## the counts are right, the rooms are the size they should be — and a player walks into it
## and cannot finish. This family has the lesson recorded from the other direction: eight
## imported maps passed 168 assertions about their zones while five of them could not be
## finished, because every assertion was about a zone existing and none was about the zones
## adding up to a run. *A map that loads is not a level.*
##
## Failing here is not a crash. [DotProcGenPipeline] catches it and tries another seed.

## The marker the flood starts from.
@export var from_kind: StringName = &"spawn"

## Marker kinds that must all be reachable from it.
##
## Empty means "every marker", which is the right default: a thing placed in a world is a
## thing somebody is meant to reach, and the exceptions are rarer than the rule.
@export var must_reach: Array[StringName] = []

## The least fraction of walkable cells that must be in the same region as the start.
##
## [b]A map can be technically connected and still mostly wasted.[/b] One thread of
## corridor to a far wing satisfies "everything is reachable" while nine tenths of the
## generated space is a sealed pocket nobody will ever see — which reads as a generator
## that produces small maps rather than as one producing large broken ones.
@export_range(0.0, 1.0, 0.01) var min_connected_fraction: float = 0.6

## Whether to fill in what the flood could not reach.
##
## [b]An alternative to failing, and usually the better one.[/b] A cave with its sealed
## pockets filled in is a good cave; the same cave with them left in is a good cave plus
## some rooms that do not exist as far as a player is concerned but do exist as far as a
## navigation mesh, a light bake and a spawn placer are concerned.
@export var fill_unreachable: bool = true


func _fingerprint_keys() -> PackedStringArray:
	return PackedStringArray([
		"from_kind", "must_reach", "min_connected_fraction", "fill_unreachable"
	])


func apply(doc: DotProcGenDoc, _stream: DotProcGenRandom) -> DotResult:
	var starts := doc.markers_of(from_kind)
	if starts.is_empty():
		return DotResult.fail(
			DotError.CODE_STATE,
			"nothing to flood from: no '%s' marker" % from_kind,
			"a validate step placed after nothing that places a start has nothing to check"
		)

	var start: Vector2i = starts[0].get("cell", Vector2i.ZERO)
	if not doc.is_walkable(start.x, start.y):
		return DotResult.fail(
			DotError.CODE_STATE,
			"the '%s' marker is inside a wall" % from_kind,
			"at %d,%d" % [start.x, start.y]
		)

	var reached := doc.reachable_from(start)
	var reachable := {}
	for idx in reached:
		reachable[idx] = true

	var walkable := 0
	for y in range(doc.height):
		for x in range(doc.width):
			if doc.is_walkable(x, y):
				walkable += 1

	if walkable > 0:
		var fraction := float(reached.size()) / float(walkable)
		if fraction < min_connected_fraction:
			return DotResult.fail(
				DotError.CODE_STATE,
				"only %.0f%% of the walkable space is reachable" % (fraction * 100.0),
				"a map that is connected and mostly wasted reads as a generator making small maps"
			)

	for m in doc.markers:
		var kind := StringName(str(m.get("kind", "")))
		if not must_reach.is_empty() and not must_reach.has(kind):
			continue
		var cell: Vector2i = m.get("cell", Vector2i.ZERO)
		var idx := cell.y * doc.width + cell.x
		if not reachable.has(idx):
			return DotResult.fail(
				DotError.CODE_STATE,
				"'%s' at %d,%d cannot be reached from the start" % [kind, cell.x, cell.y]
			)

	if fill_unreachable:
		var filled := 0
		for y in range(doc.height):
			for x in range(doc.width):
				if not doc.is_walkable(x, y):
					continue
				if reachable.has(y * doc.width + x):
					continue
				doc.set_at(x, y, DotProcGenDoc.SOLID)
				filled += 1
		if filled > 0:
			doc.meta["unreachable_filled"] = filled

	doc.meta["reachable_cells"] = reached.size()
	return DotResult.success(null)
