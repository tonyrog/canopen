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

stop_app(App, CoNode) when is_integer(CoNode) ->
    stop_app(App, integer_to_list(CoNode));
stop_app(App, CoNode) when is_atom(CoNode) ->
    stop_app(App, atom_to_list(CoNode));
stop_app(App, CoNode) ->
    case whereis(list_to_atom(atom_to_list(App) ++ CoNode)) of
	undefined  -> do_nothing;
	_Pid -> co_test_app:stop(serial())
    end.


set_get_tests() ->
    [test(set ,Name, segment) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)] ++
	[test(get, Name, segment) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)] ++
	[test(set, Name, block) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)] ++
	[test(get, Name, block) || {Name, {_Entry, _NewValue}} <- ct:get_config(dict)].

test(SetOrGet, Name, BlockOrSegment) ->
    list_to_atom(atom_to_list(SetOrGet) ++ "_" ++ atom_to_list(Name) ++ "-" ++
		     atom_to_list(BlockOrSegment)).

