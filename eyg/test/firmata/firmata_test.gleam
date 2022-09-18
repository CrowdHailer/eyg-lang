import firmata/firmata

pub fn debug_test() {
  let #(state, received) = firmata.fresh()
  firmata.parse(<<>>, state, received)
}
