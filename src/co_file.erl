%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2013, Rogvall Invest AB, <tony@rogvall.se>
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
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%% Utilities to load dictionary from file.
%%%
%%% File: co_file.erl<br/>
%%% Created:  3 Feb 2009 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(co_file).

-include("canopen.hrl").

-export([load/1]).
-export([load_objects/2]).
-import(lists, [map/2, seq/2, foreach/2]).

-ifdef(OTP_RELEASE). %% this implies 21 or higher
-define(EXCEPTION(Class, Reason, Stacktrace), Class:Reason:Stacktrace).
-define(GET_STACK(Stacktrace), Stacktrace).
-else.
-define(EXCEPTION(Class, Reason, _), Class:Reason).
-define(GET_STACK(_), erlang:get_stacktrace()).
-endif.

%%--------------------------------------------------------------------
%% @doc
%% Load (symbolic) entries from file.
%%
%% The data can then be used to bootstrap can nodes. <br/>
%% The Data is return as: <br/>
%% [ {Object, [Entry0,Entry1,...EntryN]} ]
%%
%% @end
%%--------------------------------------------------------------------
-spec load(File::string()) -> 
		  {ok, list(term())} | {error, term()}.

load(File) ->
    case file:consult(File) of
	{ok,Objects} ->
	    try load_objects(Objects, []) of
		Os -> {ok,Os}
	    catch
		?EXCEPTION(error,Error,Trace) ->
		    ?ee("load: error ~p\n~w\n",
			[Error,?GET_STACK(Trace)]),
		    {error,Error}
	    end;
	Error ->
	    Error
    end.


%% @private
load_objects([{object,Index,Options}|Es],Os) 
  when ?is_index(Index), is_list(Options) ->
    lager:debug([{index, Index}],
	 "load_objects: object ~.16.0# (~p)\n", [Index, Index]),
    Obj = load_object(Options,#dict_object { index=Index },undefined,[]),
    load_objects(Es, [Obj|Os]);
%%
%% Simplified SDO server config
%%
load_objects([{sdo_server,I,ClientID}|Es],Os) ->
    lager:debug([{index, I}],
	 "load_objects: SDO-SERVER: ~w\n", [I]),
    Access = if I==0 -> ?ACCESS_RO; true -> ?ACCESS_RW end,
    Index = ?IX_SDO_SERVER_FIRST+I,
    SDORx = co_lib:cobid(sdo_rx, ClientID),
    SDOTx = co_lib:cobid(sdo_tx, ClientID),
    NodeID = nodeid(ClientID),
    Obj = sdo_record(Index,Access,SDORx,SDOTx,NodeID),
    load_objects(Es, [Obj|Os]);

load_objects([{sdo_server,I,Rx,Tx}|Es],Os) ->
    lager:debug([{index, I}],
	 "load_objects: SDO-SERVER: ~w\n", [I]),
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
    lager:debug([{index, I}],
	 "load_objects: SDO-SERVER: ~w\n", [I]),
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
    lager:debug([{index, I}],
	 "load_objects: SDO-CLIENT: ~w\n", [I]),
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
    lager:debug([{index, I}],
	 "load_objects: TPDO-PARAMETER: ~w\n", [I]),
    Index = ?IX_TPDO_PARAM_FIRST + I,
    COBID = cobid(ID),
    Trans = proplists:get_value(transmission_type,Opts,specific),
    InhibitTime = proplists:get_value(inhibit_time,Opts,0),
    EventTimer  = proplists:get_value(event_timer,Opts,0),
    Obj = {#dict_object { index = Index, type=?PDO_PARAMETER,
			  struct=?OBJECT_RECORD, access=?ACCESS_RW },
	   [
	    #dict_entry { index={Index,0}, type=?UNSIGNED8,
			  access=?ACCESS_RO, data=(<<5>>) },
	    #dict_entry { index={Index,1}, type=?UNSIGNED32,
			  access=?ACCESS_RW, 
			  data=co_codec:encode(COBID,?UNSIGNED32) },
	    #dict_entry { index={Index,2}, type=?UNSIGNED8,
			  access=?ACCESS_RW, 
			  data=co_codec:encode(co_lib:encode_transmission(Trans),
					       ?UNSIGNED8) },
	    #dict_entry { index={Index,3}, type=?UNSIGNED16,
			  access=?ACCESS_RW, 
			  data=co_codec:encode(InhibitTime,?UNSIGNED16) },
	    #dict_entry { index={Index,4}, type=?UNSIGNED8,
			  access=?ACCESS_RW, data=(<<0>>)},
	    #dict_entry { index={Index,5}, type=?UNSIGNED16,
			  access=?ACCESS_RW, 
			  data=co_codec:encode(EventTimer,?UNSIGNED16) }]},
    lager:debug("load_objects: TPDO-PARAMETER: ~w\n", [Obj]),
    load_objects(Es, [Obj|Os]);
