-module(otel_ffi).
-export([system_time/0]).

system_time() ->
    Nanoseconds = os:system_time(nanosecond),
    {Nanoseconds div 1000000000, Nanoseconds rem 1000000000}.
