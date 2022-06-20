import firmata/firmata

pub fn debug_test() {
  let #(state, received) = firmata.fresh()
  firmata.parse(<<>>, state, received)
  todo("the firmata test")
}

pub fn bad_bitstring_test() {
  let <<_:1, _:1, a:1, b:1, c:1, d:1, e:1, f:1>> = <<0>>
}
