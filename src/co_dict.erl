%%% File    : co_dict.erl
%%% Author  : Tony Rogvall <tony@PBook.lan>
%%% Description : CANopen runtime dictionary 
%%% Created :  6 Feb 2008 by Tony Rogvall <tony@PBook.lan>

-module(co_dict).

-export([new/0, new/1,
	 from_file/1, from_file/2,
	 to_file/2, to_fd/2, to_fd/3, 
	 add_from_file/2,
	 delete/1,
	 first_object/1, first_object/2, 
	 last_object/1, last_object/2, 
	 next_object/2, next_object/3,
	 prev_object/2, prev_object/3,
	 find_object/5,
	 add_object/3, add_entry/2,
	 delete_object/2, delete_entry/2,
	 update_object/2, update_entry/2,
	 lookup_object/2, lookup_entry/2,
	 set/4, direct_set/4,
	 set_array/3, set_objects/3,
	 value/3, direct_value/3
	]).
-import(lists,[map/2, foreach/2]).

-include("../include/canopen.hrl").


%%
%% Note: this table contains two types of objects
%%       {dict_object, index=<integer>, ...}
%%       {dict_enty,   index={<integer>,<integer>}, ...}
%% key position MUST be 2 on both records
%%
new() ->
    new(public).

new(Access) ->
    init(ets:new(co_dict, [{keypos,2},Access,ordered_set])).

init(Dict) ->
    %% Install type nodes
    foreach(fun({Index,Size}) ->
		ets:insert(Dict,
			   #dict_object { index=Index, 
					  access=?ACCESS_RO,
					  struct=?OBJECT_DEFTYPE,
					  type=?UNSIGNED32 }),
		ets:insert(Dict,
			   #dict_entry { index={Index,0},
					 access=?ACCESS_RO,
					 type=?UNSIGNED32,
					 value=Size })
	end,
	[{?BOOLEAN, 1}, 
	 {?INTEGER8,8}, 
	 {?INTEGER16,16},
	 {?INTEGER32,32},
	 {?UNSIGNED8,8},
	 {?UNSIGNED16,16},
	 {?UNSIGNED32,32},
	 {?REAL32,32},
	 {?VISIBLE_STRING,0},
	 {?OCTET_STRING,0},
	 {?UNICODE_STRING,0},
	 {?TIME_OF_DAY,48},
	 {?TIME_DIFFERENCE,48},
	 {?BIT_STRING,0},
	 {?DOMAIN,0},
	 {?INTEGER24,0},
	 {?REAL64,64},
	 {?INTEGER40,40},
	 {?INTEGER48,48},
	 {?INTEGER56,56},
	 {?INTEGER64,64},
	 {?UNSIGNED24,24},
	 {?UNSIGNED40,40},
	 {?UNSIGNED48,48},
	 {?UNSIGNED56,56},
	 {?UNSIGNED64,64},
	 {?COMMAND_PAR,0}]),
    Dict.
				    

from_file(File) ->
    from_file(protected, File).

from_file(Access,File) ->
    case co_file:load(File) of
	{ok,Os} ->
	    Dict = new(Access),
	    add_objects(Dict, Os),
	    {ok,Dict};
	Error -> Error
    end.

add_from_file(Dict, File) ->
    case co_file:load(File) of
	{ok,Os} ->
	    add_objects(Dict, Os),
	    {ok,Dict};
	Error ->
	    Error
    end.

%% Add objects and entries
add_objects(Dict, [{Obj,Es}|Os]) when is_record(Obj, dict_object) ->
    add_object(Dict, Obj, Es),
    add_objects(Dict, Os);
add_objects(_Dict, []) ->
    ok.

to_file(Dict, File) ->
    case file:open(File, [write]) of
	{ok,Fd} ->
	    Res = to_fd(Dict, Fd),
	    file:close(Fd),
	    Res;
	Error ->
	    Error
    end.

to_fd(Dict, Fd) ->
    to_fd(Dict, first_object(Dict), Fd).
    

to_fd(_Dict, '$end_of_table', _Fd) ->
    ok;
