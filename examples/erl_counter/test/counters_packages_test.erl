-module(counters_packages_test).
-include_lib("eunit/include/eunit.hrl").

automatic_loading_test_() ->
    {setup,
        fun() -> {ok, Apps} = application:ensure_all_started(erl_counter), Apps end,
        fun(Apps) -> [application:stop(App) || App <- lists:reverse(Apps)] end,
        [
            fun check_fetches_and_run_reuses/0,
            fun run_fetches_without_check/0,
            fun arbitrary_packages_are_reference_driven/0,
            fun fetch_failures_prevent_effects/0,
            fun automatic_reference_forms/0,
            fun failed_load_preserves_cache/0,
            fun no_fetch_for_local_or_unparsed_code/0,
            fun bad_script_with_loaded_package_has_no_effects/0,
            fun runtime_failure_returns_cache/0,
            fun caller_can_keep_independent_caches/0,
            fun session_retains_cache/0
        ]}.

check_fetches_and_run_reuses() ->
    with_hub(standard(), [], normal, fun() ->
        Source = "@standard.list.map([\"checked\"], (name) -> { perform StartCounter(name) })",
        {{ok, _Type}, Cache1} = counters_eyg:check(Source),
        ?assertEqual([], supervisor:which_children(counters_sup)),
        ?assertEqual(4, length(get(requests))),
        {{ok, {linked_list, [_]}}, Cache2} = counters_eyg:run(Source, Cache1),
        {{ok, _}, Cache3} = counters_eyg:check(Source, Cache2),
        ?assertEqual(Cache1, Cache3),
        ?assertEqual(4, length(get(requests))),
        ok = counters_api:shutdown(<<"checked">>)
    end).

run_fetches_without_check() ->
    with_hub(standard(), [], normal, fun() ->
        Source = "@standard.list.map([\"run-only\"], (name) -> { perform StartCounter(name) })",
        {{ok, {linked_list, [_]}}, Cache} = counters_eyg:run(Source),
        ?assertEqual({{ok, {linked_list, [{integer, 1}]}}, Cache},
            counters_eyg:run("@standard.list.map([1], (x) -> { x })", Cache)),
        ?assertEqual(4, length(get(requests))),
        ?assertEqual({ok, 0}, counters_api:get_value(<<"run-only">>)),
        ok = counters_api:shutdown(<<"run-only">>)
    end).

arbitrary_packages_are_reference_driven() ->
    Child = parse(<<"11">>),
    Prices = parse(<<"#", (cid_string(cid(Child)))/binary>>),
    Taxes = parse(<<"7">>),
    Unused = parse(<<"99">>),
    Entries = [
        entry(<<"prices">>, 1, 1, cid(Prices)),
        entry(<<"taxes">>, 1, 2, cid(Taxes)),
        entry(<<"standard">>, 1, 3, cid(Unused))
    ],
    Fetch = hub_fixture(Entries, [Prices, Child, Taxes, Unused], normal),
    Source = "!int_add(@prices, @taxes)",
    %% First check one package, then introduce a second via run. The existing
    %% cache must be extended rather than replaced with a particular package.
    with_hub(Fetch, fun() ->
        {{ok, <<"Integer">>}, Cache1} = counters_eyg:check("@prices"),
        {{ok, {integer, 18}}, Cache2} = counters_eyg:run(Source, Cache1),
        assert_fetched_modules([Prices, Child, Taxes]),
        Before = length(get(requests)),
        ?assertEqual({{ok, <<"Integer">>}, Cache2}, counters_eyg:check(Source, Cache2)),
        ?assertEqual({{ok, {integer, 11}}, Cache2}, counters_eyg:run("@prices", Cache2)),
        ?assertEqual(Before, length(get(requests)))
    end),
    %% Both entry points also discover all the names from a cold cache.
    with_hub(Fetch, fun() ->
        ?assertMatch({{ok, <<"Integer">>}, _}, counters_eyg:check(Source)),
        assert_fetched_modules([Prices, Child, Taxes])
    end),
    with_hub(Fetch, fun() ->
        ?assertMatch({{ok, {integer, 18}}, _}, counters_eyg:run(Source)),
        assert_fetched_modules([Prices, Child, Taxes])
    end).

