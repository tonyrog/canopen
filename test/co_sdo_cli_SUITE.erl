%%%---- BEGIN COPYRIGHT --------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2012, Rogvall Invest AB, <tony@rogvall.se>
%%%
%%% This software is licensed as described in the file COPYRIGHT, which
%%% you should have received as part of this distribution. The terms
%%% are also available at http://www.rogvall.se/docs/copyright.txt.
%%%
%%% You may opt to use, copy, modify, merge, publish, distribute and/or sell
%%% copies of the Software, and permit persons to whom the Software is
%%% furnished to do so, under the terms of the COPYRIGHT file.
%%%
%%% This software is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY
%%% KIND, either express or implied.
%%%
%%%---- END COPYRIGHT ----------------------------------------------------------
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
-include("../include/canopen.hrl").


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
     fetch_streamed_m_block,
     timeout,
     change_timeout].
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
    co_test_lib:start_system(),
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
    co_test_lib:stop_system(),
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
init_per_testcase(Case, Config) ->
    ct:pal("Testcase: ~p", [Case]),
    {ok, Pid} = co_test_app:start(serial(), app_dict()),
    ok = co_test_app:debug(Pid, true),
    {ok, Cli} = co_test_app:start(?MGR_NODE, app_dict_cli()),
    ok = co_test_app:debug(Cli, true),
    [{app, Cli} | Config].


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
end_per_testcase(_Case, _Config) ->
    %% Wait a little for session to terminate
    timer:sleep(1000),
    co_test_app:stop(serial()),
    co_test_app:stop(?MGR_NODE),
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
%% @spec timeout(Config) -> ok 
%% @doc 
%% Negative test of what happens if the storing causes a timeout.
%% @end
%%--------------------------------------------------------------------
timeout(Config) ->
    {{Index, _Type, _M, _SrvValue}, _CliValue} = ct:get_config({dict, timeout}),
							
    %% Timeout
    {error,timed_out} = store_cmd(Config, Index, segment).

%%--------------------------------------------------------------------
%% @spec change_timeout(Config) -> ok 
%% @doc 
%% A test of giving a longer timeout and changing timeout on 
%% application side.
%% @end
%%--------------------------------------------------------------------
change_timeout(Config) ->

    {{Index, Type, _M, SrvValue}, CliValue} = 
	ct:get_config({dict, change_timeout}),

    %% Verify old value
    {Index, Type, _Transfer, SrvValue} = 
	lists:keyfind(Index, 1, co_test_app:dict(serial())),
							
    %% Change to new
    ok = store_cmd(Config, Index, segment, 10000),

    %% Verify new value
    {Index, _Type, _Transfer, CliValue} = 
	lists:keyfind(Index, 1, co_test_app:dict(serial())).

%%--------------------------------------------------------------------
%% @spec break(Config) -> ok 
%% @doc 
%% Dummy test case to have a test environment running.
%% Stores Config in ets table.
%% @end
%%--------------------------------------------------------------------
break(Config) ->
    ets:new(config, [set, public, named_table]),
    ets:insert(config, Config),
    test_server:break("Break for test development\n" ++
		     "Get Config by C = ets:tab2list(config)."),
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
	lists:keyfind(Index, 1, co_test_app:dict(?MGR_NODE)),

    %% Change to new
    ok = fetch_cmd(Config, Index, BlockOrSegment),
    {Index, _Type, _Transfer, SrvValue} = 
	lists:keyfind(Index, 1, co_test_app:dict(?MGR_NODE)),

    ok.

xnodeid() ->
    co_api:get_option(serial(), xnodeid).

store_cmd(Config, {Ix, Si}, BlockOrSegment) -> 
    co_mgr:store(xnodeid(), Ix, Si, BlockOrSegment, 
		 {app, ?config(app, Config), co_test_app}).

store_cmd(Config, {Ix, Si}, BlockOrSegment, TimeOut) -> 
    co_mgr:store(xnodeid(), Ix, Si, BlockOrSegment, 
		 {app, ?config(app, Config), co_test_app}, TimeOut).

fetch_cmd(Config, {Ix, Si}, BlockOrSegment) ->
    co_mgr:fetch(xnodeid(), Ix, Si, BlockOrSegment, 
		 {app, ?config(app, Config), co_test_app}).
    
fetch_cmd(Config, {Ix, Si}, BlockOrSegment, TimeOut) ->
    co_mgr:fetch(xnodeid(), Ix, Si, BlockOrSegment, 
		 {app, ?config(app, Config), co_test_app}, TimeOut).
    
