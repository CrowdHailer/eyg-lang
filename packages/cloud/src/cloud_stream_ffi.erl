-module(cloud_stream_ffi).
-export([post/7]).

%% Post a body and fold over the parts of the response body as they arrive.
%% Returns the folded value, or the reason the request failed.
%% `Timeout` is how long to wait for each part, not for the whole response.
post(Url, Headers, ContentType, Body, Timeout, Acc, Fold) ->
    {ok, _} = application:ensure_all_started(inets),
    {ok, _} = application:ensure_all_started(ssl),
    Hs = [{binary_to_list(K), binary_to_list(V)} || {K, V} <- Headers],
    Request = {binary_to_list(Url), Hs, binary_to_list(ContentType), Body},
    Options = [{sync, false}, {stream, self}, {body_format, binary}],
    case httpc:request(post, Request, [{ssl, ssl_options()}], Options) of
        {ok, Id} -> loop(Id, Timeout, Acc, Fold);
        {error, Reason} -> {error, describe(Reason)}
    end.

loop(Id, Timeout, Acc, Fold) ->
    receive
        {http, {Id, stream_start, _Headers}} -> loop(Id, Timeout, Acc, Fold);
        {http, {Id, stream, Part}} -> loop(Id, Timeout, Fold(Acc, Part), Fold);
        {http, {Id, stream_end, _Headers}} -> {ok, Acc};
        % A response that is not a success is not streamed, it arrives whole.
        {http, {Id, {{_Version, Status, _Reason}, _Headers, Whole}}} ->
            {error, unicode:characters_to_binary(
                io_lib:format("status ~p ~s", [Status, Whole]))};
        {http, {Id, {error, Reason}}} -> {error, describe(Reason)}
    after Timeout ->
        httpc:cancel_request(Id),
        {error, <<"response timeout">>}
    end.

ssl_options() ->
    [{verify, verify_peer},
     {cacerts, public_key:cacerts_get()},
     {customize_hostname_check,
      [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}].

describe(Reason) -> unicode:characters_to_binary(io_lib:format("~p", [Reason])).
