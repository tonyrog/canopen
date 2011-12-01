%%% File    : co_lib.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Can open utilities
%%% Created : 15 Jan 2008 by Tony Rogvall 

-module(co_lib).

-import(lists, [map/2, reverse/1]).

-export([serial_to_string/1, string_to_serial/1]).
-export([load_definition/1]).
-export([load_dmod/2]).
-export([object_by_name/2]).
-export([object_by_id/2]).
-export([object_by_index/2]).
-compile(export_all).

-include("../include/canopen.hrl").

%% convert 4 bytes serial number to a string xx:xx:xx:xx
serial_to_string(<<Serial:32>>) ->
    serial_to_string(Serial);
serial_to_string(Serial) when is_integer(Serial) ->
    lists:flatten(io_lib:format("~8.16.0B", [Serial band 16#ffffffff])).

string_to_serial(String) when is_list(String) ->
    erlang:list_to_integer(String, 16).

%% Encode/Decode category
encode_category(optional) -> ?CATEGORY_OPTIONAL;
encode_category(mandatory) -> ?CATEGORY_MANDATORY;
encode_category(conditional) ->  ?CATEGORY_CONDITIONAL.

decode_category(?CATEGORY_OPTIONAL) -> optional;
decode_category(?CATEGORY_MANDATORY) -> mandatory;
decode_category(?CATEGORY_CONDITIONAL) -> conditional.


%% Encode/Decode access field
encode_access(A) when is_integer(A), A band 16#f == A ->
    A;
encode_access(rw)    -> ?ACCESS_RW;
encode_access(ro)    -> ?ACCESS_RO;
encode_access(wo)    -> ?ACCESS_WO;
encode_access(c)     -> ?ACCESS_C;
encode_access(sto)   -> ?ACCESS_STO;
encode_access(ptr)   -> ?ACCESS_PTR;
encode_access(read)  -> ?ACCESS_RO;  %% alias
encode_access(write) -> ?ACCESS_WO;  %% alias
encode_access(const) -> ?ACCESS_C;   %% alias
encode_access([A|As]) ->
    encode_access(A) bor encode_access(As);
encode_access([]) -> 0.

decode_access(A) when is_integer(A) ->
    A1 = 
	case A band 16#3 of
	    ?ACCESS_RW -> rw;
	    ?ACCESS_RO -> ro;
	    ?ACCESS_WO -> wo;
	    ?ACCESS_C  -> const
	end,
    L = 
	if A band ?ACCESS_STO == ?ACCESS_STO ->
		[sto];
	   true ->
		[]
	end ++ 
	if A band ?ACCESS_PTR == ?ACCESS_PTR ->
		[ptr];
	   true ->
		[]
	end,
    if  L == [] -> A1;
	true -> [A1|L]
    end.

%% Encode/Decode standard type field

encode_type(T) when is_integer(T), T band 16#ff == T ->
    T;
encode_type(boolean)        -> ?BOOLEAN;
encode_type(integer8)       -> ?INTEGER8;
encode_type(integer16)      -> ?INTEGER16;
encode_type(integer32)      -> ?INTEGER32;
encode_type(integer)        -> ?INTEGER;
encode_type(unsigned8)      -> ?UNSIGNED8;
encode_type(unsigned16)     -> ?UNSIGNED16;
encode_type(unsigned32)     -> ?UNSIGNED32;
encode_type(unsigned)       -> ?UNSIGNED;
encode_type(real32)         -> ?REAL32;
encode_type(float)          -> ?FLOAT;
encode_type(visible_string) -> ?VISIBLE_STRING;
encode_type(string)         -> ?STRING;
encode_type(octet_string)   -> ?OCTET_STRING;
encode_type(unicode_string) -> ?UNICODE_STRING;
encode_type(time_of_day)    -> ?TIME_OF_DAY;
encode_type(time_difference) -> ?TIME_DIFFERENCE;
encode_type(bit_string)      -> ?BIT_STRING;
encode_type(domain)          -> ?DOMAIN;
encode_type(integer24)       -> ?INTEGER24;
encode_type(real64)          -> ?REAL64;
encode_type(double)          -> ?DOUBLE;
encode_type(integer40)       -> ?INTEGER40;
encode_type(integer48)       -> ?INTEGER48;
encode_type(integer56)       -> ?INTEGER56;
encode_type(integer64)       -> ?INTEGER64;
encode_type(unsigned24)      -> ?UNSIGNED24;
encode_type(unsigned40)      -> ?UNSIGNED40;
encode_type(unsigned48)      -> ?UNSIGNED48;
encode_type(unsigned56)      -> ?UNSIGNED56;
encode_type(unsigned64)      -> ?UNSIGNED64;
encode_type(pdo_parameter)   -> ?PDO_PARAMETER;
encode_type(pdo_mapping)     -> ?PDO_MAPPING;
encode_type(sdo_parameter)   -> ?SDO_PARAMETER;
encode_type(identity)        -> ?IDENTITY;
encode_type({enum,Base,_Name}) -> encode_type(Base);
encode_type({bitfield,Base,_Name}) -> encode_type(Base).

decode_type(?BOOLEAN) -> boolean;
decode_type(?INTEGER8) -> integer8;
decode_type(?INTEGER16) -> integer16;
decode_type(?INTEGER32) -> integer32;
decode_type(?UNSIGNED8) -> unsigned8;
decode_type(?UNSIGNED16) -> unsigned16;
decode_type(?UNSIGNED32) -> unsigned32;
decode_type(?REAL32) -> real32;
decode_type(?VISIBLE_STRING) -> visible_string;
decode_type(?OCTET_STRING) -> octet_string;
decode_type(?UNICODE_STRING) -> unicode_string;
decode_type(?TIME_OF_DAY) -> time_of_day;
decode_type(?TIME_DIFFERENCE) -> time_difference;
decode_type(?BIT_STRING) -> bit_string;
decode_type(?DOMAIN) -> domain;
decode_type(?INTEGER24) -> integer24;
decode_type(?REAL64) -> real64;
decode_type(?INTEGER40) -> integer40;
decode_type(?INTEGER48) -> integer48;
decode_type(?INTEGER56) -> integer56;
decode_type(?INTEGER64) -> integer64;
decode_type(?UNSIGNED24) -> unsigned24;
decode_type(?UNSIGNED40) -> unsigned40;
decode_type(?UNSIGNED48) -> unsigned48;
decode_type(?UNSIGNED56) -> unsigned56;
decode_type(?UNSIGNED64) -> unsigned64;
decode_type(?PDO_PARAMETER) -> pdo_parameter;
decode_type(?PDO_MAPPING) -> pdo_mapping;
decode_type(?SDO_PARAMETER) -> sdo_parameter;
decode_type(?IDENTITY) -> identity.

encode_pdo_mapping(no) -> ?MAPPING_NO;
encode_pdo_mapping(optional) -> ?MAPPING_OPTIONAL;
encode_pdo_mapping(default) -> ?MAPPING_DEFAULT.

decode_pdo_mapping(?MAPPING_NO) -> no;
decode_pdo_mapping(?MAPPING_OPTIONAL) -> optional;
decode_pdo_mapping(?MAPPING_DEFAULT) -> default.

encode_struct(null)      -> ?OBJECT_NULL;
encode_struct(domain)    -> ?OBJECT_DOMAIN;
encode_struct(deftype)   -> ?OBJECT_DEFTYPE;
encode_struct(defstruct) -> ?OBJECT_DEFSTRUCT;
encode_struct(var)       -> ?OBJECT_VAR;
encode_struct(array)     -> ?OBJECT_ARRAY;
encode_struct(rec)       -> ?OBJECT_RECORD;
encode_struct(defpdo)    -> ?OBJECT_DEFPDO.

decode_struct(?OBJECT_NULL)      -> null;
decode_struct(?OBJECT_DOMAIN)    -> domain;
decode_struct(?OBJECT_DEFTYPE)   -> deftype;
decode_struct(?OBJECT_DEFSTRUCT) -> defstruct;
decode_struct(?OBJECT_VAR)       -> var;
decode_struct(?OBJECT_ARRAY)     -> array;
decode_struct(?OBJECT_RECORD)    -> rec.

%% Encode PDO parameter transmission type
encode_transmission(specific)  -> ?TRANS_EVENT_SPECIFIC;
encode_transmission(profile)   -> ?TRANS_EVENT_PROFILE;
encode_transmission(rtr)       -> ?TRANS_RTR;
encode_transmission(rtr_sync)  -> ?TRANS_RTR_SYNC;
encode_transmission(once)      -> ?TRANS_SYNC_ONCE;
encode_transmission({sync,N}) when is_integer(N),N >= 0,N =< ?TRANS_SYNC_MAX->
    ?TRANS_EVERY_N_SYNC(N);
encode_transmission(N) when is_integer(N), N >= 0, N =< 255 ->
    N.
%% Decode PDO parameter transmission type
decode_transmission(?TRANS_EVENT_SPECIFIC) -> specific;
decode_transmission(?TRANS_EVENT_PROFILE) -> profile;
decode_transmission(?TRANS_RTR) -> rtr;
decode_transmission(?TRANS_RTR_SYNC) -> rtr_sync;
decode_transmission(?TRANS_SYNC_ONCE) -> once;
decode_transmission(N) when is_integer(N), N >= 0, N =< ?TRANS_SYNC_MAX ->
    {sync,N};
decode_transmission(N) when is_integer(N), N >= 0, N =< 255 ->
    N.

%% Encode COBID
%% encode_cobid(pdo1)
%% Decode COBID

%%
%% Load all description objects in a def file
%%
%%
-record(dmod,
	{
	  require = [],  %% modules required [atom()]
	  enums,   %% dictionary of enums
	  struct,  %% dictionary  Index -> ID  (DEFSTRUCT)
	  type,    %% dictionary  Index -> ID  (DEFTYPE)
	  pdo,     %% dictionary  Index -> ID  (PDODEF)
	  var,     %% dictionay   Index -> ID  (VAR/REC/ARRAY)
	  id,      %% dictionary  Index -> ID
	  name,    %% dictionary string => ID
	  objects  %% dictionary  ID -> OBJDEF
	}).

-record(dctx,
	{
	  module,       %% module loading
	  modules = [], %% loaded modules [{atom(),#dmod}]
	  loading = [], %% loading stack [atom()] 
	  path=[]       %% search path for require
	}).


new_dmod() ->
    #dmod 
	{ require = [],
	  enums   = dict:new(),
	  struct  = dict:new(),
	  type    = dict:new(),
	  pdo     = dict:new(),
	  var     = dict:new(),
	  id      = dict:new(),
	  name    = dict:new(),
	  objects = dict:new() }.


load_definition(File) ->
    load_definition(filename:basename(File),[filename:dirname(File)]).


load_definition(File,Path) ->
    load_dmod(list_to_atom(File), #dctx { path=Path }).

load_dmod(Module, DCtx) when is_atom(Module) ->
    File = atom_to_list(Module) ++ ".def",
    case file:path_consult(DCtx#dctx.path, File) of
	{error, enoent} ->
	    io:format("load_mod: file ~p not found\n", [File]),
	    {{error,enoent}, DCtx};
	Err = {error,_} ->
	    {Err, DCtx};
	{ok, Forms,_} ->
	    dmod(Forms, undefined, DCtx)
    end.

%% {module, abc}  - define module
dmod([{module, Module}|Os], DMod, DCtx) when is_atom(Module) ->
    case lists:keysearch(Module, 1, DCtx#dctx.modules) of
	false ->
	    DMod1 = new_dmod(),
	    DCtx1 = add_module(DCtx, DMod),
	    dmod(Os, DMod1, DCtx1#dctx { module = Module });
	{value, _} ->
	    erlang:error({module_already_defined, Module})
    end;
%% {require, def} - load a module
dmod([{require, Module}|Os], DMod, DCtx) when is_atom(Module) ->
    case lists:keysearch(Module, 1, DCtx#dctx.modules) of
	false ->
	    case lists:member(Module, DCtx#dctx.loading) of
		true ->
		    erlang:error({circular_definition, Module});
		false ->
		    DCtx1 =  DCtx#dctx { loading=[Module|DCtx#dctx.loading]},
		    {_, DCtx2} = load_dmod(Module, DCtx1),
		    Require = [Module|DMod#dmod.require],
		    dmod(Os, DMod#dmod { require=Require},
			 DCtx2#dctx { module = DCtx#dctx.module,
				      loading = DCtx#dctx.loading })
	    end;
	{value, {_, _DMod1}} ->
	    dmod(Os, DMod, DCtx)
    end;
%% {enum, atom(), [{atom(),value()}]}
dmod([{enum,Id,Enums}|Os], DMod, DCtx) ->
    Dict = dict:store(Id, Enums, DMod#dmod.enums),
    dmod(Os, DMod#dmod { enums = Dict}, DCtx);
dmod([{objdef,Index,Options}|Os], DMod, DCtx) ->
    %% io:format("objdef ixs=~p\n", [Index]),
    Ixs = 
	case Index of
	    I when I > 0, I =< 16#ffff ->
		[I];
	    {I,J} when I > 0, I =< 16#ffff, I =< J, J =< 16#ffff ->
		lists:seq(I,J,1);
	    {I,J,S} when I > 0, I =< 16#ffff, I =< J, J =< 16#ffff,
	                 S > 0, S < 16#ffff ->
		lists:seq(I,J,S)
	end,
    Obj0 = decode_obj(Options, #objdef { index=hd(Ixs)}),
    Obj  = verify_obj(Obj0,DMod),
    verify_uniqe_id(Obj,DCtx),
    Id       = Obj#objdef.id,
    Dobjects = store_one(Id,  Obj, DMod#dmod.objects),
    Dname    = store_one(Obj#objdef.name, Id, DMod#dmod.name),
    DMod1 =
	lists:foldl(
	  fun(Ix, DMod0) ->
		  Did  = store_one(Ix, Id, DMod0#dmod.id),
		  case Obj#objdef.struct of
		      defstruct ->
			  D = dict:store(Ix, Id, DMod0#dmod.struct),
			  DMod0#dmod { struct=D, id=Did };
		      deftype ->
			  D = dict:store(Ix, Id, DMod0#dmod.type),
			  DMod0#dmod { type=D, id=Did };
		      defpdo ->
			  D = dict:store(Ix, Id, DMod0#dmod.pdo),
			  DMod0#dmod { pdo=D, id=Did };
		      _ ->
			  D = dict:store(Ix, Id, DMod0#dmod.var),
			  DMod0#dmod { var=D, id=Did }
		  end
	  end, DMod#dmod { objects=Dobjects, name=Dname }, Ixs),
    dmod(Os, DMod1, DCtx);
dmod([], DMod, DCtx) ->
    {ok, add_module(DCtx, DMod)}.


%% Insert a module into the module list
add_module(DCtx, undefined) ->
    DCtx;
add_module(DCtx, DMod) ->
    DCtx#dctx { module = undefined,
		modules=[{DCtx#dctx.module,DMod}|DCtx#dctx.modules]}.

%%
%% Check that id is uniq
%%
verify_uniqe_id(Obj, DCtx) ->
    if Obj#objdef.id == undefined ->
	    erlang:error(id_required, Obj#objdef.index);
       true ->
	    case object_by_id(Obj#objdef.id, DCtx) of
		error -> true;
		{ok,Obj2} ->
		    erlang:error({id_not_uniq,Obj#objdef.id,Obj2#objdef.index})
	    end
    end.
    
store_one(Key, Value, Dict) ->
    case dict:find(Key, Dict) of
	error ->
	    dict:store(Key, Value, Dict);
	_ -> %% just store first instance 
	    Dict
    end.

%% return {ok,#objdef} | error
object_by_id(Id, DCtx) when is_atom(Id) ->
    find_in_mods(Id, #dmod.objects, DCtx#dctx.modules).

enum_by_id(Id, DCtx) when is_atom(Id) ->
    find_in_mods(Id, #dmod.enums, DCtx#dctx.modules).    

%% return {ok,#objdef} | error
object_by_name(Name, DCtx) when is_list(Name)  ->
    case find_in_mods(Name, #dmod.name, DCtx#dctx.modules) of
	error -> error;
	{ok,Id} -> object_by_id(Id, DCtx)
    end.

%% return {ok,#objdef} | error
object_by_index(Index, DCtx) ->
    case find_in_mods(Index, #dmod.id, DCtx#dctx.modules) of
	error -> error;
	{ok,Id} ->
	    case object_by_id(Id, DCtx) of
		error -> error;
		{ok,Obj} when Obj#objdef.index =/= Index ->
		    %% patch "template object"
		    {ok, Obj#objdef { index=Index }}; 
		Found -> Found
	    end
    end.

type_by_index(Index, DCtx) ->
    case find_in_mods(Index, #dmod.type, DCtx#dctx.modules) of
	error -> error;
	{ok,Id} -> object_by_id(Id,DCtx)
    end.

struct_by_index(Index, DCtx) ->
    case find_in_mods(Index, #dmod.struct, DCtx#dctx.modules) of    
	error -> error;
	{ok,Id} -> object_by_id(Id,DCtx)
    end.

pdo_by_index(Index, DCtx) ->
    case find_in_mods(Index, #dmod.pdo, DCtx#dctx.modules) of    
	error -> error;
	{ok,Id} -> object_by_id(Id,DCtx)
    end.

var_by_index(Index, DCtx) ->
    case find_in_mods(Index, #dmod.var, DCtx#dctx.modules) of
	error -> error;
	{ok,Id} -> object_by_id(Id,DCtx)
    end.


find_in_mods(Key, Pos, [{_,DMod}|DMods]) ->
    case dict:find(Key, element(Pos, DMod)) of
	error -> find_in_mods(Key, Pos, DMods);
	Found -> Found
    end;
find_in_mods(_Key, _Pos, []) ->
    error.

	    
entry_by_index(Index, SubInd, Def) ->
    case object_by_index(Index, Def) of
	error -> error;
	{ok,Obj} ->
	    case find_entry(SubInd, Obj) of
		error -> error;
		Found -> Found
	    end
    end.

find_entry(SubInd, Obj) ->
    if SubInd == 0, Obj#objdef.struct == var;
       SubInd == 0, Obj#objdef.struct == defpdo ->
	    if Obj#objdef.entry == undefined ->
		    case find_ent(SubInd, Obj#objdef.entries) of
			error -> error;
			{ok,Ent} -> {ok,Ent#entdef { index=SubInd}}
		    end;
	       true ->
		    {ok, (Obj#objdef.entry)#entdef { index=SubInd }}
	    end;
       %% special handling of SubIndex=0, SubIndex=255
       true ->
	    case find_ent(SubInd, Obj#objdef.entries) of
		error -> error;
		{ok,Ent} -> {ok,Ent#entdef { index=SubInd}}
	    end
    end.

find_ent(SubIndex, [Ent|Entries]) ->
    case match_index(SubIndex, Ent#entdef.index) of
	true -> {ok,Ent};
	false -> find_ent(SubIndex, Entries)
    end;
find_ent(_Index, []) ->
    error.

%% Check if index match object index
match_index(Index, Index) -> 
    true;
match_index(Index, {From,To}) when Index >= From, Index =< To -> 
    true;
match_index(Index, {From,To,Step}) when Index >= From, Index =< To, (Index-From) rem Step == 0 ->
    true;
match_index(_, _) -> false.

%% Convert index to offset idx
object_idx(Index, Index) -> 
    1;
object_idx(Index, {From,To}) when Index >= From, Index =< To ->
    (Index - From)+1;
object_idx(Index, {From,To,Step}) when Index >= From, Index =< To, (Index-From) rem Step == 0 ->
    (Index - From)+1.

translate(String, [{From,To} | More]) ->
    translate(translate(String, From, To), More);
translate(String, []) ->
    String.

%% translate From=>To
translate([], _From, _To) ->
    [];
translate(String, From, To) ->
    case match(String, From) of
	{true, String1} ->
	    To ++ translate(String1, From, To);
	false ->
	    [hd(String) | translate(tl(String), From, To)]
    end.

match(String, []) ->
    {true,String};
match([H|T1], [H|T2]) ->
    match(T1,T2);
match(_, _) ->
    false.

decode_obj([Opt|Options], Obj) ->
    %%io:format("decode_option: ~p\n", [Opt]),
    Obj1 = decode_obj_opt(Opt, Obj),
    decode_obj(Options, Obj1);
decode_obj([], Obj) ->
    Obj.

%% decode object
decode_obj_opt({entry,Index,Options}, Obj) ->
    IndexRange = 
	case Index of
	    I when I >= 0, I =< 16#ff ->
		I;
	    {I,J} when I >= 0, I =< 16#ff, I =< J, J =< 16#ff ->
		{I,J}
	end,
    E = decode_ent(Options, #entdef { index=IndexRange }),
    Es = Obj#objdef.entries,
    Obj#objdef { entries=[E|Es]};
decode_obj_opt(Kv={Key,Value}, Obj) ->
    %%io:format("decode object option: ~p\n", [Kv]),
    case Key of
	name ->
	    Obj#objdef { name=Value };
	id ->
	    Obj#objdef { id=Value };
	description ->
	    Obj#objdef { description=Value };
	struct   ->
	    Obj#objdef { struct=Value };
	category ->
	    Obj#objdef { category=Value };
	%% Add the following fields to a field with index=default
	type  -> 
	    Ent = decode_ent_opt(Kv, Obj#objdef.entry),
	    Obj#objdef { entry=Ent };
	access ->
	    Ent = decode_ent_opt(Kv, Obj#objdef.entry),
	    Obj#objdef { entry=Ent };
	pdo_mapping ->
	    Ent = decode_ent_opt(Kv, Obj#objdef.entry),
	    Obj#objdef { entry=Ent };
	range ->
	    Ent = decode_ent_opt(Kv, Obj#objdef.entry),
	    Obj#objdef { entry=Ent };
	default ->
	    Ent = decode_ent_opt(Kv, Obj#objdef.entry),
	    Obj#objdef { entry=Ent };
	substitute ->
	    Ent = decode_ent_opt(Kv, Obj#objdef.entry),
	    Obj#objdef { entry=Ent }
    end.



%% Decode entry description options.
decode_ent([Opt|Opts], Ent) ->
    Ent1 = decode_ent_opt(Opt, Ent),
    decode_ent(Opts, Ent1);
decode_ent([], Ent) ->
    Ent.

%% Decode entry description option
decode_ent_opt(Kv, undefined) ->
    decode_ent_opt(Kv, #entdef {});
decode_ent_opt(_Kv={Key,Value}, Ent) ->
    %%io:format("decode entry option: ~p\n", [_Kv]),
    case Key of
	name ->
	    Ent#entdef { name=Value };
	id ->
	    Ent#entdef { name=id };
	description ->
	    Ent#entdef { description=Value };
	type -> 
	    Ent#entdef { type=Value };
	category ->
	    Ent#entdef { category=Value };
	access ->
	    Ent#entdef { access=Value };
	pdo_mapping ->
	    Ent#entdef { pdo_mapping=Value };
	range ->
	    Ent#entdef { range=Value };
	default ->
	    Ent#entdef { default=Value };
	substitute ->
	    Ent#entdef { substitute=Value }
    end.

%%
%% Verify object
%%
verify_obj(Obj,Def) ->    
    verify([fun verify_obj_id/2,
	    fun verify_obj_name/2,
	    fun verify_obj_type/2,
	    fun verify_obj_struct/2,
	    fun verify_obj_category/2,
	    fun verify_obj_entries/2], Obj, Def).
	    
%%
%% Verify entry
%%	    
	
verify_ent(Ent, Def) ->
    verify([fun verify_ent_id/2,
	    fun verify_ent_name/2,
	    fun verify_ent_category/2,
	    fun verify_ent_access/2,
	    fun verify_ent_type/2,
	    fun verify_ent_pdo_mapping/2,
	    fun verify_ent_range/2,
	    fun verify_ent_default/2,
	    fun verify_ent_substitute/2],
	   Ent, Def).

verify([V|Vs], Data, Def) ->
    verify(Vs, V(Data, Def), Def);
verify([], Data, _Def) ->
    Data.

%% Verify object id
verify_obj_id(Obj,_Def) ->
    if is_atom(Obj#objdef.id),
       Obj#objdef.id =/= undefined -> Obj;
       true -> erlang:error({bad_entry_id, Obj#objdef.id})
    end.

%% Verify object name
verify_obj_name(Obj,_Def) ->
    case Obj#objdef.name of
	undefined -> 
	    Obj#objdef { name=atom_to_list(Obj#objdef.id) };
	Name when is_atom(Name) ->
	    Obj#objdef { name=atom_to_list(Name) };
	Name when is_list(Name) ->
	    Obj#objdef { name=Name };	    
	Name -> erlang:error({bad_entry_name, Name})
    end.

%% Verify object category
verify_obj_category(Obj,_Def) ->
    case Obj#objdef.category of
	undefined -> %% default
	    Obj#objdef { category=optional};	
	Cat ->
	    case catch encode_category(Cat) of
		{'EXIT',_} ->
		    erlang:error({bad_category,Cat});
		_ ->
		    Obj
	    end
    end.

verify_obj_struct(Obj,_Def) ->
    case Obj#objdef.struct of
	undefined -> %% default
	    Obj#objdef { struct=var };
	defstruct ->
	    Range = [{16#0020,16#0023}, %% built-in (canopen.def)
		     {16#0040,16#0050}, 
		     {16#0080,16#009F},
		     {16#00C0,16#00DF},
		     {16#0100,16#011F},
		     {16#0140,16#015F},
		     {16#0180,16#019F},
		     {16#01C0,16#01DF},
		     {16#0200,16#021F},
		     {16#0240,16#025F}],
	    case in_range(Obj#objdef.index, Range) of
		false ->
		    erlang:error({bad_defstruct_index, Obj#objdef.index});
		true ->
		    Obj
	    end;
	deftype ->
	    Range = [{16#0001,16#0016},  %% built in (canopen.def)
		     {16#0018,16#001B},  %% built in (canopen.def)
		     16#0017, {16#001C,16#001F}, %% reserved
		     {16#0060,16#007F}, 
		     {16#00A0,16#00BF},
		     {16#00E0,16#00FF},
		     {16#0120,16#013F},
		     {16#0160,16#017F},
		     {16#01A0,16#01BF},
		     {16#01E0,16#01FF},
		     {16#0220,16#023F}],
	    case in_range(Obj#objdef.index, Range) of
		false ->
		    erlang:error({bad_deftype_index, Obj#objdef.index});
		true ->
		    Obj
	    end;
	Struct ->
	    case catch encode_struct(Struct) of
		{'EXIT',_} ->
		    erlang:error({bad_struct,Struct});
		_ ->
		    Obj
	    end
    end.

value_range(boolean) -> [{0,1},true,false];
value_range(unsigned8)   -> {0, 16#ff};
value_range(unsigned16) -> {0, 16#ffff};
value_range(unsigned24) -> {0, 16#ffffff};
value_range(unsigned32) -> {0, 16#ffffffff};
value_range(unsigned40) -> {0, 16#ffffffffff};
value_range(unsigned48) -> {0, 16#ffffffffffff};
value_range(unsigned56) -> {0, 16#ffffffffffffff};
value_range(unsigned64) -> {0, 16#ffffffffffffffff};
value_range(integer8)   -> {-16#80, 16#7f};
value_range(integer16) -> {-16#8000,16#7fff};
value_range(integer24) -> {-16#800000,16#7fffff};
value_range(integer32) -> {-16#80000000,16#7fffffff};
value_range(integer40) -> {-16#8000000000,16#7fffffffff};
value_range(integer48) -> {-16#800000000000,16#7fffffffffff};
value_range(integer56) -> {-16#80000000000000,16#7fffffffffffff};
value_range(integer64) -> {-16#8000000000000000,16#7fffffffffffffff}.


verify_range(Value,Min,Max) when Value >= Min, Value =< Max ->
    true;
verify_range(Value,Min,Max) -> 
    erlang:error({value_out_of_range,Value,Min,Max}).

verify_value(real64, Value) when is_float(Value) -> true;
verify_value(real32, Value) when is_float(Value) -> true;  %% fixme
verify_value(visible_string, Value) when is_list(Value) -> true;
verify_value(octet_string, Value) when is_list(Value) -> true;
verify_value(unicode_string, Value) when is_list(Value) -> true;
verify_value(bit_string, Value) when is_bitstring(Value) -> true;
verify_value(domain, Value) when is_binary(Value) -> true;
verify_value(Type, Value) ->
    Range = value_range(Type),
    case in_range(Value, Range) of
	true -> true;
	false -> erlang:error({value_out_of_range,Value,Type})
    end.

%% FIXME: handle deftype! when Type=Index! or special id
verify_type(Type, _Def) ->
    case catch encode_type(Type) of
	{'EXIT',_} ->
	    erlang:error({bad_type,Type});
	_ ->
	    true
    end.

%% Check enum values against base type
verify_enum_values(Base, [{Key,Value}|KVs], Ks, Vs) ->
    verify_value(Base, Value),
    case lists:member(Key, Ks) of
	true ->
	    erlang:error({enum_name_already_defined,Key,Value});
	false ->
	    case lists:member(Value,Vs) of
		true ->
		    erlang:error({enum_value_already_used,Value,Key});
		false ->
		    verify_enum_values(Base, KVs, [Key|Ks],[Value|Vs])
	    end
    end;
verify_enum_values(_Base, [], _Ks, _Vs) ->
    true.


verify_enum(Base, Name, Def) when is_atom(Name) ->
    case dict:find(Name, Def#dmod.enums) of
	error -> erlang:error({enum_type_not_defined, Name});
	{ok,Enums} -> verify_enum_values(Base, Enums, [], [])
    end;
verify_enum(Base, Enums, _Def) when is_list(Enums) ->
    verify_enum_values(Base, Enums, [], []).


%% Verify object type (default type for array entries)
verify_obj_type(Obj,Def) ->
    case Obj#objdef.type of
	undefined ->
	    Obj;
	{enum,Base,Name} ->
	    verify_type(Base, Def),
	    verify_enum(Base,Name,Def),
	    Obj;
	{bitfield,Base,Name} ->
	    verify_type(Base, Def),
	    %% FIXME: check that enum bits are non overlapping!?
	    verify_enum(Base,Name,Def),
	    Obj;
	Type ->
	    verify_type(Type, Def),
	    Obj
    end.

verify_obj_entries(Obj,Def) ->
    %% Verify all entries
    Ents0 = map(fun(Ent) -> verify_ent(Ent,Def) end, Obj#objdef.entries),
    %% Sort according to index range, detect overlap
    Ents1 = range_sort(#entdef.index, Ents0),
    Obj#objdef { entries = Ents1 }.

%% Verify entry id
verify_ent_id(Ent,_Def) ->
    case Ent#entdef.id of
	undefined ->
	    Ent;
	ID when is_atom(ID) ->
	    Ent;
	ID ->
	    erlang:error({bad_entry_name, ID})
    end.

%% Verify entry name
verify_ent_name(Ent,_Def) ->
    case Ent#entdef.name of
	undefined -> 
	    Ent;
	Name when is_list(Name) -> 
	    Ent;
	Name when is_atom(Name) ->
	    Ent#entdef { name=atom_to_list(Name) };
	Name -> 
	    erlang:error({bad_entry_name, Name})
    end.

%% Verify entry category
verify_ent_category(Ent,_Def) ->
    case Ent#entdef.category of
	undefined -> %% default
	    Ent#entdef { category=optional};	
	Cat ->
	    case catch encode_category(Cat) of
		{'EXIT',_} ->
		    erlang:error({bad_category,Cat});
		_ ->
		    Ent
	    end
    end.

%% Verify access type	    
verify_ent_access(Ent,_Def) ->
    case Ent#entdef.access of
	undefined -> %% default
	    Ent#entdef { access=ro };	
	Acc ->
	    case catch encode_access(Acc) of
		{'EXIT',_} ->
		    erlang:error({bad_access,Acc});
		_ ->
		    Ent
	    end
    end.

%% Verify entry type
verify_ent_type(Ent,Def) ->
    case Ent#entdef.type of
	{enum,Base,Name} ->
	    verify_type(Base, Def),
	    verify_enum(Base,Name,Def),
	    Ent;
	{bitfield,Base,Name} ->
	    verify_type(Base, Def),
	    %% FIXME: check that enum bits are non overlapping!?
	    verify_enum(Base,Name,Def),
	    Ent;
	Type ->
	    verify_type(Type, Def),
	    Ent
    end.

%% Verify pdo mapping
verify_ent_pdo_mapping(Ent,_Def) ->
    case Ent#entdef.pdo_mapping of
	undefined -> %% default
	    Ent#entdef { pdo_mapping=no };	
	Map ->
	    case catch encode_pdo_mapping(Map) of
		{'EXIT',_} ->
		    erlang:error({bad_pdo_mapping,Map});
		_ ->
		    Ent
	    end
    end.

%% Verify that range values are consistent with type
verify_ent_range(Ent,_Def) ->
    Ent.

%% Verify that default value is consistent with type and in range
verify_ent_default(Ent,_Def) ->
    Ent.

%% Verify that substitute value is consistent with type, possibly not
%% with range
verify_ent_substitute(Ent,_Def) ->
    Ent.

%% Sort accoring to A={A,A} or {A,B}
%% FIXME: detect overlap
range_sort(Index, Objects) ->
    lists:keysort(Index, Objects).

%%
%% Chek if value is in range/range list
%%
in_range(A, A) -> true;
in_range(A, {B,C}) when A >= B, A =< C -> true;
in_range(A, {B,_}) when A < B -> false;
in_range(A, [A|_]) -> true;
in_range(A, [{B,C}|_]) when A >= B, A =< C -> true;
in_range(A, [{B,_}|_]) when A < B -> false;
in_range(A, [_ | Rs]) -> in_range(A, Rs);
in_range(_A, _) -> false.

