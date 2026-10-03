%% Hub protocol, CID verification and dependency resolution are existing Gleam
%% APIs. Erlang supplies the HTTP/hash callbacks and drives the cache actions.
-module(counters_packages).

-export([prepare/2, prepare/5]).

-define(CACHE, eyg@hub@cache).
-define(INFER, eyg@analysis@inference@levels_j@contextual).

%% Both check and run call this after parsing. Already loaded references, and
%% scripts without references, need neither HTTP nor a configured hub origin.
prepare(Tree, Cache) ->
    References = eyg@ir@tree:list_references(Tree),
    case available(References, Cache) of
        ok -> {ok, Cache};
        {error, _} ->
            Url = application:get_env(erl_counter, hub, <<"https://eyg.run">>),
            case ogre@origin:from_string(unicode:characters_to_binary(Url)) of
                {ok, Origin} ->
                    Fetch = application:get_env(erl_counter, package_fetch, fun http/1),
                    prepare(Tree, Cache, Origin, Fetch, fun hash/2);
                {error, _} -> {error, <<"invalid hub origin">>}
            end
    end.

%% Explicit callbacks also let tests use the real hub codecs without a network.
prepare(Tree, Cache, Origin, Fetch, Hash) ->
    References = eyg@ir@tree:list_references(Tree),
    %% prepare queues content/pinned modules and any missing release mappings.
    case drain(?CACHE:prepare(Cache, Tree), Origin, Fetch, Hash, []) of
        {ok, Cache1, Trees1} ->
            %% Once the ledger is available, queue modules named by packages and
            %% versions too: cache.prepare doesn't queue these itself.
            case queue(References, Cache1) of
                {ok, Cache2} ->
                    case drain(Cache2, Origin, Fetch, Hash, Trees1) of
                        {ok, Loaded, Sources} ->
                            case available(References, Loaded) of
                                ok -> validate(Sources, Loaded);
                                Error -> Error
                            end;
                        Error -> Error
                    end;
                Error -> Error
            end;
        Error -> Error
    end.

queue([], Cache) -> {ok, Cache};
queue([Reference | Rest], Cache) ->
    case module_cid(Reference, Cache) of
        {ok, Cid} -> queue(Rest, ?CACHE:fetch(Cache, Cid));
        Error -> Error
    end.

module_cid({content, Cid}, _Cache) -> {ok, Cid};
module_cid({package, Name}, Cache) ->
    case ?CACHE:package(Cache, Name) of
        {ok, {entry, _Version, Cid, _Cursor, _Sequence, _EntryCid}} -> {ok, Cid};
        {error, nil} -> {error, <<"package not found: ", Name/binary>>}
    end;
module_cid({version, Name, Version}, Cache) ->
    case ?CACHE:unbound_release(Cache, Name, Version) of
        {ok, Cid} -> {ok, Cid};
        {error, nil} -> missing({version, Name, Version})
    end;
module_cid({pinned, {release, Name, Version, Cid}} = Reference, Cache) ->
    case ?CACHE:unbound_release(Cache, Name, Version) of
        {ok, Cid} -> {ok, Cid};
        _ -> missing(Reference)
    end;
module_cid({relative, Path}, _Cache) ->
    {error, <<"relative imports are not supported: ", Path/binary>>}.

available([], _Cache) -> ok;
available([Reference | Rest], Cache) ->
    case ?CACHE:get_reference(Cache, Reference) of
        {ok, _Module} -> available(Rest, Cache);
        {error, nil} -> missing(Reference)
    end.

missing(Reference) ->
    {error, eyg@analysis@type_@binding@debug:render_reason({missing_reference, Reference})}.

drain(Cache0, Origin, Fetch, Hash, Trees) ->
    {Cache1, Actions} = ?CACHE:flush(Cache0),
    case Actions of
        [] -> {ok, Cache1, Trees};
        _ ->
            case actions(Actions, Cache1, Origin, Fetch, Hash, Trees) of
                {ok, Cache2, Trees2} -> drain(Cache2, Origin, Fetch, Hash, Trees2);
                Error -> Error
            end
    end.

actions([], Cache, _Origin, _Fetch, _Hash, Trees) ->
    {ok, Cache, Trees};
actions([Action | Rest], Cache, Origin, Fetch, Hash, Trees) ->
    Task = ?CACHE:compute(Action, Origin, Fetch, Hash),
    Completed = Task(fun(Result) -> Result end),
    case Completed of
        {pull_packages_completed, {error, Reason}} -> {error, Reason};
        {fetch_module_completed, _Cid, {error, Reason}} -> {error, Reason};
        _ ->
            {Next, Resolved} = ?CACHE:update(Cache, Completed, fun(_) -> {0, 0} end),
            case [Reason || {_Cid, {error, Reason}} <- Resolved] of
                [Reason | _] -> {error, eyg@interpreter@simple_debug:describe(Reason)};
                [] ->
                    Sources = case Completed of
                        {fetch_module_completed, _, {ok, Tree}} -> [Tree | Trees];
                        _ -> Trees
                    end,
                    actions(Rest, Next, Origin, Fetch, Hash, Sources)
            end
    end.

%% The existing cache infers module types but doesn't reject inference errors.
%% Check every downloaded module once its dependencies are available, before
%% exposing the cache to scripts. Cache evaluation itself handles no host effects.
validate([], Cache) -> {ok, Cache};
validate([Tree | Rest], Cache) ->
    Analysis = ?CACHE:infer_sync(?INFER:check(?INFER:pure(), Tree), Cache),
    case ?INFER:all_errors(Analysis) of
        [] -> validate(Rest, Cache);
        [{_Meta, Reason} | _] ->
            Message = eyg@analysis@type_@binding@debug:render_reason(Reason),
            {error, <<"invalid package module: ", Message/binary>>}
    end.

http(Request) ->
    fun(K) ->
        Result = case gleam@httpc:send_bits(Request) of
            {ok, Response} -> {ok, Response};
            {error, Reason} ->
                Text = unicode:characters_to_binary(io_lib:format("~p", [Reason])),
                {error, {network_error, Text}}
        end,
        K(Result)
    end.

hash(Algorithm, Bytes) ->
    fun(K) -> K(gleam@crypto:hash(Algorithm, Bytes)) end.
