import gleam/io
import deli/ctl
import deli/mon.{bind, perform, pure}

pub fn main() {
  mon.run({
    use a <- bind(pure(5))
    use b <- bind(perform("read", 0))
    use _ <- bind(perform("log", a))
    use c <- bind(perform("read", 2))

    pure(a + b + c)
  })
  |> io.debug

  mon.run({ bind(pure(5), j1) })
  |> io.debug
  io.println("Hello from deli!")
}

fn j1(a) {
  // saturated and doesn't escape but not a tail
  bind(perform("read", 0), fn(x) { j2(a, x) })
}

fn j1a(a, w) {
  case perform("read", 0)(w) {
    mon.Pure(x) -> j2(a, x)(w)
    mon.Yield(m, op, cont) -> mon.Yield(m, op, fn(x) { bind(j2(a, x), cont) })
  }
}

fn j2(a, b) {
  bind(perform("log", a), fn(_) { j3(a, b) })
}

fn j3(a, b) {
  bind(perform("read", 2), fn(c) { j4(a, b, c) })
}

fn j4(a, b, c) {
  pure(a + b + c)
}
