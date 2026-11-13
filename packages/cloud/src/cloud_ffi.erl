-module(cloud_ffi).
-export([set_tracer/1, get_tracer/0, is_null/1]).

%% The tracer every process records spans to, once the cloud has started one.
set_tracer(Tracer) -> persistent_term:put(eyg_cloud_tracer, Tracer), nil.
get_tracer() ->
    case persistent_term:get(eyg_cloud_tracer, undefined) of
        undefined -> {error, nil};
        Tracer -> {ok, Tracer}
    end.

is_null(null) -> true;
is_null(_) -> false.
