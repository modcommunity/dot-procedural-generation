extends Node

## Exercises dot-procedural-generation with no scene tree and no builder.
##
## [b]The checks that matter are the ones about a map being finishable[/b], because every
## other kind passes for a map nobody can complete. This family has that lesson from the
## other direction: eight imported maps passed 168 assertions about their zones while five
## of them could not be finished, since every assertion was about a zone existing and none
## was about the zones adding up to a run.
##
## [codeblock]
## godot --headless --path . res://examples/procgen_selftest.tscn
## [/codeblock]

const SECTIONS := 8
const CHECKS := 61

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	await _run()


func _run() -> void:
	_line("dot-procedural-generation self-test")
	_line("")

	_test_document()
	_test_random()
	_test_rooms()
	_test_connectivity()
	_test_validation_refuses()
	_test_determinism_and_fingerprint()
	_test_retries()
	await _test_sliced_runner()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


func _dungeon(w: int = 48, h: int = 48) -> DotProcGenPipeline:
	var p := DotProcGenPipeline.new()
	p.width = w
	p.height = h
	p.pipeline_name = &"test_dungeon"

	var rooms := DotProcGenRooms.new()
	rooms.step_name = &"rooms"
	rooms.min_leaf = 10
	rooms.min_rooms = 4
	p.add(rooms)

	var connect := DotProcGenConnect.new()
	connect.step_name = &"corridors"
	connect.extra_loops = 2
	p.add(connect)

	var spawn := DotProcGenMarkers.new()
	spawn.step_name = &"spawn"
	spawn.kind = &"spawn"
	spawn.placement = DotProcGenMarkers.Placement.ROOM_CENTRE
	spawn.count = 1
	p.add(spawn)

	var exit_marker := DotProcGenMarkers.new()
	exit_marker.step_name = &"exit"
	exit_marker.kind = &"exit"
	exit_marker.placement = DotProcGenMarkers.Placement.FURTHEST_ROOM
	p.add(exit_marker)

	var check := DotProcGenValidate.new()
	check.step_name = &"reachable"
	check.from_kind = &"spawn"
	p.add(check)

	return p


# --- 1 ----------------------------------------------------------------------

func _test_document() -> void:
	_section("A document, which is what a generator produces")

	var d := DotProcGenDoc.new()
	d.resize(8, 6)
	_check(d.width == 8 and d.height == 6, "it has a size")
	_check(d.cells.size() == 48, "and exactly that many cells")
	_check(d.count_of(DotProcGenDoc.SOLID) == 48, "starting solid")

	d.set_at(3, 3, DotProcGenDoc.FLOOR)
	_check(d.at(3, 3) == DotProcGenDoc.FLOOR, "a cell can be written and read")
	_check(
		d.at(-1, 3) == DotProcGenDoc.SOLID and d.at(99, 3) == DotProcGenDoc.SOLID,
		"and out of bounds is solid rather than an error, so no step needs a bounds check"
	)

	# Rect2i(1, 1, 3, 3) covers x and y in [1, 4), so it contains the cell written above
	# rather than adding to it. Getting that wrong by one is the commonest arithmetic
	# mistake in grid code and is why the count is asserted rather than the corners.
	d.fill_rect(Rect2i(1, 1, 3, 3), DotProcGenDoc.FLOOR)
	_check(d.count_of(DotProcGenDoc.FLOOR) == 9, "a rectangle fills, end-exclusive")
	_check(d.at(4, 4) == DotProcGenDoc.SOLID, "and does not reach its end corner")

	d.add_marker(&"spawn", Vector2i(2, 2))
	d.add_marker(&"chest", Vector2i(3, 3))
	_check(d.markers_of(&"spawn").size() == 1, "markers are found by kind")
	_check(d.markers.size() == 2, "and all of them are kept")

	var reach := d.reachable_from(Vector2i(2, 2))
	_check(reach.size() == 9, "a flood finds the nine cells of the room")
	_check(
		d.reachable_from(Vector2i(0, 0)).is_empty(),
		"and flooding from inside a wall finds nothing, rather than erroring"
	)

	var ascii := d.to_ascii()
	_check(ascii.size() == 6, "it draws itself, which is how a generator bug is actually seen")
	_check(ascii[1].begins_with("#..."), "with the map in it")


