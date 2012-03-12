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
-include("canopen.hrl").

%% Flags to indicate if store/restore command is valid
-define(EVAS, 1935767141). %% $e + ($v bsl 8) + ($a bsl 16) + ($s bsl 24)
-define(DOAL, 1819238756). %% $d + ($a bsl 8) + ($o bsl 16) + ($l bsl 24)

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
    [start_of_co_node,
     set_options_ok,
     set_options_nok,
     unknown_option,
     nodeid_changes,
     restore_dict,
     save_and_load,
     save_and_load_nok,
     start_stop_app].
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
    co_test_lib:start_node(Config),
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
%% TestCase - atom()
%%   Name of the test case that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% @spec end_per_testcase(TestCase, Config0) ->
%%               void() | {save_config,Config1} | {fail,Reason}
%% @end
%%--------------------------------------------------------------------
end_per_testcase(start_stop_app, _Config) ->
    co_test_lib:stop_app(co_test_app, serial()),
    ok;
end_per_testcase(Case, _Config) when Case == save_and_load;
				     Case == save_and_load_nok ->
    case whereis(co_sys_app) of
	undefined  -> do_nothing;
	_Pid ->  co_sys_app:stop(serial())
    end,
    ok;
end_per_testcase(_TestCase, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @spec start_of_co_node(Config) -> ok 
%% @doc 
%% Dummy testcase verifying that the co_node is up and running.
%% The real start is done in init_per_suite.
%% @end
%%--------------------------------------------------------------------
start_of_co_node(_Config) -> 
    ct:pal("Node up and running"),
    timer:sleep(1000),
    ok.

%%--------------------------------------------------------------------
%% @spec set_options_ok(Config) -> ok 
%% @doc 
%% Change co_node options.
%% @end
%%--------------------------------------------------------------------
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

    lists:foreach(
      fun(Option) -> set_option_ok(Option) end, Options),

    ok.

%%--------------------------------------------------------------------
%% @spec set_options_nok(Config) -> ok 
%% @doc 
%% Try changing co_node options to illegal values.
%% @end
%%--------------------------------------------------------------------
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
	       {xnodeid, 7, 
		"Option xnodeid can only be set to an integer value between 8 and 24 bits or undefined."},
	       {nodeid, 177,
	       "Option nodeid can only be set to an integer between 0 and 126 or undefined."},
	       {nodeid, 0, 
		"NodeId 0 is reserved for the CANopen manager co_mgr."}],

    lists:foreach(
      fun(Option) -> set_option_nok(Option) end, Options),

    ok.

%%--------------------------------------------------------------------
%% @spec unknown_option(Config) -> ok 
%% @doc 
%% Try get and set of unknown option.
%% @end
%%--------------------------------------------------------------------
unknown_option(_Config) ->
    {error, "Unknown option unknown_option"} = 
	co_node:get_option(serial(), unknown_option),
    
    {error, "Option unknown_option unknown."} = 
	co_node:set_option(serial(), unknown_option, any),

    ok.

%%--------------------------------------------------------------------
%% @spec unknown_option(Config) -> ok 
%% @doc 
%% Change nodeid options.
%% @end
%%--------------------------------------------------------------------
nodeid_changes(_Config) ->
    
    set_option({nodeid, 7}),
    set_option({xnodeid, undefined}),

    %% Both nodeids can't be undefined
    {error, "Not possible to remove last nodeid"} = 
	co_node:set_option(serial(), nodeid, undefined),

    set_option({xnodeid, co_lib:serial_to_xnodeid(serial())}),
    set_option({nodeid, undefined}),

    %% Both nodeids can't be undefined
    {error, "Not possible to remove last nodeid"} = 
	co_node:set_option(serial(), xnodeid, undefined),
    {error, "Not possible to remove last nodeid"} = 
	co_node:set_option(serial(), use_serial_as_xnodeid, false),

    set_option({nodeid, 7}),

    set_option({use_serial_as_xnodeid, false}),
    {xnodeid, undefined} = co_node:get_option(serial(), xnodeid),

    set_option({use_serial_as_xnodeid, true}),
    XNodeId = co_lib:serial_to_xnodeid(serial()),
    {xnodeid, XNodeId} = co_node:get_option(serial(), xnodeid),

    ok.
    

