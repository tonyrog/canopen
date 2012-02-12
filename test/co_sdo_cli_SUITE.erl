%%%-------------------------------------------------------------------
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2011, Marina Westman Lönne
%%% @doc
%%%
%%% @end
%%% Created : 29 Nov 2011 by Marina Westman Lönne <malotte@malotte.net>
%%%-------------------------------------------------------------------
-module(co_sdo_cli_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").



%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%%  Returns list of tuples to set default properties
%%  for the suite.
%%
%% Function: suite() -> Info
%%
%% Info = [tuple()]
%%   List of key/value pairs.
%%
%% Note: The suite/0 function is only meant to be used to return
%% default data values, not perform any other operations.
%%
%% @spec suite() -> Info
%% @end
%%--------------------------------------------------------------------
suite() ->
    [{timetrap,{minutes,10}},
     {require, serial},
     {require, cocli},
     {require, dict}].


%%--------------------------------------------------------------------
%% @doc
%%  Returns the list of groups and test cases that
%%  are to be executed.
%%
%% GroupsAndTestCases = [{group,GroupName} | TestCase]
%% GroupName = atom()
%%   Name of a test case group.
%% TestCase = atom()
%%   Name of a test case.
%% Reason = term()
%%   The reason for skipping all groups and test cases.
%%
%% @spec all() -> GroupsAndTestCases | {skip,Reason}
%% @end
%%--------------------------------------------------------------------
all() -> 
    [store_atomic_segment,
     fetch_atomic_segment,
     store_atomic_block,
     fetch_atomic_block,
     store_atomic_exp,
     fetch_atomic_exp,
     store_atomic_m_segment,
     fetch_atomic_m_segment,
     store_atomic_m_block,
     fetch_atomic_m_block,
     store_streamed_segment,
     fetch_streamed_segment,
     store_streamed_block,
     fetch_streamed_block,
     store_streamed_exp,
     fetch_streamed_exp,
     store_streamed_m_segment,
     fetch_streamed_m_segment,
     store_streamed_m_block,
     fetch_streamed_m_block].
%%     break].


%%--------------------------------------------------------------------
%% @doc
%% Returns a list of test case group definitions.
%%
%% Group = {GroupName,Properties,GroupsAndTestCases}
%% GroupName = atom()
%%   The name of the group.
%% Properties = [parallel | sequence | Shuffle | {RepeatType,N}]
%%   Group properties that may be combined.
%% GroupsAndTestCases = [Group | {group,GroupName} | TestCase]
%% TestCase = atom()
%%   The name of a test case.
%% Shuffle = shuffle | {shuffle,Seed}
%%   To get cases executed in random order.
%% Seed = {integer(),integer(),integer()}
%% RepeatType = repeat | repeat_until_all_ok | repeat_until_all_fail |
%%              repeat_until_any_ok | repeat_until_any_fail
%%   To get execution of cases repeated.
%% N = integer() | forever
%%
%% @spec: groups() -> [Group]
%% @end
%%--------------------------------------------------------------------
groups() ->
    [].


