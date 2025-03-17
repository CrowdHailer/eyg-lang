import eyg/ir/dag_json
import morph/editable as e
import website/components/snippet.{type Snippet, Snippet}

// throwing away the run state when a task might complete later is a problem
// This is an issue of named proceses an a pid id wouldn't have the same problem
// the pid id would be fine but how do we handle the multiple effects run in a single run
// Should the runner be built with a builder pattern potentially the runner can have a paramerisation of return type
// However all of this might be overkill if it can't be used by reload

// The interesting situation was when a run had started but was waiting on a ref because then there was no task function

// run.update(start) -> #(returniswatingref, Nothing)
// run.update(ExtrinsicHandlerReply) ->

// Cant be unstarted and waiting for a reply
// Can be started and not waiting for a reply

// Turn break around could have failure type but I'm interested in undefined variable returning something lazy
// vacant code cold also potentially have a test value
// pub type Reason(m, c) {
//   NotAFunction(v.Value(m, c))
//   UndefinedVariable(String)
//   UndefinedBuiltin(String)
//   UndefinedReference(String) + go
//   UndefinedRelease(package: String, release: Int, cid: String) + go
//   Vacant
//   NoMatch(term: v.Value(m, c))
//   UnhandledEffect(String, v.Value(m, c)) + taskref
//   IncorrectTerm(expected: String, got: v.Value(m, c))
//   MissingField(String)
// }

// We don't have a go step on builtins as we ALWAYS go but we need a variable saying will run for cache update
// It's sorta useful to say will run for further effects as we can step through effects potentially although you could handle that outse
// but if you did handle that outside would original go be handled outside probably

// next ref

// Might want auto continue to depend on effect, in which case this is just more composition of execute etc

// Might not want a global effect to run from an example for example wait 20 min and then alert is very confusing if using another example

// continue awaiting: extrinsic_ref,next_ref
// cancel sets awaiting to none and continue to false

// is reusing Return the problem here or more accuratly break

// is there a task id and ref id equivalence ones idempotent so probably not.

// unhandled effect is the return value 
// if you change the effects then there will be a task that is not expected

// run once doesn' work with bools if waiting on ref
// I don't like fixed named enums it leads to a lot of invalid type modelling
// reload does work on expression

// interactive.block(tree, scope)
// expression

pub type Runner {
  Runner(
    // if return is missing ref then continue should be once or many
    // if return is unhandled then continue should be None or many
    // if return is unhandled and awaiting ref is None then continue is irrelevant

    // if vacant and wantted to put in code then could be none or many once makes some sense in the wat
    return: Nil,
    continue: Bool,
    awaiting_ref: Nil,
    next_ref: Int,
  )
}

pub type Example {
  Example(snippet: Snippet)
}

pub fn from_block(bytes) {
  let assert Ok(source) = dag_json.from_block(bytes)
  let source =
    e.from_annotated(source)
    |> e.open_all
  let snippet = snippet.init(source)
  todo
}
