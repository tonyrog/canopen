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
%%%   Test of TPDO functionality.
%%%
%%% Created : 11 Jan 2012 by Marina Westman Lönne
%%% @end
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
    [encode_decode,
     send_tpdo0,
     send_tpdo1,
     send_tpdo2,
     send_tpdo3,
     send_tpdo4,
     send_multi,
     send_dam_mpdo,
     send_dam_mpdo_broadcast,
     send_sam_mpdo
    ].
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
%% @end
%%--------------------------------------------------------------------
-spec init_per_suite(Config0::list(tuple())) ->
			    (Config1::list(tuple())) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),Config1::list(tuple())}.
init_per_suite(Config) ->
    co_test_lib:start_system(),
    co_test_lib:start_node(Config),
    co_test_lib:start_node(Config, ?RPDO_NODE),

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

end_per_suite(Config) ->
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
%% @end
%%--------------------------------------------------------------------
-spec init_per_testcase(TestCase::atom(), Config0::list(tuple())) ->
			    (Config1::list(tuple())) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),Config1::list(tuple())}.

init_per_testcase(TestCase, Config) when TestCase == encode_decode ->
    ct:pal("Testcase: ~p", [TestCase]),
    Config;

init_per_testcase(_TestCase, Config) ->
    ct:pal("Testcase: ~p", [_TestCase]),

    %% Start reserver of tpdo objects
    IndexList  = ct:get_config(tpdo_dict),
    {ok, TPid} = co_test_tpdo_app:start(serial(), IndexList),
    ct:pal("Started tpdo app: ~p", [TPid]),
    timer:sleep(100),

    %% Redo mapping, i.e. calls to tpdo_callback
    ok = co_api:state(serial(), preoperational),
    ok = co_api:state(serial(), operational),
    ct:pal("Changed state to operational", []),    
    timer:sleep(100),

    %% Start reserver of rpdo objects
    {ok, RPid} = co_test_app:start(?RPDO_NODE, app_dict()),
    ct:pal("Started rpdo app: ~p", [RPid]),    
    ok = co_test_app:debug(RPid, true),
    timer:sleep(100),

    %% Redo mapping, i.e. calls to tpdo_callback
    ok = co_api:state(?RPDO_NODE, preoperational),
    ok = co_api:state(?RPDO_NODE, operational),
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

end_per_testcase(TestCase, _Config) when TestCase == encode_decode ->
    ok;

end_per_testcase(_TestCase, Config) ->
    case whereis(co_test_tpdo_app) of
	undefined  -> do_nothing;
	_Pid ->  co_test_tpdo_app:stop()
    end,
    co_test_app:stop(?RPDO_NODE),
    %% Restore data
    co_test_lib:load_dict(Config),
    co_test_lib:load_dict(Config, ?RPDO_NODE),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc 
%% Checks that encode - decode results in same as original
%% @end
%%--------------------------------------------------------------------
-spec encode_decode(Config::list(tuple())) -> ok.

