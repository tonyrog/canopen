%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% CANopen runtime dictionary.
%%%
%%% File    : co_dict.erl<br/>
%%% Created : 6 Feb 2008 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(co_dict).
-include("canopen.hrl").

-export([new/0, new/1,
	 delete/1,
	 add_object/3, add_entry/2,
	 delete_object/2, delete_entry/2,
	 update_object/2, update_entry/2,
	 lookup_object/2, lookup_entry/2,
	 set_value/3, direct_set_value/3,
	 set_value/4, direct_set_value/4,
	 set_data/3, direct_set_data/3,
	 set_data/4, direct_set_data/4,
	 set_array_value/3, set_array_data/3,
	 data/2, data/3, direct_data/2, direct_data/3,
	 value/2, value/3, direct_value/2, direct_value/3,
	 to_file/2, to_fd/2
	]).

-import(lists,[map/2, foreach/2]).

%%--------------------------------------------------------------------
%% @doc
%% Creates a dictionary.
%% @end
%%--------------------------------------------------------------------
-spec new() -> Dict::term().
new() ->
    new(public).

%%--------------------------------------------------------------------
%% @doc
%% Creates a dictionary.
%%
%% Note: this table contains two types of objects
%%       {dict_object, Index, ...}
%%       {dict_entry,  {Index, SubInd}, ...}
%% key position MUST be 2 on both records
%%
%% @end
%%--------------------------------------------------------------------
-spec new(Access::public | private | protected) -> Dict::term().

new(Access) ->
    init(ets:new(co_dict, [{keypos,2},Access,ordered_set])).

deftype(Dict, Type, Size) ->
    ets:insert(Dict, #dict_object { index=Type,
				    access=?ACCESS_RO,
				    struct=?OBJECT_DEFTYPE,
				    type=?UNSIGNED32 }),
    %%
    %% DS301 - page 82 - 
    %% "A device may optionally provide the length of the standard data types
    %% encoded as UNSIGNED32 at read access to the index that refers to the 
    %% data type. E.g. index 000Ch (Time of Day) contains the value 30h=48dec 
    %% as the data type „Time of Day“ is encoded using a bit sequence of 48 bit.
    %% If the length is variable (e.g. 000Fh = Domain), the entry contains 0h.
    %%
    ets:insert(Dict, #dict_entry  { index={Type,0},
				    access=?ACCESS_RO,
				    type=?UNSIGNED32,
				    data=co_codec:encode(Size, ?UNSIGNED32)}).
    

%% add entries in entry table
%% "For the supported complex data types a device may optionally provide the 
%% structure of that data type at read access to the corresponding data type
%% index. Sub-index 0 then provides the number of entries at this index not 
%% counting sub-indices 0 and 255 and the following sub-indices contain the 
%% data type according to Table 39 encoded as UNSIGNED8. The entry at Index 
%% 20h describing the structure of the PDO Communication Parameter then looks
%%  as follows (see also objects 1400h – 15FFh):
%%
defstruct(Dict, Type, Fields) ->
    ets:insert(Dict, #dict_entry  { index={Type,0},
				    access=?ACCESS_RO,
				    type=?UNSIGNED8,
				    data = co_codec:encode(length(Fields),?UNSIGNED8) }),
    defstruct_fields(Dict, Type, 1, Fields).
    
defstruct_fields(Dict, Type, I, [F|Fs]) ->
    ets:insert(Dict, #dict_entry  { index={Type,I},
				    access=?ACCESS_RO,
				    type=?UNSIGNED8,
				    data = co_codec:encode(F,?UNSIGNED8) }),
    defstruct_fields(Dict, Type, I+1, Fs);
defstruct_fields(_Dict,_Type,_I,[]) ->
    ok.