%%
%% TPDO mapping
%%
load_objects([{tpdo_map,I,Map, Opts}|Es], Os) ->
    lager:debug([{index, I}],
	 "load_objects: TPDO-MAP: ~w\n", [I]),
    Index = ?IX_TPDO_MAPPING_FIRST + I,
    Type = proplists:get_value(pdo_type,Opts,pdo),
    N = length(Map),
    Si0Value = case Type of
		   pdo -> N;
		   sam_mpdo -> ?SAM_MPDO;
		   dam_mpdo -> ?DAM_MPDO
	       end,
    Obj={#dict_object { index = Index, type=?PDO_MAPPING,
			struct=?OBJECT_RECORD, access=?ACCESS_RW },
	 [
	  #dict_entry { index={Index,0}, type=?UNSIGNED8,
			access=?ACCESS_RW, 
			data=co_codec:encode(Si0Value, ?UNSIGNED8) }
	  | map(fun({Si,{Mi,Ms,Bl}}) ->
			#dict_entry { index={Index,Si}, type=?UNSIGNED32,
				      access=?ACCESS_RW,
				      data=co_codec:encode(?PDO_MAP(Mi,Ms,Bl),
							   ?UNSIGNED32) }
	       end, lists:zip(seq(1,N), Map))]},
    load_objects(Es, [Obj|Os]);
%%
%% RPDO parameter config
%%
load_objects([{rpdo,I,ID,Opts}|Es],Os) ->
    lager:debug([{index, I}],
	 "load_objects: RPDO-PARAMETER: ~w\n", [I]),
    Index = ?IX_RPDO_PARAM_FIRST + I,
    COBID = cobid(ID),
    Trans = proplists:get_value(transmission_type,Opts,specific),
    InhibitTime = proplists:get_value(inhibit_time,Opts,0),
    EventTimer  = proplists:get_value(event_timer,Opts,0),
    Obj = {#dict_object { index = Index, type=?PDO_PARAMETER,
			  struct=?OBJECT_RECORD, access=?ACCESS_RW },
	   [
	    #dict_entry { index={Index,0}, type=?UNSIGNED8,
			  access=?ACCESS_RO, data=(<<5>>) },
	    #dict_entry { index={Index,1}, type=?UNSIGNED32,
			  access=?ACCESS_RW, 
			  data=co_codec:encode(COBID, ?UNSIGNED32) },
	    #dict_entry { index={Index,2}, type=?UNSIGNED8,
			  access=?ACCESS_RW,
			  data=co_codec:encode(co_lib:encode_transmission(Trans),
					       ?UNSIGNED8)},
	    #dict_entry { index={Index,3}, type=?UNSIGNED16,
			  access=?ACCESS_RW, 
			  data=co_codec:encode(InhibitTime,?UNSIGNED16) },
	    #dict_entry { index={Index,4}, type=?UNSIGNED8,
			  access=?ACCESS_RW, data=(<<0>>)},
	    #dict_entry { index={Index,5}, type=?UNSIGNED16,
			  access=?ACCESS_RW, 
			  data=co_codec:encode(EventTimer,?UNSIGNED16) }]},
    load_objects(Es, [Obj|Os]);

%%
%% RPDO mapping
%%
load_objects([{rpdo_map,I,Map}|Es], Os) ->
    lager:debug([{index, I}],
	 "load_objects: RPDO-MAP: ~w\n", [I]),
    Index = ?IX_RPDO_MAPPING_FIRST + I,
    N = length(Map),
    Obj = {#dict_object { index = Index, type=?PDO_MAPPING,
			  struct=?OBJECT_RECORD, access=?ACCESS_RW },
	   [#dict_entry { index={Index,0}, type=?UNSIGNED8,
			  access=?ACCESS_RW, 
			  data=co_codec:encode(N,?UNSIGNED8) }
	    | map(fun({Si,{Mi,Ms,Bl}}) ->
			  #dict_entry { index={Index,Si}, type=?UNSIGNED32,
					access=?ACCESS_RW,
					data=co_codec:encode(?PDO_MAP(Mi,Ms,Bl),
							     ?UNSIGNED32) }
		  end, lists:zip(seq(1,N), Map))]},
    load_objects(Es, [Obj|Os]);
