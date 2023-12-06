import gleam/string
import datalog/datalog.{Constant as C, fresh, not, return, return2, transform}
import gleeunit/should

// datalog match or
// single context to next

pub fn return_constant_value_test() {
  let q = return(C("hello"))
  datalog.run(q)
  |> should.equal(Ok(["hello"]))
}

pub fn return_multiple_values_test() {
  let q = return2(C("hello"), C(8))
  datalog.run(q)
  |> should.equal(Ok([#("hello", 8)]))
}

pub fn return_variable_error_test() {
  let q = {
    use x <- fresh()
    return(x)
  }
  datalog.run(q)
  |> should.equal(Error(Nil))
}

pub fn bind_test() -> Nil {
  let edge = datalog.facts2([#("a", "b"), #("c", "d")])
  let q = {
    use x <- fresh()
    use <- edge(C("a"), x)
    return(x)
  }
  datalog.run(q)
  |> should.equal(Ok(["b"]))
}

pub fn reused_bind_test() -> Nil {
  let edge = datalog.facts2([#("a", "b"), #("c", "c")])
  let q = {
    use x <- fresh()
    use <- edge(x, x)
    return(x)
  }
  datalog.run(q)
  |> should.equal(Ok(["c"]))
}

pub fn joined_bind_test() -> Nil {
  let edge = datalog.facts2([#("a", "b"), #("c", "d")])
  let q = {
    use x <- fresh()
    use i1 <- fresh()
    use i2 <- fresh()
    use y <- fresh()
    use <- edge(x, i1)
    use <- edge(i2, y)
    return2(x, y)
  }
  datalog.run(q)
  |> should.equal(Ok([#("a", "b"), #("a", "d"), #("c", "b"), #("c", "d")]))
}

fn edge(x, y, k) {
  datalog.facts2([#("a", "b"), #("b", "c"), #("c", "d")])(x, y, k)
}

fn two_step(from, too, k) {
  use via <- fresh()
  use <- edge(from, via)
  use <- edge(via, too)
  k()
}

pub fn create_rule_test() {
  // any pair separated by two steps
  let q = {
    use x <- fresh()
    use y <- fresh()
    use <- two_step(x, y)
    return2(x, y)
  }

  datalog.run(q)
  |> should.equal(Ok([#("a", "c"), #("b", "d")]))

  // any point two steps from a
  let q = {
    use y <- fresh()
    use <- two_step(C("a"), y)
    return(y)
  }

  datalog.run(q)
  |> should.equal(Ok(["c"]))
}

pub fn not_binding_test() -> Nil {
  // let edge = datalog.facts2([#("a", "b"), #("c", "d")])

  let q = {
    use x <- fresh()
    use y <- fresh()
    use <- edge(x, y)
    use <- not(edge(C("a"), y, _))
    return(x)
  }

  datalog.run(q)
  |> should.equal(Ok(["b", "c"]))
}

pub fn transformation_test() {
  let q = {
    use y <- fresh()
    use <- edge(C("a"), y)
    use y2 <- transform(y, string.uppercase)
    return(y2)
  }

  datalog.run(q)
  |> should.equal(Ok(["B"]))
}
//   let r = run(q)
//   io.debug(r)
//   //       use  <- predicate({
//   //       use x <- value(to)
//   //       use y <- value(from)
//   //       x + y  == 1
//   //     })

//   //     use<- value(to, fn(x) {value(fn(y) {
//   //       case x > y {
//   // True -> yield()
//   //       }
//   //     })})
//   // let q = {
//   //   use movie_id <- fresh()
//   //   use actor_name <- fresh()

//   //   use <- cast(movie_id, actor_name)
//   //   use loud <- map(actor_name, string.uppercase)
//   //   use <- equal(b(True), mapped())
//   //   find2(movie_title, director_name)
//   // }
//   //   always pass in fns so don't need use
// }
// // pass in db or facts in db or run?
// // db1/2 is possible
// fn foo() {
//   let q = {
//     use <- edge("x", "y")
//     fn(x) { x }
//   }
// }

// fn cast(movie_id, actor_name, k) {
//   use actor_id <- fresh()
//   use <- db(actor_id, "", actor_name)
//   use <- db(movie_id, "", actor_id)
//   k()
// }

// fn directed_by(movie_id, director_name, k) {
//   use actor_id <- fresh()
//   use <- db(actor_id, "", director_name)
//   use <- db(movie_id, "", actor_id)
//   k()
// }

// pub fn datalog_test() {
//   let q = {
//     use movie_id <- fresh()
//     use actor_name <- fresh()

//     use <- cast(movie_id, actor_name)
//     use loud <- map(actor_name, string.uppercase)
//     use <- equal(b(True), mapped())
//     find2(movie_title, director_name)
//   }
//   //   always pass in fns so don't need use
// }
