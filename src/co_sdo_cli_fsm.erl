%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%   CANopen SDO client FSM
%%% @end
%%% Created :  4 Jun 2010 by Tony Rogvall <tony@rogvall.se>
%%%-------------------------------------------------------------------
-module(co_sdo_cli_fsm).

-behaviour(gen_fsm).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/sdo.hrl").

%% API
-export([store/8, fetch/7]).

%% gen_fsm callbacks
-export([init/1, handle_event/3,
	 handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

-export([s_segmented_download_response/2]).
-export([s_segmented_download/2]).

-export([s_segmented_upload_response/2]).
-export([s_segmented_upload/2]).

-export([s_block_upload_response/2]).
-export([s_block_upload/2]).
-export([s_block_upload_end/2]).

-export([s_block_initiate_download_response/2]).
-export([s_block_download_response/2]).
-export([s_block_download_response_last/2]).
-export([s_block_download_end_response/2]).

-define(TMO(S), ((S)#co_session.ctx)#sdo_ctx.timeout).
-define(BLKTMO(S), ((S)#co_session.ctx)#sdo_ctx.blk_timeout).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @spec store(Ctx,Block,From,Src,Dst,IX,SI,Bin) -> 
%%           {ok, Pid} | ignore | {error, Error}
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @end
%%--------------------------------------------------------------------
store(Ctx,Block,From,Src,Dst,IX,SI,Bin) when is_record(Ctx, sdo_ctx) ->
    gen_fsm:start(?MODULE, 
		  [store,Block,Ctx,From,self(),Src,Dst,IX,SI,Bin], []).

%%--------------------------------------------------------------------
%% @spec fetch(Ctx,Block,From,Src,Dst,IX,SI) -> 
%%           {ok, Pid} | ignore | {error, Error}
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @end
%%--------------------------------------------------------------------
fetch(Ctx,Block,From,Src,Dst,IX,SI) ->
    gen_fsm:start(?MODULE, 
		  [fetch,Block,Ctx,From,self(),Src,Dst,IX,SI], []).

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
init([store,false,Ctx,From,NodePid,Src,Dst,IX,SI,Data]) ->
    Size = byte_size(Data),
    EndF = fun(_Data) -> gen_server:reply(From,ok) end,
    if Size =< 4 ->
	    N = if Size =:= 0 -> 0;
		   true -> 4-Size
		end,
	    Data1 = co_sdo:pad(Data,4),
	    Expedited = 1,
	    SizeInd   = ?UINT1(Size =/= 0),
	    R=?mk_ccs_initiate_download_request(N,Expedited,SizeInd,
						IX,SI,Data1),
	    {ok,TH,_Size1} = co_transfer:read_data_begin(<<>>,IX,SI,EndF),
	    S0 = new_session(Ctx,From,NodePid,Src,Dst,IX,SI,TH),
	    send(S0, R),
	    {ok, s_segmented_download_response, S0, ?TMO(S0)};
       true ->
	    %% FIXME: add streaming protocol Size=0
	    N = 0,
	    Data1 = <<Size:32/?SDO_ENDIAN>>,
	    Expedited = 0,
	    SizeInd = 1,
	    R=?mk_ccs_initiate_download_request(N,Expedited,SizeInd,
						IX,SI,Data1),
	    {ok,TH,_Size1} = co_transfer:read_data_begin(Data,IX,SI,EndF),
	    S0 = new_session(Ctx,From,NodePid,Src,Dst,IX,SI,TH),
	    send(S0, R),
	    {ok, s_segmented_download_response, S0, ?TMO(S0)}
    end;
init([store,true,Ctx,From,NodePid,Src,Dst,IX,SI,Data]) ->
    %% FIXME: stream download
    Size = byte_size(Data),
    EndF = fun(_Data) -> gen_server:reply(From,ok) end,
    {ok,TH,_Size1} = co_transfer:read_data_begin(Data,IX,SI,EndF),
    S0 = new_session(Ctx,From,NodePid,Src,Dst,IX,SI,TH),
    UseCrc = ?UINT1(Ctx#sdo_ctx.use_crc),
    SizeInd = 1,
    R = ?mk_ccs_block_download_request(UseCrc,SizeInd,IX,SI,Size),
    send(S0, R),
    {ok, s_block_initiate_download_response, S0, ?TMO(S0)};
init([fetch,false,Ctx,From,NodePid,Src,Dst,IX,SI]) ->
    EndF = fun(Data) -> gen_server:reply(From,{ok,Data}) end,
    {ok,TH,_MaxSize} = co_transfer:write_data_begin(IX,SI,EndF),
    S0 = new_session(Ctx,From,NodePid,Src,Dst,IX,SI,TH),
    R = ?mk_ccs_initiate_upload_request(IX,SI),
    send(S0, R),
    {ok, s_segmented_upload_response, S0, ?TMO(S0)};
init([fetch,true,Ctx,From,NodePid,Src,Dst,IX,SI]) ->
    EndF = fun(Data) -> gen_server:reply(From,{ok,Data}) end,
    {ok,TH,_MaxSize} = co_transfer:write_data_begin(IX,SI,EndF),
    S0 = new_session(Ctx,From,NodePid,Src,Dst,IX,SI,TH),
    CrcSup = ?UINT1(Ctx#sdo_ctx.use_crc),
    BlkSize = Ctx#sdo_ctx.max_blksize,  %% max number of segments/block
    Pst     = Ctx#sdo_ctx.pst,          %% protcol switch limit 
    R = ?mk_ccs_block_upload_request(CrcSup,IX,SI,BlkSize,Pst),
    send(S0, R),
    S1 = S0#co_session { blksize = BlkSize },
    {ok, s_block_upload_response, S1, ?TMO(S0)}.

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

s_segmented_download_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_initiate_download_response(IX,SI) when 
	      IX =:= S#co_session.index,
	      SI =:= S#co_session.subind ->
	    segmented_download(S);
	_ ->
	    l_abort(M, S, s_segmented_download_response)
    end;
s_segmented_download_response(timeout, S) ->
    abort(S, ?abort_timed_out).
	    
s_segmented_download(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_download_segment_response(T) when T =/= S#co_session.t ->
	    abort(S, ?abort_toggle_not_alternated);
	?ma_scs_download_segment_response(T) ->
	    segmented_download(S#co_session { t=1-T} );
	_ ->
	    l_abort(M, S, s_segmented_download)
    end;
s_segmented_download(timeout, S) ->
    abort(S, ?abort_timed_out).

segmented_download(S) ->
    case co_transfer:size(S#co_session.th) of
	0 ->
	    co_transfer:read_end(S#co_session.th),
	    {stop, normal, S};
	Remain ->
	    case co_transfer:read(S#co_session.th, 7) of
		{error,Reason} ->
		    abort(S, Reason);
		{ok,TH1,Data} ->
		    Data1 = co_sdo:pad(Data, 7),
		    T = S#co_session.t,
		    N = 7 - size(Data),
		    C = ?UINT1(Remain =<  7),
		    R = ?mk_ccs_download_segment_request(T,N,C,Data1),
		    send(S, R),
		    S1 = S#co_session { th = TH1 },
		    {next_state, s_segmented_download, S1, ?TMO(S1)}
	    end
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% SEGMENTED UPLOAD 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

s_segmented_upload_response(M, S) when is_record(M, can_frame) ->
    io:format("s_segmented_upload_response: got message!\n"),
    case M#can_frame.data of
	?ma_scs_initiate_upload_response(N,Expedited,SizeInd,IX,SI,Data) when
	      IX =:= S#co_session.index,
	      SI =:= S#co_session.subind ->
	    if Expedited =:= 1 ->
		    io:format("s_segmented_upload_response: expedited transfer\n"),
		    NBytes = if SizeInd =:= 1 -> 4-N; true -> 4 end,
		    case co_transfer:write(S#co_session.th, Data, NBytes) of
			{error, Reason} ->
			    abort(S, Reason);
			{ok,TH1,_NWrBytes} ->
			    co_transfer:write_end(S#co_session.ctx, TH1),
			    {stop, normal, S}
		    end;
	       true ->
		    io:format("s_segmented_upload_response: segmented transfer\n"),
		    TH = 
			if SizeInd =:= 1 ->
				<<Size:32/?SDO_ENDIAN>> = Data,
				co_transfer:write_size(S#co_session.th, Size);
			   true ->
				co_transfer:write_size(S#co_session.th, 0)
			end,
		    T = S#co_session.t,
		    R = ?mk_ccs_upload_segment_request(T),
		    send(S, R),
		    S1 = S#co_session { th=TH },
		    {next_state, s_segmented_upload, S1, ?TMO(S1)}
	    end;
	_ ->
	    l_abort(M, S, s_segmented_upload_response)
    end;
s_segmented_upload_response(timeout, S) ->
    abort(S, ?abort_timed_out).

s_segmented_upload(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_upload_segment_response(T,_N,_C,_D) when T =/= S#co_session.t ->
	    abort(S, ?abort_toggle_not_alternated);
	?ma_scs_upload_segment_response(T,N,C,D) ->
	    NBytes = 7-N,
	    case co_transfer:write(S#co_session.th, D, NBytes) of
		{error, Reason} ->
		    abort(S, Reason);
		{ok,TH1,_NWrBytes} ->
		    if C =:= 1 ->
			    co_transfer:write_end(S#co_session.ctx, TH1),
			    {stop, normal, S};
		       true ->
			    T1 = 1-T,
			    R = ?mk_ccs_upload_segment_request(T1),
			    send(S, R),
			    S1 = S#co_session { t=T1, th=TH1 },
			    {next_state, s_segmented_upload, S1, ?TMO(S1)}
		    end
	    end;
	_ ->
	    l_abort(M, S, s_segmented_upload)
    end;
s_segmented_upload(timeout, S) ->
    abort(S, ?abort_timed_out).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% BLOCK DOWNLOAD
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

s_block_initiate_download_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_initiate_download_response(GenCrc,IX,SI,BlkSize) when
	      IX =:= S#co_session.index,
	      SI =:= S#co_session.subind ->
	    DoCrc = (S#co_session.ctx)#sdo_ctx.use_crc andalso (GenCrc =:= 1),
	    S1 = S#co_session { crc = DoCrc, blksize=BlkSize,
				blkcrc=co_crc:init(), blkbytes=0 },
	    send_block(S1,1);
	?ma_scs_block_initiate_download_response(_SC,_IX,_SI,_BlkSz) ->
	    abort(S, ?abort_command_specifier);
	_ ->
	    l_abort(M, S, s_block_initiate_download_response)
    end;
s_block_initiate_download_response(timeout, S) ->
    abort(S, ?abort_timed_out).
	    
send_block(S, Seq) when Seq =< S#co_session.blksize ->
    case co_transfer:read(S#co_session.th,7) of
	{error,Reason} ->
	    abort(S,Reason);
	{ok,TH,Data} ->
	    Remain = co_transfer:size(TH),
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
		    {next_state,s_block_download_response_last,S1,?TMO(S1)};
	       Seq =:= S#co_session.blksize ->
		    {next_state, s_block_download_response,S1,?TMO(S1)};
	       true ->
		    send_block(S1, Seq+1)
	    end
    end.

s_block_download_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_download_response(AckSeq,BlkSize) when 
	      AckSeq =:= S#co_session.blkseq ->
	    S1 = S#co_session { blkseq=0, blksize=BlkSize },
	    send_block(S1, 1);
	?ma_scs_block_download_response(_AckSeq,_BlkSize) ->
	    abort(S, ?abort_invalid_sequence_number);
	_ ->
	    l_abort(M, S, s_block_download_response)
    end;
s_block_download_response(timeout, S) ->
    abort(S, ?abort_timed_out).    
	

s_block_download_response_last(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_download_response(AckSeq,BlkSize) when 
	      AckSeq =:= S#co_session.blkseq ->
	    S1 = S#co_session { blkseq=0, blksize=BlkSize },
	    CRC = co_crc:final(S1#co_session.blkcrc),
	    N   = (7- (S1#co_session.blkbytes rem 7)) rem 7,	    
	    R = ?mk_ccs_block_download_end_request(N,CRC),
	    send(S1, R),
	    {next_state, s_block_download_end_response, S1, ?TMO(S1)};
	?ma_scs_block_download_response(_AckSeq,_BlkSz) ->
	    abort(S, ?abort_invalid_sequence_number);
	_ ->
	    l_abort(M, S, s_block_download_response_last)
    end;
s_block_download_response_last(timeout, S) ->
    abort(S, ?abort_timed_out).    


s_block_download_end_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_download_end_response() ->
	    co_transfer:read_end(S#co_session.th),
	    {stop, normal, S};
	_ ->
	    l_abort(M, S, s_block_download_end_response)
    end;
s_block_download_end_response(timeout, S) ->
    abort(S, ?abort_timed_out).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% BLOCK UPLOAD 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

s_block_upload_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_upload_response(CrcSup,SizeInd,IX,SI,Size) when
	      IX =:= S#co_session.index,
	      SI =:= S#co_session.subind ->
	    TH = if SizeInd =:= 1 ->
			 co_transfer:write_size(S#co_session.th, Size);
		    true ->
			 co_transfer:write_size(S#co_session.th, 0)
		 end,
	    R = ?mk_ccs_block_upload_start(),
	    send(S, R),
	    S1 = S#co_session { crc = CrcSup =:= 1,
				blkseq = 0, th=TH },
	    {next_state, s_block_upload, S1, ?TMO(S1)};
	?ma_scs_initiate_upload_response(_N,_E,_SizeInd,_IX,_SI,_Data) ->
	    %% protocol switched
	    s_segmented_upload_response(M, S);
	_ ->
	    %% check if this was a protcol switch...
	    s_segmented_upload_response(M, S)
    end;
s_block_upload_response(timeout, S) ->
    abort(S, ?abort_timed_out).

%% Here wew receice the block segments
s_block_upload(M, S) when is_record(M, can_frame) ->
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
				    R = ?mk_ccs_block_upload_response(Seq,BlkSize),
				    send(S2, R),
				    if Last =:= 1 ->
					    {next_state, s_block_upload_end,S2,
					     ?TMO(S2)};
				       true ->
					    {next_state, s_block_upload, S2,
					     ?TMO(S2)}
				    end
			    end;
		       true ->
			    {next_state, s_block_upload, S1, ?BLKTMO(S1)}
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
s_block_upload(timeout, S) ->
    abort(S, ?abort_timed_out).

s_block_upload_end(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_upload_end_request(N,CRC) ->
	    case co_transfer:write_block_end(S#co_session.ctx, 
					     S#co_session.th,N,CRC,
					     S#co_session.crc) of
		{error,Reason} ->
		    abort(S, Reason);
		_ -> %% this can be any thing ok | true ..
		    R = ?mk_ccs_block_upload_end_response(),
		    send(S, R),
		    {stop, normal, S}
	    end;
	_ ->
	    l_abort(M, S, s_block_upload_end)
    end;
s_block_upload_end(timeout, S) ->
    abort(S, ?abort_timed_out).
			    
%%--------------------------------------------------------------------
%% @private
%% @spec handle_event(Event, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_all_state_event/2, this function is called to handle
%% the event.
%%
%% @end
%%--------------------------------------------------------------------
handle_event(_Event, StateName, S) ->
    %% FIXME: handle abort here!!!
    {next_state, StateName, S, ?TMO(S)}.

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
handle_sync_event(_Event, _From, StateName, State) ->
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
handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

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
%% @spec code_change(OldVsn, StateName, State, Extra) ->
%%                   {ok, StateName, NewState}
%% @doc
%% Convert process state when code is changed
%%
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

l_abort(M, S, StateName) ->
    case M#can_frame.data of
	?ma_scs_abort_transfer(IX,SI,Code) when
	      IX =:= S#co_session.index,
	      SI =:= S#co_session.subind ->
	    Reason = co_sdo:decode_abort_code(Code),
	    %% remote party has aborted
	    gen_server:reply(S#co_session.node_from, {error,Reason}),
	    {stop, normal, S};
	?ma_scs_abort_transfer(_IX,_SI,_Code) ->
	    %% probably a delayed abort for an old session ignore
	    {next_state, StateName, S, ?TMO(S)};
	_ ->
	    %% we did not expect this command abort
	    abort(S, ?abort_command_specifier)
    end.
	    

abort(S, Reason) ->
    Code = co_sdo:encode_abort_code(Reason),
    R = ?mk_ccs_abort_transfer(S#co_session.index, S#co_session.subind, Code),
    send(S, R),
    gen_server:reply(S#co_session.node_from, {error,Reason}),
    {stop, normal, S}.
    
send(S, Data) when is_binary(Data) ->
    io:format("send: ~s\n", [co_format:format_sdo(co_sdo:decode_rx(Data))]),
    Dst = S#co_session.dst,
    ID = if ?is_cobid_extended(Dst) ->
		 (Dst band ?CAN_EFF_MASK) bor ?CAN_EFF_FLAG;
	    true ->
		 (Dst band ?CAN_SFF_MASK)
	 end,
    %% send message as it where sent from the node process
    %% this inhibits the message to be delivered to the node process
    can:send_from(S#co_session.node_pid,ID,8,Data).

new_session(Ctx,From,NodePid,Src,Dst,IX,SI,TH) ->
    #co_session {
	     src       = Src,
	     dst       = Dst,
	     index     = IX,
	     subind    = SI,
	     t         = 0,         %% Toggle value
	     crc       = false,
	     blksize   = 0,
	     blkseq    = 0,
	     blkbytes  = 0,
	     node_pid  = NodePid,
	     node_from = From,
	     ctx       = Ctx,
	     th        = TH
	    }.