%%--------------------------------------------------------------------
%% @doc
%% Initialization before the whole suite
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the suite.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%
%% @spec init_per_suite(Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    co_test_lib:start_node(),
    co_test_lib:load_dict(Config),
    {ok, _Mgr} = co_mgr:start(),
    ct:pal("Started co_mgr"),
    Config.

%%--------------------------------------------------------------------
%% @doc
%% Cleanup after the whole suite
%%
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% @spec end_per_suite(Config) -> _
%% @end
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    co_node:stop(serial()),
    co_mgr:stop(),
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Initialization before each test case
%%
%% TestCase - atom()
%%   Name of the test case that is about to be run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the test case.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%
%% @spec init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
init_per_testcase(Case, Config) when Case == store_atomic_segment;
				     Case == fetch_atomic_segment;
				     Case == store_atomic_block;
				     Case == fetch_atomic_block;
				     Case == store_atomic_exp;
				     Case == fetch_atomic_exp;
				     Case == store_streamed_segment;
				     Case == fetch_streamed_segment;
				     Case == store_streamed_block;
				     Case == fetch_streamed_block;
				     Case == store_streamed_exp;
				     Case == fetch_streamed_exp;
				     Case == store_atomic_m_segment;
				     Case == fetch_atomic_m_segment;
				     Case == store_atomic_m_block;
				     Case == fetch_atomic_m_block;
				     Case == store_streamed_m_segment;
				     Case == fetch_streamed_m_segment;
				     Case == store_streamed_m_block;
				     Case == fetch_streamed_m_block;
				     Case == break ->
    ct:pal("Testcase: ~p", [Case]),
    {ok, _Pid} = co_test_app:start(serial(), app_dict()),
    {ok, Cli} = co_test_app:start({name, co_mgr}, app_dict_cli()),
    [{app, Cli} | Config];
init_per_testcase(_TestCase, Config) ->
    ct:pal("Testcase: ~p", [_TestCase]),
    Config.


%%--------------------------------------------------------------------
%% @doc
%% Cleanup after each test case
%%
%% TestCase - atom()
%%   Name of the test case that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% @spec end_per_testcase(TestCase, Config0) ->
%%               void() | {save_config,Config1} | {fail,Reason}
%% @end
%%--------------------------------------------------------------------
end_per_testcase(Case, _Config) when Case == store_atomic_segment;
				     Case == fetch_atomic_segment;
				     Case == store_atomic_block;
				     Case == fetch_atomic_block;
				     Case == store_atomic_exp;
				     Case == fetch_atomic_exp;
				     Case == store_streamed_segment;
				     Case == fetch_streamed_segment;
				     Case == store_streamed_block;
				     Case == fetch_streamed_block;
				     Case == store_streamed_exp;
				     Case == fetch_streamed_exp;
				     Case == store_atomic_m_segment;
				     Case == fetch_atomic_m_segment;
				     Case == store_atomic_m_block;
				     Case == fetch_atomic_m_block;
				     Case == store_streamed_m_segment;
				     Case == fetch_streamed_m_segment;
				     Case == store_streamed_m_block;
				     Case == fetch_streamed_m_block;
				     Case == break ->
    %% Wait a little for session to terminate
    timer:sleep(1000),
    co_test_lib:stop_app(co_test_app, serial()),
    co_test_lib:stop_app(co_test_app, co_mgr),
    ok;
end_per_testcase(_TestCase, _Config) ->
    ok.
%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @spec store_atomic_segment(Config) -> ok 
%% @doc 
%% Sets a value using segment between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
store_atomic_segment(Config) ->
    store(Config, ct:get_config({dict, atomic}), segment).

%%--------------------------------------------------------------------
%% @spec fetch_atomic_segment(Config) -> ok 
%% @doc 
%% Fetches a value using segment between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
fetch_atomic_segment(Config) ->
    fetch(Config, ct:get_config({dict, atomic}), segment).

%%--------------------------------------------------------------------
%% @spec store_atomic_block(Config) -> ok 
%% @doc 
%% Stores a value using block between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
store_atomic_block(Config) ->
    store(Config, ct:get_config({dict, atomic}), block).

%%--------------------------------------------------------------------
%% @spec fetch_atomic_block(Config) -> ok 
%% @doc 
%% Fetches a value using block between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
fetch_atomic_block(Config) ->
    fetch(Config, ct:get_config({dict, atomic}), block).


%%--------------------------------------------------------------------
%% @spec store_atomic_exp(Config) -> ok 
%% @doc 
%% Stores a short value using segment between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
store_atomic_exp(Config) ->
    store(Config, ct:get_config({dict, atomic_exp}), segment).

%%--------------------------------------------------------------------
%% @spec fetch_atomic_exp(Config) -> ok 
%% @doc 
%% Fetches a short value using segment between cocli and co_node and atomic 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
fetch_atomic_exp(Config) ->
    fetch(Config, ct:get_config({dict, atomic_exp}), segment).


%%--------------------------------------------------------------------
%% @spec store_streamed_segment(Config) -> ok 
%% @doc 
%% Stores a value using segment between cocli and co_node and streamed 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
store_streamed_segment(Config) ->
    store(Config, ct:get_config({dict, streamed}), segment).

%%--------------------------------------------------------------------
%% @spec fetch_streamed_segment(Config) -> ok 
%% @doc 
%% Fetches a value using segment between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
fetch_streamed_segment(Config) ->
    fetch(Config, ct:get_config({dict, streamed}), segment).

%%--------------------------------------------------------------------
%% @spec store_streamed_block(Config) -> ok 
%% @doc 
%% Stores a value using block between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
store_streamed_block(Config) ->
    store(Config, ct:get_config({dict, streamed}), block).

%%--------------------------------------------------------------------
%% @spec fetch_streamed_block(Config) -> ok 
%% @doc 
%% Fetches a value using block between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
fetch_streamed_block(Config) ->
    fetch(Config, ct:get_config({dict, streamed}), block).

%%--------------------------------------------------------------------
%% @spec store_streamed_exp(Config) -> ok 
%% @doc 
%% Stores a short value using segment between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
store_streamed_exp(Config) ->
    store(Config, ct:get_config({dict, streamed_exp}), segment).

%%--------------------------------------------------------------------
%% @spec fetch_streamed_exp(Config) -> ok 
%% @doc 
%% Fetches a short value using segment between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
fetch_streamed_exp(Config) ->
    fetch(Config, ct:get_config({dict, streamed_exp}), segment).

%%--------------------------------------------------------------------
%% @spec store_atomic_m_segment(Config) -> ok 
%% @doc 
%% Stores a value using segment between cocli and co_node and {atomic, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
store_atomic_m_segment(Config) ->
    store(Config, ct:get_config({dict, atomic_m}), segment).

%%--------------------------------------------------------------------
%% @spec fetch_atomic_m_segment(Config) -> ok 
%% @doc 
%% Fetches a value using segment between cocli and co_node and {atomic, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
fetch_atomic_m_segment(Config) ->
    fetch(Config, ct:get_config({dict, atomic_m}), segment).

%%--------------------------------------------------------------------
%% @spec store_atomic_m_block(Config) -> ok 
%% @doc 
%% Stores a value using segment between cocli and co_node and {atomic, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
store_atomic_m_block(Config) ->
    store(Config, ct:get_config({dict, atomic_m}), block).

%%--------------------------------------------------------------------
%% @spec fetch_atomic_m_block(Config) -> ok 
%% @doc 
%% Fetches a value using segment between cocli and co_node and {atomic, Module} 
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
fetch_atomic_m_block(Config) ->
    fetch(Config, ct:get_config({dict, atomic_m}), block).

%%--------------------------------------------------------------------
%% @spec store_streamed_m_segment(Config) -> ok 
%% @doc 
%% Stores a value using segment between cocli and co_node and {streamed, Module}
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
store_streamed_m_segment(Config) ->
    store(Config, ct:get_config({dict, streamed_m}), segment).

%%--------------------------------------------------------------------
%% @spec fetch_streamed_m_segment(Config) -> ok 
%% @doc 
%% Fetches a value using segment between cocli and co_node and {streamed, Module}
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
fetch_streamed_m_segment(Config) ->
    fetch(Config, ct:get_config({dict, streamed_m}), segment).

%%--------------------------------------------------------------------
%% @spec store_streamed_m_block(Config) -> ok 
%% @doc 
%% Stores a value using block between cocli and co_node and {streamed, Module}
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
store_streamed_m_block(Config) ->
    store(Config, ct:get_config({dict, streamed_m}), block).

%%--------------------------------------------------------------------
%% @spec fetch_streamed_m_block(Config) -> ok 
%% @doc 
%% Fetches a value using block between cocli and co_node and {streamed, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
fetch_streamed_m_block(Config) ->
    fetch(Config, ct:get_config({dict, streamed_m}), block).


%%--------------------------------------------------------------------
%% @spec break(Config) -> ok 
%% @doc 
%% Dummy test case to have a test environment running.
%% Stores Config in ets table.
%% @end
%%--------------------------------------------------------------------
break(Config) ->
    ets:new(conf, [set, public, named_table]),
    ets:insert(conf, Config),
    test_server:break("Break for test development\n" ++
		     "Get Config by ets:tab2list(conf≈ß)"),
    ok.

%%--------------------------------------------------------------------
%% Help functions
%%--------------------------------------------------------------------
serial() -> co_test_lib:serial().
app_dict() -> co_test_lib:app_dict().
app_dict_cli() -> co_test_lib:app_dict_cli().
%%--------------------------------------------------------------------
%% @spec store(Config, {Entry, _NewValue}, BlockOrSegment) -> ok 
%% @doc 
%% Stores a value using BlockOrSegment between co_mgr and co_node.
%% Transfer mode is defined by application based on index.
%% Fetches the old value from the apps dictionary.
%% Stores a new value and compares it.
%% @end
%%--------------------------------------------------------------------
store(Config, {{Index, _T, _M, SrvValue}, CliValue}, BlockOrSegment) ->
    %% Verify old value
    {Index, _Type, _Transfer, SrvValue} = 
	lists:keyfind(Index, 1, co_test_app:dict(serial())),
							
    %% Change to new
    ok = store_cmd(Config, Index, BlockOrSegment),
    {Index, _Type, _Transfer, CliValue} = 
	lists:keyfind(Index, 1, co_test_app:dict(serial())),
    
    ok.
   


%%--------------------------------------------------------------------
%% @spec fetch(Config, {Entry, _NewValue}, BlockOrSegment) -> ok 
%% @doc 
%% Fetches a value using BlockOrSegment between co_mgr and co_node.
%% Transfer mode is defined by application based on index.
%% Fetches the value using cocli and compares it with the value retrieved
%% from the apps dictionary.
%% @end
%%--------------------------------------------------------------------
fetch(Config, {{Index, _T, _M, SrvValue}, CliValue}, BlockOrSegment) ->
    %% Verify old value
    {Index, _Type, _Transfer, CliValue} = 
	lists:keyfind(Index, 1, co_test_app:dict({name, co_mgr})),

    %% Change to new
    ok = fetch_cmd(Config, Index, BlockOrSegment),
    {Index, _Type, _Transfer, SrvValue} = 
	lists:keyfind(Index, 1, co_test_app:dict({name, co_mgr})),

    ok.

nodeid() ->
    {ext_nodeid, NodeId} = co_node:get_option(serial(), ext_nodeid),
    NodeId.

store_cmd(Config, {Ix, Si}, BlockOrSegment) -> 
    co_mgr:store(nodeid(), Ix, Si, BlockOrSegment, 
		 {app, ?config(app, Config), co_test_app}).

fetch_cmd(Config, {Ix, Si}, BlockOrSegment) ->
    co_mgr:fetch(nodeid(), Ix, Si, BlockOrSegment, 
		 {app, ?config(app, Config), co_test_app}).
    
