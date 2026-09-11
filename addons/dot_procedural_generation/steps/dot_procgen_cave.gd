@tool
class_name DotProcGenCave
extends DotProcGenStep

## Cellular automata: noise, then smooth it until it looks like caves.
##
## The classic four-four rule, and the two things worth knowing about it are both about
## what it does NOT give you:
##
## [b]It produces disconnected caverns, always.[/b] Smoothing noise makes pockets, and
## some of them are sealed. That is not a bug to be tuned out — it is what the algorithm
## is — and the answer is [DotProcGenConnect] or [DotProcGenValidate] afterwards, not a
## better rule. A generator that ships this step alone ships unreachable treasure.
##
## [b]The iteration order matters and must not be in place.[/b] Reading the grid you are
## writing means a cell sees its left neighbour's new value and its right neighbour's old
## one, which biases every feature to the right and is invisible in a screenshot. Two
## buffers, swapped.

## Fraction of cells that start solid.
@export_range(0.0, 1.0, 0.01) var fill_chance: float = 0.45

## How many smoothing passes. Three or four is usually enough; more erases detail.
@export_range(0, 20, 1) var iterations: int = 4

## A cell becomes solid when it has at least this many solid neighbours.
@export_range(1, 8, 1) var birth_limit: int = 5

## A solid cell stays solid when it has at least this many.
@export_range(0, 8, 1) var death_limit: int = 4

## Whether the border is forced solid.
@export var solid_border: bool = true


func _fingerprint_keys() -> PackedStringArray:
	return PackedStringArray([
		"fill_chance", "iterations", "birth_limit", "death_limit", "solid_border"
	])


func apply(doc: DotProcGenDoc, stream: DotProcGenRandom) -> DotResult:
	for y in range(doc.height):
		for x in range(doc.width):
			var solid := stream.chance(fill_chance)
			if solid_border and (x == 0 or y == 0 or x == doc.width - 1 or y == doc.height - 1):
				solid = true
			doc.set_at(x, y, DotProcGenDoc.SOLID if solid else DotProcGenDoc.FLOOR)

	for _i in range(iterations):
		# Written into a copy. Smoothing in place makes every cell see its left
		# neighbour's new value and its right neighbour's old one, which drags every
		# feature to one side -- and looks exactly like a plausible cave system.
		var next := doc.cells.duplicate()
		for y in range(doc.height):
			for x in range(doc.width):
				var n := _solid_neighbours(doc, x, y)
				var was_solid := doc.at(x, y) == DotProcGenDoc.SOLID
				var now_solid := n >= (death_limit if was_solid else birth_limit)
				if solid_border and (x == 0 or y == 0 or x == doc.width - 1 or y == doc.height - 1):
					now_solid = true
				next[y * doc.width + x] = DotProcGenDoc.SOLID if now_solid else DotProcGenDoc.FLOOR
		doc.cells = next

	if doc.count_of(DotProcGenDoc.FLOOR) < 8:
		return DotResult.fail(
			DotError.CODE_STATE,
			"the cave came out almost solid",
			"fill_chance %.2f with birth_limit %d closes everything" % [fill_chance, birth_limit]
		)
	return DotResult.success(null)


func _solid_neighbours(doc: DotProcGenDoc, x: int, y: int) -> int:
	var n := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			# Out of bounds counts as solid, which is what DotProcGenDoc.at already
			# answers -- and is what keeps a cave from opening onto nothing at the edge.
			if doc.at(x + dx, y + dy) == DotProcGenDoc.SOLID:
				n += 1
	return n
