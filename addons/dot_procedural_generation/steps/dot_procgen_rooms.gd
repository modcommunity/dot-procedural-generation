@tool
class_name DotProcGenRooms
extends DotProcGenStep

## Carves rooms by binary space partition: split the area, put a room in each leaf.
##
## BSP rather than "place rectangles at random and reject overlaps", which is the obvious
## approach and is wrong in a way that only shows on a big map: rejection sampling gets
## slower as the map fills, so a 64x64 map generates instantly and a 256x256 one with the
## same settings takes seconds — and the failure is a frame hitch on the one map somebody
## made big, not a bug anybody can find.
##
## BSP also gives a tree, which is a connection plan for free: siblings are adjacent by
## construction, so [DotProcGenConnect] never has to guess which rooms should be joined.

## Smallest a leaf may be before it stops splitting, in cells.
@export_range(3, 200, 1) var min_leaf: int = 9

## How much smaller than its leaf a room is, as a fraction, at most.
@export_range(0.0, 0.9, 0.05) var margin: float = 0.25

## How lopsided a split may be. 0.5 is always down the middle.
@export_range(0.05, 0.5, 0.01) var split_jitter: float = 0.2

## Fewest rooms that count as a success.
@export_range(1, 500, 1) var min_rooms: int = 4

@export var wall_value: int = DotProcGenDoc.SOLID
@export var floor_value: int = DotProcGenDoc.FLOOR


func _fingerprint_keys() -> PackedStringArray:
	return PackedStringArray([
		"min_leaf", "margin", "split_jitter", "min_rooms", "wall_value", "floor_value"
	])


func validate() -> DotResult:
	if min_leaf < 3:
		return DotResult.fail(
			DotError.CODE_INVALID, "a leaf below three cells cannot hold a room with walls"
		)
	if min_rooms < 1:
		return DotResult.fail(DotError.CODE_INVALID, "a room step that wants no rooms")
	return DotResult.success(null)


func apply(doc: DotProcGenDoc, stream: DotProcGenRandom) -> DotResult:
	doc.cells.fill(wall_value)
	doc.rooms.clear()
	doc.links.clear()

	var leaves: Array[Rect2i] = []
	_split(Rect2i(1, 1, doc.width - 2, doc.height - 2), stream, leaves, 0)

	for leaf in leaves:
		var room := _room_in(leaf, stream)
		if room.size.x < 2 or room.size.y < 2:
			continue
		doc.fill_rect(room, floor_value)
		doc.rooms.append(room)

	if doc.rooms.size() < min_rooms:
		return DotResult.fail(
			DotError.CODE_STATE,
			"only %d rooms fitted, %d wanted" % [doc.rooms.size(), min_rooms],
			"the map is too small for this leaf size, or the seed was unlucky"
		)
	return DotResult.success(null)


func _split(area: Rect2i, stream: DotProcGenRandom, out: Array[Rect2i], depth: int) -> void:
	# A depth cap as well as a size one. The size test alone is enough in theory and a
	# recursion that cannot terminate is a frozen game rather than a bad map, so both.
	if depth > 12 or (area.size.x < min_leaf * 2 and area.size.y < min_leaf * 2):
		out.append(area)
		return

	var horizontal := area.size.x >= area.size.y
	if area.size.x < min_leaf * 2:
		horizontal = false
	elif area.size.y < min_leaf * 2:
		horizontal = true

	var extent := area.size.x if horizontal else area.size.y
	var lo := int(float(extent) * (0.5 - split_jitter))
	var hi := int(float(extent) * (0.5 + split_jitter))
	var cut := clampi(stream.range_i(lo, hi), min_leaf, extent - min_leaf)

	if horizontal:
		_split(Rect2i(area.position, Vector2i(cut, area.size.y)), stream, out, depth + 1)
		_split(
			Rect2i(area.position + Vector2i(cut, 0), Vector2i(area.size.x - cut, area.size.y)),
			stream, out, depth + 1
		)
	else:
		_split(Rect2i(area.position, Vector2i(area.size.x, cut)), stream, out, depth + 1)
		_split(
			Rect2i(area.position + Vector2i(0, cut), Vector2i(area.size.x, area.size.y - cut)),
			stream, out, depth + 1
		)


func _room_in(leaf: Rect2i, stream: DotProcGenRandom) -> Rect2i:
	var shrink_x := int(float(leaf.size.x) * stream.range_f(0.0, margin))
	var shrink_y := int(float(leaf.size.y) * stream.range_f(0.0, margin))
	# At least one cell of wall on every side, always. A room flush against the leaf edge
	# meets its neighbour with no wall between them, and the result is one enormous room
	# that looks like the partition failing rather than like a missing +1.
	var pos := leaf.position + Vector2i(1 + shrink_x / 2, 1 + shrink_y / 2)
	var size := leaf.size - Vector2i(2 + shrink_x, 2 + shrink_y)
	return Rect2i(pos, Vector2i(maxi(size.x, 0), maxi(size.y, 0)))
