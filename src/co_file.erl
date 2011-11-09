%%% File    : co_file.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Utilities to load dictionary from file
%%% Created :  3 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(co_file).

-include("../include/canopen.hrl").

-export([load/1, fold/3]).
-import(lists, [map/2, seq/2, foreach/2]).
%%
%% Load (symbolic) entries from file
%% The data can then be used to bootstrap can nodes
%% The Data is return as:
%% [ {Object, [Entry0,Entry1,...EntryN]} ]
%%
load(File) ->
    case file:consult(File) of
	{ok,Objects} ->
	    try load_objects(Objects, []) of
		Os -> {ok,Os}
	    catch
		error:Error ->
		    {error,Error}
	    end;
	Error ->
	    Error
    end.

fold(Fun, Acc, File) ->
    case load(File) of
	{ok,Os} ->
	    fold_objects(Fun, Acc, Os);
	Error ->
	    Error
    end.

%% Add objects and entries
fold_objects(Fun, Acc, [Obj={O,_}|Os]) when is_record(O, dict_object) ->
    Acc1 = Fun(Obj, Acc),
    fold_objects(Fun, Acc1, Os);
fold_objects(_Fun, Acc, []) ->
    Acc.

load_objects([{object,Index,Options}|Es],Os) 
  when ?is_index(Index), is_list(Options) ->
    io:format("~p: Load object: ~8.16.0B\n", [?MODULE, Index]),
    Obj = load_object(Options,#dict_object { index=Index },undefined,[]),
    load_objects(Es, [Obj|Os]);
%%
%% Simplified SDO server config
%%
load_objects([{sdo_server,I,ClientID}|Es],Os) ->
    io:format("~p: Load SDO-SERVER: ~w\n", [?MODULE, I]),
    Access = if I==0 -> ?ACCESS_RO; true -> ?ACCESS_RW end,
    Index = ?IX_SDO_SERVER_FIRST+I,
    SDORx = cobid(sdo_rx, ClientID),
    SDOTx = cobid(sdo_tx, ClientID),
    NodeID = nodeid(ClientID),
    Obj = sdo_record(Index,Access,SDORx,SDOTx,NodeID),
    load_objects(Es, [Obj|Os]);

load_objects([{sdo_server,I,Rx,Tx}|Es],Os) ->
    io:format("~p: Load SDO-SERVER: ~w\n", [?MODULE, I]),
    Access = if I==0 -> ?ACCESS_RO; true -> ?ACCESS_RW end,
    Index = ?IX_SDO_SERVER_FIRST,
    SDORx = cobid(Rx),
    SDOTx = cobid(Tx),
    Obj = sdo_record(Index,Access,SDORx,SDOTx,undefined),
    load_objects(Es, [Obj|Os]);

%%
%% Load general SDO server config
%%
load_objects([{sdo_server,I,Rx,Tx,ClientID}|Es],Os) ->
    io:format("~p: Load SDO-SERVER: ~w\n", [?MODULE, I]),
    Access = if I==0 -> ?ACCESS_RO; true -> ?ACCESS_RW end,
    Index = ?IX_SDO_SERVER_FIRST+I,
    SDORx = cobid(Rx),
    SDOTx = cobid(Tx),
    NodeID = nodeid(ClientID),
    Obj = sdo_record(Index,Access,SDORx,SDOTx,NodeID),
    load_objects(Es, [Obj|Os]);
%%
%% SDO - client spec
%%
load_objects([{sdo_client,I,Tx,Rx,ServerID}|Es],Os) ->
    io:format("~p: Load SDO-CLIENT: ~w\n", [?MODULE, I]),
    Index = ?IX_SDO_CLIENT_FIRST + I,
    SDORx = cobid(Rx),
    SDOTx = cobid(Tx),
    NodeID = nodeid(ServerID),
    Obj = sdo_record(Index,?ACCESS_RW,SDOTx,SDORx,NodeID),
    load_objects(Es, [Obj|Os]);
%%
%% TPDO parameter config
%%
load_objects([{tpdo,I,ID,Opts}|Es],Os) ->
    io:format("~p: Load TPDO-PARAMETER: ~w\n", [?MODULE, I]),
    Index = ?IX_TPDO_PARAM_FIRST + I,
    COBID = cobid(ID),
    Trans = proplists:get_value(transmission_type,Opts,specific),
    InhibitTime = proplists:get_value(inhibit_time,Opts,0),
    EventTimer  = proplists:get_value(event_timer,Opts,0),
    Obj = {#dict_object { index = Index, type=?PDO_PARAMETER,
			  struct=?OBJECT_RECORD, access=?ACCESS_RW },
	   [
	    #dict_entry { index={Index,0}, type=?UNSIGNED8,
			  access=?ACCESS_RO, value=5 },
	    #dict_entry { index={Index,1}, type=?UNSIGNED32,
			  access=?ACCESS_RW, value=COBID },
	    #dict_entry { index={Index,2}, type=?UNSIGNED8,
			  access=?ACCESS_RW, 
			  value=co_lib:encode_transmission(Trans)},
	    #dict_entry { index={Index,3}, type=?UNSIGNED16,
			  access=?ACCESS_RW, value=InhibitTime},
	    #dict_entry { index={Index,4}, type=?UNSIGNED8,
			  access=?ACCESS_RW, value=0},
	    #dict_entry { index={Index,5}, type=?UNSIGNED16,
			  access=?ACCESS_RW, value=EventTimer}]},
    io:format("~p: TPDO-PARAMETER: ~w\n", [?MODULE, Obj]),
    load_objects(Es, [Obj|Os]);
