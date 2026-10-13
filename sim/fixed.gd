class_name Fixed
extends RefCounted
## Fixed-point math for game numbers, and the simulation's only division (#33). The conventions:
##
## - Amounts (HP, strength, ring power, damage, pressure) are whole integers, at most MAX_AMOUNT
##   either way. Any two amounts can be multiplied: MAX_AMOUNT squared stays below 2^63.
## - Fractions (ratios, percentages, multipliers) are in thousandths: ONE is 100 % or times one,
##   250 a quarter, 1500 one and a half.
## - Every division rounds down, toward negative infinity, never toward zero, and goes through
##   these helpers. Multiply first, divide last (`mul_div`), so nothing is lost in between.

## A whole, in thousandths.
const ONE: int = 1000
## The largest amount a game number may reach, either way.
const MAX_AMOUNT: int = 1_000_000_000
## The lowest 64-bit integer, -2^63.
const LOWEST: int = -9_223_372_036_854_775_807 - 1


## `dividend` divided by `divisor`, rounded down. 0 (with an error) for a divisor of 0, and for
## the lowest integer divided by -1, whose result doesn't fit in 64 bits.
static func div_floor(dividend: int, divisor: int) -> int:
	if divisor == 0 or (divisor == -1 and dividend == LOWEST):
		push_error("Fixed.div_floor: %d / %d has no 64-bit result" % [dividend, divisor])
		return 0
	# The one place integer division is meant: the simulation has no floats to divide instead.
	@warning_ignore("integer_division")
	var quotient: int = dividend / divisor
	# GDScript's division rounds toward zero; a remainder with mixed signs needs one step down.
	if dividend % divisor != 0 and (dividend < 0) != (divisor < 0):
		quotient -= 1
	return quotient


## a × b / divisor, rounded down, without losing anything between the steps. `a` and `b` are at
## most MAX_AMOUNT either way; 0 (with an error) otherwise.
static func mul_div(a: int, b: int, divisor: int) -> int:
	# Compared directly rather than through absi(), which can't negate the lowest integer.
	if a < -MAX_AMOUNT or a > MAX_AMOUNT or b < -MAX_AMOUNT or b > MAX_AMOUNT:
		push_error("Fixed.mul_div: %d × %d is beyond the amounts the game uses" % [a, b])
		return 0
	return div_floor(a * b, divisor)


## `part` of `whole`, in thousandths: ratio(1, 4) is 250.
static func ratio(part: int, whole: int) -> int:
	return mul_div(part, ONE, whole)


## `amount` times `thousandths` / ONE: scale(10, 1500) is 15.
static func scale(amount: int, thousandths: int) -> int:
	return mul_div(amount, thousandths, ONE)
