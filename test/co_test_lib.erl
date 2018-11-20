%%% coding: latin-1"
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
-module(co_test_lib).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").

-define(DICT, "test.dict").


start_system() ->
    start_system(2,0).
%%    start_system(0,1). %% Default for can_udp.

start_system(_C) ->
    start_system(2,0).

start_system(Port, Ttl) ->
    ale:start(),
    can_udp:start(Port, [{ttl, Ttl}]),
    {ok, PPid} = co_proc:start_link([{linked, false}]),
    ct:pal("Started co_proc ~p",[PPid]).

stop_system() ->
    stop_system(2).

stop_system(Port) ->
    co_proc:stop(),
    can_udp:stop(Port),
    can_router:stop(),
    ale:stop().

start_node(C) ->
    %% From test suite
    start_node(C, serial()).

start_node(C, Opts) when is_list(C) andalso is_list(Opts) ->
    %% From test suite
    start_node(C, serial(), Opts);
start_node(C, Serial) when is_list(C) ->
    %% From test suite
    start_node(C, Serial, [{debug, false}]).

start_node(C, Serial, Opts) when is_list(C) andalso is_list(Opts) ->
    %% From test suite
    DataDir = ?config(data_dir, C),
    Dict = filename:join(DataDir, ?DICT),
    start_node(Serial, Dict, [{debug, true} | Opts]);
start_node(Serial, Dict, Opts) ->
    try co_api:alive(Serial) of
	true -> co_api:stop(Serial); %% Clean up failed ??
	false -> do_nothing
    catch error:_Reason ->
	    do_nothing
    end,

    %% Use seconds as revision
    {MegaSec, Sec, _MicroSec} = os:timestamp(),
    {ok, Pid} = co_api:start_link(Serial, Opts ++
				      [{use_serial_as_xnodeid, true},
				       {dict, Dict},
				       {max_blksize, 7},
				       {vendor,16#2A1},
				       {product, 16#0001},
				       {revision, MegaSec * 1000000 + Sec},
				       {linked, false}]),
    ct:pal("Started co_node ~p, pid = ~p",[integer_to_list(Serial,16), Pid]),
    co_api:save_dict(Serial),
    {ok, Pid}.


stop_node(Config) when is_list(Config) ->
    stop_node(serial());
stop_node(Serial) ->
    case whereis(list_to_atom(co_lib:serial_to_string(Serial))) of
	Pid when is_pid(Pid) ->
	    co_api:stop(Pid);
	undefined ->
	    ok
    end.

load_dict(C) ->
    load_dict(C, serial()).

load_dict(C, Serial) ->
    DataDir = ?config(data_dir, C),
    co_api:load_dict(Serial, filename:join(DataDir, ?DICT)).

serial() ->
    case os:getenv("CO_SERIAL") of
	false ->
	    ct:get_config(serial);
	"0x"++SerX -> erlang:list_to_integer(SerX, 16);
	Ser -> erlang:list_to_integer(Ser, 10)
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


name(Module, Serial) when is_integer(Serial) ->
    list_to_atom(atom_to_list(Module) ++ "-" ++ integer_to_list(Serial,16));
name(Module, {name, Name}) when is_atom(Name) ->
    %% co_mgr ??
    list_to_atom(atom_to_list(Module) ++ "_" ++ atom_to_list(Name));
name(Module, {_Tag, Id}) when is_integer(Id)->
    list_to_atom(atom_to_list(Module) ++ "-" ++ integer_to_list(Id,16)).

set_cmd(Config, Index, Value, Type, BFlag) ->
    set_cmd(Config, Index, Value, Type, BFlag, undefined).

set_cmd(Config, Index, Value, Type, BFlag, Tout) ->
    Cmd = set_cmd1(Config, Index, Value, Type, BFlag, Tout),
    ct:pal("Command = ~p",[Cmd]),
    Cmd.

set_cmd1(_Config, Index, Value, Type, BFlag, Tout) ->
    cocli() ++ bflag(BFlag) ++ " -T " ++ atom_to_list(Type) ++
	" -s " ++ serial_as_c_string(serial()) ++ timeout(Tout) ++
	" set " ++ index_as_c_string(Index) ++ value(Value).

get_cmd(Config, Index, Type, BFlag) ->
    get_cmd(Config, Index, Type, BFlag, undefined).
    
get_cmd(Config, Index, Type, BFlag, Tout) ->
    Cmd = get_cmd1(Config, Index, Type, BFlag, Tout),
    ct:pal("Command = ~p",[Cmd]),
    Cmd.

get_cmd1(_Config, Index, Type, BFlag, Tout) ->
    cocli() ++ bflag(BFlag) ++ " -T " ++ atom_to_list(Type) ++
	" -s " ++ serial_as_c_string(serial()) ++ timeout(Tout) ++
	" -e" ++ " get " ++ index_as_c_string(Index).

file_cmd(Config, Index, Direction, BFlag) ->
    cocli() ++ bflag(BFlag) ++ " -s " ++ 
	serial_as_c_string(serial()) ++ " " ++ 
	Direction ++ " " ++ index_as_c_string(Index) ++ " " ++
	filename:join(?config(priv_dir, Config), "tmp_file").
    
notify_cmd(Config, Index, Value, BFlag) ->
    Cmd = notify_cmd1(Config, Index, Value, BFlag),
    ct:pal("Command = ~p",[Cmd]),
    Cmd.

notify_cmd1(_Config, Index, Value, BFlag) ->
    cocli() ++ bflag(BFlag) ++ " -s " ++ 
	serial_as_c_string(serial()) ++ " notify " ++
	index_as_c_string(Index) ++ value(Value).

bflag(segment) ->
    "";
bflag(block) ->
    " -b".

timeout(undefined) ->
    "";
timeout(Tout) ->
    " -y " ++ integer_to_list(Tout).

value(Value) when is_integer(Value) ->
    " " ++ integer_to_list(Value);
value(Value) when is_list(Value) ->
" \"" ++ Value ++ "\"".

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
	     

parse_get_result(S) ->
    {ok, Tokens, _End} = erl_scan:string(S),
    {ok, [Abs]} = erl_parse:parse_exprs(Tokens),
    erl_parse:normalise(Abs).
    
full_index(Ix) when is_integer(Ix) ->
    {Ix, 0};
full_index({_Ix, _Si} = I) ->
    I.

cocli() ->
    Cmd = filename:join([os:getenv("HOME"),"bin","cocli"]),
    %% Cmd = "cocli",
    Cmd ++ " -Iudp -i2".

md5_file(File) ->
    {ok,Bin} = file:read_file(File),
    erlang:md5(Bin).

type(T) -> co_lib:encode_type(T).

set_get_tests() ->
    [test(set ,Name, segment) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)] ++
	[test(get, Name, segment) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)] ++
	[test(set, Name, block) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)] ++
	[test(get, Name, block) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)].

test(SetOrGet, Name, BlockOrSegment) ->
    list_to_atom(atom_to_list(SetOrGet) ++ "_" ++ atom_to_list(Name) ++ "-" ++
		     atom_to_list(BlockOrSegment)).

