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
                {ok, ok} -> publish(Temp, Path);
                {{error, Reason}, _} -> {error, Reason};
                {_, {error, Reason}} -> {error, Reason}
            end;
        Error -> Error
    end,
    case Result of
        ok -> {ok, nil};
        {error, Reason0} -> {error, list_to_binary(file:format_error(Reason0))}
    end.

publish(Temp, Path) ->
    %% Open and sync the directory before replacing anything, so unsupported
    %% filesystems fail without changing the published snapshot.
    case file:open(filename:dirname(Path), [read, raw, directory]) of
        {ok, Directory} ->
            Result = case file:sync(Directory) of
                ok ->
                    case file:rename(Temp, Path) of
                        ok ->
                            case file:sync(Directory) of
                                ok -> ok;
                                {error, Reason} ->
                                    %% The rename happened. Continuing with the
                                    %% old in-memory root would be inconsistent;
                                    %% fail the owner and recover from disk.
                                    erlang:error({publication_sync_failed, Reason})
                            end;
                        Error -> Error
                    end;
                Error -> Error
            end,
            file:close(Directory),
            Result;
        Error -> Error
    end.
