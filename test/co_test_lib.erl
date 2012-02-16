%%%-------------------------------------------------------------------
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2011, Marina Westman Lönne
%%% @doc
%%%
%%% @end
%%% Created : 29 Nov 2011 by Marina Westman Lönne <malotte@malotte.net>
%%%-------------------------------------------------------------------
-module(co_test_lib).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").

-define(DICT, "test.dict").

start_node() ->
    start_node(serial()).

start_node(Serial) ->
    {ok, PPid} = co_proc:start_link([]),
    ct:pal("Started co_proc ~p",[PPid]),
    {ok, Pid} = co_node:start_link([{serial,Serial}, 
				     {options, [{use_serial_as_nodeid, true},
						{max_blksize, 7},
						{vendor,16#2A1},
						{debug, true}]}]),
    ct:pal("Started co_node ~p, pid = ~p",[integer_to_list(Serial,16), Pid]),
    {ok, Pid}.

load_dict(C) ->
    load_dict(C, serial()).

load_dict(C, Serial) ->
    DataDir = ?config(data_dir, C),
    co_node:load_dict(Serial, filename:join(DataDir, ?DICT)).

serial() ->
    case os:getenv("SERIAL") of
	false ->
	    ct:get_config(serial);
	S -> 
	    case string:tokens(S, "#") of
		["16", Serial] -> list_to_integer(Serial,16);
		[Serial] -> list_to_integer(Serial,16)
	    end
    end.

app_dict() ->
    [{Name, Entry} || {Name, {Entry, _NewV}} <- ct:get_config(dict)].

app_dict_cli() ->
    [{Name, {I,T,M,NewV}} || {Name, {{I,T,M,_OldV}, NewV}} <- ct:get_config(dict)].

generate_file(File, 0) ->
    {ok, F} = file:open(File, [write, raw, binary, delayed_write]),
    file:close(F),
    ok;
generate_file(File, Size) ->
    {ok, F} = file:open(File, [write, raw, binary, delayed_write]),
    write(F, "abcdefgh", Size),
    file:close(F),
    ok.

write(F, _Data, 0) ->
    file:write(F, << "EOF">>),
    ok;
write(F, Data, N) ->
    Bin = list_to_binary(Data ++ integer_to_list(N)),
    file:write(F, Bin), 
    write(F, Data, N-1).


stop_app(App, CoNode) when is_integer(CoNode) ->
    stop_app(App, CoNode, integer_to_list(CoNode));
stop_app(App, CoNode) when is_atom(CoNode) ->
    stop_app(App, CoNode, atom_to_list(CoNode));
stop_app(App, []) ->
    case whereis(App) of
	undefined  -> do_nothing;
	_Pid -> App:stop()
    end.
stop_app(App, CoNode, CoNodeString) ->
    case whereis(list_to_atom(atom_to_list(App) ++ CoNodeString)) of
	undefined  -> do_nothing;
	_Pid -> App:stop(CoNode)
    end.

set_cmd(Config, Index, Value, block) ->
    set_cmd(Config, Index, Value, " -b");
set_cmd(Config, Index, Value, segment) ->
    set_cmd(Config, Index, Value, "");
set_cmd(Config, Index, Value, BFlag) ->
    Cmd = set_cmd1(Config, Index, Value, BFlag),
    ct:pal("Command = ~p",[Cmd]),
    Cmd.

set_cmd1(Config, Index, Value, BFlag) ->
    cocli(Config) ++ BFlag ++ " -s " ++ 
	serial_as_c_string(serial()) ++ " set " ++ 
	index_as_c_string(Index) ++ " \"" ++ Value ++ "\"".

get_cmd(Config, Index, block) ->
    get_cmd(Config, Index, " -b");
get_cmd(Config, Index, segment) ->
    get_cmd(Config, Index, "");
get_cmd(Config, Index, BFlag) ->
    Cmd = get_cmd1(Config, Index, BFlag),
    ct:pal("Command = ~p",[Cmd]),
    Cmd.

get_cmd1(Config, Index, BFlag) ->
    cocli(Config) ++ BFlag ++ " -s " ++ 
	serial_as_c_string(serial()) ++ " get " ++ 
	index_as_c_string(Index).

file_cmd(Config, Index, Direction, block) ->
    file_cmd(Config, Index, Direction, " -b");
file_cmd(Config, Index, Direction, segment) ->
    file_cmd(Config, Index, Direction, "");
file_cmd(Config, Index, Direction, BFlag) ->
    cocli(Config) ++ BFlag ++ " -s " ++ 
	serial_as_c_string(serial()) ++ " " ++ 
	Direction ++ " " ++ index_as_c_string(Index) ++ " " ++
	filename:join(?config(priv_dir, Config), "tmp_file").
    
notify_cmd(Config, Index, Value, block) ->
    notify_cmd(Config, Index, Value, " -b");
notify_cmd(Config, Index, Value, segment) ->
    notify_cmd(Config, Index, Value, "");
notify_cmd(Config, Index, Value, BFlag) ->
    Cmd = notify_cmd1(Config, Index, Value, BFlag),
    ct:pal("Command = ~p",[Cmd]),
    Cmd.

notify_cmd1(Config, Index, Value, BFlag) ->
    cocli(Config) ++ BFlag ++ " -s " ++ 
	serial_as_c_string(serial()) ++ " notify " ++
	index_as_c_string(Index) ++ " \"" ++ Value ++ "\"".

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
	     
    
cocli(C) ->
    DataDir = ?config(data_dir, C),
    filename:join(DataDir, ct:get_config(cocli)).

type(T) -> co_lib:encode_type(T).

set_get_tests() ->
    [test(set ,Name, segment) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)] ++
	[test(get, Name, segment) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)] ++
	[test(set, Name, block) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)] ++
	[test(get, Name, block) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)].

test(SetOrGet, Name, BlockOrSegment) ->
    list_to_atom(atom_to_list(SetOrGet) ++ "_" ++ atom_to_list(Name) ++ "-" ++
		     atom_to_list(BlockOrSegment)).

