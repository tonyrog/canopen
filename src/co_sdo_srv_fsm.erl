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
-include("canopen.hrl").
-include("sdo.hrl").

%% API
-export([start/3]).

%% gen_fsm callbacks
-export([init/1, handle_event/3,
	 handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% Segment download
-export([s_initial/2]).
-export([s_writing/2]).
-export([s_segmented_download/2]).
-export([s_writing_segment_started/2]). %% Streamed
-export([s_writing_segment/2]).         %% Streamed

%% Segment upload
-export([s_segmented_upload/2]).
-export([s_reading_segment_started/2]). %% Streamed
-export([s_reading_segment_first/2]).   %% Streamed
-export([s_reading_segment/2]).         %% Streamed

%% Block upload
-export([s_block_upload_start/2]).
-export([s_block_upload_response/2]).
-export([s_block_upload_response_last/2]).
-export([s_block_upload_end_response/2]).
-export([s_reading_block_started/2]).   %% Streamed
-export([s_reading_block/2]).           %% Streamed

%% Block download
-export([s_block_download/2]).
-export([s_block_download_end/2]).
-export([s_writing_block_started/2]).   %% Streamed
-export([s_writing_block/2]).           %% Streamed

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
      exp    = 0,
      size_ind = 0,
      pst    = 0,
      clientcrc = 0,
      t      = 0,         %% Toggle value
      crc    = false,     %% Check or Generate CRC
      blksize  = 0,
      blkseq   = 0,
      blkbytes = 0,
      first = true,
      node_pid = NodePid,
      ctx      = Ctx,
      streamed = false
      %% th is not the transfer handle
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
	    S1 = S#co_session{index=IX, subind=SI, exp=Expedited, 
			      data=Data, size_ind=SizeInd, n=N},
	    case co_transfer:write_begin(S#co_session.ctx,IX,SI) of
		{error,Reason} ->
		    abort(S1, Reason);
		{ok, TH, MaxSize}  when is_integer(MaxSize) ->
		    %% FIXME: check if max_size already set, reject if bad
		    start_segment_download(S1, TH, IX, SI);
		{ok, TH, Mref} when is_reference(Mref) ->
		    S2 = S1#co_session { th=TH, mref=Mref },
		    {next_state, s_writing_segment_started,S2,?TMO(S2)}
	    end;

	?ma_ccs_block_download_request(ChkCrc,SizeInd,IX,SI,Size) ->
	    S1 = S#co_session { index=IX, subind=SI, 
				size_ind=SizeInd, crc=ChkCrc, size=Size},
	    case co_transfer:write_begin(S1#co_session.ctx,IX,SI) of
		{error,Reason} ->
		    abort(S1, Reason);
		{ok, TH, MaxSize} when is_integer(MaxSize) -> 
		    %% FIXME: check if max_size already set, reject if bad
		    start_block_download(S1, TH, IX, SI);
		{ok, TH, Mref} ->
		    S2 = S1#co_session { th=TH, mref=Mref },
		    {next_state, s_writing_block_started,S2,?TMO(S2)}
	    end;

	?ma_ccs_initiate_upload_request(IX,SI) ->
	    S1 = S#co_session {index=IX,subind=SI},
	    case co_transfer:read_begin(S1#co_session.ctx, IX, SI) of
		{error,Reason} ->
		    abort(S1, Reason);
		{ok, TH, NBytes} when is_integer(NBytes) ->
		    start_segmented_upload(S1#co_session {th = TH});
		{ok, TH, Mref} when is_reference(Mref) ->
		    S2 = S1#co_session {mref = Mref, th = TH},
		    {next_state, s_reading_segment_started, S2, ?TMO(S2)}
	    end;

	?ma_ccs_block_upload_request(GenCrc,IX,SI,BlkSize,Pst) ->
	    ?dbg("~p: s_initial: block_upload_request blksize = ~p\n",
		 [?MODULE, BlkSize]),
	    S1 = S#co_session {index=IX, subind=SI, pst=Pst, blksize=BlkSize, clientcrc=GenCrc},
	    case co_transfer:read_begin(S1#co_session.ctx, IX, SI) of
		{error,Reason} ->
		    ?dbg("start block upload error=~p\n", [Reason]),
		    abort(S1, Reason);
		{ok, TH, NBytes} when Pst =/= 0, NBytes > 0, NBytes =< Pst ->
		    ?dbg("protocol switch\n",[]),
		    start_segmented_upload(S1#co_session {th = TH});
		{ok, TH, NBytes} when is_integer(NBytes) ->
		    start_block_upload(S1#co_session {th = TH});
		{ok, TH, Mref} when is_reference(Mref) ->
		    S2 = S1#co_session {mref = Mref, th = TH},
		    {next_state, s_reading_block_started, S2, ?TMO(S2)}
	    end;
	_ ->
	    l_abort(M, S, s_initial)
    end;
s_initial(timeout, S) ->
    {stop, timeout, S}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% SEGMENT DOWNLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_segment_download(S, TH, IX, SI) ->
    if S#co_session.exp =:= 1 ->
	    %% Only one segment to write
	    NBytes = if S#co_session.size_ind =:= 1 -> 4-S#co_session.n;
			true -> 0
		     end,
	    %% FIXME: async transfer function with sub-state
	    co_transfer:write_size(TH, NBytes),
	    write_one_segment_and_respond(S, TH, IX, SI, NBytes);
       true ->
	    respond(S, TH, IX, SI)
    end.

write_one_segment_and_respond(S, TH, IX, SI, NBytes) ->
    ?dbg("~p: write_one_segment_and_respond:\n", [?MODULE]),
    case co_transfer:write(TH, S#co_session.data, NBytes) of
	{error,Reason} ->
	    abort(S, Reason);
	{ok,TH1,NWrBytes} ->
	    case co_transfer:write_end(S#co_session.ctx, TH1, NWrBytes) of
		{ok, Mref} ->
		    %% Called an application
		    S1 = S#co_session {mref = Mref},
		    {next_state, s_writing, S1, ?TMO(S1)};
		ok ->
		    R = ?mk_scs_initiate_download_response(IX,SI),
		    send(S, R),
		    {stop, normal, S};
		{error,Reason} ->
		    abort(S, Reason)
	    end
    end.

respond(S, TH, IX, SI) ->
    ?dbg("~p: respond:\n", [?MODULE]),
    %% FIXME: check if max_size already set
    %% reject if bad!
    TH1 = if S#co_session.size_ind =:= 1 -> 
		  <<Size:32/?SDO_ENDIAN>> = S#co_session.data,
		  co_transfer:write_max_size(TH, Size);
	     true ->
		  co_transfer:write_max_size(TH, 0)
	  end,
    %% set T=1 since client will start with 0
    S1 = S#co_session { th=TH1, t=1 },
    R  = ?mk_scs_initiate_download_response(IX,SI),
    send(S1, R),
    {next_state, s_segmented_download, S1, ?TMO(S1)}.

%%
%% state: writing
%%    next_state:  no state
%%
s_writing({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_writing: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, ok} ->
	    erlang:demonitor(Mref, [flush]),
	    R = ?mk_scs_initiate_download_response(S#co_session.index, 
						   S#co_session.subind),
	    send(S,R),
	    {stop, normal, S};
	_Other ->
	    l_abort(M, S, s_writing)
    end;
s_writing(M, S)  ->
    ?dbg("~p: s_writing: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).

%%
%% state: segmented_download
%%    next_state:  segmented_download or s_writing_segment
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
			    case co_transfer:write_end(S#co_session.ctx, TH1, 0) of
				{ok, Mref} ->
				    %% Called an application
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

%%
%% state: writing_segment_started (for application stored data)
%%    next_state:  s_writing or s_segment_download
%%
s_writing_segment_started({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_writing_segment_started: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, ok} ->
	    erlang:demonitor(Mref, [flush]),
	    start_segment_download(S, S#co_session.th, 
				   S#co_session.index, S#co_session.subind);
	_Other ->
	    l_abort(M, S, s_writing_segment_started)
    end;
s_writing_segment_started(M, S)  ->
    ?dbg("~p: s_writing_segment_started: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).


%%
%% state: s_writing_segment (for application stored data)
%%    next_state:  No state
%%
s_writing_segment({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_writing_segment: Got event = ~p\n", [?MODULE, M]),
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
    ?dbg("~p: s_writing_segment: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% SEGMENT UPLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_segmented_upload(S) ->
    ?dbg("~p: start_segmented_upload\n", [?MODULE]),
    TH = S#co_session.th,
    IX = S#co_session.index,
    SI = S#co_session.subind,
    NBytes = co_transfer:max_size(TH),
    ?dbg("~p: start_segmented_upload, nbytes = ~p\n", [?MODULE,NBytes]),
    if NBytes =/= 0, NBytes =< 4 ->
	    case co_transfer:read(TH, NBytes) of
		{error,Reason} ->
		    abort(S, Reason);
		{ok,TH1,Data} ->
		    ?dbg("~p: start_segmented_upload, atomic.\n", [?MODULE]),
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

%%
%% state: segment_upload
%%    next_state:  segmented_upload
%%
s_segmented_upload(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_upload_segment_request(T) when T =/= S#co_session.t ->
	    abort(S, ?abort_toggle_not_alternated);
	?ma_ccs_upload_segment_request(T) ->
	    case co_transfer:read(S#co_session.th,7) of
		{ok,TH1,Data} ->
		    ?dbg("~p: s_segmented_upload: data=~p\n", 
			 [?MODULE, Data]),
		    upload_segment(S#co_session {t = T}, TH1, Data);
		{ok, Mref} ->
		    %% Called an application
		    ?dbg("~p: s_segmented_upload: mref=~p\n", 
			 [?MODULE, Mref]),
		    S1 = S#co_session {mref = Mref},
		    {next_state, s_reading_segment, S1, ?TMO(S1)};
		{error,Reason} ->
		    abort(S,Reason)
	    end;
	_ ->
	    l_abort(M, S, s_segmented_upload)
    end;
s_segmented_upload(timeout, S) ->
    abort(S, ?abort_timed_out).

upload_segment(S, TH, Data) ->
    T1 = 1-S#co_session.t,
    Remain = co_transfer:data_size(TH),
    N = 7-size(Data),
    if Remain =:= 0 ->
	    Data1 = co_sdo:pad(Data,7),
	    R = ?mk_scs_upload_segment_response(S#co_session.t,N,1,Data1),
	    send(S,R),
	    co_transfer:read_end(TH),
	    {stop,normal,S};
       true ->
	    Data1 = co_sdo:pad(Data,7),
	    R = ?mk_scs_upload_segment_response(S#co_session.t,N,0,Data1),
	    send(S,R),
	    S1 = S#co_session { t=T1, th=TH },
	    {next_state, s_segmented_upload, S1, ?TMO(S1)}
    end.

%%
%% state: reading_segment_started (for application stored data)
%%    next_state:  reading_segment_first
%%
s_reading_segment_started({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_reading_segment_started: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, Value}} ->
	    erlang:demonitor(Mref, [flush]),
	    Data = co_codec:encode(Value, co_transfer:type(S#co_session.th)),
	    TH = co_transfer:write_max_size(S#co_session.th, size(Data)),
	    TH1 = co_transfer:add_data(TH, Data),
	    start_segmented_upload(S#co_session {th = TH1});
	{Mref, {ok, Ref, Size}} ->
	    %% Check Ref ???
	    erlang:demonitor(Mref, [flush]),
	    S1 = S#co_session {streamed = true},
	    TH = co_transfer:write_max_size(S1#co_session.th, Size),
	    case co_transfer:read(TH, 7) of
		{ok, NewMref} ->
		    %% Called an application
		    ?dbg("~p: s_reading_segment_started: mref=~p\n", 
			 [?MODULE, NewMref]),
		    S2 = S1#co_session {th = TH, mref = NewMref},
		    {next_state, s_reading_segment_first, S2, ?TMO(S2)};
		Other ->
		    %% Should not be possible
		    ?dbg("~p: s_reading_segment_started: got=~p\n", [?MODULE, Other]),
		    l_abort(M, S1, s_reading_segment_started)
	    end;
	_Other ->
	    l_abort(M, S, s_reading_segment_started)
    end;
s_reading_segment_started(M, S)  ->
    ?dbg("~p: s_reading_segment_started: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).

%%
%% state: reading_segment_first (for application stored data)
%%    next_state:  segmented_upload
%%
s_reading_segment_first({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_reading_segment_first: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, Ref, Data}} ->
	    %% Check Ref ???
	    erlang:demonitor(Mref, [flush]),
	    TH = co_transfer:add_data(S#co_session.th, Data),
	    start_segmented_upload(S#co_session {th = TH});
	_Other ->
	    l_abort(M, S, s_reading_segment_first)
    end;
s_reading_segment_first(M, S)  ->
    ?dbg("~p: s_reading_segment_first: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).


%%
%% state: reading_segment (for application stored data)
%%    next_state:  segmented_upload
%%
s_reading_segment({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_reading_segment: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, Ref, Data}} ->
	    erlang:demonitor(Mref, [flush]),
	    ?dbg("~p: s_reading_segment: data = ~p, size = ~p\n", 
		 [?MODULE, Data, size(Data)]),
	    TH = co_transfer:add_data(S#co_session.th, Ref, Data),
	    upload_segment(S, TH, Data);
	_Other ->
	    l_abort(M, S, s_reading_segment)
    end;
s_reading_segment(M, S)  ->
    ?dbg("~p: s_reading_segment: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% BLOCK UPLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_block_upload(S) ->
    TH = S#co_session.th,
    IX = S#co_session.index,
    SI = S#co_session.subind,
    NBytes = case co_transfer:max_size(TH) of
		 unknown -> 0;
		 N -> N
	     end,
    ?dbg("~p: start_block_upload bytes=~p\n", [?MODULE, NBytes]),
    DoCrc = (S#co_session.ctx)#sdo_ctx.use_crc andalso 
						 (S#co_session.clientcrc =:= 1),
    CrcSup = ?UINT1(DoCrc),
    R = ?mk_scs_block_upload_response(CrcSup,?UINT1(NBytes > 0),IX,SI,NBytes),
    S1 = S#co_session { crc=DoCrc, blkcrc=co_crc:init(), blkbytes=0, th=TH },
    send(S1, R),
    {next_state, s_block_upload_start,S1,?TMO(S1)}.

%%
%% state: block_upload_start
%%    next_state:  block_upload_response or block_upload_response_last
%%
s_block_upload_start(M, S)  when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_block_upload_start() ->
	    case (S#co_session.streamed) of
		true ->
		    read_block(S);
		_Other ->
		    read_and_upload_block_segments(S, 1)
		end;
	_ ->
	    l_abort(M, S, s_block_upload_start)
    end;
s_block_upload_start(timeout, S) ->
    abort(S, ?abort_timed_out).

read_block(S) ->
    ?dbg("~p: read_block: size = ~p\n", [?MODULE, 7 * S#co_session.blksize]),
    case co_transfer:read_block(S#co_session.th, 7 * S#co_session.blksize) of
	{error,Reason} ->
	    abort(S,Reason);
	{ok, Mref} when is_reference(Mref) ->
	    %% Called an application
	    S1 = S#co_session {mref = Mref},
	    {next_state, s_reading_block, S1, ?TMO(S1)};
	{ok,TH} ->
	    read_and_upload_block_segments(S#co_session {th = TH}, 1)
    end.


read_and_upload_block_segments(S, Seq) when Seq =< S#co_session.blksize ->
    ?dbg("~p: read_and_upload_block_segments: Seq=~p\n", [?MODULE, Seq]),
    case co_transfer:read(S#co_session.th,7) of
	{error,Reason} ->
	    abort(S,Reason);
	{ok,TH,Data} ->
	    S1 = S#co_session { blkseq=Seq },
	    upload_block_segment(S1, TH, Data)
    end.

upload_block_segment(S, TH, Data) ->
    ?dbg("~p: upload_block_segment: Data = ~p\n", [?MODULE, Data]),
    Seq = S#co_session.blkseq,
    Last = case co_transfer:max_size(TH) of
	       unknown ->
		   case {co_transfer:data_size(TH),
			 S#co_session.blksize,
			 co_transfer:bufdata_size(TH)} of
		       {0, BS, _} when BS > Seq ->
			   %% No more data even though block isn't full
			   %% indicates end of data
			   1;
		       {0, _BS, 0} ->
			   %% No buffered data
			   %% indicates end of data
			   1;
		       _Other ->
			   %% We don't know :-(
			   0
		   end;
	       Remain -> ?UINT1(Remain =:= 0)
	   end,
    Data1 = co_sdo:pad(Data, 7),
    R = ?mk_block_segment(Last,Seq,Data1),
    NBytes = S#co_session.blkbytes + byte_size(Data),
    ?dbg("~p: upload_block_segment: data1 = ~p, nbytes = ~p\n",
	 [?MODULE, Data1, NBytes]),
    Crc = if S#co_session.crc ->
		  co_crc:update(S#co_session.blkcrc, Data);
	     true ->
		  S#co_session.blkcrc
	  end,
    S1 = S#co_session { blkseq=Seq, blkbytes=NBytes, blkcrc=Crc, th=TH },
    send(S1, R),
    if Last =:= 1 ->
	    ?dbg("~p: upload_block_segment: Last = ~p\n", [?MODULE, Last]),
	    {next_state, s_block_upload_response_last, S1, ?TMO(S1)};
       Seq =:= S#co_session.blksize ->
	    ?dbg("~p: upload_block_segment: Seq = ~p\n", [?MODULE, Seq]),
	    {next_state, s_block_upload_response, S1, ?TMO(S1)};
       true ->
	    read_and_upload_block_segments(S1, Seq+1)
    end.

%%
%% state: block_upload_response
%%    next_state: block_upload_response or block_upload_resonse_last 
%%
s_block_upload_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_block_upload_response(AckSeq,BlkSize) 
	  when AckSeq == S#co_session.blkseq ->
	    S1 = S#co_session { blkseq=0, blksize=BlkSize },
	    case (S1#co_session.streamed) of
		true ->
		    read_block(S1);
		_Other ->
		    read_and_upload_block_segments(S1, 1)
		end;
	?ma_ccs_block_upload_response(_AckSeq,_BlkSize) ->
	    abort(S, ?abort_invalid_sequence_number);
	_ ->
	    l_abort(M, S, s_block_upload_response)
    end;
s_block_upload_response(timeout,S) ->
    abort(S, ?abort_timed_out).

%%
%% state: block_upload_response_last
%%    next_state: block_upload_end_response
%%
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

%%
%% state: block_upload_end_response
%%    next_state: No state
%%
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

%%
%% state: reading_block_started (for application stored data)
%%    next_state:  blocked_upload
%%
s_reading_block_started({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_reading_block_started: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, Value}} ->
	    erlang:demonitor(Mref, [flush]),
	    Data = co_codec:encode(Value, co_transfer:type(S#co_session.th)),
	    TH = co_transfer:write_max_size(S#co_session.th, size(Data)),
	    TH1 = co_transfer:add_data(TH, Data),
	    segment_or_block(S, TH1);
	{Mref, {ok, Ref, Size}} ->
	    %% Check Ref ???
	    erlang:demonitor(Mref, [flush]),
	    S1 = S#co_session {streamed = true},
	    TH = co_transfer:write_max_size(S1#co_session.th, Size),
	    start_block_upload(S1#co_session {th = TH});
	_Other ->
	    l_abort(M, S, s_reading_block_started)
    end;
s_reading_block_started(M, S)  ->
    ?dbg("~p: s_reading_block_started: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).

%%
%% state: reading_block (for application stored data)
%%    next_state:  block_upload_start
%%
s_reading_block({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_reading_block: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, Value}} ->
	    erlang:demonitor(Mref, [flush]),
	    Data = co_codec:encode(Value, co_transfer:type(S#co_session.th)),
	    TH = co_transfer:write_max_size(S#co_session.th, size(Data)),
	    TH1 = co_transfer:add_data(TH, Data),
	    segment_or_block(S, TH1);
	{Mref, {ok, Ref, Data}} ->
	    %% Check Ref ???
	    erlang:demonitor(Mref, [flush]),
	    ?dbg("~p: s_reading_block: data = ~p size = ~p\n", 
		 [?MODULE, Data, size(Data)]),
	    
	    if S#co_session.first =:= true andalso
	       Data =:= (<<>>) ->
		    %% No data at all ???
		    ?dbg("~p: s_reading_block: first & no data\n", [?MODULE]),
		    abort(S, ?abort_internal_error);
	       S#co_session.first =:= true andalso
	       (7 * S#co_session.blksize) =:= size(Data) ->
		    %% Full block, buffer it and get the next
		    ?dbg("~p: s_reading_block: first & full\n", [?MODULE]),
		    TH = co_transfer:add_bufdata(S#co_session.th, Data),
		    read_block(S#co_session {th = TH, first = false});
	       S#co_session.first =:= true ->
		    %% Not full block, eof reached in first block
		    ?dbg("~p: s_reading_block: first & not full\n", [?MODULE]),
		    TH = co_transfer:add_data(S#co_session.th, Data),
		    read_and_upload_block_segments(S#co_session {th = TH}, 1);
	       true ->
		    %% Not first so move buffered data to data
		    ?dbg("~p: s_reading_block: not first\n", [?MODULE]),
		    TH = co_transfer:move_and_add_bufdata(S#co_session.th,Data),
		    read_and_upload_block_segments(S#co_session {th = TH}, 1)
	    end;
	_Other ->
	    l_abort(M, S, s_reading_block)
    end;
s_reading_block(M, S)  ->
    ?dbg("~p: s_reading_block: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).

%% Checks if protocol switch from block to segment should be done
segment_or_block(S, TH) -> 
    NBytes = case co_transfer:max_size(TH) of
		 unknown -> 0;
		 N -> N
	     end,
    if S#co_session.pst =/= 0, NBytes > 0, 
       NBytes =< S#co_session.pst ->
	    ?dbg("protocol switch\n",[]),
	    start_segmented_upload(S#co_session {th = TH});
       true ->
	    start_block_upload(S#co_session {th =TH})
    end.

    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% BLOCK DOWNLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start_block_download(S, TH, IX, SI) ->
    TH1 = if S#co_session.size_ind =:= 1 ->
		  co_transfer:write_max_size(TH, S#co_session.size);
	     true ->
		  co_transfer:write_max_size(TH, 0)
	  end,				  
    DoCrc = (S#co_session.ctx)#sdo_ctx.use_crc andalso (S#co_session.crc =:= 1),
    GenCrc = ?UINT1(DoCrc),
    %% FIXME: Calculate the BlkSize from data
    BlkSize = next_blksize(S),
    S1 = S#co_session { crc=DoCrc, blkcrc=co_crc:init(), blksize=BlkSize, th=TH1 },
    R = ?mk_scs_block_initiate_download_response(GenCrc,IX,SI,BlkSize),
    send(S1, R),
    {next_state, s_block_download, S1, ?TMO(S1)}.


%%
%% state: s_block_download
%%    next_state:  s_block_download_end
%%
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

%%
%% state: s_block_download_end
%%    next_state:  No state or s_writing_block
%%
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
		    {next_state, s_writing_block, S1, ?TMO(S1)};
		    
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

%%
%% state: writing_block_started (for application stored data)
%%    next_state:  s_block_download
%%
s_writing_block_started({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_writing_block_started: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, ok} ->
	    erlang:demonitor(Mref, [flush]),
	    start_block_download(S, S#co_session.th, 
				 S#co_session.index, S#co_session.subind);
	_Other ->
	    l_abort(M, S, s_writing_block_started)
    end;
s_writing_block_started(M, S)  ->
    ?dbg("~p: s_writing_block_started: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).


%%
%% state: s_writing_block (for application stored data)
%%    next_state:  No state
%%
s_writing_block({Mref, Reply} = M, S)  ->
    ?dbg("~p: s_writing_block: Got event = ~p\n", [?MODULE, M]),
    case {S#co_session.mref, Reply} of
	{Mref, ok} ->
	    erlang:demonitor(Mref, [flush]),
	    R = ?mk_scs_block_download_end_response(),
	    send(S, R),
	    {stop, normal, S};
	_Other ->
	    l_abort(M, S, s_writing_block)
    end;
s_writing_block(M, S)  ->
    ?dbg("~p: s_writing_block: Got event = ~p, aborting\n", [?MODULE, M]),
    demonitor_and_abort(M, S).


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
    ?dbg("~p: l_abort: Msg = ~p received in state = ~p\n", 
		 [?MODULE, M, State]),
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

    

