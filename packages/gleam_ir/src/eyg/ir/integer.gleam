//// EYG integers are native machine integers, chosen for speed. On Erlang
//// they are arbitrary-precision bignums; on JavaScript they are IEEE-754
//// doubles, which only represent integers in the safe range exactly.
////
//// `is_safe` lets the places that ingest an integer from an external
//// representation (the parser, the DAG-JSON decoder, `int_parse`) reject a
//// value that the current target can't hold exactly, so out-of-range input
//// fails loudly instead of silently rounding.

/// True when the integer is exactly representable on the current target. On
/// Erlang every integer is exact, so this is always True (the body below). On
/// JavaScript only the safe-integer range (magnitude <= 2^53 - 1) is exact,
/// matching `Number.isSafeInteger` (the FFI below).
@external(javascript, "./integer_ffi.mjs", "isSafeInteger")
pub fn is_safe(_value: Int) -> Bool {
  True
}