%%
%% TPDO mapping
%%
load_objects([{tpdo_map,I,Map}|Es], Os) ->
    io:format("~p: Load TPDO-MAP: ~w\n", [?MODULE, I]),
    Index = ?IX_TPDO_MAPPING_FIRST + I,
    N = length(Map),
    Obj={#dict_object { index = Index, type=?PDO_MAPPING,
			struct=?OBJECT_RECORD, access=?ACCESS_RW },
	 [
	  #dict_entry { index={Index,0}, type=?UNSIGNED8,
			access=?ACCESS_RW, value=N }
	  | map(fun({Si,{Mi,Ms,Bl}}) ->
			#dict_entry { index={Index,Si}, type=?UNSIGNED32,
				      access=?ACCESS_RW,
				      value=?PDO_MAP(Mi,Ms,Bl) }
	       end, lists:zip(seq(1,N), Map))]},
    load_objects(Es, [Obj|Os]);
%%
%% RPDO parameter config
%%
load_objects([{rpdo,I,ID,Opts}|Es],Os) ->
    io:format("~p: Load RPDO-PARAMETER: ~w\n", [?MODULE, I]),
    Index = ?IX_RPDO_PARAM_FIRST + I,
    COBID = cobid(ID),
    Trans = proplists:get_value(transmission_type,Opts,specific),
    InhibitTime = proplists:get_value(inhibit_time,Opts,0),
    EventTimer  = proplists:get_value(event_timer,Opts,0),
    Obj = {#dict_object { index = Index, type=?PDO_PARAMETER,
			  struct=?OBJECT_RECORD, access=?ACCESS_RW },
	   [
	    #dict_entry { index={Index,0}, type=?UNSIGNED8,
			  access=?ACCESS_RO, value=5 },
	    #dict_entry { index={Index,1}, type=?UNSIGNED32,
			  access=?ACCESS_RW, value=COBID},
	    #dict_entry { index={Index,2}, type=?UNSIGNED8,
			  access=?ACCESS_RW,
			  value=co_lib:encode_transmission(Trans)},
	    #dict_entry { index={Index,3}, type=?UNSIGNED16,
			  access=?ACCESS_RW, value=InhibitTime},
	    #dict_entry { index={Index,4}, type=?UNSIGNED8,
			  access=?ACCESS_RW, value=0},
	    #dict_entry { index={Index,5}, type=?UNSIGNED16,
			  access=?ACCESS_RW, value=EventTimer}]},
    load_objects(Es, [Obj|Os]);

%%
%% RPDO mapping
%%
load_objects([{rpdo_map,I,Map}|Es], Os) ->
    io:format("~p: Load RPDO-MAP: ~w\n", [?MODULE, I]),
    Index = ?IX_RPDO_MAPPING_FIRST + I,
    N = length(Map),
    Obj = {#dict_object { index = Index, type=?PDO_MAPPING,
			  struct=?OBJECT_RECORD, access=?ACCESS_RW },
	   [#dict_entry { index={Index,0}, type=?UNSIGNED8,
			  access=?ACCESS_RW, value=N }
	    | map(fun({Si,{Mi,Ms,Bl}}) ->
			  #dict_entry { index={Index,Si}, type=?UNSIGNED32,
					access=?ACCESS_RW,
					value=?PDO_MAP(Mi,Ms,Bl) }
		  end, lists:zip(seq(1,N), Map))]},
    load_objects(Es, [Obj|Os]);
