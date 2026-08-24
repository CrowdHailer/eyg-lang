import eyg/ir/car
import eyg/ir/helpers
import simplifile

// const v1_car = "test/fixtures/car/carv1-basic.car"

// CID decoding doesn't support v0
// pub fn decode_carv1_test() -> car.Car {
//   let assert Ok(bytes) = simplifile.read_bits(v1_car)
//   let assert Ok(archive) = car.decode(bytes)
//   archive
// }

pub fn decode_hello_test() {
  let assert Ok(bytes) =
    simplifile.read_bits("test/fixtures/car/hello_world.car")
  let assert Ok(archive) = car.decode(bytes)
  let expected = helpers.cid_from_block(<<"\"hello world\"">>)
  assert [expected] == archive.header.roots
  assert [#(expected, <<"\"hello world\"">>)] == archive.blocks

  assert Ok(bytes) == car.encode(archive)
}
