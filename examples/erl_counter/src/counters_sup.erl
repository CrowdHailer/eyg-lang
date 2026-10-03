-module(counters_sup).
-behaviour(supervisor).

-export([start_link/0, start_child/1]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(Name) ->
    supervisor:start_child(?MODULE, #{
        id => Name,
        start => {counter, start_link, [Name]},
        restart => transient
    }).

init([]) ->
    {ok, {#{strategy => one_for_one}, []}}.