to_fd(Dict, Ix, Fd) ->
    case ets:lookup(Dict, Ix) of
	[O] when O#dict_object.struct == ?OBJECT_VAR ->
	    Value = 
		if O#dict_object.access == ?ACCESS_WO ->
			[];
		   true ->
			case ets:lookup(Dict, {Ix,0}) of
			    [] -> [];
			    [E] -> [{value,E#dict_entry.value}]
			end
		end,
	    Var = {object,Ix,
		   [{struct,var},
		    {access,co_lib:decode_access(O#dict_object.access)},
		    {type,co_lib:decode_type(O#dict_object.type)} |
		    Value]},
	    io:format(Fd, "~p\n", [Var]),
	    to_fd(Dict, next_object(Dict, Ix), Fd);
	[O] ->
	    Es = read_entries(Dict, Ix, -1, []),
	    Obj = {object,Ix,
		   [{struct,co_lib:decode_struct(O#dict_object.struct)},
		    {access,co_lib:decode_access(O#dict_object.access)},
		    {type,co_lib:decode_type(O#dict_object.type)} |
		    Es]},
	    io:format(Fd, "~p\n", [Obj]),
	    to_fd(Dict, next_object(Dict, Ix), Fd);
	[] ->
	    to_fd(Dict, next_object(Dict, Ix), Fd)
    end.

		
read_entries(Dict, Ix, Sx, Es) ->
    case ets:next(Dict, {Ix,Sx}) of
	'$end_of_table' -> 
	    lists:reverse(Es);
	{Ix,Sx1} ->
	    [D] = ets:lookup(Dict, {Ix,Sx1}),
	    E = {entry,Sx1,
		 [{access,co_lib:decode_access(D#dict_entry.access)},
		  {type,co_lib:decode_type(D#dict_entry.type)},
		  {value,D#dict_entry.value}]},
	    read_entries(Dict,Ix,Sx1,[E|Es]);
	_ ->
	    lists:reverse(Es)
    end.

%%
%% Delete dictionary
%%
delete(Dict) ->
    ets:delete(Dict).

%%
%% Add a new object / new entry to dictionary
%%
add_object(Dict, Object, Es) when is_record(Object, dict_object) ->
    lists:foreach(fun(E) -> add_entry(Dict, E) end, Es),
    try ets:insert_new(Dict, Object) of
	_ -> ok
    catch
	error:badarg ->
	    {error,badarg}
    end.    

add_entry(Dict, Entry) when is_record(Entry, dict_entry) ->
    try ets:insert_new(Dict, Entry) of
	_ -> ok
    catch
	error:badarg ->
	    {error,badarg}
    end.

%%
%% Update existing object/entry
%%
update_object(Dict, Object) when is_record(Object, dict_object) ->
    case ets:member(Dict, Object#dict_object.index) of
	false -> erlang:error(badarg);
	true ->  ets:insert(Dict, Object)
    end.

update_entry(Dict, Entry) when is_record(Entry, dict_entry) ->
    case ets:member(Dict, Entry#dict_entry.index) of
	false -> erlang:error(badarg);
	true ->  ets:insert(Dict, Entry)
    end.

%%
%% Delete an object/entry
%%
delete_object(Dict, Ix) when ?is_index(Ix) ->
    ets:delete(Dict, Ix),
    ets:match_delete(Dict, #dict_entry { index={Ix,'_'}, _ = '_' }).
    
delete_entry(Dict, Index={Ix,Sx}) when ?is_index(Ix), ?is_subind(Sx) ->
    ets:delete(Dict, Index);
delete_entry(Dict, Ix) when ?is_index(Ix) ->
    delete_entry(Dict, {Ix,0}).

%%
%% Lookup object/entry in the dictionary
%% return {ok,Entry} | {ok,Object}
%%        {error, no_such_object}
%%        {error, no_such_subindex}
%%
lookup_object(Dict, Ix) when ?is_index(Ix) ->
    case ets:lookup(Dict, Ix) of
	[O] ->
	    {ok,O};
	[] ->
	    i_fail(Dict,Ix)
    end.


lookup_entry(Dict, Index={Ix,255}) ->
    case ets:lookup(Dict, Ix) of
	[O] ->
	    Value = ((O#dict_object.type band 16#ff) bsl 8) bor
		(O#dict_object.struct band 16#ff),
	    {ok,#dict_entry { index  = Index,
			      access = ?ACCESS_RO,
			      type   = ?UNSIGNED32,
			      value  = Value }};
	[] ->
	    i_fail(Dict,Ix)
    end;    
lookup_entry(Dict, Index={Ix,Sx}) when ?is_index(Ix), ?is_subind(Sx) ->
    case ets:lookup(Dict, Index) of
	[E] ->
	    {ok,E};
	[] ->
	    i_fail(Dict,Index)
    end;
lookup_entry(Dict, Ix) when ?is_index(Ix) ->
    lookup_entry(Dict, {Ix,0}).

%%
%% Set object/entry value in existing entry
%% return:
%%     {error,bad_access}
%%     {error,no_such_subindex}
%%     {error,no_such_object}
%%     ok 
%%
set(Dict, Ix, Si,Value) when ?is_index(Ix), ?is_subind(Si) ->
    Index = {Ix, Si},
    try ets:lookup_element(Dict, Index, #dict_entry.access) of
	?ACCESS_RO ->
	    {error,?abort_write_not_allowed};
	?ACCESS_C ->
	    {error,?abort_write_not_allowed};
	_ ->
	    direct_set(Dict, Ix, Si, Value)
    catch
	error:badarg ->
	    i_fail(Dict, Index);
	  error:What ->
	    erlang:error(What)
    end.

%% direct_set(Dict, Index, Value) 
%%   Work as set but without checking access !
%%
direct_set(Dict, Ix, Si,Value) when ?is_index(Ix), ?is_subind(Si) ->
    Index = {Ix, Si},
    case ets:update_element(Dict, Index, {#dict_entry.value, Value}) of
	false ->
	    i_fail(Dict, Index);
	true ->
	    ok
    end.

%% set an array of values index 1..254
set_array(Dict, Ix, Values) ->
    set_array(Dict, Ix, 1, Values).

set_array(Dict, Ix, Si, []) ->
    direct_set(Dict, Ix, 0, Si);  %% number of elements
set_array(Dict, Ix, Si, [Value|Vs]) when Si < 255 ->
    direct_set(Dict, Ix, Si, Value),
    set_array(Dict, Ix, Si+1, Vs).

%% set objects on consecutive indices
set_objects(Dict, Ix, [Obj|Objs]) ->
    set_array(Dict, Ix, 1, tuple_to_list(Obj)),
    set_objects(Dict, Ix+1, Objs);
set_objects(_Dict, _Ix, []) ->
    ok.

%%
%%     Get object/entry value
%% return:
%%     {error,bad_access}
%%     {error,no_such_subindex}
%%     {error,no_such_object}
%%     {ok,Value}
%%
value(Dict, Ix, Si) when ?is_index(Ix), ?is_subind(Si) ->
    Index = {Ix,Si},
    try ets:lookup_element(Dict, Index, #dict_entry.access) of
	?ACCESS_WO ->
	    {error,?abort_read_not_allowed};
	_ ->
	    {ok,ets:lookup_element(Dict, Index, #dict_entry.value)}
    catch
	error:badarg ->
	    i_fail(Dict, Index);
	  error:What ->
	    erlang:error(What)
    end.

%% direct_value
%%   Works as value/2 but without access check
%%
direct_value(Dict,Ix,Si) when ?is_index(Ix), ?is_subind(Si) ->
    ets:lookup_element(Dict, {Ix,Si}, #dict_entry.value).
    
%%
%% Search for dictionary entry when index I is with in range
%% Ix <= I <= Jx and ( value(I,Si) == Vf  or Vf(value(I,Si)) == true)
%%
%%
%% return {ok,I} if found 
%%        {error, no_such_object} otherwise
%%
%% FIXME: check if a match spec is better
%%
find_object(Dict, I, J, S, Vf) 
  when ?is_index(I), ?is_index(J), I =< J, ?is_subind(S) ->
    if S == 0 ->
	    match_entry_0(Dict,first_object(Dict, I),J,Vf);
       true ->
	    case ets:next(Dict,{I,S-1}) of
		{I,S} ->  %% found it
		    match_entry_s(Dict, I, J, S, Vf);
		{I,_} ->  %% not found but object exist
		    match_entry_s(Dict,next_object(Dict,I,J),J,S,Vf);
		{N,_} ->
		    match_entry_s(Dict,N,J,S,Vf);
		'$end_of_table' ->
		    {error, ?abort_no_such_object}
	    end
    end.
%%
%% Find I where value({I,S}) =:= V
%%   return {ok,I} if found
%%          {error,no_such_object}  otherwise
%%
match_entry_s(_Dict, I, J,_S,_Vf) when I > J; I =:= '$end_of_table' ->
    {error,?abort_no_such_object};
match_entry_s(Dict, I, J, S, Vf) ->
    try ets:lookup_element(Dict,{I,S},#dict_entry.value) of
	V when V == Vf ->
	    {ok,I};
	V when is_function(Vf) ->
	    case Vf(V) of
		true -> {ok,I};
		false ->
		    match_entry_s(Dict,next_object(Dict,I,J),J,S,Vf)
	    end;
	_ ->
	    match_entry_s(Dict,next_object(Dict,I,J),J,S,Vf)
    catch
	error:badarg ->
	    match_entry_s(Dict,next_object(Dict,I,J),J,S,Vf)
    end.
%%
%% Find I where value({I,0}) =:= V
%%   return {ok,I} if found
%%          {error,no_such_object}  otherwise
%%
match_entry_0(_Dict, I, J, _Vf) when I > J; I == '$end_of_tbale' ->
    {error, ?abort_no_such_object};    
match_entry_0(Dict, I, J, Vf) ->
    case ets:lookup_element(Dict, {I,0}, #dict_entry.value) of
	V when V == Vf ->
	    {ok,I};
	V when is_function(Vf) ->
	    case Vf(V) of
		true -> {ok,I};
		false ->
		    match_entry_0(Dict,next_object(Dict,I,J),J,Vf)
	    end;
	_ ->
	    match_entry_0(Dict,next_object(Dict,I,J),J,Vf)
    end.

%%
%% Find first object with index Jx where Jx >= Ix
%% return Jx or '$end_of_table'
%%
first_object(Dict) ->
    first_object(Dict, 0).

first_object(Dict, Ix) when ?is_index(Ix) ->
    case ets:next(Dict, Ix-1) of
	Jx when is_integer(Jx), Jx >= Ix -> 
	    Ix;
	_ ->
	    '$end_of_table'
    end.

%%
%% Find last object with index Jx where Jx >= Ix
%%
last_object(Dict) ->
    last_object(Dict, 16#ffff).

last_object(Dict, Ix) when ?is_index(Ix) ->
    case ets:prev(Dict,Ix+1) of
	Jx when is_integer(Jx), Jx =< Ix ->
	    Jx;
	_ ->
	    '$end_of_table'
    end.
%%
%% Find next object in dictionary after Ix when Ix <= Jx
%%
next_object(Dict, Ix) ->
    next_object(Dict, Ix, 16#ffff).

next_object(Dict, Ix, Jx) when ?is_index(Ix), ?is_index(Jx) ->
    case ets:next(Dict,Ix) of
	Kx when is_integer(Kx), Kx =< Jx ->
	    Kx;
	_ ->  '$end_of_table'
    end.

%%
%% Find prev object in dictionary after Ix when Ix >= Jx
%%
prev_object(Dict, Ix) ->
    prev_object(Dict, Ix, 0).

prev_object(Dict, Ix, Jx) when ?is_index(Ix), ?is_index(Jx) ->
    case ets:prev(Dict,Ix) of
	Kx when is_integer(Kx), Kx >= Jx ->
	    Kx;
	_ -> 
	    '$end_of_table'
    end.

%%
%% Determine the correct error response when a
%% dictionary lookup have failed.
%%
i_fail(_Dict, Ix) when is_integer(Ix) ->
    {error,?abort_no_such_object};
i_fail(Dict, {Ix,_Sx}) ->
    case ets:member(Dict,{Ix,0}) of
	true ->
	    {error,?abort_no_such_subindex};
	false ->
	    {error,?abort_no_such_object}
    end.
