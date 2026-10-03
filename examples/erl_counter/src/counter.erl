%% One supervised counter. Timer references make cancelled, queued ticks harmless.
-module(counter).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link(Name) ->
    gen_server:start_link(?MODULE, Name, []).

init(Name) ->
    {ok, schedule(#{name => Name, value => 0, seconds => 10})}.

handle_call(get_value, _From, State = #{value := Value}) ->
    {reply, {ok, Value}, State};
handle_call({set_tick_rate, Seconds}, _From, State = #{timer := Timer}) ->
    erlang:cancel_timer(Timer),
    {reply, ok, schedule(State#{seconds := Seconds})}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info({timeout, Timer, tick}, State = #{timer := Timer, value := Value}) ->
    {noreply, schedule(State#{value := Value + 1})};
handle_info(_Message, State) ->
    {noreply, State}.

schedule(State = #{seconds := Seconds}) ->
    State#{timer => erlang:start_timer(Seconds * 1000, self(), tick)}.
