-module(cloud_ffi).
-export([set_https_proxy/2]).

%% Route outbound https requests made with httpc through a proxy.
set_https_proxy(Host, Port) ->
    {ok, _} = application:ensure_all_started(inets),
    httpc:set_options([{https_proxy, {{binary_to_list(Host), Port}, ["localhost", "127.0.0.1"]}}]),
    nil.