%% 
%% MPDO Object Dispatching List (I is zero based)
%% value range 1 - 16#FE 
%%
load_objects([{mpdo_dispatch,I,Map}|Es], Os) ->
    io:format("~p: Load Object Dispatching List: ~w\n", [?MODULE, I]),
    Index = ?IX_OBJECT_DISPATCH_FIRST + I,
    N = length(Map),
    Obj = {#dict_object { index = Index, type=?UNSIGNED64,
			  struct=?OBJECT_ARRAY, access=?ACCESS_RW },
	   [#dict_entry { index={Index,0}, type=?UNSIGNED8,
			  access=?ACCESS_RW, value=N }
	    | map(fun({Si,{Bs,Li,Ls,Ri,Rs,Ni}}) ->
			  #dict_entry { index={Index,Si}, type=?UNSIGNED64,
					access=?ACCESS_RW,
					value=?RMPDO_MAP(Bs,Li,Ls,Ri,Rs,Ni) }
		  end, lists:zip(seq(1,N), Map))]},
    load_objects(Es, [Obj|Os]);

load_objects([{mpdo_scanner,I,Map}|Es], Os) ->
    io:format("~p: Load Object Scanner List: ~w\n", [?MODULE, I]),
    Index = ?IX_OBJECT_SCANNER_FIRST + I,
    N = length(Map),
    Obj = {#dict_object { index = Index, type=?UNSIGNED32,
			  struct=?OBJECT_ARRAY, access=?ACCESS_RW },
	   [#dict_entry { index={Index,0}, type=?UNSIGNED8,
			  access=?ACCESS_RW, value=N }
	    | map(fun({Si,{Bs,Li,Ls}}) ->
			  #dict_entry { index={Index,Si}, type=?UNSIGNED32,
					access=?ACCESS_RW,
					value=?TMPDO_MAP(Bs,Li,Ls) }
		  end, lists:zip(seq(1,N), Map))]},
    load_objects(Es, [Obj|Os]);

load_objects([], Os) ->
    lists:sort(fun({O1,_},{O2,_}) -> 
		       O1#dict_object.index < O2#dict_object.index
	       end, Os).