%%--------------------------------------------------------------------
%% @spec restore_dict(Config) -> ok 
%% @doc 
%% Verifies that a saved dict can be restored.
%% @end
%%--------------------------------------------------------------------
restore_dict(_Config) ->
    {Index, NewValue, _Type} = ct:get_config(dict_index),
    {ok, OldValue} = co_node:value(serial(), Index),
    ok = co_node:save_dict(serial()),

    %% Change a value and see that it is changed
    ok = co_node:set(serial(), Index, NewValue),
    {ok, NewValue} = co_node:value(serial(), Index),

    %% Restore the dictionary and see that the value is restored
    ok = co_node:load_dict(serial()),
    {ok, OldValue} = co_node:value(serial(), Index),

    ok.


%%--------------------------------------------------------------------
%% @spec save_and_load(Config) -> ok 
%% @doc 
%% Saves and loads a dict using SDO:s.
%% @end
%%--------------------------------------------------------------------
save_and_load(Config) ->
    {Index, NewValue, _Type} = ct:get_config(dict_index),
    {ok, OldValue} = co_node:value(serial(), Index),

    [] = 
	os:cmd(co_test_lib:set_cmd(Config, 
				   {?IX_STORE_PARAMETERS, ?SI_STORE_ALL}, 
				   ?EVAS, unsigned32, segment, 9000)),

    %% Change a value and see that it is changed
    ok = co_node:set(serial(), Index, NewValue),
    {ok, NewValue} = co_node:value(serial(), Index),

    %% Restore the dictionary and see that the value is restored
    [] = 
	os:cmd(co_test_lib:set_cmd(Config, 
				   {?IX_RESTORE_DEFAULT_PARAMETERS, ?SI_RESTORE_ALL}, 
				   ?DOAL, unsigned32, segment, 9000)),
    
    {ok, OldValue} = co_node:value(serial(), Index),

    ok.

%%--------------------------------------------------------------------
%% @spec save_and_load_nok(Config) -> ok 
%% @doc 
%% Verifies that load and save only works with correct values
%% @end
%%--------------------------------------------------------------------
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
%% @spec start_stop_of_app(Config) -> ok 
%% @doc 
%% Verifies start and stop of an app connecting to the co_node.
%% @end
%%--------------------------------------------------------------------
start_stop_app(_Config) ->
    {ok, _Pid} = co_test_app:start(serial(), app_dict()),
    timer:sleep(1000),

    %% Check that is it up
    Dict = co_test_app:dict(serial()),
    ct:pal("Dictionary = ~p", [Dict]),

    ok = co_test_app:stop(serial()),
    ok.


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
		     "Get Config by ets:tab2list(config)"),
    ok.


%%--------------------------------------------------------------------
%% Help functions
%%--------------------------------------------------------------------
serial() -> co_test_lib:serial().
app_dict() -> co_test_lib:app_dict().

     
set_option_ok({Option, NewValue}) ->
    %% Fetch old value
    {Option, OldValue} = co_node:get_option(serial(), Option),
    
    %% Change
    set_option({Option, NewValue}),

    %% Restore
    set_option({Option, OldValue}),

    ok.

set_option({Option, NewValue}) ->
    %% Set new value and check
    ok = co_node:set_option(serial(), Option, NewValue),
    {Option, NewValue} = co_node:get_option(serial(), Option).

set_option_nok({Option, NewValue, ErrMsg}) ->
    %% Fetch old value
    {Option, OldValue} = co_node:get_option(serial(), Option),
    
    %% Try setting new value
    {error, ErrMsg} = co_node:set_option(serial(), Option, NewValue),
    
    %% Check old wasn't changed
    {Option, OldValue} = co_node:get_option(serial(), Option),

    ok.
