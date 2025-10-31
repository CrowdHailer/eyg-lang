-module(eyg_ir_promise_ffi).

-export([map/2, identity/1]).

map(P, Then) ->
  Then(P).

identity(Ps) ->
  Ps.