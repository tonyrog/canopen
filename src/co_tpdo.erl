%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%  TPDO manager. This server manage ONE TPDO
%%%  it receives updates from dictionary notifications
%%%  or application. It packs and sends the PDO handling
%%%  inhibit timers and sync signals etc.
%%% @end
%%% Created : 16 Jun 2010 by Tony Rogvall <tony@rogvall.se>
%%%-------------------------------------------------------------------
-module(co_tpdo).

-behaviour(gen_server).

-include_lib("can/include/can.hrl").
-include("canopen.hrl").
-include("co_debug.hrl").

%% API
-export([start/3, stop/1]).
-export([rtr/1, sync/1, transmit/1]).
-export([update_param/2]).
-export([update_map/1]).

-import(lists, [map/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% inhibit_time is in 1/100 
-define(INHIBIT_TO_MS(T), (((T)+9) div 10)).

%% PDO descriptor
-record(s,
	{
	  emit = false,        %% true when scheduled to send
	  valid = true,        %% normally true
	  rtr_allowed = true,  %% RTR is allowed
	  inhibit_time = 0,    %% inhibit timer value (0.1 ms)
	  event_timer  = 0,    %% event rate
	  res_table,           %% reference to reserver table
	  dict,                %% reference to object dictionary
	  from,                %% Can frame originator
	  offset,              %% This is the pdo offset
	  id,                  %% CAN frame id
	  cob_id,              %% the cobid (translated)
	  transmission_type,   %% transmisssion type 
	  count,               %% current sync count
	  itmr=false,          %% Inhibit timer ref
	  etmr=false,          %% Event timer ref
	  index_list=[],       %% Map index list [{Index,SubIndex}]
	  type_list=[]         %% Map type list [{Type,BitLen}]
	}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @spec start(Dict, Param) -> {ok, Pid} | ignore | {error, Error}
%%
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
start(ResTable, Dict, Param) ->
    gen_server:start_link(?MODULE, [ResTable, Dict, Param, self()], []).

%% stop
stop(Pid) ->
    gen_server:call(Pid, stop).

sync(Pid) ->
    gen_server:cast(Pid, sync).

rtr(Pid) ->
    gen_server:cast(Pid, rtr).

transmit(Pid) ->
    gen_server:cast(Pid, transmit).

update_param(Pid, Param) ->
    gen_server:call(Pid, {update_param, Param}).

update_map(Pid) ->
    gen_server:call(Pid, update_map).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
init([ResTable, Dict, Param, FromPid]) ->
    put(dbg, true),
    ?dbg(tpdo, "init: param = ~p\n", [Param]),
    Valid = Param#pdo_parameter.valid,
    COBID = Param#pdo_parameter.cob_id,
    ID = if (COBID band ?COBID_ENTRY_EXTENDED) =/= 0 ->
		 (COBID band ?COBID_ENTRY_ID_MASK) bor ?CAN_EFF_FLAG;
	    true ->
		 (COBID band ?COBID_ENTRY_ID_MASK)
	 end,
    I = Param#pdo_parameter.offset,
    {Ts,Is} = tpdo_mapping(I, ResTable, Dict),
    %% May start an event timer
    Trans = Param#pdo_parameter.transmission_type,
    ETmr = if Valid, Param#pdo_parameter.event_timer > 0,Trans >= ?TRANS_RTR ->
		   start_timer(Param#pdo_parameter.event_timer,event);
	      true ->
		   false
	   end,
    Count = if not Valid -> 0;
	       Trans > ?TRANS_SYNC_MAX -> 0;
	       true -> Trans
	    end,
    S = #s { emit = false,
	     valid = Valid, %% normally true!
	     rtr_allowed = Param#pdo_parameter.rtr_allowed,
	     cob_id = COBID,
	     id     = ID,
	     res_table = ResTable,
	     dict   = Dict,
	     from   = FromPid,
	     offset = I,
	     transmission_type = Trans,
	     count        = Count,
	     event_timer  = Param#pdo_parameter.event_timer,
	     inhibit_time = Param#pdo_parameter.inhibit_time,
	     index_list = Is,
	     type_list = Ts,
	     etmr = ETmr,
	     itmr = false
	   },
    {ok, S}.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
handle_call({update_param,Param}, _From, S) ->
    ?dbg(tpdo, "handle_call: update_param\n", []),
    Valid = Param#pdo_parameter.valid,
    ITmr0 = if not Valid; Param#pdo_parameter.inhibit_time =:= 0 ->
		    stop_timer(S#s.itmr);
	       true -> S#s.itmr
	    end,
    ETmr0 = if not Valid; Param#pdo_parameter.event_timer =:= 0 ->
		    stop_timer(S#s.etmr);
	       true -> 
		    S#s.etmr
	    end,
    COBID = Param#pdo_parameter.cob_id,
    ID = if (COBID band ?COBID_ENTRY_EXTENDED) =/= 0 ->
		 (COBID band ?COBID_ENTRY_ID_MASK) bor ?CAN_EFF_FLAG;
	    true ->
		 (COBID band ?COBID_ENTRY_ID_MASK)
	 end,
    {Ts,Is} =
	if Valid, COBID =/= S#s.cob_id ->
		tpdo_mapping(Param#pdo_parameter.offset, S#s.res_table, S#s.dict);
	   Valid, Param#pdo_parameter.offset =/= S#s.offset ->
		tpdo_mapping(Param#pdo_parameter.offset, S#s.res_table, S#s.dict);
	   not Valid ->
		{[],[]};
	   true ->
		{S#s.type_list, S#s.index_list}
	end,
    Trans = Param#pdo_parameter.transmission_type,
    Count0 = S#s.count,
    Count1 = if not Valid -> 0;
		Trans > ?TRANS_SYNC_MAX -> 0;
		Count0 < Trans -> Count0;
		true -> Trans
	     end,
    %% May start an event timer 
    %%  FIXME: what about changed event_timer, less or greater (> 0)
    %%         We may have to check remaining time to know
    %%         Right now let event timer trigger and set rate then
    ETmr1 = if ETmr0 =:= false,
	       Valid,Param#pdo_parameter.event_timer > 0,Trans >= ?TRANS_RTR ->
		    start_timer(S#s.event_timer,event);
	       true ->
		    ETmr0
	    end,
    Emit = if not Valid -> false;
	      %% more Conditions for setting to false?
	      true -> S#s.emit
	   end,
    S1 = S#s { 
	   emit              = Emit,
	   valid             = Valid,
	   rtr_allowed       = Param#pdo_parameter.rtr_allowed,
	   inhibit_time      = Param#pdo_parameter.inhibit_time,
	   event_timer       = Param#pdo_parameter.event_timer,
	   offset            = Param#pdo_parameter.offset,
	   cob_id            = COBID,
	   id                = ID,
	   transmission_type = Trans,
	   count             = Count1,
	   itmr              = ITmr0,
	   etmr              = ETmr1,
	   index_list        = Is,
	   type_list         = Ts
	  },
    {reply, ok, S1};
handle_call(update_map, _From, S) ->
    ?dbg(tpdo, "handle_call: update_map\n", []),
    {Ts,Is} =
	if S#s.valid ->
		tpdo_mapping(S#s.offset, S#s.res_table, S#s.dict);
	   true ->
		{[],[]}
	end,
    S1 = S#s { index_list = Is, type_list=Ts },
    {reply, ok, S1};
handle_call(stop, _From, S) ->
    ?dbg(tpdo, "handle_call: stop\n", []),
    {stop, normal, S};
handle_call(_Request, _From, S) ->
    {reply, {error,bad_call}, S}.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
handle_cast(sync, S) ->
    {noreply, do_sync(S)};
handle_cast(rtr, S) ->
    {noreply, do_rtr(S)};
handle_cast(transmit, S) ->
    {noreply, do_transmit(S)};
handle_cast(_Msg, S) ->
    {noreply, S}.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @doc
%% Handling all non call/cast messages
%%
%% @end
%%--------------------------------------------------------------------
handle_info({timeout,Ref,inhibit}, S) when S#s.itmr =:= Ref ->
    {noreply, do_send(S#s { itmr=false }, S#s.emit)};
handle_info({timeout,Ref,event}, S) when S#s.etmr =:= Ref ->
    ETmr = start_timer(S#s.event_timer,event), %% restart
    {noreply, do_send(S#s { etmr=ETmr }, true)};
handle_info(_Info, S) ->
    {noreply, S}.

%%--------------------------------------------------------------------
%% @private
%% @spec terminate(Reason, State) -> void()
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @doc
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

tpdo_mapping(Offset, ResTable, Dict) ->
    %% cob_id is changed!
    ?dbg(tpdo, "tpdo_mapping: offset=~8.16.0#\n", [Offset]),
    case co_node:tpdo_mapping(Offset, ResTable, Dict) of
	{pdo,Mapping} -> 
	    ?dbg(tpdo, "tpdo_mapping: mapping = ~p\n", [Mapping]),
	    Mapping;
	%% {mpdo,Mapping} -> %% FIXME
	_Error ->
	    ?dbg(tpdo, "tpdo_mapping: mapping error= ~p\n", [_Error]),
	    {[],[]}
    end.

do_transmit(S) ->
    ?dbg(tpdo, "do_transmit:\n", []),
    if S#s.transmission_type =:= ?TRANS_SYNC_ONCE ->
	    S#s { emit=true }; %% send at next sync
       S#s.transmission_type >= ?TRANS_RTR_SYNC ->
	    do_send(S,true);
       true ->
	    S  %% ignore, produce error
    end.

do_rtr(S) ->
    ?dbg(tpdo, "do_rtr:\n", []),
    if S#s.rtr_allowed ->
	    if S#s.transmission_type =:= ?TRANS_RTR_SYNC ->
		    S#s { emit=true };  %% send at next sync
	       S#s.transmission_type =:= ?TRANS_RTR ->
		    do_send(S, true);
	       true ->
		    S %% Ignored
	    end;
       true ->
	    S  %% ignored
    end.

do_sync(S) ->
    ?dbg(tpdo, "do_sync:\n", []),
    if S#s.transmission_type =:= ?TRANS_RTR_SYNC ->
	    do_send(S, S#s.emit);
       S#s.transmission_type =:= ?TRANS_SYNC_ONCE ->
	    do_send(S, S#s.emit);
       S#s.transmission_type =< ?TRANS_SYNC_MAX ->
	    Count = S#s.count - 1,
	    ?dbg(tpdo, "do_sync: count=~w\n", [Count]),
	    if Count =:= 0 ->
		    do_send(S#s { count=S#s.transmission_type }, true);
	       true ->
		    S#s { count=Count }
	    end;
       true ->
	    S
    end.

do_send(S,true) ->
    ?dbg(tpdo, "do_send:\n", []),
    if S#s.itmr =:= false ->
	    Ds = map(fun({IX,SI}) -> 
			     {ok, V} = 
				 co_node:value({IX, SI}, S#s.res_table, S#s.dict),
			     V
		     end,
		     S#s.index_list),
	    ?dbg(tpdo, "do_send: values = ~p, types = ~p", [Ds, S#s.type_list]),
	    Data = co_codec:encode(Ds, S#s.type_list),
	    Frame = #can_frame { id = S#s.id,
				 len = byte_size(Data),
				 data = Data },
	    can:send_from(S#s.from, Frame),
	    ITmr = start_timer(?INHIBIT_TO_MS(S#s.inhibit_time), inhibit),
	    S#s { emit=false, itmr=ITmr };
       true ->
	    S#s { emit=true }  %% inhibit is running, delay transmission
    end;
do_send(S,false) ->
    S.

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
    