%% 
%% MPDO Object Dispatching List (I is zero based)
%% value range 1 - 16#FE 
%%
load_objects([{mpdo_dispatch,I,Map}|Es], Os) ->
    lager:debug([{index, I}],
	 "load_objects: MPDO-DISPATCH: ~w\n", [ I]),
    Index = ?IX_OBJECT_DISPATCH_FIRST + I,
    N = length(Map),
    Obj = {#dict_object { index = Index, type=?UNSIGNED64,
			  struct=?OBJECT_ARRAY, access=?ACCESS_RW },
	   [#dict_entry { index={Index,0}, type=?UNSIGNED8,
			  access=?ACCESS_RW, data=co_codec:encode(N,?UNSIGNED8) }
	    | map(fun({Si,{Bs,Li,Ls,Ri,Rs,Ni}}) ->
			  #dict_entry { index={Index,Si}, type=?UNSIGNED64,
					access=?ACCESS_RW,
					data=co_codec:encode(
					       ?RMPDO_MAP(Bs,Li,Ls,Ri,Rs,Ni),
					       ?UNSIGNED64) }
		  end, lists:zip(seq(1,N), Map))]},
    lager:debug("load_objects: MPDO-DISPATCH: ~w\n", [Obj]),
    load_objects(Es, [Obj|Os]);

load_objects([{mpdo_scanner,I,Map}|Es], Os) ->
    lager:debug([{index, I}],
	 "load_objects: MPDO-SCANNER: ~w\n", [I]),
    Index = ?IX_OBJECT_SCANNER_FIRST + I,
    N = length(Map),
    Obj = {#dict_object { index = Index, type=?UNSIGNED32,
			  struct=?OBJECT_ARRAY, access=?ACCESS_RW },
	   [#dict_entry { index={Index,0}, type=?UNSIGNED8,
			  access=?ACCESS_RW,  data=co_codec:encode(N,?UNSIGNED8) }
	    | map(fun({Si,{Bs,Li,Ls}}) ->
			  #dict_entry { index={Index,Si}, type=?UNSIGNED32,
					access=?ACCESS_RW,
					data=co_codec:encode(?TMPDO_MAP(Bs,Li,Ls),
							     ?UNSIGNED32) }
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
	    GuessedType = %% Overridden if found
		entry_type(SubIndex,O#dict_object.type,O#dict_object.struct),
	    E=load_entry(SubOpts,#dict_entry{index={Index,SubIndex},type = GuessedType}),
	    %% Encode the value according to type
	    load_object(Opts,O,V,[E|Es])
    end;
load_object([],O,V,[]) when O#dict_object.struct == ?OBJECT_VAR ->
    {O,[#dict_entry{index={O#dict_object.index,0},
		    type   = O#dict_object.type,
		    access = O#dict_object.access,
		    data=co_codec:encode(V, O#dict_object.type)}]};
load_object([],O,_V,Es) ->
    {O,Es}.


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
	    Data = co_codec:encode(V, Entry#dict_entry.type),
	    load_entry(Opts,Entry#dict_entry {data=Data})
    end;
load_entry([],Entry) ->
    Entry.


sdo_record(Index,Access,COB1,COB2,NodeID) ->
    N = if NodeID == undefined -> 2; true -> 3 end,
    [#dict_object { index=Index, type=?SDO_PARAMETER,
		    struct=?OBJECT_RECORD, access=?ACCESS_RW },
     #dict_entry { index={Index,0}, type=?UNSIGNED8, 
		   access=?ACCESS_RO, data=co_codec:encode(N,?UNSIGNED8) },
     %% Client->Server(Rx)
     #dict_entry { index={Index,1}, type=?UNSIGNED32,
		   access=Access, data=co_codec:encode(COB1, ?UNSIGNED32) },
     %% Server->Client(Tx)
     #dict_entry { index={Index,2}, type=?UNSIGNED32,
		   access=Access, data=co_codec:encode(COB2, ?UNSIGNED32) } |
     if NodeID == undefined ->
	     [];
	true ->
	     %% Client ID
	     [#dict_entry { index={Index,3}, type=?UNSIGNED8,
		   access=?ACCESS_RW, data=co_codec:encode(NodeID,?UNSIGNED8) }]
     end].


%% derive entry type, when missing and possible
entry_type(0,_,?OBJECT_ARRAY)  -> ?UNSIGNED8;
entry_type(0,_,?OBJECT_RECORD) -> ?UNSIGNED8;
entry_type(_SI,Type,_)  -> Type. %% ?? ?????????????????

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
    co_lib:cobid(F,N);
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

%% fold(Fun, Acc, File) ->
%%     case load(File) of
%% 	{ok,Os} ->
%% 	    fold_objects(Fun, Acc, Os);
%% 	Error ->
%% 	    Error
%%     end.

%% %% Add objects and entries
%% fold_objects(Fun, Acc, [Obj={O,_}|Os]) when is_record(O, dict_object) ->
%%     Acc1 = Fun(Obj, Acc),
%%     fold_objects(Fun, Acc1, Os);
%% fold_objects(_Fun, Acc, []) ->
%%     Acc.


