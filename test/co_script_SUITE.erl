%%%-------------------------------------------------------------------
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2011, Marina Westman Lönne
%%% @doc
%%%
%%% Created : 27 March by Marina Westman Lönne 
%%% @end
%%%-------------------------------------------------------------------
-module(co_script_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include("canopen.hrl").

-define(SCRIPT1, 'test1.script').

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
    [require,
     fetch_store,
     script].
%%     break].


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
    put(dbg,true), %% Enable trace
    co_test_lib:start_node(Config),
    {ok, _Mgr} = co_mgr:start([{linked, false}, {debug, true}]),
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
end_per_suite(Config) ->
    co_mgr:stop(),
    co_test_lib:stop_node(Config),
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
end_per_testcase(_TestCase, _Config) ->
    ok.
%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @spec require(Config) -> ok 
%% @doc 
%% Requires the manager to load a definition file
%% @end
%%--------------------------------------------------------------------
require(_Config) ->
    ok = co_mgr:client_require(canopen),
    ok.

%%--------------------------------------------------------------------
%% @spec fetch_store(Config) -> ok 
%% @doc 
%% Fetches cobid_time_stamp, changes it and restores it.
%% @end
%%--------------------------------------------------------------------
fetch_store(_Config) ->
    %% Fetch
    CTS = co_mgr:client_fetch(co_lib:serial_to_xnodeid(serial()),
			      cobid_time_stamp, 0),

    %% Change
    NewCTS = CTS + 1,
    ok = co_mgr:client_store(co_lib:serial_to_xnodeid(serial()),
			     cobid_time_stamp, 0, NewCTS),

    %% Verify change
    NewCTS = co_mgr:client_fetch(co_lib:serial_to_xnodeid(serial()),
				 cobid_time_stamp, 0),

    %% Restore
    ok = co_mgr:client_store(co_lib:serial_to_xnodeid(serial()),
			     cobid_time_stamp, 0, CTS),

    %% Verify restore
    CTS = co_mgr:client_fetch(co_lib:serial_to_xnodeid(serial()),
			      cobid_time_stamp, 0),

    ok.

%%--------------------------------------------------------------------
%% @spec script(Config) -> ok 
%% @doc 
%% Runs a script 
%% @end
%%--------------------------------------------------------------------
script(Config) ->
    DataDir = ?config(data_dir, Config),

    %% Using file instead of run/script to avoid halt of node
    ok = co_script:file([filename:join(DataDir, ?SCRIPT1)]),
    ok.

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
		     "Get Config by ets:tab2list(conf)"),
    ok.

%%--------------------------------------------------------------------
%% Help functions
%%--------------------------------------------------------------------
serial() -> co_test_lib:serial().
