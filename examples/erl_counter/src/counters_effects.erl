%% EYG effect signatures and their Erlang implementations.
-module(counters_effects).

-export([types/0, handle/2]).

-define(TYPE, eyg@analysis@type_@isomorphic).

types() ->
    Reply = ?TYPE:result({record, empty}, string),
    Rate = ?TYPE:record([{<<"name">>, string}, {<<"seconds">>, integer}]),
    [
        {<<"StartCounter">>, {string, Reply}},
        {<<"SetTickRate">>, {Rate, Reply}},
        {<<"GetValue">>, {string, ?TYPE:result(integer, string)}},
        {<<"Shutdown">>, {string, Reply}}
    ].

handle(<<"StartCounter">>, {string, Name}) ->
    reply(counters_api:start_counter(Name));
handle(<<"SetTickRate">>, {record, #{<<"name">> := {string, Name}, <<"seconds">> := {integer, Seconds}}}) ->
    reply(counters_api:set_tick_rate(Name, Seconds));
handle(<<"GetValue">>, {string, Name}) ->
    reply(counters_api:get_value(Name));
handle(<<"Shutdown">>, {string, Name}) ->
    reply(counters_api:shutdown(Name)).

reply(ok) -> {tagged, <<"Ok">>, {record, #{}}};
reply({ok, Value}) -> {tagged, <<"Ok">>, {integer, Value}};
reply({error, Reason}) -> {tagged, <<"Error">>, {string, message(Reason)}}.

message(already_started) -> <<"counter already started">>;
message(not_found) -> <<"counter not found">>;
message(invalid_rate) -> <<"seconds must be a positive integer">>.
