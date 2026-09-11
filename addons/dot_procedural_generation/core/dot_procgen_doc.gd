class_name DotProcGenDoc
extends RefCounted

## What a generator produces: a document, not a world.
##
## [b]This is the whole architecture in one sentence, and it is the same sentence as
## dot-loadout's and dot-user-avatar's.[/b] Generation produces data; a builder turns data
## into nodes. Four things fall out of that and none of them is available to a generator
## that instantiates as it goes:
##
## [b]A server and a client can agree.[/b] Two machines with one seed produce two
## identical documents, and the only thing that has to travel is the seed and a hash. A
## generator that builds nodes can only be compared by looking at the nodes.
##
## [b]A suite can assert on it.[/b] "Every room is reachable from the spawn", "there are
## between four and nine rooms", "no corridor is one tile wide at a door" are all
## questions about a document. Against a scene tree they are questions about a scene tree.
##
## [b]2D and 3D share it.[/b] The grid is a grid. A top-down game reads it as tiles and a
## first-person game extrudes it into walls, with one generator and no second code path —
## the same trick dot-npc uses when it maps a 2D world onto the XZ plane.
##
## [b]It can be generated over several frames.[/b] A half-built document is data that is
## not finished; a half-built world is a world a player can walk into.

## The four-way neighbourhood, typed.
##
## An untyped array literal iterated with `for d in [...]` gives a Variant, and `x + d.x`
## is then a Variant too -- which is a parse ERROR under these projects' settings rather
## than a warning, and the message names the variable rather than the literal that caused
## it.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

## What a cell is. A game may use the free values for its own.
const SOLID := 0
const FLOOR := 1
const DOOR := 2
const WATER := 3
const HAZARD := 4

var width: int = 0
var height: int = 0

## Row-major, `width * height` bytes.
##
## A [PackedByteArray] rather than a 2D [Array]: one allocation instead of `height` of
## them, it hashes directly, and it is the only shape that can be compared between two
## machines cheaply.
var cells: PackedByteArray = PackedByteArray()

## Rooms, as grid rectangles. Empty for a generator that does not think in rooms.
var rooms: Array[Rect2i] = []

## Pairs of room indices that were deliberately joined. The graph, before it is drawn.
var links: Array[Vector2i] = []

## Where things go. Each is [code]{"kind": StringName, "cell": Vector2i, ...}[/code].
##
## Deliberately untyped beyond that: a spawn point, a chest, a monster nest and a light
## are all "a kind and a place", and a document that had a class per kind would need
## changing every time a game invented one.
var markers: Array[Dictionary] = []

## Anything a step wants to tell a later step or the builder.
var meta: Dictionary = {}


func resize(w: int, h: int, fill: int = SOLID) -> void:
	width = maxi(0, w)
	height = maxi(0, h)
	cells = PackedByteArray()
	cells.resize(width * height)
	cells.fill(fill)
	rooms.clear()
	links.clear()
	markers.clear()


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		# Out of bounds is SOLID rather than an error. Every neighbour test in every step
		# would otherwise need a bounds check, and the one that is forgotten is a crash
		# at a map edge -- which is exactly where a generator spends most of its time.
		return SOLID
	return cells[y * width + x]


func set_at(x: int, y: int, value: int) -> void:
	if in_bounds(x, y):
		cells[y * width + x] = value


func at_v(cell: Vector2i) -> int:
	return at(cell.x, cell.y)


func set_v(cell: Vector2i, value: int) -> void:
	set_at(cell.x, cell.y, value)


func is_walkable(x: int, y: int) -> bool:
	var c := at(x, y)
	return c == FLOOR or c == DOOR or c == WATER


