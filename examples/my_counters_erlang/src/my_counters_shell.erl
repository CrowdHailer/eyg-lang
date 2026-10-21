-module(my_counters_shell).
-export([start/0]).

start() ->
  {ok, _} = application:ensure_all_started(my_counters),
  spawn(fun loop/0).

loop() ->
  case io:get_line("eyg> ") of
    eof ->
      ok;
    {error, _} ->
      ok;
    Line ->
      case string:trim(Line) of
        ":quit" -> ok;
        "" -> loop();
        Source ->
          io:put_chars(my_counters_script:run(Source)),
          loop()
      end
  end.
