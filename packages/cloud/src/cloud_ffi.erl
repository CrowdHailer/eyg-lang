-module(cloud_ffi).
-export([set_https_proxy/2, read_stdin/0]).

%% Route outbound https requests made with httpc through a proxy.
set_https_proxy(Host, Port) ->
    {ok, _} = application:ensure_all_started(inets),
    httpc:set_options([{https_proxy, {{binary_to_list(Host), Port}, ["localhost", "127.0.0.1"]}}]),
    nil.

%% Read all of standard input as a binary.
read_stdin() ->
    read_stdin([]).

read_stdin(Acc) ->
    case io:get_chars(standard_io, "", 1024) of
        eof -> unicode:characters_to_binary(lists:reverse(Acc));
        {error, _} -> unicode:characters_to_binary(lists:reverse(Acc));
        Chunk -> read_stdin([Chunk | Acc])
    end.