# --- 2 ----------------------------------------------------------------------

func _test_random() -> void:
	_section("A second implementation of the stream, on purpose")

	var a := DotProcGenRandom.new(1234, &"world")
	var b := DotProcGenRandom.new(1234, &"world")
	var agreed := true
	for _i in range(200):
		if a.next() != b.next():
			agreed = false
	_check(agreed, "one seed and one name is one stream")

	var root := DotProcGenRandom.new(99, &"root")
	var rooms := root.stream(&"rooms")
	var props := root.stream(&"props")
	var expected: Array[float] = []
	for _i in range(4):
		expected.append(rooms.unit())

	# The property that makes a pipeline editable: a step added later cannot change the
	# numbers a step before it drew.
	var root2 := DotProcGenRandom.new(99, &"root")
	var props2 := root2.stream(&"props")
	for _i in range(500):
		props2.unit()
	var rooms2 := root2.stream(&"rooms")
	var same := true
	for i in range(4):
		if not is_equal_approx(rooms2.unit(), expected[i]):
			same = false
	_check(same, "500 draws from another step's stream leave this one exactly where it was")
	_check(props.at(0) != rooms.at(0), "and two steps are not each other")

	# The half-range bug this family shipped once: a maximum-magnitude check passes for a
	# hash that only ever returns the bottom half.
	var above := 0
	var lo := 1.0
	var hi := 0.0
	for i in range(8000):
		var u := a.unit_at(i)
		lo = minf(lo, u)
		hi = maxf(hi, u)
		if u >= 0.5:
			above += 1
	_check(lo >= 0.0 and hi < 1.0, "unit stays inside [0, 1)")
	_check(absf(float(above) / 8000.0 - 0.5) < 0.03, "and reaches the top half of it")

	var counts := {}
	for _i in range(3000):
		var v := a.range_i(2, 5)
		counts[v] = int(counts.get(v, 0)) + 1
	_check(counts.size() == 4, "range_i covers an inclusive range")
	_check(not counts.has(1) and not counts.has(6), "and never leaves it")


# --- 3 ----------------------------------------------------------------------

func _test_rooms() -> void:
	_section("Rooms, with walls between them")

	var res := _dungeon().generate(7)
	_check(res.ok, "a dungeon generates")
	var doc := res.value as DotProcGenDoc
	_check(doc.rooms.size() >= 4, "with at least the rooms it asked for (%d)" % doc.rooms.size())

	# A room flush against its leaf's edge meets its neighbour with no wall between them,
	# and the result is one enormous room that reads as the partition failing.
	var touching := 0
	for i in range(doc.rooms.size()):
		for j in range(i + 1, doc.rooms.size()):
			if doc.rooms[i].intersects(doc.rooms[j]):
				touching += 1
	_check(touching == 0, "and no two rooms overlap")

	var edge_clear := true
	for x in range(doc.width):
		if doc.is_walkable(x, 0) or doc.is_walkable(x, doc.height - 1):
			edge_clear = false
	for y in range(doc.height):
		if doc.is_walkable(0, y) or doc.is_walkable(doc.width - 1, y):
			edge_clear = false
	_check(
		edge_clear,
		"and nothing reaches the border, which on an extruded map is a hole in the world"
	)

	var tiny := _dungeon(12, 12)
	var tiny_res := tiny.generate(1)
	_check(
		not tiny_res.ok,
		"a map too small for the rooms asked for fails honestly rather than producing one room"
	)


# --- 4 ----------------------------------------------------------------------

func _test_connectivity() -> void:
	_section("Every room reachable, and loops on purpose")

	var res := _dungeon().generate(11)
	_check(res.ok, "it generates")
	var doc := res.value as DotProcGenDoc

	var spawn: Vector2i = doc.markers_of(&"spawn")[0]["cell"]
	var reached := doc.reachable_from(spawn)
	var reachable := {}
	for idx in reached:
		reachable[idx] = true

	var unreachable_rooms := 0
	for r in doc.rooms:
		var centre := r.position + r.size / 2
		if not reachable.has(centre.y * doc.width + centre.x):
			unreachable_rooms += 1
	_check(unreachable_rooms == 0, "every room can be walked to from the spawn")

	# A spanning tree is a bad level: one route between any two rooms, so every fight is a
	# corridor and every retreat is the way you came.
	_check(
		doc.links.size() > doc.rooms.size() - 1,
		"and there are more corridors than a spanning tree, so the map has loops in it (%d for %d rooms)"
		% [doc.links.size(), doc.rooms.size()]
	)

	var exits := doc.markers_of(&"exit")
	_check(exits.size() == 1, "the exit was placed")
	var exit_cell: Vector2i = exits[0]["cell"]
	_check(
		reachable.has(exit_cell.y * doc.width + exit_cell.x),
		"and can be reached, which is the only check that says the map is finishable"
	)


