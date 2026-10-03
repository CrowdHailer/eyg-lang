%% An application-owned session retains the cache returned by check and run.
%% Only results cross the process boundary, not the interpreter's large cache.
-module(counters_session).
-behaviour(gen_server).

-export([start_link/0, check/2, run/2, cached/2]).
-export([init/1, handle_call/3, handle_cast/2]).

start_link() ->
    gen_server:start_link(?MODULE, [], []).

check(Session, Source) ->
    gen_server:call(Session, {check, Source}, infinity).

run(Session, Source) ->
    gen_server:call(Session, {run, Source}, infinity).

cached(Session, Reference) ->
    gen_server:call(Session, {cached, Reference}).

init([]) ->
    {ok, eyg@hub@cache:empty()}.

handle_call({check, Source}, _From, Cache0) ->
    {Result, Cache1} = counters_eyg:check(Source, Cache0),
    {reply, Result, Cache1};
handle_call({run, Source}, _From, Cache0) ->
    {Result, Cache1} = counters_eyg:run(Source, Cache0),
    {reply, Result, Cache1};
handle_call({cached, Reference}, _From, Cache) ->
    Loaded = case eyg@hub@cache:get_reference(Cache, Reference) of
        {ok, _} -> true;
        {error, _} -> false
    end,
    {reply, Loaded, Cache}.

handle_cast(_Message, Cache) ->
    {noreply, Cache}.
