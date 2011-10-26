-module(co_tmp).

%% @private
%%
%% find_sdo_client:
%%  Lookup COBID (Tx/Rx) in client side table 
%%  SDO CLIENT side lookup to find incoming SDO communication id 
%%
find_sdo_client_rx(Dict, COBID) ->
    co_dict:find_object(Dict, 
			?IX_SDO_CLIENT_FIRST, ?IX_SDO_CLIENT_LAST, 
			?SI_SDO_SERVER_TO_CLIENT, COBID).

find_sdo_client_tx(Dict, COBID) ->
    co_dict:find_object(Dict, 
			?IX_SDO_CLIENT_FIRST, ?IX_SDO_CLIENT_LAST, 
			?SI_SDO_CLIENT_TO_SERVER, COBID).

find_sdo_client_id(Dict, NodeID) ->
    co_dict:find_object(Dict,
			?IX_SDO_CLIENT_FIRST, ?IX_SDO_CLIENT_LAST, 
			?SI_SDO_NODEID, NodeID).


find_sdo_cli(Ctx, CobID) ->
    if	CobID == ?COB_ID(?SDO_TX, Ctx#co_ctx.id) ->
	    {ok,?COB_ID(?SDO_RX, Ctx#co_ctx.id)};
	CobID == ?XCOB_ID(?SDO_TX, Ctx#co_ctx.id) ->
	    {ok,?XCOB_ID(?SDO_RX, Ctx#co_ctx.id)};
       true ->
	    case find_sdo_client_rx(Ctx#co_ctx.dict, CobID) of
		{ok,Ix} ->
		    co_dict:value(Ctx#co_ctx.dict, 
				  {Ix,?SI_SDO_CLIENT_TO_SERVER});
		Error ->
		    if Ctx#co_ctx.id == 0 -> %% special master case
			    Nid = ?NODE_ID(CobID),
			    {ok, ?COB_ID(?SDO_RX, Nid)};
		       true ->
			    Error
		    end
	    end
    end.


find_sdo_server_id(Dict, NodeID) ->
    co_dict:find_object(Dict,
			?IX_SDO_SERVER_FIRST, ?IX_SDO_SERVER_LAST,
			?SI_SDO_NODEID, NodeID).


%%
%% find_sdo_server:
%%  Lookup COBID (Tx/Rx) in server side table 
%%  SDO SERVER side lookup to find incoming SDO communication id 
%%

find_sdo_server_tx(Dict, COBID) ->
    co_dict:find_object(Dict,
			?IX_SDO_SERVER_FIRST, ?IX_SDO_SERVER_LAST, 
			?SI_SDO_SERVER_TO_CLIENT, COBID).

find_sdo_server_rx(Dict, COBID) ->
    co_dict:find_object(Dict,
			?IX_SDO_SERVER_FIRST, ?IX_SDO_SERVER_LAST, 
			?SI_SDO_CLIENT_TO_SERVER, COBID).




find_sdo_srv(Ctx, CobID) ->
    if  CobID == ?COB_ID(?SDO_RX, Ctx#co_ctx.id) ->
	    {ok,?COB_ID(?SDO_TX, Ctx#co_ctx.id)};
	CobID == ?XCOB_ID(?SDO_RX, Ctx#co_ctx.id) ->
	    {ok,?XCOB_ID(?SDO_TX, Ctx#co_ctx.id)};
	true ->
	    case find_sdo_server_tx(Ctx#co_ctx.dict, CobID) of
		{ok,SRVix} ->
		    co_dict:value(Ctx#co_ctx.dict,
				  {SRVix,?SI_SDO_SERVER_TO_CLIENT});
		Error ->
		    Error
	    end
    end.



%%
%% Find RPDO parmeter entry given COBID (PDO_Tx) 
%% FIXME: cache
%%
find_rpdo(COBID, Ctx) ->
    Cmp = fun(PdoEnt) ->
		  COBID1 = cob_map(PdoEnt,Ctx),
		  if COBID1 band ?COBID_ENTRY_INVALID =/= 0 ->
			  false;
		     true ->
			  (COBID1 band ?COBID_ENTRY_ID_MASK) == COBID
		  end
	  end,
    co_dict:find_object(Ctx#co_ctx.dict,
			?IX_RPDO_PARAM_FIRST, ?IX_RPDO_PARAM_LAST,
			?SI_PDO_COB_ID, Cmp).
%%
%% Find TPDO Parameter entry given COBID (PDO_Tx)
%% FIXME: cache
%%
find_tpdo(COBID, Ctx) ->
    Cmp = fun(PdoEnt) ->
		  COBID1 = cob_map(PdoEnt,Ctx),
		  if COBID1 band ?COBID_ENTRY_INVALID =/= 0 ->
			  false;
		     COBID1 band ?COBID_ENTRY_RTR_DISALLOWED =/= 0 ->
			  false;
		     true ->
			  (COBID1 band ?COBID_ENTRY_ID_MASK) == COBID
		  end
	  end,
    co_dict:find_object(Ctx#co_ctx.dict,
			?IX_TPDO_PARAM_FIRST, ?IX_TPDO_PARAM_LAST,
			?SI_PDO_COB_ID, Cmp).