assert_fetched_modules(Trees) ->
    Urls = [gleam@uri:to_string(gleam@http@request:to_uri(Request))
        || Request <- get(requests)],
    Actual = [Cid || <<"https://hub.test/modules/", Cid/binary>> <- Urls],
    Expected = [cid_string(cid(Tree)) || Tree <- Trees],
    ?assertEqual(lists:sort(Expected), lists:sort(Actual)).

fetch_failures_prevent_effects() ->
    lists:foreach(fun(Mode) ->
        with_hub(parse(<<"42">>), [], Mode, fun() ->
            Source = "let _ = perform StartCounter(\"unfetched\")\n@standard",
            {{error, _}, CheckCache} = counters_eyg:check(Source),
            {{error, _}, RunCache} = counters_eyg:run(Source),
            ?assertEqual(eyg@hub@cache:empty(), CheckCache),
            ?assertEqual(eyg@hub@cache:empty(), RunCache),
            ?assertEqual({error, not_found}, counters_api:get_value(<<"unfetched">>))
        end)
    end, [network_failure, corrupt, missing_module, missing_package]).

automatic_reference_forms() ->
    Child = parse(<<"42">>),
    Root = parse(<<"#", (cid_string(cid(Child)))/binary>>),
    RootCid = cid_string(cid(Root)),
    with_hub(Root, [Child, parse(<<"0">>)], normal, fun() ->
        Sources = [
            {<<"@standard">>, 42},
            {<<"@standard:2">>, 42},
            {<<"@standard:2:", RootCid/binary>>, 42},
            {<<"#", RootCid/binary>>, 42},
            {<<"@standard:1">>, 0},
            {<<"!int_add(@standard:1, @standard)">>, 42}
        ],
        lists:foreach(fun({Source, Value}) ->
            %% Each call starts from an empty explicit cache.
            ?assertMatch({{ok, <<"Integer">>}, _}, counters_eyg:check(Source, eyg@hub@cache:empty())),
            ?assertMatch({{ok, {integer, Value}}, _}, counters_eyg:run(Source, eyg@hub@cache:empty()))
        end, Sources),
        put(requests, []),
        ?assertMatch({{ok, {integer, 42}}, _}, counters_eyg:run(<<"#", RootCid/binary>>)),
        %% A content reference and its content dependency do not need a ledger.
        ?assertEqual(2, length(get(requests)))
    end).

failed_load_preserves_cache() ->
    with_hub(parse(<<"42">>), [], normal, fun() ->
        {{ok, <<"Integer">>}, Cache1} = counters_eyg:check("@standard"),
        Before = length(get(requests)),
        {{error, _}, Cache2} = counters_eyg:check("@missing", Cache1),
        ?assertEqual(Cache1, Cache2),
        ?assert(length(get(requests)) > Before),
        After = length(get(requests)),
        ?assertEqual({{ok, {integer, 42}}, Cache2}, counters_eyg:run("@standard", Cache2)),
        {{error, _}, Cache3} = counters_eyg:run("@missing", Cache2),
        ?assertEqual(Cache2, Cache3),
        %% run's failed load must also leave a cache the caller can reuse.
        AfterRun = length(get(requests)),
        ?assertEqual({{ok, <<"Integer">>}, Cache3}, counters_eyg:check("@standard", Cache3)),
        ?assertEqual(AfterRun, length(get(requests))),
        ?assert(AfterRun > After)
    end).

no_fetch_for_local_or_unparsed_code() ->
    with_hub(parse(<<"42">>), [], network_failure, fun() ->
        Empty = eyg@hub@cache:empty(),
        ?assertEqual({{ok, <<"Integer">>}, Empty}, counters_eyg:check("1")),
        ?assertEqual({{ok, {integer, 1}}, Empty}, counters_eyg:run("1")),
        ?assertMatch({{error, _}, Empty}, counters_eyg:check("@standard.list.map(")),
        ?assertMatch({{error, _}, Empty}, counters_eyg:run("@standard.list.map(")),
        ?assertEqual([], get(requests))
    end).

