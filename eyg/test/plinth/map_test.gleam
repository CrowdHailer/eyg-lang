import plinth/javascript/map
import gleeunit/should

pub fn map_size_test() {
  let m = map.new()
  should.equal(map.size(m), 0)

  map.set(m, "a", 1)
  should.equal(map.size(m), 1)

  map.set(m, "b", 1)
  should.equal(map.size(m), 2)

  map.set(m, "b", 10)
  should.equal(map.size(m), 2)
}

pub fn map_retrieve_test() {
  let m = map.new()
  should.equal(map.get(m, "a"), Error(Nil))

  map.set(m, "a", 1)
  should.equal(map.get(m, "a"), Ok(1))

  map.set(m, "a", 2)
  should.equal(map.get(m, "a"), Ok(2))
}
