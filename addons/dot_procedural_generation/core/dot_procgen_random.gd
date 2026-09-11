class_name DotProcGenRandom
extends RefCounted

## A counter-based, splittable random stream. Deliberately a second implementation.
##
## [b]dot-randomness has this class and this addon does not use it.[/b] That is the
## family's rule — only dot-core may be a hard dependency — and it is the same decision
## dot-browser made when it wrote a second implementation of dot-server's wire format
## rather than depending on it.
##
## What this addon takes from a game's dot-randomness, when there is one, is the **seed**:
## [member DotProcGenPipeline.seed_source] asks any object with [code]seed_for(name)[/code]
## for a number, so a generated world comes out of the session's own seed rather than out
## of one of its own. The numbers a generator draws from that seed are its own business,
## and nothing anywhere compares them with dot-randomness'.
##
## The design is the important half and it is shared on purpose:
##
## - A draw is a pure function of (key, index), so [method at] answers for an index nobody
##   has reached and a second machine reproduces any of it without having taken the same
##   path there.
## - [method stream] derives a child by hashing a name, so two steps never disturb each
##   other — which is what lets a step be added to a pipeline without changing the map the
##   steps before it produced.

const _GAMMA := -7046029254386353131  # 0x9E3779B97F4A7C15
const _MIX_A := -4658895280553007687  # 0xBF58476D1CE4E5B9
const _MIX_B := -7723592293110705685  # 0x94D049BB133111EB

## 53 bits, which is every bit a float64 mantissa can hold. Taking fewer is a range that
## does not reach its top -- dot-combat's spread shipped with 23 where it wanted 24 and
## every pattern was a half-moon.
const _UNIT_SCALE := 1.0 / 9007199254740992.0

var _key: int = 0
var _counter: int = 0


func _init(p_seed: int = 0, p_name: StringName = &"") -> void:
	_key = _mix(p_seed ^ _hash_name(p_name))


func stream(name: StringName) -> DotProcGenRandom:
	var child := DotProcGenRandom.new()
	child._key = _mix(_key ^ _hash_name(name) ^ _GAMMA)
	return child


func at(index: int) -> int:
	return _mix(_key ^ _mix(index + _GAMMA))


func unit_at(index: int) -> float:
	return float(_unsigned_shift(at(index), 11)) * _UNIT_SCALE


func next() -> int:
	var v := at(_counter)
	_counter += 1
	return v


func unit() -> float:
	var v := unit_at(_counter)
	_counter += 1
	return v


## An integer in [code][lo, hi][/code], inclusive.
##
## Scaled from the float rather than taken modulo the raw value: `x % span` on a signed
## 64-bit int is negative for half of every mixer's output, so the obvious spelling
## silently returns values below `lo` about half the time.
func range_i(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + int(unit() * float(hi - lo + 1)) % (hi - lo + 1)


func range_f(lo: float, hi: float) -> float:
	return lo + unit() * (hi - lo)


func chance(p: float) -> bool:
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	return unit() < p


## A shuffled copy. Fisher-Yates downward, which is the only uniform version.
func shuffled(items: Array) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := range_i(0, i)
		var tmp: Variant = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[range_i(0, items.size() - 1)]


func counter() -> int:
	return _counter


static func _mix(x: int) -> int:
	var z := x + _GAMMA
	z = (z ^ _unsigned_shift(z, 30)) * _MIX_A
	z = (z ^ _unsigned_shift(z, 27)) * _MIX_B
	return z ^ _unsigned_shift(z, 31)


## Logical right shift. GDScript's `>>` is arithmetic on a signed 64-bit int, so shifting
## a negative value keeps the sign bits and the top of the mixer's output becomes a run of
## ones rather than entropy -- for half of every value it produces.
static func _unsigned_shift(value: int, bits: int) -> int:
	if bits <= 0:
		return value
	if bits >= 64:
		return 0
	return (value >> bits) & ((1 << (64 - bits)) - 1)


static func _hash_name(name: StringName) -> int:
	var s := String(name)
	if s.is_empty():
		return 0
	# FNV-1a rather than String.hash(), which is 32-bit and is not promised to be stable
	# across engine versions -- and a seed that means a different world after an upgrade
	# was never shareable.
	var h := -3750763034362895579  # 0xCBF29CE484222325
	for b in s.to_utf8_buffer():
		h = (h ^ b) * 1099511628211
	return h
