%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2017, Rogvall Invest AB, <tony@rogvall.se>
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
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Malotte W Lonne <malotte@malotte.net>
%%% @copyright (C) 2017, Tony Rogvall
%%% @doc
%%% CANopen utilities.
%%%
%%% File: co_lib.erl<br/>
%%% Created:  15 Jan 2008 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(co_lib).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/co_debug.hrl").

-import(lists, [map/2, reverse/1]).

%% Serial/nodeid/cobid transformations
-export([serial_to_string/1, 
         string_to_serial/1,
         serial_to_xnodeid/1,
         serial_to_nodeid/1,
	 canid_to_nodeid/1,
         cobid_to_nodeid/1,
         cobid/2,
         add_xflag/1,
	 add_tag/1,
	 node2string/1]).

%% Encode CANOpen attributes
-export([encode_type/1,
         encode_struct/1,
         encode_access/1,
         encode_func/1,
         encode_transmission/1,
         encode_nmt_command/1]).

%% Decode CANOpen attributes
-export([decode_type/1,
         decode_struct/1,
         decode_access/1,
         decode_transmission/1,
         decode_category/1,
         decode_pdo_mapping/1,
         decode_nmt_command/1]).

%% Utilities
-export([utc_time/0,
	 sec/0,
         debug/1,
	 text_expand/2]).
-export([decode_obj/2, verify_obj/1, simple_type/1]).


%%--------------------------------------------------------------------
%% @doc
%% Convert 4 bytes serial number to a string xx:xx:xx:xx
%% @end
%%--------------------------------------------------------------------
-spec serial_to_string(Serial::binary() | integer()) ->
			      String::string().

serial_to_string(<<Serial:32>>) ->
    serial_to_string(Serial);
