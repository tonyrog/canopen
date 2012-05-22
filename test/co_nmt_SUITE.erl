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
%%%   Test of NMT functionality.
%%%
%%% Created : 14 May 2012 by Marina Westman Lönne
%%% @end
%%%-------------------------------------------------------------------
-module(co_nmt_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include("canopen.hrl").

-define(SLAVE_NODE, 16#3077701).

%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%%  Returns list of tuples to set default properties
%%  for the suite.
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
    [start_master,
     {group, subscribe},
     {group, monitor_subscriber},
     {group, manage_slave},
     start_slave,
     {group, node_guard},
     {group, nmt_commands}].
%%     break].

%%--------------------------------------------------------------------
%% @doc
%% Returns a list of test case group definitions.
%% @end
%%--------------------------------------------------------------------
-spec groups() -> 
    [{GroupName::atom(),
      list(Prop::parallel | 
		 sequence | 
		 shuffle | {shuffle,Seed::{integer(),integer(),integer()}} |
		 repeat | 
		 repeat_until_all_ok | 
		 repeat_until_all_fail |              
		 repeat_until_any_ok | 
		 {repeat_until_any_fail,N::integer() | forever}),
      list(TestCases::atom())}].

groups() ->
    [{subscribe, [sequence], [subscribe, unsubscribe]},
     {monitor_subscriber, [sequence], [subscribe, die]},
     {manage_slave, [sequence], [add_slave, remove_slave]},
     {node_guard, [sequence], [activate_node_guard, detect_lost_slave]},
     {nmt_commands, [sequence], [stop_cmd, enter_pre_op_cmd, start_cmd]}
    ].

%%--------------------------------------------------------------------
%% @doc
%% Initialization before the whole suite
%% @end
%%--------------------------------------------------------------------
-spec init_per_suite(Config0::list(tuple())) ->
			    (Config1::list(tuple())) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),Config1::list(tuple())}.
init_per_suite(Config) ->
    co_test_lib:start_system(),
    co_test_lib:start_node(Config, 
			   [{nmt_role, master}]),

    Config.

%%--------------------------------------------------------------------
%% @doc
%% Cleanup after the whole suite
%% @end
%%--------------------------------------------------------------------
-spec end_per_suite(Config::list(tuple())) -> ok.

end_per_suite(Config) ->
    co_test_lib:stop_node(Config),
    co_test_lib:stop_system(),
    ok.


%%--------------------------------------------------------------------
%% @doc
%% Initialization before each test case group.
%% @end
%%--------------------------------------------------------------------
-spec init_per_group(GroupName::atom(), Config0::list(tuple())) ->
			    Config1::list(tuple()) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),Config1::list(tuple())}.

init_per_group(GroupName, Config) 
  when GroupName == nmt_commands->
    ct:pal("TestGroup: ~p", [GroupName]),
    co_nmt:remove_slave(xslave_id()),
    co_nmt:remove_slave(slave_id()),
    [] = co_nmt:slaves(),
    co_test_lib:start_node(Config, 
			   ?SLAVE_NODE,
			   [{nmt_role, slave},
			    {supervision, none},
			    slave_id()]),
    Config;
init_per_group(GroupName, Config) ->
    ct:pal("TestGroup: ~p", [GroupName]),
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
-spec end_per_group(GroupName::atom(), Config0::list(tuple())) ->
			   no_return() | 
			   {save_config, Config1::list(tuple())}.

end_per_group(nmt_commands, _Config) ->
    co_nmt:remove_slave(slave_id()),
    co_test_lib:stop_node(?SLAVE_NODE),
    ok;
end_per_group(node_guard, _Config) ->
    ok = co_api:set_option(serial(), supervision, none),
    {supervision, none} = co_api:get_option(serial(), supervision),
    co_test_lib:stop_node(?SLAVE_NODE),
    co_nmt:remove_slave(xslave_id()),
    co_nmt:remove_slave(slave_id()),
    ok;
end_per_group(handle_slave, _Config) ->
    co_nmt:remove_slave(slave_id()),
    [] = co_nmt:slaves(),
    ok;
