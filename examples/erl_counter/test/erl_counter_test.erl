-module(erl_counter_test).
-include_lib("eunit/include/eunit.hrl").

-export([main/0]).

%% Run with `erl -pa build/dev/erlang/*/ebin -noshell -s erl_counter_test main -s init stop`.
main() ->
    case eunit:test([?MODULE, counters_packages_test], [verbose]) of
        ok -> ok;
        error -> erlang:halt(1)
    end.

counters_test_() ->
    {setup,
        fun() ->
            {ok, Apps} = application:ensure_all_started(erl_counter),
            application:set_env(erl_counter, package_fetch, fun(_) ->
                fun(K) -> K({error, {network_error, <<"offline test">>}}) end
            end),
            Apps
        end,
        fun(Apps) ->
            application:unset_env(erl_counter, package_fetch),
            [application:stop(App) || App <- lists:reverse(Apps)]
        end,
        [
            fun check_does_not_execute/0,
            fun rejects_bad_scripts_before_effects/0,
            fun sequential_effects/0,
            fun error_values_and_shutdown/0,
            fun rate_changes_ignore_old_ticks/0
        ]}.

cache() -> eyg@hub@cache:empty().

check_does_not_execute() ->
    {{ok, _Type}, Cache} = counters_eyg:check("perform StartCounter(\"check\")", cache()),
    ?assertEqual(cache(), Cache),
    ?assertEqual({error, not_found}, counters_api:get_value(<<"check">>)).

rejects_bad_scripts_before_effects() ->
    ?assertMatch({{error, _}, _}, counters_eyg:run("{broken:", cache())),
    ?assertMatch({{error, _}, _}, counters_eyg:run("perform Log(\"no\")", cache())),
    ?assertMatch({{error, _}, _}, counters_eyg:run("@missing", cache())),
    {{error, Message}, Cache} = counters_eyg:run(
        "let _ = perform StartCounter(\"bad\")\nperform GetValue(3)", cache()),
    ?assertEqual(cache(), Cache),
    ?assertNotEqual(nomatch, binary:match(Message,
        <<"type mismatch given: Integer expected: String">>)),
    ?assertNotEqual(nomatch, binary:match(Message, <<"perform GetValue(3)">>)),
    ?assertEqual({error, not_found}, counters_api:get_value(<<"bad">>)).

sequential_effects() ->
    Source = "let _ = perform StartCounter(\"sequence\")\n"
             "let _ = perform SetTickRate({name: \"sequence\", seconds: 1})\n"
             "perform GetValue(\"sequence\")",
    ?assertEqual({{ok, {tagged, <<"Ok">>, {integer, 0}}}, cache()}, counters_eyg:run(Source, cache())),
    ?assertEqual(ok, counters_api:shutdown(<<"sequence">>)).

error_values_and_shutdown() ->
    ?assertEqual(ok, counters_api:start_counter(<<"errors">>)),
    ?assertMatch({{ok, {tagged, <<"Error">>, {string, _}}}, _},
        counters_eyg:run("perform StartCounter(\"errors\")", cache())),
    ?assertMatch({{ok, {tagged, <<"Error">>, {string, _}}}, _},
        counters_eyg:run("perform SetTickRate({name: \"errors\", seconds: 0})", cache())),
    ?assertEqual({{ok, {tagged, <<"Ok">>, {record, #{}}}}, cache()},
        counters_eyg:run("perform Shutdown(\"errors\")", cache())),
    ?assertMatch({{ok, {tagged, <<"Error">>, {string, _}}}, _},
        counters_eyg:run("perform GetValue(\"errors\")", cache())),
    ?assertEqual(ok, counters_api:start_counter(<<"errors">>)),
    ?assertEqual(ok, counters_api:shutdown(<<"errors">>)).

rate_changes_ignore_old_ticks() ->
    ok = counters_api:start_counter(<<"timer">>),
    {<<"timer">>, Pid, worker, _} = lists:keyfind(
        <<"timer">>, 1, supervisor:which_children(counters_sup)),
    #{seconds := 10, timer := OldTimer} = sys:get_state(Pid),
    ok = counters_api:set_tick_rate(<<"timer">>, 1),
    Pid ! {timeout, OldTimer, tick},
    ?assertEqual({ok, 0}, counters_api:get_value(<<"timer">>)),
    await_tick(erlang:monotonic_time(millisecond) + 3000),
    ok = counters_api:shutdown(<<"timer">>).

await_tick(Deadline) ->
    case counters_api:get_value(<<"timer">>) of
        {ok, Value} when Value >= 1 -> ok;
        _ ->
            ?assert(erlang:monotonic_time(millisecond) < Deadline),
            timer:sleep(20),
            await_tick(Deadline)
    end.
