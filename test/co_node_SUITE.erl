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
%% @spec all() -> GroupsAndTestCases | {skip,Reason}
%% @end
%%--------------------------------------------------------------------
all() -> 
    [start_of_co_node,
     start_of_app,
     set_atomic_segment,
     set_atomic_block,
     set_streamed_segment,
     set_streamed_block,
     get_atomic_segment,
     get_atomic_block,
     get_streamed_segment,
     get_streamed_block,
     set_atomic_m_segment,
     set_atomic_m_block,
     set_streamed_m_segment,
     set_streamed_m_block,
     get_atomic_m_segment,
     get_atomic_m_block,
     get_streamed_m_segment,
     get_streamed_m_block,
     stream_app].
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
    [{co_app, [sequence],
     [start_of_app, 
      stop_of_app]}].


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
    {ok, _Pid} = co_node:start_link([{serial,ct:get_config(serial)}, 
				     {options, [extended, {vendor,0},
						{dict_file, "test.dict"}]}]),
    ct:pal("Started co_node"),
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
    co_node:stop(ct:get_config(serial)),
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
init_per_testcase(Case, Config) when Case == set_atomic_segment;
				     Case == set_atomic_block;
				     Case == set_streamed_segment;
				     Case == set_streamed_block;
				     Case == get_atomic_segment;
				     Case == get_atomic_block;
				     Case == get_streamed_segment;
				     Case == get_streamed_block ;
				     Case == set_atomic_m_segment;
				     Case == set_atomic_m_block;
				     Case == set_streamed_m_segment;
				     Case == set_streamed_m_block;
				     Case == get_atomic_m_segment;
				     Case == get_atomic_m_block;
				     Case == get_streamed_m_segment;
				     Case == get_streamed_m_block;
				     Case == break ->
    ct:pal("Testcase: ~p", [Case]),
    {ok, _Pid} = co_test_app:start(ct:get_config(serial)),
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
end_per_testcase(Case, _Config) when Case == set_atomic_segment;
				     Case == set_atomic_block;
				     Case == set_streamed_segment;
				     Case == set_streamed_block;
				     Case == get_atomic_segment;
				     Case == get_atomic_block;
				     Case == get_streamed_segment;
				     Case == get_streamed_block ;
				     Case == set_atomic_m_segment;
				     Case == set_atomic_m_block;
				     Case == set_streamed_m_segment;
				     Case == set_streamed_m_block;
				     Case == get_atomic_m_segment;
				     Case == get_atomic_m_block;
				     Case == get_streamed_m_segment;
				     Case == get_streamed_m_block ->
    %% Wait a little for session to terminate
    timer:sleep(200),
    ok = co_test_app:stop(),
    ok;
end_per_testcase(stream_app, _Config) ->
    ok = co_stream_app:stop(),
    ct:pal("Stopped stream app"),
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
%% @spec start_of_co_app(Config) -> ok 
%% @doc 
%% Verifies start of an app connecting to the co_node.
%% @end
%%--------------------------------------------------------------------
start_of_app(_Config) ->
    {ok, _Pid} = co_test_app:start(ct:get_config(serial)),
    timer:sleep(1000),
    ok.

%%--------------------------------------------------------------------
%% @spec stop_of_co_app(Config) -> ok 
%% @doc 
%% Verifies stop of an app connected to the co_node.
%% @end
%%--------------------------------------------------------------------
stop_of_app(_Config) ->
    ok = co_test_app:stop(),
    ok.

%%--------------------------------------------------------------------
%% @spec set_atomic_segment(Config) -> ok 
%% @doc 
%% Sets a value using block between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_atomic_segment(_Config) ->
    set(ct:get_config({dict, atomic}), segment).

%%--------------------------------------------------------------------
%% @spec set_atomic_block(Config) -> ok 
%% @doc 
%% Sets a value using segment between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_atomic_block(_Config) ->
    set(ct:get_config({dict, atomic}), block).

%%--------------------------------------------------------------------
%% @spec set_streamed_segment(Config) -> ok 
%% @doc 
%% Sets a value using segment between cocli and co_node and streamed 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_streamed_segment(_Config) ->
    set(ct:get_config({dict, streamed}), segment).

%%--------------------------------------------------------------------
%% @spec set_streamed_block(Config) -> ok 
%% @doc 
%% Sets a value using block between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_streamed_block(_Config) ->
    set(ct:get_config({dict, streamed}), block).

%%--------------------------------------------------------------------
%% @spec get_atomic_segment(Config) -> ok 
%% @doc 
%% Gets a value using block between cocli and co_node and atomic 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_atomic_segment(_Config) ->
    get(ct:get_config({dict, atomic}), segment).

