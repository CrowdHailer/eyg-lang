-module(my_counters_script).
-include_lib("eyg_interpreter/include/eyg@interpreter@break_UnhandledEffect.hrl").
-include_lib("eyg_interpreter/include/eyg@interpreter@value_String.hrl").

-export([run/1]).

run(Code) when is_list(Code) ->
    run(unicode:characters_to_binary(Code));
run(Code) when is_binary(Code) ->
  case eyg@parser:all_from_string(Code) of
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
extrinsic(<<"Random">>, {integer, Max}) when Max > 0 ->
  {ok, {integer, rand:uniform(Max)}};
extrinsic(Label, Value) -> {error, #unhandled_effect{label = Label, value = Value}}.

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