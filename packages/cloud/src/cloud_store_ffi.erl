-module(cloud_store_ffi).
-export([new/0, insert/3, lookup/2, size/1]).

new() ->
    ets:new(cloud_blocks, [set, public, {read_concurrency, true}]).

insert(Table, Key, Block) ->
    ets:insert_new(Table, {Key, Block}),
    nil.

lookup(Table, Key) ->
    case ets:lookup(Table, Key) of
        [{_, Block}] -> {ok, Block};
        [] -> {error, nil}
    end.

size(Table) ->
    ets:info(Table, size).
