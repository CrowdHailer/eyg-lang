import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/int
import gleam/io
import gleam/list
import gleeunit
import gleeunit/should
import soundness
import soundness/generate_typed
import soundness/property

pub fn main() {
  gleeunit.main()
}

const fuel = 4000

/// Programs built from the type rules must run.
pub fn typed_search_test() {
  list.each([10, 20, 35], fn(size) {
    let summary =
      soundness.search_typed(
        from: 1,
        count: 1500,
        size: size,
        fuel: fuel,
        config: generate_typed.everything(),
      )
    io.println(
      "size " <> int.to_string(size) <> " " <> soundness.render(summary),
    )
    summary.counterexamples
    |> should.equal([])
  })
}

/// Programs built at random are nearly all rejected by the analysis, the few
/// that are accepted still have to run.
pub fn random_search_test() {
  let summary = soundness.search(from: 1, count: 2000, size: 12, fuel: fuel)
  summary.counterexamples
  |> should.equal([])
}

// --- programs that were once accepted and then failed

/// The fixed value has to be a function, the self reference always is one.
/// https://github.com/CrowdHailer/eyg-lang/issues/97
pub fn fix_of_non_function_test() {
  ir.apply(
    ir.builtin("fix"),
    ir.lambda(
      "x",
      ir.apply(ir.apply(ir.builtin("int_add"), ir.variable("x")), ir.integer(1)),
    ),
  )
  |> rejected
}

/// The constructor runs again on every recursive call, so an effect it
/// performs escapes the handler that was installed when fix was called.
pub fn fix_of_effectful_constructor_test() {
  let loop =
    ir.lambda(
      "n",
      ir.apply(
        ir.apply(
          ir.apply(ir.case_("Gt"), ir.lambda("_", ir.integer(0))),
          ir.lambda("_", ir.apply(ir.variable("self"), ir.integer(0))),
        ),
        ir.apply(
          ir.apply(ir.builtin("int_compare"), ir.variable("n")),
          ir.integer(0),
        ),
      ),
    )
  let constructor =
    ir.lambda(
      "self",
      ir.let_("_", ir.apply(ir.perform("Log"), ir.empty()), loop),
    )
  let handler = ir.lambda("_", ir.lambda("resume", ir.integer(0)))
  let fixed = ir.apply(ir.builtin("fix"), constructor)
  ir.apply(
    ir.apply(ir.apply(ir.handle("Log"), handler), ir.lambda("_", fixed)),
    ir.integer(3),
  )
  |> rejected
}

/// A record is a map, it cannot have two fields with the same label.
pub fn duplicate_row_test() {
  ir.apply(
    ir.apply(ir.extend("a"), ir.integer(1)),
    ir.apply(ir.apply(ir.extend("a"), ir.string("s")), ir.empty()),
  )
  |> rejected

  // The same label at two levels of nesting is fine.
  ir.apply(
    ir.apply(ir.extend("a"), ir.integer(1)),
    ir.apply(
      ir.apply(
        ir.extend("b"),
        ir.apply(ir.apply(ir.extend("a"), ir.string("s")), ir.empty()),
      ),
      ir.empty(),
    ),
  )
  |> accepted
}

/// A union carries one tag and `Case` peels one row at a time, so a repeated
/// tag describes a value that can exist.
pub fn duplicate_tag_test() {
  ir.apply(
    ir.apply(
      ir.apply(ir.case_("Ok"), ir.lambda("x", ir.variable("x"))),
      ir.lambda(
        "rest",
        ir.apply(
          ir.apply(
            ir.apply(
              ir.case_("Ok"),
              ir.lambda(
                "s",
                ir.apply(ir.builtin("string_length"), ir.variable("s")),
              ),
            ),
            ir.lambda("_", ir.integer(0)),
          ),
          ir.variable("rest"),
        ),
      ),
    ),
    ir.apply(ir.tag("Ok"), ir.integer(1)),
  )
  |> accepted
}

fn rejected(source) {
  case property.check(source, fuel) {
    property.Rejected(_) -> Nil
    outcome -> {
      io.println(property.report(source, outcome))
      panic as "the analysis accepted a program it should reject"
    }
  }
}

fn accepted(source) {
  case property.check(source, fuel) {
    property.Sound -> Nil
    outcome -> {
      io.println(property.report(source, outcome))
      panic as "the analysis rejected a program that runs"
    }
  }
}

/// The type of a value is a promise about its shape.
pub fn conforms_test() {
  let assert Ok(value) = property.evaluate(ir.integer(1), fuel)

  property.conforms(value, t.Integer)
  |> should.be_true

  property.conforms(value, t.String)
  |> should.be_false
}