func fill_rect(r: Rect2i, value: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			set_at(x, y, value)


func count_of(value: int) -> int:
	var n := 0
	for c in cells:
		if c == value:
			n += 1
	return n


func add_marker(kind: StringName, cell: Vector2i, extra: Dictionary = {}) -> void:
	var m := {"kind": String(kind), "cell": cell}
	for k in extra.keys():
		m[k] = extra[k]
	markers.append(m)


func markers_of(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in markers:
		if str(m.get("kind", "")) == String(kind):
			out.append(m)
	return out


## Every walkable cell reachable from [param from], by four-way flood fill.
##
## The engine of [DotProcGenValidate], and useful on its own to a builder that wants to
## place something "somewhere a player can get to".
func reachable_from(from: Vector2i) -> PackedInt32Array:
	var seen := PackedByteArray()
	seen.resize(width * height)
	var out := PackedInt32Array()
	if not in_bounds(from.x, from.y) or not is_walkable(from.x, from.y):
		return out

	var queue := PackedInt32Array([from.y * width + from.x])
	seen[from.y * width + from.x] = 1
	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		out.append(idx)
		var x := idx % width
		var y := idx / width
		for d in NEIGHBOURS:
			var nx := x + d.x
			var ny := y + d.y
			if not in_bounds(nx, ny):
				continue
			var n := ny * width + nx
			if seen[n] == 1 or not is_walkable(nx, ny):
				continue
			seen[n] = 1
			queue.append(n)
	return out


func cell_of_index(index: int) -> Vector2i:
	return Vector2i(index % width, index / width)


## A stable fingerprint of the whole document.
##
## [b]What two peers compare instead of comparing maps.[/b] Same idea as dot-net's message
## schema hash, and it has to be built the same careful way: everything that goes in is
## ordered by construction, and nothing is sorted by [StringName]. Godot compares
## StringNames by their interned pointer, so a sort over them gives two peers two different
## orders — that bug gave two clients two different wire ids for one message type and was
## only visible once a real browser connected.
func fingerprint() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("%d:%d|" % [width, height]).to_utf8_buffer())
	# update() errors on empty input -- dot-cloud found that hashing an empty schema -- so
	# an empty grid contributes its header and nothing else.
	if not cells.is_empty():
		ctx.update(cells)
	var parts := PackedStringArray()
	for r in rooms:
		parts.append("r%d,%d,%d,%d" % [r.position.x, r.position.y, r.size.x, r.size.y])
	for l in links:
		parts.append("l%d,%d" % [l.x, l.y])
	for m in markers:
		var cell: Vector2i = m.get("cell", Vector2i.ZERO)
		parts.append("m%s,%d,%d" % [str(m.get("kind", "")), cell.x, cell.y])
	var joined := "|".join(parts)
	if not joined.is_empty():
		ctx.update(joined.to_utf8_buffer())
	return ctx.finish().hex_encode()


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("document %dx%d" % [width, height])
	out.append("  floor   %d of %d cells" % [count_of(FLOOR), cells.size()])
	out.append("  rooms   %d, links %d" % [rooms.size(), links.size()])
	var kinds := {}
	for m in markers:
		var k := str(m.get("kind", ""))
		kinds[k] = int(kinds.get(k, 0)) + 1
	for k in kinds.keys():
		out.append("  marker  %-16s %d" % [k, kinds[k]])
	out.append("  hash    %s" % fingerprint().substr(0, 16))
	return out


## The grid as text, for a bug report and for a person reading a failing test.
##
## [b]Worth more than it looks.[/b] Every generator bug this kind of code has is visible
## in ten lines of ASCII and invisible in every assertion that does not print one — which
## is the same lesson as this family's four screenshot-only bugs, one dimension down and
## free.
func to_ascii(max_width: int = 120) -> PackedStringArray:
	var out := PackedStringArray()
	var glyphs := {SOLID: "#", FLOOR: ".", DOOR: "+", WATER: "~", HAZARD: "!"}
	for y in range(height):
		var row := ""
		for x in range(mini(width, max_width)):
			row += str(glyphs.get(at(x, y), "?"))
		out.append(row)
	return out
