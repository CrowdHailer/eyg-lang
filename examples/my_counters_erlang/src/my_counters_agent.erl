-module(my_counters_agent).
-export([start/0]).

start() ->
  Key = case os:getenv("OLLAMA_TOKEN") of
    false -> error({missing_environment_variable, "OLLAMA_TOKEN"});
    "" -> error({missing_environment_variable, "OLLAMA_TOKEN"});
    Token -> Token
  end,
  {ok, _} = application:ensure_all_started(my_counters),
  {ok, _} = application:ensure_all_started(inets),
  {ok, _} = application:ensure_all_started(ssl),
  Model = unicode:characters_to_binary(os:getenv("OLLAMA_MODEL", "gpt-oss:120b")),
  spawn(fun() ->
    io:format("Ollama / ~ts | tool: run_eyg | :quit to exit~n", [Model]),
    shell([#{role => <<"system">>, content => system_prompt()}], Key, Model)
  end).

shell(Messages, Key, Model) ->
  case io:get_line("agent> ") of
    eof -> ok;
    {error, _} -> ok;
    Line ->
      case string:trim(Line) of
        ":quit" -> ok;
        "" -> shell(Messages, Key, Model);
        Prompt ->
          Next = Messages ++ [#{role => <<"user">>,
            content => unicode:characters_to_binary(Prompt)}],
          shell(turn(Next, Key, Model), Key, Model)
      end
  end.

turn(Messages, Key, Model) ->
  case chat(Messages, Key, Model) of
    {ok, Reply} ->
      case maps:get(<<"content">>, Reply, <<>>) of
        <<>> -> ok;
        Content -> io:format("~ts~n", [Content])
      end,
      Next = Messages ++ [Reply],
      case maps:get(<<"tool_calls">>, Reply, []) of
        [] -> Next;
        Calls ->
          Results = lists:map(fun call_tool/1, Calls),
          turn(Next ++ Results, Key, Model)
      end;
    {error, Reason} ->
      io:format("Ollama error: ~p~n", [Reason]),
      Messages
  end.

chat(Messages, Key, Model) ->
  Body = iolist_to_binary(json:encode(#{
    model => Model, messages => Messages, tools => [tool()], stream => false
  })),
  Headers = [{"authorization", "Bearer " ++ Key}],
  TLS = [{verify, verify_peer}, {cacerts, public_key:cacerts_get()},
    {customize_hostname_check, [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}],
  case httpc:request(post,
    {"https://ollama.com/api/chat", Headers, "application/json", Body},
    [{ssl, TLS}, {timeout, 120000}], [{body_format, binary}]) of
    {ok, {{_, 200, _}, _, Response}} ->
      case json:decode(Response) of
        #{<<"message">> := Message} -> {ok, Message};
        #{<<"error">> := Error} -> {error, Error}
      end;
    {ok, {{_, Status, _}, _, _}} -> {error, {http_status, Status}};
    {error, Reason} -> {error, Reason}
  end.

tool() ->
  #{type => <<"function">>, function => #{
    name => <<"run_eyg">>,
    description => <<"Run an EYG expression on the live counter application. "
      "Returns the evaluator's formatted value or diagnostics.">>,
    parameters => #{type => <<"object">>, required => [<<"source">>],
      properties => #{source => #{type => <<"string">>}}}
  }}.

call_tool(#{<<"function">> := #{<<"name">> := Name, <<"arguments">> := Args}}) ->
  Output = case {Name, Args} of
    {<<"run_eyg">>, #{<<"source">> := Source}} when is_binary(Source) ->
      io:format("eyg> ~ts~n", [Source]),
      try my_counters_script:run(Source)
      catch Class:Reason ->
        unicode:characters_to_binary(io_lib:format("Error: ~p:~p", [Class, Reason]))
      end;
    _ -> <<"Error: expected run_eyg with a string source argument.">>
  end,
  io:format("~ts~n", [Output]),
  #{role => <<"tool">>, tool_name => Name, content => Output}.

system_prompt() ->
  <<"You control a running BEAM counter application using the run_eyg tool. "
    "Always use the tool for actions and current values; never invent results. "
    "You are in a tool loop and may call again after seeing results. "
    "Keep replies to one short sentence. Only do what the user asks.\n"
    "EYG expressions available:\n"
    "perform StartCounter(\"demo\") starts a new named counter ticking every second.\n"
    "perform SetTickRate({name: \"demo\", seconds: 5}) changes its interval to a positive number of seconds.\n"
    "perform GetValue(\"demo\") reads a running counter's current integer value.\n"
    "perform Random(6) returns an integer from 1 to 6.\n"
    "perform Now({}) returns the current Unix timestamp in milliseconds.\n"
    "perform Log(\"hello\") prints a string and returns {}.\n"
    "!int_add(20, 22) returns 42.\n"
    "The perform keyword is mandatory for effects. StartCounter(\"demo\") "
    "without perform only constructs a value and does not start a counter. "
    "Use separate tool calls for separate actions. Counter processes persist "
    "between calls, but EYG variable bindings do not. "
    "These are the only available effects. There is no sleep effect.">>.
