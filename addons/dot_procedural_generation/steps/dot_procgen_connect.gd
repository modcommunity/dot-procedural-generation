@tool
class_name DotProcGenConnect
extends DotProcGenStep

## Joins every room to every other, and then adds a few loops on purpose.
##
## A minimum spanning tree first, because that is the cheapest set of corridors that
## guarantees the map is one piece — and then [member extra_loops] more, because
## **a spanning tree is a bad level**. A tree has exactly one route between any two rooms,
## so every fight is a corridor, every retreat is the way you came, and the map reads as a
## sequence rather than as a place. Every hand-built level in the genre has loops in it.
##
## The MST is Prim's rather than Kruskal's for one practical reason: Prim's needs no
## union-find and no sort, and **no sort means nothing here is ever sorted by
## [StringName]** — which is the shape of a bug this family has already paid for, where
## two peers got two different orders out of one list and two different wire ids from it.

## How many corridors beyond the spanning tree. Zero is a tree, which is a bad level.
@export_range(0, 100, 1) var extra_loops: int = 3

## Corridor width in cells.
##
## One is the classic and is worth thinking about before shipping: a one-cell corridor
## cannot be walked past somebody in, which in a co-operative game means the slowest player
## sets the pace of the whole map.
@export_range(1, 8, 1) var corridor_width: int = 1

## Whether corridors turn once (L-shaped) or go straight.
@export var elbow: bool = true

@export var floor_value: int = DotProcGenDoc.FLOOR


func _fingerprint_keys() -> PackedStringArray:
	return PackedStringArray(["extra_loops", "corridor_width", "elbow", "floor_value"])


func apply(doc: DotProcGenDoc, stream: DotProcGenRandom) -> DotResult:
	if doc.rooms.size() < 2:
		# One room is already connected. Not a failure: a cave pipeline with no rooms in
		# it is a legitimate thing to run this step after, and refusing would make the
		# step order matter for no reason.
		return DotResult.success(null)

	var centres: Array[Vector2i] = []
	for r in doc.rooms:
		centres.append(r.position + r.size / 2)

	# Prim's: grow one connected set, always taking the cheapest edge out of it.
	var inside := PackedByteArray()
	inside.resize(centres.size())
	inside[0] = 1
	var joined := 1

	while joined < centres.size():
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for a in range(centres.size()):
			if inside[a] == 0:
				continue
			for b in range(centres.size()):
				if inside[b] == 1:
					continue
				var d := float(centres[a].distance_squared_to(centres[b]))
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		if best_b < 0:
			break
		inside[best_b] = 1
		joined += 1
		doc.links.append(Vector2i(best_a, best_b))
		_carve(doc, centres[best_a], centres[best_b], stream)

	# And then the loops, which are what stop it being a sequence.
	for _i in range(extra_loops):
		var a := stream.range_i(0, centres.size() - 1)
		var b := stream.range_i(0, centres.size() - 1)
		if a == b:
			continue
		var pair := Vector2i(mini(a, b), maxi(a, b))
		if doc.links.has(pair) or doc.links.has(Vector2i(pair.y, pair.x)):
			continue
		doc.links.append(pair)
		_carve(doc, centres[a], centres[b], stream)

	return DotResult.success(null)


func _carve(doc: DotProcGenDoc, from: Vector2i, to: Vector2i, stream: DotProcGenRandom) -> void:
	var corner := Vector2i(to.x, from.y) if stream.chance(0.5) else Vector2i(from.x, to.y)
	if not elbow:
		corner = from
	_line(doc, from, corner)
	_line(doc, corner, to)


func _line(doc: DotProcGenDoc, a: Vector2i, b: Vector2i) -> void:
	var half := corridor_width / 2
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var at := a
	var guard := 0
	while at != b and guard < 10000:
		_brush(doc, at, half)
		if at.x != b.x:
			at.x += step.x
		elif at.y != b.y:
			at.y += step.y
		guard += 1
	_brush(doc, b, half)


func _brush(doc: DotProcGenDoc, at: Vector2i, half: int) -> void:
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			# The border is left alone. A corridor that reaches the edge of the document
			# is a hole in the outside wall, and on a map that is extruded into 3D it is a
			# player walking out of the world.
			var x := at.x + dx
			var y := at.y + dy
			if x <= 0 or y <= 0 or x >= doc.width - 1 or y >= doc.height - 1:
				continue
			doc.set_at(x, y, floor_value)
