%% Names are binaries used as supervisor child IDs, not dynamically created atoms.
-module(counters_api).

-export([start_counter/1, set_tick_rate/2, get_value/1, shutdown/1]).

start_counter(Name) when is_binary(Name) ->
    case counters_sup:start_child(Name) of
        {ok, _Pid} -> ok;
        {error, {already_started, _Pid}} -> {error, already_started};
        {error, already_present} -> {error, already_started}
    end.

set_tick_rate(_Name, Seconds) when not is_integer(Seconds); Seconds < 1 ->
    {error, invalid_rate};
set_tick_rate(Name, Seconds) ->
    with_counter(Name, fun(Pid) ->
        gen_server:call(Pid, {set_tick_rate, Seconds})
    end).

get_value(Name) ->
    with_counter(Name, fun(Pid) -> gen_server:call(Pid, get_value) end).

shutdown(Name) ->
    case supervisor:terminate_child(counters_sup, Name) of
        ok -> supervisor:delete_child(counters_sup, Name);
        {error, not_found} -> {error, not_found}
    end.

with_counter(Name, Fun) ->
    case lists:keyfind(Name, 1, supervisor:which_children(counters_sup)) of
        {Name, Pid, worker, _} when is_pid(Pid) -> Fun(Pid);
        _ -> {error, not_found}
    end.
