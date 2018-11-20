%% coding: latin-1
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
%%% @copyright (C) 2012, Marina Westman Lönne
%%% @doc
%%%   Test suite for CANopen process dictionary.
%%% Created : 9 Feb 2012 by Marina Westman Lönne 
%%% @end
%%%-------------------------------------------------------------------
-module(co_proc_SUITE).

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
    [{timetrap,{minutes,10}}].


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
    [start_of_co_proc,
     reg_unreg,
     i,
     clear,
     monitor].
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
    {ok, _Pid} = co_proc:start_link([{linked, false}]),
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
    co_proc:stop(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @spec start_of_co_proc(Config) -> ok 
%% @doc 
%% Dummy testcase verifying that the co_proc is up and running.
%% The real start is done in init_per_testcase.
%% @end
%%--------------------------------------------------------------------
start_of_co_proc(_Config) -> 
    ct:pal("Proc up and running"),
    timer:sleep(100),
    ok.

%%--------------------------------------------------------------------
%% @spec reg(Config) -> ok 
%% @doc 
%% Verifies reg and unreg functions.
%% @end
%%--------------------------------------------------------------------
reg_unreg(_Config) ->
    ok = co_proc:reg(one),
    [one] = co_proc:regs(),
    ok = co_proc:unreg(one),
    {error,not_found} = co_proc:regs(),
    ok.

%%--------------------------------------------------------------------
%% @spec reg(Config) -> ok 
%% @doc 
%% Verifies i function.
%% @end
%%--------------------------------------------------------------------
i(_Config) ->
    [] = co_proc:i(),
    Pid = self(),
    ok = co_proc:reg(one),
    [{Pid, _Mon, [one]}] = co_proc:i(),
    ok.

%%--------------------------------------------------------------------
%% @spec reg(Config) -> ok 
%% @doc 
%% Verifies clear function.
%% @end
%%--------------------------------------------------------------------
clear(_Config) ->
    ok = co_proc:reg(one),
    ok = co_proc:reg(two),
    [one, two] = co_proc:regs(),
    ok = co_proc:clear(),
    {error,not_found} = co_proc:regs(),
    ok.

%%--------------------------------------------------------------------
%% @spec reg(Config) -> ok 
%% @doc 
%% Verifies monitoring of registered processes.
%% @end
%%--------------------------------------------------------------------
monitor(_Config) ->
    Pid = spawn(
	    fun() -> 
		    co_proc:reg(spawn),
		    [spawn] = co_proc:regs(),
		    exit
	    end),
    timer:sleep(100),
    {error,dead} = co_proc:regs(Pid),
    [{Pid, {dead, _R}, []}] = co_proc:i(),
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
