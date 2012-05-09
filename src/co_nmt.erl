%%%-------------------------------------------------------------------
%%% @author Malotte Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%%  Handles CANopen NMT protocol.
%%%
%%% File: co_nmt.erl
%%% Created:  3 May 2012 by Malotte Westman Lönne
%%% @end
%%%-------------------------------------------------------------------
-module(co_nmt).

-include_lib("can/include/can.hrl").
-include("canopen.hrl").
-include("co_debug.hrl").

-behaviour(gen_server).

%% API
-export([start_link/1, 
	 stop/0,
	 alive/0,
	 add_slave/1,
	 remove_slave/1,
	 save/0,
	 load/0]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).


%% Test functions
-export([debug/1,
	 dump/0]).

-define(NMT_MASTER, co_nmt_master).
-define(NMT_CONF, "nmt.conf").

-record(ctx, 
	{
	  serial,
	  node_pid,
	  supervision = none, %% Type of supervision
	  nmt_table,  %% Table of NMT slaves
	  node_map    %% ??
	 }).

-record(nmt_entry,
	{
	  id,                  %% node id (key)
	  guard_time = 0,
	  life_factor = 0,
	  guard_timer,
	  life_timer,
	  com_status = ok,
	  node_state=?PreOperational,
	  toggle = 0           %% Expected next toggle
	 }).


%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% @end
%%--------------------------------------------------------------------
-spec start_link(list(tuple())) -> 
			{ok, Pid::pid()} | ignore | {error, Error::term()}.

start_link(Args) ->
    error_logger:info_msg("~p: start_link: args = ~p\n", [?MODULE, Args]),
    F =	case proplists:get_value(linked,Args,true) of
	    true -> start_link;
	    false -> start
	end,
    
    case whereis(?NMT_MASTER) of
	Pid when is_pid(Pid) ->
	    {error, already_started};
	undefined ->
	    gen_server:F({local, ?NMT_MASTER}, ?MODULE, Args, [])
    end.


%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | {error, Reason::atom()}.
				  
stop() ->
    case whereis(?NMT_MASTER) of
	Pid when is_pid(Pid) ->
	    gen_server:call(?NMT_MASTER, stop);
	undefined ->
	    ok
    end.


%%--------------------------------------------------------------------
%% @doc
%% Checks if the co_proc still is alive.
%% @end
%%--------------------------------------------------------------------
-spec alive() -> true | false.

alive() ->
    case whereis(?NMT_MASTER) of
	undefined -> false;
	_PI -> true
    end.

%%--------------------------------------------------------------------
%% @doc
%% Adds slave to supervise.
%% @end
%%--------------------------------------------------------------------
-spec add_slave(SlaveId::integer()) ->
    ok | {error, Reason::term()}.

add_slave(SlaveId) when is_integer(SlaveId) ->
    gen_server:call(?NMT_MASTER, {add_slave, SlaveId}).

%%--------------------------------------------------------------------
%% @doc
%% Remove slave from supervision.
%% @end
%%--------------------------------------------------------------------
-spec remove_slave(SlaveId::integer()) ->
    ok | {error, Reason::term()}.

remove_slave(SlaveId) when is_integer(SlaveId) ->
    gen_server:call(?NMT_MASTER, {remove_slave, SlaveId}).

%%--------------------------------------------------------------------
%% @doc
%% Saves nmt configuration (slaves to supervise).
%% @end
%%--------------------------------------------------------------------
-spec save() -> ok | {error, Reason::term()}.

save() ->
    gen_server:call(?NMT_MASTER, save).


%%--------------------------------------------------------------------
%% @doc
%% Restores saved nmt configuration (slaves to supervise).
%% @end
%%--------------------------------------------------------------------
-spec load() -> ok | {error, Reason::term()}.

load() ->
    gen_server:call(?NMT_MASTER, load).


%%--------------------------------------------------------------------
%% @doc
%% Adjust debug flag.
%% @end
%%--------------------------------------------------------------------
-spec debug(TrueOrFalse::boolean()) -> ok.

