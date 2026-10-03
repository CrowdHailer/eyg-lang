%% Parse, load references, and check once; execute against that same cache.
-module(counters_eyg).

-export([check/1, check/2, run/1, run/2]).

-define(INFER, eyg@analysis@inference@levels_j@contextual).
-define(DEBUG, eyg@analysis@type_@binding@debug).
-define(CACHE, eyg@hub@cache).
-define(EXPR, eyg@interpreter@expression).
-define(VALUE_DEBUG, eyg@interpreter@simple_debug).

%% Every entry point returns {Result, Cache}. The caller owns the cache.
%% One-argument shell conveniences start empty and print readable diagnostics.
check(Source) ->
    {Result, _Cache} = Return = check(Source, ?CACHE:empty()),
    case Result of
        {ok, Type} -> io:format("~ts~n", [Type]);
        {error, Message} -> io:format("~ts~n", [Message])
    end,
    Return.

check(Source, Cache) ->
    case parse_and_check(unicode:characters_to_binary(Source), Cache) of
        {{ok, {_Tree, Analysis}}, Loaded} ->
            {{ok, ?DEBUG:render_type(?INFER:type_(Analysis))}, Loaded};
        Failed -> Failed
    end.

run(Source) ->
    {Result, _Cache} = Return = run(Source, ?CACHE:empty()),
    case Result of
        {ok, Value} -> io:format("~ts~n", [?VALUE_DEBUG:inspect(Value)]);
        {error, Message} -> io:format("~ts~n", [Message])
    end,
    Return.

run(Source0, Cache) ->
    Source = unicode:characters_to_binary(Source0),
    case parse_and_check(Source, Cache) of
        {{ok, {Tree, _Analysis}}, Loaded} ->
            {run_step(?EXPR:execute(Tree, []), Source, Loaded), Loaded};
        Failed -> Failed
    end.

%% static_loop consumes reference breaks using cached values. Only effects reach
%% the handler. Env and K are opaque interpreter state: pass them back unchanged.
run_step(Step, Source, Cache) ->
    case ?CACHE:static_loop(Step, Cache, fun ?EXPR:resume/3) of
        {error, {{unhandled_effect, Label, Lift}, _Span, Env, K}} ->
            Reply = counters_effects:handle(Label, Lift),
            run_step(?EXPR:resume(Reply, Env, K), Source, Cache);
        {error, {Reason, Span, _Env, _K}} ->
            {error, eyg@parser:render_error(
                ?VALUE_DEBUG:describe(Reason), ?VALUE_DEBUG:hint(Reason), Source, Span
            )};
        {ok, Value} -> {ok, Value}
    end.

parse_and_check(Source, Cache) ->
    case eyg@parser:all_from_string(Source) of
        {error, Reason} -> {{error, eyg@parser:format_error(Reason, Source)}, Cache};
        {ok, Tree} ->
            case counters_packages:prepare(Tree, Cache) of
                {ok, Loaded} -> {analyse(Tree, Source, Loaded), Loaded};
                %% A failed package batch hasn't passed validation: retain the
                %% caller's original cache rather than expose unchecked modules.
                Error -> {Error, Cache}
            end
    end.

analyse(Tree, Source, Cache) ->
    Context = ?INFER:with_effects(?INFER:pure(), counters_effects:types()),
    Analysis = ?CACHE:infer_sync(?INFER:check(Context, Tree), Cache),
    case ?INFER:all_errors(Analysis) of
        [] -> {ok, {Tree, Analysis}};
        Errors ->
            Messages = [eyg@parser:render_error(
                ?DEBUG:render_reason(Reason), ?DEBUG:hint(Reason), Source, Span
            ) || {Span, Reason} <- Errors],
            {error, iolist_to_binary(lists:join(<<"\n\n">>, Messages))}
    end.