bad_script_with_loaded_package_has_no_effects() ->
    with_hub(parse(<<"42">>), [], normal, fun() ->
        Source = "let _ = perform StartCounter(\"ill-typed\")\n!int_add(@standard, \"bad\")",
        {{error, _}, Cache} = counters_eyg:run(Source),
        ?assertEqual(4, length(get(requests))),
        ?assertEqual({error, not_found}, counters_api:get_value(<<"ill-typed">>)),
        ?assertEqual({{ok, {integer, 42}}, Cache}, counters_eyg:run("@standard", Cache)),
        {{error, _}, CheckCache} = counters_eyg:check(Source),
        ?assertEqual(Cache, CheckCache),
        Before = length(get(requests)),
        ?assertEqual({{ok, <<"Integer">>}, CheckCache}, counters_eyg:check("@standard", CheckCache)),
        %% Even parse errors return the caller's populated cache unchanged.
        ?assertMatch({{error, _}, CheckCache}, counters_eyg:check("{broken:", CheckCache)),
        ?assertMatch({{error, _}, CheckCache}, counters_eyg:run("{broken:", CheckCache)),
        ?assertEqual(Before, length(get(requests)))
    end).

runtime_failure_returns_cache() ->
    with_hub(parse(<<"42">>), [], normal, fun() ->
        {{ok, _}, Loaded} = counters_eyg:check("@standard"),
        %% Model an inconsistent host-supplied module: its type says Integer,
        %% but its value is a String. Checking succeeds and execution must fail.
        {cache, Modules, Fetching, Releases, Packages, Cursor, Status} = Loaded,
        WrongValues = maps:map(fun(_Cid, {module, _Value, Type}) ->
            {module, {string, <<"bad host value">>}, Type}
        end, Modules),
        Cache = {cache, WrongValues, Fetching, Releases, Packages, Cursor, Status},
        ?assertEqual({{ok, <<"Integer">>}, Cache},
            counters_eyg:check("!int_add(@standard, 1)", Cache)),
        {{error, Message}, Returned} = counters_eyg:run("!int_add(@standard, 1)", Cache),
        ?assertEqual(Cache, Returned),
        ?assertNotEqual(nomatch, binary:match(Message, <<"!int_add(@standard, 1)">>)),
        ?assertEqual(4, length(get(requests))),
        ?assertEqual({{ok, {integer, 1}}, Returned}, counters_eyg:run("1", Returned))
    end).

session_retains_cache() ->
    OldHub = application:get_env(erl_counter, hub),
    OldFetch = application:get_env(erl_counter, package_fetch),
    Count = atomics:new(1, []),
    Fetch = fixture(standard(), [], normal),
    application:set_env(erl_counter, hub, <<"https://hub.test">>),
    application:set_env(erl_counter, package_fetch, fun(Request) ->
        atomics:add(Count, 1, 1),
        Fetch(Request)
    end),
    {ok, Session} = counters_session:start_link(),
    try
        Reference = {package, <<"standard">>},
        Source = "@standard.list.map([\"session\"], (name) -> { perform StartCounter(name) })",
        ?assertEqual(false, counters_session:cached(Session, Reference)),
        ?assertMatch({ok, _}, counters_session:check(Session, Source)),
        ?assertEqual(true, counters_session:cached(Session, Reference)),
        ?assertEqual([], supervisor:which_children(counters_sup)),
        ?assertEqual(4, atomics:get(Count, 1)),
        ?assertMatch({ok, {linked_list, [_]}}, counters_session:run(Session, Source)),
        ?assertEqual({ok, 0}, counters_api:get_value(<<"session">>)),
        ?assertEqual(4, atomics:get(Count, 1)),
        ok = counters_api:shutdown(<<"session">>)
    after
        gen_server:stop(Session),
        restore_env(hub, OldHub),
        restore_env(package_fetch, OldFetch)
    end.