debug(TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(?NMT_MASTER, {debug, TrueOrFalse}).

%%--------------------------------------------------------------------
%% @doc
%% Dump data.
%% @end
%%--------------------------------------------------------------------
-spec dump() -> ok.

dump()  ->
    gen_server:call(?NMT_MASTER,dump).

	
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
-spec init(list(term())) -> {ok, Ctx::#ctx{}}.

init(Args) ->
    error_logger:info_msg("~p: init: args = ~p, pid = ~p\n", 
			  [?MODULE, Args, self()]),

    %% Trace output enable/disable
    put(dbg, proplists:get_value(debug,Args,false)), 

    case proplists:get_value(node_pid, Args) of
	NodePid when is_pid(NodePid) ->
	    %% Manager needed
	    co_mgr:start([{debug, get(dbg)}]),
	    Supervision = proplists:get_value(supervision, Args, none),
	    NMT = ets:new(co_nmt_table, [{keypos,#nmt_entry.id},
					 protected, named_table, ordered_set]),
	    MAP = ets:new(co_node_map, []),
	    {ok, #ctx {node_pid = NodePid, supervision = Supervision,
		       nmt_table = NMT, node_map = MAP}};
	_NotPid ->
	    {error, no_co_node}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	{add_slave, SlaveId::integer()} |
	{remove_slave, SlaveId::integer()} |
	save |
	load |
	{debug, TrueOrFalse::boolean()} |
	stop.

-spec handle_call(Request::call_request(),
		  From::{pid(), term()}, Ctx::#ctx{}) ->
			 {reply, Reply::term(), Ctx::#ctx{}} |
			 {stop, Reason::term(), Reply::term(), Ctx::#ctx{}}.

handle_call({add_slave, SlaveId}, _From, Ctx=#ctx {nmt_table = NmtTable}) ->
    ?dbg(nmt, "handle_call: add_slave ~.16#", [SlaveId]),
    case ets:lookup(NmtTable, SlaveId) of
	[_Slave] -> ok; %% already supervised
	[] -> add_slave(SlaveId, Ctx)
    end,
    {reply, ok, Ctx};

handle_call({remove_slave, SlaveId}, _From, Ctx=#ctx {nmt_table = NmtTable}) ->
    ?dbg(nmt, "handle_call: remove_slave ~.16#", [SlaveId]),
    case ets:lookup(NmtTable, SlaveId) of
	[] -> ok; %% not supervised
	[Slave] -> remove_slave(Slave, Ctx)
    end,
    {reply, ok, Ctx};

handle_call(save, _From, Ctx=#ctx {nmt_table = NmtTable}) ->
    File = filename:join(code:priv_dir(canopen), ?NMT_CONF),
    ?dbg(nmt, "handle_call: save nmt configuration to ~p", [File]),
    case file:open(File, [write]) of
	{ok, Fd} ->
	    Tab = ets:tab2list(NmtTable),
	    io:format(Fd,"~p.\n",[Tab]),
	    file:close(Fd),
	    {reply, ok, Ctx};
	Error ->
	    {reply, Error, Ctx}
    end;
	
handle_call(load, _From, Ctx=#ctx {nmt_table = NmtTable}) ->
    File = filename:join(code:priv_dir(canopen), ?NMT_CONF),
    ?dbg(nmt, "handle_call: load nmt configuration from ~p", [File]),
    case filelib:is_regular(File) of
	true ->
	    case file:consult(File) of
		{ok, [List]} ->
		    ?dbg(nmt, "handle_call: loading list ~p", [List]),
		    try ets:insert(NmtTable, List) of
			true -> {reply, ok, Ctx}
		    catch
			error:Reason -> {reply, {error, Reason}, Ctx}
		    end;
		Error ->
		    {reply, Error, Ctx}
	    end;
	false ->
	    {reply, {error, no_nmt_conf_exists}, Ctx}
    end;

handle_call({debug, TrueOrFalse}, _From, Ctx) ->
    put(dbg, TrueOrFalse),
    {reply, ok, Ctx};

handle_call(dump, _From, Ctx) ->
    io:format("---- NMT TABLE ----\n"),
    ets:foldl(
      fun(E,_) ->
	      io:format("  ID: ~.16#\n", 
			[E#nmt_entry.id]),
	      io:format("     STATE: ~s\n", 
			[co_format:state(E#nmt_entry.node_state)])
      end, ok, Ctx#ctx.nmt_table),
    io:format("---- NODE MAP TABLE ----\n"),
    ets:foldl(
      fun({Sn,SlaveId},_) ->
	      io:format("~10.16.0# => ~w\n", [Sn, SlaveId])
      end, ok, Ctx#ctx.node_map),
   {reply, ok, Ctx};

handle_call(stop, _From, Ctx) ->
    {stop, normal, ok, Ctx};

handle_call(_Call, _From, Ctx) ->
    ?dbg(nmt, "handle_call: unknown call ~p, ignored", [_Call]),
    {reply, {error, bad_call}, Ctx}.
    

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-type msg()::
	{node_guard_reply, SlaveId::integer(), Frame::#can_frame{}} | 
	{supervision, node_guard | heartbeat | none} | 
	term().

-spec handle_cast(Msg::msg(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}}.

handle_cast({node_guard_reply, SlaveId, Frame}, Ctx) 
  when Frame#can_frame.len >= 1 ->
    ?dbg(nmt, "handle_cast: node_guard_reply ~w", [Frame]),
    case Frame#can_frame.data of
	<<Toggle:1, State:7, _/binary>> ->
	    handle_node_guard(SlaveId, State, Toggle, Ctx);
	_ ->
	    do_nothing
    end,
    {noreply, Ctx};

handle_cast({supervision, Supervision}, Ctx=#ctx {supervision = Supervision}) ->
    ?dbg(?NAME," handle_cast: supervision ~p, no change.", [Supervision]),
    {noreply, Ctx};
handle_cast({supervision, New}, Ctx=#ctx {supervision = _Old}) ->
    ?dbg(?NAME," handle_cast: supervision ~p -> ~p.", [_Old, New]),
    %% Activate/deactivate .. or handle in co_node ??
    {noreply, Ctx#ctx {supervision = New}};
handle_cast(_Msg, Ctx) ->
    ?dbg(?NAME," handle_cast: Unknown message = ~p, ignored. ", [_Msg]),
    {noreply, Ctx}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% Handles 'DOWN' messages for monitored processes.
%% @end
%%--------------------------------------------------------------------
-type info()::
	{do_node_guard, SlaveId::integer()} |
	{node_guard_timeout, SlaveId::integer()} | 
	term().


-spec handle_info(Info::info(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}}.

handle_info({do_node_guard, SlaveId}, 
	    Ctx=#ctx {nmt_table = NmtTable, node_pid = NodePid}) ->
    ?dbg(nmt, "handle_info: do_node_guard for ~.16#", [SlaveId]),
    case ets:lookup(NmtTable, SlaveId) of
	[] -> 
	    ?dbg(nmt, "handle_info: do_node_guard, slave not found!", []),
	    ok;
	[Slave] -> 
	    send_node_guard(SlaveId, NodePid),
	    ets:insert(NmtTable, Slave#nmt_entry {com_status = waiting})
    end,
    {noreply, Ctx};

handle_info({node_guard_timeout, SlaveId}, Ctx=#ctx {nmt_table = NmtTable}) ->
    ?dbg(nmt, "handle_info: node_guard timeout received for ~.16#", [SlaveId]),
    error_logger:error_msg("Node guard timeout, check NMT slave ~.16#.\n",[SlaveId]),
    case ets:lookup(NmtTable, SlaveId) of
	[] -> 
	    ?dbg(nmt, "handle_info: node_guard_timeout, slave not found!", []),
	    ok;
	[Slave] -> 
	    ets:insert(NmtTable, Slave#nmt_entry {com_status = lost})
    end,
    %% Start again ??
    {noreply, Ctx};

handle_info(_Info, Ctx) ->
    ?dbg(?NAME," handle_info: Unknown Info ~p, ignored.\n", [_Info]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason::term(), Ctx::#ctx{}) -> 
		       no_return().

terminate(_Reason, _Ctx) ->
    ?dbg(node, "terminate: reason ~p, exiting", [_Reason]),
    co_mgr:stop(),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term(), Ctx::#ctx{}, Extra::term()) -> 
			 {ok, NewCtx::#ctx{}}.

code_change(_OldVsn, Ctx, _Extra) ->
    {ok, Ctx}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

add_slave(SlaveId, _Ctx=#ctx {supervision = none, nmt_table = NmtTable}) ->
    ?dbg(nmt, "add_slave: ~.16#", [SlaveId]),
    ?dbg(nmt, "add_slave: no supervision", []),
    ets:insert(NmtTable, #nmt_entry {id = SlaveId});

add_slave(SlaveId, _Ctx=#ctx {nmt_table = NmtTable}) ->
    ?dbg(nmt, "add_slave: ~.16#", [SlaveId]),
    %% get node guard time and life factor
    %%GuardTime = 1000,
    %%LifeFactor = 10,
    NodeId = if ?is_nodeid_extended(SlaveId) ->
		     {xnodeid, SlaveId};
		?is_nodeid(SlaveId) ->
		     {nodeid, SlaveId}
	     end,

    {ok, GuardTime} = 
	co_mgr:fetch(NodeId, ?IX_GUARD_TIME, segment, {value, ?UNSIGNED16}),
    {ok, LifeFactor} = 
	co_mgr:fetch(NodeId, ?IX_LIFE_TIME_FACTOR, segment, {value, ?UNSIGNED8}),
    case GuardTime of
	0 -> 
	    ?dbg(nmt, "add_slave: no node guarding", []),
	    ets:insert(NmtTable, #nmt_entry {id = SlaveId});
	_T ->
	    ?dbg(nmt, "add_slave: node guarding, ~p * ~p", [GuardTime, LifeFactor]),
	    Slave = #nmt_entry {id = SlaveId,
				guard_time = GuardTime,
				life_factor = LifeFactor},
				
	    GTimer = start_guard_timer(Slave),
	    LTimer = start_life_timer(Slave),
	    ets:insert(NmtTable, Slave#nmt_entry {guard_timer = GTimer,
						  life_timer = LTimer,
						  com_status = ok})
    end.

remove_slave(Slave, _Ctx=#ctx {nmt_table = NmtTable}) ->
    ?dbg(nmt, "remove_slave: ~.16#", [Slave#nmt_entry.id]),
    cancel_life_timer(Slave),
    cancel_guard_timer(Slave),
    ets:delete(NmtTable,Slave).

handle_node_guard(SlaveId, State, Toggle, 
		  Ctx=#ctx {supervision = Supervision, nmt_table = NmtTable}) ->
    ?dbg(nmt, "handle_node_guard: node ~.16#, state ~p, toggle ~p", 
	 [SlaveId, State, Toggle]),
    case ets:lookup(NmtTable, SlaveId) of
	[] -> 
	    %% First message
	    ?dbg(nmt, "handle_node_guard: new node, creating entry", []),
	    if State =/= ?Initialisation ->
		    error_logger:error_msg("Unexpected state",[]);
	       true -> ok
	    end,
	    add_slave(SlaveId, Ctx);
	[Slave] when Supervision == node_guard -> 
	    if Slave#nmt_entry.toggle == Toggle andalso
	       Slave#nmt_entry.node_state == State ->
		    update_slave(Slave, Toggle, NmtTable);
	       true ->
		    ?dbg(nmt, "handle_node_guard: expected state ~p, toggle ~p", 
			 [Slave#nmt_entry.node_state, Slave#nmt_entry.toggle]),
		    %% Send error ??
		    error_logger:error_msg("Node ~p answered node guard with "
					   "wrong toggle and/or state, ignored.", 
					   [SlaveId])
	    end;
	[_Slave] when Supervision == none -> 
	    ?dbg(nmt, "handle_node_guard: no supervision", []),
	    ok
    end.


update_slave(Slave, Toggle, NmtTable) ->
    %% Restart life timer
    cancel_life_timer(Slave),
    NewTimer = start_life_timer(Slave),
    ets:insert(NmtTable, Slave#nmt_entry {toggle = 1 - Toggle,
					  life_timer = NewTimer,
					  com_status = ok}).

start_life_timer(_Slave=#nmt_entry {guard_time = GT, life_factor = LF, id = Id}) ->
    case GT * LF of
	0 -> 
	    undefined; %% No node guarding
	NLT ->
	    {ok, TRef} = 
		timer:send_after(NLT, {node_guard_timeout, Id}),
	    TRef
    end.

cancel_life_timer(_Slave=#nmt_entry {life_timer = undefined}) ->
    do_nothing;
cancel_life_timer(_Slave=#nmt_entry {life_timer = Timer}) ->
    timer:cancel(Timer).

start_guard_timer(_Slave=#nmt_entry {guard_time = 0}) ->
    undefined; %% No node guarding
start_guard_timer(_Slave=#nmt_entry {guard_time = GT, id = Id}) ->
    {ok, TRef} = 
	timer:send_interval(GT, {do_node_guard, Id}),
    TRef.

cancel_guard_timer(_Slave=#nmt_entry {guard_timer = undefined}) ->
    do_nothing;
cancel_guard_timer(_Slave=#nmt_entry {guard_timer = Timer}) ->
    timer:cancel(Timer).


send_nmt_state_change(SlaveId, Cs) ->
    can:send(#can_frame { id = ?COBID_TO_CANID(?NMT_ID),
			  len = 2,
			  data = <<Cs:8, SlaveId:8>>}).

send_node_guard(SlaveId, NodePid) ->
    ?dbg(nmt, "send_node_guard: slave ~.16#", [SlaveId]),
    Id = 
	if ?is_nodeid_extended(SlaveId) ->
		?COBID_TO_CANID(?XCOB_ID(?NODE_GUARD,SlaveId)) 
		    bor ?CAN_RTR_FLAG;
	   ?is_nodeid(SlaveId) ->
		?COBID_TO_CANID(?COB_ID(?NODE_GUARD,SlaveId)) 
		    bor ?CAN_RTR_FLAG
	end,
    can:send_from(NodePid, #can_frame { id = Id, len = 0, data = <<>>}).



    


