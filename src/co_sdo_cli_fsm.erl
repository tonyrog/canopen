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
-include("canopen.hrl").
-include("sdo.hrl").
-include("co_app.hrl").
-include("co_debug.hrl").

%% API
-export([store/8, fetch/8]).

%% gen_fsm callbacks
-export([init/1, handle_event/3,
	 handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% States
-export([s_segmented_download_response/2]).
-export([s_segmented_download/2]).
-export([s_segmented_download_end/2]).
-export([s_reading_segment_started/2]). %% Streamed
-export([s_reading_segment/2]).         %% Streamed

-export([s_segmented_upload_response/2]).
-export([s_segmented_upload/2]).
-export([s_writing_segment_started/2]). %% Streamed
-export([s_writing_segment/2]).         %% Streamed

-export([s_block_initiate_download_response/2]).
-export([s_block_download_response/2]).
-export([s_block_download_response_last/2]).
-export([s_block_download_end_response/2]).
-export([s_reading_block_started/2]).   %% Streamed

-export([s_block_upload_response/2]).
-export([s_block_upload/2]).
-export([s_block_upload_end/2]).
-export([s_writing_block_started/2]).   %% Streamed
-export([s_writing_block_end/2]).       %% Streamed

-export([store/3, fetch/3]).
 
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
store(Ctx,Block,From,Src,Dst,IX,SI,Term) when is_record(Ctx, sdo_ctx) ->
    ?dbg(cli, "store: block = ~p, From = ~p, Ix = ~p, Si = ~p, Term = ~p",
	 [Block, From, IX, SI, Term]),
    gen_fsm:start(?MODULE, 
		  [store,Block,Ctx,From,self(),Src,Dst,IX,SI,Term], []).

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
fetch(Ctx,Block,From,Src,Dst,IX,SI,Term) ->
    gen_fsm:start(?MODULE, 
		  [fetch,Block,Ctx,From,self(),Src,Dst,IX,SI,Term], []).

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
init([Action,Block,Ctx,From,NodePid,Src,Dst,IX,SI,Term]) ->
    put(dbg, true), %% Make debug possbible
    ?dbg(cli,"init: ~p ~p src=~.16#, dst=~.16#", [Action, Block, Src, Dst]),
    ?dbg(cli,"init: From = ~p, Index = ~4.16.0B:~p, Term = ~p",
    	 [From, IX, SI, Term]),
    S = new_session(Ctx,From,NodePid,Src,Dst,IX,SI),
    apply(?MODULE, Action, [S, Block, Term]).

store(S=#co_session {ctx = Ctx, index = IX, subind = SI}, Block, {Pid, Module}) 
  when is_pid(Pid), is_atom(Module) ->
    case read_begin(Ctx, IX, SI, Pid, Module) of
	{ok, Buf} ->
	    case Block of
		true ->
		    start_block_download(S#co_session {buf = Buf}, ok);
		false ->
		    start_segmented_download(S#co_session {buf = Buf}, ok)
	    end;
	{ok, Buf, Mref} when is_reference(Mref) ->
	    %% Application called, wait for reply
	    S1 = S#co_session {mref = Mref, buf = Buf},
	    case Block of 
		true ->
		    {ok, s_reading_block_started, S1, ?TMO(S1)};
		false ->
		    {ok, s_reading_segment_started, S1, ?TMO(S1)}
	    end;
	{error,Reason} ->
	    co_session:abort(S, Reason)
    end;
store(S=#co_session {ctx = Ctx, index = IX, subind = SI}, Block, Data) 
  when is_binary(Data) ->
    case co_data_buf:init(read, self(), {Data, {IX, SI}}, Ctx#sdo_ctx.read_buf_size, 
			  trunc(Ctx#sdo_ctx.read_buf_size * 
				    Ctx#sdo_ctx.load_ratio)) of 
	{ok, Buf} ->
	    case Block of 
		true ->
		    start_block_download(S#co_session {buf = Buf}, ok);
		false ->
		    start_segmented_download(S#co_session {buf = Buf}, ok)
		end;
	{error, Reason} ->
	    co_session:abort(S, Reason)
    end.

fetch(S=#co_session {index = IX, subind = SI}, Block, {Pid, Module}) 
  when is_pid(Pid), is_atom(Module) ->
    case write_begin(IX, SI, Pid, Module) of
	{ok, Buf}  -> 
	    case Block of
		true ->
		    start_block_upload(S#co_session {buf = Buf}, ok);
		false ->
		    start_segmented_upload(S#co_session {buf = Buf}, ok)
		end;
	{ok, Buf, Mref} ->
	    %% Application called, wait for reply
	    S1 = S#co_session { buf=Buf, mref=Mref },
	    case Block of 
		true ->
		    {ok, s_writing_block_started,S1,?TMO(S1)};
		false ->
		    {ok, s_writing_segment_started,S1,?TMO(S1)}
	    end;
	{error,Reason} ->
	    co_session:abort(S, Reason)
    end;
fetch(S=#co_session {index = IX, subind = SI}, Block, data) ->
    case co_data_buf:init(write, self(), {(<<>>), {IX, SI}}, undefined, undefined) of
	{ok, Buf} ->
	    case Block of 
		true ->
		    start_block_upload(S#co_session {buf = Buf}, ok);
		false ->
		    start_segmented_upload(S#co_session {buf = Buf}, ok)
		end;
	{error, Reason} ->
	    co_session:abort(S, Reason)
    end.
	
read_begin(Ctx, Index, SubInd, Pid, Mod) ->
    case Mod:get_entry(Pid, {Index, SubInd}) of
	{entry, Entry} ->
	    if (Entry#app_entry.access band ?ACCESS_RO) =:= ?ACCESS_RO ->
		    ?dbg(cli, "app_read_begin: Read access ok\n", []),
		    ?dbg(cli, "app_read_begin: Transfer mode = ~p\n", 
			 [Entry#app_entry.transfer]),
		    co_data_buf:init(read, Pid, Entry, 
				     Ctx#sdo_ctx.read_buf_size, 
				     trunc(Ctx#sdo_ctx.read_buf_size * 
					       Ctx#sdo_ctx.load_ratio));
	       true ->
		    {entry, ?abort_read_not_allowed}
	    end;
	Error ->
	    Error
    end.

write_begin(Index, SubInd, Pid, Mod) ->
    case Mod:get_entry(Pid, {Index, SubInd}) of
	{entry, Entry} ->
	    if (Entry#app_entry.access band ?ACCESS_WO) =:= ?ACCESS_WO ->
		    ?dbg(cli, "app_write_begin: transfer=~p, type = ~p\n",
			 [Entry#app_entry.transfer, Entry#app_entry.type]),
		    co_data_buf:init(write, Pid, Entry, undefined, undefined);
	       true ->
		    {entry, ?abort_unsupported_access}
	    end;
	{error, Reason}  ->
	    {error, Reason}
    end.
    


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

start_segmented_download(S=#co_session {buf = Buf, index = IX, subind = SI}, Reply) ->
    NBytes = co_data_buf:data_size(Buf),
    EofFlag = co_data_buf:eof(Buf),
    ?dbg(cli, "start_segmented_download: nbytes = ~p, eof = ~p",[NBytes, EofFlag]),
    if NBytes =/= 0, NBytes =< 4 andalso EofFlag =:= true ->
	    case co_data_buf:read(Buf, NBytes) of
		{ok, Data, true, Buf1} ->
		    ?dbg(cli, "start_segmented_download, expediated.\n", []),
		    N = 4-size(Data),
		    Data1 = co_sdo:pad(Data,4),
		    Expedited = 1,
		    SizeInd   = 1,
		    R=?mk_ccs_initiate_download_request(N,Expedited,SizeInd,
							IX,SI,Data1),
		    send(S, R),
		    {Reply, s_segmented_download_response, S#co_session {buf = Buf1}, ?TMO(S)};
		{error, Reason} ->
		    co_session:abort(init, Reason)
	    end;
       true ->
	    %% FIXME: add streaming protocol Size=0
	    N = 0,
	    Data1 = <<NBytes:32/?SDO_ENDIAN>>,
	    Expedited = 0,
	    SizeInd = 1,
	    R=?mk_ccs_initiate_download_request(N,Expedited,SizeInd,
						IX,SI,Data1),
	    send(S, R),
	    {Reply, s_segmented_download_response, S, ?TMO(S)}
    end.

s_segmented_download_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_initiate_download_response(IX,SI) when 
	      IX =:= S#co_session.index,
	      SI =:= S#co_session.subind ->
	    read_segment(S);
	_ ->
	    co_session:l_abort(M, S, s_segmented_download_response)
    end;
s_segmented_download_response(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

	    
s_segmented_download(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_download_segment_response(T) when T =/= S#co_session.t ->
	    co_session:abort(S, ?abort_toggle_not_alternated);
	?ma_scs_download_segment_response(T) ->
	    read_segment(S#co_session {t=1-T} );
	_ ->
	    co_session:l_abort(M, S, s_segmented_download)
    end;
s_segmented_download(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

read_segment(S) ->
    case co_data_buf:read(S#co_session.buf,7) of
	{ok, Data, Eod, Buf} ->
	    ?dbg(cli, "read_segment: data=~p, Eod=~p\n", 
		 [Data, Eod]),
	    send_segment(S#co_session {buf = Buf}, Data, Eod);
	{ok, Buf, Mref} ->
	    %% Called an application
	    ?dbg(cli, "read_segment: mref=~p\n", 
		 [Mref]),
	    S1 = S#co_session {mref = Mref, buf = Buf},
	    {next_state, s_reading_segment, S1, ?TMO(S1)};
	{error,Reason} ->
	    co_session:abort(S,Reason)
    end.

send_segment(S, Data, Eod) ->
    Data1 = co_sdo:pad(Data, 7),
    T = S#co_session.t,
    N = 7 - size(Data),
    Last = ?UINT1(Eod),
    R = ?mk_ccs_download_segment_request(T,N,Last,Data1),
    send(S, R),
    if Eod =:= true ->
	    {next_state, s_segmented_download_end, S, ?TMO(S)};
       true ->
	    {next_state, s_segmented_download, S, ?TMO(S)}
    end.

s_segmented_download_end(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_download_segment_response(T) when T =/= S#co_session.t ->
	    co_session:abort(S, ?abort_toggle_not_alternated);
	?ma_scs_download_segment_response(_T) ->
	    gen_server:reply(S#co_session.node_from, ok),
	    {stop,normal,S};
	_ ->
	    co_session:l_abort(M, S, s_segmented_download)
    end;
s_segmented_download_end(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

%%
%% state: reading_segment_started (for application stored data)
%%    next_state:  segmented_download
%%
s_reading_segment_started({Mref, Reply} = M, S)  ->
    ?dbg(cli, "s_reading_segment_started: Got event = ~p\n", [M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, _Value}} ->
	    %% Atomic
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    start_segmented_download(S#co_session {buf = Buf}, next_state);	    
	{Mref, {ok, _Ref, _Size}} ->
	    %% Streamed
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    %% Start to fill data buffer
	    case co_data_buf:load(Buf) of
		{ok, Buf1} ->
		    %% Buffer loaded
		    start_segmented_download(S#co_session {buf = Buf1}, next_state);
		{ok, Buf1, Mref1} ->
		    %% Wait for data ??
		    start_segmented_download(S#co_session {buf = Buf1, mref = Mref1},next_state);
		{error, _Error} ->
		    co_session:l_abort(M, S, s_reading_segment_started)
	    end;
	_Other ->
	    co_session:l_abort(M, S, s_reading_segment_started)
    end;
s_reading_segment_started(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_reading_segment_started(M, S)  ->
    ?dbg(cli, "s_reading_segment_started: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).

s_reading_segment(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_reading_segment(M, S)  ->
    %% All correct messages should be handled in handle_info()
    ?dbg(cli, "s_reading_segment: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% SEGMENTED UPLOAD 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_segmented_upload(S=#co_session {index = IX, subind = SI}, Reply) ->
    ?dbg(cli, "start_segmented_upload: ~4.16.0B:~p", [IX, SI]),
    R = ?mk_ccs_initiate_upload_request(IX,SI),
    send(S, R),
    {Reply, s_segmented_upload_response, S, ?TMO(S)}.

s_segmented_upload_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_initiate_upload_response(N,Expedited,SizeInd,IX,SI,Data) when
	      IX =:= S#co_session.index,
	      SI =:= S#co_session.subind ->
	    ?dbg(cli, "s_segmented_upload_response", []),

	    if Expedited =:= 1 ->
		    NBytes = if SizeInd =:= 1 -> 4 - N;
				true -> 0
			     end,
		    <<Data1:NBytes/binary, _Filler/binary>> = Data,
		    ?dbg(cli, "s_segmented_upload_response: expedited, Data = ~p\n", 
			 [Data1]),
		    NBytes = if SizeInd =:= 1 -> 4-N; true -> 4 end,
		    case co_data_buf:write(S#co_session.buf, Data, true, segment) of
			{ok, _Buf1} ->
			    gen_server:reply(S#co_session.node_from, {ok, Data}),
			    {stop, normal, S};
			{ok, Buf1, Mref} when is_reference(Mref) ->
			    %% Called an application
			    S1 = S#co_session {mref = Mref, buf = Buf1},
			    {next_state, s_writing_segment, S1, ?TMO(S1)};
			{error, Reason} ->
			    co_session:abort(S, Reason)
		    end;
	       true ->
		    ?dbg(cli, "s_segmented_upload_response: Size = ~p\n", [N]),
		    case co_data_buf:update(S#co_session.buf, {ok, N}) of
			{ok, Buf1} ->
			    T = S#co_session.t,
			    R = ?mk_ccs_upload_segment_request(T),
			    send(S, R),
			    S1 = S#co_session { buf=Buf1 },
			    {next_state, s_segmented_upload, S1, ?TMO(S1)};
			{error, Reason} ->
			    co_session:abort(S, Reason)
		    end
	    end;
	_ ->
	    co_session:l_abort(M, S, s_segmented_upload_response)
    end;
s_segmented_upload_response(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

s_segmented_upload(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_upload_segment_response(T,_N,_C,_D) when T =/= S#co_session.t ->
	    co_session:abort(S, ?abort_toggle_not_alternated);
	?ma_scs_upload_segment_response(T,N,C,Data) ->
	    ?dbg(cli, "s_segmented_upload: Data = ~p\n", [Data]),	    
	    NBytes = 7-N,
	    Eod = (C =:= 1),
	    <<DataToWrite:NBytes/binary, _Filler/binary>> = Data,
	    case co_data_buf:write(S#co_session.buf, DataToWrite, Eod, segment) of
		{ok, Buf1} ->
		    if Eod ->
			    gen_server:reply(S#co_session.node_from, ok),
			    {stop, normal, S};
		       true ->
			    T1 = 1-T,
			    S1 = S#co_session { t=T1, buf=Buf1 },
			    R = ?mk_ccs_upload_segment_request(T1),
			    send(S1, R),
			    {next_state, s_segmented_upload, S1, ?TMO(S1)}
		    end;
		{ok, Buf1, Mref} when is_reference(Mref) ->
		    %% Called an application
		    S1 = S#co_session {mref = Mref, buf = Buf1},
		    {next_state, s_writing_segment, S1, ?TMO(S1)};
		{error, Reason} ->
		    co_session:abort(S, Reason)
	    end;
	_ ->
	    co_session:l_abort(M, S, s_segmented_upload)
    end;
s_segmented_upload(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

%%
%% state: writing_segment_started (for application stored data)
%%    next_state:  s_segmented_upload_response
%%
s_writing_segment_started({Mref, Reply} = M, S)  ->
    ?dbg(cli, "s_writing_segment_started: Got event = ~p\n", [M]),
    case S#co_session.mref of
	Mref ->
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    start_segmented_upload(S#co_session {buf = Buf}, next_state);
	_Other ->
	    co_session:l_abort(M, S, s_writing_segment_started)
    end;
s_writing_segment_started(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_writing_segment_started(M, S)  ->
    ?dbg(cli, "s_writing_segment_started: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).


%%
%% state: s_writing_segment (for application stored data)
%%    next_state:  No state
%%
s_writing_segment({Mref, Reply} = M, S)  ->
    ?dbg(cli, "s_writing_segment: Got event = ~p\n", [M]),
    case {S#co_session.mref, Reply} of
	{Mref, ok} ->
	    %% Atomic reply
	    erlang:demonitor(Mref, [flush]),
	    gen_server:reply(S#co_session.node_from, ok),
	    {stop, normal, S};
	{Mref, {ok, Ref}} when is_reference(Ref)->
	    %% Streamed reply
	    erlang:demonitor(Mref, [flush]),
	    gen_server:reply(S#co_session.node_from, ok),
	    {stop, normal, S};
	_Other ->
	    co_session:l_abort(M, S, s_writing)
    end;
s_writing_segment(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_writing_segment(M, S)  ->
    ?dbg(cli, "s_writing_segment: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% BLOCK DOWNLOAD
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_block_download(S=#co_session {buf = Buf, ctx = Ctx, index = IX, subind = SI}, Reply) ->
    NBytes = co_data_buf:data_size(Buf),
    UseCrc = ?UINT1(Ctx#sdo_ctx.use_crc),
    SizeInd = 1, %% ???
    R = ?mk_ccs_block_download_request(UseCrc,SizeInd,IX,SI,NBytes),
    send(S, R),
    {Reply, s_block_initiate_download_response, S, ?TMO(S)}.
    

s_block_initiate_download_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_initiate_download_response(GenCrc,IX,SI,BlkSize) when
	      IX =:= S#co_session.index,
	      SI =:= S#co_session.subind ->
	    DoCrc = (S#co_session.ctx)#sdo_ctx.use_crc andalso (GenCrc =:= 1),
	    S1 = S#co_session { crc = DoCrc, blksize=BlkSize,
				blkcrc=co_crc:init(), blkbytes=0 },
	    read_block_segment(S1#co_session {blkseq = 1});
	?ma_scs_block_initiate_download_response(_SC,_IX,_SI,_BlkSz) ->
	    co_session:abort(S, ?abort_command_specifier);
	_ ->
	    co_session:l_abort(M, S, s_block_initiate_download_response)
    end;
s_block_initiate_download_response(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).
	    
read_block_segment(S) ->
    ?dbg(srv, "read_block_segment: Seq=~p\n", [S#co_session.blkseq]),
    case co_data_buf:read(S#co_session.buf,7) of
	{ok, Data, Eod, Buf} ->
	    send_block_segment(S#co_session {buf = Buf}, Data, Eod);
	{ok, Buf, Mref} ->
	    %% Called an application
	    ?dbg(srv, "read_block_segment: mref=~p\n", [Mref]),
	    S1 = S#co_session {mref = Mref, buf = Buf},
	    {next_state, s_reading_block_segment, S1, ?TMO(S1)};
	{error,Reason} ->
	    co_session:abort(S,Reason)
    end.

send_block_segment(S, Data, Eod) ->
    ?dbg(srv, "send_block_segment: Data = ~p, Eod = ~p\n", [Data, Eod]),
    Seq = S#co_session.blkseq,
    Last = ?UINT1(Eod),
    Data1 = co_sdo:pad(Data, 7),
    R = ?mk_block_segment(Last,Seq,Data1),
    NBytes = S#co_session.blkbytes + byte_size(Data),
    ?dbg(srv, "send_block_segment: data1 = ~p, nbytes = ~p\n",
	 [Data1, NBytes]),
    Crc = if S#co_session.crc ->
		  co_crc:update(S#co_session.blkcrc, Data);
	     true ->
		  S#co_session.blkcrc
	  end,
    S1 = S#co_session { blkseq=Seq, blkbytes=NBytes, blkcrc=Crc},
    send(S1, R),
    if Eod ->
	    ?dbg(srv, "upload_block_segment: Last = ~p\n", [Last]),
	    {next_state, s_block_download_response_last, S1, ?TMO(S1)};
       Seq =:= S#co_session.blksize ->
	    ?dbg(srv, "upload_block_segment: Seq = ~p\n", [Seq]),
	    {next_state, s_block_download_response, S1, ?TMO(S1)};
       true ->
	    read_block_segment(S1#co_session {blkseq = Seq + 1})
    end.

s_block_download_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_download_response(AckSeq,BlkSize) when 
	      AckSeq =:= S#co_session.blkseq ->
	    read_block_segment(S#co_session { blkseq=0, blksize=BlkSize });
	?ma_scs_block_download_response(_AckSeq,_BlkSize) ->
	    co_session:abort(S, ?abort_invalid_sequence_number);
	_ ->
	    co_session:l_abort(M, S, s_block_download_response)
    end;
s_block_download_response(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).    
	

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
	    co_session:abort(S, ?abort_invalid_sequence_number);
	_ ->
	    co_session:l_abort(M, S, s_block_download_response_last)
    end;
s_block_download_response_last(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).    


s_block_download_end_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_download_end_response() ->
	    gen_server:reply(S#co_session.node_from, ok),
	    {stop, normal, S};
	_ ->
	    co_session:l_abort(M, S, s_block_download_end_response)
    end;
s_block_download_end_response(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

%%
%% state: reading_block_started (for application stored data)
%%    next_state:  blocked_upload
%%
s_reading_block_started({Mref, Reply} = M, S)  ->
    ?dbg(cli, "s_reading_block_started: Got event = ~p\n", [M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, _Value}} ->
	    %% Atomic
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    start_block_download(S#co_session {buf = Buf}, next_state);
	{Mref, {ok, _Ref, _Size}} ->
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    case co_data_buf:load(Buf) of
		{ok, Buf1} ->
		    %% Buffer loaded
		    start_block_download(S#co_session {buf = Buf1}, next_state);
		{ok, Buf1, Mref1} ->
		    start_block_download(S#co_session {buf = Buf1, mref = Mref1}, next_state)
	    end;
	_Other ->
	    co_session:l_abort(M, S, s_reading_block_started)
    end;
s_reading_block_started(M, S)  ->
    ?dbg(cli, "s_reading_block_started: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% BLOCK UPLOAD 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_block_upload(S=#co_session {buf = Buf, ctx = Ctx, index = IX, subind = SI}, Reply) ->
    CrcSup = ?UINT1(Ctx#sdo_ctx.use_crc),
    BlkSize = Ctx#sdo_ctx.max_blksize,  %% max number of segments/block
    Pst     = Ctx#sdo_ctx.pst,          %% protcol switch limit 
    R = ?mk_ccs_block_upload_request(CrcSup,IX,SI,BlkSize,Pst),
    send(S, R),
    S1 = S#co_session { blksize = BlkSize, pst = Pst },
    {Reply, s_block_upload_response, S1#co_session {buf = Buf}, ?TMO(S)}.

s_block_upload_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_upload_response(CrcSup,SizeInd,IX,SI,Size) when
	      IX =:= S#co_session.index,
	      SI =:= S#co_session.subind ->
	    R = ?mk_ccs_block_upload_start(),
	    send(S, R),
	    %% Size ??
	    S1 = S#co_session { crc = CrcSup =:= 1, blkseq = 0 },
	    {next_state, s_block_upload, S1, ?TMO(S1)};
	?ma_scs_initiate_upload_response(_N,_E,_SizeInd,_IX,_SI,_Data) ->
	    %% protocol switched
	    s_segmented_upload_response(M, S);
	_ ->
	    %% check if this was a protcol switch...
	    s_segmented_upload_response(M, S)
    end;
s_block_upload_response(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

%% Here we receice the block segments
s_block_upload(M, S) when is_record(M, can_frame) ->
    NextSeq = S#co_session.blkseq+1,
    case M#can_frame.data of
	?ma_block_segment(Last,Seq,Data) when Seq =:= NextSeq ->
	    ?dbg(cli, "s_block_upload: Data = ~p\n", [Data]),	    
	    case co_data_buf:write(S#co_session.buf, Data, false, block) of
		{ok, Buf} ->
		    block_segment_written(S#co_session {buf = Buf, last = Last});
		{ok, Buf, Mref} when is_reference(Mref) ->
		    block_segment_written(S#co_session {buf = Buf, last = Last, mref = Mref});		    %% Called an application
		{error, Reason} ->
		    co_session:abort(S, Reason)
	    end;
	?ma_block_segment(_Last,Seq,_Data) when Seq =:= 0; Seq > S#co_session.blksize ->
	    co_session:abort(S, ?abort_invalid_sequence_number);
	?ma_block_segment(_Last,_Seq,_Data) ->
	    %% here we could takecare of out of order data
	    co_session:abort(S, ?abort_invalid_sequence_number);
	%% Handle abort and spurious packets ...
	%% We can not use co_session:l_abort here because we do not know if message
	%% is an abort or not.
	_ ->
	    co_session:abort(S, ?abort_command_specifier)
    end;
s_block_upload(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).


block_segment_written(S=#co_session {last = Last}) ->
    NextSeq = S#co_session.blkseq + 1,
    if Last =:= 1; NextSeq =:= S#co_session.blksize ->
	    BlkSize = co_session:next_blksize(S),
	    S1 = S#co_session {blkseq=0, blksize=BlkSize},
	    R = ?mk_scs_block_download_response(NextSeq,BlkSize),
	    send(S1, R),
	    if Last =:= 1 ->
		    {next_state, s_block_upload_end, S1,?TMO(S1)};
	       true ->
		    {next_state, s_block_upload, S1, ?TMO(S1)}
	    end;
       true ->
	    S1 = S#co_session {blkseq=NextSeq},
	    {next_state, s_block_upload, S1, ?BLKTMO(S1)}
    end.


s_block_upload_end(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_upload_end_request(N,CRC) ->
	    %% CRC ??
	    case co_data_buf:write(S#co_session.buf,N,true,block) of	    
		{error,Reason} ->
		    co_session:abort(S, Reason);
		{ok, Buf, Mref} ->
		    %% Called an application
		    S1 = S#co_session {mref = Mref, buf = Buf},
		    {next_state, s_writing_block_end, S1, ?TMO(S1)};
		    
		_ -> %% this can be any thing ok | true ..
		    R = ?mk_scs_block_download_end_response(),
		    send(S, R),
		    {stop, normal, S}
	    end;
	_ ->
	    co_session:l_abort(M, S, s_block_upload_end)
    end;
s_block_upload_end(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).
		
%%
%% state: writing_block_started (for application stored data)
%%    next_state:  s_block_download
%%
s_writing_block_started({Mref, Reply} = M, S)  ->
    ?dbg(cli, "s_writing_block_started: Got event = ~p\n", [M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, _Ref, _WriteSze}} ->
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    start_block_upload(S#co_session {buf = Buf}, next_state);
	_Other ->
	    co_session:l_abort(M, S, s_writing_block_started)
    end;
s_writing_block_started(M, S)  ->
    ?dbg(cli, "s_writing_block_started: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).


s_writing_block_end(M, S)  ->
    %% All correct messages should be taken care of in handle_info()
    ?dbg(cli, "s_writing_block: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).

	    
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
%% @doc
%% This function is called by a gen_fsm when it receives any
%% message other than a synchronous or asynchronous event
%% (or a system message).
%%
%% NOTE!!! This actually where all the replies from the application
%% are received. They are then normally sent on to the appropriate
%% state-function.
%% The exception is the reply to the read-call sent from co_data_buf as
%% this can arrive in any state and should just fill the buffer.
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info::term(), StateName::atom(), S::#co_session{}) ->
			 {next_state, NextState::atom(), NextS::#co_session{}} |
			 {next_state, NextState::atom(), NextS::#co_session{}, Tout::timeout()} |
			 {stop, Reason::atom(), NewS::#co_session{}}.
			 
handle_info({Mref, {ok, _Ref, _Data, _Eod} = Reply}, StateName, S) ->
    %% Streamed data read from application
    ?dbg(cli, "handle_info: Reply = ~p, State = ~p\n",[Reply, StateName]),
    case S#co_session.mref of
	Mref ->
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    %% Fill data buffer if needed
	    case co_data_buf:load(Buf) of
		{ok, Buf1} ->
		    %% Buffer loaded
		    check_reading(StateName, S#co_session {buf = Buf1});
		{ok, Buf1, Mref1} ->
		    %% Wait for data ??
		    check_reading(StateName, S#co_session {buf = Buf1, 
							   mref = Mref1});
		{error, Error} ->
		    co_session:abort(S, Error)
	    end;
	_OtherRef ->
	    %% Ignore reply
	    ?dbg(cli, "handle_info: wrong mref, ignoring\n",[]),
	    {next_state, StateName, S}
    end;
handle_info({_Mref, ok} = Info, StateName, S) 
  when StateName =:= s_writing_segment ->
    %% "Converting" info to event
    apply(?MODULE, StateName, [Info, S]);
handle_info({_Mref, ok} = Info, StateName, S) ->
    check_writing_block_end(Info, StateName, S);
handle_info({_Mref, {ok, Ref}} = Info, StateName, S) 
  when  is_reference(Ref) andalso
	 StateName =:= s_writing_segment ->
    %% "Converting" info to event
    apply(?MODULE, StateName, [Info, S]);
handle_info({_Mref, {ok, Ref}} = Info, StateName, S) when is_reference(Ref) ->
    check_writing_block_end(Info, StateName, S);
handle_info(Info, StateName, S) ->
    ?dbg(cli, "handle_info: Got info ~p\n",[Info]),
    %% "Converting" info to event
    apply(?MODULE, StateName, [Info, S]).


check_reading(s_reading_segment, S) ->
    read_segment(S);
check_reading(s_reading_block_segment, S) ->
    read_block_segment(S);
check_reading(State, S) -> 
    {next_state, State, S}.
	    

check_writing_block_end({Mref, Reply}, StateName, S) ->
    %% Streamed data write acknowledged
    ?dbg(cli, "check_writing_block_end: State = ~p\n",[StateName]),
    case S#co_session.mref of
	Mref ->
	    erlang:demonitor(Mref, [flush]),
	    case StateName of
		s_writing_block_end ->
		    ?dbg(cli, "handle_info: last reply, terminating\n",[]),
		    R = ?mk_scs_block_download_end_response(),
		    send(S, R),
		    {stop, normal, S};
		State ->
		    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
		    {next_state, State, S#co_session {buf = Buf}}
	    end;
	_OtherRef ->
	    %% Ignore reply
	    ?dbg(cli, "handle_info: wrong mref, ignoring\n",[]),
	    {next_state, StateName, S}
    end.

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

new_session(Ctx,From,NodePid,Src,Dst,IX,SI) ->
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
	     ctx       = Ctx
	    }.

send(S, Data) when is_binary(Data) ->
    ?dbg(cli, "send: ~s\n", [co_format:format_sdo(co_sdo:decode_rx(Data))]),
    co_session:send(S, Data).

