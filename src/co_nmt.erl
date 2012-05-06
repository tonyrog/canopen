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
	  nmt_table,  %% 
	  node_map    %% ??
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
-spec add_slave(NodeId::integer()) ->
    ok | {error, Reason::term()}.

add_slave(NodeId) when is_integer(NodeId) ->
    gen_server:call(?NMT_MASTER, {add_slave, NodeId}).

%%--------------------------------------------------------------------
%% @doc
%% Remove slave from supervision.
%% @end
%%--------------------------------------------------------------------
-spec remove_slave(NodeId::integer()) ->
    ok | {error, Reason::term()}.

remove_slave(NodeId) when is_integer(NodeId) ->
    gen_server:call(?NMT_MASTER, {remove_slave, NodeId}).

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

    case proplists:get_value(serial, Args) of
	undefined ->
	    {error, no_serial};
	Serial ->
	    NMT = ets:new(co_nmt_table, [protected, named_table, ordered_set]),
	    MAP = ets:new(co_node_map, []),
	    {ok, #ctx {serial = Serial, nmt_table = NMT, node_map = MAP}}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	{add_slave, NodeId::integer()} |
	{remove_slave, NodeId::integer()} |
	save |
	load |
	{debug, TrueOrFalse::boolean()} |
	stop.

-spec handle_call(Request::call_request(),
		  From::{pid(), term()}, Ctx::#ctx{}) ->
			 {reply, Reply::term(), Ctx::#ctx{}} |
			 {stop, Reason::term(), Reply::term(), Ctx::#ctx{}}.

handle_call({add_slave, NodeId}, _From, Ctx=#ctx {nmt_table = NmtTable}) ->
    ?dbg(nmt, "handle_call: add_slave ~.16#", [NodeId]),
    case ets:lookup(NmtTable, NodeId) of
	[_Slave] -> ok; %% already supervised
	[] -> add_slave(NodeId, Ctx)
    end,
    {reply, ok, Ctx};

handle_call({remove_slave, NodeId}, _From, Ctx=#ctx {nmt_table = NmtTable}) ->
    ?dbg(nmt, "handle_call: remove_slave ~.16#", [NodeId]),
    case ets:lookup(NmtTable, NodeId) of
	[] -> ok; %% not supervised
	[_Slave] -> ets:delete(NmtTable,NodeId)
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
	      io:format("  ID: ~w\n", 
			[E#nmt_entry.id]),
	      io:format("    VENDOR: ~10.16.0#\n", 
			[E#nmt_entry.vendor]),
	      io:format("    SERIAL: ~10.16.0#\n", 
			[E#nmt_entry.serial]),
	      io:format("     STATE: ~s\n", 
			[co_format:state(E#nmt_entry.state)])
      end, ok, Ctx#ctx.nmt_table),
    io:format("---- NODE MAP TABLE ----\n"),
    ets:foldl(
      fun({Sn,NodeId},_) ->
	      io:format("~10.16.0# => ~w\n", [Sn, NodeId])
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
-spec handle_cast(Msg::term(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}}.

handle_cast({node_guard_reply, NodeId, Frame}, Ctx) 
  when Frame#can_frame.len >= 1 ->
    ?dbg(nmt, "handle_cast: node_guard_reply ~w", [Frame]),
    case Frame#can_frame.data of
	<<Toggle:1, State:7, _/binary>> ->
	    case node_guard_toggle(NodeId, Toggle, Ctx) of
		ok ->
		    update_nmt_entry(NodeId, [{state,State}], Ctx);
		nok ->
		    %% Send error ??
		    error_logger:error_msg("Node ~p answered node guard with "
					   "wrong toggle ~p, ignored.", 
					   [NodeId, Toggle]),
		    Ctx
	    end;
	_ ->
	    Ctx
    end,
    {noreply, Ctx}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% Handles 'DOWN' messages for monitored processes.
%% @end
%%--------------------------------------------------------------------
-type info()::
	term().


-spec handle_info(Info::info(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}}.

handle_info(_Info, Ctx) ->
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, Ctx) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _Ctx) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @spec code_change(OldVsn, Ctx, Extra) -> {ok, NewCtx}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, Ctx, _Extra) ->
    {ok, Ctx}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


add_slave(NodeId, _Ctx=#ctx {nmt_table = NmtTable}) ->
    %% get node guard time
    ets:insert(NmtTable, {NodeId}).

set_node_state(Ctx, NodeId, State) ->
    update_nmt_entry(NodeId, [{state,State}], Ctx).

do_node_guard(Ctx, 0) ->
    lists:foreach(
      fun(I) ->
	      update_nmt_entry(I, [{state,?UnknownState}], Ctx)
      end,
      lists:seq(0, 127)),
    send_nmt_node_guard(0),
    Ctx;
do_node_guard(Ctx, I) when I > 0, I =< 127 ->
    update_nmt_entry(I, [{state,?UnknownState}], Ctx),
    send_nmt_node_guard(I),
    Ctx.


send_nmt_state_change(NodeId, Cs) ->
    can:send(#can_frame { id = ?NMT_ID,
			  len = 2,
			  data = <<Cs:8, NodeId:8>>}).

send_nmt_node_guard(NodeId) ->
    ID = ?COB_ID(?NODE_GUARD,NodeId) bor ?CAN_RTR_FLAG,
    can:send(#can_frame { id = ID,
			  len = 0, data = <<>>}).


%% lookup / create nmt entry
lookup_nmt_entry(NodeId, Ctx) ->
    case ets:lookup(Ctx#ctx.nmt_table, NodeId) of
	[] ->
	    #nmt_entry { id = NodeId };
	[E] ->
	    E
    end.

%%
%% Update the Node map table (Serial => NodeId)
%%  Check if nmt entry for node id has a consistent Serial
%%  if not then remove bad mapping
%%
update_node_map(NodeId, Serial, Ctx) ->
    case ets:lookup(Ctx#ctx.nmt_table, NodeId) of
	[E] when E#nmt_entry.serial =/= Serial ->
	    %% remove old mapping
	    ets:delete(Ctx#ctx.node_map, E#nmt_entry.serial),
	    %% update new mapping
	    update_nmt_entry(NodeId, [{serial,Serial}], Ctx);
	_ ->
	    ok
    end,
    ets:insert(Ctx#ctx.node_map, {Serial,NodeId}),
    Ctx.
    
%%    
%% Update the NMT entry (NodeId => #nmt_entry { serial, vendor ... })
%%
update_nmt_entry(NodeId, Opts, Ctx) ->
    E = lookup_nmt_entry(NodeId, Ctx),
    E1 = update_nmt_entry(Opts, E),
    ets:insert(Ctx#ctx.nmt_table, E1),
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


node_guard_toggle(NodeId, Toggle, Ctx) ->   
    E = lookup_nmt_entry(NodeId, Ctx),
    if E#nmt_entry.toggle == Toggle ->
	    ets:insert(Ctx#ctx.nmt_table, E#nmt_entry {toggle = Toggle bxor 16#80}),
	    ok;
       true ->
	    nok
    end.


