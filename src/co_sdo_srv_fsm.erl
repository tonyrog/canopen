%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%    CANopen SDO server FSM
%%% @end
%%% Created :  2 Jun 2010 by Tony Rogvall <tony@rogvall.se>
%%%-------------------------------------------------------------------
-module(co_sdo_srv_fsm).

-behaviour(gen_fsm).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/sdo.hrl").

%% API
-export([start/3]).

%% gen_fsm callbacks
-export([init/1, handle_event/3,
	 handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

-export([s_initial/2]).
-export([s_writing/2]).
-export([s_writing_segment/2]).
-export([s_reading_segment/2]).
-export([s_reading_block/2]).
-export([s_segmented_download/2]).
-export([s_segmented_upload/2]).

-export([s_block_upload_start/2]).
-export([s_block_upload_response/2]).
-export([s_block_upload_response_last/2]).
-export([s_block_upload_end_response/2]).

-export([s_block_download/2]).
-export([s_block_download_end/2]).

-define(TMO(S), ((S)#co_session.ctx)#sdo_ctx.timeout).
-define(BLKTMO(S), ((S)#co_session.ctx)#sdo_ctx.blk_timeout).

-ifdef(debug).
-define(dbg(Fmt,As), io:format(Fmt, As)).
-else.
-define(dbg(Fmt, As), ok).
-endif.
		 
%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @spec start(Ctx, Src, Dst) -> {ok, Pid} | ignore | {error, Error}
%%
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @end
%%--------------------------------------------------------------------
start(Ctx,Src,Dst) when is_record(Ctx, sdo_ctx) ->
    gen_fsm:start(?MODULE, [Ctx,self(),Src,Dst], []).

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @spec init(Args) -> {ok, StateName, State} |
%%                     {ok, StateName, State, Timeout} |
%%                     ignore |
%%                     {stop, StopReason}
%% @doc
%% Whenever a gen_fsm is started using gen_fsm:start/[3,4] or
%% gen_fsm:start_link/[3,4], this function is called by the new
%% process to initialize.
%%
%% @end
%%--------------------------------------------------------------------
init([Ctx,NodePid,Src,Dst]) ->
    ?dbg("co_sdo_srv_fsm: started src=~p, dst=~p \n", [Src, Dst]),
    S0 = #co_session {
      src    = Src,
      dst    = Dst,
      index  = undefined,
      subind = undefined,
      t      = 0,         %% Toggle value
      crc    = false,     %% Check or Generate CRC
      blksize  = 0,
      blkseq   = 0,
      blkbytes = 0,
      node_pid = NodePid,
      ctx      = Ctx
      %% th is not the transefer handle
      %% transfer is setup when we know the item
     },
    {ok, s_initial, S0, ?TMO(S0)}.

%%--------------------------------------------------------------------
%% @private
%% @spec state_name(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @end
%%--------------------------------------------------------------------
state_name(_Event, _State) ->
    dummy_for_edoc.

s_initial(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_initiate_download_request(N,Expedited,SizeInd,IX,SI,Data) ->
	    S1 = S#co_session { index=IX, subind=SI },
	    case co_transfer:write_begin(S#co_session.ctx,IX,SI) of
		{error,Reason} ->
		    abort(S1, Reason);
		{ok, TH, _MaxSize} -> %% transfer handle
		    if Expedited =:= 1 ->
			    NBytes = if SizeInd =:= 1 -> 4-N;
					true -> 0
				     end,
			    %% FIXME: async transfer function with sub-state
			    case co_transfer:write(TH, Data, NBytes) of
				{error,Reason} ->
				    abort(S1, Reason);
				{ok,TH1,_NWrBytes} ->
				    case co_transfer:write_end(S1#co_session.ctx, TH1) of
					{ok, Mref} ->
					    S2 = S1#co_session {mref = Mref},
					    {next_state, s_writing, S2, ?TMO(S2)};
					ok ->
					    R = ?mk_scs_initiate_download_response(IX,SI),
					    send(S, R),
					    {stop, normal, S1};
					{error,Reason} ->
					    abort(S1, Reason)
				    end
			    end;
		       true ->
			    %% FIXME: check if max_size already set
			    %% reject if bad!
			    TH1 = if SizeInd =:= 1 -> 
					  <<Size:32/?SDO_ENDIAN>> = Data,
					  co_transfer:write_size(TH, Size);
				     true ->
					  co_transfer:write_size(TH, 0)
				  end,
			    %% set T=1 since client will start with 0
			    S2 = S1#co_session { th=TH1, t=1 },
			    R  = ?mk_scs_initiate_download_response(IX,SI),
			    send(S2, R),
			    {next_state, s_segmented_download,S2,?TMO(S2)}
		    end
	    end;

	?ma_ccs_block_download_request(ChkCrc,SizeInd,IX,SI,Size) ->
	    S1 = S#co_session { index=IX, subind=SI },
	    case co_transfer:write_begin(S1#co_session.ctx,IX,SI) of
		{error,Reason} ->
		    abort(S1, Reason);
		{ok,TH, _MaxSize} -> %% transfer handle
		    %% FIXME: check if max_size already set, reject if bad
		    TH1 = if SizeInd =:= 1 ->
				  co_transfer:write_size(TH, Size);
			     true ->
				  co_transfer:write_size(TH, 0)
			  end,				  
		    DoCrc = (S#co_session.ctx)#sdo_ctx.use_crc andalso (ChkCrc =:= 1),
		    GenCrc = ?UINT1(DoCrc),
		    %% FIXME: Calculate the BlkSize from data
		    BlkSize = next_blksize(S1),
		    S2 = S1#co_session { crc=DoCrc, blkcrc=co_crc:init(),
					 blksize=BlkSize, th=TH1 },
		    R = ?mk_scs_block_initiate_download_response(GenCrc,IX,SI,BlkSize),
		    send(S2, R),
		    {next_state, s_block_download,S2,?TMO(S2)}
	    end;

	?ma_ccs_initiate_upload_request(IX,SI) ->
	    S1 = S#co_session {index=IX,subind=SI},
	    case co_transfer:read_begin(S1#co_session.ctx, IX, SI) of
		{error,Reason} ->
		    abort(S1, Reason);
		{ok, TH, NBytes} ->
		    start_segmented_upload(S1, IX, SI, TH, NBytes);
		{ok, Mref} ->
		    S2 = S1#co_session {mref = Mref},
		    {next_state, s_reading_segment, S2, ?TMO(S2)}
	    end;

	?ma_ccs_block_upload_request(GenCrc,IX,SI,BlkSize,Pst) ->
	    S1 = S#co_session {index=IX, subind=SI, pst=Pst, blksize=BlkSize, clientcrc=GenCrc},
	    case co_transfer:read_begin(S1#co_session.ctx, IX, SI) of
		{error,Reason} ->
		    ?dbg("start block upload error=~p\n", [Reason]),
		    abort(S1, Reason);
		{ok, TH, NBytes} when Pst =/= 0, NBytes > 0, NBytes =< Pst ->
		    ?dbg("protocol switch\n",[]),
		    start_segmented_upload(S1, IX, SI, TH, NBytes);
		{ok, TH, NBytes} ->
		    start_block_upload(S1, IX, SI, TH, NBytes);
		{ok, Mref} ->
		    S2 = S1#co_session {mref = Mref},
		    {next_state, s_reading_block, S2, ?TMO(S2)}
	    end;
	_ ->
	    l_abort(M, S, s_initial)
    end;
s_initial(timeout, S) ->
    {stop, timeout, S}.

s_writing({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_writing: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, ok} ->
	    erlang:demonitor(Mref, [flush]),
	    R = ?mk_scs_initiate_download_response(S#co_session.index, S#co_session.subind),
	    send(S,R),
	    {stop, normal, S};
	_Other ->
	    l_abort(M, S, s_writing)
    end;
s_writing(M, S)  ->
    ?dbg("~p: s_writing: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).

s_writing_segment({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_writing: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, ok} ->
	    erlang:demonitor(Mref, [flush]),
	    R = ?mk_scs_download_segment_response(1-S#co_session.t),
	    send(S,R),
	    {stop, normal, S};
	_Other ->
	    l_abort(M, S, s_writing)
    end;
s_writing_segment(M, S)  ->
    ?dbg("~p: s_writing: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).

s_reading_segment({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_reading_segment: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, {value, Type, Value}} ->
	    erlang:demonitor(Mref, [flush]),
	    Data = co_codec:encode(Value, Type),
	    {ok, TH, NBytes} = 
		co_transfer:app_t_handle(Data, S#co_session.index, S#co_session.subind),
	    start_segmented_upload(S, S#co_session.index, S#co_session.subind, TH, NBytes);

	_Other ->
	    l_abort(M, S, s_reading_segment)
    end;
s_reading_segment(M, S)  ->
    ?dbg("~p: s_reading_segment: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).

s_reading_block({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_reading_block: Got event = ~p\n", [?MODULE, M]),
   case {S#co_session.mref, Reply} of
	{Mref, {value, Type, Value}} ->
	    erlang:demonitor(Mref, [flush]),
	    Data = co_codec:encode(Value, Type),
	    {ok, TH, NBytes} = 
		co_transfer:app_t_handle(Data, S#co_session.index, S#co_session.subind),	    
	    if S#co_session.pst =/= 0, NBytes > 0, NBytes =< S#co_session.pst ->
		    ?dbg("protocol switch\n",[]),
		    start_segmented_upload(S, S#co_session.index, S#co_session.subind, TH, NBytes);
	       true ->
		    start_block_upload(S, S#co_session.index, S#co_session.subind, TH, NBytes)
	    end;
	_Other ->
	    l_abort(M, S, s_reading_block)
    end;
s_reading_block(M, S)  ->
    ?dbg("~p: s_reading_block: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).

start_segmented_upload(S, IX, SI, TH, NBytes) ->
    if NBytes =/= 0, NBytes =< 4 ->
	    case co_transfer:read(TH, NBytes) of
		{error,Reason} ->
		    abort(S, Reason);
		{ok,TH1,Data} ->
		    NRdBytes = size(Data),
		    Data1 = co_sdo:pad(Data, 4),
		    N = 4-NRdBytes,E=1,SizeInd=1,
		    R=?mk_scs_initiate_upload_response(N,E,
						       SizeInd,
						       IX,SI,
						       Data1),
		    send(S, R),
		    co_transfer:read_end(TH1),
		    {stop, normal, S}
	    end;
       NBytes > 4 ->
	    N=0, E=0, SizeInd=1,
	    Data = <<NBytes:32/?SDO_ENDIAN>>,
	    R=?mk_scs_initiate_upload_response(N,E,SizeInd,
					       IX,SI,Data),
	    send(S, R),
	    S1 = S#co_session { th=TH },
	    {next_state, s_segmented_upload, S1, ?TMO(S1)};
       NBytes =:= 0 ->
	    N=0, E=0, SizeInd=0,
	    Data = <<0:32/?SDO_ENDIAN>>, %% filler
	    R=?mk_scs_initiate_upload_response(N,E,SizeInd,
					       IX,SI,Data),
	    send(S, R),
	    S1 = S#co_session { th=TH },
	    {next_state, s_segmented_upload, S1, ?TMO(S1)}
    end.
    
start_block_upload(S, IX, SI, TH, NBytes) ->
    ?dbg("starting block upload bytes=~p\n", [NBytes]),
    SizeInd = ?UINT1(NBytes > 0),
    DoCrc = (S#co_session.ctx)#sdo_ctx.use_crc andalso 
						 (S#co_session.clientcrc =:= 1),
    CrcSup = ?UINT1(DoCrc),
    R = ?mk_scs_block_upload_response(CrcSup,SizeInd,IX,SI,NBytes),
    S1 = S#co_session { crc=DoCrc, blkcrc=co_crc:init(), blkbytes=0, th=TH },
    send(S1, R),
    {next_state, s_block_upload_start,S1,?TMO(S1)}.

%%
%% state: segmented_download
%%    next_state:  segmented_download
%%
s_segmented_download(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_download_segment_request(T,_N,_C,_D) 
	  when T =:= S#co_session.t ->
	    abort(S, ?abort_toggle_not_alternated);

	?ma_ccs_download_segment_request(T,N,Last,Data) ->
	    NBytes = 7-N,
	    case co_transfer:write(S#co_session.th,Data,NBytes) of
		{error,Reason} ->
		    abort(S,Reason);
		{ok,TH1,_NWrBytes} ->
		    %% reply with same toggle value as the request
		    if Last =:= 1 ->
			    case co_transfer:write_end(S#co_session.ctx, TH1) of
				{ok, Mref} ->
				    S1 = S#co_session {mref = Mref},
				    {next_state, s_writing_segment, S1, ?TMO(S1)};
				ok ->
				    R = ?mk_scs_download_segment_response(T),
				    send(S,R),
				    {stop, normal, S};
				{error,Reason} ->
				    abort(S,Reason)
			    end;
		       true ->
			    R = ?mk_scs_download_segment_response(T),
			    send(S,R),
			    S1 = S#co_session { t=T, th=TH1 },
			    {next_state, s_segmented_download, S1,?TMO(S1)}
		    end
	    end;
	_ ->
	    l_abort(M, S, s_segmented_download)
    end;
s_segmented_download(timeout, S) ->
    abort(S, ?abort_timed_out).


s_segmented_upload(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_upload_segment_request(T) when T =/= S#co_session.t ->
	    abort(S, ?abort_toggle_not_alternated);
	?ma_ccs_upload_segment_request(T) ->
	    case co_transfer:read(S#co_session.th,7) of
		{error,Reason} ->
		    abort(S,Reason);
		{ok,TH1,Data} ->
		    ?dbg("s_segmented_upload: data=~p\n", [Data]),
		    T1 = 1-T,
		    Remain = co_transfer:get_size(TH1),
		    N = 7-size(Data),
		    if Remain =:= 0 ->
			    Data1 = co_sdo:pad(Data,7),
			    R = ?mk_scs_upload_segment_response(T,N,1,Data1),
			    send(S,R),
			    co_transfer:read_end(TH1),
			    {stop,normal,S};
		       true ->
			    Data1 = co_sdo:pad(Data,7),
			    R = ?mk_scs_upload_segment_response(T,N,0,Data1),
			    send(S,R),
			    S1 = S#co_session { t=T1, th=TH1 },
			    {next_state, s_segmented_upload, S1, ?TMO(S1)}
		    end
	    end;
	_ ->
	    l_abort(M, S, s_segmented_upload)
    end;
s_segmented_upload(timeout, S) ->
    abort(S, ?abort_timed_out).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% BLOCK UPLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

s_block_upload_start(M, S)  when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_block_upload_start() ->
	    send_block(S,1);
	_ ->
	    l_abort(M, S, s_block_upload_start)
    end;
s_block_upload_start(timeout, S) ->
    abort(S, ?abort_timed_out).


send_block(S, Seq) when Seq =< S#co_session.blksize ->
    case co_transfer:read(S#co_session.th,7) of
	{error,Reason} ->
	    abort(S,Reason);
	{ok,TH,Data} ->
	    Remain = co_transfer:get_size(TH),
	    Last = ?UINT1(Remain =:= 0),
	    Data1 = co_sdo:pad(Data, 7),
	    R = ?mk_block_segment(Last,Seq,Data1),
	    NBytes = S#co_session.blkbytes + byte_size(Data),
	    Crc = if S#co_session.crc ->
			  co_crc:update(S#co_session.blkcrc, Data);
		     true ->
			  S#co_session.blkcrc
		  end,
	    S1 = S#co_session { blkseq=Seq, blkbytes=NBytes, blkcrc=Crc, th=TH },
	    send(S1, R),
	    if Last =:= 1 ->
		    {next_state, s_block_upload_response_last, S1, ?TMO(S1)};
	       Seq =:= S#co_session.blksize ->
		    {next_state, s_block_upload_response, S1, ?TMO(S1)};
	       true ->
		    send_block(S1, Seq+1)
	    end
    end.

s_block_upload_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_block_upload_response(AckSeq,BlkSize) when AckSeq == S#co_session.blkseq ->
	    S1 = S#co_session { blkseq=0, blksize=BlkSize },
	    send_block(S1, 1);
	?ma_ccs_block_upload_response(_AckSeq,_BlkSize) ->
	    abort(S, ?abort_invalid_sequence_number);
	_ ->
	    l_abort(M, S, s_block_upload_response)
    end;
s_block_upload_response(timeout,S) ->
    abort(S, ?abort_timed_out).

s_block_upload_response_last(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_block_upload_response(AckSeq,BlkSize) when AckSeq == S#co_session.blkseq ->
	    S1 = S#co_session { blkseq=0, blksize=BlkSize },
	    CRC = co_crc:final(S1#co_session.blkcrc),
	    N   = (7- (S1#co_session.blkbytes rem 7)) rem 7,
	    R = ?mk_scs_block_upload_end_request(N,CRC),
	    send(S1, R),
	    {next_state, s_block_upload_end_response, S1, ?TMO(S1)};
	?ma_ccs_block_upload_response(_AckSeq,_BlkSize) ->
	    abort(S, ?abort_invalid_sequence_number);	    
	_ ->
	    l_abort(M, S, s_block_upload_response_last)
    end;
s_block_upload_response_last(timeout,S) ->
    abort(S, ?abort_timed_out).

s_block_upload_end_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_block_upload_end_response() ->
	    co_transfer:read_end(S#co_session.th),
	    {stop, normal, S};
	_ ->
	    l_abort(M, S, s_block_upload_end_response)
    end;
s_block_upload_end_response(timeout, S) ->
    abort(S, ?abort_timed_out).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% BLOCK UPLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Here wew receice the block segments
s_block_download(M, S) when is_record(M, can_frame) ->
    NextSeq = S#co_session.blkseq+1,
    case M#can_frame.data of
	?ma_block_segment(Last,Seq,Data) when Seq =:= NextSeq ->
	    case co_transfer:write_block_segment(S#co_session.th,Seq,Data) of
		{error, Reason} ->
		    abort(S, Reason);
		{ok,TH1,_NWrBytes} ->
		    S1 = S#co_session { blkseq=NextSeq, th=TH1 },
		    if Last =:= 1; Seq =:= S1#co_session.blksize ->
			    case co_transfer:write_block_segment_end(TH1) of
				{error,Reason} ->
				    abort(S1, Reason);
				{ok,TH2,_NWrBytes2} ->
				    BlkSize = next_blksize(S1),
				    S2 = S1#co_session { th=TH2, blksize=BlkSize, blkseq=0 },
				    R = ?mk_scs_block_download_response(Seq,BlkSize),
				    send(S2, R),
				    if Last =:= 1 ->
					    {next_state,s_block_download_end,S2,
					     ?TMO(S2)};
				       true ->
					    {next_state,s_block_download,S2,
					     ?TMO(S2)}
				    end
			    end;
		       true ->
			    {next_state, s_block_download, S1, ?BLKTMO(S1)}
		    end
	    end;
	?ma_block_segment(_Last,Seq,_Data) when Seq =:= 0; Seq > S#co_session.blksize ->
	    abort(S, ?abort_invalid_sequence_number);
	?ma_block_segment(_Last,_Seq,_Data) ->
	    %% here we could takecare of out of order data
	    abort(S, ?abort_invalid_sequence_number);
	%% Handle abort and spurious packets ...
	%% We can not use l_abort here because we do not know if message
	%% is an abort or not.
	_ ->
	    abort(S, ?abort_command_specifier)
    end;
s_block_download(timeout, S) ->
    abort(S, ?abort_timed_out).

s_block_download_end(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_block_download_end_request(N,CRC) ->
	    case co_transfer:write_block_end(S#co_session.ctx,
					     S#co_session.th,N,CRC,
					     S#co_session.crc) of	    
		{error,Reason} ->
		    abort(S, Reason);
		{ok, Mref} ->
		    %% Called an application
		    S1 = S#co_session {mref = Mref},
		    {next_state, s_writing, S1, ?TMO(S1)};
		    
		_ -> %% this can be any thing ok | true ..
		    R = ?mk_scs_block_download_end_response(),
		    send(S, R),
		    {stop, normal, S}
	    end;
	_ ->
	    l_abort(M, S, s_block_download_end)
    end;
s_block_download_end(timeout, S) ->
    abort(S, ?abort_timed_out).    


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_all_state_event/2, this function is called to handle
%% the event.
%%
%% @spec handle_event(Event, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_event(Event, StateName, S) ->
    ?dbg("~p: handle_event: Got event ~p\n",[?MODULE, Event]),
    %% FIXME: handle abort here!!!
    apply(?MODULE, StateName, [Event, S]).

%%--------------------------------------------------------------------
%% @private
%% @spec handle_sync_event(Event, From, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {reply, Reply, NextStateName, NextState} |
%%                   {reply, Reply, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState} |
%%                   {stop, Reason, Reply, NewState}
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_all_state_event/[2,3], this function is called
%% to handle the event.
%%
%% @end
%%--------------------------------------------------------------------
handle_sync_event(Event, _From, StateName, State) ->
    ?dbg("~p: handle_sync_event: Got event ~p\n",[?MODULE, Event]),
    Reply = ok,
    {reply, Reply, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_info(Info,StateName,State)->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @doc
%% This function is called by a gen_fsm when it receives any
%% message other than a synchronous or asynchronous event
%% (or a system message).
%%
%% @end
%%--------------------------------------------------------------------
handle_info(Info, StateName, State) ->
    ?dbg("~p: handle_info: Got info ~p\n",[?MODULE, Info]),
    apply(?MODULE, StateName, [Info, State]).

%%--------------------------------------------------------------------
%% @private
%% @spec terminate(Reason, StateName, State) -> void()
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _StateName, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, StateName, State, Extra) ->
%%                   {ok, StateName, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

next_blksize(S) ->
    %% We may want to alter this ...
    (S#co_session.ctx)#sdo_ctx.max_blksize.

demonitor_and_abort(M, S) ->
    case S#co_session.mref of
	Mref when is_reference(Mref)->
	    erlang:demonitor(Mref, [flush]);
	_NoRef ->
	    do_nothing
    end,
    l_abort(M, S, s_reading).


l_abort(M, S, State) when is_record(M, can_frame)->
    case M#can_frame.data of
	?ma_ccs_abort_transfer(IX,SI,Code) when
	      IX =:= S#co_session.index,
	      SI =:= S#co_session.subind ->
	    Reason = co_sdo:decode_abort_code(Code),
	    %% remote party has aborted
	    %% gen_server:reply(S#co_session.node_from, {error,Reason}),
	    ?dbg("~p: l_abort: Abort = ~p received in state = ~p, terminating\n", 
		 [?MODULE, Reason, State]),
	    {stop, normal, S};
	?ma_ccs_abort_transfer(_IX,_SI,_Code) ->
	    %% probably a delayed abort for an old session ignore
	    ?dbg("~p: l_abort: Abort for ~7.16.0#:~w received in state = ~p, ignoring\n", 
		 [?MODULE, _IX, _SI, State]),
	    {next_state, State, S, ?TMO(S)};
	_ ->
	    %% we did not expect this command abort
	    ?dbg("~p: l_abort: Unexpected command = ~p received in state = ~p\n", 
		 [?MODULE, M, State]),
	    abort(S, ?abort_command_specifier)
    end;
l_abort(timeout, S, _State) ->
    abort(S, ?abort_timed_out);
l_abort(M, S, State) ->
    ?dbg("~p: l_abort: Event = ~p received in state = ~p\n", [?MODULE, M, State]),
    abort(S, ?abort_internal_error).


abort(S, Reason) ->
    ?dbg("~p: ix=~p, subind=~p, abort reason=~p\n", 
	      [?MODULE, S#co_session.index, S#co_session.subind, Reason]),
    Code = co_sdo:encode_abort_code(Reason),
    R = ?mk_scs_abort_transfer(S#co_session.index, S#co_session.subind, Code),
    send(S, R),
    
    {stop, normal, S}.
    

send(S, Data) when is_binary(Data) ->
    ?dbg("~p: send: ~s\n", [?MODULE, co_format:format_sdo(co_sdo:decode_tx(Data))]),
    Dst = S#co_session.dst,
    ID = if ?is_cobid_extended(Dst) ->
		 (Dst band ?CAN_EFF_MASK) bor ?CAN_EFF_FLAG;
	    true ->
		 (Dst band ?CAN_SFF_MASK)
	 end,
    %% send message as it where sent from the node process
    %% this inhibits the message to be delivered to the node process
    can:send_from(S#co_session.node_pid,ID,8,Data).

    

