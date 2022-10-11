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
%%% @author Malotte W Lonne <malotte@malotte.net>
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%% CANopen node.
%%%
%%% File: co_node.erl <br/>
%%% Created: 10 Jan 2008 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(co_node).

-behaviour(gen_server).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/co_app.hrl").

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2,
	 code_change/3]).

%% Application interface
-export([notify/4,  %% To send MPOs
         notify_from/5, %% To send MPOs
         subscribers/2,
         reserver_with_module/2,
         tpdo_mapping/2, 
	 rpdo_mapping/2, 
	 tpdo_data/2]).

-import(lists, [foreach/2, reverse/1, seq/2, map/2, foldl/3]).

-define(LAST_SAVED_DICT, "last.dict").
-define(DEFAULT_DICT, "default.dict").

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Send notification. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec notify(CobId::integer(), Ix::integer(), Si::integer(), Data::binary()) -> 
		    ok | {error, Error::atom()}.

notify(CobId,Index,Subind,Data)
  when ?is_index(Index), ?is_subind(Subind), is_binary(Data) ->
    FrameID = ?COBID_TO_CANID(CobId),
    Frame = #can_frame { id=FrameID, len=8, 
			 data=(<<16#80,Index:16/little,Subind:8,Data:4/binary>>) },
    lager:debug("notify: Sending frame ~p from CobId = ~.16#, CanId = ~.16#)",
	 [Frame, CobId, FrameID]),
    can:send(Frame).


%%--------------------------------------------------------------------
%% @doc
%% Send notification but not to (own) Node. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec notify_from(NodePid::pid(),CobId::integer(), Ix::integer(), Si::integer(), 
		  Data::binary()) -> 
		    ok | {error, Error::atom()}.

notify_from(NodePid, CobId,Index,Subind,Data)
  when ?is_index(Index), ?is_subind(Subind), is_binary(Data) ->
    FrameID = ?COBID_TO_CANID(CobId),
    Frame = #can_frame { id=FrameID, len=8, 
			 data=(<<16#80,Index:16/little,Subind:8,Data:4/binary>>) },
    lager:debug("notify: Sending frame ~p from CobId = ~.16#, CanId = ~.16#)",
	 [Frame, CobId, FrameID]),
    can:send_from(NodePid, Frame).


%%--------------------------------------------------------------------
%% @doc
%% Get the RPDO mapping. <br/>
%% Executing in calling process context.<br/>
%% @end
%%--------------------------------------------------------------------
-spec rpdo_mapping(Offset::integer(), TpdoCtx::#tpdo_ctx{}) -> 
			  Map::term() | {error, Error::atom()}.

rpdo_mapping(Offset, TpdoCtx) ->
    pdo_mapping(Offset+?IX_RPDO_MAPPING_FIRST, TpdoCtx).

%%--------------------------------------------------------------------
%% @doc
%% Get the TPDO mapping. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec tpdo_mapping(Offset::integer(), TpdoCtx::#tpdo_ctx{}) -> 
			  Map::term() | {error, Error::atom()}.

tpdo_mapping(Offset, TpdoCtx) ->
    pdo_mapping(Offset+?IX_TPDO_MAPPING_FIRST, TpdoCtx).

%%--------------------------------------------------------------------
%% @doc
%% Get all subscribers in Tab for Index. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec subscribers(Tab::atom() | integer(), Index::integer()) -> 
			 list(Pid::pid()) | {error, Error::atom()}.

subscribers(Tab, Ix) when ?is_index(Ix) ->
    ets:foldl(
      fun({ID,ISet}, Acc) ->
	      case co_iset:member(Ix, ISet) of
		  true -> [ID|Acc];
		  false -> Acc
	      end
      end, [], Tab).

%%--------------------------------------------------------------------
%% @doc
%% Get the reserver in Tab for Index if any. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec reserver_with_module(Tab::atom() | integer(), Index::integer()) -> 
				  {Pid::pid() | dead, Mod::atom()} | 
				  [].

reserver_with_module(Tab, Ix) when ?is_index(Ix) ->
    case ets:lookup(Tab, Ix) of
	[] -> [];
	[{Ix, Mod, Pid}] -> {Pid, Mod}
    end.

%%====================================================================
%% gen_server callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Description: Initiates the server
%% @end
%%--------------------------------------------------------------------
-spec init({Identity::term(), NodeName::atom(), Opts::list(term())}) -> 
		  {ok, Context::#co_ctx{}} |
		  {stop, Reason::term()}.


init({Serial, NodeName, Opts}) ->
    lager:debug("serial = ~.16#, name = ~p, opts = ~p\n pid = ~p", 
		[Serial, NodeName, Opts, self()]),

    %% Trace output enable/disable
    Dbg = proplists:get_value(debug,Opts,false),
    co_lib:debug(Dbg),

    co_proc:reg(Serial),

    {ShortNodeId, ExtNodeId} = nodeids(Serial,Opts),
    reg({nodeid, ShortNodeId}),
    reg({xnodeid, ExtNodeId}),
    reg({name, NodeName}),

    Dict = create_dict(),
    SubTable = create_sub_table(),
    XNotTable = ets:new(co_xnot_table, [public,ordered_set]),
    ResTable =  ets:new(co_res_table, [public,ordered_set]),
    TpdoCache = ets:new(co_tpdo_cache, [public,ordered_set]),
    MpdoDispatch = ets:new(co_mpdo_dispatch, [public,ordered_set]),
    SdoCtx = #sdo_ctx {
      timeout         = proplists:get_value(sdo_timeout,Opts,3000),
      blk_timeout     = proplists:get_value(blk_timeout,Opts,500),
      pst             = proplists:get_value(pst,Opts,16),
      max_blksize     = proplists:get_value(max_blksize,Opts,74),
      use_crc         = proplists:get_value(use_crc,Opts,true),
      readbufsize     = proplists:get_value(readbufsize,Opts,1024),
      load_ratio      = proplists:get_value(load_ratio,Opts,0.5),
      atomic_limit    = proplists:get_value(atomic_limit,Opts,1024),
      debug           = Dbg,
      dict            = Dict,
      sub_table       = SubTable,
      res_table       = ResTable
     },
    TpdoCtx = #tpdo_ctx {
      nodeid          = ShortNodeId,
      node_pid        = self(),
      dict            = Dict,
      tpdo_cache      = TpdoCache,
      res_table       = ResTable
     },
    CobTable = create_cob_table(ExtNodeId, ShortNodeId),
    Ctx = #co_ctx {
      xnodeid = ExtNodeId,
      nodeid = ShortNodeId,
      name   = NodeName,
      vendor = proplists:get_value(vendor,Opts),
      product = proplists:get_value(product,Opts),
      revision = proplists:get_value(revision,Opts),
      serial = Serial,
      state  = ?Initialisation,
      debug = Dbg,
      nmt_role = proplists:get_value(nmt_role,Opts,autonomous),
      nmt_conf = proplists:get_value(nmt_conf,Opts,default),
      supervision = proplists:get_value(supervision,Opts,none),
      sub_table = SubTable,
      res_table = ResTable,
      xnot_table = XNotTable,
      inact_subs = [],     
      inact_timeout = proplists:get_value(inact_timeout,Opts,infinity),
      can_timestamp = 0,
      dict = Dict,
      mpdo_dispatch = MpdoDispatch,
      tpdo_cache = TpdoCache,
      tpdo_cache_limit = proplists:get_value(tpdo_cache_limit,Opts,512),
      tpdo = TpdoCtx,
      cob_table = CobTable,
      app_list = [],
      tpdo_list = [],
      toggle = 0, 
      xtoggle = 0,
      data = [],
      sdo  = SdoCtx,
      sdo_list = [],
      time_stamp_time = proplists:get_value(time_stamp, Opts, 60000)
     },

    can_router:attach(),

    case load_dict_init(proplists:get_value(dict, Opts, saved), Ctx) of
	{ok, Ctx1} ->
	    %% Update dict identity object
	    lager:debug("~s: init: dict loaded, udating id.",  [NodeName]),
	    Dict = Ctx1#co_ctx.dict,
	    update_id(Dict, ?SI_IDENTITY_VENDOR, Ctx1#co_ctx.vendor),
	    update_id(Dict, ?SI_IDENTITY_PRODUCT, Ctx1#co_ctx.product),
	    update_id(Dict, ?SI_IDENTITY_REVISION, Ctx1#co_ctx.revision),
	    update_id(Dict, ?SI_IDENTITY_SERIAL, Ctx1#co_ctx.serial),

	    process_flag(trap_exit, true),

	    if ShortNodeId =:= 0 ->
		    %% CANopen manager
		    Ctx2 = initialization(Ctx1),
		    {ok, Ctx2};
	       true ->
		    %% Standard node
		    Ctx2 = reset_application(Ctx1),
		    {ok, Ctx2}
	    end;

	{error, Reason} ->
	    ?ee("~p: Loading of dict failed, reason = ~p, exiting.", 
                [NodeName, Reason]),
	    {stop, Reason}
    end.

update_id(_Dict, _Any, undefined) ->
    lager:debug("~p: update_id: not setting ~.16.0#:~w to undefined.", 
	 [self(), ?IX_IDENTITY_OBJECT, _Any]),
    ok;
update_id(Dict, SubIndex, Value) ->
    lager:debug("~p: update_id: setting ~.16.0#:~w to ~w.", 
	 [self(), ?IX_IDENTITY_OBJECT, SubIndex, Value]),
    ok = co_dict:direct_set_value(Dict, 
				  ?IX_IDENTITY_OBJECT,
				  SubIndex,
				  Value).

nodeids(Serial, Opts) ->
    {proplists:get_value(nodeid,Opts,undefined),
     case proplists:get_value(use_serial_as_xnodeid,Opts,false) of
	 false -> undefined;
	 true  -> co_lib:serial_to_xnodeid(Serial)
     end}.

reg({_, undefined}) ->	    
    do_nothing;
reg(Term) ->	
    co_proc:reg(Term).

%%
%%
%%
reset_application(Ctx=#co_ctx {name=_Name, nodeid=_SNodeId, xnodeid=_XNodeId}) ->
    ?ei("Node '~s' id=~w,~w reset_application", [_Name, _XNodeId, _SNodeId]),
    send_to_apps(reset_app, Ctx),
    reset_communication(Ctx).

reset_communication(Ctx=#co_ctx {name=_Name, nodeid=_SNodeId, xnodeid=_XNodeId}) ->
    ?ei("Node '~s' id=~w,~w reset_communication",[_Name, _XNodeId, _SNodeId]),
    send_to_apps(reset_com, Ctx),
    initialization(Ctx).

initialization(Ctx=#co_ctx {name=_Name, nodeid=SNodeId, xnodeid=_XNodeId,
			    nmt_role = NmtRole, supervision = Supervision}) ->
    ?ei("Node '~s' role=~w, id=~w,~w initialization", 
	[_Name, NmtRole, _XNodeId, SNodeId]),

    broadcast_state(?PreOperational, Ctx),
    case {NmtRole,SNodeId} of 
	{master, _S} ->
	    activate_nmt(Ctx),
	    broadcast_state(?Operational, Ctx),
	    Ctx#co_ctx {state = ?Operational}; %% ??
	{slave,_S} ->
	    Ctx1 = Ctx#co_ctx {state = ?PreOperational},
	    send_bootup(id(Ctx1)),
	    if Supervision =:= node_guard ->
		    activate_node_guard(Ctx1);
	       Supervision =:= heartbeat ->
		    activate_heartbeat(Ctx1);
	       true ->
		    Ctx1
	    end;
	{autonomous, 0} ->
	    %% Mgr
	    broadcast_state(?Operational, Ctx),
	    Ctx#co_ctx {state = ?Operational};
	{autonomous, _S} ->
	    send_bootup(id(Ctx)),
	    broadcast_state(?Operational, Ctx),
	    Ctx#co_ctx {state = ?Operational}
    end.
    

activate_node_guard(Ctx=#co_ctx {nmt_role = autonomous, name = _Name}) ->
    lager:debug("~s: activate_node_guard: autonomous, no node guarding.", [_Name]),
    Ctx;
activate_node_guard(Ctx=#co_ctx {nmt_role = master, name = _Name}) ->
    lager:debug("~s: activate_node_guard: nmt master, node guarding "
	 "handled by nmt master process.", [_Name]),
    Ctx;
activate_node_guard(Ctx=#co_ctx {nmt_role = slave, dict = Dict, name = _Name}) ->
    lager:debug("~s: activate_node_guard: nmt slave.", [_Name]),
    case co_dict:value(Dict, ?IX_GUARD_TIME) of
	{ok, NodeGuardTime} ->
	    case co_dict:value(Dict, ?IX_LIFE_TIME_FACTOR) of
		{ok, LifeTimeFactor} ->
		    case NodeGuardTime * LifeTimeFactor of
			0 -> 
			    lager:debug(
			      "~s: activate_node_guard: no node guarding.", 
			      [_Name]),
			    Ctx; %% No node guarding
			NodeLifeTime -> 
			    Timer = erlang:send_after(NodeLifeTime, self(), 
						    node_guard_timeout),
			    lager:debug("~s: activate_node_guard time ~p", 
				 [_Name,NodeLifeTime]),
			    Ctx#co_ctx {node_guard_timer = Timer, 
					node_life_time = NodeLifeTime}
		    end;
		_NotFound2 ->
		    lager:debug("~s: activate_node_guard: no life_time_factor", 
			 [_Name]),
		    Ctx
	    end;
	_NotFound1 ->
	    lager:debug("~s: activate_node_guard: no node_guard_time", [_Name]),
	    Ctx
    end.
			    
deactivate_node_guard(Ctx=#co_ctx {node_guard_timer = undefined}) ->		    
    %% Do nothing
    Ctx;
deactivate_node_guard(Ctx=#co_ctx {node_guard_timer = Timer}) ->		    
    erlang:cancel_timer(Timer),
    Ctx#co_ctx {node_guard_timer = undefined}.

activate_heartbeat(Ctx=#co_ctx {nmt_role = autonomous, name = _Name}) ->
    %% ???
    lager:debug("~s: activate_heartbeat: autonomous, no heartbeat.", [_Name]),
    Ctx;
activate_heartbeat(Ctx=#co_ctx {nmt_role = master, name = _Name}) ->
    lager:debug("~s: activate_heartbeat: nmt master/heartbeat consumer, heart "
	 "handled by nmt master process.", [_Name]),
    Ctx;
activate_heartbeat(Ctx=#co_ctx {nmt_role = slave, dict = Dict, name = _Name}) ->
    lager:debug("~s: activate_heartbeat: nmt slave.", [_Name]),
    case co_dict:value(Dict, ?IX_PRODUCER_HEARTBEAT_TIME) of
	{ok, 0} ->
	    lager:debug("~s: activate_heartbeat: no heartbeat.", [_Name]),
	    Ctx; 
	{ok, HeartBeatTime} ->
	    Timer = erlang:send_after(HeartBeatTime, self(), do_heartbeat),
	    lager:debug("~s: activate_heartbeat time ~p", [_Name,HeartBeatTime]),
	    Ctx#co_ctx {heartbeat_timer = Timer, 
			heartbeat_time = HeartBeatTime};
	_NotFound1 ->
	    lager:debug("~s: activate_heartbeat: no heartbeat_time", [_Name]),
	    Ctx
    end.
			    
deactivate_heartbeat(Ctx=#co_ctx {heartbeat_timer = undefined}) ->		    
    %% Do nothing
    Ctx;
deactivate_heartbeat(Ctx=#co_ctx {heartbeat_timer = Timer}) ->		    
    erlang:cancel_timer(Timer),
    Ctx#co_ctx {heartbeat_timer = undefined}.

%% If ShortNodeId defined use it, otherwise XNodeId
send_bootup({_TypeOfNid, undefined}) ->
    lager:debug("~p: send_bootup: ~p not defined, no bootup sent.", 
	 [self(), _TypeOfNid]),
    ok;
send_bootup(NodeId) ->
    lager:debug("~p: send_bootup: nmt slave, sending bootup to master.", [self()]),
    %% Bootup uses same CobId as NodeGuard
    send_node_guard(NodeId, 1, <<0>>).

send_node_guard({nodeid, SNodeId} = _S, Len, Data) ->
    lager:debug("~p: send_node_guard: nmt slave, sending ~p to master.", 
		[_S, Data]),
    CobId = ?COB_ID(?NODE_GUARD,SNodeId),
    lager:debug("~p: send_node_guard: nmt slave, cobid ~p.", [self(), CobId]),
    can:send_from(self(), #can_frame { id = ?COBID_TO_CANID(CobId),
				       len = Len, data = Data });
send_node_guard({xnodeid, XNodeId} = _X, Len, Data) ->
    lager:debug("~p: send_node_guard: nmt slave, sending ~p to master.", 
		[_X, Data]),
    XCobId = ?XCOB_ID(?NODE_GUARD,co_lib:add_xflag(XNodeId)),
    lager:debug("~p: send_node_guard: nmt slave, xcobid ~p.", [_X, XCobId]),
    can:send_from(self(), #can_frame { id = ?COBID_TO_CANID(XCobId),
				       len = Len, data = Data }).



%%--------------------------------------------------------------------
%% @private
%% @spec handle_call(Request, From, Context) -> {reply, Reply, Context} |  
%%                                            {reply, Reply, Context, Timeout} |
%%                                            {noreply, Context} |
%%                                            {noreply, Context, Timeout} |
%%                                            {stop, Reason, Reply, Context} |
%%                                            {stop, Reason, Context}
%% Request = {set_value, Index, SubInd, Value} | 
%%           {set_data, Index, SubInd, Data} | 
%%           {value, {index, SubInd}} | 
%%           {value, Index} | 
%%           {store, Block, CobId, Index, SubInd, Bin} | 
%%           {fetch, Block, CobId, Index, SubInd} | 
%%           {add_entry, Entry} | 
%%           {get_entry, {Index, SubIndex}} | 
%%           {get_object, Index} | 
%%           {load_dict, File} | 
%%           {attach, Pid} | 
%%           {detach, Pid}  
%% @doc
%% Description: Handling call messages.
%% @end
%%--------------------------------------------------------------------

handle_call({set_value,{Ix,Si},Value}, _From, Ctx) ->
    {Reply,Ctx1} = set_value(Ix,Si,Value,Ctx),
    {reply, Reply, Ctx1};
handle_call({direct_set_value,{Ix,Si},Value}, _From, Ctx) ->
    {Reply,Ctx1} = direct_set_value(Ix,Si,Value,Ctx),
    {reply, Reply, Ctx1};
handle_call({set_data,{Ix,Si},Data}, _From, Ctx) ->
    {Reply,Ctx1} = set_data(Ix,Si,Data,Ctx),
    {reply, Reply, Ctx1};
handle_call({direct_set_data,{Ix,Si},Data}, _From, Ctx) ->
    {Reply,Ctx1} = direct_set_data(Ix,Si,Data,Ctx),
    {reply, Reply, Ctx1};
handle_call({value,{Ix, Si}}, _From, Ctx) ->
    Result = co_dict:value(Ctx#co_ctx.dict, Ix, Si),
    {reply, Result, Ctx};
handle_call({data,{Ix, Si}}, _From, Ctx) ->
    Result = co_dict:data(Ctx#co_ctx.dict, Ix, Si),
    {reply, Result, Ctx};

handle_call({tpdo_set,I,Value,Mode}, _From, Ctx) ->
    {Reply,Ctx1} = tpdo_set(I,Value,Mode,Ctx),
    {reply, Reply, Ctx1};

handle_call({Action,Mode,{TypeOfNode,NodeId},Ix,Si,Term}, From, Ctx) 
  when Action == store;
       Action == fetch ->
    %% {reply, Res, Cx} and {noreply, Ctx} are possible reults
    handle_mgr_action(Action,Mode,{TypeOfNode,NodeId},Ix,Si,Term,default, 
		      From, Ctx);
handle_call({Action,Mode,{TypeOfNode,NodeId},Ix,Si,Term,TOut}, From, Ctx) 
  when Action == store;
       Action == fetch ->
    %% {reply, Res, Cx} and {noreply, Ctx} are possible reults
    handle_mgr_action(Action,Mode,{TypeOfNode,NodeId},Ix,Si,Term,TOut, 
		      From, Ctx);

handle_call({add_object,Object, Es}, _From, Ctx) 
  when is_record(Object, dict_object) ->
    try set_dict_object({Object, Es}, Ctx) of
	Error = {error,_} ->
	    {reply, Error, Ctx};
	Ctx1 ->
	    {reply, ok, Ctx1}
    catch
	error:Reason ->
	    {reply, {error,Reason}, Ctx}
    end;

handle_call({add_entry,Entry}, _From, Ctx) 
  when is_record(Entry, dict_entry) ->
    try set_dict_entry(Entry, Ctx) of
	Error = {error,_} ->
	    {reply, Error, Ctx};
	Ctx1 ->
	    {reply, ok, Ctx1}
    catch
	error:Reason ->
	    {reply, {error,Reason}, Ctx}
    end;

handle_call({get_entry,Index}, _From, Ctx) ->
    Result = co_dict:lookup_entry(Ctx#co_ctx.dict, Index),
    {reply, Result, Ctx};

handle_call({get_object,Index}, _From, Ctx) ->
    Result = co_dict:lookup_object(Ctx#co_ctx.dict, Index),
    {reply, Result, Ctx};

handle_call(load_dict, From, Ctx=#co_ctx {serial = Serial}) ->
    File = filename:join(code:priv_dir(canopen), 
			 co_lib:serial_to_string(Serial) ++ ?LAST_SAVED_DICT),
    handle_call({load_dict, File}, From, Ctx);
handle_call({load_dict, File}, _From, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_call: load_dict, file = ~p", [_Name, File]),    
    case load_dict_internal(File, Ctx) of
	{ok, Ctx1} ->
	    %% Inform applications (or only reservers ??)
	    send_to_apps(load, Ctx1),
	    {reply, ok, Ctx1};
	{error, Error} ->
	    {reply, Error, Ctx}
    end;

handle_call(save_dict, From, Ctx=#co_ctx {serial = Serial}) ->
    File = filename:join(code:priv_dir(canopen), 
			 co_lib:serial_to_string(Serial) ++ ?LAST_SAVED_DICT),
    handle_call({save_dict, File}, From, Ctx);
handle_call({save_dict, File}, _From, 
	    Ctx=#co_ctx {dict = Dict, name = _Name}) ->
    lager:debug("~s: handle_call: save_dict, file = ~p", [_Name, File]),    
    case co_dict:to_file(Dict, File) of
	ok ->
	    %% Inform applications (or only reservers ??)
	    send_to_apps(save, Ctx),
	    {reply, ok, Ctx};
	{error, Error} ->
	    {reply, Error, Ctx}
    end;

handle_call({attach,Pid}, _From, Ctx) when is_pid(Pid) ->
    case lists:keysearch(Pid, #app.pid, Ctx#co_ctx.app_list) of
	false ->
	    Mon = erlang:monitor(process, Pid),
	    App = #app { pid=Pid, mon=Mon },
	    Ctx1 = Ctx#co_ctx { app_list = [App |Ctx#co_ctx.app_list] },
	    {reply, {ok, Ctx#co_ctx.dict}, Ctx1};
	{value,_} ->
	    %% Already attached
	    {reply, {ok, Ctx#co_ctx.dict}, Ctx}
    end;

handle_call({detach,Pid}, _From, Ctx) when is_pid(Pid) ->
    case lists:keysearch(Pid, #app.pid, Ctx#co_ctx.app_list) of
	false ->
	    {reply, {error, not_attached}, Ctx};
	{value, App} ->
	    remove_subscriptions(Ctx#co_ctx.sub_table, Pid),
	    remove_subscriptions(Ctx#co_ctx.xnot_table, Pid),
	    remove_reservations(Ctx#co_ctx.res_table, Pid),
	    erlang:demonitor(App#app.mon, [flush]),
	    Ctx1 = Ctx#co_ctx { app_list = Ctx#co_ctx.app_list -- [App]},
	    {reply, ok, Ctx1}
    end;

handle_call({subscribe,{Ix1, Ix2},Pid}, _From, Ctx) when is_pid(Pid) ->
    case index_defined(lists:seq(Ix1, Ix2), Ctx) of
	true ->
	    Res = add_subscription(Ctx#co_ctx.sub_table, Ix1, Ix2, Pid),
	    {reply, Res, Ctx};
	false ->
	    {reply, {error, no_such_object}, Ctx}
    end;

handle_call({subscribe,Ix,Pid}, _From, Ctx) when is_pid(Pid) ->
    case index_defined([Ix], Ctx) of
	true ->
	    Res = add_subscription(Ctx#co_ctx.sub_table, Ix, Ix, Pid),
	    {reply, Res, Ctx};
	false ->
	    {reply, {error, no_such_object}, Ctx}
    end;

handle_call({unsubscribe,{Ix1, Ix2},Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = remove_subscription(Ctx#co_ctx.sub_table, Ix1, Ix2, Pid),
    {reply, Res, Ctx};

handle_call({unsubscribe,Ix,Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = remove_subscription(Ctx#co_ctx.sub_table, Ix, Ix, Pid),
    {reply, Res, Ctx};

handle_call({subscriptions,Pid}, _From, Ctx) when is_pid(Pid) ->
    Subs = subscriptions(Ctx#co_ctx.sub_table, Pid),
    {reply, Subs, Ctx};

handle_call({subscribers,Ix}, _From, Ctx)  ->
    Subs = subscribers(Ctx#co_ctx.sub_table, Ix),
    {reply, Subs, Ctx};

handle_call({subscribers}, _From, Ctx)  ->
    Subs = subscribers(Ctx#co_ctx.sub_table),
    {reply, Subs, Ctx};

handle_call({reserve,{Ix1, Ix2},Module,Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = add_reservation(Ctx#co_ctx.res_table, Ix1, Ix2, Module, Pid),
    {reply, Res, Ctx};

handle_call({reserve,Ix, Module, Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = add_reservation(Ctx#co_ctx.res_table, [Ix], Module, Pid),
    {reply, Res, Ctx};

handle_call({unreserve,{Ix1, Ix2},Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = remove_reservation(Ctx#co_ctx.res_table, Ix1, Ix2, Pid),
    {reply, Res, Ctx};

handle_call({unreserve,Ix,Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = remove_reservation(Ctx#co_ctx.res_table, [Ix], Pid),
    {reply, Res, Ctx};

handle_call({reservations,Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = reservations(Ctx#co_ctx.res_table, Pid),
    {reply, Res, Ctx};

handle_call({reserver,Ix}, _From, Ctx)  ->
    PidInList = reserver_pid(Ctx#co_ctx.res_table, Ix),
    {reply, PidInList, Ctx};

handle_call({reservers}, _From, Ctx)  ->
    Res = reservers(Ctx#co_ctx.res_table),
    {reply, Res, Ctx};

handle_call({xnot_subscribe,{Ix1, Ix2},Pid}, _From, 
	    Ctx=#co_ctx {name = _Name}) 
  when is_pid(Pid) ->
    lager:debug(
      "~s: handle_call: xnot_subscribe index = ~.16.0#-~.16.0# pid = ~p",  
      [_Name, Ix1, Ix2, Pid]),    
    Res = add_subscription(Ctx#co_ctx.xnot_table, Ix1, Ix2, Pid),
    {reply, Res, Ctx};

handle_call({xnot_subscribe,Ix,Pid}, _From, Ctx=#co_ctx {name = _Name})
  when is_pid(Pid) ->
    lager:debug("~s: handle_call: xnot_subscribe index = ~.16.0# pid = ~p",  
	 [_Name, Ix, Pid]),    
    Res = add_subscription(Ctx#co_ctx.xnot_table, Ix, Ix, Pid),
    {reply, Res, Ctx};

handle_call({xnot_unsubscribe,{Ix1, Ix2},Pid}, _From, Ctx) 
  when is_pid(Pid) ->
    Res = remove_subscription(Ctx#co_ctx.xnot_table, Ix1, Ix2, Pid),
    {reply, Res, Ctx};

handle_call({xnot_unsubscribe,Ix,Pid}, _From, Ctx) 
  when is_pid(Pid) ->
    Res = remove_subscription(Ctx#co_ctx.xnot_table, Ix, Pid),
    {reply, Res, Ctx};

handle_call({xnot_subscriptions,Pid}, _From, Ctx) 
  when is_pid(Pid) ->
    Subs = subscriptions(Ctx#co_ctx.xnot_table, Pid),
    {reply, Subs, Ctx};

handle_call({xnot_subscribers,Ix}, _From, Ctx)  ->
    Subs = subscribers(Ctx#co_ctx.xnot_table, Ix),
    {reply, Subs, Ctx};

handle_call({xnot_subscribers}, _From, Ctx)  ->
    Subs = subscribers(Ctx#co_ctx.xnot_table),
    {reply, Subs, Ctx};

handle_call({inactive_subscribe, Pid}, _From, 
	    Ctx=#co_ctx {name = _Name, inact_subs = [], inact_timeout = IT})
  when is_pid(Pid), IT =/= infinity ->
    lager:debug("~s: handle_call: first inactive subscribe pid = ~p", 
	 [_Name, Pid]),
    %% Timer must be activated
    Ref = start_timer(IT * 1000, inactive),
    {reply, ok, Ctx#co_ctx {inact_subs = [Pid], inact_timer = Ref}};

handle_call({inactive_subscribe, Pid}, _From, 
	    Ctx=#co_ctx {name = _Name, inact_subs = IS})
  when is_pid(Pid) ->
    lager:debug("~s: handle_call: inactive subscribe pid = ~p", [_Name, Pid]),
    {reply, ok, Ctx#co_ctx {inact_subs = lists:usort([Pid | IS])}};

handle_call({inactive_unsubscribe, Pid}, _From, 
	    Ctx=#co_ctx {name = _Name, inact_subs = [Pid], inact_timer = Ref}) 
  when is_pid(Pid) ->
    %% Timer must be deactivated
    stop_timer(Ref),
    {reply, ok, Ctx#co_ctx {inact_subs = []}};
handle_call({inactive_unsubscribe, Pid}, _From, 
	    Ctx=#co_ctx {name = _Name, inact_subs = IS}) 
  when is_pid(Pid) ->
    {reply, ok, Ctx#co_ctx {inact_subs = IS -- [Pid]}};

handle_call({inactive_subscribers}, _From, Ctx=#co_ctx {inact_subs = IS})  ->
    {reply, IS, Ctx};

handle_call({set_error,Error,Code}, _From, Ctx) ->
    Ctx1 = set_error(Error,Code,Ctx),
    {reply, ok, Ctx1};

handle_call({dump, Qualifier}, _From, Ctx=#co_ctx {name = _Name}) ->
    io:format("   NAME: ~p\n", [_Name]),
    print_hex(nodeid, Ctx#co_ctx.nodeid),
    print_hex(xnodeid, Ctx#co_ctx.xnodeid),
    print_hex(vendor, Ctx#co_ctx.vendor),
    print_hex(serial, Ctx#co_ctx.serial),
    io:format("  STATE: ~s\n", [co_format:state(Ctx#co_ctx.state)]),

    io:format("---- COB TABLE ----\n"),
    ets:foldl(
      fun({CobId, X},_) ->
	      io:format("~11.16. # => ~p\n", [CobId, X])
      end, ok, Ctx#co_ctx.cob_table),
    io:format("---- SUB TABLE ----\n"),
    ets:foldl(
      fun({Pid, IxList},_) ->
	      io:format("~p => \n", [Pid]),
	      lists:foreach(
		fun(Ixs) ->
			case Ixs of
			    {IxStart, IxEnd} ->
				io:format("[~7.16.0#-~7.16.0#]\n", 
					  [IxStart, IxEnd]);
			    Ix ->
				io:format("~7.16.0#\n",[Ix])
			end
		end,
		IxList)
      end, ok, Ctx#co_ctx.sub_table),
    io:format("---- RES TABLE ----\n"),
    ets:foldl(
      fun({Ix, Mod, Pid},_) ->
	      io:format("~7.16.0# reserved by ~p, module ~s\n",[Ix, Pid, Mod])
      end, ok, Ctx#co_ctx.res_table),
    io:format("---- XNOT SUB TABLE ----\n"),
    ets:foldl(
      fun({Pid, IxList},_) ->
	      io:format("~p => \n", [Pid]),
	      lists:foreach(
		fun(Ixs) ->
			case Ixs of
			    {IxStart, IxEnd} ->
				io:format("[~7.16.0#-~7.16.0#]\n", 
					  [IxStart, IxEnd]);
			    Ix ->
				io:format("~7.16.0#\n",[Ix])
			end
		end,
		IxList)
      end, ok, Ctx#co_ctx.xnot_table),
    io:format("---- TPDO CACHE ----\n"),
    ets:foldl(
      fun({{Ix,Si}, Value},_) ->
	      io:format("~7.16.0#:~w = ~p\n",[Ix, Si, Value])
      end, ok, Ctx#co_ctx.tpdo_cache),
    io:format("---- MPDO DISPATCH ----\n"),
    ets:foldl(
      fun({{RIx,RSi,RNid}, {LIx,LSi}},_) ->
	      io:format("~7.16.0#:~w, ~.16.0# = ~7.16.0#:~w\n",
			[RIx, RSi, RNid, LIx, LSi])
      end, ok, Ctx#co_ctx.mpdo_dispatch),
    io:format("---------PROCESSES----------\n"),
    lists:foreach(
      fun(Process) ->
	      case Process of
		  T when is_record(T, tpdo) ->
		      io:format("tpdo process ~p\n",[T]);
		  A when is_record(A, app) ->
		      io:format("app process ~p\n",[A]);
		  S when is_record(S, sdo) ->
		      io:format("sdo process ~p\n",[S])
	      end
      end,
      Ctx#co_ctx.tpdo_list ++ Ctx#co_ctx.app_list ++ Ctx#co_ctx.sdo_list),
    if Qualifier == all ->
	    io:format("---------DICT----------\n"),
	    co_dict:to_fd(Ctx#co_ctx.dict, user),
	    io:format("------------------------\n");
       true ->
	    do_nothing
    end,
    io:format("DEBUG: ~p~n",[Ctx#co_ctx.debug]),
    {reply, ok, Ctx};

handle_call({option, Option}, _From, Ctx=#co_ctx {name = _Name}) ->
    Reply = case Option of
		name -> {Option, Ctx#co_ctx.name};
		nodeid -> {Option, Ctx#co_ctx.nodeid};
		xnodeid -> {Option, Ctx#co_ctx.xnodeid};
		nmt_role -> {Option, Ctx#co_ctx.nmt_role};
		nmt_conf -> {Option, Ctx#co_ctx.nmt_conf};
		supervision -> {Option, Ctx#co_ctx.supervision};
		inact_timeout -> {Option, Ctx#co_ctx.inact_timeout};
		id -> id(Ctx);
		use_serial_as_xnodeid -> {Option, calc_use_serial(Ctx)};
		sdo_timeout ->  {Option, Ctx#co_ctx.sdo#sdo_ctx.timeout};
		blk_timeout -> {Option, Ctx#co_ctx.sdo#sdo_ctx.blk_timeout};
		pst ->  {Option, Ctx#co_ctx.sdo#sdo_ctx.pst};
		max_blksize -> {Option, Ctx#co_ctx.sdo#sdo_ctx.max_blksize};
		use_crc -> {Option, Ctx#co_ctx.sdo#sdo_ctx.use_crc};
		readbufsize -> {Option, Ctx#co_ctx.sdo#sdo_ctx.readbufsize};
		load_ratio -> {Option, Ctx#co_ctx.sdo#sdo_ctx.load_ratio};
		atomic_limit -> {Option, Ctx#co_ctx.sdo#sdo_ctx.atomic_limit};
		time_stamp -> {Option, Ctx#co_ctx.time_stamp_time};
		debug -> {Option, Ctx#co_ctx.debug};
		_Other -> {error, "Unknown option " ++ atom_to_list(Option)}
	    end,
    lager:debug("~s: handle_call: option = ~p, reply = ~w", 
	 [_Name, Option, Reply]),    
    {reply, Reply, Ctx};
handle_call({option, Option, NewValue}, _From, 
	    Ctx=#co_ctx {name = _Name, sdo = SDO}) ->
    lager:debug("~s: handle_call: option = ~p, new value = ~p", 
	 [_Name, Option, NewValue]),    
    Reply = case Option of
		sdo_timeout -> 
		    SDO#sdo_ctx {timeout = NewValue};
		blk_timeout -> 
		    SDO#sdo_ctx {blk_timeout = NewValue};
		pst ->  
		    SDO#sdo_ctx {pst = NewValue};
		max_blksize -> 
		    SDO#sdo_ctx {max_blksize = NewValue};
		use_crc -> 
		    SDO#sdo_ctx {use_crc = NewValue};
		readbufsize -> 
		    SDO#sdo_ctx{readbufsize = NewValue};
		load_ratio -> 
		    SDO#sdo_ctx{load_ratio = NewValue};
		atomic_limit -> 
		    SDO#sdo_ctx{atomic_limit = NewValue};
		inact_timeout -> 
		    Ctx#co_ctx {inact_timeout = NewValue};
		time_stamp -> 
		    Ctx#co_ctx {time_stamp_time = NewValue};

		debug -> co_lib:debug(NewValue),
			 Ctx#co_ctx {debug = NewValue, 
				     sdo = SDO#sdo_ctx {debug = NewValue}};

		name -> OldName = Ctx#co_ctx.name,
			co_proc:unreg({name, OldName}),			
			co_proc:reg({name, NewValue}),
			send_to_apps({name_change, OldName, NewValue}, Ctx),
			Ctx#co_ctx {name = NewValue}; 

		NodeIdChange when
		      NodeIdChange =:= nodeid;
		      NodeIdChange =:= xnodeid;
		      NodeIdChange =:= use_serial_as_xnodeid -> 
		    nodeid_change(NodeIdChange, NewValue, Ctx);

		NmtChange when
		      NmtChange =:= nmt_role;
		      NmtChange =:= nmt_conf;
		      NmtChange =:= supervision ->
		    nmt_change(NmtChange, NewValue, Ctx);
		
		_Other -> {error, "Unknown option " ++ atom_to_list(Option)}
	    end,
    case Reply of
	SdoCtx when is_record(SdoCtx, sdo_ctx) ->
	    {reply, ok, Ctx#co_ctx {sdo = SdoCtx}};
	CoCtx when is_record(CoCtx, co_ctx) ->
	    {reply, ok, CoCtx};
	{error, _Reason} ->
	    {reply, Reply, Ctx}
    end;
handle_call(stop, _From, Ctx) ->
    {stop, normal, ok, Ctx};

handle_call(state, _From, Ctx=#co_ctx {state = State}) ->
    {reply, State, Ctx};

handle_call({state, State}, _From, Ctx) ->
    broadcast_state(State, Ctx),
    {reply, ok, Ctx#co_ctx {state = State}};

handle_call(dict, _From, Ctx=#co_ctx {dict = Dict}) ->
    {reply, Dict, Ctx};

handle_call(_Request, _From, Ctx) ->
    {reply, {error,bad_call}, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% Function: handle_cast(Msg, Context) -> {noreply, Context} |
%%                                      {noreply, Context, Timeout} |
%%                                      {stop, Reason, Context}
%% Description: Handling cast messages
%% @end
%%--------------------------------------------------------------------
handle_cast({object_event, {Ix, _Si}}, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_cast: object_event, index = ~.16B:~p", 
	 [_Name, Ix, _Si]),
    inform_subscribers(Ix, Ctx),
    {noreply, Ctx};

handle_cast({session_over, Pid, _Reason}, 
	    Ctx=#co_ctx {name = _Name, sdo_list = SList}) ->
    lager:debug("~s: handle_cast: session_over, pid ~p, reason ~p", 
	 [_Name, Pid, _Reason]),
    NewSList = 
	case lists:keysearch(Pid, #sdo.pid, SList) of
	    {value,S} -> 
		lists:keyreplace(Pid, #sdo.pid, SList, 
				 S#sdo {state = zombie});
	    false ->  
		lager:debug("~s: handle_cast: session_over, no sdo process found", 
		 [_Name]),
		SList
	end,
    {noreply, Ctx#co_ctx {sdo_list = NewSList}};

handle_cast({pdo_event, CobId}, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_cast: pdo_event, CobId = ~.16B", 
	 [_Name, CobId]),
    case lists:keysearch(CobId, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
	{value, T} ->
	    co_tpdo:transmit(T#tpdo.pid),
	    {noreply,Ctx};
	_ ->
	    lager:debug("~s: handle_cast: pdo_event, no tpdo process found", 
		 [_Name]),
	    {noreply,Ctx}
    end;

handle_cast({dam_mpdo_event, CobId, Destination}, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_cast: dam_mpdo_event, CobId = ~.16B", 
	 [_Name, CobId]),
    case lists:keysearch(CobId, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
	{value, T} ->
	    co_tpdo:transmit(T#tpdo.pid, Destination), %% ??
	    {noreply,Ctx};
	_ ->
	    lager:debug("~s: handle_cast: pdo_event, no tpdo process found", 
		 [_Name]),
	    {noreply,Ctx}
    end;

handle_cast(_Msg, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_cast: unknown message ~p.",  [_Name, _Msg]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% Function: handle_info(Info, Context) -> {noreply, Context} |
%%                                       {noreply, Context, Timeout} |
%%                                       {stop, Reason, Context}
%% Description: Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------
handle_info(Frame, Ctx=#co_ctx {name = _Name}) 
  when is_record(Frame, can_frame) ->
    lager:debug("~s: handle_info: CAN frame received", [_Name]),
    Ctx1 = handle_can(Frame, 
		      Ctx#co_ctx {can_timestamp = co_lib:sec(),
				  inact_sent = false}),
    {noreply, Ctx1};

handle_info({timeout,Ref,sync}, Ctx=#co_ctx {name = _Name}) 
  when Ref =:= Ctx#co_ctx.sync_tmr ->
    %% Send a SYNC frame
    %% FIXME: check that we still are sync producer?
    lager:debug("~s: handle_info: sync timeout received", [_Name]),
    FrameID = ?COBID_TO_CANID(Ctx#co_ctx.sync_id),
    Frame = #can_frame { id=FrameID, len=0, data=(<<>>) },
    can:send(Frame),
    lager:debug("~s: handle_info: Sent sync", [_Name]),
    Ctx1 = Ctx#co_ctx { sync_tmr = start_timer(Ctx#co_ctx.sync_time, sync) },
    {noreply, Ctx1};

handle_info({timeout,Ref,time_stamp}, Ctx=#co_ctx {name = _Name}) 
  when Ref =:= Ctx#co_ctx.time_stamp_tmr ->
    %% FIXME: Check that we still are time stamp producer
    lager:debug("~s: handle_info: time_stamp timeout received", [_Name]),
    FrameID = ?COBID_TO_CANID(Ctx#co_ctx.time_stamp_id),
    Time = time_of_day(),
    Data = co_codec:encode(Time, ?TIME_OF_DAY),
    Size = byte_size(Data),
    Frame = #can_frame { id=FrameID, len=Size, data=Data },
    can:send(Frame),
    lager:debug("~s: handle_info: Sent time stamp ~p", [_Name, Time]),
    Ctx1 = Ctx#co_ctx { time_stamp_tmr = 
			    start_timer(Ctx#co_ctx.time_stamp_time, time_stamp) },
    {noreply, Ctx1};

handle_info({timeout, Ref, inactive}, Ctx=#co_ctx {name = _Name, 
						   inact_subs = [], 
						   inact_timer = Ref}) ->
    lager:debug("~s: handle_info: inactive timeout, no one to send to.", 
	 [_Name]),
    %% No subscribers, timer should not be restarted
    {noreply, Ctx#co_ctx {inact_timer = undefined, inact_sent = false}};

handle_info({timeout, Ref, inactive}, Ctx=#co_ctx {name = _Name, 
						   can_timestamp = CT, 
						   inact_subs = IS, 
						   inact_timeout = IT, 
						   inact_timer = Ref, 
						   inact_sent = false}) 
  when is_integer(IT) ->
    %% Send an inactive event
    lager:debug("~s: handle_info: inactive timeout received.", [_Name]),
    Now = co_lib:sec(),
    if Now - CT >= IT ->
	    lager:debug("~s: handle_info: sending inactive event to ~p.", 
		 [_Name, IS]),
	    lists:foldl(
	      fun(Pid, _Acc) ->
		      Pid ! inactive
	      end, [], IS),
	    NewRef = start_timer(IT, inactive),
	    {noreply, Ctx#co_ctx {inact_sent = true, inact_timer = NewRef}};
       true ->
	    %% Restart timer with the time left minus 1 to be on safe side
	    NewTimeOut = max(IT - (Now - CT)  - 1, 1),
	    lager:debug("~s: handle_info: restart timer with ~p.", 
		 [_Name, NewTimeOut]),
	    NewRef = start_timer(NewTimeOut * 1000, inactive),
	    {noreply, Ctx#co_ctx {inact_timer = NewRef}}
    end;

handle_info({timeout, Ref, inactive}, Ctx=#co_ctx {name = _Name, 
						   inact_timeout = IT, 
						   inact_timer = Ref, 
						   inact_sent = true}) 
  when is_integer(IT) ->
    lager:debug("~s: handle_info: inactive timeout received, restart timer.", 
	 [_Name]),
    NewRef = start_timer(IT * 1000, inactive),
    {noreply, Ctx#co_ctx {
inact_timer = NewRef}};
    
handle_info(do_heartbeat, Ctx=#co_ctx {state = State, 
				       heartbeat_time = HeartBeatTime, 
				       name=_Name}) ->
    lager:debug("~s: handle_info: do_heartbeat ", [_Name]),
    Data = <<0:1, State:7>>,
    send_node_guard(id(Ctx), 1, Data),
    Timer = erlang:send_after(HeartBeatTime, self(), do_heartbeat),
    {noreply, Ctx#co_ctx {heartbeat_timer = Timer}};

handle_info(node_guard_timeout, Ctx=#co_ctx {name=_Name}) ->
    lager:debug("~s: handle_info: node_guard timeout received", [_Name]),
    send_to_apps(lost_nmt_master_contact, Ctx),
    ?ee("Node guard timeout, check NMT master.", []),
    {noreply, Ctx#co_ctx {node_guard_error = true}};

handle_info({rc_reset, Pid}, Ctx=#co_ctx {name = _Name, tpdo_list = TList}) ->
    lager:debug("~s: handle_info: rc_reset for process ~p received",  
		[_Name, Pid]),
    case lists:keysearch(Pid, #tpdo.pid, TList) of
	{value,T} -> 
	    NewT = T#tpdo {rc = 0},
	    lager:debug("~s: handle_info: rc counter cleared",  [_Name]),
	    {noreply, Ctx#co_ctx { tpdo_list = [NewT | TList]--[T]}};
	false -> 
	    lager:debug("~s: handle_info: rc_reset no process found", [_Name]),
	    {noreply, Ctx}
    end;

    
handle_info({'DOWN',Ref,process,_Pid,Reason}, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_info: DOWN for process ~p received", 
	 [_Name, _Pid]),
    Ctx1 = handle_sdo_processes(Ref, Reason, Ctx),
    Ctx2 = handle_app_processes(Ref, Reason, Ctx1),
    Ctx3 = handle_tpdo_processes(Ref, Reason, Ctx2),
    {noreply, Ctx3};

handle_info({'EXIT', Pid, Reason}, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_info: EXIT for process ~p received", 
	 [_Name, Pid]),
    Ctx1 = handle_sdo_processes(Pid, Reason, Ctx),
    Ctx2 = handle_app_processes(Pid, Reason, Ctx1),
    Ctx3 = handle_tpdo_processes(Pid, Reason, Ctx2),

    case Ctx3 of
	Ctx ->
	    %% No 'normal' linked process died, we should termiate ??
	    %% co_nmt ??
	    lager:debug("~s: handle_info: linked process ~p died, reason ~p, "
		 "terminating\n", [_Name, Pid, Reason]),
	    {stop, Reason, Ctx};
	_ChangedCtx ->
	    %% 'Normal' linked process died, ignore
	    {noreply, Ctx3}
    end;

handle_info(_Info, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_info: unknown info ~p received", [_Name, _Info]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% Function: terminate(Reason, Context) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, Ctx=#co_ctx {name = _Name}) ->
    %% If NMT master stop master process
    if Ctx#co_ctx.nmt_role == master ->
	    deactivate_nmt(Ctx);
       true ->
	    do_nothing
    end,
    
    %% Stop all apps ??
    lists:foreach(
      fun(A) ->
	      case A#app.pid of
		  Pid -> 
		      lager:debug("~s: terminate: Killing app with pid = ~p", 
			   [_Name, Pid]),
			  %% Or gen_server:cast(Pid, co_node_terminated) ?? 
		      exit(Pid, co_node_terminated)
	      end
      end,
      Ctx#co_ctx.app_list),

    %% Stop all tpdo-servers ??
    lists:foreach(
      fun(T) ->
	      case T#tpdo.pid of
		  Pid -> 
		      lager:debug("~s: terminate: Killing TPDO with pid = ~p", 
			   [_Name, Pid]),
			  %% Or gen_server:cast(Pid, co_node_terminated) ?? 
		      exit(Pid, co_node_terminated)
	      end
      end,
      Ctx#co_ctx.tpdo_list),

    case co_proc:alive() of
	true -> co_proc:clear();
	false -> do_nothing
    end,
   lager:debug("~s: terminate: cleaned up, exiting", [_Name]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% Func: code_change(OldVsn, Context, Extra) -> {ok, NewContext}
%% Description: Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, Ctx, _Extra) ->
    {ok, Ctx}.

%%--------------------------------------------------------------------
%%% Support functions
%%--------------------------------------------------------------------


%% 
%% Create and initialize dictionary
%%
create_dict() ->
    Dict = co_dict:new(public),
    %% install mandatory default items
    co_dict:add_object(Dict, #dict_object { index=?IX_ERROR_REGISTER,
					    access=?ACCESS_RO,
					    struct=?OBJECT_VAR,
					    type=?UNSIGNED8 },
		       [#dict_entry { index={?IX_ERROR_REGISTER, 0},
				      access=?ACCESS_RO,
				      type=?UNSIGNED8,
				      data=(<<0>>)}]),
    co_dict:add_object(Dict, #dict_object { index=?IX_PREDEFINED_ERROR_FIELD,
					    access=?ACCESS_RO,
					    struct=?OBJECT_ARRAY,
					    type=?UNSIGNED32 },
		       [#dict_entry { index={?IX_PREDEFINED_ERROR_FIELD,0},
				      access=?ACCESS_RW,
				      type=?UNSIGNED8,
				      data=(<<0>>)}]),
    Dict.
    
%%
%% Initialized the default connection set
%% For the extended format we always set the COBID_ENTRY_EXTENDED bit
%% This match for the none extended format
%% We may handle the mixed mode later on....
%%
create_cob_table(ExtNid, ShortNid) ->
    T = ets:new(co_cob_table, [public]),
    add_to_cob_table(T, xnodeid, co_lib:add_xflag(ExtNid)),
    add_to_cob_table(T, nodeid, ShortNid),
    T.

add_to_cob_table(_T, _NidType, undefined) ->
    ok;
add_to_cob_table(T, xnodeid, ExtNid) 
  when ExtNid =/= undefined ->
    XSDORx = ?XCOB_ID(?SDO_RX,ExtNid),
    XSDOTx = ?XCOB_ID(?SDO_TX,ExtNid),
    ets:insert(T, {XSDORx, {sdo_rx, XSDOTx}}),
    ets:insert(T, {XSDOTx, {sdo_tx, XSDORx}}),
    ets:insert(T, {?XCOB_ID(?NMT, 0), nmt}),
    ets:insert(T, {?XCOB_ID(?NODE_GUARD,ExtNid), 
		   {supervision, {xnodeid, ExtNid}}}),
    lager:debug("add_to_cob_table: XNid=~w, XSDORx=~w, XSDOTx=~w", 
	 [ExtNid,XSDORx,XSDOTx]);
add_to_cob_table(T, nodeid, ShortNid) 
  when ShortNid =/= undefined->
    lager:debug("add_to_cob_table: ShortNid=~w", [ShortNid]),
    SDORx = ?COB_ID(?SDO_RX,ShortNid),
    SDOTx = ?COB_ID(?SDO_TX,ShortNid),
    ets:insert(T, {SDORx, {sdo_rx, SDOTx}}),
    ets:insert(T, {SDOTx, {sdo_tx, SDORx}}),
    ets:insert(T, {?COB_ID(?NMT, 0), nmt}),
    ets:insert(T, {?COB_ID(?NODE_GUARD,ShortNid), 
		   {supervision, {nodeid, ShortNid}}}),
    lager:debug("add_to_cob_table: SDORx=~w, SDOTx=~w", [SDORx,SDOTx]).


delete_from_cob_table(_T, _NidType, undefined) ->
    ok;
delete_from_cob_table(T, xnodeid, Nid)
  when Nid =/= undefined ->
    ExtNid = co_lib:add_xflag(Nid),
    XSDORx = ?XCOB_ID(?SDO_RX,ExtNid),
    XSDOTx = ?XCOB_ID(?SDO_TX,ExtNid),
    ets:delete(T, XSDORx),
    ets:delete(T, XSDOTx),
    ets:delete(T, ?XCOB_ID(?NMT,0)),
    ets:delete(T, ?XCOB_ID(?NODE_GUARD,ExtNid)),
    lager:debug("delete_from_cob_table: XNid=~w, XSDORx=~w, XSDOTx=~w", 
	 [ExtNid,XSDORx,XSDOTx]);
delete_from_cob_table(T, nodeid, ShortNid)
  when ShortNid =/= undefined->
    SDORx = ?COB_ID(?SDO_RX,ShortNid),
    SDOTx = ?COB_ID(?SDO_TX,ShortNid),
    ets:delete(T, SDORx),
    ets:delete(T, SDOTx),
    ets:delete(T, ?COB_ID(?NMT,0)),
    ets:delete(T, ?COB_ID(?NODE_GUARD,ShortNid)),
   lager:debug("delete_from_cob_table: ShortNid=~w, SDORx=~w, SDOTx=~w", 
	 [ShortNid,SDORx,SDOTx]).


nodeid_change(xnodeid, NewXNid, Ctx=#co_ctx {xnodeid = NewXNid}) ->
    %% No change
    Ctx;
nodeid_change(xnodeid, undefined, _Ctx=#co_ctx {nodeid = undefined}) -> 
    {error, "Not possible to remove last nodeid"};
nodeid_change(xnodeid, NewNid, Ctx=#co_ctx {xnodeid = OldNid, nodeid = SNid}) ->
    execute_change(xnodeid, NewNid, OldNid, Ctx),
    if SNid == undefined ->
	    send_bootup({xnodeid, NewNid});
       true ->
	    %% Using SNid for supervision
	    do_nothing
    end,
    Ctx#co_ctx {xnodeid = NewNid};
nodeid_change(nodeid, NewNid, Ctx=#co_ctx {nodeid = NewNid}) ->
    %% No change
    Ctx;
nodeid_change(nodeid, undefined, _Ctx=#co_ctx {xnodeid = undefined}) -> 
    {error, "Not possible to remove last nodeid"};
nodeid_change(nodeid, 0, _Ctx) ->
    {error, "NodeId 0 is reserved for the CANopen manager co_mgr."};
nodeid_change(nodeid, NewNid, Ctx=#co_ctx {nodeid = OldNid}) ->
    execute_change(nodeid, NewNid, OldNid, Ctx),
    send_bootup({nodeid, NewNid}),
    Ctx#co_ctx {nodeid = NewNid};
nodeid_change(use_serial_as_xnodeid, true, Ctx=#co_ctx {serial = Serial}) ->
    NewXNid = co_lib:serial_to_xnodeid(Serial),
    nodeid_change(xnodeid, NewXNid, Ctx);
nodeid_change(use_serial_as_xnodeid, false, Ctx) ->
    case  calc_use_serial(Ctx) of
	true ->
	    %% Serial was used as extended node id
	    nodeid_change(xnodeid, undefined, Ctx);
	false ->
	    %% Serial was NOT used as nodeid so flag was already false
	    Ctx
    end.

%% New nmt configuration
nmt_change(nmt_conf, NewValue, Ctx) ->
    case co_nmt:load(NewValue) of
	ok ->
	    Ctx#co_ctx {nmt_conf = NewValue};
	Error ->
	    Error
    end;
%% ROLE
%% No change
nmt_change(nmt_role, NewRole, Ctx=#co_ctx {nmt_role = NewRole}) ->
    Ctx;
%% autonomous to master
nmt_change(nmt_role, master, Ctx=#co_ctx {nmt_role = autonomous}) ->
    activate_nmt(Ctx#co_ctx {nmt_role = master});
%% slave to master
nmt_change(nmt_role, master, 
	   Ctx=#co_ctx {nmt_role = slave, supervision = node_guard}) ->
    activate_nmt(deactivate_node_guard(Ctx#co_ctx {nmt_role = master}));
nmt_change(nmt_role, master, 
	   Ctx=#co_ctx {nmt_role = slave, supervision = heartbeat}) ->
    activate_nmt(deactivate_heartbeat(Ctx#co_ctx {nmt_role = master}));
nmt_change(nmt_role, master, 
	   Ctx=#co_ctx {nmt_role = slave, supervision = none}) ->
    activate_nmt(Ctx#co_ctx {nmt_role = master});
%% master to slave
nmt_change(nmt_role, slave, 
	   Ctx=#co_ctx {nmt_role = master, supervision = node_guard}) ->
    activate_node_guard(deactivate_nmt(Ctx#co_ctx {nmt_role = slave}));
nmt_change(nmt_role, slave, 
	   Ctx=#co_ctx {nmt_role = master, supervision = heartbeat}) ->
    activate_heartbeat(deactivate_nmt(Ctx#co_ctx {nmt_role = slave}));
nmt_change(nmt_role, slave, 
	   Ctx=#co_ctx {nmt_role = master, supervision = none}) ->
    deactivate_nmt(Ctx#co_ctx {nmt_role = slave});
%% master to autonomous
nmt_change(nmt_role, autonomous, Ctx=#co_ctx {nmt_role = master}) ->
    deactivate_nmt(Ctx#co_ctx {nmt_role = autonomous});
%% SUPERVISION
%%  No change
nmt_change(supervision, NewValue, Ctx=#co_ctx {supervision = NewValue}) ->
    Ctx;
%% to heartbeart when slave
nmt_change(supervision, heartbeat, 
	   Ctx=#co_ctx {supervision = none, nmt_role = slave}) ->
    activate_heartbeat(Ctx#co_ctx {supervision = heartbeat});
nmt_change(supervision, heartbeat, 
	   Ctx=#co_ctx {supervision = node_guard, nmt_role = slave}) ->
    activate_heartbeat(deactivate_node_guard(Ctx#co_ctx {supervision = heartbeat}));
%% supervision change when master handled by master ??
nmt_change(supervision, NewValue, 
	   Ctx=#co_ctx {supervision = _OldValue, nmt_role = master}) ->		
    gen_server:cast(co_nmt_master, {supervision, NewValue}),
    Ctx#co_ctx {supervision = NewValue}; 
%% supervision change when autonomous ignored ??
nmt_change(supervision, NewValue, Ctx=#co_ctx {nmt_role = autonomous}) ->
    Ctx#co_ctx {supervision = NewValue};
%% to node_guard when slave
nmt_change(supervision, node_guard, 
	   Ctx=#co_ctx {supervision = none, nmt_role = slave}) ->	
    activate_node_guard(Ctx#co_ctx {supervision = node_guard});
nmt_change(supervision, node_guard, 
	   Ctx=#co_ctx {supervision = heartbeat, nmt_role = slave}) ->	
    activate_node_guard(deactivate_heartbeat(Ctx#co_ctx {supervision = node_guard}));
%% to none when slave
nmt_change(supervision, none, 
	   Ctx=#co_ctx {supervision = node_guard, nmt_role = slave}) ->
    deactivate_node_guard(Ctx#co_ctx {supervision = none});
nmt_change(supervision, none, 
	   Ctx=#co_ctx {supervision = heartbeat, nmt_role = slave}) ->
    deactivate_heartbeat(Ctx#co_ctx {supervision = none}).


execute_change(NidType, NewNid, OldNid, Ctx=#co_ctx {cob_table = T}) ->  
    lager:debug("execute_change: NidType = ~p, OldNid = ~p, NewNid = ~p", 
	 [NidType, OldNid, NewNid]),
    delete_from_cob_table(T, NidType, OldNid),
    co_proc:unreg({NidType, OldNid}),
    add_to_cob_table(T, NidType, NewNid),
    reg({NidType, NewNid}),
    send_to_apps({nodeid_change, NidType, OldNid, NewNid}, Ctx),
    send_to_tpdos({nodeid_change, NidType, OldNid, NewNid}, Ctx).
    
  
calc_use_serial(_Ctx=#co_ctx {xnodeid = OldXNid, serial = Serial}) ->
    case co_lib:serial_to_xnodeid(Serial) of
	OldXNid ->
	    %% Serial was used as extended node id
	    true;
	_Other ->
	    %% Serial was NOT used as nodeid so flag was already false
	    false
    end.
   
%%
%% Create subscription table
%%
create_sub_table() ->
    T = ets:new(co_sub_table, [public,ordered_set]),
    add_subscription(T, ?IX_COB_ID_SYNC_MESSAGE, self()),
    add_subscription(T, ?IX_COM_CYCLE_PERIOD, self()),
    add_subscription(T, ?IX_COB_ID_TIME_STAMP, self()),
    add_subscription(T, ?IX_COB_ID_EMERGENCY, self()),
    add_subscription(T, ?IX_SDO_SERVER_FIRST,?IX_SDO_SERVER_LAST, self()),
    add_subscription(T, ?IX_SDO_CLIENT_FIRST,?IX_SDO_CLIENT_LAST, self()),
    add_subscription(T, ?IX_RPDO_PARAM_FIRST, ?IX_RPDO_PARAM_LAST, self()),
    add_subscription(T, ?IX_TPDO_PARAM_FIRST, ?IX_TPDO_PARAM_LAST, self()),
    add_subscription(T, ?IX_TPDO_MAPPING_FIRST, ?IX_TPDO_MAPPING_LAST, self()),
    T.
    
%%
%% Load a dictionary
%% 
%%
%% Load dictionary from file
%% FIXME: map
%%    IX_COB_ID_SYNC_MESSAGE  => cob_table
%%    IX_COB_ID_TIME_STAMP    => cob_table
%%    IX_COB_ID_EMERGENCY     => cob_table
%%    IX_SDO_SERVER_FIRST - IX_SDO_SERVER_LAST =>  cob_table
%%    IX_SDO_CLIENT_FIRST - IX_SDO_CLIENT_LAST =>  cob_table
%%    IX_RPDO_PARAM_FIRST - IX_RPDO_PARAM_LAST =>  cob_table
%% 
load_dict_init(none, Ctx) ->
    {ok, Ctx};
load_dict_init(default, Ctx) ->
    File = filename:join(code:priv_dir(canopen), ?DEFAULT_DICT),
    case filelib:is_regular(File) of
	true -> load_dict_internal(File, Ctx);
	false -> {error, no_dict_available}
    end;
load_dict_init(saved, Ctx=#co_ctx {serial = Serial}) ->
    File = filename:join(code:priv_dir(canopen), 
			 co_lib:serial_to_string(Serial) ++ ?LAST_SAVED_DICT),
    case filelib:is_regular(File) of
	true -> 
	    load_dict_internal(File, Ctx);
	false -> 
	    ?ei("No saved dictionary found, using default", []),
	    load_dict_init(default, Ctx)
    end;
load_dict_init(File, Ctx) when is_list(File) ->
    load_dict_internal(filename:join(code:priv_dir(canopen), File), Ctx); 
load_dict_init(File, Ctx) when is_atom(File) ->
    load_dict_internal(filename:join(code:priv_dir(canopen), 
				     atom_to_list(File)), 
		       Ctx). 

load_dict_internal(File, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: load_dict_internal: Loading file = ~p", [_Name, File]),
    case filelib:is_regular(File) of
	true -> load_dict_internal1(File, Ctx);
	false -> {error, no_dict_available}
    end.

    
load_dict_internal1(File, Ctx=#co_ctx {dict = Dict, name = _Name}) ->
    try co_file:load(File) of
	{ok,Os} ->
	    lager:debug("~s: load_dict_internal1: Loaded file = ~p", [_Name, File]),

	    %% Install all new/changed objects
	    ChangedIxs =
		foldl(
		  fun({Obj,Es}, OIxs) ->
			  ChangedEIxs = 
			      foldl(fun(E, EIxs) -> 
					    I = E#dict_entry.index,
					    ChangedI = case ets:lookup(Dict, I) of
							   [E] -> []; %% No change
							   [_E] -> [I]; %% Changed Entry
							   [] -> [I] %% New Entry
						       end,
					    ets:insert(Dict, E),
					    EIxs ++ ChangedI
				    end, [], Es),
			  ets:insert(Dict, Obj),
			  %% Only want to know object index of changed entry
			  {Ixs, _SubIxs} = lists:unzip(ChangedEIxs),
			  OIxs ++ lists:usort(Ixs)
		  end, [], Os),

	    %% What about removed entries ???

	    %% Now take action if needed
	    lager:debug("~s: load_dict_internal: changed entries ~p", 
		 [_Name, ChangedIxs]),
	    Ctx1 = 
		foldl(fun(I, Ctx0) ->
			      handle_notify(I, Ctx0)
		      end, Ctx, ChangedIxs),

	    {ok, Ctx1};
	Error ->
	    lager:debug("~s: load_dict_internal: Failed loading file, error = ~p", 
		 [_Name, Error]),
	    Error
    catch
	error:Reason ->
	    lager:debug("~s: load_dict_internal: Failed loading file, reason = ~p", 
		 [_Name, Reason]),

	    {error, Reason}
    end.

%%
%% Update dictionary
%% Only valid for 'local' objects
%%
set_dict_object({Object,Es}, Ctx=#co_ctx {dict = Dict}) 
  when is_record(Object, dict_object) ->
    case co_dict:add_object(Dict, Object, Es) of
	ok ->
	    I = Object#dict_object.index,
	    handle_notify(I, Ctx);
	Error ->
	    Error
    end.

set_dict_entry(Entry, Ctx=#co_ctx {dict = Dict}) 
  when is_record(Entry, dict_entry) ->
    case co_dict:add_entry(Dict, Entry) of
	ok ->
	    {I,_} = Entry#dict_entry.index,
	    handle_notify(I, Ctx);
	Error ->
	    Error
    end.

set_value(Ix,Si,Value,Ctx) ->
    set(set_value, Ix,Si, Value, Ctx).

set_data(Ix,Si,Data,Ctx) ->
    set(set_data, Ix,Si, Data, Ctx).

direct_set_value(Ix,Si,Value,Ctx) ->
    set(direct_set_value, Ix, Si, Value, Ctx).

direct_set_data(Ix,Si,Data,Ctx) ->
    set(direct_set_data, Ix, Si, Data, Ctx).

set(Func, Ix,Si,ValueOrData,Ctx) ->
    try co_dict:Func(Ctx#co_ctx.dict, Ix,Si,ValueOrData) of
	ok -> {ok, handle_notify(Ix, Ctx)};
	Error -> {Error, Ctx}
    catch
	error:Reason -> {{error,Reason}, Ctx}
    end.



%%
%% Handle can messages
%%
handle_can(Frame, Ctx=#co_ctx {name = _Name}) 
  when ?is_can_frame_rtr(Frame) ->
    CobId = ?CANID_TO_COBID(Frame#can_frame.id),
    lager:debug("~s: handle_can: (rtr) CobId=~8.16.0B", [_Name, CobId]),
    case lookup_cobid(CobId, Ctx) of
	nmt  -> Ctx;
	{supervision, NodeId} -> handle_node_guard(Frame, NodeId, Ctx);
	undefined ->
	    case lists:keysearch(CobId, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
		{value, T} ->
		    co_tpdo:rtr(T#tpdo.pid),
		    Ctx;
		_ -> 
		    lager:debug("~s: handle_can: frame ~w, cobid undefined not "
			 "handled", [_Name, Frame]),
		    Ctx
	    end;
	_Other ->
	    lager:debug("~s: handle_can: frame ~w, cobid ~w not handled", 
		 [_Name, Frame, _Other]),
	    Ctx
    end;
handle_can(Frame, Ctx=#co_ctx {state = _State, name = _Name}) ->
    CobId = ?CANID_TO_COBID(Frame#can_frame.id),
    lager:debug("~s: handle_can: CobId=~8.16.0B", [_Name, CobId]),
    case lookup_cobid(CobId, Ctx) of
	nmt        -> handle_nmt(Frame, Ctx);
	lss        -> handle_lss(Frame, Ctx);
	sync       -> handle_sync(Frame, Ctx);
	emcy       -> handle_emcy(Frame, Ctx);
	time_stamp -> handle_time_stamp(Frame, Ctx);
	{supervision, NodeId} -> handle_supervision(Frame, NodeId, Ctx);
	{rpdo,Offset} -> handle_rpdo(Frame, Offset, CobId, Ctx);
	{sdo_tx,Rx} -> handle_sdo_tx(Frame, CobId, Rx, Ctx);
	{sdo_rx,Tx} -> handle_sdo_rx(Frame, CobId, Tx, Ctx);
	{sdo_rx, not_receiver, _Tx} -> 
	    lager:debug("~s: handle_can: sdo_rx frame ~w to ~.16# ignored", 
		 [_Name, Frame, _Tx]),
	    Ctx; %% ignored
	_AssumedMpdo -> handle_mpdo(Frame, CobId, Ctx) 
    end.


%%
%% NMT 
%%
handle_nmt(M, Ctx=#co_ctx {nmt_role = autonomous, name=_Name}) ->
    <<_NodeId,_Cs,_/binary>> = M#can_frame.data,
    lager:debug(
      "~s: handle_nmt: node is autonomous, nmt command ~p to ~p ignored. ",
      [_Name, co_lib:decode_nmt_command(_Cs), _NodeId]),
    Ctx;
handle_nmt(M, Ctx=#co_ctx {nodeid=undefined, nmt_role = slave, name=_Name}) ->
    <<_NodeId,_Cs,_/binary>> = M#can_frame.data,
    lager:debug("~s: handle_nmt: node has no short id, no nmt possible. "
	 "Command ~p is for node ~p",
	 [_Name, co_lib:decode_nmt_command(_Cs), _NodeId]),
    Ctx;
handle_nmt(M, Ctx=#co_ctx {nodeid=SNodeId, nmt_role = slave, name=_Name}) 
  when M#can_frame.len >= 2 andalso SNodeId =/= undefined ->
    <<Cs,NodeId,_/binary>> = M#can_frame.data,
    lager:debug("~s: handle_nmt: slave ~p, command ~p", 
	 [_Name, NodeId, co_lib:decode_nmt_command(Cs)]),
    if NodeId =:= 0; 
       NodeId =:= SNodeId ->
	    case Cs of
		?NMT_RESET_NODE ->
		    reset_application(Ctx);
		?NMT_RESET_COMMUNICATION ->
		    reset_communication(Ctx);
		?NMT_ENTER_PRE_OPERATIONAL ->
		    broadcast_state(?PreOperational, Ctx),
		    Ctx#co_ctx { state = ?PreOperational };
		?NMT_START_REMOTE_NODE ->
		    broadcast_state(?Operational, Ctx),
		    Ctx#co_ctx { state = ?Operational };
		?NMT_STOP_REMOTE_NODE ->
		    broadcast_state(?Stopped, Ctx),
		    Ctx#co_ctx { state = ?Stopped };
		_ ->
		    lager:debug("~s: handle_nmt: unknown cs=~w", 
			 [_Name, Cs]),
		    Ctx
	    end;
       true ->
	    %% not for me
	    Ctx
    end;
handle_nmt(M, Ctx=#co_ctx {nmt_role = master, name = _Name}) ->
    <<_Cs,_NodeId,_/binary>> = M#can_frame.data,
    lager:debug("~s: handle_nmt: node is nmt master, no nmt command possible. "
	 "Command ~p is for node ~p",
	 [_Name, co_lib:decode_nmt_command(_Cs), _NodeId]),
    Ctx.
    

handle_node_guard(Frame, NodeId = {TypeOfNid, _Nid},
		  Ctx=#co_ctx {state = State, 
			       nmt_role = slave, supervision = node_guard,
			       toggle = Toggle, xtoggle = XToggle,
			       node_guard_timer = Timer, node_life_time = NLT,
			       node_guard_error = NgError, name=_Name}) 
  when ?is_can_frame_rtr(Frame) ->
    lager:debug("~s: handle_node_guard: node ~p request ~w, now ~p", 
	 [_Name,NodeId,Frame, os:timestamp()]),
    %% Reset NMT master supervision timer
    if Timer =/= undefined ->
	    erlang:cancel_timer(Timer);
       true ->
	    do_nothing
    end,
    %% If NMT supervision has been down resend bootup ?? Toggle ??
    if NgError ->
	    send_to_apps(found_nmt_master_contact, Ctx),
	    send_bootup(id(Ctx));
       true ->
	    do_nothing
    end,
    %% Reply
    lager:debug("~s: handle_node_guard: toggle ~p, xtoggle ~p", 
		[_Name,Toggle,XToggle]),
    {Data, NewToggle, NewXToggle} = 
	if TypeOfNid == nodeid ->
		{<<Toggle:1, State:7>>, 1 - Toggle, XToggle};
	   TypeOfNid == xnodeid ->
		{<<XToggle:1, State:7>>, Toggle, 1 - XToggle}
	end,
    send_node_guard(NodeId, 1, Data),
    %% Restart NMT master supervision
    NewTimer = if NLT =/= 0 ->
		       erlang:send_after(NLT, self(), node_guard_timeout);
		  true ->
		       undefined
	       end,
    Ctx#co_ctx {toggle = NewToggle, xtoggle = NewXToggle,
		node_guard_error = false, node_guard_timer = NewTimer};

handle_node_guard(_Frame, _NodeId, 
		  Ctx=#co_ctx {supervision = Super, name=_Name}) 
  when Super == none orelse Super == hearbeat ->
    lager:debug("~s: handle_node_guard: node has supervision ~p, "
	 "node_guard request ~w  ignored. ",[_Name, Super, _Frame]),
    Ctx;
handle_node_guard(_Frame, _NodeId, 
		  Ctx=#co_ctx {nmt_role = autonomous, name=_Name}) ->
    lager:debug("~s: handle_node_guard: node is autonomous, "
	 "node_guard request ~w  ignored. ",[_Name, _Frame]),
    Ctx;
handle_node_guard(Frame, _NodeId, 
		  Ctx=#co_ctx {nmt_role = master, name=_Name}) 
  when ?is_can_frame_rtr(Frame) ->
    lager:debug("~s: handle_node_guard: request ~w", [_Name,Frame]),
    %% Node is nmt master and should NOT receive node_guard request
    ?ee("Illegal NMT confiuration, receiving node_guard "
        " request even though being NMT master", []),
    Ctx.

handle_supervision(Frame, NodeId, Ctx=#co_ctx {nmt_role = master, name = _Name}) 
  when Frame#can_frame.len >= 1 ->
    lager:debug("~s: handle_supervision: reply ~w", [_Name,Frame]),
    gen_server:cast(co_nmt_master, {supervision_frame, NodeId, Frame}),
    Ctx;
handle_supervision(_Frame, _NodeId, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_supervision: reply ~w from ~p", 
		[_Name, _Frame, _NodeId]),
    lager:debug("~s: not nmt master, ignored", [_Name]),
    Ctx.

%%
%% LSS
%% 
handle_lss(_M, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_lss: ~w", [_Name,_M]),
    Ctx.

%%
%% SYNC
%%
handle_sync(_Frame, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_sync: ~w", [_Name,_Frame]),
    lists:foreach(
      fun(T) -> co_tpdo:sync(T#tpdo.pid) end, Ctx#co_ctx.tpdo_list),
    Ctx.

%%
%% TIME STAMP - update local time offset
%%
handle_time_stamp(Frame, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_timestamp: ~w", [_Name,Frame]),
    try co_codec:decode(Frame#can_frame.data, ?TIME_OF_DAY) of
	T when is_record(T, time_of_day) ->
	    lager:debug("~s: Got timestamp: ~p", [_Name, T]),
	    set_time_of_day(T),
	    Ctx;
	_ ->
	    Ctx
    catch
	error:_ ->
	    Ctx
    end.

%%
%% EMERGENCY - this is the consumer side detecting emergency
%%
handle_emcy(_Frame, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_emcy: ~w", [_Name,_Frame]),
    Ctx.

%%
%% Recive PDO - unpack into the dictionary
%%
handle_rpdo(Frame, Offset, _CobId, 
	    Ctx=#co_ctx {state = ?Operational, name = _Name}) ->
    lager:debug("~s: handle_rpdo: offset = ~p, frame = ~w", 
	 [_Name, Offset, Frame]),
    rpdo_unpack(?IX_RPDO_MAPPING_FIRST + Offset, Frame#can_frame.data, Ctx);
handle_rpdo(_Frame, _Offset, _CobId, 
	    Ctx=#co_ctx {state = State, name = _Name}) ->
    lager:debug("~s: handle_rpdo: offset = ~p, frame = ~w, state ~p", 
	 [_Name, _Offset, _Frame, State]),
    ?ew("Received pdo in state ~p, ignoring", [State]),
    Ctx.

%% CLIENT side:
%% SDO tx - here we receive can_node response
%% FIXME: conditional compile this
%%
handle_sdo_tx(Frame, Tx, Rx, Ctx=#co_ctx {state = State, name = _Name}) 
  when State == ?Operational;
       State == ?PreOperational ->
    lager:debug("~s: handle_sdo_tx: src=~p, ~s",
	      [_Name, Tx,
	       co_format:format_sdo(co_sdo:decode_tx(Frame#can_frame.data))]),
    ID = {Tx,Rx},
    lager:debug("~s: handle_sdo_tx: session id=~p", [_Name, ID]),
    Sessions = Ctx#co_ctx.sdo_list,
    case lists:keysearch(ID,#sdo.id,Sessions) of
	{value, S=#sdo {state = active}} ->
	    gen_fsm:send_event(S#sdo.pid, Frame),
	    Ctx;
	_Other ->
	    %% state = zombie;
	    %% false
	    lager:debug("~s: handle_sdo_tx: session not found", [_Name]),
	    %% no such session active
	    Ctx
    end;
handle_sdo_tx(_Frame, _Tx, _Rx, 
	      Ctx=#co_ctx {state = State, name = _Name}) ->
    lager:debug("~s: handle_sdo_tx: src=~p, ~s",
	 [_Name, _Tx,
	  co_format:format_sdo(co_sdo:decode_tx(_Frame#can_frame.data))]),
    ?ew("Received sdo in state ~p, ignoring", [State]),
    Ctx.


%% SERVER side
%% SDO rx - here we receive client requests
%% FIXME: conditional compile this
%%
handle_sdo_rx(Frame, Rx, Tx, Ctx=#co_ctx {state = State, name = _Name})
  when State == ?Operational;
       State == ?PreOperational ->
    lager:debug("~s: handle_sdo_rx: ~s", 
	      [_Name,co_format:format_sdo(co_sdo:decode_rx(Frame#can_frame.data))]),
    ID = {Rx,Tx},
    Sessions = Ctx#co_ctx.sdo_list,
    case lists:keysearch(ID,#sdo.id,Sessions) of
	{value, S=#sdo {state = active}} ->
	    lager:debug("~s: handle_sdo_rx: Frame sent to old process ~p", 
		 [_Name,S#sdo.pid]),
	    gen_fsm:send_event(S#sdo.pid, Frame),
	    Ctx;
	_Other -> 
	    %% state = zombie;
	    %% false
	    %% FIXME: handle expedited and spurios frames here
	    %% like late aborts etc here !!!
	    case co_sdo_srv_fsm:start(Ctx#co_ctx.sdo,Rx,Tx) of
		{error, Reason} ->
		   ?ew("~p: unable to start co_sdo_srv_fsm: ~p",
		       [_Name, Reason]),
		    Ctx;
		{ok,Pid} ->
		    Mon = erlang:monitor(process, Pid),
		    %% sys:trace(Pid, true),
		    lager:debug("~s: handle_sdo_rx: Frame sent to new process ~p", 
			 [_Name,Pid]),		    
		    gen_fsm:send_event(Pid, Frame),
		    S = #sdo { id=ID, pid=Pid, mon=Mon },
		    Ctx#co_ctx { sdo_list = [S|Sessions]}
	    end
    end;
handle_sdo_rx(_Frame, _Rx, _Tx, Ctx=#co_ctx {state = State, name = _Name}) ->
    lager:debug("~s: handle_sdo_rx: ~s", 
	      [_Name,co_format:format_sdo(
		       co_sdo:decode_rx(_Frame#can_frame.data))]),
    ?ew("Received sdo in state ~p, ignoring", [State]),
    Ctx.

handle_mgr_action(Action,Mode,{TypeOfNode,NodeId},Ix,Si,Term,TOut, From, 
	    Ctx=#co_ctx {name = _Name, sdo_list = Sessions, sdo = SdoCtx}) ->
    Nid = case TypeOfNode of
	      nodeid -> NodeId;
	      xnodeid -> co_lib:add_xflag(NodeId)
	  end,
    lager:debug("~s: ~p: node ~.16.0#.", [_Name, Action, Nid]),
    case lookup_sdo_server(Nid,Ctx) of
	ID={Tx,Rx} ->
	    lager:debug("~s: ~p: ID = {~.16.0#, ~.16.0#}", [_Name,Action,Tx,Rx]),
	    case lists:keyfind(Nid, #sdo.dest_node, Sessions) of
		_S=#sdo {state = active} ->
		    lager:debug("~s: ~p: Session already in progress to ~.16.0#",
			 [_Name, Action, Nid]),
		    {reply, {error, session_already_in_progress}, Ctx};
		_Other ->
		    %% state = zombie or
		    %% false
		    %% OK to start new session
		    case co_sdo_cli_fsm:Action(
			   SdoCtx#sdo_ctx {timeout =
					       %% If remote timeout given use it
					       %% otherwise use default
					       if TOut =/= default -> TOut;
						  true -> SdoCtx#sdo_ctx.timeout
					       end},
					       Mode,From,Tx,Rx,Ix,Si,Term) of
			{error, Reason} ->
			    lager:debug([node],
					"~s: ~p: unable to start co_sdo_cli_fsm, "
					"reason ~p",  [_Name, Action, Reason]),
			    {reply, Reason, Ctx};
			{ok, Pid} ->
			    Mon = erlang:monitor(process, Pid),
			    %% sys:trace(Pid, true),
			    S = #sdo {dest_node = Nid, id=ID, pid=Pid, mon=Mon},
			    lager:debug("~s: ~p: added session, "
					"ID={~.16.0#, ~.16.0#}",
					[_Name, Action, Tx, Rx]),
			    {noreply, Ctx#co_ctx { sdo_list = [S|Sessions]}}
		    end
	    end;
	undefined ->
	    lager:debug("~s: ~p: No sdo server found for node ~.16.0#.", 
		 [_Name, Action, Nid]),
	    {reply, {error, badarg}, Ctx}
    end.


handle_mpdo(Frame, CobId, Ctx=#co_ctx {state = ?Operational, name = _Name}) ->
    case Frame#can_frame.data of
	%% Test if MPDO
	<<F:1, Addr:7, Ix:16/little, Si:8, Data:4/binary>> ->
	    case {F, Addr} of
		{1, 0} ->
		    %% DAM-MPDO, destination is a group
		    handle_dam_mpdo(CobId, {Ix, Si}, Data, Ctx),
		    extended_notify(Ix, Frame, Ctx);
		{1, Nid} when Nid == Ctx#co_ctx.nodeid ->
		    %% DAM-MPDO, destination is this node
		    handle_dam_mpdo(CobId, {Ix, Si}, Data, Ctx),
		    extended_notify(Ix, Frame, Ctx);
		{1, _OtherNid} ->
		    %% DAM-MPDO, destination is some other node
		    lager:debug("~s: handle_mpdo: DAM-MPDO: destination is "
			 "other node = ~.16.0#", [_Name, _OtherNid]),
		    Ctx;
		{0, 0} ->
		    %% Reserved
		    lager:debug("~s: handle_mpdo: SAM-MPDO: Addr = 0, reserved "
			 "Frame = ~w", [_Name, Frame]),
		    Ctx;
		{0, SourceNid} ->
		    handle_sam_mpdo(SourceNid, {Ix, Si}, Data, Ctx)
	    end;
	_Other ->
	    lager:debug("~s: handle_mpdo: frame not handled: Frame = ~w", 
		 [_Name, Frame]),
	    Ctx
    end;
handle_mpdo(_Frame, _CobId, Ctx=#co_ctx {state = State, name = _Name}) ->
    ?ew("Received pdo in state ~p, ignoring", [State]),
    Ctx.

handle_sam_mpdo(SourceNid, {SourceIx, SourceSi}, Data,
		Ctx=#co_ctx {mpdo_dispatch = MpdoDispatch, name = _Name}) ->
    lager:debug("~s: handle_sam_mpdo: Index = ~.16#:~w, Nid = ~.16.0#, Data = ~w", 
	 [_Name,SourceIx,SourceSi,SourceNid,Data]),
    case ets:lookup(MpdoDispatch, {SourceIx, SourceSi, SourceNid}) of
	[{{SourceIx, SourceSi, SourceNid}, LocalIndex = {_LocalIx, _LocalSi}}] ->
	    lager:debug("~s: handle_sam_mpdo: Found Index = ~.16#:~w, updating", 
		 [_Name,_LocalIx,_LocalSi]),
	    rpdo_value(LocalIndex,Data,Ctx);
	[] ->
	    Ctx;
	_Other ->
	    lager:debug("~s: handle_sam_mpdo: Found other ~p ", [_Name, _Other]),
	    Ctx
    end.

%%
%% DAM-MPDO
%%
handle_dam_mpdo(_CobId, Index = {_Ix, _Si}, Data, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_dam_mpdo: Index = ~.16#:~w", [_Name,_Ix,_Si]),
    %% Enough ??
    rpdo_value(Index,Data,Ctx).

extended_notify(Ix, Frame, 
		Ctx=#co_ctx {xnot_table = XNotTable, name = _Name}) ->
    case lists:usort(subscribers(XNotTable, Ix)) of
	[] ->
	    lager:debug("~s: extended_notify: No xnot subscribers for index ~.16#", 
		 [_Name, Ix]);
	PidList ->
	    lists:foreach(
	      fun(Pid) ->
		      case Pid of
			  dead ->
			      %% Warning ??
			      lager:debug(
				"~s: extended_notify: Process subscribing "
				"to index ~.16# is dead", [_Name, Ix]);
			  P when is_pid(P)->
			      lager:debug(
				"~s: extended_notify: Process ~p subscribes "
				"to index ~.16#", [_Name, Pid, Ix]),
			      gen_server:cast(Pid, {extended_notify, Ix, Frame})
		      end
	      end, PidList)
    end,
    Ctx.
    

%%
%% Handle terminated processes
%%
handle_sdo_processes(Pid, Reason, Ctx=#co_ctx {sdo_list = SList}) 
  when is_pid(Pid) ->
    case lists:keysearch(Pid, #sdo.pid, SList) of
	{value,S} -> handle_sdo_process(S, Reason, Ctx);
	false ->  Ctx
    end;
handle_sdo_processes(Ref, Reason, Ctx=#co_ctx {sdo_list = SList}) ->
    case lists:keysearch(Ref, #sdo.mon, SList) of
	{value,S} -> handle_sdo_process(S, Reason, Ctx);
	false ->  Ctx
    end.

handle_sdo_process(S, Reason, Ctx=#co_ctx {name = _Name, sdo_list = SList}) ->
    maybe_warning(Reason, "sdo session", _Name),
    Ctx#co_ctx { sdo_list = SList -- [S]}.

maybe_warning(normal, _Type, _Name) ->
    ok;
maybe_warning(Reason, Type, Name) ->
    ?ee("~s: ~s died: ~p", [Name, Type, Reason]).

handle_app_processes(Pid, Reason, Ctx=#co_ctx {app_list = AList}) 
  when is_pid(Pid)->
    case lists:keysearch(Pid, #app.pid, AList) of
	{value,A} -> handle_app_process(A, Reason, Ctx);
	false -> Ctx
    end;
handle_app_processes(Ref, Reason, Ctx=#co_ctx {app_list = AList}) ->
    case lists:keysearch(Ref, #app.mon, AList) of
	{value,A} -> handle_app_process(A, Reason, Ctx);
	false -> Ctx
    end.

handle_app_process(A=#app {pid = Pid}, Reason, 
		   Ctx=#co_ctx {name = _Name, app_list = AList,
			       sub_table = STable, res_table = RTable}) ->
    if Reason =/= normal ->
	    ?ee("~s: id=~w application died:~p", [_Name,A#app.pid, Reason]);
       true -> ok
    end,
    remove_subscriptions(STable, Pid), %% Or reset ??
    reset_reservations(RTable, Pid),
    %% FIXME: restart application? application_mod ?
    Ctx#co_ctx {app_list = AList--[A]}.

handle_tpdo_processes(Pid, Reason, Ctx=#co_ctx {tpdo_list = TList}) 
  when is_pid(Pid)->
    case lists:keysearch(Pid, #tpdo.pid, TList) of
	{value,T} -> handle_tpdo_process(T, Reason, Ctx);
	false -> Ctx
    end;
handle_tpdo_processes(Ref, Reason, Ctx=#co_ctx {tpdo_list = TList}) ->
    case lists:keysearch(Ref, #tpdo.mon, TList) of
	{value,T} -> handle_tpdo_process(T, Reason, Ctx);
	false -> Ctx
    end.

handle_tpdo_process(T=#tpdo {pid = _Pid, offset = _Offset}, _Reason, 
		    Ctx=#co_ctx {name = _Name, tpdo_list = TList}) ->
    ?ee("~s: id=~w tpdo process died: ~p", [_Name,_Pid, _Reason]),
    case restart_tpdo(T, Ctx) of
	{error, _Error} ->
	    ?ee(" ~s: not possible to restart "
                "tpdo process for offset ~p, reason = ~p", 
                [_Name,_Offset,_Error]),
	    Ctx;
	NewT ->
	    lager:debug("~s: handle_tpdo_processes: new tpdo process ~p started", 
		 [_Name, NewT#tpdo.pid]),
	    Ctx#co_ctx { tpdo_list = [NewT | TList]--[T]}
    end.



activate_nmt(Ctx=#co_ctx {supervision = Sup, dict = Dict, nmt_conf = Conf,
			  name = _Name, debug = Dbg}) ->
    lager:debug("~s: activate_nmt", [_Name]),
    co_nmt:start_link([{node_pid, self()},
		       {conf, Conf},
		       {dict, Dict},
		       {supervision, Sup},
		       {debug, Dbg}]),
    Ctx.

deactivate_nmt(Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: deactivate_nmt", [_Name]),
    co_nmt:stop(),
    Ctx.


broadcast_state(State, #co_ctx {state = State, name = _Name}) ->
    %% No change
    lager:debug("~s: broadcast_state: no change state = ~p", [_Name, State]),
    ok;
broadcast_state(State, Ctx=#co_ctx { name = _Name}) ->
    lager:debug("~s: broadcast_state: new state = ~p", [_Name, State]),

    %% To all tpdo processes
    send_to_tpdos({state, State}, Ctx),
    
    %% To all applications ??
    send_to_apps({state, State}, Ctx).

send_to_apps(Msg, _Ctx=#co_ctx {name = _Name, app_list = AList}) ->
    lists:foreach(
      fun(A) ->
	      case A#app.pid of
		  Pid -> 
		      lager:debug("~s: handle_call: sending ~w to app "
			   "with pid = ~p", [_Name, Msg, Pid]),
		      gen_server:cast(Pid, Msg) 
	      end
      end,
      AList).

send_to_tpdos(Msg, _Ctx=#co_ctx {name = _Name, tpdo_list = TList}) ->
    lists:foreach(
      fun(T) ->
	      case T#tpdo.pid of
		  Pid -> 
		      lager:debug("~s: handle_call: sending ~w to tpdo "
			   "with pid = ~p", [_Name, Msg, Pid]),
		      gen_server:cast(Pid, Msg) 
	      end
      end,
      TList).
    
%%
%% Dictionary entry has been updated
%% Emulate co_node as subscriber to dictionary updates
%%
handle_notify(I, Ctx) ->
    NewCtx = handle_notify1(I, Ctx),
    inform_subscribers(I, NewCtx),
    inform_reserver(I, NewCtx),
    NewCtx.

handle_notify1(I, Ctx=#co_ctx {name = _Name}) ->
    lager:debug("~s: handle_notify: Index=~.16#",[_Name, I]),
    case I of
	?IX_COB_ID_SYNC_MESSAGE ->
	    update_sync(Ctx);
	?IX_COM_CYCLE_PERIOD ->
	    update_sync(Ctx);
	?IX_COB_ID_TIME_STAMP ->
	    update_time_stamp(Ctx);
	?IX_COB_ID_EMERGENCY ->
	    update_emcy(Ctx);
	_ when I == ?IX_GUARD_TIME orelse I == ?IX_LIFE_TIME_FACTOR ->
	    update_node_guard(Ctx);
	_ when I == ?IX_CONSUMER_HEARTBEAT_TIME orelse 
	       I == ?IX_PRODUCER_HEARTBEAT_TIME ->
	    update_heartbeat(Ctx, I);
	_ when I >= ?IX_SDO_SERVER_FIRST, I =< ?IX_SDO_SERVER_LAST ->
	    case load_sdo_parameter(I, Ctx) of
		undefined -> Ctx;
		SDO ->
		    Rx = SDO#sdo_parameter.client_to_server_id,
		    Tx = SDO#sdo_parameter.server_to_client_id,
		    ets:insert(Ctx#co_ctx.cob_table, {Rx,{sdo_rx,Tx}}),
		    ets:insert(Ctx#co_ctx.cob_table, {Tx,{sdo_tx,Rx}}),
		    Ctx
	    end;
	_ when I >= ?IX_SDO_CLIENT_FIRST, I =< ?IX_SDO_CLIENT_LAST ->
	    case load_sdo_parameter(I, Ctx) of
		undefined -> Ctx;
		SDO ->
		    Tx = SDO#sdo_parameter.client_to_server_id,
		    Rx = SDO#sdo_parameter.server_to_client_id,
		    ets:insert(Ctx#co_ctx.cob_table, {Rx,{sdo_rx,Tx}}),
		    ets:insert(Ctx#co_ctx.cob_table, {Tx,{sdo_tx,Rx}}),
		    Ctx
	    end;
	_ when I >= ?IX_RPDO_PARAM_FIRST, I =< ?IX_RPDO_PARAM_LAST ->
	    lager:debug("~s: handle_notify: update RPDO offset=~.16#", 
		 [_Name, (I-?IX_RPDO_PARAM_FIRST)]),
	    case load_pdo_parameter(I, (I-?IX_RPDO_PARAM_FIRST), Ctx) of
		undefined -> 
		    Ctx;
		Param ->
		    if not (Param#pdo_parameter.valid) ->
			    ets:delete(Ctx#co_ctx.cob_table,
				       Param#pdo_parameter.cob_id);
		       true ->
			    ets:insert(Ctx#co_ctx.cob_table, 
				       {Param#pdo_parameter.cob_id,
					{rpdo,Param#pdo_parameter.offset}})
		    end,
		    Ctx
	    end;
	_ when I >= ?IX_TPDO_PARAM_FIRST, I =< ?IX_TPDO_PARAM_LAST ->
	    lager:debug("~s: handle_notify: update TPDO: offset=~.16#",
		 [_Name, I - ?IX_TPDO_PARAM_FIRST]),
	    case load_pdo_parameter(I, (I-?IX_TPDO_PARAM_FIRST), Ctx) of
		undefined -> Ctx;
		Param ->
		    case update_tpdo(Param, Ctx) of
			{new, {_T,Ctx1}} ->
			    lager:debug("~s: handle_notify: TPDO:new",
				 [_Name]),
			    
			    Ctx1;
			{existing,T} ->
			    lager:debug("~s: handle_notify: TPDO:existing",
				 [_Name]),
			    co_tpdo:update_param(T#tpdo.pid, Param),
			    Ctx;
			{deleted,Ctx1} ->
			    lager:debug("~s: handle_notify: TPDO:deleted",
				 [_Name]),
			    Ctx1;
			none ->
			    lager:debug("~s: handle_notify: TPDO:none",
				 [_Name]),
			    Ctx
		    end
	    end;
	_ when I >= ?IX_TPDO_MAPPING_FIRST, I =< ?IX_TPDO_MAPPING_LAST ->
	    Offset = I - ?IX_TPDO_MAPPING_FIRST,
	    lager:debug("~s: handle_notify: update TPDO-MAP: offset=~w", 
		 [_Name, Offset]),
	    J = ?IX_TPDO_PARAM_FIRST + Offset,
	    CobId = co_dict:direct_value(Ctx#co_ctx.dict,J,?SI_PDO_COB_ID),
	    case lists:keysearch(CobId, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
		{value, T} ->
		    co_tpdo:update_map(T#tpdo.pid),
		    Ctx;
		_ ->
		    Ctx
	    end;
	_ when I >= ?IX_OBJECT_DISPATCH_FIRST, I =< ?IX_OBJECT_DISPATCH_LAST ->
	    lager:debug(
	      "~s: handle_notify: update SAM-MPDO-Dispatch for index ~.16.0# ", 
	      [_Name, I]),
	    update_mpdo_disp(Ctx, I);
	_ ->
	    Ctx
    end.

update_node_guard(Ctx=#co_ctx {supervision = S, name = _Name}) 
  when S == none orelse S == heartbeat ->
    lager:debug("~s: update_node_guard: no node guarding.", [_Name]),
    Ctx;
update_node_guard(Ctx=#co_ctx {nmt_role = autonomous, name = _Name}) ->
    lager:debug("~s: update_node_guard: autonomous, no node guarding.", [_Name]),
    Ctx;
update_node_guard(Ctx=#co_ctx {nmt_role = master, name = _Name}) ->
    lager:debug("~s: update_node_guard: nmt master, node guarding "
	 "handled by nmt master process.", [_Name]),
    Ctx;
update_node_guard(Ctx=#co_ctx {nmt_role = slave, name = _Name}) ->
    lager:debug("~s: update_node_guard: nmt slave.", [_Name]),
    Ctx1 = deactivate_node_guard(Ctx),
    activate_node_guard(Ctx1).


update_heartbeat(Ctx=#co_ctx {supervision = S, name = _Name}, _I) 
  when S == none orelse S == node_guard ->
    lager:debug("~s: update_heartbeat: no heartbeat.", [_Name]),
    Ctx;
update_heartbeat(Ctx=#co_ctx {nmt_role = autonomous, name = _Name}, _I) ->
    lager:debug("~s: update_heartbeat: autonomous, no heartbeat.", [_Name]),
    Ctx;
update_heartbeat(Ctx=#co_ctx {nmt_role = master, name = _Name}, 
		 ?IX_CONSUMER_HEARTBEAT_TIME) ->
    lager:debug("~s: update_heartbeat: nmt master, heartbeat "
	 "handled by nmt master process.", [_Name]),
    gen_server:cast(co_nmt_master, heartbeat_change),    
    Ctx;
update_heartbeat(Ctx=#co_ctx {nmt_role = slave, name = _Name}, 
		?IX_PRODUCER_HEARTBEAT_TIME) ->
    lager:debug("~s: update_heartbeat: nmt slave.", [_Name]),
    Ctx1 = deactivate_heartbeat(Ctx),
    activate_heartbeat(Ctx1);
update_heartbeat(Ctx=#co_ctx {name = _Name}, _I) ->
    lager:debug("~s: update_heartbeat: no change.", [_Name]),
    Ctx.



update_mpdo_disp(Ctx=#co_ctx {dict = Dict, name = _Name}, I) ->
   try co_dict:direct_value(Dict,{I,0}) of
	NoOfEntries ->
	    Ixs = [{I, Si} || Si <- lists:seq(1, NoOfEntries)],
	   lager:debug("~s: update_mpdo_disp: index list ~w ", [_Name, Ixs]),
 	    update_mpdo_disp1(Ctx, Ixs)
    catch
	error:_Reason ->
	    ?ew("~s: update_mpdo_disp: reading dict, "
		"index  ~.16#:~w failed, reason = ~w",  
		[_Name, I, 0, _Reason]),
	    Ctx
    end.

update_mpdo_disp1(Ctx, []) ->
    Ctx;
update_mpdo_disp1(Ctx=#co_ctx {dict = Dict, mpdo_dispatch = MpdoDisp, name = _Name}, 
		 [Index = {_Ix, _Si} | Ixs]) ->
    lager:debug("~s: update_mpdo_disp: index ~.16#:~w ", [_Name, _Ix, _Si]),
    try co_dict:direct_value(Dict,Index) of
	Map ->
	    {SourceIx, SourceSi, SourceNid} = 
		{?RMPDO_MAP_RINDEX(Map), 
		 ?RMPDO_MAP_RSUBIND(Map), 
		 ?RMPDO_MAP_RNID(Map)},
	    {LocalIx, LocalSi} = 
		{?RMPDO_MAP_INDEX(Map), 
		 ?RMPDO_MAP_SUBIND(Map)},
	    Size = ?RMPDO_MAP_SIZE(Map),
	    EntryList = 
		[{{SourceIx, SourceSi + I, SourceNid}, {LocalIx,LocalSi + I}} ||
		    I <- lists:seq(0, Size - 1)],
	    lager:debug("~s: update_mpdo_disp: entry list ~w ", [_Name, EntryList]),
	    insert_mpdo_disp(MpdoDisp,EntryList)
    catch
	error:_Reason ->
	    ?ew("~s: update_mpdo_disp: reading dict, "
		"index  ~.16#:~w failed, reason = ~w",  
		[_Name, _Ix, _Si, _Reason])
    end,
    update_mpdo_disp1(Ctx, Ixs).
    
insert_mpdo_disp(_MpdoDisp,[]) ->
    ok;
insert_mpdo_disp(MpdoDisp,[Entry | EntryList]) ->	    
    ets:insert(MpdoDisp, Entry),
    insert_mpdo_disp(MpdoDisp, EntryList).
    
%% Load time_stamp CobId - maybe start co_time_stamp server
update_time_stamp(Ctx=#co_ctx {name = _Name}) ->
    try co_dict:direct_value(Ctx#co_ctx.dict,?IX_COB_ID_TIME_STAMP,0) of
	ID ->
	    CobId = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    if ID band ?COBID_ENTRY_TIME_PRODUCER =/= 0 ->
		    Time = Ctx#co_ctx.time_stamp_time,
		    lager:debug("~s: update_time_stamp: Timestamp server time=~p", 
			 [_Name, Time]),
		    if Time > 0 ->
			    Tmr = start_timer(Ctx#co_ctx.time_stamp_time,
					      time_stamp),
			    Ctx#co_ctx { time_stamp_tmr=Tmr, 
					 time_stamp_id=CobId };
		       true ->
			    Tmr = stop_timer(Ctx#co_ctx.time_stamp_tmr),
			    Ctx#co_ctx { time_stamp_tmr=Tmr,
					 time_stamp_id=CobId}
		    end;
	       ID band ?COBID_ENTRY_TIME_CONSUMER =/= 0 ->
		    %% consumer
		    lager:debug("~s: update_time_stamp: Timestamp consumer", 
			 [_Name]),
		    Tmr = stop_timer(Ctx#co_ctx.time_stamp_tmr),
		    %% FIXME: delete old CobId!!!
		    ets:insert(Ctx#co_ctx.cob_table, {CobId,time_stamp}),
		    Ctx#co_ctx { time_stamp_tmr=Tmr, time_stamp_id=CobId}
	    end
    catch
	error:_Reason ->
	    Ctx
    end.


%% Load emcy CobId 
update_emcy(Ctx) ->
    try co_dict:direct_value(Ctx#co_ctx.dict,?IX_COB_ID_EMERGENCY,0) of
	ID ->
	    CobId = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    if ID band ?COBID_ENTRY_INVALID =/= 0 ->
		    Ctx#co_ctx { emcy_id = CobId };
	       true ->
		    Ctx#co_ctx { emcy_id = 0 }
	    end
    catch
	error:_ ->
	    Ctx#co_ctx { emcy_id = 0 }  %% FIXME? keep or reset?
    end.

%% Either SYNC_MESSAGE or CYCLE_WINDOW is updated
update_sync(Ctx) ->
    try co_dict:direct_value(Ctx#co_ctx.dict,?IX_COB_ID_SYNC_MESSAGE,0) of
	ID ->
	    CobId = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    if ID band ?COBID_ENTRY_SYNC =/= 0 ->
		    %% producer - sync server
		    try co_dict:direct_value(Ctx#co_ctx.dict,
					     ?IX_COM_CYCLE_PERIOD,0) of
			Time when Time > 0 ->
			    %% we do not have micro :-(
			    Ms = (Time + 999) div 1000,  
			    Tmr = start_timer(Ms, sync),
			    Ctx#co_ctx { sync_tmr=Tmr,sync_time = Ms,
					 sync_id=CobId };
			_ ->
			    Tmr = stop_timer(Ctx#co_ctx.sync_tmr),
			    Ctx#co_ctx { sync_tmr=Tmr,sync_time=0,
					 sync_id=CobId}
		    catch
			error:_Reason ->
			    Ctx
		    end;
	       true ->
		    %% consumer
		    Tmr = stop_timer(Ctx#co_ctx.sync_tmr),
		    ets:insert(Ctx#co_ctx.cob_table, {CobId,sync}),
		    Ctx#co_ctx { sync_tmr=Tmr, sync_time=0,sync_id=CobId}
	    end
    catch
	error:_Reason ->
	    Ctx
    end.
    

update_tpdo(P=#pdo_parameter {offset = Offset, cob_id = CId, valid = Valid}, 
	    Ctx=#co_ctx { tpdo_list = TList, tpdo = TpdoCtx, 
			  name = _Name, debug = Dbg }) ->
    lager:debug("~s: update_tpdo: pdo param for ~p", [_Name, Offset]),
    case lists:keytake(CId, #tpdo.cob_id, TList) of
	false ->
	    if Valid ->
		    {ok,Pid} = co_tpdo:start(TpdoCtx#tpdo_ctx {debug = Dbg}, P),
		    lager:debug("~s: update_tpdo: starting tpdo process ~p for ~p", 
			 [_Name, Pid, Offset]),
		    %%co_tpdo:debug(Pid, Dbg),
		    gen_server:cast(Pid, {state, Ctx#co_ctx.state}),
		    Mon = erlang:monitor(process, Pid),
		    T = #tpdo { offset = Offset,
				cob_id = CId,
				pid = Pid,
				mon = Mon },
		    {new, {T, Ctx#co_ctx { tpdo_list = TList ++ [T]}}};
	       true ->
		    none
	    end;
	{value, T, TList1} ->
	    if Valid ->
		    {existing, T};
	       true ->
		    erlang:demonitor(T#tpdo.mon),
		    co_tpdo:stop(T#tpdo.pid),
		    {deleted, Ctx#co_ctx { tpdo_list = TList1 }}
	    end
    end.

restart_tpdo(T=#tpdo {offset = Offset, rc = RC}, 
	     Ctx=#co_ctx {tpdo = TpdoCtx, tpdo_restart_limit = TRL, 
			  name = _Name, debug = Dbg}) ->
    case load_pdo_parameter(?IX_TPDO_PARAM_FIRST + Offset, Offset, Ctx) of
	undefined -> 
	    lager:debug("~s: restart_tpdo: pdo param for ~p not found", 
		 [_Name, Offset]),
	    {error, not_found};
	Param ->
	    case RC >= TRL of
		true ->
		    lager:debug("~s: restart_tpdo: restart counter exceeded",  
				[_Name]),
		    {error, restart_not_allowed};
		false ->
		    {ok,Pid} = 
			co_tpdo:start(TpdoCtx#tpdo_ctx {debug = Dbg}, Param),
		    %% co_tpdo:debug(Pid, Dbg),
		    gen_server:cast(Pid, {state, Ctx#co_ctx.state}),
		    Mon = erlang:monitor(process, Pid),
		    
		    %% If process still ok after 1 min, reset counter
		    erlang:send_after(60 * 1000,  self(), {rc_reset, Pid}),

		    T#tpdo {pid = Pid, mon = Mon, rc = RC+1}
	    end
    end.



load_pdo_parameter(I, Offset, _Ctx=#co_ctx {dict = Dict, name = _Name}) ->
    lager:debug("~s: load_pdo_parameter ~p + ~p", [_Name, I, Offset]),
    case load_list(Dict, [{I, ?SI_PDO_COB_ID}, 
			  {I,?SI_PDO_TRANSMISSION_TYPE, 255},
			  {I,?SI_PDO_INHIBIT_TIME, 0},
			  {I,?SI_PDO_EVENT_TIMER, 0}]) of
	[ID,Trans,Inhibit,Timer] ->
	    Valid = (ID band ?COBID_ENTRY_INVALID) =:= 0,
	    RtrAllowed = (ID band ?COBID_ENTRY_RTR_DISALLOWED) =:=0,
	    CobId = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    #pdo_parameter { offset = Offset,
			     valid = Valid,
			     rtr_allowed = RtrAllowed,
			     cob_id = CobId,
			     transmission_type=Trans,
			     inhibit_time = Inhibit,
			     event_timer = Timer };
	_ ->
	    undefined
    end.
    

load_sdo_parameter(I, _Ctx=#co_ctx {dict = Dict}) ->
    case load_list(Dict, [{I,?SI_SDO_CLIENT_TO_SERVER},{I,?SI_SDO_SERVER_TO_CLIENT},
			  {I,?SI_SDO_NODEID,undefined}]) of
	[CS,SC,NodeID] ->
	    #sdo_parameter { client_to_server_id = CS, 
			     server_to_client_id = SC,
			     node_id = NodeID };
	_ ->
	    undefined
    end.

load_list(Dict, List) ->
    load_list(Dict, List, []).

load_list(Dict, [{Ix,Si}|List], Acc) ->
    try co_dict:direct_value(Dict,Ix,Si) of
	Value -> load_list(Dict, List, [Value|Acc])
    catch
	error:_ -> undefined
    end;
load_list(Dict, [{Ix,Si,Default}|List],Acc) ->
    try co_dict:direct_value(Dict,Ix,Si) of
	Value -> load_list(Dict, List, [Value|Acc])
    catch
	error:_ ->
	    load_list(Dict, List, [Default|Acc])
    end;
load_list(_Dict, [], Acc) ->
    reverse(Acc).

index_defined([], _Ctx) ->
    true;
index_defined([Ix | Rest], 
	      Ctx=#co_ctx {dict = Dict, res_table = RTable, name = _Name}) ->
    case co_dict:lookup_object(Dict, Ix) of
	{ok, _Obj} -> 
	    true,
	    index_defined(Rest, Ctx);
	{error, _Reason} ->
	    lager:debug("~s: index_defined: index ~.16# not in dictionary",  
			[_Name, Ix]),
	    case reserver_pid(RTable, Ix) of
		[] -> 
		    lager:debug("~s: index_defined: index ~.16# not reserved",  
				[_Name, Ix]),
		    false;
		[_Any] ->
		    true,
		    index_defined(Rest, Ctx)
	    end
    end.
    


add_subscription(Tab, Ix, Key) ->
    add_subscription(Tab, Ix, Ix, Key).

add_subscription(Tab, Ix1, Ix2, Key) 
  when ?is_index(Ix1), ?is_index(Ix2), 
       Ix1 =< Ix2 ->
    lager:debug("add_subscription: ~.16#:~.16# for ~w", 
	 [Ix1, Ix2, Key]),
    I = co_iset:new(Ix1, Ix2),
    case ets:lookup(Tab, Key) of
	[] -> ets:insert(Tab, {Key, I});
	[{_,ISet}] -> ets:insert(Tab, {Key, co_iset:union(ISet, I)})
    end,
    ok.

remove_subscriptions(Tab, Key) ->
    ets:delete(Tab, Key),
    ok.

remove_subscription(Tab, Ix, Key) ->
    remove_subscription(Tab, Ix, Ix, Key).

remove_subscription(Tab, Ix1, Ix2, Key) when Ix1 =< Ix2 ->
    lager:debug("remove_subscription: ~.16#:~.16# for ~w", 
	 [Ix1, Ix2, Key]),
    case ets:lookup(Tab, Key) of
	[] -> ok;
	[{Key,ISet}] -> 
	    case co_iset:difference(ISet, co_iset:new(Ix1, Ix2)) of
		[] ->
		    lager:debug("remove_subscription: last index for ~w", 
			 [Key]),
		    ets:delete(Tab, Key);
		ISet1 -> 
		    lager:debug("remove_subscription: new index set ~p for ~w", 
			 [ISet1,Key]),
		    ets:insert(Tab, {Key,ISet1})
	    end
    end,
    ok.

subscriptions(Tab, Key) when is_pid(Key) ->
    case ets:lookup(Tab, Key) of
	[] -> [];
	[{Key, Iset, _Opts}] -> Iset
    end.

subscribers(Tab) ->
    lists:usort([Key || {Key, _Ixs} <- ets:tab2list(Tab)]).

inform_subscribers(I, _Ctx=#co_ctx {name = _Name, sub_table = STable}) ->
    Self = self(),
    lists:foreach(
      fun(Pid) ->
	      case Pid of
		  Self -> do_nothing;
		  _OtherPid ->
		      lager:debug("~s: inform_subscribers: "
			   "Sending object event to ~p", [_Name, Pid]),
		      gen_server:cast(Pid, {object_event, I}) 
	      end
      end,
      lists:usort(subscribers(STable, I))).


reservations(Tab, Pid) when is_pid(Pid) ->
    lists:usort([Ix || {Ix, _M, P} <- ets:tab2list(Tab), P == Pid]).

	
add_reservation(_Tab, [], _Mod, _Pid) ->
    ok;
add_reservation(Tab, [Ix | Tail], Mod, Pid) ->
    case ets:lookup(Tab, Ix) of
	[] -> 
	    lager:debug("add_reservation: ~.16# for ~w",[Ix, Pid]), 
	    ets:insert(Tab, {Ix, Mod, Pid}), 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, Mod, dead}] ->  %% M or Mod ???
	    ok, 
	    lager:debug("add_reservation: renewing ~.16# for ~w",[Ix, Pid]), 
	    ets:insert(Tab, {Ix, Mod, Pid}), 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, _M, Pid}] -> 
	    ok, 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, _M, _OtherPid}] ->        
	    lager:debug("add_reservation: index already reserved  by ~p", 
		 [_OtherPid]),
	    {error, index_already_reserved}
    end.


add_reservation(_Tab, Ix1, Ix2, _Mod, _Pid) when Ix1 < ?MAN_SPEC_MIN;
						 Ix2 < ?MAN_SPEC_MIN->
    lager:debug("add_reservation: not possible for ~.16#:~w for ~w", 
	 [Ix1, Ix2, _Pid]),
    {error, not_possible_to_reserve};
add_reservation(Tab, Ix1, Ix2, Mod, Pid) when ?is_index(Ix1), ?is_index(Ix2), 
					      Ix1 =< Ix2, 
					      is_pid(Pid) ->
    lager:debug("add_reservation: ~.16#:~w for ~w", 
	 [Ix1, Ix2, Pid]),
    add_reservation(Tab, lists:seq(Ix1, Ix2), Mod, Pid).
	    

   
remove_reservations(Tab, Pid) ->
    remove_reservation(Tab, reservations(Tab, Pid), Pid).

remove_reservation(_Tab, [], _Pid) ->
    ok;
remove_reservation(Tab, [Ix | Tail], Pid) ->
    lager:debug("remove_reservation: ~.16# for ~w", [Ix, Pid]),
    case ets:lookup(Tab, Ix) of
	[] -> 
	    ok, 
	    remove_reservation(Tab, Tail, Pid);
	[{Ix, _M, Pid}] -> 
	    ets:delete(Tab, Ix), 
	    remove_reservation(Tab, Tail, Pid);
	[{Ix, _M, _OtherPid}] -> 	    
	    lager:debug("remove_reservation: index reserved by other pid ~p", 
		 [_OtherPid]),
	    {error, index_reservered_by_other}
    end.

remove_reservation(Tab, Ix1, Ix2, Pid) when Ix1 =< Ix2 ->
    lager:debug("remove_reservation: ~.16#:~.16# for ~w", 
	 [Ix1, Ix2, Pid]),
    remove_reservation(Tab, lists:seq(Ix1, Ix2), Pid).

reset_reservations(Tab, Pid) ->
    reset_reservation(Tab, reservations(Tab, Pid), Pid).

reset_reservation(_Tab, [], _Pid) ->
    ok;
reset_reservation(Tab, [Ix | Tail], Pid) ->
    lager:debug("reset_reservation: ~.16# for ~w", [Ix, Pid]),
    case ets:lookup(Tab, Ix) of
	[] -> 
	    ok, 
	    reset_reservation(Tab, Tail, Pid);
	[{Ix, M, Pid}] -> 
	    ets:delete(Tab, Ix), 
	    ets:insert(Tab, {Ix, M, dead}),
	    reset_reservation(Tab, Tail, Pid);
	[{Ix, _M, _OtherPid}] -> 	    
	    lager:debug("reset_reservation: index reserved by other pid ~p", 
		 [_OtherPid]),
	    {error, index_reservered_by_other}
    end.

reservers(Tab) ->
    lists:usort([Pid || {_Ix, _M, Pid} <- ets:tab2list(Tab)]).

reserver_pid(Tab, Ix) when ?is_index(Ix) ->
    case ets:lookup(Tab, Ix) of
	[] -> [];
	[{Ix, _Mod, Pid}] -> [Pid]
    end.

inform_reserver(Ix, _Ctx=#co_ctx {name = _Name, res_table = RTable}) ->
    Self = self(),
    case reserver_pid(RTable, Ix) of
	[Self] -> do_nothing;
	[] -> do_nothing;
	[Pid] when is_pid(Pid) -> 
	    lager:debug("~s: inform_reservers: "
		 "Sending object event to ~p", [_Name, Pid]),
	    gen_server:cast(Pid, {object_event, Ix})
    end.

lookup_sdo_server(Nid, _Ctx=#co_ctx {name = _Name}) ->
    if ?is_nodeid_extended(Nid) ->
	    NodeID = Nid band ?COBID_ENTRY_ID_MASK,
	    Tx = ?XCOB_ID(?SDO_TX,NodeID),
	    Rx = ?XCOB_ID(?SDO_RX,NodeID),
	    {Tx,Rx};
       ?is_nodeid(Nid) ->
	    NodeID = Nid band 16#7F,
	    Tx = ?COB_ID(?SDO_TX,NodeID),
	    Rx = ?COB_ID(?SDO_RX,NodeID),
	    {Tx,Rx};
       true ->
	    lager:debug("~s: lookup_sdo_server: Nid  ~12.16.0# "
		 "neither extended nor short ???", [_Name, Nid]),
	    undefined
    end.

lookup_cobid(CobId, Ctx) ->
    case ets:lookup(Ctx#co_ctx.cob_table, CobId) of
	[{_,Entry}] -> 
	    Entry;
	[] -> 
	    if %% Sdo tx, start session
	       ?is_cobid_extended(CobId) andalso 
	       ?XFUNCTION_CODE(CobId) =:= ?SDO_TX ->
		    {sdo_tx, ?XCOB_ID(?SDO_RX, ?XNODE_ID(CobId))};
	       ?is_not_cobid_extended(CobId) andalso
	       ?FUNCTION_CODE(CobId) =:= ?SDO_TX ->
		    {sdo_tx, ?COB_ID(?SDO_RX, ?NODE_ID(CobId))};

	       %% Sdo rx to other node, ignore
	       ?is_cobid_extended(CobId) andalso 
	       ?XFUNCTION_CODE(CobId) =:= ?SDO_RX ->
		    {sdo_rx, not_receiver, ?XCOB_ID(?SDO_RX, ?XNODE_ID(CobId))};
	       ?is_not_cobid_extended(CobId) andalso
	       ?FUNCTION_CODE(CobId) =:= ?SDO_RX ->
		    {sdo_rx, not_receiver, ?COB_ID(?SDO_RX, ?NODE_ID(CobId))};

	       %% Node guard -> nmt master
	       ?is_cobid_extended(CobId) andalso 
	       ?XFUNCTION_CODE(CobId) =:= ?NODE_GUARD ->
		    {supervision, {xnodeid, ?XNODE_ID(CobId)}};
	       ?is_not_cobid_extended(CobId) andalso
	       ?FUNCTION_CODE(CobId) =:= ?NODE_GUARD ->
		    {supervision, {nodeid, ?NODE_ID(CobId)}};

	       true ->
		    undefined
	    end
    end.

%%
%% 
%%
%%
%% Callback functions for changes in tpdo elements
%%
tpdo_set({_Ix, _Si} = I, Data, Mode,
	 Ctx=#co_ctx {tpdo_cache = Cache, tpdo_cache_limit = TCL, name = _Name}) ->
    lager:debug("~s: tpdo_set: Ix = ~.16#:~w, Data = ~w, Mode ~p",
	 [_Name, _Ix, _Si, Data, Mode]), 
    case {ets:lookup(Cache, I), Mode} of
	{[], _} ->
	    %% Previously unknown tpdo element, probably in sam_mpdo
	    %% with block size > 1
	    %% Insert ??
	    lager:debug("~s: tpdo_set: inserting first value for "
		 "previously unknown tpdo element.",
		 [_Name]), 
	    ets:insert(Cache, {I, [Data]}),
	    {ok, Ctx};
	    %% io:format("WARNING!" 
	    %% "~s: tpdo_set: unknown tpdo element\n", [_Name]),
	    %% {{error,unknown_tpdo_element}, Ctx};
	{[{I, OldData}], append} when length(OldData) >= TCL ->
	    ?ew("~s: tpdo_set: tpdo cache for ~.16#:~w full.", 
		[_Name,  _Ix, _Si]),
	    {{error, tpdo_cache_full}, Ctx};
	{[{I, OldData}], append} ->
	    NewData = case OldData of
			    [(<<>>)] -> [Data]; %% remove default
			    _List -> OldData ++ [Data]
			end,
	    lager:debug("~s: tpdo_set: append, old = ~p, new = ~p",
		 [_Name, OldData, NewData]), 
	    try ets:insert(Cache,{I,NewData}) of
		true -> {ok, Ctx}
	    catch
		error:Reason -> 
		    ?ew("~s: tpdo_set: insert of ~p failed, reason = ~w", 
			[_Name, NewData, Reason]),
		    {{error,Reason}, Ctx}
	    end;
	{[{I, _OldData}], overwrite} ->
	    lager:debug("~s: tpdo_set: overwrite, old = ~p, new = ~p",
		 [_Name, _OldData, Data]), 
	    ets:insert(Cache, {I, [Data]}),
	    {ok, Ctx}
    end.

%%
%% Unpack PDO Data from external TPDO/internal RPDO 
%%
rpdo_unpack(I, Data, Ctx=#co_ctx {name = _Name}) ->
    case pdo_mapping(I, Ctx#co_ctx.res_table, Ctx#co_ctx.dict, 
		     Ctx#co_ctx.tpdo_cache, self()) of
	{rpdo,IL} ->
	    BitLenList = [BitLen || {_Ix, BitLen} <- IL],
	    lager:debug("~s: rpdo_unpack: data = ~w, il = ~w, bl = ~w", 
		 [_Name, Data, IL, BitLenList]),
	    try co_codec:decode_pdo(Data, BitLenList) of
		{Ds, _} ->
		    lager:debug("~s: rpdo_unpack: decoded data ~p", [_Name, Ds]),
		    rpdo_set(IL, Ds, Ctx)
	    catch error:_Reason ->
		    ?ew("~s: rpdo_unpack: decode failed, reason ~p",  
			[_Name, _Reason]),
		    Ctx
	    end;
	_Error ->
	    ?ew("~s: rpdo_unpack: error = ~p", [_Name, _Error]),
	    Ctx
    end.

rpdo_set([{{Ix,Si}, _BitLen}|Is], [Data|Ds], Ctx) ->
    if Ix >= ?BOOLEAN, Ix =< ?UNSIGNED32 -> %% skip entry
	    rpdo_set(Is, Ds, Ctx);
       true ->
	    Ctx1 = rpdo_value({Ix,Si},Data,Ctx),
	    rpdo_set(Is, Ds, Ctx1)
    end;
rpdo_set([], [], Ctx) ->
    Ctx.

%%
%% read PDO mapping  => {tpdo | dam_mpdo, [{Index, Len}} |
%%                      {sam_mpdo, [{{Index,BlockSize}, Len}} 
%%
pdo_mapping(Ix, _TpdoCtx=#tpdo_ctx {dict = Dict, 
				    res_table = ResTable, 
				    tpdo_cache = TpdoCache,
				    node_pid = NodePid}) ->
    lager:debug("pdo_mapping: api call for ~.16#", [Ix]),
    pdo_mapping(Ix, ResTable, Dict, TpdoCache, NodePid).
pdo_mapping(Ix, ResTable, Dict, TpdoCache, NodePid) ->
    lager:debug("pdo_mapping: ~.16#", [Ix]),
    case co_dict:value(Dict, Ix, 0) of
	{ok,N} when N >= 0, N =< 64 -> %% Standard tpdo/rpdo
	    MType = case Ix of
			_TPDO when Ix >= ?IX_TPDO_MAPPING_FIRST, 
				   Ix =< ?IX_TPDO_MAPPING_LAST ->
			    tpdo;
			_RPDO when Ix >= ?IX_RPDO_MAPPING_FIRST, 
				   Ix =< ?IX_RPDO_MAPPING_LAST ->
			    rpdo
		    end,
	    lager:debug("pdo_mapping: Standard pdo of size ~p found", [N]),
	    pdo_mapping(MType,Ix,1,N,ResTable,Dict,TpdoCache,NodePid);
	{ok,?SAM_MPDO} -> %% SAM-MPDO
	    lager:debug("pdo_mapping: sam_mpdo identified look for value", []),
	    mpdo_mapping(sam_mpdo,Ix,ResTable,Dict,TpdoCache,NodePid);
	{ok,?DAM_MPDO} -> %% DAM-MPDO
	    lager:debug("pdo_mapping: dam_mpdo found", []),
	    pdo_mapping(dam_mpdo,Ix,1,1,ResTable,Dict,TpdoCache,NodePid);
	Error ->
	    Error
    end.


pdo_mapping(MType,Ix,Si,Sn,ResTable,Dict,TpdoCache,NodePid) ->
    pdo_mapping(MType,Ix,Si,Sn,[],ResTable,Dict,TpdoCache,NodePid).

pdo_mapping(MType,_Ix,Si,Sn,Is,_ResTable,_Dict,_TpdoCache,_NodePid) when Si > Sn ->
    lager:debug("pdo_mapping: ~p all entries mapped, result ~p", 
	 [MType, Is]),
    {MType, reverse(Is)};
pdo_mapping(MType,Ix,Si,Sn,Is,ResTable,Dict,TpdoCache,NodePid) -> 
    lager:debug("pdo_mapping: type = ~p, index = ~.16#:~w", [MType,Ix,Si]),
    case co_dict:value(Dict, Ix, Si) of
	{ok,Map} ->
	    lager:debug("pdo_mapping: map = ~.16#", [Map]),
	    Index = {_I,_S} = {?PDO_MAP_INDEX(Map),?PDO_MAP_SUBIND(Map)},
	    lager:debug("pdo_mapping: entry[~w] = {~.16#:~w}", 
		 [Si,_I,_S]),
	    maybe_inform_reserver(MType, Index, ResTable, Dict, TpdoCache, NodePid),
	    pdo_mapping(MType,Ix,Si+1,Sn,
			[{Index, ?PDO_MAP_BITS(Map)}|Is], 
			ResTable, Dict, TpdoCache, NodePid);
	Error ->
	    lager:debug("pdo_mapping: ~.16#:~w = Error ~w", 
		 [Ix,Si,Error]),
	    Error
    end.

mpdo_mapping(MType,Ix,ResTable,Dict,TpdoCache,NodePid) 
  when MType == sam_mpdo andalso is_integer(Ix) ->
    lager:debug("mpdo_mapping: index = ~.16#", [Ix]),
    case co_dict:value(Dict, Ix, 1) of
	{ok,Map} ->
	   Index = {?PDO_MAP_INDEX(Map),?PDO_MAP_SUBIND(Map)},
	   mpdo_mapping(MType,Index,ResTable,Dict,TpdoCache,NodePid);
	Error ->
	    lager:debug("mpdo_mapping: ~.16# = Error ~w", [Ix,Error]),
	    Error
    end;
mpdo_mapping(MType,{IxInScanList,SiInScanList},ResTable,Dict,TpdoCache,NodePid) 
  when MType == sam_mpdo andalso
       IxInScanList >= ?IX_OBJECT_SCANNER_FIRST andalso
       IxInScanList =< ?IX_OBJECT_SCANNER_LAST  ->
    %% MPDO Producer mapping
    %% The entry in PDO Map has been read, now read the entry in MPDO Scan List
    lager:debug("mpdo_mapping: sam_mpdo, scan index = ~.16#:~w", 
	 [IxInScanList,SiInScanList]),
    case co_dict:value(Dict, IxInScanList, SiInScanList) of
	{ok, Map} ->
	    lager:debug("mpdo_mapping: map = ~.16#", [Map]),
	    Index = {_Ix,_Si} = {?TMPDO_MAP_INDEX(Map),?TMPDO_MAP_SUBIND(Map)},
	    BlockSize = ?TMPDO_MAP_SIZE(Map), %% TODO ????
	    lager:debug("mpdo_mapping: sam_mpdo, local index = ~.16#:~w", 
			[_Ix,_Si]),
	    maybe_inform_reserver(MType, Index, ResTable, Dict, TpdoCache, NodePid),
	    {MType, [{{Index, BlockSize}, ?MPDO_DATA_SIZE}]};
	Error ->
	    Error %%??
    end.
       
maybe_inform_reserver(MType, {Ix, _Si} = Index, ResTable, 
		      _Dict, TpdoCache, NodePid) ->
    case reserver_with_module(ResTable, Ix) of
	[] ->
	    lager:debug("maybe_inform_reserver: No reserver for index ~.16#", [Ix]),
	    ok;
	{NodePid, _Mod} when is_pid(NodePid)->
	    lager:debug(
	      "maybe_inform_reserver: co_node ~p has reserved index ~.16#", 
	      [NodePid, Ix]),
	    ok;
	{Pid, _Mod} when is_pid(Pid)->
	    lager:debug(
	      "maybe_inform_reserver: Process ~p has reserved index ~.16#", 
	      [Pid, Ix]),

	    %% Handle differently when TPDO and RPDO
	    case MType of
		rpdo ->
		    ok;
		T when T == tpdo orelse T == sam_mpdo orelse T == dam_mpdo ->

		    %% Store default value in cache ??
		    case ets:lookup(TpdoCache, Index) of
			[] ->
			    ets:insert(TpdoCache, {Index, [(<<>>)]});
			[_Something] ->
			    do_nothing
		    end,
		    gen_server:cast(Pid, {index_in_tpdo, Index}),
		    ok
	    end;
	{dead, _Mod} ->
	    lager:debug("maybe_inform_reserver: "
		 "Reserver process for index ~.16# dead.", [Ix]),
	    {error, ?abort_internal_error}
    end.

tpdo_data({Ix, Si} = I, #tpdo_ctx {res_table = ResTable, 
				   dict = Dict, 
				   tpdo_cache = TpdoCache, 
				   node_pid = NodePid}) ->
    case reserver_with_module(ResTable, Ix) of
	[] ->
	    lager:debug("tpdo_data: No reserver for index ~.16#", [Ix]),
	    co_dict:data(Dict, Ix, Si);
	{NodePid, _Mod} when is_pid(NodePid)->
	    lager:debug("tpdo_data: co_node ~p has reserved index ~.16#", 
		 [NodePid, Ix]),
	    co_dict:data(Dict, Ix, Si);
	{Pid, _Mod} when is_pid(Pid)->
	    lager:debug("tpdo_data: Process ~p has reserved index ~.16#", 
		 [Pid, Ix]),
	    %% Value cached ??
	    cache_value(TpdoCache, I);
	{dead, _Mod} ->
	    lager:debug("tpdo_data: Reserver process for index ~.16# dead.", 
		 [Ix]),
	    %% Value cached??
	    cache_value(TpdoCache, I)
    end.

cache_value(Cache, I = {_Ix, _Si}) ->
    case ets:lookup(Cache, I) of
	[] ->
	    %% How handle ???
	    ?ew("~p: cache_value: unknown tpdo element ~.16#:~w", 
		 [self(), _Ix, _Si]),
	    lager:debug("cache_value: tpdo element not found for ~.16#:~w, "
		 "returning default value.",  [_Ix, _Si]),
	    {error, no_value};
	[{I,[LastValue | []]}]  ->
	    %% Leave last value in cache
	    lager:debug("cache_value: Last value = ~p.", [LastValue]),
	    {ok, LastValue};
	[{I, [FirstValue | Rest]}] ->
	    %% Remove first value from list
	    lager:debug("cache_value: First value = ~p, rest = ~p.", 
		 [FirstValue, Rest]),
	    ets:insert(Cache, {I, Rest}),
	    {ok, FirstValue}
    end.
	    
    
rpdo_value({Ix,Si},Data,Ctx=#co_ctx {res_table = RTable}) ->
    Self = self(),
    case reserver_with_module(RTable, Ix) of
	[] ->
	    rpdo_value_dict({Ix,Si},Data,Ctx);
	{Self, _Mod} when is_pid(Self)->
	    rpdo_value_dict({Ix,Si},Data,Ctx);	    
	{Pid, Mod} when is_pid(Pid)->
	    rpdo_value_app({Ix,Si}, Data, {Pid, Mod}, Ctx);
	{dead, _Mod} ->
	    lager:debug("rpdo_value: Reserver process for index ~.16# dead.", 
		 [Ix]),
	    Ctx
    end.

rpdo_value_dict({Ix,Si}, Data, Ctx=#co_ctx {dict = Dict}) ->
    lager:debug("rpdo_value: No reserver for index ~.16#", [Ix]),
    try co_dict:set_data(Dict, Ix, Si, Data) of
	ok -> 
	    handle_notify(Ix, Ctx);
	_Error -> 
	    lager:debug("rpdo_value: set_data failed,error ~p", [_Error]),
	    Ctx
    catch
	error:_Reason -> 
	    lager:debug("rpdo_value: set_data failed, reason ~p", [_Reason]),
	    Ctx
    end.

rpdo_value_app({Ix,Si}, Data, {Pid, Mod}, Ctx) ->
    lager:debug("rpdo_value: Process ~p has reserved index ~.16#", [Pid, Ix]),
    case co_set_fsm:start({Pid, Mod}, {Ix, Si}, Data) of
	{ok, _FsmPid} -> 
	    lager:debug([node],"Started set session ~p", [_FsmPid]),
	    handle_notify(Ix, Ctx);
	ignore ->
	    lager:debug([node],"Complete set session executed", []),
	    handle_notify(Ix, Ctx);
	{error, _Reason} -> 	
	    %% io:format ??
	    lager:debug([node],"Failed starting set session, reason ~p", [_Reason]),
	    Ctx
    end.


%% Set error code - and send the emergency object (if defined)
%% FIXME: clear error list when code 0000
set_error(Error, Code, Ctx) ->
    case lists:member(Code, Ctx#co_ctx.error_list) of
	true -> 
	    Ctx;  %% condition already reported, do NOT send
	false ->
	    co_dict:direct_set_value(Ctx#co_ctx.dict,?IX_ERROR_REGISTER, 0, Error),
	    NewErrorList = 
		update_error_list([Code | Ctx#co_ctx.error_list], 1, Ctx),
	    if Ctx#co_ctx.emcy_id =:= 0 ->
		    ok;
	       true ->
		    FrameID = ?COBID_TO_CANID(Ctx#co_ctx.emcy_id),
		    Data = <<Code:16/little,Error,0,0,0,0,0>>,
		    Frame = #can_frame { id = FrameID, len=0, data=Data },
		    can:send(Frame)
	    end,
	    Ctx#co_ctx { error_list = NewErrorList }
    end.

update_error_list([], Si, Ctx) ->
    co_dict:update_entry(Ctx#co_ctx.dict,
			 #dict_entry { index = {?IX_PREDEFINED_ERROR_FIELD,0},
				       access = ?ACCESS_RW,
				       type  = ?UNSIGNED8,
				       data = co_codec:encode(Si,?UNSIGNED8) }),
    [];
update_error_list(_Cs, Si, Ctx) when Si >= 254 ->
    co_dict:update_entry(Ctx#co_ctx.dict,
			 #dict_entry { index = {?IX_PREDEFINED_ERROR_FIELD,0},
				       access = ?ACCESS_RW,
				       type  = ?UNSIGNED8,
				       data = co_codec:encode(254,?UNSIGNED8) }),
    [];
update_error_list([Code|Cs], Si, Ctx) ->
    %% FIXME: Code should be 16 bit MSB ?
    co_dict:update_entry(Ctx#co_ctx.dict,
			 #dict_entry { index = {?IX_PREDEFINED_ERROR_FIELD,Si},
				       access = ?ACCESS_RO,
				       type  = ?UNSIGNED32,
				       data = co_codec:encode(Code,?UNSIGNED32) }),
    [Code | update_error_list(Cs, Si+1, Ctx)].
    

print_hex(Label, undefined) ->
    io:format("~7s:"++ " not defined~n",
	      [string:to_upper(atom_to_list(Label))]);
print_hex(Label, NodeId) ->
    io:format("~7s:" ++ " ~10.16.0#\n", 
	      [string:to_upper(atom_to_list(Label)),NodeId]).

%% Optionally start a timer
start_timer(infinity, _Msg) -> false;
start_timer(0, _Msg) -> false;
start_timer(Time, Msg) -> erlang:start_timer(Time,self(),Msg).

%% Optionally stop a timer and flush
stop_timer(false) -> false;
stop_timer(undefined) -> false;
stop_timer(TimerRef) ->
    case erlang:cancel_timer(TimerRef) of
	false ->
	    receive
		{timeout,TimerRef,_} -> false
	    after 0 ->
		    false
	    end;
	_Remain -> false
    end.


time_of_day() ->
    now_to_time_of_day(os:timestamp()).

set_time_of_day(_Time) ->
    lager:debug("set_time_of_day: ~p", [_Time]),
    ok.

now_to_time_of_day({Sm,S0,Us}) ->
    S1 = Sm*1000000 + S0,
    D = S1 div ?SECS_PER_DAY,
    S = S1 rem ?SECS_PER_DAY,
    Ms = S*1000 + (Us  div 1000),
    Days = D + (?DAYS_FROM_0_TO_1970 - ?DAYS_FROM_0_TO_1984),
    #time_of_day { ms = Ms, days = Days }.

%% To be used ??
%% time_of_day_to_now(T) when is_record(T, time_of_day)  ->
%%     D = T#time_of_day.days + (?DAYS_FROM_0_TO_1984-?DAYS_FROM_0_TO_1970),
%%     Sec = D*?SECS_PER_DAY + (T#time_of_day.ms div 1000),
%%     USec = (T#time_of_day.ms rem 1000)*1000,
%%     {Sec div 1000000, Sec rem 1000000, USec}.

%% Use short nodeid if available
id(_Ctx=#co_ctx {nodeid = NodeId}) when NodeId =/= undefined ->
    {nodeid, NodeId};
id(_Ctx=#co_ctx {xnodeid = XNodeId}) when XNodeId =/= undefined ->
    {xnodeid, XNodeId}.


