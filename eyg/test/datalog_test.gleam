import gleam/string
import datalog/datalog.{Constant as C, fresh, not, return, return2, transform}
import gleeunit/should

// rules facts/rules https://flix.dev/paper/oopsla2020a.pdf
// syntax section
// Fact vs Rule (Constraint)

// reuse rules, predicate/transform and type safety
// or and recursion

// a :- b(3)

// percival has a syntax explaining what is needed

// an ignore key is useful, IF not named fields
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
