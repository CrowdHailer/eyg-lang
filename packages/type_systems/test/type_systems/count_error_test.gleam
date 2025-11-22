import type_systems/counter_result.{bind, fresh, ok, stop}

pub fn example_test() {
  let out =
    {
      use x <- fresh()
      echo x
      use y <- fresh()
      echo y
      use z <- bind(case y > 0 {
        True -> {
          use z <- fresh()
          ok(#(z, "yo"))
        }
        False -> stop("out")
      })
      echo z
      use a <- fresh()
      echo a
      ok("hi")
    }(0)
  echo out
}
