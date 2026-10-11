class_name DotProcGenRandom
extends RefCounted

## A counter-based, splittable random stream: this addon's names over dot-core's
## [DotRandomStream], which draws every number.
##
## [b]A wrapper, not a second implementation, and it used to be one.[/b] It was written
## when the family's random stream lived in a separate addon (dot-randomness) that this one
## could not depend on, so it carried its own copy of the same SplitMix64 mixer. That
## addon folded into dot-core, which every addon may depend on, and two copies of one
## algorithm are two chances for them to drift. The names here ([method unit],
## [method range_i], [method shuffled]) are kept because every generator step calls them.
##
## What a game's seed source gives this addon is still only the [b]seed[/b]:
## [member DotProcGenPipeline.seed_source] asks any object with [code]seed_for(name)[/code]
## for a number, so a generated world comes out of the session's own seed.
##
## The design is the important half:
##
## - A draw is a pure function of (key, index), so [method at] answers for an index nobody
##   has reached and a second machine reproduces any of it without having taken the same
##   path there.
## - [method stream] derives a child by hashing a name, so two steps never disturb each
##   other, which is what lets a step be added to a pipeline without changing the map the
##   steps before it produced.

var _s: DotRandomStream


func _init(p_seed: int = 0, p_name: StringName = &"") -> void:
	_s = DotRandomStream.new(p_seed, p_name)


static func _wrap(inner: DotRandomStream) -> DotProcGenRandom:
	var out := DotProcGenRandom.new()
	out._s = inner
	return out


func stream(name: StringName) -> DotProcGenRandom:
	return _wrap(_s.stream(name))


## The stream underneath, for a step that wants dot-core's wider vocabulary
## ([method DotRandomStream.next_gaussian], [method DotRandomStream.next_weighted]).
func core() -> DotRandomStream:
	return _s


func at(index: int) -> int:
	return _s.at(index)


func unit_at(index: int) -> float:
	return _s.unit_at(index)


func next() -> int:
	return _s.next()


func unit() -> float:
	return _s.next_unit()


## An integer in [code][lo, hi][/code], inclusive.
func range_i(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return _s.next_range_i(lo, hi)


func range_f(lo: float, hi: float) -> float:
	return _s.next_range_f(lo, hi)


func chance(p: float) -> bool:
	return _s.next_chance(p)


## A shuffled copy. Fisher-Yates downward, which is the only uniform version.
func shuffled(items: Array) -> Array:
	return _s.next_shuffled(items)


func pick(items: Array) -> Variant:
	return _s.next_pick(items)


func counter() -> int:
	return _s.counter()


## dot-core's mixer, under the name the pipeline's retry seeding has always called. Kept so
## a retry's seed (mix(root ^ mix(attempt))) is exactly what it was.
static func _mix(x: int) -> int:
	return DotRandomStream._mix(x)
