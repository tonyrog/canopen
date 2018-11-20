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
%%%  TPDO manager. 
%%%  This server manages ONE TPDO. <br/>
%%%  It receives updates from dictionary notifications
%%%  or application. It packs and sends the PDO handling
%%%  inhibit timers and sync signals etc.
%%%
%%% File: co_tpdo.erl <br/>
%%% Created: 16 Jun 2010 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(co_tpdo).

-behaviour(gen_server).

-include_lib("can/include/can.hrl").
-include("canopen.hrl").
-include("co_debug.hrl").

%% API
-export([start/2, stop/1]).
-export([rtr/1, sync/1, transmit/1, transmit/2]).
-export([update_param/2]).
-export([update_map/1]).

-import(lists, [map/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% Test
-export([debug/2]).
-export([loop_data/1]).

%% inhibit_time is in 1/100 
-define(INHIBIT_TO_MS(T), (((T)+9) div 10)).

%% PDO descriptor
-record(s,
	{
	  state = ?Initialisation, %% State, see canopen.hrl
	  type,                %% pdo | dam_mpdo | sam_mpdo
	  emit = false,        %% true when scheduled to send
	  valid = true,        %% normally true
	  rtr_allowed = true,  %% RTR is allowed
	  inhibit_time = 0,    %% inhibit timer value (0.1 ms)
	  event_timer  = 0,    %% event rate
	  ctx,                 %% context from co_node
	  from,                %% Can frame originator
	  offset,              %% This is the pdo offset
	  id,                  %% CAN frame id
	  cob_id,              %% the cobid (translated)
	  transmission_type,   %% transmisssion type 
	  count,               %% current sync count
	  itmr=false,          %% Inhibit timer ref
	  etmr=false,          %% Event timer ref
	  index_list=[]        %% Map index list [{{Index,SubIndex}, BitLen}]
	}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% Arguments are:
%% <ul>
%% <li> Ctx - record tpdo_ctx(), see {@link canopen}. </li>
%% <li> Param - record pdo_param(), see {@link canopen}. </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec start(Ctx::#tpdo_ctx{}, Param::#pdo_parameter{}) -> 
		   {ok, Pid::pid()} | ignore | {error, Error::atom()}.

start(Ctx, Param) ->
    gen_server:start_link(?MODULE, [Ctx, Param, self()], []).

%% stop
stop(Pid) ->
    gen_server:call(Pid, stop).

sync(Pid) ->
    gen_server:cast(Pid, sync).

rtr(Pid) ->
    gen_server:cast(Pid, rtr).

transmit(Pid) ->
    gen_server:cast(Pid, transmit).

transmit(Pid, Destination) ->
    gen_server:cast(Pid, {transmit, Destination}).

update_param(Pid, Param) ->
    gen_server:call(Pid, {update_param, Param}).

update_map(Pid) ->
    gen_server:call(Pid, update_map).

debug(Pid, TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(Pid, {debug, TrueOrFalse}).

loop_data(Pid) ->
    gen_server:call(Pid, loop_data).


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
init([Ctx, Param, FromPid]) ->
    case Ctx#tpdo_ctx.debug of 
        true -> co_lib:debug(true);
        _ -> do_nothing
    end,
    ?dbg("init: param = ~p", [Param]),
    Valid = Param#pdo_parameter.valid,
    COBID = Param#pdo_parameter.cob_id,
    ID = if (COBID band ?COBID_ENTRY_EXTENDED) =/= 0 ->
		 (COBID band ?COBID_ENTRY_ID_MASK) bor ?CAN_EFF_FLAG;
	    true ->
		 (COBID band ?COBID_ENTRY_ID_MASK)
	 end,
    I = Param#pdo_parameter.offset,
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

    S = #s { state = ?Initialisation, 
	     emit = false,
	     valid = Valid, %% normally true!
	     rtr_allowed = Param#pdo_parameter.rtr_allowed,
	     cob_id = COBID,
	     id     = ID,
	     ctx    = Ctx,
	     from   = FromPid,
	     offset = I,
	     transmission_type = Trans,
	     count        = Count,
	     event_timer  = Param#pdo_parameter.event_timer,
	     inhibit_time = Param#pdo_parameter.inhibit_time,
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
    ?dbg("handle_call: update_param", []),
    S1 = update_param_int(Param, S),
    {reply, ok, S1};
handle_call(update_map, _From, S) ->
    ?dbg("handle_call: update_map", []),
    {Type, Is} =
	if S#s.valid andalso S#s.state == ?Operational ->
		tpdo_mapping(S#s.offset, S#s.ctx);
	   true ->
		{undefined, []}
	end,
    S1 = S#s { type = Type, index_list = Is },
    {reply, ok, S1};
handle_call({debug, TrueOrFalse}, _From, S) ->
    co_lib:debug(TrueOrFalse),
    {reply, ok, S};
handle_call(loop_data, _From, S) ->
    io:format("Loop data = ~p\n", [S]),
    {reply, ok, S};
handle_call(stop, _From, S) ->
    ?dbg("handle_call: stop", []),
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
handle_cast({state, State}, S=#s {offset = I, ctx = Ctx}) 
  when State == ?Operational ->
    ?dbg("handle_cast: state ~p", [State]),
    {Type, Is} = tpdo_mapping(I, Ctx),
    {noreply, S#s {state = State, type = Type, index_list = Is}};
handle_cast({state, State}, S) ->
    {noreply, S#s {state = State}};
handle_cast({nodeid_change, nodeid, OldNid, NewNid},  
	    S=#s {ctx = Ctx=#tpdo_ctx {nodeid = OldNid}, type = Type}) ->
    case {NewNid, Type} of
	{undefined, sam_mpdo} -> 
	    ?ew("~p: (Short) nodeid undefined"
		"not possible to send sam-mpdos", 
		[self()]);
	{undefined, _OtherType} ->
	    ?dbg("handle_cast: nodeid set to undefined", []);
	_Defined ->
	    ?dbg("handle_cast: new nodeid ~5.16.0#", [NewNid])
    end,
    NewCtx = Ctx#tpdo_ctx {nodeid = NewNid},
    {noreply, S#s {ctx = NewCtx}};
handle_cast(sync, S) ->
    {noreply, do_sync(S)};
handle_cast(rtr, S) ->
    {noreply, do_rtr(S)};
handle_cast(transmit, S) ->
    {noreply, do_transmit(S)};
handle_cast({transmit, Destination}, S=#s {type = Type}) 
  when Type == dam_mpdo ->
    {noreply, do_transmit(S, Destination)};
handle_cast(_Msg, S) ->
    ?dbg("handle_cast: Unknown Msg ~p received, Session = ~p", [_Msg, S]),
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
update_param_int(Param, S) ->
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
    {Type, Is} =
	if S#s.state == ?Operational ->
		if Valid, COBID =/= S#s.cob_id ->
			tpdo_mapping(Param#pdo_parameter.offset, S#s.ctx);
		   Valid, Param#pdo_parameter.offset =/= S#s.offset ->
			tpdo_mapping(Param#pdo_parameter.offset, S#s.ctx);
		   not Valid ->
			{tpdo, []};
		   true ->
			{S#s.type, S#s.index_list}
		end;
	   true ->
		{undefined, {[],[]}}
	end,
    Trans = Param#pdo_parameter.transmission_type,

    %% Verify that Trans and Type is valid together ???

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
    S#s { 
      type              = Type,
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
      index_list        = Is
     }.
 

tpdo_mapping(Offset, Ctx) ->
    ?dbg("tpdo_mapping: offset=~.16#", [Offset]),
    case co_api:tpdo_mapping(Offset, Ctx) of
	{Type, Mapping} when Type == tpdo;
			     Type == rpdo;
			     Type == dam_mpdo;
			     Type == sam_mpdo -> 
	    ?dbg("tpdo_mapping: ~p mapping = ~p", [Type, Mapping]),
	    {Type, Mapping};
	_Error ->
	    ?dbg("tpdo_mapping: mapping error= ~p", [_Error]),
	    %% Should we terminate ??
	    {undefined, {[],[]}} 
    end.

do_transmit(S=#s {state = ?Operational})->
    ?dbg("do_transmit:", []),
    if S#s.transmission_type =:= ?TRANS_SYNC_ONCE ->
	    S#s { emit=true }; %% send at next sync
       S#s.transmission_type >= ?TRANS_RTR_SYNC ->
	    do_send(S,true);
       true ->
	    S  %% ignore, produce error
    end;
do_transmit(S) ->
    S.

do_transmit(S=#s {state = ?Operational, type = dam_mpdo}, Destination)->
    ?dbg("do_transmit: dam_mpdo to ~p", [Destination]),
    do_send(S,Destination, true);
do_transmit(S, _Destination) ->
    ?dbg("do_transmit: dam_mpdo to ~p, wrong type/state in session ~p", 
	[_Destination, S]),
    S.

do_rtr(S=#s {state = ?Operational}) ->
    ?dbg("do_rtr:", []),
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
    end;
do_rtr(S) ->
    S.


do_sync(S=#s {state = ?Operational}) ->
    ?dbg("do_sync:", []),
    if S#s.transmission_type =:= ?TRANS_RTR_SYNC ->
	    do_send(S, S#s.emit);
       S#s.transmission_type =:= ?TRANS_SYNC_ONCE ->
	    do_send(S, S#s.emit);
       S#s.transmission_type =< ?TRANS_SYNC_MAX ->
	    Count = S#s.count - 1,
	    ?dbg("do_sync: count=~w", [Count]),
	    if Count =:= 0 ->
		    do_send(S#s { count=S#s.transmission_type }, true);
	       true ->
		    S#s { count=Count }
	    end;
       true ->
	    S
    end;
do_sync(S) ->
    S.

do_send(S=#s {state = ?Operational, type = tpdo, itmr = false}, true)->
    send_tpdo(S);
do_send(S=#s {state = ?Operational, type = sam_mpdo, itmr = false,
	      ctx = #tpdo_ctx {nodeid = Nid}, 
	      index_list = [{{{Ix, Si}, BlockSize}, ?MPDO_DATA_SIZE}]}, 
	true) 
  when Nid =/= undefined ->
    ?dbg("do_send: sam_mpdo index = ~7.16.0#:~w, block_size = ~w", 
	 [Ix, Si, BlockSize]),
    IndexList = [{Ix, I} || I <- lists:seq(Si, Si + BlockSize - 1)],
    send_sam_mpdo(S, IndexList);
do_send(S=#s {state = ?Operational, itmr = Itmr}, true) 
  when Itmr =/= false ->
    S#s { emit=true };  %% inhibit is running, delay transmission
do_send(S,true) ->
    ?dbg("do_send: invalid combination, session = ~p", [S]),
    S;
do_send(S,_) ->
    S.

do_send(S=#s {state = ?Operational, type = dam_mpdo, itmr = false,
	      index_list = [{_Index, Size}]}, 
	Destination, true) 
  when Size =< ?MPDO_DATA_SIZE->
    send_dam_mpdo(S, Destination);
do_send(S=#s {state = ?Operational, itmr = Itmr}, _Dest, true) 
  when Itmr =/= false ->
    S#s { emit=true };  %% inhibit is running, delay transmission
do_send(S,_Dest,true) ->
    ?dbg("do_send: invalid combination, session = ~p, destination = ~p", 
	 [S, _Dest]),
    S.

send_tpdo(S=#s {ctx = Ctx, index_list = IL}) ->
    ?dbg("send_tpdo: indexes = ~w", [IL]),
    case tpdo_data(IL, Ctx, []) of
	{error, Reason} ->
	    ?ee("~p: TPDO value not retreived, reason = ~p\n", 
		[self(), Reason]),
	    S;
	DataList ->
	    ?dbg("send_tpdo: values = ~w, ", [DataList]),
	    BitLenList = [BitLen || {_Ix, BitLen} <- IL],
	    Data = co_codec:encode_pdo(DataList,BitLenList),
	    ?dbg("send_tpdo: data = ~p", [Data]),
	    Frame = #can_frame { id = S#s.id,
				 len = byte_size(Data),
				 data = Data },
	    can:send_from(S#s.from, Frame),
	    ITmr = start_timer(?INHIBIT_TO_MS(S#s.inhibit_time), inhibit),
	    S#s { emit=false, itmr=ITmr }
    end.
    
send_dam_mpdo(S=#s {ctx = Ctx, index_list = [{Index = {Ix, Si}, _Size}]}, 
	      Destination) ->
    ?dbg("send_dam_mpdo, index = ~7.16.0#:~w", [Ix, Si]),
    case co_api:tpdo_data(Index, Ctx) of
	{ok, DataToSend} ->
	    ?dbg("send_dam_mpdo, index data = ~p", [DataToSend]),
	    Dest = case Destination of
		       broadcast -> 0;
		       NodeId -> NodeId
		   end,
	    Data = <<1:1, Dest:7, Ix:16/little, Si:8, DataToSend:4/binary>>,
	    ?dbg("send_dam_mpdo: data = ~p", [Data]),
	    Frame = #can_frame { id = S#s.id,
				 len = byte_size(Data),
				 data = Data },
	    can:send_from(S#s.from, Frame),
	    ITmr = start_timer(?INHIBIT_TO_MS(S#s.inhibit_time), inhibit),
	    S#s { emit=false, itmr=ITmr };
	{error, Reason}->
	    ?ew("~p: TPDO value not retreived, reason = ~p\n", 
		[self(), Reason]),
	    S
    end.

send_sam_mpdo(S, []) -> 
    S;
send_sam_mpdo(S=#s {state = ?Operational, type = sam_mpdo,
		    ctx = Ctx=#tpdo_ctx {nodeid = Nid}},
	      [Index = {Ix, Si} | Ixs]) ->
    ?dbg("send_sam_mpdo, index = ~7.16.0#:~w", [Ix, Si]),
    S1 = 
	case co_api:tpdo_data(Index, Ctx) of
	    {ok, DataToSend} ->
		Data = <<0:1, Nid:7, Ix:16/little, Si:8, DataToSend:4/binary>>,
		?dbg("send_sam_mpdo: data = ~p", [Data]),
		Frame = #can_frame { id = S#s.id,
				     len = byte_size(Data),
				     data = Data },
		can:send_from(S#s.from, Frame),
		ITmr = start_timer(?INHIBIT_TO_MS(S#s.inhibit_time), inhibit),
		S#s { emit=false, itmr=ITmr };
	    {error, Reason} ->
		?ew("~p: TPDO value not retreived, reason = ~p\n", 
		    [self(), Reason]),
		S
	end,
    send_sam_mpdo(S1, Ixs).

tpdo_data([], _Ctx, DataList) ->
    lists:reverse(DataList);
tpdo_data([{Index, _BitLen} | Rest], Ctx, DataList) ->
    case co_api:tpdo_data(Index, Ctx) of
	{ok, Data} ->
	    tpdo_data(Rest, Ctx, [Data | DataList]);
	{error, _Reason} = E->
	    E
    end.

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
    