init(Dict) ->
    deftype(Dict, ?BOOLEAN,         1),
    deftype(Dict, ?INTEGER8,        8),
    deftype(Dict, ?INTEGER16,       16),
    deftype(Dict, ?INTEGER32,       32),
    deftype(Dict, ?UNSIGNED8,       8),
    deftype(Dict, ?UNSIGNED16,      16),
    deftype(Dict, ?UNSIGNED32,      32),
    deftype(Dict, ?REAL32,          32),
    deftype(Dict, ?VISIBLE_STRING,  0),
    deftype(Dict, ?OCTET_STRING,    0),
    deftype(Dict, ?UNICODE_STRING,  0),
    deftype(Dict, ?TIME_OF_DAY,     48),
    deftype(Dict, ?TIME_DIFFERENCE, 48),
    deftype(Dict, ?BIT_STRING,      0),
    deftype(Dict, ?DOMAIN,          0),
    deftype(Dict, ?INTEGER24,      24),
    deftype(Dict, ?REAL64,         64),
    deftype(Dict, ?INTEGER40,      40),
    deftype(Dict, ?INTEGER48,      48),
    deftype(Dict, ?INTEGER56,      56),
    deftype(Dict, ?INTEGER64,      64),
    deftype(Dict, ?UNSIGNED24,     24),
    deftype(Dict, ?UNSIGNED40,     40),
    deftype(Dict, ?UNSIGNED48,     48),
    deftype(Dict, ?UNSIGNED56,     56),
    deftype(Dict, ?UNSIGNED64,     64),
    defstruct(Dict, ?PDO_PARAMETER, 
	      [?UNSIGNED32,  %% COB-ID
	       ?UNSIGNED8,   %% Transmission type
	       ?UNSIGNED16,  %% Inhibit timer
	       ?UNSIGNED8,   %% reserved
	       ?UNSIGNED16   %% Event timer
	      ]),
    defstruct(Dict, ?PDO_MAPPING, lists:duplicate(64, ?UNSIGNED32)),
    defstruct(Dict, ?SDO_PARAMETER, 
	      [?UNSIGNED32,   %% COB-ID: Client -> Server
	       ?UNSIGNED32,   %% COB-ID: Server -> Client
	       ?UNSIGNED8     %% Node ID of SDO's client/server 
	                      %% FIXME: Extend this to UNSIGNED32!
	      ]),
    defstruct(Dict, ?IDENTITY, 
	      [?UNSIGNED32,   %% Vendor ID
	       ?UNSIGNED32,   %% Product code
	       ?UNSIGNED32,   %% Revision number
	       ?UNSIGNED32    %% Serial number
	      ]),
    defstruct(Dict, ?DEBUGGER_PAR,
	      [?OCTET_STRING, %% Command
	       ?UNSIGNED8,    %% Status
	       ?OCTET_STRING  %% Reply
	      ]),
    defstruct(Dict, ?COMMAND_PAR,
	      [?OCTET_STRING, %% Command,
	       ?UNSIGNED8,    %% Status
	       ?OCTET_STRING  %% Reply
	      ]),
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

%%--------------------------------------------------------------------
%% @doc
%% Writes a dictionary to a file.
%%
%% @end
%%--------------------------------------------------------------------
-spec to_file(Dict::term(), FileName::string()) -> ok.

to_file(Dict, File) ->
    case file:open(File, [write]) of
	{ok,Fd} ->
	    Res = to_fd(Dict, Fd),
	    file:close(Fd),
	    Res;
	Error ->
	    Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% Writes a dictionary to a file. Converts binary data to value