load_object([Opt|Opts],O,V,Es) ->
    case Opt of
	{access,Access} ->
	    A = co_lib:encode_access(Access),
	    load_object(Opts,O#dict_object {access=A}, V, Es);
	{type,Type} ->
	    T = co_lib:encode_type(Type),
	    load_object(Opts,O#dict_object {type=T}, V, Es);
	{struct,Struct} ->
	    S = co_lib:encode_struct(Struct),
	    load_object(Opts,O#dict_object {struct=S}, V, Es);
	{value,V1} ->
	    load_object(Opts,O,V1,Es);
	{name,_Name} ->  %% just as comment for real entries
	    load_object(Opts,O,V,Es);
	{entry,SubIndex,SubOpts} when ?is_subind(SubIndex),is_list(SubOpts) ->
	    Index = O#dict_object.index,
	    E=load_entry(SubOpts,#dict_entry{index={Index,SubIndex}}),
	    %% Encode the value according to type
	    load_object(Opts,O,V,[E|Es])
    end;
load_object([],O,V,[]) when O#dict_object.struct == ?OBJECT_VAR ->
    {O,[#dict_entry{index={O#dict_object.index,0},
		    type   = O#dict_object.type,
		    access = O#dict_object.access,
		    value=V}]};
load_object([],O,_V,Es) ->
    Es1 = lists:map(
	    fun(E) ->
		    Type = entry_type(E#dict_entry.type,E#dict_entry.index,
				      O#dict_object.type,O#dict_object.struct),
		    E#dict_entry { type=Type }
	    end, Es),
    {O,Es1}.


load_entry([Opt|Opts],Entry) ->
    case Opt of
	{access,Access} ->
	    A = co_lib:encode_access(Access),
	    load_entry(Opts,Entry#dict_entry {access=A});
	{name,_Name} ->
	    %% just as comment for real entries
	    load_entry(Opts,Entry);
	{type,Type} ->
	    T = co_lib:encode_type(Type),
	    load_entry(Opts,Entry#dict_entry {type=T});
	{value,V} ->
	    load_entry(Opts,Entry#dict_entry {value=V})
    end;
load_entry([],Entry) ->
    Entry.


sdo_record(Index,Access,COB1,COB2,NodeID) ->
    N = if NodeID == undefined -> 2; true -> 3 end,
    [#dict_object { index=Index, type=?SDO_PARAMETER,
		    struct=?OBJECT_RECORD, access=?ACCESS_RW },
     #dict_entry { index={Index,0}, type=?UNSIGNED8, 
		   access=?ACCESS_RO, value=N },
     %% Client->Server(Rx)
     #dict_entry { index={Index,1}, type=?UNSIGNED32,
		   access=Access, value=COB1 },
     %% Server->Client(Tx)
     #dict_entry { index={Index,2}, type=?UNSIGNED32,
		   access=Access, value=COB2 } |
     if NodeID == undefined ->
	     [];
	true ->
	     %% Client ID
	     [#dict_entry { index={Index,3}, type=?UNSIGNED8,
		   access=?ACCESS_RW, value=NodeID}]
     end].


%% derive entry type, when missing and possible
entry_type(undefined,{_,0},_,?OBJECT_ARRAY)  -> unsigned8;
entry_type(undefined,{_,0},_,?OBJECT_RECORD) -> unsigned8;
entry_type(undefined,{_,I},Type,?OBJECT_ARRAY) when I>0 -> Type;
entry_type(Type,_,_,_) when Type =/= undefined -> Type.

%% Construct and check a cobid
cobid(ID) when is_integer(ID) ->
    if ID > 0, ID < 16#7f0 -> ID;
       ID > 16#7FF, ID < 16#1FC00000 ->
	    ID + ?COBID_ENTRY_EXTENDED;
       (ID band (bnot ?COBID_ENTRY_ID_MASK)) =:= ?COBID_ENTRY_EXTENDED ->
	    (ID band ?COBID_ENTRY_ID_MASK) bor ?COBID_ENTRY_EXTENDED;
       true ->
	    erlang:error(badarg)
    end;
cobid({extended,ID}) when ID > 0, ID < 16#1FC00000 ->
    ID + ?COBID_ENTRY_EXTENDED;
cobid({F,N}) -> %% symbolic cobid
    cobid(F,N);
cobid(_) ->    
    erlang:error(badarg).

%% Handle some input forms of NodeID 
nodeid(ID) when ID > 0, ID =< 127 ->
    ID;
nodeid(ID) when ID > 127, ID =< 16#1FFFFFF -> 
    ID bor ?COBID_ENTRY_EXTENDED;
nodeid({extended,ID}) when ID > 0, ID =< 16#1FFFFFF ->
    ID bor ?COBID_ENTRY_EXTENDED;
nodeid(_) ->
    erlang:error(badarg).

%% Encode symbol connection set function code
func(nmt) -> ?NMT;
func(sync) -> ?SYNC;
func(time_stamp) -> ?TIME_STAMP;
func(pdo1_tx) -> ?PDO1_TX;
func(pdo1_rx) -> ?PDO1_RX;
func(pdo2_tx) -> ?PDO2_TX;
func(pdo2_rx) -> ?PDO2_RX;
func(pdo3_tx) -> ?PDO3_TX;
func(pdo3_rx) -> ?PDO3_RX;
func(pdo4_tx) -> ?PDO4_TX;
func(pdo4_rx) -> ?PDO4_RX;
func(sdo_tx) -> ?SDO_TX;
func(sdo_rx) -> ?SDO_RX;
func(node_guard) -> ?NODE_GUARD;
func(lss) -> ?LSS;
func(emergency) -> ?EMERGENCY;
func(F) when F >= 0, F < 15 -> F;
func(_) -> erlang:error(badarg).

%% Combine nodeid with function code
cobid(F, N) ->
    Func = func(F),
    NodeID = nodeid(N),
    if ?is_nodeid_extended(NodeID) ->
	    NodeID1 = NodeID band ?COBID_ENTRY_ID_MASK,
	    ?XCOB_ID(Func,NodeID1);
       ?is_nodeid(NodeID) ->
	    ?COB_ID(Func,NodeID);
       true ->
	    erlang:error(badarg)
    end.
