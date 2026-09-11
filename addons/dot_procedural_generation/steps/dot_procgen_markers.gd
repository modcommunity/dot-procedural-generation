@tool
class_name DotProcGenMarkers
extends DotProcGenStep

## Puts a kind of thing in the world: spawns, loot, monsters, lights.
##
## One step, configured, rather than a class per kind. A spawn point and a chest are both
## "a kind, a count, and a rule about where" — which is the same reduction dot-effects
## made when it found nineteen of twenty-one status effects were the same six fields.

enum Placement {
	## One per room, at its centre. Spawns, objectives.
	ROOM_CENTRE,
	## Anywhere walkable, spread out.
	SCATTERED,
	## In the room furthest from the first one. An exit, a boss.
	FURTHEST_ROOM,
}

@export var kind: StringName = &"spawn"

@export var placement: Placement = Placement.ROOM_CENTRE

## How many to place. Zero with ROOM_CENTRE means one per room.
@export_range(0, 1000, 1) var count: int = 0

## Cells that must be clear of any other marker. Zero allows them to stack.
##
## [b]The setting that stops two players spawning inside each other[/b], and the one that
## makes a scattered placement look designed rather than clumped: rejection against a
## minimum distance is what turns uniform noise into something a person would have drawn.
@export_range(0, 64, 1) var min_separation: int = 3

## How many placements to try before giving up on one. Bounded, so a full map terminates.
@export_range(1, 1000, 1) var attempts_each: int = 40


func _fingerprint_keys() -> PackedStringArray:
	return PackedStringArray(["kind", "placement", "count", "min_separation", "attempts_each"])


func validate() -> DotResult:
	if kind == &"":
		return DotResult.fail(DotError.CODE_INVALID, "a marker step with no kind")
	return DotResult.success(null)


func apply(doc: DotProcGenDoc, stream: DotProcGenRandom) -> DotResult:
	match placement:
		Placement.ROOM_CENTRE:
			var wanted := count if count > 0 else doc.rooms.size()
			var order := stream.shuffled(range(doc.rooms.size()))
			for i in range(mini(wanted, order.size())):
				var r: Rect2i = doc.rooms[order[i]]
				doc.add_marker(kind, r.position + r.size / 2, {"room": order[i]})

		Placement.FURTHEST_ROOM:
			if doc.rooms.is_empty():
				return DotResult.success(null)
			var first: Rect2i = doc.rooms[0]
			var best := 0
			var best_d := -1.0
			for i in range(doc.rooms.size()):
				var d := float(
					(doc.rooms[i].position + doc.rooms[i].size / 2).distance_squared_to(
						first.position + first.size / 2
					)
				)
				if d > best_d:
					best_d = d
					best = i
			var room: Rect2i = doc.rooms[best]
			doc.add_marker(kind, room.position + room.size / 2, {"room": best})

		_:
			var placed := 0
			var tries := 0
			while placed < count and tries < count * attempts_each:
				tries += 1
				var cell := Vector2i(
					stream.range_i(1, maxi(1, doc.width - 2)),
					stream.range_i(1, maxi(1, doc.height - 2))
				)
				if not doc.is_walkable(cell.x, cell.y):
					continue
				if min_separation > 0 and _too_close(doc, cell):
					continue
				doc.add_marker(kind, cell)
				placed += 1
			if placed < count:
				# A shortfall is reported rather than retried for ever. A map with room
				# for four chests and a pipeline asking for twenty is a configuration
				# mistake, and the honest answer is to say so and let the pipeline's own
				# retry decide -- not to loop until one fits.
				return DotResult.fail(
					DotError.CODE_STATE,
					"only placed %d of %d '%s'" % [placed, count, kind],
					"not enough walkable space at a separation of %d" % min_separation
				)

	return DotResult.success(null)


func _too_close(doc: DotProcGenDoc, cell: Vector2i) -> bool:
	var limit := min_separation * min_separation
	for m in doc.markers:
		var other: Vector2i = m.get("cell", Vector2i.ZERO)
		if cell.distance_squared_to(other) < limit:
			return true
	return false
