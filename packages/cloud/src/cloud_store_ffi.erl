-module(cloud_store_ffi).
-export([atomic_write/2]).

atomic_write(Path, Bytes) ->
    Temp = <<Path/binary, ".tmp">>,
    Result = case file:open(Temp, [write, binary, raw]) of
        {ok, File} ->
            Written = case file:write(File, Bytes) of
                ok -> file:sync(File);
                Error -> Error
            end,
            Closed = file:close(File),
            case {Written, Closed} of
                {ok, ok} -> file:rename(Temp, Path);
                {{error, Reason}, _} -> {error, Reason};
                {_, {error, Reason}} -> {error, Reason}
            end;
        Error -> Error
    end,
    case Result of
        ok -> {ok, nil};
        {error, Reason0} -> {error, list_to_binary(file:format_error(Reason0))}
    end.
