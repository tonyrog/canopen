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
-module(co_node_SUITE).

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
%% @spec all() -> GroupsAndTestCases | {skip,Reason}
%% @end
%%--------------------------------------------------------------------
all() -> 
    [start_of_co_node,
     set_options_ok,
     set_options_nok,
     unknown_option,
     nodeid_changes,
     restore_dict,
     save_and_load,
     save_and_load_nok,
     start_stop_app,
     inactive].
%%     break].



%%--------------------------------------------------------------------
%% @doc
%% Initialization before the whole suite
%%
%% @spec init_per_suite(Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    co_test_lib:start_system(),
    co_test_lib:start_node(Config),
    Config.

%%--------------------------------------------------------------------
%% @doc
%% Cleanup after the whole suite
%%
%% @spec end_per_suite(Config) -> _
%% @end
%%--------------------------------------------------------------------
end_per_suite(Config) ->
    co_test_lib:stop_node(Config),
    co_test_lib:stop_system(),
    ok.


%%--------------------------------------------------------------------
%% @doc
%% Initialization before each test case
%%
%% @spec init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
init_per_testcase(Case, Config) when Case == save_and_load;
				     Case == save_and_load_nok ->

    ct:pal("Testcase: ~p", [Case]),
    {ok, Pid} = co_sys_app:start_link(serial()),
    ok = co_sys_app:debug(Pid, true),
    Config;
init_per_testcase(_TestCase, Config) ->
    ct:pal("Testcase: ~p", [_TestCase]),
    Config.


%%--------------------------------------------------------------------
%% @doc
%% Cleanup after each test case
%%
%% @spec end_per_testcase(TestCase, Config0) ->
%%               void() | {save_config,Config1} | {fail,Reason}
%% @end
%%--------------------------------------------------------------------
end_per_testcase(start_stop_app, _Config) ->
    co_test_app:stop(serial()),
    ok;
end_per_testcase(Case, _Config) when Case == save_and_load;
				     Case == save_and_load_nok ->
    case whereis(co_sys_app) of
	undefined  -> do_nothing;
	_Pid ->  co_sys_app:stop(serial())
    end,
    ok;
end_per_testcase(inactive, _Config) ->
    co_api:set_option(serial(), inact_timeout, infinity),
    ok;
end_per_testcase(_TestCase, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc 
%% Dummy testcase verifying that the co_node is up and running.
%% The real start is done in init_per_suite.
%% @end
%%--------------------------------------------------------------------
-spec start_of_co_node(Config::list(tuple())) -> ok.

start_of_co_node(_Config) -> 
    ct:pal("Node up and running"),
    timer:sleep(1000),
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Change co_node options.
%% @end
%%--------------------------------------------------------------------
-spec set_options_ok(Config::list(tuple())) -> ok.

set_options_ok(_Config) ->

    Options = [{name, "Test"},
	       {sdo_timeout, 2000},
	       {blk_timeout, 1000},
	       {pst, 64},
	       {max_blksize, 64},
	       {use_crc, false},
	       {readbufsize, 64},
	       {load_ratio, 0.7},
	       {atomic_limit, 128},
	       {time_stamp, 30000},
	       {debug, false}],

    lists:foreach(fun(Option) -> set_option_ok(Option) end, Options), 
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Try changing co_node options to illegal values.
%% @end
%%--------------------------------------------------------------------
-spec set_options_nok(Config::list(tuple())) -> ok.

set_options_nok(_Config) ->

    Options = [{name, 7, 
		"Option name can only be set to a string or an atom."},
	       {pst, "String", 
		"Option pst can only be set to a positive integer value or zero."},
	       {max_blksize, -64, 
		"Option max_blksize can only be set to a positive integer value."},
	       {use_crc, any, 
		"Option use_crc can only be set to true or false."},
	       {load_ratio, 7, 
		"Option load_ratio can only be set to a float value between 0 and 1."},
	       {time_stamp, 0, 
		"Option time_stamp can only be set to a positive integer value."},
	       {xnodeid, 16#ffffffff, 
		"Option xnodeid can only be set to an integer value between 0 and 16777215 (0 - 16#ffffff) or undefined."},
	       {nodeid, 177,
	       "Option nodeid can only be set to an integer between 0 and 126 (0 - 16#7e) or undefined."},
	       {nodeid, 0, 
		"NodeId 0 is reserved for the CANopen manager co_mgr."}],

    lists:foreach( fun(Option) -> set_option_nok(Option) end, Options), 
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Try get and set of unknown option.
%% @end
%%--------------------------------------------------------------------
-spec unknown_option(Config::list(tuple())) -> ok.

unknown_option(_Config) ->
    {error, "Unknown option unknown_option"} = 
	co_api:get_option(serial(), unknown_option),
    
    {error, "Option unknown_option unknown."} = 
	co_api:set_option(serial(), unknown_option, any),

    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Change nodeid options.
%% @end
%%--------------------------------------------------------------------
-spec nodeid_changes(Config::list(tuple())) -> ok.

nodeid_changes(_Config) ->
    
    set_option({nodeid, 7}),
    set_option({xnodeid, undefined}),

    %% Both nodeids can't be undefined
    {error, "Not possible to remove last nodeid"} = 
	co_api:set_option(serial(), nodeid, undefined),

    set_option({xnodeid, co_lib:serial_to_xnodeid(serial())}),
    set_option({nodeid, undefined}),

    %% Both nodeids can't be undefined
    {error, "Not possible to remove last nodeid"} = 
	co_api:set_option(serial(), xnodeid, undefined),
    {error, "Not possible to remove last nodeid"} = 
	co_api:set_option(serial(), use_serial_as_xnodeid, false),

    set_option({nodeid, 7}),

    set_option({use_serial_as_xnodeid, false}),
    {xnodeid, undefined} = co_api:get_option(serial(), xnodeid),

    set_option({use_serial_as_xnodeid, true}),
    XNodeId = co_lib:serial_to_xnodeid(serial()),
    {xnodeid, XNodeId} = co_api:get_option(serial(), xnodeid),

    ok.
    

%%--------------------------------------------------------------------
%% @doc 
%% Verifies that a saved dict can be restored.
%% @end
%%--------------------------------------------------------------------
-spec restore_dict(Config::list(tuple())) -> ok.

restore_dict(_Config) ->
    {Index, NewValue, _Type} = ct:get_config(dict_index),
    {ok, OldValue} = co_api:value(serial(), Index),
    ok = co_api:save_dict(serial()),

    %% Change a value and see that it is changed
    ok = co_api:set_value(serial(), Index, NewValue),
    {ok, NewValue} = co_api:value(serial(), Index),

    %% Restore the dictionary and see that the value is restored
    ok = co_api:load_dict(serial()),
    {ok, OldValue} = co_api:value(serial(), Index),

    ok.


%%--------------------------------------------------------------------
%% @doc 
%% Saves and loads a dict using SDO:s.
%% @end
%%--------------------------------------------------------------------
-spec save_and_load(Config::list(tuple())) -> ok.

save_and_load(Config) ->
    {Index, NewValue, _Type} = ct:get_config(dict_index),
    {ok, OldValue} = co_api:value(serial(), Index),

    [] = 
	os:cmd(co_test_lib:set_cmd(Config, 
				   {?IX_STORE_PARAMETERS, ?SI_STORE_ALL}, 
				   ?EVAS, unsigned32, segment, 9000)),

    %% Change a value and see that it is changed
    ok = co_api:set_value(serial(), Index, NewValue),
    {ok, NewValue} = co_api:value(serial(), Index),

    %% Restore the dictionary and see that the value is restored
    [] = 
	os:cmd(co_test_lib:set_cmd(Config, 
				   {?IX_RESTORE_DEFAULT_PARAMETERS, ?SI_RESTORE_ALL}, 
				   ?DOAL, unsigned32, segment, 9000)),
    
    {ok, OldValue} = co_api:value(serial(), Index),

    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Verifies that load and save only works with correct values
%% @end
%%--------------------------------------------------------------------
-spec save_and_load_nok(Config::list(tuple())) -> ok.

save_and_load_nok(Config) ->

    "cocli: error: set failed: local control error\r\n" = 
	os:cmd(co_test_lib:set_cmd(Config, 
				   {?IX_STORE_PARAMETERS, ?SI_STORE_ALL}, 
				   1935, unsigned32, segment, 9000)),

    "cocli: error: set failed: local control error\r\n" = 
	os:cmd(co_test_lib:set_cmd(Config, 
				   {?IX_RESTORE_DEFAULT_PARAMETERS, ?SI_RESTORE_ALL}, 
				   1935, unsigned32, segment, 9000)),
    
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Verifies start and stop of an app connecting to the co_node.
%% @end
%%--------------------------------------------------------------------
-spec start_stop_app(Config::list(tuple())) -> ok.

start_stop_app(_Config) ->
    {ok, _Pid} = co_test_app:start(serial(), app_dict()),
    timer:sleep(1000),

    %% Check that is it up
    Dict = co_test_app:dict(serial()),
    ct:pal("Dictionary = ~p", [Dict]),

    ok = co_test_app:stop(serial()),
    ok.


%%--------------------------------------------------------------------
%% @doc 
%% Verifies that an inactive is sent if subscribed to.
%% @end
%%--------------------------------------------------------------------
-spec inactive(Config::list(tuple())) -> ok.

inactive(_Config) ->
    ok = co_api:set_option(serial(), inact_timeout, 2),
    ok = co_api:inactive_event_subscribe(serial()),

    receive 
	inactive ->
	    ct:pal("Got inactive.",[]);
	_Other1 ->
	    ct:pal("Received other = ~p", [_Other1]),
	    ct:fail("Received other")
    after 2500 ->
	    ct:fail("Application did not get inactive")
    end,
    ok.


%%--------------------------------------------------------------------
%% @doc 
%% Dummy test case to have a test environment running.
%% Stores Config in ets table.
%% @end
%%--------------------------------------------------------------------
-spec break(Config::list(tuple())) -> ok.

break(Config) ->
    ets:new(config, [set, public, named_table]),
    ets:insert(config, Config),
    test_server:break("Break for test development\n" ++
		     "Get Config by ets:tab2list(config)"),
    ok.


%%--------------------------------------------------------------------
%% Help functions
%%--------------------------------------------------------------------
serial() -> co_test_lib:serial().
app_dict() -> co_test_lib:app_dict().

     
set_option_ok({Option, NewValue}) ->
    %% Fetch old value
    {Option, OldValue} = co_api:get_option(serial(), Option),
    
    %% Change
    set_option({Option, NewValue}),

    %% Restore
    set_option({Option, OldValue}),

    ok.

set_option({Option, NewValue}) ->
    %% Set new value and check
    ok = co_api:set_option(serial(), Option, NewValue),
    {Option, NewValue} = co_api:get_option(serial(), Option).

set_option_nok({Option, NewValue, ErrMsg}) ->
    %% Fetch old value
    {Option, OldValue} = co_api:get_option(serial(), Option),
    
    %% Try setting new value
    {error, ErrMsg} = co_api:set_option(serial(), Option, NewValue),
    
    %% Check old wasn't changed
    {Option, OldValue} = co_api:get_option(serial(), Option),

    ok.
