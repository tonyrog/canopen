%%%------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Malotte W Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
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
-include("canopen.hrl").
-include("co_app.hrl").
-include("co_debug.hrl").

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2,
	 code_change/3]).

%% Application interface
-export([notify/4]). %% To send MPOs
-export([subscribers/2]).
-export([reserver_with_module/2]).
-export([tpdo_mapping/2, 
	 rpdo_mapping/2, 
	 tpdo_data/4]).

-import(lists, [foreach/2, reverse/1, seq/2, map/2, foldl/3]).

-define(LAST_SAVED_FILE, "last.dict").

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Send notification (from CobId). <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec notify(CobId::integer(), Ix::integer(), Si::integer(), Data::binary()) -> 
		    ok | {error, Error::atom()}.

notify(CobId,Index,Subind,Data)
  when ?is_index(Index), ?is_subind(Subind), is_binary(Data) ->
    FrameID = ?COBID_TO_CANID(CobId),
    Frame = #can_frame { id=FrameID, len=0, 
			 data=(<<16#80,Index:16/little,Subind:8,Data:4/binary>>) },
    ?dbg(node, "notify: Sending frame ~p from CobId = ~.16#, CanId = ~.16#)",
	 [Frame, CobId, FrameID]),
    can:send(Frame).


%%--------------------------------------------------------------------
%% @doc
%% Get the RPDO mapping. <br/>
%% Executing in calling process context.<br/>
%% @end
%%--------------------------------------------------------------------
-spec rpdo_mapping(Offset::integer(), Ctx::record()) -> 
			  Map::term() | {error, Error::atom()}.

rpdo_mapping(Offset, Ctx) ->
    pdo_mapping(Offset+?IX_RPDO_MAPPING_FIRST, Ctx).

%%--------------------------------------------------------------------
%% @doc
%% Get the TPDO mapping. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec tpdo_mapping(Offset::integer(), Ctx::record()) -> 
			  Map::term() | {error, Error::atom()}.

tpdo_mapping(Offset, Ctx) ->
    pdo_mapping(Offset+?IX_TPDO_MAPPING_FIRST, Ctx).

%%--------------------------------------------------------------------
%% @doc
%% Get all subscribers in Tab for Index. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec subscribers(Tab::reference(), Index::integer()) -> 
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
-spec reserver_with_module(Tab::reference(), Index::integer()) -> 
				  {Pid::pid(), Mod::atom()} | [].

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
		  {ok, Context::record()} |
		  {ok, Context::record(), Timeout::integer()} |
		  ignore               |
		  {stop, Reason::atom()}.


init({Serial, NodeName, Opts} = Args) ->
    error_logger:info_msg("~p: init: args = ~p,\n pid = ~p\n", [?MODULE, Args, self()]),

    %% Trace output enable/disable
    put(dbg, proplists:get_value(debug,Opts,false)), 

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
      timeout         = proplists:get_value(sdo_timeout,Opts,1000),
      blk_timeout     = proplists:get_value(blk_timeout,Opts,500),
      pst             = proplists:get_value(pst,Opts,16),
      max_blksize     = proplists:get_value(max_blksize,Opts,74),
      use_crc         = proplists:get_value(use_crc,Opts,true),
      readbufsize     = proplists:get_value(readbufsize,Opts,1024),
      load_ratio      = proplists:get_value(load_ratio,Opts,0.5),
      atomic_limit    = proplists:get_value(atomic_limit,Opts,1024),
      debug           = proplists:get_value(debug,Opts,false),
      dict            = Dict,
      sub_table       = SubTable,
      res_table       = ResTable
     },
    TpdoCtx = #tpdo_ctx {
      nodeid          = ShortNodeId,
      dict            = Dict,
      tpdo_cache      = TpdoCache,
      res_table       = ResTable
     },
    CobTable = create_cob_table(ExtNodeId, ShortNodeId),
    Ctx = #co_ctx {
      xnodeid = ExtNodeId,
      nodeid = ShortNodeId,
      name   = NodeName,
      vendor = proplists:get_value(vendor,Opts,0),
      serial = Serial,
      state  = ?Initialisation,
      node_map = ets:new(co_node_map, [{keypos,1}]),
      nmt_table = ets:new(co_nmt_table, [{keypos,#nmt_entry.id}]),
      sub_table = SubTable,
      res_table = ResTable,
      xnot_table = XNotTable,
      dict = Dict,
      mpdo_dispatch = MpdoDispatch,
      tpdo_cache = TpdoCache,
      tpdo_cache_limit = proplists:get_value(tpdo_cache_limit,Opts,512),
      tpdo = TpdoCtx,
      cob_table = CobTable,
      app_list = [],
      tpdo_list = [],
      toggle = 0,
      data = [],
      sdo  = SdoCtx,
      sdo_list = [],
      time_stamp_time = proplists:get_value(time_stamp, Opts, 60000)
     },

    can_router:attach(),

    case load_dict_init(proplists:get_value(dict_file, Opts), 
			proplists:get_value(load_last_saved, Opts, true), 
			Ctx) of
	{ok, Ctx1} ->
	    process_flag(trap_exit, true),
	    if ShortNodeId =:= 0 ->
		    {ok, Ctx1#co_ctx { state = ?Operational }};
	       true ->
		    {ok, reset_application(Ctx1)}
		end;
	{error, Reason} ->
	    error_logger:error_msg(" ~p: Loading of dict failed, reason = ~p, "
				   "exiting.\n", [NodeName, Reason]),
	    {stop, Reason}
    end.

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
reset_application(Ctx=#co_ctx {name=Name, nodeid=SNodeId, xnodeid=XNodeId}) ->
    error_logger:info_msg("Node '~s' id=~w,~w reset_application\n", 
	      [Name, XNodeId, SNodeId]),
    reset_communication(Ctx).

reset_communication(Ctx=#co_ctx {name=Name, nodeid=SNodeId, xnodeid=XNodeId}) ->
    error_logger:info_msg("Node '~s' id=~w,~w reset_communication\n",
	      [Name, XNodeId, SNodeId]),
    initialization(Ctx).

initialization(Ctx=#co_ctx {name=Name, nodeid=SNodeId, xnodeid=XNodeId}) ->
    error_logger:info_msg("Node '~s' id=~w,~w initialization\n",
	      [Name, XNodeId, SNodeId]),

    %% ??
    if XNodeId =/= undefined ->
	    can:send(#can_frame { id = ?NODE_GUARD_ID(add_xflag(XNodeId)),
				  len = 1, data = <<0>> });
       true ->
	    do_nothing
    end,
    if SNodeId =/= undefined ->
	    can:send(#can_frame { id = ?NODE_GUARD_ID(SNodeId),
				  len = 1, data = <<0>> });
       true ->
	    do_nothing
    end,
	   
    Ctx#co_ctx { state = ?PreOperational }.


%%--------------------------------------------------------------------
%% @private
%% @spec handle_call(Request, From, Context) -> {reply, Reply, Context} |  
%%                                            {reply, Reply, Context, Timeout} |
%%                                            {noreply, Context} |
%%                                            {noreply, Context, Timeout} |
%%                                            {stop, Reason, Reply, Context} |
%%                                            {stop, Reason, Context}
%% Request = {set, Index, SubInd, Value} | 
%%           {direct_set, Index, SubInd, Value} | 
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

handle_call({set,{Ix,Si},Value}, _From, Ctx) ->
    {Reply,Ctx1} = set_dict_value(Ix,Si,Value,Ctx),
    {reply, Reply, Ctx1};
handle_call({tpdo_set,I,Value,Mode}, _From, Ctx) ->
    {Reply,Ctx1} = tpdo_set(I,Value,Mode,Ctx),
    {reply, Reply, Ctx1};
handle_call({direct_set,{Ix,Si},Value}, _From, Ctx) ->
    {Reply,Ctx1} = direct_set_dict_value(Ix,Si,Value,Ctx),
    {reply, Reply, Ctx1};
handle_call({value,{Ix, Si}}, _From, Ctx) ->
    Result = co_dict:value(Ctx#co_ctx.dict, Ix, Si),
    {reply, Result, Ctx};

handle_call({Action,Mode,NodeId,Ix,Si,Term}, From, 
	    Ctx=#co_ctx {name = _Name, sdo_list = Sessions, sdo = SdoCtx}) 
  when Action == store;
       Action == fetch ->
    Nid = complete_nodeid(NodeId),
    case lookup_sdo_server(Nid,Ctx) of
	ID={Tx,Rx} ->
	    ?dbg(node, "~s: ~p: ID = ~p", [_Name,Action,ID]),
	    case lists:keyfind(Nid, #sdo.dest_node, Sessions) of
		false ->
		    %% OK to start new session
		    case co_sdo_cli_fsm:Action(SdoCtx,Mode,From,Tx,Rx,Ix,Si,Term) of
			{error, Reason} ->
			    ?dbg(node,"~s: ~p: unable to start co_sdo_cli_fsm: ~p", 
				 [_Name, Action, Reason]),
			    {reply, Reason, Ctx};
			{ok, Pid} ->
			    Mon = erlang:monitor(process, Pid),
			    sys:trace(Pid, true),
			    S = #sdo { dest_node = Nid, id=ID, pid=Pid, mon=Mon },
			    ?dbg(node, "~s: ~p: added session id=~p", 
				 [_Name, Action, ID]),
			    {noreply, Ctx#co_ctx { sdo_list = [S|Sessions]}}
		    end;
		_Found ->
		    ?dbg(node, "~s: ~p: Session already in progress to ~.16.0#", 
			 [_Name, Action, Nid]),
		    {reply, {error, session_already_in_progress}, Ctx}
	    end;
	undefined ->
	    ?dbg(node, "~s: ~p: No sdo server found for node ~.16.0#.", 
		 [_Name, Action, Nid]),
	    {reply, {error, badarg}, Ctx}
    end;

handle_call({add_entry,Entry}, _From, Ctx) when is_record(Entry, dict_entry) ->
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
			 co_lib:serial_to_string(Serial) ++ ?LAST_SAVED_FILE),
    handle_call({load_dict, File}, From, Ctx);
handle_call({load_dict, File}, _From, Ctx) ->
    ?dbg(node, "~s: handle_call: load_dict, file = ~p", [Ctx#co_ctx.name, File]),    
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
			 co_lib:serial_to_string(Serial) ++ ?LAST_SAVED_FILE),
    handle_call({save_dict, File}, From, Ctx);
handle_call({save_dict, File}, _From, Ctx=#co_ctx {dict = Dict}) ->
    ?dbg(node, "~s: handle_call: save_dict, file = ~p", [Ctx#co_ctx.name, File]),    
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
    ?dbg(node, "~s: handle_call: xnot_subscribe index = ~.16.0#-~.16.0# pid = ~p",  
	 [_Name, Ix1, Ix2, Pid]),    
    Res = add_subscription(Ctx#co_ctx.xnot_table, Ix1, Ix2, Pid),
    {reply, Res, Ctx};

handle_call({xnot_subscribe,Ix,Pid}, _From, Ctx=#co_ctx {name = _Name})
  when is_pid(Pid) ->
    ?dbg(node, "~s: handle_call: xnot_subscribe index = ~.16.0# pid = ~p",  
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

handle_call({dump, Qualifier}, _From, Ctx) ->
    io:format("   NAME: ~p\n", [Ctx#co_ctx.name]),
    print_nodeid(" NODEID:", Ctx#co_ctx.nodeid),
    print_nodeid("XNODEID:", Ctx#co_ctx.xnodeid),
    io:format(" VENDOR: ~10.16.0#\n", [Ctx#co_ctx.vendor]),
    io:format(" SERIAL: ~10.16.0#\n", [Ctx#co_ctx.serial]),
    io:format("  STATE: ~s\n", [co_format:state(Ctx#co_ctx.state)]),

    io:format("---- NMT TABLE ----\n"),
    ets:foldl(
      fun(E,_) ->
	      io:format("  ID: ~w\n", 
			[E#nmt_entry.id]),
	      io:format("    VENDOR: ~10.16.0#\n", 
			[E#nmt_entry.vendor]),
	      io:format("    SERIAL: ~10.16.0#\n", 
			[E#nmt_entry.serial]),
	      io:format("     STATE: ~s\n", 
			[co_format:state(E#nmt_entry.state)])
      end, ok, Ctx#co_ctx.nmt_table),
    io:format("---- NODE MAP TABLE ----\n"),
    ets:foldl(
      fun({Sn,NodeId},_) ->
	      io:format("~10.16.0# => ~w\n", [Sn, NodeId])
      end, ok, Ctx#co_ctx.node_map),
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
				io:format("[~7.16.0#-~7.16.0#]\n", [IxStart, IxEnd]);
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
				io:format("[~7.16.0#-~7.16.0#]\n", [IxStart, IxEnd]);
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
    io:format("  DEBUG: ~p\n", [get(dbg)]),
    {reply, ok, Ctx};

handle_call(loop_data, _From, Ctx) ->
    io:format("  LoopData: ~p\n", [Ctx]),
    {reply, ok, Ctx};

handle_call({option, Option}, _From, Ctx) ->
    Reply = case Option of
		name -> {Option, Ctx#co_ctx.name};
		nodeid -> {Option, Ctx#co_ctx.nodeid};
		xnodeid -> {Option, Ctx#co_ctx.xnodeid};
		id -> if Ctx#co_ctx.nodeid =/= undefined ->
			      {nodeid, Ctx#co_ctx.nodeid};
			 true ->
			      {xnodeid, Ctx#co_ctx.xnodeid}
		      end;
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
		debug -> {Option, Ctx#co_ctx.sdo#sdo_ctx.debug};
		_Other -> {error, "Unknown option " ++ atom_to_list(Option)}
	    end,
    ?dbg(node, "~s: handle_call: option = ~p, reply = ~w", 
	 [Ctx#co_ctx.name, Option, Reply]),    
    {reply, Reply, Ctx};
handle_call({option, Option, NewValue}, _From, Ctx) ->
    ?dbg(node, "~s: handle_call: option = ~p, new value = ~p", 
	 [Ctx#co_ctx.name, Option, NewValue]),    
    Reply = case Option of
		name -> Ctx#co_ctx {name = NewValue}; %% Reg new name ??
		sdo_timeout -> Ctx#co_ctx.sdo#sdo_ctx {timeout = NewValue};
		blk_timeout -> Ctx#co_ctx.sdo#sdo_ctx {blk_timeout = NewValue};
		pst ->  Ctx#co_ctx.sdo#sdo_ctx {pst = NewValue};
		max_blksize -> Ctx#co_ctx.sdo#sdo_ctx {max_blksize = NewValue};
		use_crc -> Ctx#co_ctx.sdo#sdo_ctx {use_crc = NewValue};
		readbufsize -> Ctx#co_ctx.sdo#sdo_ctx {readbufsize = NewValue};
		load_ratio -> Ctx#co_ctx.sdo#sdo_ctx {load_ratio = NewValue};
		atomic_limit -> Ctx#co_ctx.sdo#sdo_ctx {atomic_limit = NewValue};
		time_stamp -> Ctx#co_ctx {time_stamp_time = NewValue};
		debug -> put(dbg, NewValue),
			 Ctx#co_ctx.sdo#sdo_ctx {debug = NewValue};
		NodeId when
		      NodeId == nodeid;
		      NodeId == xnodeid;
		      NodeId == use_serial_as_xnodeid -> 
		    change_nodeid(Option, NewValue, Ctx);
		_Other -> {error, "Unknown option " ++ atom_to_list(Option)}
	    end,
    case Reply of
	SdoCtx when is_record(SdoCtx, sdo_ctx) ->
	    {reply, ok, Ctx#co_ctx {sdo = SdoCtx}};
	NewCtx when is_record(NewCtx, co_ctx) ->
	    {reply, ok, NewCtx};
	{error, _Reason} ->
	    {reply, Reply, Ctx}
    end;
handle_call(stop, _From, Ctx) ->
    {stop, normal, ok, Ctx};

handle_call({state, State}, _From, Ctx) ->
    broadcast_state(State, Ctx),
    {reply, ok, Ctx#co_ctx {state = State}};

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
handle_cast({object_event, {Ix, _Si}}, Ctx) ->
    ?dbg(node, "~s: handle_cast: object_event, index = ~.16B:~p", 
	 [Ctx#co_ctx.name, Ix, _Si]),
    inform_subscribers(Ix, Ctx),
    {noreply, Ctx};
handle_cast({pdo_event, CobId}, Ctx) ->
    ?dbg(node, "~s: handle_cast: pdo_event, CobId = ~.16B", 
	 [Ctx#co_ctx.name, CobId]),
    case lists:keysearch(CobId, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
	{value, T} ->
	    co_tpdo:transmit(T#tpdo.pid),
	    {noreply,Ctx};
	_ ->
	    ?dbg(node, "~s: handle_cast: pdo_event, no tpdo process found", 
		 [Ctx#co_ctx.name]),
	    {noreply,Ctx}
    end;
handle_cast({dam_mpdo_event, CobId, Destination}, Ctx) ->
    ?dbg(node, "~s: handle_cast: dam_mpdo_event, CobId = ~.16B", 
	 [Ctx#co_ctx.name, CobId]),
    case lists:keysearch(CobId, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
	{value, T} ->
	    co_tpdo:transmit(T#tpdo.pid, Destination), %% ??
	    {noreply,Ctx};
	_ ->
	    ?dbg(node, "~s: handle_cast: pdo_event, no tpdo process found", 
		 [Ctx#co_ctx.name]),
	    {noreply,Ctx}
    end;
handle_cast(_Msg, Ctx) ->
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% Function: handle_info(Info, Context) -> {noreply, Context} |
%%                                       {noreply, Context, Timeout} |
%%                                       {stop, Reason, Context}
%% Description: Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------
handle_info(Frame, Ctx) 
  when is_record(Frame, can_frame) ->
    ?dbg(node, "~s: handle_info: CAN frame received", [Ctx#co_ctx.name]),
    Ctx1 = handle_can(Frame, Ctx),
    {noreply, Ctx1};

handle_info({timeout,Ref,sync}, Ctx) 
  when Ref =:= Ctx#co_ctx.sync_tmr ->
    %% Send a SYNC frame
    %% FIXME: check that we still are sync producer?
    ?dbg(node, "~s: handle_info: sync timeout received", [Ctx#co_ctx.name]),
    FrameID = ?COBID_TO_CANID(Ctx#co_ctx.sync_id),
    Frame = #can_frame { id=FrameID, len=0, data=(<<>>) },
    can:send(Frame),
    ?dbg(node, "~s: handle_info: Sent sync", [Ctx#co_ctx.name]),
    Ctx1 = Ctx#co_ctx { sync_tmr = start_timer(Ctx#co_ctx.sync_time, sync) },
    {noreply, Ctx1};

handle_info({timeout,Ref,time_stamp}, Ctx) 
  when Ref =:= Ctx#co_ctx.time_stamp_tmr ->
    %% FIXME: Check that we still are time stamp producer
    ?dbg(node, "~s: handle_info: time_stamp timeout received", [Ctx#co_ctx.name]),
    FrameID = ?COBID_TO_CANID(Ctx#co_ctx.time_stamp_id),
    Time = time_of_day(),
    Data = co_codec:encode(Time, ?TIME_OF_DAY),
    Size = byte_size(Data),
    Frame = #can_frame { id=FrameID, len=Size, data=Data },
    can:send(Frame),
    ?dbg(node, "~s: handle_info: Sent time stamp ~p", [Ctx#co_ctx.name, Time]),
    Ctx1 = Ctx#co_ctx { time_stamp_tmr = start_timer(Ctx#co_ctx.time_stamp_time, time_stamp) },
    {noreply, Ctx1};

handle_info({rc_reset, Pid}, Ctx=#co_ctx {name = _Name, tpdo_list = TList}) ->
    ?dbg(node, "~s: handle_info: rc_reset for process ~p received",  [_Name, Pid]),
    case lists:keysearch(Pid, #tpdo.pid, TList) of
	{value,T} -> 
	    NewT = T#tpdo {rc = 0},
	    ?dbg(node, "~s: handle_info: rc counter cleared",  [_Name]),
	    {noreply, Ctx#co_ctx { tpdo_list = [NewT | TList]--[T]}};
	false -> 
	    ?dbg(node, "~s: handle_info: rc_reset no process found", [_Name]),
	    {noreply, Ctx}
    end;

    
handle_info({'DOWN',Ref,process,_Pid,Reason}, Ctx) ->
    ?dbg(node, "~s: handle_info: DOWN for process ~p received", 
	 [Ctx#co_ctx.name, _Pid]),
    Ctx1 = handle_sdo_processes(Ref, Reason, Ctx),
    Ctx2 = handle_app_processes(Ref, Reason, Ctx1),
    Ctx3 = handle_tpdo_processes(Ref, Reason, Ctx2),
    {noreply, Ctx3};

handle_info({'EXIT', Pid, Reason}, Ctx) ->
    ?dbg(node, "~s: handle_info: EXIT for process ~p received", 
	 [Ctx#co_ctx.name, Pid]),
    Ctx1 = handle_sdo_processes(Pid, Reason, Ctx),
    Ctx2 = handle_app_processes(Pid, Reason, Ctx1),
    Ctx3 = handle_tpdo_processes(Pid, Reason, Ctx2),

    case Ctx3 of
	Ctx ->
	    %% No 'normal' linked process died, we should termiate ??
	    ?dbg(node, "~s: handle_info: linked process ~p died, reason ~p, "
		 "terminating\n", [Ctx#co_ctx.name, Pid, Reason]),
	    {stop, Reason, Ctx};
	_ChangedCtx ->
	    %% 'Normal' linked process died, ignore
	    {noreply, Ctx3}
    end;

handle_info(_Info, Ctx) ->
    ?dbg(node, "~s: handle_info: unknown info received", [Ctx#co_ctx.name]),
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
terminate(_Reason, Ctx) ->
    
    %% Stop all apps ??
    lists:foreach(
      fun(A) ->
	      case A#app.pid of
		  Pid -> 
		      ?dbg(node, "~s: terminate: Killing app with pid = ~p", 
			   [Ctx#co_ctx.name, Pid]),
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
		      ?dbg(node, "~s: terminate: Killing TPDO with pid = ~p", 
			   [Ctx#co_ctx.name, Pid]),
			  %% Or gen_server:cast(Pid, co_node_terminated) ?? 
		      exit(Pid, co_node_terminated)
	      end
      end,
      Ctx#co_ctx.tpdo_list),

    case co_proc:alive() of
	true -> co_proc:clear();
	false -> do_nothing
    end,
   ?dbg(node, "~s: terminate: cleaned up, exiting", [Ctx#co_ctx.name]),
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
    add_to_cob_table(T, xnodeid, add_xflag(ExtNid)),
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
    ?dbg(node, "add_to_cob_table: XNid=~w, XSDORx=~w, XSDOTx=~w", 
	 [ExtNid,XSDORx,XSDOTx]);
add_to_cob_table(T, nodeid, ShortNid) 
  when ShortNid =/= undefined->
    ?dbg(node, "add_to_cob_table: ShortNid=~w", [ShortNid]),
    SDORx = ?COB_ID(?SDO_RX,ShortNid),
    SDOTx = ?COB_ID(?SDO_TX,ShortNid),
    ets:insert(T, {SDORx, {sdo_rx, SDOTx}}),
    ets:insert(T, {SDOTx, {sdo_tx, SDORx}}),
    ets:insert(T, {?COB_ID(?NMT, 0), nmt}),
    ?dbg(node, "add_to_cob_table: SDORx=~w, SDOTx=~w", [SDORx,SDOTx]).


delete_from_cob_table(_T, _NidType, undefined) ->
    ok;
delete_from_cob_table(T, xnodeid, Nid)
  when Nid =/= undefined ->
    ExtNid = add_xflag(Nid),
    XSDORx = ?XCOB_ID(?SDO_RX,ExtNid),
    XSDOTx = ?XCOB_ID(?SDO_TX,ExtNid),
    ets:delete(T, XSDORx),
    ets:delete(T, XSDOTx),
    ets:delete(T, ?XCOB_ID(?NMT,0)),
    ?dbg(node, "delete_from_cob_table: XNid=~w, XSDORx=~w, XSDOTx=~w", 
	 [ExtNid,XSDORx,XSDOTx]);
delete_from_cob_table(T, nodeid, ShortNid)
  when ShortNid =/= undefined->
    SDORx = ?COB_ID(?SDO_RX,ShortNid),
    SDOTx = ?COB_ID(?SDO_TX,ShortNid),
    ets:delete(T, SDORx),
    ets:delete(T, SDOTx),
    ets:delete(T, ?COB_ID(?NMT,0)),
    ?dbg(node, "delete_from_cob_table: ShortNid=~w, SDORx=~w, SDOTx=~w", 
	 [ShortNid,SDORx,SDOTx]).


change_nodeid(xnodeid, NewXNid, Ctx=#co_ctx {xnodeid = NewXNid}) ->
    %% No change
    Ctx;
change_nodeid(xnodeid, undefined, _Ctx=#co_ctx {nodeid = undefined}) -> 
    {error, "Not possible to remove last nodeid"};
change_nodeid(xnodeid, NewNid, Ctx=#co_ctx {xnodeid = OldNid}) ->
    execute_change(xnodeid, NewNid, OldNid, Ctx),
    Ctx#co_ctx {xnodeid = NewNid};
change_nodeid(nodeid, NewNid, Ctx=#co_ctx {nodeid = NewNid}) ->
    %% No change
    Ctx;
change_nodeid(nodeid, undefined, _Ctx=#co_ctx {xnodeid = undefined}) -> 
    {error, "Not possible to remove last nodeid"};
change_nodeid(nodeid, 0, _Ctx) ->
    {error, "NodeId 0 is reserved for the CANopen manager co_mgr."};
change_nodeid(nodeid, NewNid, Ctx=#co_ctx {nodeid = OldNid}) ->
    execute_change(nodeid, NewNid, OldNid, Ctx),
    Ctx#co_ctx {nodeid = NewNid};
change_nodeid(use_serial_as_xnodeid, true, Ctx=#co_ctx {serial = Serial}) ->
    NewXNid = co_lib:serial_to_xnodeid(Serial),
    change_nodeid(xnodeid, NewXNid, Ctx);
change_nodeid(use_serial_as_xnodeid, false, Ctx) ->
    case  calc_use_serial(Ctx) of
	true ->
	    %% Serial was used as extended node id
	    change_nodeid(xnodeid, undefined, Ctx);
	false ->
	    %% Serial was NOT used as nodeid so flag was already false
	    Ctx
    end.

execute_change(NidType, NewNid, OldNid, Ctx=#co_ctx { cob_table = T}) ->  
    ?dbg(node, "execute_change: NidType = ~p, OldNid = ~p, NewNid = ~p", 
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
load_dict_init(undefined, true, Ctx=#co_ctx {serial = Serial}) ->
    File = filename:join(code:priv_dir(canopen), 
			 co_lib:serial_to_string(Serial) ++ ?LAST_SAVED_FILE),
    case filelib:is_regular(File) of
	true -> load_dict_init(File, true, Ctx);
	false -> {ok, Ctx}
    end;
load_dict_init(undefined, false, Ctx) ->
    %% ??
    {ok, Ctx};
load_dict_init(File, _Flag, Ctx) when is_list(File) ->
    load_dict_internal(filename:join(code:priv_dir(canopen), File), Ctx); 
load_dict_init(File, _Flag, Ctx) when is_atom(File) ->
    load_dict_internal(filename:join(code:priv_dir(canopen), atom_to_list(File)), Ctx). 

load_dict_internal(File, Ctx=#co_ctx {dict = Dict, name = _Name}) ->
    ?dbg(node, "~s: load_dict_internal: Loading file = ~p", 
	 [_Name, File]),
    try co_file:load(File) of
	{ok,Os} ->
	    %% Install all objects
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
			  {Ixs, _SubIxs} = lists:unzip(ChangedEIxs),
			  OIxs ++ lists:usort(Ixs)
		  end, [], Os),

	    %% Now take action if needed
	    ?dbg(node, "~s: load_dict_internal: changed entries ~p", 
		 [_Name, ChangedIxs]),
	    Ctx1 = 
		foldl(fun(I, Ctx0) ->
			      handle_notify(I, Ctx0)
		      end, Ctx, ChangedIxs),

	    {ok, Ctx1};
	Error ->
	    ?dbg(node, "~s: load_dict_internal: Failed loading file, error = ~p", 
		 [_Name, Error]),
	    Error
    catch
	error:Reason ->
	    ?dbg(node, "~s: load_dict_internal: Failed loading file, reason = ~p", 
		 [_Name, Reason]),

	    {error, Reason}
    end.

%%
%% Update dictionary
%% Only valid for 'local' objects
%%
set_dict_object({O,Es}, Ctx) when is_record(O, dict_object) ->
    lists:foreach(fun(E) -> ets:insert(Ctx#co_ctx.dict, E) end, Es),
    ets:insert(Ctx#co_ctx.dict, O),
    I = O#dict_object.index,
    handle_notify(I, Ctx).

set_dict_entry(E, Ctx) when is_record(E, dict_entry) ->
    {I,_} = E#dict_entry.index,
    ets:insert(Ctx#co_ctx.dict, E),
    handle_notify(I, Ctx).

set_dict_value(Ix,Si,Value,Ctx) ->
    try co_dict:set_value(Ctx#co_ctx.dict, Ix,Si,Value) of
	ok -> {ok, handle_notify(Ix, Ctx)};
	Error -> {Error, Ctx}
    catch
	error:Reason -> {{error,Reason}, Ctx}
    end.


direct_set_dict_value(Ix,Si,Value,Ctx) ->
    ?dbg(node, "~s: direct_set_dict_value: Ix = ~.16#:~w, Value = ~p",
	 [Ctx#co_ctx.name, Ix, Si, Value]), 
    try co_dict:direct_set_value(Ctx#co_ctx.dict, Ix,Si,Value) of
	ok -> {ok, handle_notify(Ix, Ctx)};
	Error -> {Error, Ctx}
    catch
	error:Reason -> {{error,Reason}, Ctx}
    end.


%%
%% Handle can messages
%%
handle_can(Frame, Ctx) when ?is_can_frame_rtr(Frame) ->
    COBID = ?CANID_TO_COBID(Frame#can_frame.id),
    ?dbg(node, "~s: handle_can: (rtr) COBID=~8.16.0B", [Ctx#co_ctx.name, COBID]),
    case lookup_cobid(COBID, Ctx) of
	nmt  ->
	    %% Handle Node guard
	    Ctx;

	_Other ->
	    case lists:keysearch(COBID, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
		{value, T} ->
		    co_tpdo:rtr(T#tpdo.pid),
		    Ctx;
		_ -> 
		    Ctx
	    end
    end;
handle_can(Frame, Ctx=#co_ctx {state = State, name = _Name}) ->
    COBID = ?CANID_TO_COBID(Frame#can_frame.id),
    ?dbg(node, "~s: handle_can: COBID=~8.16.0B", [_Name, COBID]),
    case lookup_cobid(COBID, Ctx) of
	nmt        -> handle_nmt(Frame, Ctx);
	sync       -> handle_sync(Frame, Ctx);
	emcy       -> handle_emcy(Frame, Ctx);
	time_stamp -> handle_time_stamp(Frame, Ctx);
	node_guard -> handle_node_guard(Frame, Ctx);
	lss        -> handle_lss(Frame, Ctx);
	{rpdo,Offset} -> handle_rpdo(Frame, Offset, COBID, Ctx);
	{sdo_tx,Rx} ->
	    if State=:= ?Operational; 
	       State =:= ?PreOperational ->	    
		    handle_sdo_tx(Frame, COBID, Rx, Ctx);
	       true ->
		    Ctx
	    end;
	{sdo_rx,Tx} ->
	    if State=:= ?Operational; 
	       State =:= ?PreOperational ->	    
		    handle_sdo_rx(Frame, COBID, Tx, Ctx);
	       true ->
		    Ctx
	    end;
	_AssumedMpdo ->
	    case Frame#can_frame.data of
		%% Test if MPDO
		<<F:1, Addr:7, Ix:16/little, Si:8, Data:4/binary>> ->
		    case {F, Addr} of
			{1, 0} ->
			    %% DAM-MPDO, destination is a group
			    handle_dam_mpdo(Ctx, COBID, {Ix, Si}, Data),
			    extended_notify(Ctx, Ix, Frame);
			{1, Nid} when Nid == Ctx#co_ctx.nodeid ->
			    %% DAM-MPDO, destination is this node
			    handle_dam_mpdo(Ctx, COBID, {Ix, Si}, Data),
			    extended_notify(Ctx, Ix, Frame);
			{1, _OtherNid} ->
			    %% DAM-MPDO, destination is some other node
			    ?dbg(node, "~s: handle_can: DAM-MPDO: destination is "
				 "other node = ~.16.0#", [_Name, _OtherNid]),
			    Ctx;
			{0, 0} ->
			    %% Reserved
			    ?dbg(node, "~s: handle_can: SAM-MPDO: Addr = 0, reserved "
				 "Frame = ~w", [_Name, Frame]),
			    Ctx;
			    %% Temporary fix for fault in seasone rc
			    %% handle_dam_mpdo(Ctx, COBID, {Ix, Si}, Data),
			    %% extended_notify(Ctx, Ix, Frame);
			{0, SourceNid} ->
			    handle_sam_mpdo(Ctx, SourceNid, {Ix, Si}, Data)
		    end;
		_Other ->
		    ?dbg(node, "~s: handle_can: frame not handled: Frame = ~w", 
			 [_Name, Frame]),
		    Ctx
	    end
    end.

%%
%% NMT 
%%
handle_nmt(M, Ctx=#co_ctx {nodeid=SNodeId, xnodeid=XNodeId, name=_Name}) 
  when M#can_frame.len >= 2 ->
    ?dbg(node, "~s: handle_nmt: ~p", [_Name, M]),
    <<NodeId,Cs,_/binary>> = M#can_frame.data,
    XNid = add_xflag(XNodeId),
    if NodeId == 0; 
       NodeId == XNid; 
       NodeId == SNodeId ->
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
		    ?dbg(node, "~s: handle_nmt: unknown cs=~w", 
			 [_Name, Cs]),
		    Ctx
	    end;
       true ->
	    %% not for me
	    Ctx
    end.


handle_node_guard(Frame, Ctx=#co_ctx {nodeid=SNodeId, xnodeid=XNodeId, name=_Name}) 
  when ?is_can_frame_rtr(Frame) ->
    ?dbg(node, "~s: handle_node_guard: request ~w", [_Name,Frame]),
    NodeId = ?NODE_ID(Frame#can_frame.id),
    XNid = add_xflag(XNodeId),
    if NodeId == 0; 
       NodeId == SNodeId;
       NodeId == XNid ->
	    Data = Ctx#co_ctx.state bor Ctx#co_ctx.toggle,
	    if XNodeId =/= undefined ->
		    can:send(#can_frame { id = ?NODE_GUARD_ID(add_xflag(XNodeId)),
					  len = 1,
					  data = <<Data>> });
	       true ->
		    do_nothing
	    end,
	    if SNodeId =/= undefined ->
		    can:send(#can_frame { id = ?NODE_GUARD_ID(SNodeId),
					  len = 1,
					  data = <<Data>> });
	       true ->
		    do_nothing
	    end,
	    Toggle = Ctx#co_ctx.toggle bxor 16#80,
	    Ctx#co_ctx { toggle = Toggle };
       true ->
	    %% ignore, not for me
	    Ctx
    end;
handle_node_guard(Frame, Ctx) when Frame#can_frame.len >= 1 ->
    ?dbg(node, "~s: handle_node_guard: ~w", [Ctx#co_ctx.name,Frame]),
    NodeId = ?NODE_ID(Frame#can_frame.id),
    XNid = add_xflag(Ctx#co_ctx.xnodeid),
    case Frame#can_frame.data of
	<<_Toggle:1, State:7, _/binary>> 
	  when (NodeId =/= XNid andalso
		NodeId =/= Ctx#co_ctx.nodeid) ->
	    %% Verify toggle if NodeId=slave and we are Ctx#co_ctx.xnodeid=master
	    update_nmt_entry(NodeId, [{state,State}], Ctx);
	_ ->
	    Ctx
    end.

%%
%% LSS
%% 
handle_lss(_M, Ctx) ->
    ?dbg(node, "~s: handle_lss: ~w", [Ctx#co_ctx.name,_M]),
    Ctx.

%%
%% SYNC
%%
handle_sync(_Frame, Ctx) ->
    ?dbg(node, "~s: handle_sync: ~w", [Ctx#co_ctx.name,_Frame]),
    lists:foreach(
      fun(T) -> co_tpdo:sync(T#tpdo.pid) end, Ctx#co_ctx.tpdo_list),
    Ctx.

%%
%% TIME STAMP - update local time offset
%%
handle_time_stamp(Frame, Ctx) ->
    ?dbg(node, "~s: handle_timestamp: ~w", [Ctx#co_ctx.name,Frame]),
    try co_codec:decode(Frame#can_frame.data, ?TIME_OF_DAY) of
	{T, _Bits} when is_record(T, time_of_day) ->
	    ?dbg(node, "~s: Got timestamp: ~p", [Ctx#co_ctx.name, T]),
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
handle_emcy(_Frame, Ctx) ->
    ?dbg(node, "~s: handle_emcy: ~w", [Ctx#co_ctx.name,_Frame]),
    Ctx.

%%
%% Recive PDO - unpack into the dictionary
%%
handle_rpdo(Frame, Offset, _COBID, Ctx) ->
    ?dbg(node, "~s: handle_rpdo: offset = ~p, frame = ~w", 
	 [Ctx#co_ctx.name, Offset, Frame]),
    rpdo_unpack(?IX_RPDO_MAPPING_FIRST + Offset, Frame#can_frame.data, Ctx).

%% CLIENT side:
%% SDO tx - here we receive can_node response
%% FIXME: conditional compile this
%%
handle_sdo_tx(Frame, Tx, Rx, Ctx) ->
    ?dbg(node, "~s: handle_sdo_tx: src=~p, ~s",
	      [Ctx#co_ctx.name, Tx,
	       co_format:format_sdo(co_sdo:decode_tx(Frame#can_frame.data))]),
    ID = {Tx,Rx},
    ?dbg(node, "~s: handle_sdo_tx: session id=~p", [Ctx#co_ctx.name, ID]),
    Sessions = Ctx#co_ctx.sdo_list,
    case lists:keysearch(ID,#sdo.id,Sessions) of
	{value, S} ->
	    gen_fsm:send_event(S#sdo.pid, Frame),
	    Ctx;
	false ->
	    ?dbg(node, "~s: handle_sdo_tx: session not found", [Ctx#co_ctx.name]),
	    %% no such session active
	    Ctx
    end.

%% SERVER side
%% SDO rx - here we receive client requests
%% FIXME: conditional compile this
%%
handle_sdo_rx(Frame, Rx, Tx, Ctx=#co_ctx {name = _Name}) ->
    ?dbg(node, "~s: handle_sdo_rx: ~s", 
	      [_Name,co_format:format_sdo(co_sdo:decode_rx(Frame#can_frame.data))]),
    ID = {Rx,Tx},
    Sessions = Ctx#co_ctx.sdo_list,
    case lists:keysearch(ID,#sdo.id,Sessions) of
	{value, S} ->
	    ?dbg(node, "~s: handle_sdo_rx: Frame sent to old process ~p", 
		 [_Name,S#sdo.pid]),
	    gen_fsm:send_event(S#sdo.pid, Frame),
	    Ctx;
	false ->
	    %% FIXME: handle expedited and spurios frames here
	    %% like late aborts etc here !!!
	    case co_sdo_srv_fsm:start(Ctx#co_ctx.sdo,Rx,Tx) of
		{error, Reason} ->
		   error_logger:warning_msg("~p: unable to start co_sdo_srv_fsm: ~p\n",
					    [_Name, Reason]),
		    Ctx;
		{ok,Pid} ->
		    Mon = erlang:monitor(process, Pid),
		    sys:trace(Pid, true),
		    ?dbg(node, "~s: handle_sdo_rx: Frame sent to new process ~p", 
			 [_Name,Pid]),		    
		    gen_fsm:send_event(Pid, Frame),
		    S = #sdo { id=ID, pid=Pid, mon=Mon },
		    Ctx#co_ctx { sdo_list = [S|Sessions]}
	    end
    end.

handle_sam_mpdo(Ctx=#co_ctx {mpdo_dispatch = MpdoDispatch, name = _Name}, 
		SourceNid, {SourceIx, SourceSi}, Data ) ->
    ?dbg(node, "~s: handle_sam_mpdo: Index = ~.16#:~w, Nid = ~.16.0#, Data = ~w", 
	 [_Name,SourceIx,SourceSi,SourceNid,Data]),
    case ets:lookup(MpdoDispatch, {SourceIx, SourceSi, SourceNid}) of
	[{{SourceIx, SourceSi, SourceNid}, LocalIndex = {_LocalIx, _LocalSi}}] ->
	    ?dbg(node, "~s: handle_sam_mpdo: Found Index = ~.16#:~w, updating", 
		 [_Name,_LocalIx,_LocalSi]),
	    rpdo_value(LocalIndex,Data,Ctx);
	[] ->
	    Ctx;
	_Other ->
	    ?dbg(node, "~s: handle_sam_mpdo: Found other ~p ", [_Name, _Other]),
	    Ctx
    end.

%%
%% DAM-MPDO
%%
handle_dam_mpdo(Ctx, _CobId, Index = {_Ix, _Si}, Data) ->
    ?dbg(node, "~s: handle_dam_mpdo: Index = ~.16#:~w", [Ctx#co_ctx.name,_Ix,_Si]),
    %% Enough ??
    rpdo_value(Index,Data,Ctx).

extended_notify(Ctx=#co_ctx {xnot_table = XNotTable, name = _Name}, Ix, Frame) ->
    case lists:usort(subscribers(XNotTable, Ix)) of
	[] ->
	    ?dbg(node, "~s: extended_notify: No xnot subscribers for index ~.16#", 
		 [_Name, Ix]);
	PidList ->
	    lists:foreach(
	      fun(Pid) ->
		      case Pid of
			  dead ->
			      %% Warning ??
			      ?dbg(node, "~s: extended_notify: Process subscribing "
				   "to index ~.16# is dead", [_Name, Ix]);
			  P when is_pid(P)->
			      ?dbg(node, "~s: extended_notify: Process ~p subscribes "
				   "to index ~.16#", [_Name, Pid, Ix]),
			      gen_server:cast(Pid, {extended_notify, Ix, Frame})
		      end
	      end, PidList)
    end,
    Ctx.
    

%%
%% Handle terminated processes
%%
handle_sdo_processes(Pid, Reason, Ctx) when is_pid(Pid) ->
    case lists:keysearch(Pid, #sdo.pid, Ctx#co_ctx.sdo_list) of
	{value,S} -> handle_sdo_process(S, Reason, Ctx);
	false ->  Ctx
    end;
handle_sdo_processes(Ref, Reason, Ctx) ->
    case lists:keysearch(Ref, #sdo.mon, Ctx#co_ctx.sdo_list) of
	{value,S} -> handle_sdo_process(S, Reason, Ctx);
	false ->  Ctx
    end.

handle_sdo_process(S, Reason, Ctx) ->
    maybe_warning(Reason, "sdo session", Ctx#co_ctx.name),
    Ctx#co_ctx { sdo_list = Ctx#co_ctx.sdo_list -- [S]}.

maybe_warning(normal, _Type, _Name) ->
    ok;
maybe_warning(Reason, Type, Name) ->
    error_logger:error_msg("~s: ~s died: ~p\n", [Name, Type, Reason]).

handle_app_processes(Pid, Reason, Ctx) when is_pid(Pid)->
    case lists:keysearch(Pid, #app.pid, Ctx#co_ctx.app_list) of
	{value,A} -> handle_app_process(A, Reason, Ctx);
	false -> Ctx
    end;
handle_app_processes(Ref, Reason, Ctx) ->
    case lists:keysearch(Ref, #app.mon, Ctx#co_ctx.app_list) of
	{value,A} -> handle_app_process(A, Reason, Ctx);
	false -> Ctx
    end.

handle_app_process(A, Reason, Ctx) ->
    error_logger:error_msg("~s: id=~w application died:~p\n", 
			   [Ctx#co_ctx.name,A#app.pid, Reason]),
    remove_subscriptions(Ctx#co_ctx.sub_table, A#app.pid), %% Or reset ??
    reset_reservations(Ctx#co_ctx.res_table, A#app.pid),
    %% FIXME: restart application? application_mod ?
    Ctx#co_ctx { app_list = Ctx#co_ctx.app_list--[A]}.

handle_tpdo_processes(Pid, Reason, Ctx) when is_pid(Pid)->
    case lists:keysearch(Pid, #tpdo.pid, Ctx#co_ctx.tpdo_list) of
	{value,T} -> handle_tpdo_process(T, Reason, Ctx);
	false -> Ctx
    end;
handle_tpdo_processes(Ref, Reason, Ctx) ->
    case lists:keysearch(Ref, #tpdo.mon, Ctx#co_ctx.tpdo_list) of
	{value,T} -> handle_tpdo_process(T, Reason, Ctx);
	false -> Ctx
    end.

handle_tpdo_process(T=#tpdo {pid = _Pid, offset = _Offset}, _Reason, 
		    Ctx=#co_ctx {name = _Name, tpdo_list = TList}) ->
    error_logger:error_msg("~s: id=~w tpdo process died: ~p\n", 
			   [_Name,_Pid, _Reason]),
    case restart_tpdo(T, Ctx) of
	{error, _Error} ->
	    error_logger:error_msg(" ~s: not possible to restart "
				   "tpdo process for offset ~p, reason = ~p\n", 
				   [_Name,_Offset,_Error]),
	    Ctx;
	NewT ->
	    ?dbg(node, "~s: handle_tpdo_processes: new tpdo process ~p started", 
		 [_Name, NewT#tpdo.pid]),
	    Ctx#co_ctx { tpdo_list = [NewT | TList]--[T]}
    end.




%%
%% NMT requests (call from within node process)
%%
set_node_state(Ctx, NodeId, State) ->
    update_nmt_entry(NodeId, [{state,State}], Ctx).

do_node_guard(Ctx, 0) ->
    foreach(
      fun(I) ->
	      update_nmt_entry(I, [{state,?UnknownState}], Ctx)
      end,
      lists:seq(0, 127)),
    send_nmt_node_guard(0);
do_node_guard(Ctx, I) when I > 0, I =< 127 ->
    update_nmt_entry(I, [{state,?UnknownState}], Ctx),
    send_nmt_node_guard(I).


send_nmt_state_change(NodeId, Cs) ->
    can:send(#can_frame { id = ?NMT_ID,
			  len = 2,
			  data = <<Cs:8, NodeId:8>>}).

send_nmt_node_guard(NodeId) ->
    ID = ?COB_ID(?NODE_GUARD,NodeId) bor ?CAN_RTR_FLAG,
    can:send(#can_frame { id = ID,
			  len = 0, data = <<>>}).

send_x_node_guard(NodeId, Cmd, Ctx) ->
    Crc = crc:checksum(<<(Ctx#co_ctx.serial):32/little>>),
    Data = <<Cmd:8, (Ctx#co_ctx.serial):32/little, Crc:16/little,
	     (Ctx#co_ctx.state):8>>,
    can:send(#can_frame { id = ?COB_ID(?NODE_GUARD,NodeId),
			  len = 8, data = Data}),
    Ctx.

%% lookup / create nmt entry
lookup_nmt_entry(NodeId, Ctx) ->
    case ets:lookup(Ctx#co_ctx.nmt_table, NodeId) of
	[] ->
	    #nmt_entry { id = NodeId };
	[E] ->
	    E
    end.

broadcast_state(State, #co_ctx {state = State, name = _Name}) ->
    %% No change
    ?dbg(node, "~s: broadcast_state: no change state = ~p", [_Name, State]),
    ok;
broadcast_state(State, Ctx=#co_ctx { name = _Name}) ->
    ?dbg(node, "~s: broadcast_state: new state = ~p", [_Name, State]),

    %% To all tpdo processes
    send_to_tpdos({state, State}, Ctx),
    
    %% To all applications ??
    send_to_apps({state, State}, Ctx).

send_to_apps(Msg, _Ctx=#co_ctx {name = _Name, app_list = AList}) ->
    lists:foreach(
      fun(A) ->
	      case A#app.pid of
		  Pid -> 
		      ?dbg(node, "~s: handle_call: sending ~w to app "
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
		      ?dbg(node, "~s: handle_call: sending ~w to tpdo "
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
    ?dbg(node, "~s: handle_notify: Index=~.16#",[_Name, I]),
    case I of
	?IX_COB_ID_SYNC_MESSAGE ->
	    update_sync(Ctx);
	?IX_COM_CYCLE_PERIOD ->
	    update_sync(Ctx);
	?IX_COB_ID_TIME_STAMP ->
	    update_time_stamp(Ctx);
	?IX_COB_ID_EMERGENCY ->
	    update_emcy(Ctx);
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
	    ?dbg(node, "~s: handle_notify: update RPDO offset=~.16#", 
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
	    ?dbg(node, "~s: handle_notify: update TPDO: offset=~.16#",
		 [_Name, I - ?IX_TPDO_PARAM_FIRST]),
	    case load_pdo_parameter(I, (I-?IX_TPDO_PARAM_FIRST), Ctx) of
		undefined -> Ctx;
		Param ->
		    case update_tpdo(Param, Ctx) of
			{new, {_T,Ctx1}} ->
			    ?dbg(node, "~s: handle_notify: TPDO:new",
				 [_Name]),
			    
			    Ctx1;
			{existing,T} ->
			    ?dbg(node, "~s: handle_notify: TPDO:existing",
				 [_Name]),
			    co_tpdo:update_param(T#tpdo.pid, Param),
			    Ctx;
			{deleted,Ctx1} ->
			    ?dbg(node, "~s: handle_notify: TPDO:deleted",
				 [_Name]),
			    Ctx1;
			none ->
			    ?dbg(node, "~s: handle_notify: TPDO:none",
				 [_Name]),
			    Ctx
		    end
	    end;
	_ when I >= ?IX_TPDO_MAPPING_FIRST, I =< ?IX_TPDO_MAPPING_LAST ->
	    Offset = I - ?IX_TPDO_MAPPING_FIRST,
	    ?dbg(node, "~s: handle_notify: update TPDO-MAP: offset=~w", 
		 [_Name, Offset]),
	    J = ?IX_TPDO_PARAM_FIRST + Offset,
	    COBID = co_dict:direct_value(Ctx#co_ctx.dict,J,?SI_PDO_COB_ID),
	    case lists:keysearch(COBID, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
		{value, T} ->
		    co_tpdo:update_map(T#tpdo.pid),
		    Ctx;
		_ ->
		    Ctx
	    end;
	_ when I >= ?IX_OBJECT_DISPATCH_FIRST, I =< ?IX_OBJECT_DISPATCH_LAST ->
	    ?dbg(node, "~s: handle_notify: update SAM-MPDO-Dispatch for index ~.16.0# ", 
		 [_Name, I]),
	    update_mpdo_disp(Ctx, I);
	_ ->
	    Ctx
    end.

update_mpdo_disp(Ctx=#co_ctx {dict = Dict, name = _Name}, I) ->
   try co_dict:direct_value(Dict,{I,0}) of
	NoOfEntries ->
	    Ixs = [{I, Si} || Si <- lists:seq(1, NoOfEntries)],
	   ?dbg(node, "~s: update_mpdo_disp: index list ~w ", [_Name, Ixs]),
 	    update_mpdo_disp1(Ctx, Ixs)
    catch
	error:_Reason ->
	    error_logger:warning_msg("~s: update_mpdo_disp: reading dict, "
				     "index  ~.16#:~w failed, reason = ~w\n",  
				     [_Name, I, 0, _Reason]),
	    Ctx
    end.

update_mpdo_disp1(Ctx, []) ->
    Ctx;
update_mpdo_disp1(Ctx=#co_ctx {dict = Dict, mpdo_dispatch = MpdoDisp, name = _Name}, 
		 [Index = {_Ix, _Si} | Ixs]) ->
    ?dbg(node, "~s: update_mpdo_disp: index ~.16#:~w ", [_Name, _Ix, _Si]),
    try co_dict:direct_value(Dict,Index) of
	Map ->
	    {SourceIx, SourceSi, SourceNid} = 
		{?RMPDO_MAP_RINDEX(Map), ?RMPDO_MAP_RSUBIND(Map), ?RMPDO_MAP_RNID(Map)},
	    {LocalIx, LocalSi} = 
		{?RMPDO_MAP_INDEX(Map), ?RMPDO_MAP_SUBIND(Map)},
	    Size = ?RMPDO_MAP_SIZE(Map),
	    EntryList = 
		[{{SourceIx, SourceSi + I, SourceNid}, {LocalIx,LocalSi + I}} ||
		    I <- lists:seq(0, Size - 1)],
	    ?dbg(node, "~s: update_mpdo_disp: entry list ~w ", [_Name, EntryList]),
	    insert_mpdo_disp(MpdoDisp,EntryList)
    catch
	error:_Reason ->
	    error_logger:warning_msg("~s: update_mpdo_disp: reading dict, "
				     "index  ~.16#:~w failed, reason = ~w\n",  
				     [_Name, _Ix, _Si, _Reason])
    end,
    update_mpdo_disp1(Ctx, Ixs).
    
insert_mpdo_disp(_MpdoDisp,[]) ->
    ok;
insert_mpdo_disp(MpdoDisp,[Entry | EntryList]) ->	    
    ets:insert(MpdoDisp, Entry),
    insert_mpdo_disp(MpdoDisp, EntryList).
    
%% Load time_stamp COBID - maybe start co_time_stamp server
update_time_stamp(Ctx=#co_ctx {name = _Name}) ->
    try co_dict:direct_value(Ctx#co_ctx.dict,?IX_COB_ID_TIME_STAMP,0) of
	ID ->
	    COBID = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    if ID band ?COBID_ENTRY_TIME_PRODUCER =/= 0 ->
		    Time = Ctx#co_ctx.time_stamp_time,
		    ?dbg(node, "~s: update_time_stamp: Timestamp server time=~p", 
			 [_Name, Time]),
		    if Time > 0 ->
			    Tmr = start_timer(Ctx#co_ctx.time_stamp_time,
					      time_stamp),
			    Ctx#co_ctx { time_stamp_tmr=Tmr, 
					 time_stamp_id=COBID };
		       true ->
			    Tmr = stop_timer(Ctx#co_ctx.time_stamp_tmr),
			    Ctx#co_ctx { time_stamp_tmr=Tmr,
					 time_stamp_id=COBID}
		    end;
	       ID band ?COBID_ENTRY_TIME_CONSUMER =/= 0 ->
		    %% consumer
		    ?dbg(node, "~s: update_time_stamp: Timestamp consumer", 
			 [_Name]),
		    Tmr = stop_timer(Ctx#co_ctx.time_stamp_tmr),
		    %% FIXME: delete old COBID!!!
		    ets:insert(Ctx#co_ctx.cob_table, {COBID,time_stamp}),
		    Ctx#co_ctx { time_stamp_tmr=Tmr, time_stamp_id=COBID}
	    end
    catch
	error:_Reason ->
	    Ctx
    end.


%% Load emcy COBID 
update_emcy(Ctx) ->
    try co_dict:direct_value(Ctx#co_ctx.dict,?IX_COB_ID_EMERGENCY,0) of
	ID ->
	    COBID = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    if ID band ?COBID_ENTRY_INVALID =/= 0 ->
		    Ctx#co_ctx { emcy_id = COBID };
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
	    COBID = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    if ID band ?COBID_ENTRY_SYNC =/= 0 ->
		    %% producer - sync server
		    try co_dict:direct_value(Ctx#co_ctx.dict,
					     ?IX_COM_CYCLE_PERIOD,0) of
			Time when Time > 0 ->
			    %% we do not have micro :-(
			    Ms = (Time + 999) div 1000,  
			    Tmr = start_timer(Ms, sync),
			    Ctx#co_ctx { sync_tmr=Tmr,sync_time = Ms,
					 sync_id=COBID };
			_ ->
			    Tmr = stop_timer(Ctx#co_ctx.sync_tmr),
			    Ctx#co_ctx { sync_tmr=Tmr,sync_time=0,
					 sync_id=COBID}
		    catch
			error:_Reason ->
			    Ctx
		    end;
	       true ->
		    %% consumer
		    Tmr = stop_timer(Ctx#co_ctx.sync_tmr),
		    ets:insert(Ctx#co_ctx.cob_table, {COBID,sync}),
		    Ctx#co_ctx { sync_tmr=Tmr, sync_time=0,sync_id=COBID}
	    end
    catch
	error:_Reason ->
	    Ctx
    end.
    

update_tpdo(P=#pdo_parameter {offset = Offset, cob_id = CId, valid = Valid}, 
	    Ctx=#co_ctx { tpdo_list = TList, tpdo = TpdoCtx, name = _Name }) ->
    ?dbg(node, "~s: update_tpdo: pdo param for ~p", [_Name, Offset]),
    case lists:keytake(CId, #tpdo.cob_id, TList) of
	false ->
	    if Valid ->
		    {ok,Pid} = co_tpdo:start(TpdoCtx#tpdo_ctx {debug = get(dbg)}, P),
		    ?dbg(node, "~s: update_tpdo: starting tpdo process ~p for ~p", 
			 [_Name, Pid, Offset]),
		    co_tpdo:debug(Pid, get(dbg)),
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
	     Ctx=#co_ctx {tpdo = TpdoCtx, tpdo_restart_limit = TRL, name = _Name}) ->
    case load_pdo_parameter(?IX_TPDO_PARAM_FIRST + Offset, Offset, Ctx) of
	undefined -> 
	    ?dbg(node, "~s: restart_tpdo: pdo param for ~p not found", 
		 [_Name, Offset]),
	    {error, not_found};
	Param ->
	    case RC >= TRL of
		true ->
		    ?dbg(node, "~s: restart_tpdo: restart counter exceeded",  [_Name]),
		    {error, restart_not_allowed};
		false ->
		    {ok,Pid} = 
			co_tpdo:start(TpdoCtx#tpdo_ctx {debug = get(dbg)}, Param),
		    co_tpdo:debug(Pid, get(dbg)),
		    gen_server:cast(Pid, {state, Ctx#co_ctx.state}),
		    Mon = erlang:monitor(process, Pid),
		    
		    %% If process still ok after 1 min, reset counter
		    timer:send_after(60 * 1000,  {rc_reset, Pid}),

		    T#tpdo {pid = Pid, mon = Mon, rc = RC+1}
	    end
    end.



load_pdo_parameter(I, Offset, _Ctx=#co_ctx {dict = Dict, name = _Name}) ->
    ?dbg(node, "~s: load_pdo_parameter ~p + ~p", [_Name, I, Offset]),
    case load_list(Dict, [{I, ?SI_PDO_COB_ID}, 
			  {I,?SI_PDO_TRANSMISSION_TYPE, 255},
			  {I,?SI_PDO_INHIBIT_TIME, 0},
			  {I,?SI_PDO_EVENT_TIMER, 0}]) of
	[ID,Trans,Inhibit,Timer] ->
	    Valid = (ID band ?COBID_ENTRY_INVALID) =:= 0,
	    RtrAllowed = (ID band ?COBID_ENTRY_RTR_DISALLOWED) =:=0,
	    COBID = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    #pdo_parameter { offset = Offset,
			     valid = Valid,
			     rtr_allowed = RtrAllowed,
			     cob_id = COBID,
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
index_defined([Ix | Rest], Ctx=#co_ctx {dict = Dict, res_table = RTable, name = _Name}) ->
    case co_dict:lookup_object(Dict, Ix) of
	{ok, _Obj} -> 
	    true,
	    index_defined(Rest, Ctx);
	{error, _Reason} ->
	    ?dbg(node, "~s: index_defined: index ~.16# not in dictionary",  [_Name, Ix]),
	    case reserver_pid(RTable, Ix) of
		[] -> 
		    ?dbg(node, "~s: index_defined: index ~.16# not reserved",  [_Name, Ix]),
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
    ?dbg(node, "add_subscription: ~.16#:~.16# for ~w", 
	 [Ix1, Ix2, Key]),
    I = co_iset:new(Ix1, Ix2),
    case ets:lookup(Tab, Key) of
	[] -> ets:insert(Tab, {Key, I});
	[{_,ISet}] -> ets:insert(Tab, {Key, co_iset:union(ISet, I)})
    end.

remove_subscriptions(Tab, Key) ->
    ets:delete(Tab, Key).

remove_subscription(Tab, Ix, Key) ->
    remove_subscription(Tab, Ix, Ix, Key).

remove_subscription(Tab, Ix1, Ix2, Key) when Ix1 =< Ix2 ->
    ?dbg(node, "remove_subscription: ~.16#:~.16# for ~w", 
	 [Ix1, Ix2, Key]),
    case ets:lookup(Tab, Key) of
	[] -> ok;
	[{Key,ISet}] -> 
	    case co_iset:difference(ISet, co_iset:new(Ix1, Ix2)) of
		[] ->
		    ?dbg(node, "remove_subscription: last index for ~w", 
			 [Key]),
		    ets:delete(Tab, Key);
		ISet1 -> 
		    ?dbg(node, "remove_subscription: new index set ~p for ~w", 
			 [ISet1,Key]),
		    ets:insert(Tab, {Key,ISet1})
	    end
    end.

subscriptions(Tab, Key) when is_pid(Key) ->
    case ets:lookup(Tab, Key) of
	[] -> [];
	[{Key, Iset, _Opts}] -> Iset
    end.

subscribers(Tab) ->
    lists:usort([Key || {Key, _Ixs} <- ets:tab2list(Tab)]).

inform_subscribers(I, _Ctx=#co_ctx {name = _Name, sub_table = STable}) ->
    lists:foreach(
      fun(Pid) ->
	      case self() of
		  Pid -> do_nothing;
		  _OtherPid ->
		      ?dbg(node, "~s: inform_subscribers: "
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
	    ?dbg(node, "add_reservation: ~.16# for ~w",[Ix, Pid]), 
	    ets:insert(Tab, {Ix, Mod, Pid}), 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, Mod, dead}] ->  %% M or Mod ???
	    ok, 
	    ?dbg(node, "add_reservation: renewing ~.16# for ~w",[Ix, Pid]), 
	    ets:insert(Tab, {Ix, Mod, Pid}), 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, _M, Pid}] -> 
	    ok, 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, _M, _OtherPid}] ->        
	    ?dbg(node, "add_reservation: index already reserved  by ~p", 
		 [_OtherPid]),
	    {error, index_already_reserved}
    end.


add_reservation(_Tab, Ix1, Ix2, _Mod, _Pid) when Ix1 < ?MAN_SPEC_MIN;
						 Ix2 < ?MAN_SPEC_MIN->
    ?dbg(node, "add_reservation: not possible for ~.16#:~w for ~w", 
	 [Ix1, Ix2, _Pid]),
    {error, not_possible_to_reserve};
add_reservation(Tab, Ix1, Ix2, Mod, Pid) when ?is_index(Ix1), ?is_index(Ix2), 
					      Ix1 =< Ix2, 
					      is_pid(Pid) ->
    ?dbg(node, "add_reservation: ~.16#:~w for ~w", 
	 [Ix1, Ix2, Pid]),
    add_reservation(Tab, lists:seq(Ix1, Ix2), Mod, Pid).
	    

   
remove_reservations(Tab, Pid) ->
    remove_reservation(Tab, reservations(Tab, Pid), Pid).

remove_reservation(_Tab, [], _Pid) ->
    ok;
remove_reservation(Tab, [Ix | Tail], Pid) ->
    ?dbg(node, "remove_reservation: ~.16# for ~w", [Ix, Pid]),
    case ets:lookup(Tab, Ix) of
	[] -> 
	    ok, 
	    remove_reservation(Tab, Tail, Pid);
	[{Ix, _M, Pid}] -> 
	    ets:delete(Tab, Ix), 
	    remove_reservation(Tab, Tail, Pid);
	[{Ix, _M, _OtherPid}] -> 	    
	    ?dbg(node, "remove_reservation: index reserved by other pid ~p", 
		 [_OtherPid]),
	    {error, index_reservered_by_other}
    end.

remove_reservation(Tab, Ix1, Ix2, Pid) when Ix1 =< Ix2 ->
    ?dbg(node, "remove_reservation: ~.16#:~.16# for ~w", 
	 [Ix1, Ix2, Pid]),
    remove_reservation(Tab, lists:seq(Ix1, Ix2), Pid).

reset_reservations(Tab, Pid) ->
    reset_reservation(Tab, reservations(Tab, Pid), Pid).

reset_reservation(_Tab, [], _Pid) ->
    ok;
reset_reservation(Tab, [Ix | Tail], Pid) ->
    ?dbg(node, "reset_reservation: ~.16# for ~w", [Ix, Pid]),
    case ets:lookup(Tab, Ix) of
	[] -> 
	    ok, 
	    reset_reservation(Tab, Tail, Pid);
	[{Ix, M, Pid}] -> 
	    ets:delete(Tab, Ix), 
	    ets:insert(Tab, {Ix, M, dead}),
	    reset_reservation(Tab, Tail, Pid);
	[{Ix, _M, _OtherPid}] -> 	    
	    ?dbg(node, "reset_reservation: index reserved by other pid ~p", 
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
	    ?dbg(node, "~s: inform_reservers: "
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
	    ?dbg(node, "~s: lookup_sdo_server: Nid  ~12.16.0# "
		 "neither extended or short ???", [_Name, Nid]),
	    undefined
    end.

lookup_cobid(COBID, Ctx) ->
    case ets:lookup(Ctx#co_ctx.cob_table, COBID) of
	[{_,Entry}] -> 
	    Entry;
	[] -> 
	    if ?is_cobid_extended(COBID) andalso 
	       ?XFUNCTION_CODE(COBID) =:= ?SDO_TX ->
		    {sdo_tx, ?XCOB_ID(?SDO_RX, ?XNODE_ID(COBID))};
	       ?is_not_cobid_extended(COBID) andalso
	       ?FUNCTION_CODE(COBID) =:= ?SDO_TX ->
		    {sdo_tx, ?COB_ID(?SDO_RX, ?NODE_ID(COBID))};
	       true ->
		    undefined
	    end
    end.

%%
%% Update the Node map table (Serial => NodeId)
%%  Check if nmt entry for node id has a consistent Serial
%%  if not then remove bad mapping
%%
update_node_map(NodeId, Serial, Ctx) ->
    case ets:lookup(Ctx#co_ctx.nmt_table, NodeId) of
	[E] when E#nmt_entry.serial =/= Serial ->
	    %% remove old mapping
	    ets:delete(Ctx#co_ctx.node_map, E#nmt_entry.serial),
	    %% update new mapping
	    update_nmt_entry(NodeId, [{serial,Serial}], Ctx);
	_ ->
	    ok
    end,
    ets:insert(Ctx#co_ctx.node_map, {Serial,NodeId}),
    Ctx.
    
%%    
%% Update the NMT entry (NodeId => #nmt_entry { serial, vendor ... })
%%
update_nmt_entry(NodeId, Opts, Ctx) ->
    E = lookup_nmt_entry(NodeId, Ctx),
    E1 = update_nmt_entry(Opts, E),
    ets:insert(Ctx#co_ctx.nmt_table, E1),
    Ctx.


update_nmt_entry([{Key,Value}|Kvs],E) when is_record(E, nmt_entry) ->
    E1 = update_nmt_value(Key, Value,E),
    update_nmt_entry(Kvs,E1);
update_nmt_entry([], E) ->
    E#nmt_entry { time=now() }.

update_nmt_value(Key,Value,E) when is_record(E, nmt_entry) ->
    case Key of
	id       -> E#nmt_entry { time=Value};
	vendor   -> E#nmt_entry { vendor=Value};
	product  -> E#nmt_entry { product=Value};
	revision -> E#nmt_entry { revision=Value};
	serial   -> E#nmt_entry { serial=Value};
	state    -> E#nmt_entry { state=Value}
    end.
	    
%%
%% 
%%
%%
%% Callback functions for changes in tpdo elements
%%
tpdo_set({_Ix, _Si} = I, Data, Mode,
	 Ctx=#co_ctx {tpdo_cache = Cache, tpdo_cache_limit = TCL, name = _Name}) ->
    ?dbg(node, "~s: tpdo_set: Ix = ~.16#:~w, Data = ~w, Mode ~p",
	 [_Name, _Ix, _Si, Data, Mode]), 
    case {ets:lookup(Cache, I), Mode} of
	{[], _} ->
	    %% Previously unknown tpdo element, probably in sam_mpdo
	    %% with block size > 1
	    %% Insert ??
	    ?dbg(node, "~s: tpdo_set: inserting first value for "
		 "previously unknown tpdo element.",
		 [_Name]), 
	    ets:insert(Cache, {I, [Data]}),
	    {ok, Ctx};
	    %% io:format("WARNING!" 
	    %% "~s: tpdo_set: unknown tpdo element\n", [_Name]),
	    %% {{error,unknown_tpdo_element}, Ctx};
	{[{I, OldData}], append} when length(OldData) >= TCL ->
	    error_logger:warning_msg( "~s: tpdo_set: tpdo cache for ~.16#:~w "
				      "full.\n", [_Name,  _Ix, _Si]),
	    {{error, tpdo_cache_full}, Ctx};
	{[{I, OldData}], append} ->
	    NewData = case OldData of
			    [(<<>>)] -> [Data]; %% remove default
			    _List -> OldData ++ [Data]
			end,
	    ?dbg(node, "~s: tpdo_set: append, old = ~p, new = ~p",
		 [_Name, OldData, NewData]), 
	    try ets:insert(Cache,{I,NewData}) of
		true -> {ok, Ctx}
	    catch
		error:Reason -> 
		    error_logger:warning_msg("~s: tpdo_set: insert of ~p failed, "
					     "reason = ~w\n", [_Name, NewData, Reason]),
		    {{error,Reason}, Ctx}
	    end;
	{[{I, _OldData}], overwrite} ->
	    ?dbg(node, "~s: tpdo_set: overwrite, old = ~p, new = ~p",
		 [_Name, _OldData, Data]), 
	    ets:insert(Cache, {I, [Data]}),
	    {ok, Ctx}
    end.

%%
%% Unpack PDO Data from external TPDO/internal RPDO 
%%
rpdo_unpack(I, Data, Ctx=#co_ctx {name = _Name}) ->
    case pdo_mapping(I, Ctx#co_ctx.res_table, Ctx#co_ctx.dict, 
		     Ctx#co_ctx.tpdo_cache) of
	{rpdo,IL} ->
	    BitLenList = [BitLen || {_Ix, BitLen} <- IL],
	    ?dbg(node, "~s: rpdo_unpack: data = ~w, il = ~w, bl = ~w", 
		 [_Name, Data, IL, BitLenList]),
	    try co_codec:decode_pdo(Data, BitLenList) of
		{Ds, _} -> 
		    ?dbg(node, "~s: rpdo_unpack: decoded data ~p", [_Name, Ds]),
		    rpdo_set(IL, Ds, Ctx)
	    catch error:_Reason ->
		    error_logger:warning_msg("~s: rpdo_unpack: decode failed, "
					     "reason ~p\n",  [_Name, _Reason]),
		    Ctx
	    end;
	_Error ->
	    error_logger:warning_msg("~s: rpdo_unpack: error = ~p\n", [_Name, _Error]),
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
pdo_mapping(Ix, _TpdoCtx=#tpdo_ctx {dict = Dict, res_table = ResTable, 
				   tpdo_cache = TpdoCache}) ->
    ?dbg(node, "pdo_mapping: api call for ~.16#", [Ix]),
    pdo_mapping(Ix, ResTable, Dict, TpdoCache).
pdo_mapping(Ix, ResTable, Dict, TpdoCache) ->
    ?dbg(node, "pdo_mapping: ~.16#", [Ix]),
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
	    ?dbg(node, "pdo_mapping: Standard pdo of size ~p found", [N]),
	    pdo_mapping(MType,Ix,1,N,ResTable,Dict,TpdoCache);
	{ok,?SAM_MPDO} -> %% SAM-MPDO
	    ?dbg(node, "pdo_mapping: sam_mpdo identified look for value", []),
	    mpdo_mapping(sam_mpdo,Ix,ResTable,Dict,TpdoCache);
	{ok,?DAM_MPDO} -> %% DAM-MPDO
	    ?dbg(node, "pdo_mapping: dam_mpdo found", []),
	    pdo_mapping(dam_mpdo,Ix,1,1,ResTable,Dict,TpdoCache);
	Error ->
	    Error
    end.


pdo_mapping(MType,Ix,Si,Sn,ResTable,Dict,TpdoCache) ->
    pdo_mapping(MType,Ix,Si,Sn,[],ResTable,Dict,TpdoCache).

pdo_mapping(MType,_Ix,Si,Sn,Is,_ResTable,_Dict,_TpdoCache) when Si > Sn ->
    ?dbg(node, "pdo_mapping: ~p all entries mapped, result ~p", 
	 [MType, Is]),
    {MType, reverse(Is)};
pdo_mapping(MType,Ix,Si,Sn,Is,ResTable,Dict,TpdoCache) -> 
    ?dbg(node, "pdo_mapping: type = ~p, index = ~.16#:~w", [MType,Ix,Si]),
    case co_dict:value(Dict, Ix, Si) of
	{ok,Map} ->
	    ?dbg(node, "pdo_mapping: map = ~.16#", [Map]),
	    Index = {_I,_S} = {?PDO_MAP_INDEX(Map),?PDO_MAP_SUBIND(Map)},
	    ?dbg(node, "pdo_mapping: entry[~w] = {~.16#:~w}", 
		 [Si,_I,_S]),
	    maybe_inform_reserver(MType, Index, ResTable, Dict, TpdoCache),
	    pdo_mapping(MType,Ix,Si+1,Sn,
			[{Index, ?PDO_MAP_BITS(Map)}|Is], 
			ResTable, Dict, TpdoCache);
	Error ->
	    ?dbg(node, "pdo_mapping: ~.16#:~w = Error ~w", 
		 [Ix,Si,Error]),
	    Error
    end.

mpdo_mapping(MType,Ix,ResTable,Dict,TpdoCache) 
  when MType == sam_mpdo andalso is_integer(Ix) ->
    ?dbg(node, "mpdo_mapping: index = ~.16#", [Ix]),
    case co_dict:value(Dict, Ix, 1) of
	{ok,Map} ->
	   Index = {?PDO_MAP_INDEX(Map),?PDO_MAP_SUBIND(Map)},
	   mpdo_mapping(MType,Index,ResTable,Dict,TpdoCache);
	Error ->
	    ?dbg(node, "mpdo_mapping: ~.16# = Error ~w", [Ix,Error]),
	    Error
    end;
mpdo_mapping(MType,{IxInScanList,SiInScanList},ResTable,Dict,TpdoCache) 
  when MType == sam_mpdo andalso
       IxInScanList >= ?IX_OBJECT_SCANNER_FIRST andalso
       IxInScanList =< ?IX_OBJECT_SCANNER_LAST  ->
    %% MPDO Producer mapping
    %% The entry in PDO Map has been read, now read the entry in MPDO Scan List
    ?dbg(node, "mpdo_mapping: sam_mpdo, scan index = ~.16#:~w", 
	 [IxInScanList,SiInScanList]),
    case co_dict:value(Dict, IxInScanList, SiInScanList) of
	{ok, Map} ->
	    ?dbg(node, "mpdo_mapping: map = ~.16#", [Map]),
	    Index = {_Ix,_Si} = {?TMPDO_MAP_INDEX(Map),?TMPDO_MAP_SUBIND(Map)},
	    BlockSize = ?TMPDO_MAP_SIZE(Map), %% TODO ????
	    ?dbg(node, "mpdo_mapping: sam_mpdo, local index = ~.16#:~w", [_Ix,_Si]),
	    maybe_inform_reserver(MType, Index, ResTable, Dict, TpdoCache),
	    {MType, [{{Index, BlockSize}, ?MPDO_DATA_SIZE}]};
	Error ->
	    Error %%??
    end.
       
maybe_inform_reserver(MType, {Ix, _Si} = Index, ResTable, _Dict, TpdoCache) ->
    case reserver_with_module(ResTable, Ix) of
	[] ->
	    ?dbg(node, "maybe_inform_reserver: No reserver for index ~.16#", [Ix]),
	    ok;
	{Pid, _Mod} when is_pid(Pid)->
	    ?dbg(node, "maybe_inform_reserver: Process ~p has reserved index ~.16#", 
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
	    ?dbg(node, "maybe_inform_reserver: "
		 "Reserver process for index ~.16# dead.", [Ix]),
	    {error, ?abort_internal_error}; %% ???
	_Other ->
	    ?dbg(node, "maybe_inform_reserver: "
		 "Other case = ~p", [_Other]),
	    {error, ?abort_internal_error}
    end.

tpdo_data({Ix, Si} = I, ResTable, Dict, TpdoCache) ->
    case reserver_with_module(ResTable, Ix) of
	[] ->
	    ?dbg(node, "tpdo_data: No reserver for index ~.16#", [Ix]),
	    co_dict:data(Dict, Ix, Si);
	{Pid, _Mod} when is_pid(Pid)->
	    ?dbg(node, "tpdo_data: Process ~p has reserved index ~.16#", 
		 [Pid, Ix]),
	    %% Value cached ??
	    cache_value(TpdoCache, I);
	{dead, _Mod} ->
	    ?dbg(node, "tpdo_data: Reserver process for index ~.16# dead.", 
		 [Ix]),
	    %% Value cached??
	    cache_value(TpdoCache, I);
	_Other ->
	    %% How handle ???
	    error_logger:error_msg("~p: tpdo_data: unknown tpdo element\n", [self()]),
	    ?dbg(node, "tpdo_data: Other case = ~p, returning default value.", 
		 [_Other]),
	    {ok, [(<<>>)]}
    end.

cache_value(Cache, I = {_Ix, _Si}) ->
    case ets:lookup(Cache, I) of
	[] ->
	    %% How handle ???
	    error_logger:warning_msg( "~p: cache_value: unknown tpdo element "
				      "~.16#:~w\n", [self(), _Ix, _Si]),
	    ?dbg(node, "cache_value: tpdo element not found for ~.16#:~w, "
		 "returning default value.",  [_Ix, _Si]),
	    {error, no_value};
	[{I,[LastValue | []]}]  ->
	    %% Leave last value in cache
	    ?dbg(node, "cache_value: Last value = ~p.", [LastValue]),
	    {ok, LastValue};
	[{I, [FirstValue | Rest]}] ->
	    %% Remove first value from list
	    ?dbg(node, "cache_value: First value = ~p, rest = ~p.", 
		 [FirstValue, Rest]),
	    ets:insert(Cache, {I, Rest}),
	    {ok, FirstValue}
    end.
	    
    
rpdo_value({Ix,Si},Data,Ctx) ->
    case reserver_with_module(Ctx#co_ctx.res_table, Ix) of
	[] ->
	    ?dbg(node, "rpdo_value: No reserver for index ~.16#", [Ix]),
	    try co_dict:set_data(Ctx#co_ctx.dict, Ix, Si, Data) of
		ok -> 
		    handle_notify(Ix, Ctx);
		_Error -> 
		    ?dbg(node, "rpdo_value: set_data failed,error ~p", [_Error]),
		    Ctx
	    catch
		error:_Reason -> 
		    ?dbg(node, "rpdo_value: set_data failed, reason ~p", [_Reason]),
		    Ctx
	    end;
	{Pid, Mod} when is_pid(Pid)->
	    ?dbg(node, "rpdo_value: Process ~p has reserved index ~.16#", 
		 [Pid, Ix]),
	    case co_set_fsm:start({Pid, Mod}, {Ix, Si}, Data) of
		{ok, _FsmPid} -> 
		    ?dbg(node,"Started set session ~p", [_FsmPid]),
		    handle_notify(Ix, Ctx);
		ignore ->
		    ?dbg(node,"Complete set session executed", []),
		    handle_notify(Ix, Ctx);
		{error, _Reason} -> 	
		    %% io:format ??
		    ?dbg(node,"Failed starting set session, reason ~p", [_Reason]),
		    Ctx
	    end;
	{dead, _Mod} ->
	    ?dbg(node, "rpdo_value: Reserver process for index ~.16# dead.", 
		 [Ix]),
	    Ctx;
	_Other ->
	    ?dbg(node, "rpdo_value: Other case = ~p", [_Other]),
	    Ctx
    end.


add_xflag(undefined) ->
    undefined;
add_xflag(NodeId) ->
    NodeId bor ?COBID_ENTRY_EXTENDED.

complete_nodeid(NodeId) ->
    if ?is_nodeid(NodeId) ->
	    %% Not extended
	    NodeId;
       true ->
	    add_xflag(NodeId)
    end.
    


%% Set error code - and send the emergency object (if defined)
%% FIXME: clear error list when code 0000
set_error(Error, Code, Ctx) ->
    case lists:member(Code, Ctx#co_ctx.error_list) of
	true -> 
	    Ctx;  %% condition already reported, do NOT send
	false ->
	    co_dict:direct_set(Ctx#co_ctx.dict,?IX_ERROR_REGISTER, 0, Error),
	    NewErrorList = update_error_list([Code | Ctx#co_ctx.error_list], 1, Ctx),
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
    

print_nodeid(Label, undefined) ->
    io:format(Label ++ " not defined\n",[]);
print_nodeid(" NODEID:", NodeId) ->
    io:format(" NODEID:" ++ " ~4.16.0#\n", [NodeId]);
print_nodeid("XNODEID:", NodeId) ->
    io:format("XNODEID:" ++ " ~8.16.0#\n", [NodeId]).

				       

%% Optionally start a timer
start_timer(0, _Type) -> false;
start_timer(Time, Type) -> erlang:start_timer(Time,self(),Type).

%% Optionally stop a timer and flush
stop_timer(false) -> false;
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
    now_to_time_of_day(now()).

set_time_of_day(Time) ->
    ?dbg(node, "set_time_of_day: ~p", [Time]),
    ok.

now_to_time_of_day({Sm,S0,Us}) ->
    S1 = Sm*1000000 + S0,
    D = S1 div ?SECS_PER_DAY,
    S = S1 rem ?SECS_PER_DAY,
    Ms = S*1000 + (Us  div 1000),
    Days = D + (?DAYS_FROM_0_TO_1970 - ?DAYS_FROM_0_TO_1984),
    #time_of_day { ms = Ms, days = Days }.

time_of_day_to_now(T) when is_record(T, time_of_day)  ->
    D = T#time_of_day.days + (?DAYS_FROM_0_TO_1984-?DAYS_FROM_0_TO_1970),
    Sec = D*?SECS_PER_DAY + (T#time_of_day.ms div 1000),
    USec = (T#time_of_day.ms rem 1000)*1000,
    {Sec div 1000000, Sec rem 1000000, USec}.