%%--------------------------------------------------------------------
%% @spec get_atomic_block(Config) -> ok 
%% @doc 
%% Gets a value using segment between cocli and co_node and atomic 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_atomic_block(_Config) ->
    get(ct:get_config({dict, atomic}), block).


%%--------------------------------------------------------------------
%% @spec get_streamed_segment(Config) -> ok 
%% @doc 
%% Gets a value using segment between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_streamed_segment(_Config) ->
    get(ct:get_config({dict, streamed}), segment).

%%--------------------------------------------------------------------
%% @spec get_streamed_block(Config) -> ok 
%% @doc 
%% Gets a value using block between cocli and co_node and streamed 
%% atomic between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_streamed_block(_Config) ->
    get(ct:get_config({dict, streamed}), block).


%%--------------------------------------------------------------------
%% @spec set_atomic_m_segment(Config) -> ok 
%% @doc 
%% Sets a value using block between cocli and co_node and {atomic, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_atomic_m_segment(_Config) ->
    set(ct:get_config({dict, atomic_m}), segment).

%%--------------------------------------------------------------------
%% @spec set_atomic_m_block(Config) -> ok 
%% @doc 
%% Sets a value using segment between cocli and co_node and {atomic, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_atomic_m_block(_Config) ->
    set(ct:get_config({dict, atomic_m}), block).

%%--------------------------------------------------------------------
%% @spec set_streamed_m_segment(Config) -> ok 
%% @doc 
%% Sets a value using segment between cocli and co_node and {streamed, Module}
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_streamed_m_segment(_Config) ->
    set(ct:get_config({dict, streamed_m}), segment).

%%--------------------------------------------------------------------
%% @spec set_streamed_m_block(Config) -> ok 
%% @doc 
%% Sets a value using block between cocli and co_node and {streamed, Module}
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
set_streamed_m_block(_Config) ->
    set(ct:get_config({dict, streamed_m}), block).

%%--------------------------------------------------------------------
%% @spec get_atomic_m_segment(Config) -> ok 
%% @doc 
%% Gets a value using block between cocli and co_node and {atomic, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_atomic_m_segment(_Config) ->
    get(ct:get_config({dict, atomic_m}), segment).

%%--------------------------------------------------------------------
%% @spec get_atomic_m_block(Config) -> ok 
%% @doc 
%% Gets a value using segment between cocli and co_node and {atomic, Module} 
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_atomic_m_block(_Config) ->
    get(ct:get_config({dict, atomic_m}), block).


%%--------------------------------------------------------------------
%% @spec get_streamed_m_segment(Config) -> ok 
%% @doc 
%% Gets a value using segment between cocli and co_node and {streamed, Module}
%% atomic_m between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_streamed_m_segment(_Config) ->
    get(ct:get_config({dict, streamed_m}), segment).

%%--------------------------------------------------------------------
%% @spec get_streamed_m_block(Config) -> ok 
%% @doc 
%% Gets a value using block between cocli and co_node and {streamed, Module} 
%% between co_node and application.
%% @end
%%--------------------------------------------------------------------
get_streamed_m_block(_Config) ->
    get(ct:get_config({dict, streamed_m}), block).


%%--------------------------------------------------------------------
%% @spec stream_app(Config) -> ok 
%% @doc 
%% Tests streaming of file cocli -> co_stream_app -> cocli 
%% @end
%%--------------------------------------------------------------------
stream_app(_Config) ->
    generate_file(ct:get_config(read_file)),

    Md5Res1 = os:cmd("md5 " ++ ct:get_config(read_file)),
    [_,_,_,Md5] = string:tokens(Md5Res1," "),

    {ok, _Pid} = co_stream_app:start(ct:get_config(serial), 
				     {ct:get_config(file_stream_index), 
				      ct:get_config(read_file), 
				      ct:get_config(write_file)}),
    ct:pal("Started stream app"),
    timer:sleep(1000),

    [] = os:cmd(file_cmd(ct:get_config(file_stream_index), "download", block)),
    %% ct:pal("Started download of file from stream app, result = ~p",[Res1]),
    receive 
	eof ->
	    ct:pal("Application upload finished",[]),
	    timer:sleep(1000),
	    ok
    after 5000 ->
	    ct:fail("Application stuck")
    end,

    [] = os:cmd(file_cmd(ct:get_config(file_stream_index), "upload", block)),
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
    Md5Res2 = os:cmd("md5 " ++ ct:get_config(write_file)),
    %% Doesn't work because of cocli error
    %% [_,_,_,Md5] = string:tokens(Md5Res2," "),
    
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
%%--------------------------------------------------------------------
%% @spec get({Index, _NewValue}, BlockOrSegment -> ok 
%% @doc 
%% sets a value using BlockOrSegment between cocli and co_node.
%% Transfer mode is defined by application based on index.
%% Gets the old value using cocli and compares it with the value retrieved
%% from the apps dictionary.
%% Sets a new value and compares it.
%% Restores the old calue.
%% @end
%%--------------------------------------------------------------------
set({Index, _T, _M, _Org, NewValue}, BlockOrSegment) ->
    %% Get old value
    {Index, _Type, _Transfer, OldValue, _X} = lists:keyfind(Index, 1, co_test_app:dict()),
							
    %% Change to new
    [] = os:cmd(set_cmd(Index, NewValue, BlockOrSegment)),
    {Index, _Type, _Transfer, NewValue, _Y} = lists:keyfind(Index, 1, co_test_app:dict()),
    
    %% Restore old
    [] = os:cmd(set_cmd(Index, OldValue, BlockOrSegment)),
    {Index, _Type, _Transfer, OldValue, _X} = lists:keyfind(Index, 1, co_test_app:dict()),

    ok.


%%--------------------------------------------------------------------
%% @spec get({Index, _NewValue}, BlockOrSegment -> ok 
%% @doc 
%% Gets a value using BlockOrSegment between cocli and co_node.
%% Transfer mode is defined by application based on index.
%% Gets the value using cocli and compares it with the value retrieved
%% from the apps dictionary.
%% @end
%%--------------------------------------------------------------------
get({Index, _T, _M, _Org, _NewValue}, BlockOrSegment) ->

    Result = os:cmd(get_cmd(Index, BlockOrSegment)),

    %% For now ....
    case Result of
	"0x6033 = 1701734733\n" -> ok;
	"0x6034 = \"Long string\"\n" -> ok;
	"0x6035 = \"Mine2\"\n" -> ok;
	"0x6036 = \"Long string2\"\n" -> ok
    end,

    ct:pal("Result = ~p", [Result]),

    %% Get value from cocli and compare with dict
    %% {Index, _Type, _Transfer, Value} = lists:keyfind(Index, 1, co_test_app:dict()),
    
    ok.

generate_file(File) ->
    {ok, F} = file:open(File, [write, raw, binary, delayed_write]),
    write(F, "qwertyuiopasdfghjklzxcvbnm", 50),
    file:close(F),
    ok.

write(F, _Data, 0) ->
    file:write(F, << "EOF">>),
    ok;
write(F, Data, N) ->
    Bin = list_to_binary(Data ++ integer_to_list(N)),
    file:write(F, Bin), 
    write(F, Data, N-1).


set_cmd(Index, Value, block) ->
    set_cmd(Index, Value, " -b");
set_cmd(Index, Value, segment) ->
    set_cmd(Index, Value, "");
set_cmd(Index, Value, BFlag) ->
    Cmd = set_cmd1(Index, Value, BFlag),
    ct:pal("Command = ~p",[Cmd]),
    Cmd.

set_cmd1(Index, Value, BFlag) ->
    ct:get_config(cocli) ++ BFlag ++ " -s " ++ 
	serial_as_c_string(ct:get_config(serial)) ++ " set " ++ 
	index_as_c_string(Index) ++ " \"" ++ Value ++ "\"".

get_cmd(Index, block) ->
    get_cmd(Index, " -b");
get_cmd(Index, segment) ->
    get_cmd(Index, "");
get_cmd(Index, BFlag) ->
    Cmd = get_cmd1(Index, BFlag),
    ct:pal("Command = ~p",[Cmd]),
    Cmd.

get_cmd1(Index, BFlag) ->
    ct:get_config(cocli) ++ BFlag ++ " -s " ++ 
	serial_as_c_string(ct:get_config(serial)) ++ " get " ++ 
	index_as_c_string(Index).

file_cmd(Index, Direction, block) ->
    file_cmd(Index, Direction, " -b");
file_cmd(Index, Direction, segment) ->
    file_cmd(Index, Direction, "");
file_cmd(Index, Direction, BFlag) ->
    ct:get_config(cocli) ++ BFlag ++ " -s " ++ 
	serial_as_c_string(ct:get_config(serial)) ++ " " ++ 
	Direction ++ " " ++ index_as_c_string(Index) ++ " tmp_file".
    
index_as_c_string({Index, 0}) ->
    "0x" ++ integer_to_list(Index,16);
index_as_c_string({Index, SubInd}) ->
    "0x" ++ integer_to_list(Index,16) ++ ":" ++ integer_to_list(SubInd);
index_as_c_string(Index) when is_integer(Index)->
    "0x" ++ integer_to_list(Index,16).

serial_as_c_string(Serial) ->
    S = integer_to_list(Serial,16),
    S1 = string:substr(S, 1, length(S) - 2), 
    case length(S1) of
	3 -> "0x80000" ++ S1;
	4 -> "0x8000" ++ S1;
	5 -> "0x800" ++ S1;
	6 -> "0x80" ++ S1
    end.
	     
    
    