caller_can_keep_independent_caches() ->
    with_hub(parse(<<"42">>), [], normal, fun() ->
        Empty = eyg@hub@cache:empty(),
        {{ok, _}, Cache1} = counters_eyg:check("@standard", Empty),
        ?assertEqual(4, length(get(requests))),
        %% A separate caller passing its empty cache must not inherit Cache1.
        {{ok, {integer, 42}}, Cache2} = counters_eyg:run("@standard", Empty),
        ?assertEqual(8, length(get(requests))),
        ?assertEqual(Cache1, Cache2),
        ?assertEqual({{ok, <<"Integer">>}, Cache1}, counters_eyg:check("@standard", Cache1)),
        ?assertEqual(8, length(get(requests)))
    end).

with_hub(Root, Dependencies, Mode, Test) ->
    with_hub(fixture(Root, Dependencies, Mode), Test).

with_hub(Fetch, Test) ->
    OldHub = application:get_env(erl_counter, hub),
    OldFetch = application:get_env(erl_counter, package_fetch),
    application:set_env(erl_counter, hub, <<"https://hub.test">>),
    application:set_env(erl_counter, package_fetch, fun(Request) ->
        put(requests, [Request | get(requests)]),
        Fetch(Request)
    end),
    put(requests, []),
    try Test()
    after
        restore_env(hub, OldHub),
        restore_env(package_fetch, OldFetch),
        erase(requests)
    end.

restore_env(Key, {ok, Value}) -> application:set_env(erl_counter, Key, Value);
restore_env(Key, undefined) -> application:unset_env(erl_counter, Key).

standard() ->
    {ok, Json} = file:read_file("../../eyg_packages/standard/index.eyg.json"),
    {ok, Tree} = gleam@json:parse(Json, eyg@ir@dag_json:decoder(nil)),
    Tree.

standard_effects_test_() ->
    {setup,
        fun() -> {ok, Apps} = application:ensure_all_started(erl_counter), Apps end,
        fun(Apps) -> [application:stop(App) || App <- lists:reverse(Apps)] end,
        fun standard_effects/0}.

standard_effects() ->
    Tree = standard(),
    {ok, Cache} = load(Tree, [], normal),
    Source = "let _ = perform StartCounter(\"before\")\n"
             "let _ = @standard.list.map([\"a\", \"b\"], (name) -> {\n"
             "  perform StartCounter(name)\n"
             "})\n"
             "perform GetValue(\"a\")",
    ?assertMatch({{ok, _}, Cache}, counters_eyg:check(Source, Cache)),
    ?assertEqual([], supervisor:which_children(counters_sup)),
    ?assertEqual({{ok, {tagged, <<"Ok">>, {integer, 0}}}, Cache}, counters_eyg:run(Source, Cache)),
    ?assertEqual(3, length(supervisor:which_children(counters_sup))),
    [ok = counters_api:shutdown(Name) || Name <- [<<"before">>, <<"a">>, <<"b">>]].

dependencies_and_reference_forms_test() ->
    Child = parse(<<"42">>),
    ChildCid = cid(Child),
    Root = parse(<<"#", (cid_string(ChildCid))/binary>>),
    RootCid = cid(Root),
    {ok, Cache} = load(Root, [Child], normal),
    Sources = [
        <<"@standard">>,
        <<"@standard:2">>,
        <<"@standard:2:", (cid_string(RootCid))/binary>>,
        <<"#", (cid_string(RootCid))/binary>>
    ],
    [?assertEqual({{ok, {integer, 42}}, Cache}, counters_eyg:run(Source, Cache)) || Source <- Sources],
    WrongPin = <<"@standard:2:", (cid_string(ChildCid))/binary>>,
    ?assertMatch({{error, _}, Cache}, counters_eyg:run(WrongPin, Cache)).

wrong_cid_test() ->
    ?assertEqual({error, <<"hub returned module with the wrong cid.">>},
        load(parse(<<"42">>), [], corrupt)).