# --- 5 ----------------------------------------------------------------------

func _test_validation_refuses() -> void:
	_section("A map that cannot be finished is refused")

	# Hand-built rather than generated, because the whole point is to produce the case a
	# generator produces about one seed in thirty and prove it is caught.
	var doc := DotProcGenDoc.new()
	doc.resize(20, 10)
	doc.fill_rect(Rect2i(1, 1, 6, 6), DotProcGenDoc.FLOOR)
	doc.fill_rect(Rect2i(12, 1, 6, 6), DotProcGenDoc.FLOOR)
	doc.add_marker(&"spawn", Vector2i(3, 3))
	doc.add_marker(&"exit", Vector2i(14, 3))

	var check := DotProcGenValidate.new()
	check.from_kind = &"spawn"
	check.min_connected_fraction = 0.0
	check.fill_unreachable = false
	var res := check.apply(doc, DotProcGenRandom.new())
	_check(not res.ok, "an exit sealed off from the spawn is refused")
	_check(res.error.message.contains("exit"), "naming what could not be reached")

	# The subtler half: connected, and mostly wasted. One thread of corridor to a far wing
	# satisfies "everything is reachable" while nine tenths of the map is a sealed pocket.
	var mostly := DotProcGenDoc.new()
	mostly.resize(30, 30)
	mostly.fill_rect(Rect2i(1, 1, 4, 4), DotProcGenDoc.FLOOR)
	mostly.fill_rect(Rect2i(10, 10, 18, 18), DotProcGenDoc.FLOOR)
	mostly.add_marker(&"spawn", Vector2i(2, 2))
	var strict := DotProcGenValidate.new()
	strict.from_kind = &"spawn"
	strict.min_connected_fraction = 0.6
	strict.fill_unreachable = false
	_check(
		not strict.apply(mostly, DotProcGenRandom.new()).ok,
		"and so is a map that is connected and nine tenths wasted"
	)

	# Filling in is usually better than failing: a cave with its sealed pockets filled is
	# a good cave, and the same cave with them left in has rooms that exist for a
	# navigation mesh and not for a player.
	var filler := DotProcGenValidate.new()
	filler.from_kind = &"spawn"
	filler.min_connected_fraction = 0.0
	filler.fill_unreachable = true
	var before := mostly.count_of(DotProcGenDoc.FLOOR)
	_check(filler.apply(mostly, DotProcGenRandom.new()).ok, "with filling on, it passes")
	_check(mostly.count_of(DotProcGenDoc.FLOOR) < before, "and the unreachable part is gone")
	_check(int(mostly.meta.get("unreachable_filled", 0)) > 0, "and it says how much it filled")

	var no_start := DotProcGenDoc.new()
	no_start.resize(10, 10)
	_check(
		not check.apply(no_start, DotProcGenRandom.new()).ok,
		"a validate step with nothing to flood from says so rather than passing"
	)

	var buried := DotProcGenDoc.new()
	buried.resize(10, 10)
	buried.add_marker(&"spawn", Vector2i(5, 5))
	var res_buried := check.apply(buried, DotProcGenRandom.new())
	_check(not res_buried.ok, "and a spawn inside a wall is refused")
	_check(res_buried.error.message.contains("wall"), "by name")


# --- 6 ----------------------------------------------------------------------

