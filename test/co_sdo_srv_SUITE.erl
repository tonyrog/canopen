%%%-------------------------------------------------------------------
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2011, Marina Westman Lönne
%%% @doc
%%%
%%% @end
%%% Created : 29 Nov 2011 by Marina Westman Lönne <malotte@malotte.net>
%%%-------------------------------------------------------------------
-module(co_sdo_srv_SUITE).

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
    [set_dict_segment,
     get_dict_segment,
     set_dict_block,
     get_dict_block,
     set_atomic_segment,
     get_atomic_segment,
     set_atomic_block,
     get_atomic_block,
     set_atomic_exp,
     get_atomic_exp,
     set_atomic_m_segment,
     get_atomic_m_segment,
     set_atomic_m_block,
     get_atomic_m_block,
     set_streamed_segment,
     get_streamed_segment,
     set_streamed_block,
     get_streamed_block,
     set_streamed_exp,
     get_streamed_exp,
     set_streamed_m_segment,
     get_streamed_m_segment,
     set_streamed_m_block,
     get_streamed_m_block,
     stream_file_segment,
     stream_file_block,
     stream_0file_segment,
     stream_0file_block,
     notify,
     mpdo,
     timeout].
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
%% @spec init_per_group(GroupName, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
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
%% @spec end_per_group(GroupName, Config0) ->
%%               void() | {save_config,Config1}
%% @end
%%--------------------------------------------------------------------
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
%% @spec init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
init_per_testcase(_TestCase = timeout, Config) ->
    ct:pal("Testcase: ~p", [_TestCase]),
    {ok, Pid} = co_test_app:start(serial(), app_dict()),
    ok = co_test_app:debug(Pid, true),

    %% Change the timeout for the co_node
    {sdo_timeout, OldTOut} = co_node:get_option(serial(), sdo_timeout),
    ok = co_node:set_option(serial(), sdo_timeout, 500),
    [{timeout, OldTOut} | Config];

init_per_testcase(_TestCase, Config) ->
    ct:pal("Testcase: ~p", [_TestCase]),
    {ok, Pid} = co_test_app:start(serial(), app_dict()),
    ok = co_test_app:debug(Pid, true),
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
end_per_testcase(Case, Config) when Case == stream_file_segment;
				    Case == stream_file_block;
				    Case == stream_0file_segment;
				    Case == stream_0file_block ->
    co_test_lib:stop_app(co_test_stream_app, []),

    PrivDir = ?config(priv_dir, Config),
    RFile = filename:join(PrivDir, ct:get_config(read_file)),
    WFile = filename:join(PrivDir, ct:get_config(write_file)),

    os:cmd("rm " ++ RFile),
    os:cmd("rm " ++ WFile),

    ok;
end_per_testcase(timeout, Config) ->
    %% Wait a little for session to terminate
    timer:sleep(1000),
    co_test_lib:stop_app(co_test_app, serial()),

    %% Restore the timeout for the co_node
    OldTOut = ?config(timeout, Config),
    co_node:set_option(serial(), sdo_timeout, OldTOut),
    ok;

end_per_testcase(_TestCase, _Config) ->
    %% Wait a little for session to terminate
    timer:sleep(1000),
    co_test_lib:stop_app(co_test_app, serial()),
    ok.
%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @spec set_dict_segment(Config) -> ok 
%% @doc 
%% Sets a value in the co_node internal dict using segment between cocli and co_node.
%% @end
%%--------------------------------------------------------------------
set_dict_segment(Config) ->
    set(Config, ct:get_config(dict_index), segment).

%%--------------------------------------------------------------------
%% @spec get_dict_segment(Config) -> ok 
%% @doc 
%% Gets a value from the co_node internal dict using segment between cocli and co_node.
%% @end
%%--------------------------------------------------------------------
get_dict_segment(Config) ->
    get(Config, ct:get_config(dict_index), segment).

%%--------------------------------------------------------------------
%% @spec set_dict_block(Config) -> ok 
%% @doc 
%% Sets a value in the co_node internal dict using block between cocli and co_node
%% @end
%%--------------------------------------------------------------------
set_dict_block(Config) ->
    set(Config, ct:get_config(dict_index), block).

%%--------------------------------------------------------------------
%% @spec get_dict_block(Config) -> ok 
%% @doc 
%% Gets a value from the co_node internal using block between cocli and co_node.
%% @end
%%--------------------------------------------------------------------
get_dict_block(Config) ->
    get(Config, ct:get_config(dict_index), block).


%%--------------------------------------------------------------------
%% @spec set_atomic_segment(Config) -> ok 
%% @doc 
%% Sets a value using segment between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_atomic_segment(Config) ->
    set(Config, ct:get_config({dict, atomic}), segment).

%%--------------------------------------------------------------------
%% @spec get_atomic_segment(Config) -> ok 
%% @doc 
%% Gets a value using segment between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_atomic_segment(Config) ->
    get(Config, ct:get_config({dict, atomic}), segment).

%%--------------------------------------------------------------------
%% @spec set_atomic_block(Config) -> ok 
%% @doc 
%% Sets a value using block between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_atomic_block(Config) ->
    set(Config, ct:get_config({dict, atomic}), block).

%%--------------------------------------------------------------------
%% @spec get_atomic_block(Config) -> ok 
%% @doc 
%% Gets a value using block between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_atomic_block(Config) ->
    get(Config, ct:get_config({dict, atomic}), block).


%%--------------------------------------------------------------------
%% @spec set_atomic_exp(Config) -> ok 
%% @doc 
%% Sets a short value using segment between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_atomic_exp(Config) ->
    set(Config, ct:get_config({dict, atomic_exp}), segment).

%%--------------------------------------------------------------------
%% @spec get_atomic_exp(Config) -> ok 
%% @doc 
%% Gets a short value using segment between cocli and co_node and atomic 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_atomic_exp(Config) ->
    get(Config, ct:get_config({dict, atomic_exp}), segment).


%%--------------------------------------------------------------------
%% @spec set_streamed_segment(Config) -> ok 
%% @doc 
%% Sets a value using segment between cocli and co_node and streamed 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_streamed_segment(Config) ->
    set(Config, ct:get_config({dict, streamed}), segment).

%%--------------------------------------------------------------------
%% @spec get_streamed_segment(Config) -> ok 
%% @doc 
%% Gets a value using segment between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_streamed_segment(Config) ->
    get(Config, ct:get_config({dict, streamed}), segment).

%%--------------------------------------------------------------------
%% @spec set_streamed_block(Config) -> ok 
%% @doc 
%% Sets a value using block between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_streamed_block(Config) ->
    set(Config, ct:get_config({dict, streamed}), block).

%%--------------------------------------------------------------------
%% @spec get_streamed_block(Config) -> ok 
%% @doc 
%% Gets a value using block between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_streamed_block(Config) ->
    get(Config, ct:get_config({dict, streamed}), block).

%%--------------------------------------------------------------------
%% @spec set_streamed_exp(Config) -> ok 
%% @doc 
%% Sets a short value using segment between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_streamed_exp(Config) ->
    set(Config, ct:get_config({dict, streamed_exp}), segment).

%%--------------------------------------------------------------------
%% @spec get_streamed_exp(Config) -> ok 
%% @doc 
%% Gets a short value using segment between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_streamed_exp(Config) ->
    get(Config, ct:get_config({dict, streamed_exp}), segment).

%%--------------------------------------------------------------------
%% @spec set_atomic_m_segment(Config) -> ok 
%% @doc 
%% Sets a value using segment between cocli and co_node and {atomic, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_atomic_m_segment(Config) ->
    set(Config, ct:get_config({dict, atomic_m}), segment).

%%--------------------------------------------------------------------
%% @spec get_atomic_m_segment(Config) -> ok 
%% @doc 
%% Gets a value using segment between cocli and co_node and {atomic, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_atomic_m_segment(Config) ->
    get(Config, ct:get_config({dict, atomic_m}), segment).

%%--------------------------------------------------------------------
%% @spec set_atomic_m_block(Config) -> ok 
%% @doc 
%% Sets a value using segment between cocli and co_node and {atomic, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_atomic_m_block(Config) ->
    set(Config, ct:get_config({dict, atomic_m}), block).

%%--------------------------------------------------------------------
%% @spec get_atomic_m_block(Config) -> ok 
%% @doc 
%% Gets a value using segment between cocli and co_node and {atomic, Module} 
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_atomic_m_block(Config) ->
    get(Config, ct:get_config({dict, atomic_m}), block).

%%--------------------------------------------------------------------
%% @spec set_streamed_m_segment(Config) -> ok 
%% @doc 
%% Sets a value using segment between cocli and co_node and {streamed, Module}
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_streamed_m_segment(Config) ->
    set(Config, ct:get_config({dict, streamed_m}), segment).

%%--------------------------------------------------------------------
%% @spec get_streamed_m_segment(Config) -> ok 
%% @doc 
%% Gets a value using segment between cocli and co_node and {streamed, Module}
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_streamed_m_segment(Config) ->
    get(Config, ct:get_config({dict, streamed_m}), segment).

%%--------------------------------------------------------------------
%% @spec set_streamed_m_block(Config) -> ok 
%% @doc 
%% Sets a value using block between cocli and co_node and {streamed, Module}
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_streamed_m_block(Config) ->
    set(Config, ct:get_config({dict, streamed_m}), block).

%%--------------------------------------------------------------------
%% @spec get_streamed_m_block(Config) -> ok 
%% @doc 
%% Gets a value using block between cocli and co_node and {streamed, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_streamed_m_block(Config) ->
    get(Config, ct:get_config({dict, streamed_m}), block).


%%--------------------------------------------------------------------
%% @spec stream_file_segment(Config) -> ok 
%% @doc 
%% Tests streaming of file cocli -> co_test_stream_app -> cocli 
%% @end
%%--------------------------------------------------------------------
stream_file_segment(Config) ->
    stream_file(Config, segment, 50).

%%--------------------------------------------------------------------
%% @spec stream_file_block(Config) -> ok 
%% @doc 
%% Tests streaming of file cocli -> co_test_stream_app -> cocli 
%% @end
%%--------------------------------------------------------------------

stream_file_block(Config) ->
    stream_file(Config, block, 50).


%%--------------------------------------------------------------------
%% @spec stream_0file_segment(Config) -> ok 
%% @doc 
%% Tests streaming of 0 size file cocli -> co_test_stream_app -> cocli 
%% @end
%%--------------------------------------------------------------------
stream_0file_segment(Config) ->
    stream_file(Config, segment, 0).

%%--------------------------------------------------------------------
%% @spec stream_0file_block(Config) -> ok 
%% @doc 
%% Tests streaming of 0 size file cocli -> co_test_stream_app -> cocli 
%% @end
%%--------------------------------------------------------------------

stream_0file_block(Config) ->
    stream_file(Config, block, 0).


%%--------------------------------------------------------------------
%% @spec notify(Config) -> ok 
%% @doc 
%% Sets a value for an index in the co_node dictionary on which 
%% co_test_app subscribes.
%% @end
%%--------------------------------------------------------------------
notify(Config) ->
    {{Index = {Ix, _Si}, _T, _M, _Org}, NewValue} = ct:get_config({dict, notify}),
    [] = os:cmd(co_test_lib:set_cmd(Config, Index, NewValue, segment)),
    
    receive 
	{object_event, Ix} ->
	    ct:pal("Application notified",[]),
	    ok;
	Other ->
	    ct:pal("Received other = ~p", [Other]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:fail("Application not notified")
    end.

%%--------------------------------------------------------------------
%% @spec mpdo(Config) -> ok 
%% @doc 
%% Sends an mpdo that is broadcasted to all subscribers.
%% @end
%%--------------------------------------------------------------------
mpdo(Config) ->
    {{Index = {Ix, _Si}, _T, _M, _Org}, NewValue} = ct:get_config({dict, mpdo}),
    "ok\n" = os:cmd(co_test_lib:notify_cmd(Config, Index, NewValue, segment)),
    
    receive 
	{notify, Ix} ->
	    ct:pal("Application notified",[]),
	    ok;
	Other ->
	    ct:pal("Received other = ~p", [Other]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:fail("Application not notified")
    end.

%%--------------------------------------------------------------------
%% @spec timeout(Config) -> ok 
%% @doc 
%% Negative test of what happens if the receiving causes a timeout.
%% @end
%%--------------------------------------------------------------------
timeout(Config) ->

    %% Set
    {{Index, _T, _M, _Org}, NewValue} = ct:get_config({dict, timeout}),
    "cocli: error: error: timed out\n" = 
	os:cmd(co_test_lib:set_cmd(Config, Index, NewValue, segment)),

    receive 
	{set, Index, NewValue} ->
	    ct:pal("Application notified",[]),
	    ok;
	Other ->
	    ct:pal("Received other = ~p", [Other]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:pal("Application not notified")
    end,
    
    %% Get
    get(Config, ct:get_config({dict, timeout}), segment).


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

%%--------------------------------------------------------------------
%% @spec set(Config, {Entry, _NewValue}, BlockOrSegment) -> ok 
%% @doc 
%% Sets a value using BlockOrSegment between cocli and co_node.
%% Transfer mode is defined by application based on index.
%% Gets the old value using cocli and compares it with the value retrieved
%% from the apps dictionary.
%% Sets a new value and compares it.
%% Restores the old calue.
%% @end
%%--------------------------------------------------------------------
set(Config, {{Index, _T, _M, _Org}, NewValue}, BlockOrSegment) ->
    %% Get old value
    {Index, _Type, _Transfer, OldValue} = 
	lists:keyfind(Index, 1, co_test_app:dict(serial())),
							
    %% Change to new
    [] = os:cmd(co_test_lib:set_cmd(Config, Index, NewValue, BlockOrSegment)),
    {Index, _Type, _Transfer, NewValue} = 
	lists:keyfind(Index, 1, co_test_app:dict(serial())),
    
    receive 
	{set, Index, NewValue} ->
	    ct:pal("Application set done",[]),
	    ok;
	Other1 ->
	    ct:pal("Received other = ~p", [Other1]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:pal("Application set not done")
    end,

    %% Restore old
    [] = os:cmd(co_test_lib:set_cmd(Config, Index, OldValue, BlockOrSegment)),
    {Index, _Type, _Transfer, OldValue} = 
	lists:keyfind(Index, 1, co_test_app:dict(serial())),

    receive 
	{set, Index, OldValue} ->
	    ct:pal("Application set done",[]),
	    ok;
	Other2 ->
	    ct:pal("Received other = ~p", [Other2]),
	    ct:fail("Received other")
    after 5000 ->
	    ct:pal("Application set not done")
    end,
    ok;
set(Config, {Index, NewValue}, BlockOrSegment) ->
    %% co_node internal dict
    [] = os:cmd(co_test_lib:set_cmd(Config, Index, NewValue, BlockOrSegment)).
   


%%--------------------------------------------------------------------
%% @spec get(Config, {Entry, _NewValue}, BlockOrSegment) -> ok 
%% @doc 
%% Gets a value using BlockOrSegment between cocli and co_node.
%% Transfer mode is defined by application based on index.
%% Gets the value using cocli and compares it with the value retrieved
%% from the apps dictionary.
%% @end
%%--------------------------------------------------------------------
get(Config, {{Index, _T, _M, _Org}, _NewValue}, BlockOrSegment) ->

    Result = os:cmd(co_test_lib:get_cmd(Config, Index, BlockOrSegment)),

    %% For now ....
    case Result of
	"0x6033 = 1701734733\n" -> ok;
	"0x6034 = \"Long string\"\n" -> ok;
	"0x6035 = \"Mine2\"\n" -> ok;
	"0x6036 = \"Long string2\"\n" -> ok;
	"0x6037 = 65\n" -> ok;
	"0x6038 = 67\n" -> ok;
	"cocli: error: failed to retrive value for '0x7334' timed out\n" -> ok
    end,

    ct:pal("Result = ~p", [Result]),

    %% Get value from cocli and compare with dict
    %% {Index, _Type, _Transfer, Value} = lists:keyfind(Index, 1, co_test_app:dict(serial())),
    
    ok;
get(Config, {Index, _NewValue}, BlockOrSegment) ->
    %% co_node internal dict
    Result = os:cmd(co_test_lib:get_cmd(Config, Index, BlockOrSegment)),
    ct:pal("Result = ~p", [Result]),
    
    Result = "0x2002 = \"New string aaaaabbbbbbbccccccddddddeeeee\"\n".



stream_file(Config, TransferMode, Size) ->
    PrivDir = ?config(priv_dir, Config),
    RFile = filename:join(PrivDir, ct:get_config(read_file)),
    WFile = filename:join(PrivDir, ct:get_config(write_file)),

    co_test_lib:generate_file(RFile, Size),

    Md5Res1 = os:cmd("md5 " ++ RFile),
    [_,_,_,Md5] = string:tokens(Md5Res1," "),

    {ok, _Pid} = co_test_stream_app:start(serial(), 
					  {ct:get_config(file_stream_index), 
					   RFile, WFile}),
    ct:pal("Started stream app"),
    timer:sleep(1000),

    [] = os:cmd(co_test_lib:file_cmd(Config, ct:get_config(file_stream_index), 
				     "download", TransferMode)),
    %% ct:pal("Started download of file from stream app, result = ~p",[Res1]),
    receive 
	eof ->
	    ct:pal("Application upload finished",[]),
	    timer:sleep(1000),
	    ok
    after 5000 ->
	    ct:fail("Application stuck")
    end,

    [] = os:cmd(co_test_lib:file_cmd(Config, ct:get_config(file_stream_index), 
				     "upload", TransferMode)),
    %% ct:pal("Started upload of file to stream app, result = ~p",[Res2]),
    receive 
	eof ->
	    ct:pal("Application download finished",[]),
	    timer:sleep(1000),
	    ok
    after 5000 ->
	    ct:fail("Application stuck")
    end,

    %% Check that file is unchanged
    Md5Res2 = os:cmd("md5 " ++ WFile),
    [_,_,_,Md5] = string:tokens(Md5Res2," "),
    
    ok.


