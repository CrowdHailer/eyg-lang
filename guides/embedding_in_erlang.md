---
name: Embedding EYG in Erlang programs
description: Step by step guide to using EYG types, effects and packages from erlang.
---

This guide adds EYG scripting to an Erlang application `my_counters`.
Just want the code look at [example](../examples/my_counters_erlang).

Embedding EYG in Erlang gives you a scripting environment with tight controls over what can be accessed.
With this control you can:

- Expose scripting to the users, maybe for small queries or automations
- Build a safer shell with predefined dev tasks
- Provide a set of business logic functions to agents

## Install dependencies

EYG's toolkit consists of a set of composable parts, for this guide install the following.

- [eyg_parser](https://hex.pm/packages/eyg_parser)
- [eyg_interpreter](https://hex.pm/packages/eyg_interpreter)
- [eyg_analysis](https://hex.pm/packages/eyg_analysis)

## Run a pure program

Below is the simplest Erlang module that will run EYG code.

```erlang
-module(my_counters_script).

-export([run/1]).

run(Code) when is_binary(Code) ->
  case eyg@parser:all_from_string(Code) of
    {ok, Source} -> 
      Result = eyg@interpreter@expression:execute(Source, []),
      Result;
    {error, Reason} -> {error, Reason}
  end.
```

Start an Erlang shell, with this module loaded, and run your first scripts.

```
(counters@MyComputer)1> my_counters_script:run(<<"!int_add(2, 1)">>).
{ok,{integer,3}}
```

This is everything needed to run any self-contained, pure EYG program.
We will add two affordances that make it easier to work with.

First we will pretty print the errors.
Each EYG package has its own pretty printing functions.
The code below will handle formatting parser errors as well as runtime values and errors.
The return value from this function is now a binary that can be presented to the user.

```erlang
run(Code) when is_binary(Code) ->
  case eyg@parser:all_from_string(Code) of
    {ok, Source} -> 
      Result = eyg@interpreter@expression:execute(Source, []),
      case Result of
        {ok, Value} -> debug_interpreter_value(Value);
        {error, Reason} -> debug_interpreter_error(Reason, Code)
      end;
    {error, Reason} -> debug_parser_error(Reason, Code)
  end.

debug_parser_error(Reason, Code) ->
  eyg@parser:format_error(Reason, Code).

debug_interpreter_value(Value) ->
  eyg@interpreter@simple_debug:inspect(Value).

debug_interpreter_error({Reason, Span, _, _}, Code) ->
  eyg@parser:render_error(
    eyg@interpreter@simple_debug:describe(Reason),
    eyg@interpreter@simple_debug:hint(Reason),
    Code,
    Span
  ).
```

All the examples in this guide we are running from the erlang shell so it's convenient for our run function to accept charlists as well as binaries.

```erlang
run(Code) when is_list(Code) ->
    run(unicode:characters_to_binary(Code));
run(Code) when is_binary(Code) ->
  % existing body
```

Now a runtime errors prints useful output.

```
(counters@MyComputer)1> io:put_chars(my_counters_script:run(<<"!int_add(2, foo)">>)).
error: variable undefined: foo
hint: check the variable name or add a `let` binding before it is used

 1 | !int_add(2, foo)
                 ^^^
```

## Effects

EYG programs in this first runner cannot perform any side effect.
This is already good enough for a configuration script but for anything more we need to add effects.
Running a simple hello world currently fails.

```eyg
perform Log("Hello, world!")
```

```
(counters@MyComputer)1> io:put_chars(my_counters_script:run(<<"perform Log(\"Hello, World!\")">>)).
error: unhandled effect Log("Hello, World!")
hint: handle this effect or run the program in a runtime that supports it

 1 | perform Log("Hello, World!")
     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

Any error interpreting an EYG program returns the reason for the break and the full program state.
An unhandled effect is one type of break.

*For an explanation of what an algebraic effect is check out this [post](https://crowdhailer.me/2025-02-14/algebraic-effects-are-a-functional-approach-to-manage-side-effects/)*

When execution stops at an unhandled effect, the Erlang host can implement it and resume the EYG program with the reply value.
We update the `run` function so the initial result from executing the expression is passed to a `loop` function that will keep running the program for every break that can be handled.

```erlang
run(Code) when is_binary(Code) ->
  Output = case eyg@parser:all_from_string(Code) of
    {ok, Source} -> 
      Result = loop(eyg@interpreter@expression:execute(Source, [])),
      % same as before
```

The implementation of `loop` matches on an `unhandled_effect`.
If the extrinsic implementation of the effect succeeds the loop recurses.

```erlang
-include_lib("eyg_interpreter/include/eyg@interpreter@break_UnhandledEffect.hrl").
-include_lib("eyg_interpreter/include/eyg@interpreter@value_String.hrl").

loop({error, {#unhandled_effect{label = Label, value = Value}, Span, Env, Stack}}) ->
  case extrinsic(Label, Value) of
    {ok, Reply} ->
      loop(eyg@interpreter@expression:resume(Reply, Env, Stack));
    {error, Reason} ->
      {error, {Reason, Span, Env, Stack}}
  end;
loop(Result) -> Result.

extrinsic(<<"Log">>, #string{value = String})->
  io:put_chars(String),
  {ok, eyg@interpreter@value:unit()};
extrinsic(Label, Value) -> {error, #unhandled_effect{label = Label, value = Value}}.
```

Effects can be implemented at any level of abstraction.
They can be core utilities like logging or more specific to the application.
The counter example has additional utilities `Random` and `Now` as well as three effects for managing the counter application.

## Type checking

Before running an EYG we can check that it has no runtime errors.
The type inferences is sound, any program that passes type checking has no runtime errors.
An effect context is passed to type checking ensuring that a program has no errors including trying to call effects that are unavailable.

In this type checking loop we start with a pure context and extend it with just the the `Log` effect.

```erlang
type_check(Source) ->
  Infer = eyg@analysis@inference@levels_j@contextual,
  Analysis = type_check_loop(Infer:check(inference_context(), Source)),
  Infer:all_errors(Analysis).

type_check_loop({done, Analysis}) -> Analysis;
type_check_loop({lookup, _Reference, Resume}) -> type_check_loop(Resume({error, nil})).

inference_context() ->
  Infer = eyg@analysis@inference@levels_j@contextual,
  Context0 = Infer:pure(),
  Unit = eyg@analysis@type_@isomorphic:record([]),
  Context1 = Infer:with_effect(Context0, <<"Log">>, string, Unit),
  Context1.

debug_type_error({Span, Reason}, Source) ->
  eyg@parser:render_error(
      eyg@analysis@type_@binding@debug:render_reason(Reason),
      eyg@analysis@type_@binding@debug:hint(Reason),
      Source,
      Span
  ).
```

Replace the successful parse branch in `run/1` with the following.
If type checking succeeds, run the program; otherwise, return the formatted diagnostics.

```erlang
{ok, Source} ->
  case type_check(Source) of
    [] ->
      Result = loop(eyg@interpreter@expression:execute(Source, [])),
      case Result of
        {ok, Value} -> debug_interpreter_value(Value);
        {error, Reason} -> debug_interpreter_error(Reason, Code)
      end;
    Errors ->
      unicode:characters_to_binary([[debug_type_error(Error, Code), "\n"] || Error <- Errors])
  end;
```

You now have an EYG scripting environment that checks programs before running them and has the full power of Erlang available for implementing effects.
To expose more of your application, add effect handlers and their corresponding types to the inference context.

## Loading releases

The [example runner](../examples/my_counters_erlang/src/my_counters_script.erl)
also loads dependencies from `https://eyg.run` using `eyg_hub` and `gleam_httpc`.
For example, try this in the Erlang shell:

```erlang
io:put_chars(my_counters_script:run(
  <<"let {list} = @standard list.length([1, 2, 3])">>
)).
```

This prints `3`. `@standard` selects the latest release in the hub's package
ledger. `@standard:1` selects a version, while `@name:version:<module-cid>` pins
both the version and module. Use the fully pinned form in shared programs.
Content references (`#<module-cid>`) are also supported; relative file imports
are not resolved by this runner.

Loading has two parts: supplying a dependency's type during inference, and its
value during execution:

1. `eyg@hub@cache:prepare/2` queues the initial module fetches and any required package
   ledger pull. `drain/2` flushes those actions, performs the HTTP requests, and
   feeds responses to `eyg@hub@cache:update/3`. It repeats until no actions remain,
   including requests for transitive dependencies and further ledger pages.
2. When inference returns a `lookup`, `eyg@hub@cache:follow_reference/2` resolves its
   module CID. The runner fetches it and resumes inference with the cached
   module's `type_` field. Pinned releases must match the ledger's CID.
3. If type checking succeeds, execution begins. An `undefined_reference` break
   is resumed with the cached module's `value` field, just as an effect break is
   resumed with the host's reply.

Each fetched module is re-encoded as DAG-JSON and hashed with SHA-256 to check
its CID before it enters the cache. Unavailable dependencies produce the normal
type diagnostics; a script with type errors is not executed.

`run/1` starts with an empty cache, so self-contained expressions do not make
network requests. The HTTP applications start when a request is needed.
`run/2` accepts an existing cache; both functions return the formatted result.
Newly loaded dependencies are shared within that evaluation, not retained
between shell inputs.