serial_to_string(Serial) when is_integer(Serial) ->
    lists:flatten(io_lib:format("~8.16.0B", [Serial band 16#ffffffff])).

%%--------------------------------------------------------------------
%% @doc
%% Convert a string xx:xx:xx:xx to 4 bytes serial number
%% @end
%%--------------------------------------------------------------------
-spec string_to_serial(String::string()) ->
			      Serial::integer().

string_to_serial(String) when is_list(String) ->
    erlang:list_to_integer(String, 16).

%%--------------------------------------------------------------------
%% @doc
%% Convert Serial to extended nodeid 
%% (remove least significant byte)
%% @end
%%--------------------------------------------------------------------
-spec serial_to_xnodeid(Serial::integer()) ->
			       XNodeId::integer().

serial_to_xnodeid(Serial) when is_integer(Serial)->
    (Serial bsr 8).

%%--------------------------------------------------------------------
%% @doc
%% Convert Serial to nodeid 
%% (remove least significant byte and cut to 7)
%% @end
%%--------------------------------------------------------------------
-spec serial_to_nodeid(Serial::integer()) ->
			      NodeId::integer().

serial_to_nodeid(Serial) when is_integer(Serial) ->
    ((Serial bsr 8) band 16#7f).

%%--------------------------------------------------------------------
%% @doc
%% Retreive nodeid from canid.
%% @end
%%--------------------------------------------------------------------
-spec canid_to_nodeid(CanId::integer()) ->
			     NodeId::integer().

canid_to_nodeid(CanId) when is_integer(CanId) ->
    CobId = ?CANID_TO_COBID(CanId),
    if ?is_cobid_extended((CobId)) ->
	    ?XNODE_ID(CobId);
       ?is_not_cobid_extended((CobId)) ->
	    ?NODE_ID(CobId);
       true ->
	    undefined
    end.

%%--------------------------------------------------------------------
%% @doc
%% Retreive nodeid from cobid.
%% @end
%%--------------------------------------------------------------------
-spec cobid_to_nodeid(CobId::integer()) ->
			     NodeId::integer().

cobid_to_nodeid(CobId) when is_integer(CobId)->
    if ?is_cobid_extended((CobId)) ->
	    ?XNODE_ID(CobId);
       ?is_not_cobid_extended((CobId)) ->
	    ?NODE_ID(CobId);
       true ->
	    undefined
    end.

%%--------------------------------------------------------------------
%% @doc
%% Combine nodeid with function code
%% @end
%%--------------------------------------------------------------------
-spec cobid(Func::atom(), NodeId::integer()) ->
	      CobId::integer().
cobid(F, NodeId) when is_atom(F), is_integer(NodeId)->
    Func = co_lib:encode_func(F),
    if ?is_nodeid_extended(NodeId) ->
	    XNodeId = NodeId band ?COBID_ENTRY_ID_MASK,
	    ?XCOB_ID(Func,XNodeId);
       ?is_nodeid(NodeId) ->
	    ?COB_ID(Func,NodeId);
       true ->
	    erlang:error(badarg)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Determine nodeid type and add nodeid/xnodeid tag.
%% @end
%%--------------------------------------------------------------------
add_tag(N) when is_integer(N), N > 16#7f, N =< ?COBID_ENTRY_EXTENDED ->
    {xnodeid, N bor ?COBID_ENTRY_EXTENDED};
add_tag(N) when is_integer(N), N > 0 ->
    {nodeid, N}.

%%--------------------------------------------------------------------
%% @doc
%% Combine nodeid with extended flag.
%% @end
%%--------------------------------------------------------------------
add_xflag(NodeId) when is_integer(NodeId) ->
    NodeId bor ?COBID_ENTRY_EXTENDED;
add_xflag(NodeId) ->
    NodeId.

%%--------------------------------------------------------------------
%% @doc
%% Translate node  to string for easy output.
%% @end
%%--------------------------------------------------------------------
node2string(NodeId) when is_integer(NodeId), NodeId > 16#7f ->
    io_lib:format("~6.16.0B", [NodeId band 16#ffffff]);
node2string(NodeId) when is_integer(NodeId), NodeId < 16#80->
    io_lib:format("~2.16.0B", [NodeId]);
node2string({Tag, NodeId})  when is_integer(NodeId) ->
    lists:flatten(io_lib:fwrite("{~w, ", [Tag]) ++ node2string(NodeId) ++ "}").

%%--------------------------------------------------------------------
%% @doc
%% Encode category 
%% @end
%%--------------------------------------------------------------------
-spec encode_category(C::atom()) -> Category::integer().

encode_category(optional) -> ?CATEGORY_OPTIONAL;
encode_category(mandatory) -> ?CATEGORY_MANDATORY;
encode_category(conditional) ->  ?CATEGORY_CONDITIONAL.

%%--------------------------------------------------------------------
%% @doc
%% Decode category 
%% @end
%%--------------------------------------------------------------------
-spec decode_category(C::integer()) -> Category::atom().

decode_category(?CATEGORY_OPTIONAL) -> optional;
decode_category(?CATEGORY_MANDATORY) -> mandatory;
decode_category(?CATEGORY_CONDITIONAL) -> conditional.


%%--------------------------------------------------------------------
%% @doc
%% Encode access field
%% @end
%%--------------------------------------------------------------------
-spec encode_access(A::atom()) -> Access::integer().

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

%%--------------------------------------------------------------------
%% @doc
%% Decode access field
%% @end
%%--------------------------------------------------------------------
-spec decode_access(A::integer()) -> Access::atom().

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

%%--------------------------------------------------------------------
%% @doc
%% Encode standard type field
%% @end
%%--------------------------------------------------------------------
-spec encode_type(T::atom() |
		     {enum, Base::integer(), Name::atom()} |
		     {bitfield, Base::integer(), Name::atom()}) -> 
			 Type::integer().

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

simple_type(undefined) ->
    false; %% ??
simple_type(T) ->
    ?dbg("simple_type: testing ~p", [T]),
    case encode_type(T) of
	Simple when Simple < 16#0020 -> true;
	_Complex -> false
    end.

%%--------------------------------------------------------------------
%% @doc
%% Decode standard type field
%% @end
%%--------------------------------------------------------------------
-spec decode_type(T::integer()) -> Type::atom().

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

%%--------------------------------------------------------------------
%% @doc
%% Encode pdo mapping flag
%% @end
%%--------------------------------------------------------------------
-spec encode_pdo_mapping(P::atom()) -> 
				PdoMap::integer().

encode_pdo_mapping(no) -> ?MAPPING_NO;
encode_pdo_mapping(optional) -> ?MAPPING_OPTIONAL;
encode_pdo_mapping(default) -> ?MAPPING_DEFAULT.

%%--------------------------------------------------------------------
%% @doc
%% Decode pdo mapping flag
%% @end
%%--------------------------------------------------------------------
-spec decode_pdo_mapping(P::integer()) -> 
				PdoMap::atom().

decode_pdo_mapping(?MAPPING_NO) -> no;
decode_pdo_mapping(?MAPPING_OPTIONAL) -> optional;
decode_pdo_mapping(?MAPPING_DEFAULT) -> default.

%%--------------------------------------------------------------------
%% @doc
%% Encode struct
%% @end
%%--------------------------------------------------------------------
-spec encode_struct(S::atom()) -> 
			   Struct::integer().

encode_struct(null)      -> ?OBJECT_NULL;
encode_struct(domain)    -> ?OBJECT_DOMAIN;
encode_struct(deftype)   -> ?OBJECT_DEFTYPE;
encode_struct(defstruct) -> ?OBJECT_DEFSTRUCT;
encode_struct(var)       -> ?OBJECT_VAR;
encode_struct(array)     -> ?OBJECT_ARRAY;
encode_struct(rec)       -> ?OBJECT_RECORD;
encode_struct(defpdo)    -> ?OBJECT_DEFPDO.

%%--------------------------------------------------------------------
%% @doc
%% Decode struct
%% @end
%%--------------------------------------------------------------------
-spec decode_struct(S::integer()) -> 
				Struct::atom().

decode_struct(?OBJECT_NULL)      -> null;
decode_struct(?OBJECT_DOMAIN)    -> domain;
decode_struct(?OBJECT_DEFTYPE)   -> deftype;
decode_struct(?OBJECT_DEFSTRUCT) -> defstruct;
decode_struct(?OBJECT_VAR)       -> var;
decode_struct(?OBJECT_ARRAY)     -> array;
decode_struct(?OBJECT_RECORD)    -> rec.


%%--------------------------------------------------------------------
%% @doc
%% Encode PDO parameter transmission type
%% @end
%%--------------------------------------------------------------------
-spec encode_transmission(T::atom()) -> 
				 Transmission::integer().

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
%%--------------------------------------------------------------------
%% @doc
%% Decode PDO parameter transmission type
%% @end
%%--------------------------------------------------------------------
-spec decode_transmission(T::integer()) -> 
				Transmission::atom().

decode_transmission(?TRANS_EVENT_SPECIFIC) -> specific;
decode_transmission(?TRANS_EVENT_PROFILE) -> profile;
decode_transmission(?TRANS_RTR) -> rtr;
decode_transmission(?TRANS_RTR_SYNC) -> rtr_sync;
decode_transmission(?TRANS_SYNC_ONCE) -> once;
decode_transmission(N) when is_integer(N), N >= 0, N =< ?TRANS_SYNC_MAX ->
    {sync,N};
decode_transmission(N) when is_integer(N), N >= 0, N =< 255 ->
    N.

%%--------------------------------------------------------------------
%% @doc
%% Encode function codes.
%% @end
%%--------------------------------------------------------------------
-spec encode_func(Func::atom()) -> FuncCode::integer().

encode_func(nmt) -> ?NMT;
encode_func(sync) -> ?SYNC;
encode_func(time_stamp) -> ?TIME_STAMP;
encode_func(pdo1_tx) -> ?PDO1_TX;
encode_func(pdo1_rx) -> ?PDO1_RX;
encode_func(pdo2_tx) -> ?PDO2_TX;
encode_func(pdo2_rx) -> ?PDO2_RX;
encode_func(pdo3_tx) -> ?PDO3_TX;
encode_func(pdo3_rx) -> ?PDO3_RX;
encode_func(pdo4_tx) -> ?PDO4_TX;
encode_func(pdo4_rx) -> ?PDO4_RX;
encode_func(sdo_tx) -> ?SDO_TX;
encode_func(sdo_rx) -> ?SDO_RX;
encode_func(node_guard) -> ?NODE_GUARD;
encode_func(lss) -> ?LSS;
encode_func(emergency) -> ?EMERGENCY;
encode_func(F) when F >= 0, F < 15 -> F;
encode_func(_) -> erlang:error(badarg).

%%--------------------------------------------------------------------
%% @doc
%% Encode nmt commands.
%% @end
%%--------------------------------------------------------------------
-spec encode_nmt_command(Cmd::atom() | integer()) -> CmdCode::integer().

encode_nmt_command(start) -> ?NMT_START_REMOTE_NODE;
encode_nmt_command(stop) -> ?NMT_STOP_REMOTE_NODE;
encode_nmt_command(enter_pre_op) -> ?NMT_ENTER_PRE_OPERATIONAL;
encode_nmt_command(reset) -> ?NMT_RESET_NODE;
encode_nmt_command(reset_com) -> ?NMT_RESET_COMMUNICATION;
encode_nmt_command(Cmd) when is_integer(Cmd) -> Cmd; %% ??
encode_nmt_command(_) -> erlang:error(badarg).

%%--------------------------------------------------------------------
%% @doc
%% Encode nmt commands.
%% @end
%%--------------------------------------------------------------------
-spec decode_nmt_command(Cmd::integer()) -> 
				 CmdCode::atom().

decode_nmt_command(?NMT_START_REMOTE_NODE) -> start;
decode_nmt_command(?NMT_STOP_REMOTE_NODE) -> stop;
decode_nmt_command(?NMT_ENTER_PRE_OPERATIONAL) -> enter_pre_op;
decode_nmt_command(?NMT_RESET_NODE) -> reset;
decode_nmt_command(?NMT_RESET_COMMUNICATION) -> reset_com;
decode_nmt_command(Other) -> Other.

decode_obj([Opt|Options], Obj) ->
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
decode_obj_opt(_Kv={Key,Value}, Obj) ->
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
	type  -> 
	    Obj#objdef { type=Value };
	access ->
	    Obj#objdef { access=Value };
	range ->
	    Obj#objdef { range=Value }
    end.



%% Decode entry description options.
decode_ent([Opt|Opts], Ent) ->
    Ent1 = decode_ent_opt(Opt, Ent),
    decode_ent(Opts, Ent1);
decode_ent([], Ent) ->
    Ent.

%% Decode entry description option
decode_ent_opt(_Kv={Key,Value}, Ent) ->
    case Key of
	name ->
	    Ent#entdef { name=Value };
	id ->
	    Ent#entdef { id=Value };
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
verify_obj(Obj) ->
    verify([fun verify_obj_name/1,
	    fun verify_obj_type/1,
	    fun verify_obj_struct/1,
	    fun verify_obj_category/1,
	    fun verify_obj_entries/1], Obj).
	    
%%
%% Verify entry
%%	    
	
verify_ent(Ent) ->
    verify([fun verify_ent_id/1,
	    fun verify_ent_name/1,
	    fun verify_ent_category/1,
	    fun verify_ent_access/1,
	    fun verify_ent_type/1,
	    fun verify_ent_pdo_mapping/1,
	    fun verify_ent_range/1,
	    fun verify_ent_default/1,
	    fun verify_ent_substitute/1],
	   Ent).

verify([V|Vs], Obj) ->
    verify(Vs, V(Obj));
verify([], Obj) ->
    Obj.

%% Verify object name
verify_obj_name(Obj) ->
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
verify_obj_category(Obj) ->
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

verify_obj_struct(Obj) ->
    case Obj#objdef.struct of
	undefined -> %% default
	    Obj#objdef { struct=var };
	defstruct ->
	    Range = [{16#0020,16#0025}, %% built-in (canopen.def)
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
		     16#0017,            %% reserved
		     {16#001C,16#001F},  %% reserved
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

%% To be used ??
%% verify_range(Value,Min,Max) when Value >= Min, Value =< Max ->
%%     true;
%% verify_range(Value,Min,Max) -> 
%%     erlang:error({value_out_of_range,Value,Min,Max}).

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
verify_type(Type) ->
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

verify_enum(Base, Name) when is_atom(Name) ->
    case co_objdef:prev({enum,Name,'\377',1}) of
	Key={enum,Name,_Mod,_Version} ->
	    case co_objdef:lookup_object(Key) of
		false ->
		    erlang:error({enum_type_not_defined, Name});
		{enum,_,Enums} ->
		    verify_enum_values(Base, Enums, [], [])
	    end;
	_Key ->
	    io:format("Key = ~p\n", [_Key]),
	    erlang:error({enum_type_not_defined, Name})
    end;
verify_enum(Base, Enums) when is_list(Enums) ->
    verify_enum_values(Base, Enums, [], []).


%% Verify object type (default type for array entries)
verify_obj_type(Obj) ->
    case Obj#objdef.type of
	undefined ->
	    Obj;
	{enum,Base,Name} ->
	    verify_type(Base),
	    verify_enum(Base,Name),
	    Obj;
	{bitfield,Base,Name} ->
	    verify_type(Base),
	    %% FIXME: check that enum bits are non overlapping!?
	    verify_enum(Base,Name),
	    Obj;
	Type ->
	    verify_type(Type),
	    Obj
    end.

verify_obj_entries(Obj) ->
    %% Verify all entries
    Ents0 = map(fun(Ent) -> verify_ent(Ent) end, Obj#objdef.entries),
    %% Sort according to index range, detect overlap
    Ents1 = range_sort(#entdef.index, Ents0),
    Obj#objdef { entries = Ents1 }.

%% Verify entry id
verify_ent_id(Ent) ->
    case Ent#entdef.id of
	undefined ->
	    Ent;
	ID when is_atom(ID) ->
	    Ent;
	ID ->
	    erlang:error({bad_entry_name, ID})
    end.

%% Verify entry name
verify_ent_name(Ent) ->
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
verify_ent_category(Ent) ->
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
verify_ent_access(Ent) ->
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
verify_ent_type(Ent) ->
    case Ent#entdef.type of
	{enum,Base,Name} ->
	    verify_type(Base),
	    verify_enum(Base,Name),
	    Ent;
	{bitfield,Base,Name} ->
	    verify_type(Base),
	    %% FIXME: check that enum bits are non overlapping!?
	    verify_enum(Base,Name),
	    Ent;
	Type ->
	    verify_type(Type),
	    Ent
    end.

%% Verify pdo mapping
verify_ent_pdo_mapping(Ent) ->
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
verify_ent_range(Ent) ->
    Ent.

%% Verify that default value is consistent with type and in range
verify_ent_default(Ent) ->
    Ent.

%% Verify that substitute value is consistent with type, possibly not
%% with range
verify_ent_substitute(Ent) ->
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


utc_time() ->
    TS = {_,_,Micro} = os:timestamp(),
    {{Year,Month,Day},{Hour,Minute,Second}} = 
	calendar:now_to_universal_time(TS),
    Mstr = element(Month,{"Jan","Feb","Mar","Apr","May","Jun","Jul",
			  "Aug","Sep","Oct","Nov","Dec"}),
    io_lib:format("~2w ~s ~4w ~2w:~2..0w:~2..0w.~6..0w",
		  [Day,Mstr,Year,Hour,Minute,Second,Micro]).

%%--------------------------------------------------------------------
%% @doc
%% Seconds utility, gives timestamp as seconds.
%% @end
%%--------------------------------------------------------------------
-spec sec() -> Sec::integer().
sec() ->
    {MegaSec, Sec, _MilliSec} = os:timestamp(),
    1000 * MegaSec + Sec.


debug(true) ->
    ale:trace(on, self(), debug);
debug(false) ->
    ale:trace(off, self(), debug).

%%
%% Utility to exand environment "variables" in unicode text
%% variables are written as ${var} where var is a encoded atom
%% operating system enviroment is accessed through $(VAR)
%% and application library dir $/app/
%%
text_expand(Text, Env) when is_list(Text) ->
    %% assume unicode character list!
    text_expand_(Text, [], Env);
text_expand(Text, Env) when is_binary(Text) ->
    %% assume utf8 encoded data!
    text_expand_(unicode:characters_to_list(Text), [], Env).

text_expand_([$$,${|Text], Acc, Env) ->
    text_expand_collect_(Text, [], [${,$$], env, Acc, Env);
text_expand_([$$,$(|Text], Acc, Env) ->
    text_expand_collect_(Text, [], [$(,$$], shell, Acc, Env);
text_expand_([$$,$/|Text], Acc, Env) ->
    text_expand_collect_(Text, [], [$/,$$], lib, Acc, Env);
text_expand_([$\\,C|Text], Acc, Env) ->
    text_expand_(Text, [C|Acc], Env);
text_expand_([C|Text], Acc, Env) ->
    text_expand_(Text, [C|Acc], Env);
text_expand_([], Acc, _Env) ->
    lists:reverse(Acc).


text_expand_collect_([$)|Text], Var, _Pre, shell, Acc, Env) ->
    case os:getenv(rev_variable(Var)) of
	false ->
	    text_expand_(Text, Acc, Env);
	Value ->
	    Acc1 = lists:reverse(Value, Acc),
	    text_expand_(Text, Acc1, Env)
    end;
text_expand_collect_([$/|Text], Var, _Pre, lib, Acc, Env) ->
    try erlang:list_to_existing_atom(rev_variable(Var)) of
	App ->
	    case code:lib_dir(App) of
		{error,_} ->
		    text_expand_(Text, Acc, Env);
		Value ->
		    Acc1 = lists:reverse(Value, Acc),
		    text_expand_(Text, Acc1, Env)
	    end
    catch
	error:_ ->
	    text_expand_(Text, Acc, Env)
    end;
text_expand_collect_([$}|Text], Var, _Pre, env, Acc, Env) ->
    try erlang:list_to_existing_atom(rev_variable(Var)) of
	Key ->
	    case lists:keyfind(Key, 1, Env) of
		false ->
		    text_expand_(Text, Acc, Env);
		{_,Val} ->
		    Value = lists:flatten(io_lib:format("~w", [Val])),
		    Acc1 = lists:reverse(Value, Acc),
		    text_expand_(Text, Acc1, Env)
	    end
    catch
	error:_ ->
	    text_expand_(Text, Acc, Env)
    end;
text_expand_collect_([C|Text], Var, Pre, Shell, Acc, Env) ->
    if C >= $a, C =< $z;
       C >= $A, C =< $Z;
       C >= $0, C =< $9;
       C == $_; C == $@;
       C == $\s; C == $\t -> %% space and tab allowed in begining and end
	    text_expand_collect_(Text, [C|Var], Pre, Shell, Acc, Env);
       true ->
	    %% char not allowed in variable named
	    text_expand_(Text,  [C | Var ++ Pre ++ Acc], Env)
    end;
text_expand_collect_([], Var, Pre, _Shell, Acc, Env) ->
    text_expand_([],  Var ++ Pre ++ Acc, Env).

rev_variable(Var) ->
    trim_hd(lists:reverse(trim_hd(Var))).

trim_hd([$\s|Cs]) -> trim_hd(Cs);
trim_hd([$\t|Cs]) -> trim_hd(Cs);
trim_hd(Cs) -> Cs.

