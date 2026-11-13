import eyg/embed/browser
import gleam/bit_array
import gleam/javascript/promise
import midas/effect

pub fn sha256_is_computed_by_the_platform_test() {
  use hashed <- promise.map(browser.hash(effect.Sha256, <<"abc":utf8>>)(
    promise.resolve,
  ))
  assert bit_array.base16_encode(hashed)
    == "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
}

pub fn a_slice_of_a_bit_array_is_hashed_on_its_own_test() {
  let assert Ok(slice) = bit_array.slice(<<"xabcx":utf8>>, 1, 3)
  use hashed <- promise.map(browser.hash(effect.Sha256, slice)(promise.resolve))
  assert bit_array.base16_encode(hashed)
    == "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
}