encode_decode(_Config) ->
    %% Encode decode testing
    %% {ValuesIn, TypesIn, ValuesOut, TypesOut}
    Cases = 
	[{["hej"], [{string, 64}], [[104,101,106,0,0,0,0,0]], [{string, 64}]},
	 {["hej"], [{string, 64}], [[0,0,0]], [{string, 24}]},
	 {["hejsanxx"], [{string, 64}], ["hejsanxx"], [{string, 64}]},
	 {["hej"], [{string, 24}], ["hej"], [{string, 24}]},
	 {[16#AAAA], [{integer, 32}], [16#AAAA], [{integer, 32}]},
	 {[16#AAAA], [{unsigned, 16}], [16#AAAA], [{unsigned, 16}]},
	 {[16#AAAA, 16#BBBB], [{unsigned, 16}, {unsigned, 16}], 
	  [16#AAAA, 16#BBBB], [{unsigned, 16}, {unsigned, 16}]},
	 {[16#AAAA, 16#BBBB], [{unsigned, 16}, {unsigned, 16}], 
	  [16#BBBBAAAA], [{unsigned, 32}]},
	 {[16#AAAAAAAA], [{unsigned, 16}], [16#AAAA], [{unsigned, 16}]},
	 {[6], [{integer16, 32}], [not_used], [{integer16, 32}]}],

    lists:foreach(
      fun({ValuesIn, TsIn, ValuesOut, TsOut}) ->
	      TsInX = [{co_lib:encode_type(T), S } || {T,S} <- TsIn],
	      TsOutX = [{co_lib:encode_type(T), S } || {T,S} <- TsOut],
	      try co_codec:encode(ValuesIn, TsInX) of
		  Bin -> 
		      try co_codec:decode(Bin, TsOutX) of
			  ValuesOut ->
			      ok;
			  OtherValuesOut ->
			      %% Add other check when encoding - decoding
			      %% 'too short' string ???
			      ct:pal("Encoding values ~p with types ~w = ~w,\n "
				     "resulting bin ~w,\n "
				     "decoded ~p with types ~w = ~w,\n"
				     "residue ~p",
				     [ValuesIn, TsIn, TsInX, Bin, 
				      OtherValuesOut, TsOut, TsInX])
		      catch error:Reason2 ->
			    ct:pal("Decode of ~p with ~w = ~w failed, reason ~p", 
				   [Bin, TsOut, TsOutX, Reason2])
		      end
	      catch error:Reason1 ->
		      ct:pal("Encode of ~p with ~w = ~w failed, reason ~p", 
			     [ValuesIn, TsIn, TsInX, Reason1])
	      end
      end, Cases),
    
    ok.
    

%%--------------------------------------------------------------------
%% @doc 
%% Verifies sending of tpdo0 - co_node dictionary entries
%% @end
%%--------------------------------------------------------------------
-spec send_tpdo0(Config::list(tuple())) -> ok.

send_tpdo0(_Config) ->
    %% Set and read in dict
    {CobId, SourceList, TargetList} = ct:get_config(tpdo0),

    %% Set values
    lists:foreach(
      fun({{Ix, Si} = SourceIndex, SourceValue}) -> 
	      ct:pal("Setting ~.16B:~w to ~p",[Ix, Si, SourceValue]),
	      co_api:set_value(serial(), SourceIndex, SourceValue)
      end, SourceList),

    %% Send tpdo with new value
    co_api:pdo_event(serial(), CobId),

    %% Wait for new values to be sent to co_node
    timer:sleep(1000),

    lists:foreach(
      fun({{IxT, SiT} = TargetIndex, TargetValue}) -> 
	      {ok, TargetValue} = co_api:value(?RPDO_NODE, TargetIndex),
	      ct:pal("Value for ~.16B:~w is ~p",[IxT, SiT, TargetValue])
      end, TargetList),
    
    ok.
    
%%--------------------------------------------------------------------
%% @doc 
%% Verifies sending of tpdo1 - 1 string to 1 string
%% @end
%%--------------------------------------------------------------------
-spec send_tpdo1(Config::list(tuple())) -> ok.
send_tpdo1(Config) ->
    send_tpdo(Config, tpdo1).

%%--------------------------------------------------------------------
%% @doc 
%% Verifies sending of tpdo2 - 2 strings to 2 other strings
%% @end
%%--------------------------------------------------------------------
-spec send_tpdo2(Config::list(tuple())) -> ok.
send_tpdo2(Config) ->
    send_tpdo(Config, tpdo2).

%%--------------------------------------------------------------------
%% @doc 
%% Verifies sending of tpdo3 - 1 integer to 1 integer
%% @end
%%--------------------------------------------------------------------
-spec send_tpdo3(Config::list(tuple())) -> ok.
send_tpdo3(Config) ->
    send_tpdo(Config, tpdo3).

%%--------------------------------------------------------------------
%% @doc 
%% Verifies sending of tpdo4 2 unsigned to 1 unsigned
%% @end
%%--------------------------------------------------------------------
-spec send_tpdo4(Config::list(tuple())) -> ok.
send_tpdo4(Config) ->
    send_tpdo(Config, tpdo4).

%%--------------------------------------------------------------------
%% @doc 
%% Verifies that multiple sets results in multiple receives.
%% @end
%%--------------------------------------------------------------------
-spec send_multi(Config::list(tuple())) -> ok.

send_multi(Config) ->
    %% Wait for all processes to be up
    timer:sleep(100),
    {CobId, SourceList, TargetList} = ct:get_config(tpdo1),

    %% Set values 3 times
    set(Config, SourceList),
    set(Config, SourceList),
    set(Config, SourceList),

    %% Send tpdo with new value 3 times
    co_api:pdo_event(serial(), CobId),
    co_api:pdo_event(serial(), CobId),
    co_api:pdo_event(serial(), CobId),

    %% Receive values 3 times
    rec(TargetList),
    rec(TargetList),
    rec(TargetList),
   
    ok.
    
  
%%--------------------------------------------------------------------
%% @doc 
%% Verifies sending of dam_mpdo broadcast.
%% @end
%%--------------------------------------------------------------------
-spec send_dam_mpdo_broadcast(Config::list(tuple())) -> ok.

send_dam_mpdo_broadcast(Config) ->
    send_dam_mpdo(Config, dam_mpdo, broadcast).

%%--------------------------------------------------------------------
%% @doc 
%% Verifies sending of dam_mpdo to one node.
%% @end
%%--------------------------------------------------------------------
-spec send_dam_mpdo(Config::list(tuple())) -> ok.

send_dam_mpdo(Config) ->
    %% Make sure the receiving node has a short nodeid
    NodeId = co_lib:serial_to_nodeid(?RPDO_NODE),
    ok = co_api:set_option(?RPDO_NODE, nodeid, NodeId),
    timer:sleep(1000),
    send_dam_mpdo(Config, dam_mpdo, NodeId).

%%--------------------------------------------------------------------
%% @doc 
%% Verifies sending of sam_mpdo 
%% @end
%%--------------------------------------------------------------------
-spec send_sam_mpdo(Config::list(tuple())) -> ok.

send_sam_mpdo(Config) ->
    %% Make sure the sending node has a short nodeid
    ok = co_api:set_option(serial(), nodeid, co_lib:serial_to_nodeid(serial())),
    timer:sleep(1000),
    send_tpdo(Config, sam_mpdo).

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

send_tpdo(Config, Tpdo) ->
    %% Wait for all processes to be up
    timer:sleep(100),
    {CobId, SourceList, TargetList} = ct:get_config(Tpdo),

    %% Set values
    set(Config, SourceList),

    %% Send tpdo with new value
    ok = co_api:pdo_event(serial(), CobId),

    rec(TargetList),

    ok.

send_dam_mpdo(Config, Tpdo, Destination) ->
    %% Wait for all processes to be up
    timer:sleep(100),
    {CobId, SourceList, TargetList} = ct:get_config(Tpdo),

    %% Set values
    set(Config, SourceList),

    %% Send tpdo with new value
    ok = co_api:dam_mpdo_event(serial(), CobId, Destination),

    rec(TargetList),

    ok.

set(Config, SourceList) ->
    lists:foreach(
      fun({{Ix, Si} = SourceIndex, SourceValue}) -> 
	      ct:pal("Setting ~.16B:~w to ~p",[Ix, Si, SourceValue]),
	      co_test_tpdo_app:set(?config(tpdo_app, Config), 
				   SourceIndex, SourceValue)
      end, SourceList),
    
    %% Wait for new values to be sent to co_node
    timer:sleep(100),

    ok.
   

rec([{TargetIndex, TargetValue}]) ->
    receive 
	{set, TargetIndex = {Ix, Si}, TargetValue} ->
	    ct:pal("Application got set ~.16B:~w updated to ~p",
		   [Ix, Si, TargetValue]);
	_Other1 ->
	    ct:pal("Received other = ~p", [_Other1]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:fail("Application did not get set")
    end,
    ok;

rec([{TargetIndex1, TargetValue1}, {TargetIndex2, TargetValue2}]) ->
    %% We don't know the order ...
    %% receive first
    rec({TargetIndex1, TargetValue1}, {TargetIndex2, TargetValue2}),
    %% receive second
    rec({TargetIndex1, TargetValue1}, {TargetIndex2, TargetValue2}),
    ok.

rec({TargetIndex1, TargetValue1}, {TargetIndex2, TargetValue2}) ->
    receive 
	{set, TargetIndex1 = {Ix1, Si1}, TargetValue1} ->
	    ct:pal("Application got set ~.16B:~w updated to ~p",
		   [Ix1, Si1, TargetValue1]);
	{set, TargetIndex2 = {Ix2, Si2}, TargetValue2} ->
	    ct:pal("Application got set ~.16B:~w updated to ~p",
		   [Ix2, Si2, TargetValue2]);
	_Other1 ->
	    ct:pal("Received other = ~p", [_Other1]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:fail("Application did not get set")
    end,
    ok.
