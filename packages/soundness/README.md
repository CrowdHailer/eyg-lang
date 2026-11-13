# Soundness

Property tests that look for programs the analysis accepts and eval rejects.

EYG aspires to type soundness: if the analysis accepts a program then running
it should not fail with a type error. Every way eval can fail is a type error,
so the property is simple to state.

> A program that type checks in a pure context runs to a value of that type,
> or does not terminate.

Run the search with `gleam test --runtime bun`.

## How programs are generated

`soundness/generate_typed` builds programs from the type rules themselves: the
types in the builtin table, and the shapes the inference gives to lambdas,
records, unions, `fix` and handlers. Every program it produces should type
check, so the analysis accepting them proves nothing, but any of them failing
to run means a rule promises something eval does not honour.

Generation is indexed by the effects allowed at each point. A function type
carries its own effect row, so a function that performs an effect can be built
in a pure part of the program, passed around, and called where the effect is
handled. That is the shape of program where the interesting questions about
effects live, and where two of the three bugs found so far were hiding.

`soundness/generate` builds programs at random instead. About 199 in 200 are
rejected by the analysis, which is why it is not the main search, but it
reaches shapes the typed generator does not know how to build.

## What it found

The regression cases in the test suite are the programs that used to be
accepted and then failed.

- `!fix` typed as `((a) -> a) -> a`, so the fixed value did not have to be a
  function, [issue 97](https://github.com/CrowdHailer/eyg-lang/issues/97)
- the constructor passed to `!fix` could perform effects, which are then
  performed again on every recursive call, outside the handler that was
  installed when `fix` was called
- a record type could name the same label twice, describing a field the value
  does not have
