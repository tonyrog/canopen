%%%-------------------------------------------------------------------
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Marina Westman Lönne
%%% @doc
%%%
%%% @end
%%% Created : 11 Jan 2012 by Marina Westman Lönne <malotte@malotte.net>
%%%-------------------------------------------------------------------
-module(co_tpdo_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").

-define(RPDO_NODE, 16#3077701).

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
%% @end
%%--------------------------------------------------------------------
-spec suite() -> Info::list(tuple()).

suite() ->
    [{timetrap,{minutes,10}},
     {require, serial}].


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
%% @end
%%--------------------------------------------------------------------
-spec all() -> list(GroupsAndTestCases::atom() | tuple()) | 
	       {skip, Reason::term()}.

all() -> 
    [send_tpdo1
    ].
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
%% @end
%%--------------------------------------------------------------------
-spec groups() -> list(Group::tuple()).

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
%% @end
%%--------------------------------------------------------------------
-spec init_per_suite(Config0::list(tuple())) ->
			    (Config1::list(tuple())) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),Config1::list(tuple())}.
init_per_suite(Config) ->
    co_test_lib:start_node(),
    co_test_lib:start_node(?RPDO_NODE),

    Config.

%%--------------------------------------------------------------------
%% @doc
%% Cleanup after the whole suite
%%
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% @end
%%--------------------------------------------------------------------
-spec end_per_suite(Config::list(tuple())) -> ok.

end_per_suite(_Config) ->
    co_node:stop(serial()),
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Initialization before each test case group.
%%
%% GroupName = atom()
%%   Name of the test case group that is about to run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding configuration data for the group.
%% Reason = term()
%%   The reason for skipping all test cases and subgroups in the group.
%%
%% @end
%%--------------------------------------------------------------------
-spec init_per_group(Group::atom(), Config0::list(tuple())) ->
			    (Config1::list(tuple())) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),Config1::list(tuple())}.

init_per_group(_GroupName, Config) ->
    Config.

%%--------------------------------------------------------------------
%% @doc
%% Cleanup after each test case group.
%%
%% GroupName = atom()
%%   Name of the test case group that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding configuration data for the group.
%%
%% @end
%%--------------------------------------------------------------------
-spec end_per_group(Group::atom(), Config::list(tuple())) -> 
			   ok |
			   {save_config,Config1::list(tuple())}.

end_per_group(_GroupName, _Config) ->
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
%% @end
%%--------------------------------------------------------------------
-spec init_per_testcase(TestCase::atom(), Config0::list(tuple())) ->
			    (Config1::list(tuple())) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),Config1::list(tuple())}.

init_per_testcase(_TestCase, Config) ->
    ct:pal("Testcase: ~p", [_TestCase]),
    IndexList  = ct:get_config(tpdo_dict),
    {ok, TPid} = co_test_tpdo_app:start(serial(), IndexList),
    ct:pal("Started tpdo app: ~p", [TPid]),
    timer:sleep(100),
    {ok, RPid} = co_test_app:start(?RPDO_NODE, app_dict()),
    ct:pal("Started rpdo app: ~p", [RPid]),    
    ok = co_test_app:debug(RPid, true),
    timer:sleep(100),
    ok = co_node:state(serial(), operational),
    ct:pal("Changed state to operational", []),    
    timer:sleep(100),
    [{tpdo_app, TPid}, {rpdo_app,  RPid} | Config].


%%--------------------------------------------------------------------
%% @doc
%% Cleanup after each test case
%%
%% TestCase - atom()
%%   Name of the test case that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% @end
%%--------------------------------------------------------------------
-spec end_per_testcase(TestCase::atom(), Config0::list(tuple())) ->
			      ok |
			      {save_config,Config1::list(tuple())}.

end_per_testcase(_TestCase, _Config) ->
    case whereis(co_test_tpdo_app) of
	undefined  -> do_nothing;
	_Pid ->  co_test_tpdo_app:stop()
    end,
    co_test_lib:stop_app(co_test_app, serial()),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc 
%% Verifies sending of tpdo
%% @end
%%--------------------------------------------------------------------
-spec send_tpdo1(Config::list(tuple())) -> ok.

send_tpdo1(Config) ->
    %% Wait for all processes to be up
    timer:sleep(100),
    {CobId, [{SourceIndex, SourceValue}], [{TargetIndex, TargetValue}]} = 
	ct:get_config(tpdo1),

    %% Send tpdo with default value
    co_node:pdo_event(serial(), CobId),

    receive 
	{set, TargetIndex = {Ix, Si}, DefValue} ->
	    ct:pal("Application got set ~.16B:~.8B updated to ~p",
		   [Ix, Si, DefValue]);
	_Other1 ->
	    ct:pal("Received other = ~p", [_Other1]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:fail("Application did not get set")
    end,

    co_test_tpdo_app:set(?config(app, Config), SourceIndex, SourceValue),

    %% Send tpdo with new value
    co_node:pdo_event(serial(), CobId),

    receive 
	{set, TargetIndex = {Ix2, Si2}, NewValue} ->
	    ct:pal("Application got set ~.16B:~.8B updated to ~p",
		   [Ix2, Si2, NewValue]);
	_Other2 ->
	    ct:pal("Received other = ~p", [_Other2]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:fail("Application did not get set")
    end,

    ok.

send_tpdo_old(Config) ->
    IndexList = ct:get_config(tpdo_index),
    {{Ix, _T, V}, NV} = hd(IndexList),

    receive 
	{callback, Ix, MF} ->
	    ct:pal("Application got callback ~p for ~p",[MF, Ix]);
	_Other1 ->
	    ct:pal("Received other = ~p", [_Other1]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:fail("Application did not get callback")
    end,

    timer:sleep(100),
    co_node:pdo_event(serial(), ct:get_config(tpdo1)),
    %% Check tpdo sent with default value ??

    timer:sleep(100),
    co_test_tpdo_app:set(?config(app, Config), Ix, NV),
    receive 
	{set, Ix, NV} ->
	    ct:pal("Application got set for ~p",[Ix]);
	_Other2 ->
	    ct:pal("Received other = ~p", [_Other2]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:fail("Application did not get set")
    end,

    timer:sleep(100),
    co_node:pdo_event(serial(), ct:get_config(tpdo_offset)),
    %% Check tpdo sent ??

    timer:sleep(100),
    co_test_tpdo_app:set(?config(app, Config), Ix, V),
    receive 
	{set, Ix, V} ->
	    ct:pal("Application got set for ~p",[Ix]);
	_Other3 ->
	    ct:pal("Received other = ~p", [_Other3]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:fail("Application did not get set")
    end,

    timer:sleep(100),
    co_node:pdo_event(serial(), ct:get_config(tpdo_offset)),
    %% Check tpdo sent ??
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

     
