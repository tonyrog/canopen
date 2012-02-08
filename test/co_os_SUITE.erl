%%%-------------------------------------------------------------------
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2011, Marina Westman Lönne
%%% @doc
%%%
%%% @end
%%% Created : 29 Nov 2011 by Marina Westman Lönne <malotte@malotte.net>
%%%-------------------------------------------------------------------
-module(co_os_SUITE).

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
%% @end
%%--------------------------------------------------------------------
-spec suite() -> Info::list(tuple()).

suite() ->
    [{timetrap,{minutes,10}},
     {require, serial},
     {require, cocli}].


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
    [start_stop_app,
     os_command,
     os_command_slow,
     os_command_seq
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
    co_test_lib:load_dict(Config),
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

init_per_testcase(Case, Config) when Case == os_command;
				     Case == os_command_slow;
				     Case == os_command_seq ->
    {ok, _Pid} = co_os_app:start(serial()),
    ok = co_os_app:debug(true),
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
%% @end
%%--------------------------------------------------------------------
-spec end_per_testcase(TestCase::atom(), Config0::list(tuple())) ->
			      ok |
			      {save_config,Config1::list(tuple())}.

end_per_testcase(Case, _Config) when Case == start_stop_app;
				     Case == os_command;
				     Case == os_command_slow;
				     Case == os_command_seq ->
    case whereis(co_os_app) of
	undefined  -> do_nothing;
	_Pid ->  co_os_app:stop()
    end,
    ok;
end_per_testcase(_TestCase, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc 
%% Verifies start and stop of an app connecting to the co_node.
%% @end
%%--------------------------------------------------------------------
-spec start_stop_app(Config::list(tuple())) -> ok.

start_stop_app(_Config) ->
    {ok, _Pid} = co_os_app:start(serial()),

    %% Check that is it up
    ok = co_os_app:debug(true),
    timer:sleep(1000),

    ok = co_os_app:stop(),
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Sends an os command and checks the result.
%% @end
%%--------------------------------------------------------------------
-spec os_command(Config::list(term())) -> ok.

os_command(Config) ->
    Command = "pwd",
    %% Send command
    [] = os:cmd(co_test_lib:set_cmd(Config, {16#1023, 1}, Command, segment)),
    
    Result = get_result(Config),
    ct:pal("Result ~p", [Result]),
    
    verify_result("1", Result),

    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Sends an os command that should take a while and checks the result.
%% @end
%%--------------------------------------------------------------------
-spec os_command_slow(Config::list(term())) -> ok.

os_command_slow(Config) ->
    Command = "sleep 2",
    %% Send command
    [] = os:cmd(co_test_lib:set_cmd(Config, {16#1023, 1}, Command, segment)),
 
    Result = get_result(Config),
    ct:pal("Result ~p", [Result]),
    verify_result("255", Result),

    %% Wait for command to be executed
    timer:sleep(2000),
    
    Result1 = get_result(Config),
    ct:pal("Result ~p", [Result1]),
    verify_result("0", Result1),

    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Sends an os command and checks the result.
%% @end
%%--------------------------------------------------------------------
-spec os_command_seq(Config::list(tuple())) -> ok. 

os_command_seq(Config) ->
    Command = "pwd; cd /; pwd",
    %% Send command
    [] = os:cmd(co_test_lib:set_cmd(Config, {16#1023, 1}, Command, segment)),
    
    Result = get_result(Config),
    ct:pal("Result ~p", [Result]),
    
    verify_result("1", Result),

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

     
get_result(Config) -> 
    %% Command
    Cmd = os:cmd(co_test_lib:get_cmd(Config, {16#1023, 1}, segment)),
    
    %% Status
    Status = os:cmd(co_test_lib:get_cmd(Config, {16#1023, 2}, segment)),
    
    %% Reply
    Reply = os:cmd(co_test_lib:get_cmd(Config, {16#1023, 3}, segment)),

    {Cmd, Status, Reply}.

verify_result(ExpectedStatus, {Cmd, Status, Reply}) ->
    
    "0x1023:1 = " ++ _ = Cmd, 
    "0x1023:3 = " ++ _ = Reply,
    
    ["0x1023:2", "=", ExpectedStatus] = string:tokens(Status, " \n").
    