func _test_determinism_and_fingerprint() -> void:
	_section("Two peers compare a hash, not a map")

	var a := _dungeon().generate(4242)
	var b := _dungeon().generate(4242)
	_check(a.ok and b.ok, "two runs of one seed both succeed")
	var doc_a := a.value as DotProcGenDoc
	var doc_b := b.value as DotProcGenDoc
	_check(doc_a.cells == doc_b.cells, "and produce byte-identical maps")
	_check(doc_a.fingerprint() == doc_b.fingerprint(), "so the fingerprints agree")

	var c := _dungeon().generate(4243)
	_check(
		(c.value as DotProcGenDoc).fingerprint() != doc_a.fingerprint(),
		"a different seed is a different map"
	)

	var p1 := _dungeon()
	var p2 := _dungeon()
	_check(p1.fingerprint() == p2.fingerprint(), "two identical pipelines agree")

	# The case this is actually for: one peer running a pipeline that has been edited.
	p2.steps[1].set("extra_loops", 9)
	_check(
		p1.fingerprint() != p2.fingerprint(),
		"and a step's own setting changing changes it, which is what catches an edited pipeline"
	)

	var p3 := _dungeon()
	p3.steps[1].enabled = false
	_check(
		p1.fingerprint() != p3.fingerprint(),
		"as does disabling a step, because that is a different pipeline"
	)

	_check(doc_a.meta.has("seed"), "the document says which seed it came from")
	_check(
		int(doc_a.meta["seed"]) == 4242,
		"which is the first question anybody asks about a generated world"
	)


# --- 7 ----------------------------------------------------------------------

func _test_retries() -> void:
	_section("An unlucky seed is retried, not shipped")

	var p := _dungeon(14, 14)
	p.max_attempts = 1
	var one := p.generate(3)
	_check(not one.ok, "with one attempt, a map too small to satisfy the rooms step fails")

	var q := _dungeon(48, 48)
	q.max_attempts = 10
	var many := q.generate(3)
	_check(many.ok, "and a workable pipeline succeeds")

	# Mixed rather than added. seed+1 is somebody else's world, so a failure on seed 41
	# would quietly hand a player the map seed 42 should have produced -- and two people
	# comparing notes would disagree about what seed 41 looks like.
	var direct := _dungeon(48, 48).generate(4)
	var doc_many := many.value as DotProcGenDoc
	_check(
		doc_many.fingerprint() != (direct.value as DotProcGenDoc).fingerprint(),
		"and a retry is not simply the next seed's map"
	)

	var empty := DotProcGenPipeline.new()
	_check(not empty.validate().ok, "a pipeline with no steps is refused")

	var clash := _dungeon()
	clash.steps[1].step_name = &"rooms"
	_check(
		not clash.validate().ok,
		"and two steps with one name, because a step's name is its random stream"
	)


# --- 8 ----------------------------------------------------------------------

func _test_sliced_runner() -> void:
	_section("Generated across frames, on the main thread")

	var runner := DotProcGenRunner.new()
	runner.pipeline = _dungeon()
	runner.frame_budget_ms = 1
	add_child(runner)

	var done := []
	runner.finished.connect(func(doc: DotProcGenDoc, res: DotResult) -> void:
		done.append([doc, res])
	)
	var steps_seen := []
	runner.step_started.connect(func(name: StringName, _i: int, _t: int) -> void:
		steps_seen.append(name)
	)

	_check(runner.begin(8080).ok, "a sliced run starts")
	_check(runner.running(), "and is running")

	var guard := 0
	while runner.running() and guard < 600:
		await get_tree().process_frame
		guard += 1

	_check(not runner.running(), "and finishes")
	_check(done.size() == 1, "announcing itself exactly once")
	_check(done[0][1].ok, "with a document")
	_check(steps_seen.size() >= 5, "having announced each step, which a progress bar needs")

	# The whole point of slicing between steps rather than inside one: a half-built
	# document is data that is not finished, and a half-built world is one a player can
	# walk into.
	var sliced := done[0][0] as DotProcGenDoc
	var blocking := DotProcGenRunner.new()
	blocking.pipeline = _dungeon()
	add_child(blocking)
	var straight := blocking.generate_now(8080)
	_check(straight.ok, "and generating in one go works too")
	_check(
		(straight.value as DotProcGenDoc).fingerprint() == sliced.fingerprint(),
		"producing exactly the same map, which is what makes slicing an implementation detail"
	)

	runner.queue_free()
	blocking.queue_free()


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