end_per_group(_GroupName, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Initialization before each test case
%% @end
%%--------------------------------------------------------------------
-spec init_per_testcase(TestCase::atom(), Config0::list(tuple())) ->
			    (Config1::list(tuple())) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),Config1::list(tuple())}.

init_per_testcase(TestCase, Config)  
  when TestCase == start_slave;
       TestCase == activate_node_guard ->
    ct:pal("TestCase: ~p", [TestCase]),
    co_test_lib:start_node(Config, 
			   ?SLAVE_NODE,
			   [{nmt_role, slave}]),

    Config;
init_per_testcase(TestCase, Config) ->
    ct:pal("TestCase: ~p", [TestCase]),
    Config.


%%--------------------------------------------------------------------
%% @doc
%% Cleanup after each test case
%% @end
%%--------------------------------------------------------------------
-spec end_per_testcase(TestCase::atom(), Config0::list(tuple())) ->
			      ok |
			      {save_config,Config1::list(tuple())}.

end_per_testcase(TestCase, _Config)  
  when TestCase == start_slave ->
    co_test_lib:stop_node(?SLAVE_NODE),
    co_nmt:remove_slave(xslave_id()),
    ok;
end_per_testcase(_TestCase, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc 
%% Start nmt master
%% @end
%%--------------------------------------------------------------------
-spec start_master(Config::list(tuple())) -> ok.

start_master(_Config) ->
    %% Done in init_per_suite
    {nmt_role, master} = co_api:get_option(serial(), nmt_role),
    true = co_nmt:alive(),
    ok.
  
%%--------------------------------------------------------------------
%% @doc 
%% Subscribe to error notifications
%% @end
%%--------------------------------------------------------------------
-spec subscribe(Config::list(tuple())) ->  
		       ok |
		       {save_config, Config1::list(tuple())}.

subscribe(Config) ->
    true = co_nmt:alive(),
    Pid = spawn(fun() ->
			Self = self(),
			ok = co_nmt:subscribe(),
			{ok, [Self]} = co_nmt:subscribers(),
			ok = co_nmt:subscribe(Self),
			{ok, [Self]} = co_nmt:subscribers(),
			receive
			    die -> ok
			after 1000 ->
				ct:pal("No die received.")
			end
		end),

    timer:sleep(100),
    {ok, [Pid]} = co_nmt:subscribers(),				       
    true = co_nmt:alive(),
    {save_config, [{subscriber, Pid} | Config]}.
  
%%--------------------------------------------------------------------
%% @doc 
%% Unubscribe to error notifications
%% @end
%%--------------------------------------------------------------------
-spec unsubscribe(Config::list(tuple())) -> ok.

unsubscribe(Config) ->
    true = co_nmt:alive(),
    {subscribe, Config1} = ?config(saved_config, Config),
    Pid = ?config(subscriber, Config1),
    {ok, [Pid]} = co_nmt:subscribers(),
    ok = co_nmt:unsubscribe(Pid),
    {ok, []} = co_nmt:subscribers(),
    true = co_nmt:alive(),
    Pid ! die,
    ok.
  
%%--------------------------------------------------------------------
%% @doc 
%% Checks monitoring of subscriber
%% @end
%%--------------------------------------------------------------------
-spec die(Config::list(tuple())) -> ok.

die(Config) ->
    true = co_nmt:alive(),
    {subscribe, Config1} = ?config(saved_config, Config),
    Pid = ?config(subscriber, Config1),
    Pid ! die,
    timer:sleep(100),
    {ok, []} = co_nmt:subscribers(),
    ok = co_nmt:unsubscribe(Pid),
    true = co_nmt:alive(),
    ok.
  
%%--------------------------------------------------------------------
%% @doc 
%% Manually add slave
%% @end
%%--------------------------------------------------------------------
-spec add_slave(Config::list(tuple())) ->  
		       ok.

add_slave(_Config) ->
    true = co_nmt:alive(),
    [] = co_nmt:slaves(),
    SlaveId = slave_id(),
    ok = co_nmt:add_slave(SlaveId),
    [{SlaveId, ?Operational, ok}] = co_nmt:slaves(),
    true = co_nmt:alive(),
    ok.
  
%%--------------------------------------------------------------------
%% @doc 
%% Manually remove slave
%% @end
%%--------------------------------------------------------------------
-spec remove_slave(Config::list(tuple())) ->  
		       ok.

remove_slave(_Config) ->
    true = co_nmt:alive(),
    SlaveId = slave_id(),
    [{SlaveId, ?Operational, ok}] = co_nmt:slaves(),
    ok = co_nmt:remove_slave(SlaveId),
    [] = co_nmt:slaves(),
    true = co_nmt:alive(),
    ok.
  
%%--------------------------------------------------------------------
%% @doc 
%% Start nmt slave
%% @end
%%--------------------------------------------------------------------
-spec start_slave(Config::list(tuple())) -> ok.

start_slave(_Config) ->
    %% Start done in init_per_testcase
    {nmt_role, slave} = co_api:get_option(?SLAVE_NODE, nmt_role),

    %% Time for bootup message to arrive
    timer:sleep(500),
    SlaveId = xslave_id(),

    %% No short nodeid so slave can not be started by nmt master
    [{SlaveId, ?PreOperational, ok}] = co_nmt:slaves(),

    ok.
  
%%--------------------------------------------------------------------
%% @doc 
%% Activate node guarding
%% @end
%%--------------------------------------------------------------------
-spec activate_node_guard(Config::list(tuple())) -> ok.

activate_node_guard(_Config) ->
    ok = co_api:set_option(serial(), supervision, node_guard),
    {supervision, node_guard} = co_api:get_option(serial(), supervision),
    ok = co_api:set_option(?SLAVE_NODE, supervision, node_guard),
    {supervision, node_guard} = co_api:get_option(?SLAVE_NODE, supervision),

    %% Time for node guarding to start
    timer:sleep(500),
    SlaveId = xslave_id(),
    %% No short nodeid so slave can not be started by nmt master
    [{SlaveId, ?PreOperational, ok}] = co_nmt:slaves(),

    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Detect lost slave
%% @end
%%--------------------------------------------------------------------
-spec detect_lost_slave(Config::list(tuple())) -> ok.

detect_lost_slave(_Config) ->
    ok = co_nmt:subscribe(),
    co_test_lib:stop_node(?SLAVE_NODE),
    SlaveId = xslave_id(),

    receive 
	{lost_contact, SlaveId} ->
	    ct:pal("Received lost slave ~p", [SlaveId]);
	
	_Other1 ->
	    ct:pal("Received other = ~p", [_Other1]),
	    ct:fail("Received unexpected")
     after 10000 ->
	    ct:fail("Slave loss not detected")
    end,
    %% No short nodeid so slave can not be started by nmt master
    [{SlaveId, ?PreOperational, lost}] = co_nmt:slaves(),    
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Send start command to slave through master
%% @end
%%--------------------------------------------------------------------
-spec start_cmd(Config::list(tuple())) ->  ok.

start_cmd(_Config) ->
    nmt_command(start, ?Operational),
    true = co_nmt:alive(),
    ok.
  
%%--------------------------------------------------------------------
%% @doc 
%% Send stop command to slave through master
%% @end
%%--------------------------------------------------------------------
-spec stop_cmd(Config::list(tuple())) ->  ok.

stop_cmd(_Config) ->
    nmt_command(stop, ?Stopped),
    true = co_nmt:alive(),
    ok.
  
%%--------------------------------------------------------------------
%% @doc 
%% Send enter_pre_op command to slave through master
%% @end
%%--------------------------------------------------------------------
-spec enter_pre_op_cmd(Config::list(tuple())) ->  ok.

enter_pre_op_cmd(_Config) ->
    nmt_command(enter_pre_op, ?PreOperational),
    true = co_nmt:alive(),
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

nmt_command(Cmd, ExpectedState) ->
    SlaveId = slave_id(),
    ok = co_nmt:send_nmt_command(SlaveId, Cmd),
    timer:sleep(100),
    ExpectedState = co_api:state(SlaveId).

slave_id() ->
    {nodeid, co_lib:serial_to_nodeid(?SLAVE_NODE)}.
xslave_id() ->
    {xnodeid, co_lib:serial_to_xnodeid(?SLAVE_NODE)}.
