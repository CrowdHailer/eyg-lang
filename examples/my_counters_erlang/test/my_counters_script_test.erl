-module(my_counters_script_test).
-include_lib("eunit/include/eunit.hrl").
-include_lib("eyg_hub/include/eyg@hub@cache_Cache.hrl").
-include_lib("eyg_hub/include/eyg@hub@cache_Entry.hrl").

pure_expression_test() ->
  ?assertEqual(<<"42">>, my_counters_script:run("!int_add(20, 22)")).

release_forms_test() ->
  {Cache, First, Second} = fixture(),
  ?assertEqual(<<"42">>, my_counters_script:run(<<"@fixture">>, Cache)),
  ?assertEqual(<<"41">>, my_counters_script:run(<<"@fixture:1">>, Cache)),
  Pin = multiformats@cid@v1:to_string(Second),
  ?assertEqual(<<"42">>, my_counters_script:run(<<"@fixture:2:", Pin/binary>>, Cache)),
  Content = multiformats@cid@v1:to_string(First),
  ?assertEqual(<<"41">>, my_counters_script:run(<<"#", Content/binary>>, Cache)).

reference_resumes_evaluation_test() ->
  {Cache, _, _} = fixture(),
  ?assertEqual(<<"43">>, my_counters_script:run("!int_add(@fixture, 1)", Cache)),
  ?assertEqual(<<"42">>, my_counters_script:run(
    "let _ = perform Log(\"\") @fixture", Cache
  )).

transitive_dependency_test() ->
  {Cache0, First, _} = fixture(),
  Child = multiformats@cid@v1:to_string(First),
  {Cache1, Parent} = add_module(Cache0, <<"!int_add(#", Child/binary, ", 1)">>),
  Reference = multiformats@cid@v1:to_string(Parent),
  ?assertEqual(<<"42">>, my_counters_script:run(<<"#", Reference/binary>>, Cache1)).

wrong_release_pin_test() ->
  {Cache, First, _} = fixture(),
  Wrong = multiformats@cid@v1:to_string(First),
  ?assertMatch(<<"error:", _/binary>>, my_counters_script:run(
    <<"@fixture:2:", Wrong/binary>>, Cache
  )).

dependency_type_error_prevents_effects_test() ->
  {Cache, _, _} = fixture(),
  Name = release_type_error_counter,
  ?assertEqual(undefined, whereis(Name)),
  Code = <<"let _ = perform StartCounter(\"release_type_error_counter\") "
    "!int_add(@fixture, \"bad\")">>,
  ?assertMatch(<<"error:", _/binary>>, my_counters_script:run(Code, Cache)),
  ?assertEqual(undefined, whereis(Name)).

relative_import_is_not_a_hub_dependency_test() ->
  ?assertMatch(<<"error:", _/binary>>, my_counters_script:run("import \"./missing.eyg\"")).

fixture() ->
  {Cache0, First} = add_module(eyg@hub@cache:empty(), <<"41">>),
  {Cache1, Second} = add_module(Cache0, <<"42">>),
  Cache2 = Cache1#cache{
    releases = #{{<<"fixture">>, 1} => First, {<<"fixture">>, 2} => Second},
    packages = #{<<"fixture">> => #entry{
      version = 2, module = Second, cursor = 2, sequence = 2, cid = Second
    }}
  },
  {Cache2, First, Second}.

add_module(Cache0, Code) ->
  {ok, Source} = eyg@parser:all_from_string(Code),
  Digest = crypto:hash(sha256, eyg@ir@dag_json:to_block(Source)),
  Cid = {cid, dag_json:code(), {multihash, sha256, Digest}},
  {Cache1, _} = eyg@hub@cache:fetch_module_completed(Cache0, Cid, {ok, Source}),
  {Cache1, Cid}.
