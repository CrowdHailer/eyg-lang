-module(my_counters_script).
-include_lib("eyg_hub/include/eyg@hub@cache_Module.hrl").
-include_lib("eyg_interpreter/include/eyg@interpreter@break_UndefinedReference.hrl").
-include_lib("eyg_interpreter/include/eyg@interpreter@break_UnhandledEffect.hrl").
-include_lib("eyg_interpreter/include/eyg@interpreter@value_Integer.hrl").
-include_lib("eyg_interpreter/include/eyg@interpreter@value_Record.hrl").
-include_lib("eyg_interpreter/include/eyg@interpreter@value_String.hrl").

-export([run/1, run/2]).

run(Code) ->
  run(Code, eyg@hub@cache:empty()).

run(Code, Cache) when is_list(Code) ->
  run(unicode:characters_to_binary(Code), Cache);
run(Code, Cache0) when is_binary(Code) ->
  case eyg@parser:all_from_string(Code) of
    {ok, Source} ->
      {Errors, Cache1} = type_check(Source, Cache0),
      case Errors of
        [] ->
          Result = loop(eyg@interpreter@expression:execute(Source, []), Cache1),
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

loop({error, {#unhandled_effect{label = Label, value = Value}, Span, Env, Stack}}, Cache) ->
  case extrinsic(Label, Value) of
    {ok, Reply} ->
      loop(eyg@interpreter@expression:resume(Reply, Env, Stack), Cache);
    {error, Reason} ->
      {error, {Reason, Span, Env, Stack}}
  end;
loop({error, {#undefined_reference{reference = Reference}, _, Env, Stack}} = Result, Cache) ->
  case eyg@hub@cache:get_reference(Cache, Reference) of
    {ok, #module{value = Value}} ->
      loop(eyg@interpreter@expression:resume(Value, Env, Stack), Cache);
    {error, _} -> Result
  end;
loop(Result, _Cache) -> Result.

extrinsic(<<"Log">>, #string{value = String})->
  io:put_chars(String),
  {ok, eyg@interpreter@value:unit()};
extrinsic(<<"Random">>, #integer{value = Max}) when Max > 0 ->
  {ok, #integer{value = rand:uniform(Max)}};
extrinsic(<<"Now">>, #record{fields = Fields}) when map_size(Fields) =:= 0 ->
  {ok, #integer{value = erlang:system_time(millisecond)}};
extrinsic(<<"StartCounter">>, #string{value = Name}) ->
  {ok, _} = my_counters_sup:start_child(binary_to_atom(Name, utf8)),
  {ok, eyg@interpreter@value:unit()};
extrinsic(<<"GetValue">>, #string{value = Name}) ->
  {ok, #integer{value = my_counter:get_value(binary_to_existing_atom(Name, utf8))}};
extrinsic(<<"SetTickRate">>, #record{fields = #{
  <<"name">> := #string{value = Name}, <<"seconds">> := #integer{value = Seconds}
}}) when Seconds > 0 ->
  ok = my_counter:set_tick_rate(binary_to_existing_atom(Name, utf8), Seconds),
  {ok, eyg@interpreter@value:unit()};
extrinsic(Label, Value) -> {error, #unhandled_effect{label = Label, value = Value}}.

type_check(Source, Cache0) ->
  {ok, Origin} = ogre@origin:from_string(<<"https://eyg.run">>),
  Cache1 = drain(eyg@hub@cache:prepare(Cache0, Source), Origin),
  Infer = eyg@analysis@inference@levels_j@contextual,
  {Analysis, Cache2} = type_check_loop(Infer:check(inference_context(), Source), Cache1, Origin),
  {Infer:all_errors(Analysis), Cache2}.

type_check_loop({done, Analysis}, Cache, _Origin) -> {Analysis, Cache};
type_check_loop({lookup, Reference, Resume}, Cache0, Origin) ->
  {Fetched, Cache2} = case eyg@hub@cache:follow_reference(Cache0, Reference) of
    {ok, Cid} ->
      Cache1 = drain(eyg@hub@cache:fetch(Cache0, Cid), Origin),
      case eyg@hub@cache:get_module(Cache1, Cid) of
        {ok, #module{type_ = PolyType}} -> {{ok, PolyType}, Cache1};
        {error, _} -> {{error, nil}, Cache1}
      end;
    {error, _} -> {{error, nil}, Cache0}
  end,
  type_check_loop(Resume(Fetched), Cache2, Origin).

inference_context() ->
  Infer = eyg@analysis@inference@levels_j@contextual,
  Context0 = Infer:pure(),
  Unit = eyg@analysis@type_@isomorphic:record([]),
  Context1 = Infer:with_effect(Context0, <<"Log">>, string, Unit),
  Context2 = Infer:with_effect(Context1, <<"Random">>, integer, integer),
  Context3 = Infer:with_effect(Context2, <<"Now">>, Unit, integer),
  Context4 = Infer:with_effect(Context3, <<"StartCounter">>, string, Unit),
  Context5 = Infer:with_effect(Context4, <<"GetValue">>, string, integer),
  TickRate = eyg@analysis@type_@isomorphic:record([
    {<<"name">>, string}, {<<"seconds">>, integer}
  ]),
  Context6 = Infer:with_effect(Context5, <<"SetTickRate">>, TickRate, Unit),
  Context6.

debug_type_error({Span, Reason}, Source) ->
  eyg@parser:render_error(
    eyg@analysis@type_@binding@debug:render_reason(Reason),
    eyg@analysis@type_@binding@debug:hint(Reason),
    Source,
    Span
  ).

drain(Cache0, Origin) ->
  {Cache1, Actions} = eyg@hub@cache:flush(Cache0),
  case Actions of
    [] -> Cache1;
    _ ->
      {ok, _} = application:ensure_all_started(gleam_httpc),
      drain(perform_actions(Actions, Cache1, Origin), Origin)
  end.

perform_actions([], Cache, _Origin) -> Cache;
perform_actions([Action | Rest], Cache0, Origin) ->
  Completed = perform_cache_action(Action, Origin),
  {Cache1, _Resolved} = eyg@hub@cache:update(Cache0, Completed, fun(_) -> {0, 0} end),
  perform_actions(Rest, Cache1, Origin).

perform_cache_action({fetch_module, Cid}, Origin) ->
  Request = eyg@hub@client:fetch_module_request(Cid, Origin),
  Result = case gleam@httpc:send_bits(Request) of
    {ok, Response} ->
      case eyg@hub@client:fetch_module_response(Response) of
        {ok, {some, Tree}} -> verify_module(Cid, Tree);
        {ok, none} -> {error, <<"Module not found">>};
        {error, Reason} -> cache_error(Reason)
      end;
    {error, Reason} -> cache_error(Reason)
  end,
  {fetch_module_completed, Cid, Result};
perform_cache_action({pull_packages, Offset}, Origin) ->
  Request = eyg@hub@client:pull_packages_request(
    {pull_parameters, Offset, 1000, []}, Origin
  ),
  Result = case gleam@httpc:send_bits(Request) of
    {ok, Response} ->
      case eyg@hub@client:pull_packages_response(Response) of
        {ok, {pull_response, Entries}} -> {ok, Entries};
        {error, Reason} -> cache_error(Reason)
      end;
    {error, Reason} -> cache_error(Reason)
  end,
  {pull_packages_completed, Result}.

verify_module(Cid, Tree) ->
  Bytes = eyg@ir@dag_json:to_block(Tree),
  Digest = crypto:hash(sha256, Bytes),
  Actual = {cid, dag_json:code(), {multihash, sha256, Digest}},
  case Actual =:= Cid of
    true -> {ok, Tree};
    false -> {error, <<"Hub returned module with the wrong CID">>}
  end.

cache_error(Reason) ->
  {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}.