%%
%% @end
%%--------------------------------------------------------------------
-spec to_fd(Dict::term(), FileDescriptor::term()) -> ok.

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
			    [E] -> 
				{V, _Rest} = co_codec:decode(E#dict_entry.data,
							     E#dict_entry.type),
				[{value, V }]
			end
		end,
	    Var = {object,Ix,
		   [{struct,var},
		    {access,co_lib:decode_access(O#dict_object.access)},
		    {type,co_lib:decode_type(O#dict_object.type)} |
		    Value]},
	    io:format(Fd, "~p.\n", [Var]),
	    to_fd(Dict, next_object(Dict, Ix), Fd);
	[O] ->
	    Es = read_entries(Dict, Ix, -1, []),
	    Obj = {object,Ix,
		   [{struct,co_lib:decode_struct(O#dict_object.struct)},
		    {access,co_lib:decode_access(O#dict_object.access)},
		    {type,co_lib:decode_type(O#dict_object.type)} |
		    Es]},
	    io:format(Fd, "~p.\n", [Obj]),
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
	    {V, _Rest} = co_codec:decode(D#dict_entry.data,
					 D#dict_entry.type),
	    E = {entry,Sx1,
		 [{access,co_lib:decode_access(D#dict_entry.access)},
		  {type,co_lib:decode_type(D#dict_entry.type)},
		  {value,V}]},
	    read_entries(Dict,Ix,Sx1,[E|Es]);
	_ ->
	    lists:reverse(Es)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Deletes a dictionary
%%
%% @end
%%--------------------------------------------------------------------
-spec delete(Dict::term()) -> ok.

delete(Dict) ->
    ets:delete(Dict).

%%--------------------------------------------------------------------
%% @doc
%% Add a new object to dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec add_object(Dict::term(), Object::record(), list(Entry::record())) ->
			ok | {error, badarg}.

add_object(Dict, Object, Es) when is_record(Object, dict_object) ->
    lists:foreach(fun(E) -> add_entry(Dict, E) end, Es),
    try ets:insert_new(Dict, Object) of
	_ -> ok
    catch
	error:badarg ->
	    {error,badarg}
    end.    

%%--------------------------------------------------------------------
%% @doc
%% Add a new entry to dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec add_entry(Dict::term(), Entry::record()) ->
		       ok | {error, badarg}.

add_entry(Dict, Entry) when is_record(Entry, dict_entry) ->
    try ets:insert_new(Dict, Entry) of
	_ -> ok
    catch
	error:badarg ->
	    {error,badarg}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Update existing object in dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec update_object(Dict::term(), Object::record()) ->
			ok | {error, badarg}.

update_object(Dict, Object) when is_record(Object, dict_object) ->
    case ets:member(Dict, Object#dict_object.index) of
	false -> erlang:error(badarg);
	true ->  ets:insert(Dict, Object)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Update existing entry in dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec update_entry(Dict::term(), Entry::record()) ->
		       ok | {error, badarg}.

update_entry(Dict, Entry) when is_record(Entry, dict_entry) ->
    case ets:member(Dict, Entry#dict_entry.index) of
	false -> erlang:error(badarg);
	true ->  ets:insert(Dict, Entry)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Delete existing object in dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec delete_object(Dict::term(), Index::integer()) ->
			ok | {error, badarg}.

delete_object(Dict, Ix) when ?is_index(Ix) ->
    ets:delete(Dict, Ix),
    ets:match_delete(Dict, #dict_entry { index={Ix,'_'}, _ = '_' }).
    
%%--------------------------------------------------------------------
%% @doc
%% Delete existing entry in dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec delete_entry(Dict::term(), Index::integer() | {integer(), integer()}) ->
		       ok | {error, badarg}.

delete_entry(Dict, Index={Ix,Sx}) when ?is_index(Ix), ?is_subind(Sx) ->
    ets:delete(Dict, Index);
delete_entry(Dict, Ix) when ?is_index(Ix) ->
    delete_entry(Dict, {Ix,0}).

%%--------------------------------------------------------------------
%% @doc
%% Lookup existing object in dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec lookup_object(Dict::term(), Index::integer()) ->
			{ok, Object::record()} | {error, no_such_object}.

lookup_object(Dict, Ix) when ?is_index(Ix) ->
    case ets:lookup(Dict, Ix) of
	[O] ->
	    {ok,O};
	[] ->
	    i_fail(Dict,Ix)
    end.


%%--------------------------------------------------------------------
%% @doc
%% Lookup existing entry in dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec lookup_entry(Dict::term(), Index::integer() | {integer(), integer()}) ->
			  {ok, Entry::record()} | 
			  {error, no_such_object} |
			  {error, no_such_subindex}.

lookup_entry(Dict, Index={Ix,255}) ->
    case ets:lookup(Dict, Ix) of
	[O] ->
	    Value = ((O#dict_object.type band 16#ff) bsl 8) bor
		(O#dict_object.struct band 16#ff),
	    {ok,#dict_entry { index  = Index,
			      access = ?ACCESS_RO,
			      type   = ?UNSIGNED32,
			      data   = co_codec:encode(Value, ?UNSIGNED32)}};
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

%%--------------------------------------------------------------------
%% @doc
%% Set data of existing object in dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec set_data(Dict::term(), Index::integer(), SubInd::integer(), Data::binary()) ->
		 ok | 
		 {error, no_such_object} |
		 {error, no_such_subindex} |
		 {error, bad_access}.

set_data(Dict, Ix, Si, Data) 
  when ?is_index(Ix), ?is_subind(Si), is_binary(Data) ->
    Index = {Ix, Si},
    try ets:lookup_element(Dict, Index, #dict_entry.access) of
	?ACCESS_RO ->
	    {error,?abort_write_not_allowed};
	?ACCESS_C ->
	    {error,?abort_write_not_allowed};
	_ ->
	    direct_set_data(Dict, Ix, Si, Data)
    catch
	error:badarg ->
	    i_fail(Dict, Index);
	  error:What ->
	    erlang:error(What)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Set data of existing object in dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec set_data(Dict::term(), Index::{Ix::integer(), Si::integer()}, Data::binary()) ->
		 ok | 
		 {error, no_such_object} |
		 {error, no_such_subindex} |
		 {error, bad_access}.

set_data(Dict, {Ix, Si}, Data) 
  when ?is_index(Ix), ?is_subind(Si), is_binary(Data) ->
    set_data(Dict, Ix, Si, Data).

%%%--------------------------------------------------------------------
%% @doc
%% Set data of existing object in dictionary.
%% Work as set but without checking access !
%% @end
%%--------------------------------------------------------------------
-spec direct_set_data(Dict::term(), Index::integer(), SubInd::integer(), 
		 Data::binary()) ->
		 ok | 
		 {error, no_such_object} |
		 {error, no_such_subindex} |
		 {error, bad_access}.

direct_set_data(Dict, Ix, Si, Data) 
  when ?is_index(Ix), ?is_subind(Si), is_binary(Data) ->
    Index = {Ix, Si},
    case ets:update_element(Dict, Index, {#dict_entry.data, Data}) of
	false ->
	    i_fail(Dict, Index);
	true ->
	    ok
    end.
%%%--------------------------------------------------------------------
%% @doc
%% Set data of existing object in dictionary.
%% Work as set but without checking access !
%% @end
%%--------------------------------------------------------------------
-spec direct_set_data(Dict::term(), Index::{Ix::integer(), Si::integer()}, 
		 Data::binary()) ->
		 ok | 
		 {error, no_such_object} |
		 {error, no_such_subindex} |
		 {error, bad_access}.

direct_set_data(Dict, {Ix, Si}, Data) 
  when ?is_index(Ix), ?is_subind(Si), is_binary(Data) ->
    direct_set_data(Dict, Ix, Si, Data).

%%--------------------------------------------------------------------
%% @doc
%% Set value of existing object in dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec set_value(Dict::term(), Ix::integer(), Si::integer(), Value::term()) ->
		 ok | 
		 {error, no_such_object} |
		 {error, no_such_subindex} |
		 {error, bad_access}.

set_value(Dict, Ix, Si,Value) 
  when ?is_index(Ix), ?is_subind(Si) ->
    Index = {Ix, Si},
    try ets:lookup_element(Dict, Index, #dict_entry.access) of
	?ACCESS_RO ->
	    {error,?abort_write_not_allowed};
	?ACCESS_C ->
	    {error,?abort_write_not_allowed};
	_ ->
	    direct_set_value(Dict, Ix, Si, Value)
    catch
	error:badarg ->
	    i_fail(Dict, Index);
	  error:What ->
	    erlang:error(What)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Set value of existing object in dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec set_value(Dict::term(), Index::{Ix::integer(), Si::integer()}, Value::term()) ->
		 ok | 
		 {error, no_such_object} |
		 {error, no_such_subindex} |
		 {error, bad_access}.

set_value(Dict, {Ix, Si},Value) 
  when ?is_index(Ix), ?is_subind(Si) ->
    set_value(Dict, Ix, Si,Value).

%%--------------------------------------------------------------------
%% @doc
%% Set value of existing object in dictionary.
%% Work as set but without checking access !
%% @end
%%--------------------------------------------------------------------
-spec direct_set_value(Dict::term(), Index::integer(), SubInd::integer(), 
		 Value::term()) ->
		 ok | 
		 {error, no_such_object} |
		 {error, no_such_subindex} |
		 {error, bad_access}.

direct_set_value(Dict, Ix, Si,Value) 
  when ?is_index(Ix), ?is_subind(Si) ->
    Index = {Ix, Si},
    Type = ets:lookup_element(Dict, Index, #dict_entry.type),
    direct_set_data(Dict, Ix, Si,co_codec:encode(Value, Type)).


%%--------------------------------------------------------------------
%% @doc
%% Set value of existing object in dictionary.
%% Work as set but without checking access !
%% @end
%%--------------------------------------------------------------------
-spec direct_set_value(Dict::term(), Index::{Ix::integer(), Si::integer()}, 
		 Value::term()) ->
		 ok | 
		 {error, no_such_object} |
		 {error, no_such_subindex} |
		 {error, bad_access}.

direct_set_value(Dict, {Ix, Si},Value) 
  when ?is_index(Ix), ?is_subind(Si) ->
    direct_set_value(Dict, Ix, Si,Value).

%%--------------------------------------------------------------------
%% @doc
%% Sets an array of data for subindex 1..254.
%% @end
%%--------------------------------------------------------------------
-spec set_array_data(Dict::term(), Index::integer(), list(Data::binary())) ->
		       ok | 
		       {error, no_such_object} |
		       {error, no_such_subindex} |
		       {error, bad_access}.

set_array_data(Dict, Ix, DataList) ->
    set_array_data(Dict, Ix, 1, DataList).

set_array_data(Dict, Ix, Si, []) ->
    direct_set_data(Dict, Ix, 0, Si);  %% number of elements
set_array_data(Dict, Ix, Si, [Data|Rest]) when Si < 255 ->
    direct_set_data(Dict, Ix, Si, Data),
    set_array_data(Dict, Ix, Si+1, Rest).

%%--------------------------------------------------------------------
%% @doc
%% Sets an array of values for subindex 1..254.
%% @end
%%--------------------------------------------------------------------
-spec set_array_value(Dict::term(), Index::integer(), list(Value::term())) ->
		       ok | 
		       {error, no_such_object} |
		       {error, no_such_subindex} |
		       {error, bad_access}.

set_array_value(Dict, Ix, Values) ->
    set_array_value(Dict, Ix, 1, Values).

set_array_value(Dict, Ix, Si, []) ->
    direct_set_value(Dict, Ix, 0, Si);  %% number of elements
set_array_value(Dict, Ix, Si, [Value|Vs]) when Si < 255 ->
    direct_set_value(Dict, Ix, Si, Value),
    set_array_value(Dict, Ix, Si+1, Vs).


%%--------------------------------------------------------------------
%% @doc
%% Get data of existing object in dictionary.
%% @end
%%--------------------------------------------------------------------
-spec data(Dict::term(), Index::integer(), SubInd::integer()) ->
		   {ok, Value::term()} | 
		   {error, Reason::atom()}.

data(Dict, Ix, Si) when ?is_index(Ix), ?is_subind(Si) ->
    data(Dict, {Ix, Si}).
%%--------------------------------------------------------------------
%% @doc
%% Get data of existing object in dictionary.
%% @end
%%--------------------------------------------------------------------
-spec data(Dict::term(), Index::{Ix::integer(), Si::integer()}) ->
		   {ok, Value::term()} | 
		   {error, Reason::atom()}.

data(Dict, {Ix, Si} = Index) when ?is_index(Ix), ?is_subind(Si) ->
    case ets:lookup(Dict, Index) of
	[E] -> 
	    case E#dict_entry.access of
		?ACCESS_WO ->
		    {error,?abort_read_not_allowed};
		_ ->
		    {ok, E#dict_entry.data}
	    end;
	_Other ->
	    i_fail(Dict, Index)
    end.
 
%%--------------------------------------------------------------------
%% @doc
%% Get data of existing object in dictionary.
%% Works as data but without access check.
%% @end
%%--------------------------------------------------------------------
-spec direct_data(Dict::term(), Index::integer(), SubInd::integer()) ->
			 Data::binary() | 
			       {error, Reason::atom()}.

direct_data(Dict,Ix,Si) when ?is_index(Ix), ?is_subind(Si) ->
    ets:lookup_element(Dict, {Ix,Si}, #dict_entry.data).
    
%%--------------------------------------------------------------------
%% @doc
%% Get data of existing object in dictionary.
%% Works as data but without access check.
%% @end
%%--------------------------------------------------------------------
-spec direct_data(Dict::term(), Index::{Ix::integer(), Si::integer()}) ->
			 Data::binary() | 
			  {error, Reason::atom()}.

direct_data(Dict,{Ix,Si} = Index) when ?is_index(Ix), ?is_subind(Si) ->
    ets:lookup_element(Dict, Index, #dict_entry.data).
    
%%--------------------------------------------------------------------
%% @doc
%% Get value of existing object in dictionary.
%% @end
%%--------------------------------------------------------------------
-spec value(Dict::term(), Index::integer(), SubInd::integer()) ->
		   {ok, Value::term()} | 
		   {error, Reason::atom()}.

value(Dict, Ix, Si) when ?is_index(Ix), ?is_subind(Si) ->
    value(Dict, {Ix, Si}).

%%--------------------------------------------------------------------
%% @doc
%% Get value of existing object in dictionary.
%% @end
%%--------------------------------------------------------------------
-spec value(Dict::term(), Index::{Ix::integer(), Si::integer()}) ->
		   {ok, Value::term()} | 
		   {error, Reason::atom()}.

value(Dict, {Ix, Si} = Index) when ?is_index(Ix), ?is_subind(Si) ->
    case ets:lookup(Dict, Index) of
	[E] -> 
	    case E#dict_entry.access of
		?ACCESS_WO ->
		    {error,?abort_read_not_allowed};
		_ ->
		    {Value, _Rest} =
			co_codec:decode(E#dict_entry.data,E#dict_entry.type),
		    {ok, Value}
	    end;
	_Other ->
	    i_fail(Dict, Index)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Get value of existing object in dictionary.
%% Works as value but without access check.
%% @end
%%--------------------------------------------------------------------
-spec direct_value(Dict::term(), Index::integer(), SubInd::integer()) ->
			  Value::term() | 
			  {error, Reason::atom()}.

direct_value(Dict,Ix,Si) when ?is_index(Ix), ?is_subind(Si) ->
    direct_value(Dict,{Ix,Si}).
    
%%--------------------------------------------------------------------
%% @doc
%% Get value of existing object in dictionary.
%% Works as value but without access check.
%% @end
%%--------------------------------------------------------------------
-spec direct_value(Dict::term(), Index::{Ix::integer(), Si::integer()}) ->
			  Value::term() | 
			  {error, Reason::atom()}.

direct_value(Dict,{Ix,Si} = Index) when ?is_index(Ix), ?is_subind(Si) ->
    case ets:lookup(Dict, Index) of
	[E] -> 
	    {Value, _Rest} =
		co_codec:decode(E#dict_entry.data,E#dict_entry.type),
	    Value;
	_Other ->
	    i_fail(Dict, Index)
    end.
    
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
	    match_entry_s(Dict,first_object(Dict, I),J,0,Vf);
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
    case ets:lookup(Dict,{I,S}) of
	[E] ->
	    {Value, _Rest} = co_codec:decode(E#dict_entry.data, E#dict_entry.type),
	    case Value of 
		Vf ->
		    {ok,I};
		V when is_function(Vf) ->
		    case Vf(V) of
			true -> {ok,I};
			false ->
			    match_entry_s(Dict,next_object(Dict,I,J),J,S,Vf)
		    end;
		_ ->
		    match_entry_s(Dict,next_object(Dict,I,J),J,S,Vf)
	    end;
	_Other ->
	    match_entry_s(Dict,next_object(Dict,I,J),J,S,Vf)
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
