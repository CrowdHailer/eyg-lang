-module(my_counter).
-behaviour(gen_server).

-export([start_link/1, get_value/1, set_tick_rate/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], []).

get_value(Counter) ->
    gen_server:call(Counter, get_value).

set_tick_rate(Counter, Seconds) ->
    gen_server:call(Counter, {set_tick_rate, Seconds}).

init([]) ->
    {ok, schedule(#{value => 0, seconds => 1})}.

handle_call(get_value, _From, State = #{value := Value}) ->
    {reply, Value, State};
handle_call({set_tick_rate, Seconds}, _From, State = #{timer := Timer})
        when is_integer(Seconds), Seconds > 0 ->
    erlang:cancel_timer(Timer),
    {reply, ok, schedule(State#{seconds := Seconds})};
handle_call({set_tick_rate, _}, _From, State) ->
    {reply, {error, invalid_tick_rate}, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info({timeout, Timer, tick}, State = #{timer := Timer, value := Value}) ->
    {noreply, schedule(State#{value := Value + 1})};
handle_info(_Message, State) ->
    % A cancelled timer may already have sent its message. Ignore stale ticks.
    {noreply, State}.

schedule(State = #{seconds := Seconds}) ->
    State#{timer => erlang:start_timer(Seconds * 1000, self(), tick)}.