network_failure_test() ->
    ?assertMatch({error, _}, load(parse(<<"42">>), [], network_failure)).

missing_module_test() ->
    ?assertEqual({error, <<"no module">>}, load(parse(<<"42">>), [], missing_module)).

missing_package_test() ->
    ?assertEqual({error, <<"package not found: standard">>},
        load(parse(<<"42">>), [], missing_package)).

invalid_closure_test() ->
    %% Evaluation returns a closure, so inference must still reject its body.
    {error, Message} = load(parse(<<"(x) -> { !int_add(\"bad\", x) }">>), [], normal),
    ?assertMatch(<<"invalid package module: ", _/binary>>, Message).

impure_module_test() ->
    ?assertMatch({error, _}, load(parse(<<"perform StartCounter(\"no\")">>), [], normal)).

load(Root, Dependencies, Mode) ->
    counters_packages:prepare(parse(<<"@standard">>), eyg@hub@cache:empty(),
        ogre@origin:https(<<"hub.test">>),
        fixture(Root, Dependencies, Mode),
        fun(Algorithm, Bytes) -> fun(K) -> K(gleam@crypto:hash(Algorithm, Bytes)) end end).

fixture(Root, Dependencies, Mode) ->
    Entries = [
        entry(<<"standard">>, 1, 1, cid(parse(<<"0">>))),
        entry(<<"standard">>, 2, 2, cid(Root))
    ],
    hub_fixture(Entries, [Root | Dependencies], Mode).

hub_fixture(Entries, Trees, Mode) ->
    Modules = maps:from_list([
        {cid_string(cid(Tree)), eyg@ir@dag_json:to_block(Tree)}
        || Tree <- Trees
    ]),
    fun(Request) ->
        fun(K) -> K(response(Request, Entries, Modules, Mode)) end
    end.

response(_Request, _Entries, _Modules, network_failure) ->
    {error, {network_error, <<"offline">>}};
response(Request, Entries, Modules, Mode) ->
    Url = gleam@uri:to_string(gleam@http@request:to_uri(Request)),
    case Url of
        <<"https://hub.test/packages/pull", _/binary>> ->
            Since = case gleam@http@request:get_query(Request) of
                {ok, [{<<"since">>, Number}]} -> binary_to_integer(Number);
                _ -> 0
            end,
            Remaining = [Entry || {archived_entry, Cursor, _, _, _, _, _, _} = Entry <- Entries,
                Cursor > Since],
            Page = case {Mode, Remaining} of
                {missing_package, _} -> [];
                {_, [First | _]} -> [First];
                {_, []} -> []
            end,
            Json = untethered@ledger@schema:entries_response_encode(Page),
            {ok, {response, 200, [], gleam@json:to_string(Json)}};
        <<"https://hub.test/modules/", Cid/binary>> ->
            case Mode of
                missing_module -> {ok, {response, 204, [], <<>>}};
                corrupt -> {ok, {response, 200, [], eyg@ir@dag_json:to_block(parse(<<"99">>))}};
                _ ->
                    case maps:find(Cid, Modules) of
                        {ok, Body} -> {ok, {response, 200, [], Body}};
                        error -> {ok, {response, 204, [], <<>>}}
                    end
            end
    end.

entry(Name, Version, Cursor, ModuleCid) ->
    Identity = cid(parse(<<"0">>)),
    Entry = {entry, Version, none, Identity, <<"test-key">>,
        {release, Name, Version, ModuleCid}},
    Payload = gleam@json:to_string(eyg@hub@publisher:encode(Entry)),
    {archived_entry, Cursor, Identity, Payload, Identity, Version, none, <<"release">>}.

parse(Source) ->
    {ok, Tree} = eyg@parser:all_from_string(Source),
    Tree.

cid(Tree) ->
    Task = eyg@ir@cid:from_tree(Tree,
        fun(Bytes) -> fun(K) -> K(crypto:hash(sha256, Bytes)) end end),
    Task(fun(Value) -> Value end).

cid_string(Cid) -> multiformats@cid@v1:to_string(Cid).
