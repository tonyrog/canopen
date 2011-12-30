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
-include("co_app.hrl").
-include("co_debug.hrl").

%% API
-export([start/3]).

%% gen_fsm callbacks
-export([init/1, handle_event/3,
	 handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% Segment download
-export([s_initial/2]).
-export([s_segmented_download/2]).
-export([s_writing_segment_started/2]). %% Streamed
-export([s_writing_segment/2]).         %% Streamed

%% Segment upload
-export([s_segmented_upload/2]).
-export([s_reading_segment_started/2]). %% Streamed
-export([s_reading_segment/2]).         %% Streamed

%% Block upload
-export([s_block_upload_start/2]).
-export([s_block_upload_response/2]).
-export([s_block_upload_response_last/2]).
-export([s_block_upload_end_response/2]).
-export([s_reading_block_started/2]).   %% Streamed
-export([s_reading_block_segment/2]).   %% Streamed

%% Block download
-export([s_block_download/2]).
-export([s_block_download_end/2]).
-export([s_writing_block_started/2]).   %% Streamed
-export([s_writing_block_end/2]).       %% Streamed

		 
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
    put(dbg, true), %% Make debug possbible
    ?dbg(srv,"init: src=~p, dst=~p \n", [Src, Dst]),
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

%%--------------------------------------------------------------------
%% @doc
%% Initial state.<br/>
%% Expected events are:
%% <ul>
%% <li>initiate_download_request</li>
%% <li>block_download_request</li>
%% <li>initiate_upload_request</li>
%% <li>block_upload_request</li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_initial(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, Tout::integer()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_initial(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_initiate_download_request(N,Expedited,SizeInd,IX,SI,Data) ->
	    S1 = S#co_session{index=IX, subind=SI, exp=Expedited, 
			      data=Data, size_ind=SizeInd, n=N},
	    case write_begin(S1) of
		{ok, Buf}  ->
		    %% FIXME: check if max_size already set, reject if bad
		    start_segment_download(S1#co_session {buf = Buf});
		{ok, Buf, Mref} when is_reference(Mref) ->
		    %% Application called, wait for reply
		    S2 = S1#co_session { buf=Buf, mref=Mref },
		    {next_state, s_writing_segment_started,S2,?TMO(S2)};
		{error,Reason} ->
		    co_session:abort(S1, Reason)
	    end;

	?ma_ccs_block_download_request(ChkCrc,SizeInd,IX,SI,Size) ->
	    S1 = S#co_session { index=IX, subind=SI, 
				size_ind=SizeInd, crc=ChkCrc, size=Size},
	    case write_begin(S1) of
		{ok, Buf}  -> 
		    %% FIXME: check if max_size already set, reject if bad
		    start_block_download(S1#co_session {buf = Buf});
		{ok, Buf, Mref} ->
		    %% Application called, wait for reply
		    S2 = S1#co_session { buf=Buf, mref=Mref },
		    {next_state, s_writing_block_started,S2,?TMO(S2)};
		{error,Reason} ->
		    co_session:abort(S1, Reason)
	    end;

	?ma_ccs_initiate_upload_request(IX,SI) ->
	    S1 = S#co_session {index=IX,subind=SI},
	    case read_begin(S1) of
		{ok, Buf} ->
		    start_segmented_upload(S1#co_session {buf = Buf});
		{ok, Buf, Mref} when is_reference(Mref) ->
		    %% Application called, wait for reply
		    S2 = S1#co_session {mref = Mref, buf = Buf},
		    {next_state, s_reading_segment_started, S2, ?TMO(S2)};
		{error,Reason} ->
		    co_session:abort(S1, Reason)
	    end;

	?ma_ccs_block_upload_request(GenCrc,IX,SI,BlkSize,Pst) ->
	    ?dbg(srv, "s_initial: block_upload_request blksize = ~p\n",
		 [BlkSize]),
	    S1 = S#co_session {index=IX, subind=SI, pst=Pst, blksize=BlkSize, clientcrc=GenCrc},
	    case read_begin(S1) of
		{ok, Buf} ->
		    NBytes = co_data_buf:data_size(Buf),
		    if Pst =/= 0, NBytes > 0, NBytes =< Pst ->
			    ?dbg(srv, "protocol switch\n",[]),
			    start_segmented_upload(S1#co_session {buf = Buf});
		       true ->
			    start_block_upload(S1#co_session {buf = Buf})
		       end;
		{ok, Buf, Mref} when is_reference(Mref) ->
		    %% Application called, wait for reply
		    S2 = S1#co_session {mref = Mref, buf = Buf},
		    {next_state, s_reading_block_started, S2, ?TMO(S2)};
		{error,Reason} ->
		    ?dbg(srv,"start block upload error=~p\n", [Reason]),
		    co_session:abort(S1, Reason)
	    end;
	_ ->
	    co_session:l_abort(M, S, s_initial)
    end;
s_initial(timeout, S) ->
    {stop, timeout, S}.

%%--------------------------------------------------------------------
%% @doc Start a write operation
%% @end
%%--------------------------------------------------------------------
-spec write_begin(S::#co_session{}) ->
			{ok, Mref::reference(), Buf::term()} | 
			{ok, Buf::term()} |
			{error, Error::atom()}.

write_begin(S) ->
    Ctx= S#co_session.ctx,
    Index = S#co_session.index,
    SubInd = S#co_session.subind,
    case co_node:reserver_with_module(Ctx#sdo_ctx.res_table, Index) of
	[] ->
	    ?dbg(srv, "write_begin: No reserver for index ~7.16.0#\n", [Index]),
	    central_write_begin(Ctx, Index, SubInd);
	{Pid, Mod} when is_pid(Pid) ->
	    ?dbg(srv, "write_begin: Process ~p has reserved index ~7.16.0#\n", 
		 [Pid, Index]),
	    app_write_begin(Index, SubInd, Pid, Mod);
	{dead, _Mod} ->
	    ?dbg(srv, "write_begin: Reserver process for index ~7.16.0# dead.\n", [Index]),
	    {error, ?abort_internal_error}; %% ???
	_Other ->
	    ?dbg(srv, "write_begin: Other case = ~p\n", [_Other]),
	    {error, ?abort_internal_error}
    end.


central_write_begin(Ctx, Index, SubInd) ->
    Dict = Ctx#sdo_ctx.dict,
    case co_dict:lookup_entry(Dict, {Index,SubInd}) of
	{ok,E} ->
	    if (E#dict_entry.access band ?ACCESS_WO) =:= ?ACCESS_WO ->
		    ?dbg(srv, "central_write_begin: Write access ok\n", []),
		    co_data_buf:init(write, Dict, E, undefined, undefined);
	       true ->
		    {error,?abort_write_not_allowed}
	    end;
	{error, Reason}  ->
	    {error, Reason}
    end.

app_write_begin(Index, SubInd, Pid, Mod) ->
    case Mod:get_entry(Pid, {Index, SubInd}) of
	{entry, Entry} ->
	    if (Entry#app_entry.access band ?ACCESS_WO) =:= ?ACCESS_WO ->
		    ?dbg(srv, "app_write_begin: transfer=~p, type = ~p\n",
			 [Entry#app_entry.transfer, Entry#app_entry.type]),
		    co_data_buf:init(write, Pid, Entry, undefined, undefined);
	       true ->
		    {entry, ?abort_unsupported_access}
	    end;
	{error, Reason}  ->
	    {error, Reason}
    end.
    

%%--------------------------------------------------------------------
%% @doc Start a read operation
%% @end
%%--------------------------------------------------------------------
-spec read_begin(S::#co_session{}) ->
			{ok, Mref::reference(), Buf::term()} | 
			{ok, Buf::term()} |
			{error, Error::atom()}.

read_begin(S) ->
    Ctx= S#co_session.ctx,
    Index = S#co_session.index,
    SubInd = S#co_session.subind,
    case co_node:reserver_with_module(Ctx#sdo_ctx.res_table, Index) of
	[] ->
	    ?dbg(srv, "read_begin: No reserver for index ~7.16.0#\n", [Index]),
	    central_read_begin(Ctx, Index, SubInd);
	{Pid, Mod} when is_pid(Pid)->
	    ?dbg(srv, "read_begin: Process ~p subscribes to index ~7.16.0#\n", 
		 [Pid, Index]),
	    app_read_begin(Ctx, Index, SubInd, Pid, Mod);
	{dead, _Mod} ->
	    ?dbg(srv, "read_begin: Reserver process for index ~7.16.0# dead.\n", [Index]),
	    {error, ?abort_internal_error}; %% ???
	_Other ->
	    ?dbg(srv, "read_begin: Other case = ~p\n", [_Other]),
	    {error, ?abort_internal_error}
    end.

central_read_begin(Ctx, Index, SubInd) ->
    Dict = Ctx#sdo_ctx.dict,
    case co_dict:lookup_entry(Dict, {Index,SubInd}) of
	{ok,E} ->
	    if (E#dict_entry.access band ?ACCESS_RO) =:= ?ACCESS_RO ->
		    ?dbg(srv, "central_read_begin: Read access ok\n", []),
		    co_data_buf:init(read, Dict, E,
				     Ctx#sdo_ctx.read_buf_size, 
				     trunc(Ctx#sdo_ctx.read_buf_size * 
					       Ctx#sdo_ctx.load_ratio));
	       true ->
		    {error, ?abort_read_not_allowed}
	    end;
	{error, Reason}  ->
	    {error, Reason}
    end.

app_read_begin(Ctx, Index, SubInd, Pid, Mod) ->
    case Mod:get_entry(Pid, {Index, SubInd}) of
	{entry, Entry} ->
	    if (Entry#app_entry.access band ?ACCESS_RO) =:= ?ACCESS_RO ->
		    ?dbg(srv, "app_read_begin: Read access ok\n", []),
		    ?dbg(srv, "app_read_begin: Transfer mode = ~p\n", 
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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% SEGMENT DOWNLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_segment_download(S) ->
    IX = S#co_session.index,
    SI = S#co_session.subind,
    if S#co_session.exp =:= 1 ->
	    %% Only one segment to write
	    NBytes = if S#co_session.size_ind =:= 1 -> 4-S#co_session.n;
			true -> 0
		     end,
	    <<Data:NBytes/binary, _Filler/binary>> = S#co_session.data,
	    ?dbg(srv, "start_segment_download: expedited, Data = ~p\n", [Data]),
	    case co_data_buf:write(S#co_session.buf, Data, true, segment) of
		{ok, Buf1, Mref} when is_reference(Mref) ->
		    %% Called an application
		    S1 = S#co_session {mref = Mref, buf = Buf1},
		    {next_state, s_writing_segment, S1, ?TMO(S1)};
		{ok, _Buf1} ->
		    R = ?mk_scs_initiate_download_response(IX,SI),
		    send(S, R),
		    {stop, normal, S};
		{error,Reason} ->
		    co_session:abort(S, Reason)
	    end;
       true ->
	    ?dbg(srv, "start_segment_download: not expedited\n", []),
	    %% FIXME: check if max_size already set
	    %% reject if bad!
	    %% set T=1 since client will start wibuf 0
	    S1 = S#co_session {t=1},
	    R  = ?mk_scs_initiate_download_response(IX,SI),
	    send(S1, R),
	    {next_state, s_segmented_download, S1, ?TMO(S1)}
    end.

 
%%
%% state: segmented_download
%%    next_state:  segmented_download or s_writing_segment
%%
s_segmented_download(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_download_segment_request(T,_N,_C,_D) 
	  when T =:= S#co_session.t ->
	    co_session:abort(S, ?abort_toggle_not_alternated);

	?ma_ccs_download_segment_request(T,N,Last,Data) ->
	    NBytes = 7-N,
	    Eod = (Last =:= 1),
	    <<DataToWrite:NBytes/binary, _Filler/binary>> = Data,
	    case co_data_buf:write(S#co_session.buf, DataToWrite, Eod, segment) of
		{ok, Buf, Mref} ->
		    %% Called an application
		    S1 = S#co_session {t = T, mref = Mref, buf = Buf},
		    %% Reply with same toggle value as the request
		    R = ?mk_scs_download_segment_response(T),
		    send(S1,R),
		    if Eod ->
			    %% Wait for write reply from app
			    {next_state, s_writing_segment, S1,?TMO(S1)};
		       true ->
			    {next_state, s_segmented_download, S1,?TMO(S1)}
		    end;
		{ok, Buf} ->
		    S1 = S#co_session {t = T, buf = Buf},
		    %% Reply with same toggle value as the request
		    R = ?mk_scs_download_segment_response(T),
		    send(S1,R),
		    if Eod ->
			    {stop, normal, S1};
		       true ->
			    {next_state, s_segmented_download, S1,?TMO(S1)}
		    end;
		{error,Reason} ->
		    co_session:abort(S,Reason)
	    end;
	_ ->
	    co_session:l_abort(M, S, s_segmented_download)
    end;
s_segmented_download(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

%%
%% state: writing_segment_started (for application stored data)
%%    next_state:  s_segment_download
%%
s_writing_segment_started({Mref, Reply} = M, S)  ->
    ?dbg(srv, "s_writing_segment_started: Got event = ~p\n", [M]),
    case S#co_session.mref of
	Mref ->
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    start_segment_download(S#co_session {buf = Buf});
	_Other ->
	    co_session:l_abort(M, S, s_writing_segment_started)
    end;
s_writing_segment_started(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_writing_segment_started(M, S)  ->
    ?dbg(srv, "s_writing_segment_started: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).


%%
%% state: s_writing_segment (for application stored data)
%%    next_state:  No state
%%
s_writing_segment({Mref, Reply} = M, S)  ->
    ?dbg(srv, "s_writing_segment: Got event = ~p\n", [M]),
    case {S#co_session.mref, Reply} of
	{Mref, ok} ->
	    %% Atomic reply
	    erlang:demonitor(Mref, [flush]),
	    R = ?mk_scs_initiate_download_response(S#co_session.index, 
						   S#co_session.subind),
	    send(S,R),
	    {stop, normal, S};
	{Mref, {ok, Ref}} when is_reference(Ref)->
	    %% Streamed reply
	    erlang:demonitor(Mref, [flush]),
	    {stop, normal, S};
	_Other ->
	    co_session:l_abort(M, S, s_writing)
    end;
s_writing_segment(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_writing_segment(M, S)  ->
    ?dbg(srv, "s_writing_segment: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% SEGMENT UPLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_segmented_upload(S) ->
    ?dbg(srv, "start_segmented_upload\n", []),
    Buf = S#co_session.buf,
    IX = S#co_session.index,
    SI = S#co_session.subind,
    NBytes = co_data_buf:data_size(Buf),
    EofFlag = co_data_buf:eof(Buf),
    ?dbg(srv, "start_segmented_upload, nbytes = ~p\n", [NBytes]),
    if NBytes =/= 0, NBytes =< 4 andalso EofFlag =:= true ->
	    case co_data_buf:read(Buf, NBytes) of
		{ok, Data, true, _Buf1} ->
		    ?dbg(srv, "start_segmented_upload, expediated, data = ~p", 
			 [Data]),
		    Data1 = co_sdo:pad(Data, 4),
		    E=1,
		    SizeInd=1,
		    N = 4 - NBytes,
		    R=?mk_scs_initiate_upload_response(N,E,SizeInd,IX,SI,Data1),
		    send(S, R),
		    {stop, normal, S};
		{error, Reason} ->
		    co_session:abort(S, Reason)
	    end;
       (NBytes =:= 0 andalso EofFlag =:= true) orelse
       (NBytes =:= undefined) ->
	    N=0, E=0, SizeInd=0,
	    Data = <<0:32/?SDO_ENDIAN>>, %% filler
	    R=?mk_scs_initiate_upload_response(N,E,SizeInd,
					       IX,SI,Data),
	    send(S, R),
	    {next_state, s_segmented_upload, S, ?TMO(S)};
       true ->
	    N=0, E=0, SizeInd=1,
	    Data = <<NBytes:32/?SDO_ENDIAN>>,
	    R=?mk_scs_initiate_upload_response(N,E,SizeInd,
					       IX,SI,Data),
	    send(S, R),
	    {next_state, s_segmented_upload, S, ?TMO(S)}
    end.


%%
%% state: segment_upload
%%    next_state:  segmented_upload
%%
s_segmented_upload(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_upload_segment_request(T) when T =/= S#co_session.t ->
	    co_session:abort(S, ?abort_toggle_not_alternated);
	?ma_ccs_upload_segment_request(T) ->
	    read_segment(S#co_session {t = T});
	_ ->
	    co_session:l_abort(M, S, s_segmented_upload)
    end;
s_segmented_upload(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

read_segment(S) ->
    case co_data_buf:read(S#co_session.buf,7) of
	{ok, Data, Eod, Buf} ->
	    ?dbg(srv, "read_segment: data=~p, Eod=~p\n", 
		 [Data, Eod]),
	    upload_segment(S#co_session {buf = Buf}, Data, Eod);
	{ok, Buf, Mref} ->
	    %% Called an application
	    ?dbg(srv, "s_segmented_upload: mref=~p\n", 
		 [Mref]),
	    S1 = S#co_session {mref = Mref, buf = Buf},
	    {next_state, s_reading_segment, S1, ?TMO(S1)};
	{error,Reason} ->
	    co_session:abort(S,Reason)
    end.

upload_segment(S, Data, Eod) ->
    T1 = 1-S#co_session.t,
    N = 7-size(Data),
    %% erlang:display({T1,Remain,N,Data}),
    if Eod =:= true ->
	    Data1 = co_sdo:pad(Data,7),
	    R = ?mk_scs_upload_segment_response(S#co_session.t,N,1,Data1),
	    send(S,R),
	    {stop,normal,S};
       true ->
	    Data1 = co_sdo:pad(Data,7),
	    R = ?mk_scs_upload_segment_response(S#co_session.t,N,0,Data1),
	    send(S,R),
	    S1 = S#co_session {t=T1},
	    {next_state, s_segmented_upload, S1, ?TMO(S1)}
    end.

%%
%% state: reading_segment_started (for application stored data)
%%    next_state:  segmented_upload
%%
s_reading_segment_started({Mref, Reply} = M, S)  ->
    ?dbg(srv, "s_reading_segment_started: Got event = ~p\n", [M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, _Value}} ->
	    %% Atomic
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    start_segmented_upload(S#co_session {buf = Buf});	    
	{Mref, {ok, _Ref, _Size}} ->
	    %% Streamed
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    %% Start to fill data buffer
	    case co_data_buf:load(Buf) of
		{ok, Buf1} ->
		    %% Buffer loaded
		    start_segmented_upload(S#co_session {buf = Buf1});
		{ok, Buf1, Mref1} ->
		    %% Wait for data ??
		    start_segmented_upload(S#co_session {buf = Buf1, mref = Mref1});
		{error, Error} ->
		    co_session:l_abort(M, S, s_reading_segment_started)
	    end;
	_Other ->
	    co_session:l_abort(M, S, s_reading_segment_started)
    end;
s_reading_segment_started(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_reading_segment_started(M, S)  ->
    ?dbg(srv, "s_reading_segment_started: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).

s_reading_segment(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_reading_segment(M, S) ->
    %% All correct messages should be handled in handle_info()
    ?dbg(srv, "s_reading_segment: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% BLOCK UPLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_block_upload(S) ->
    Buf = S#co_session.buf,
    IX = S#co_session.index,
    SI = S#co_session.subind,
    NBytes = case co_data_buf:data_size(Buf) of
		 undefined -> 0;
		 N -> N
	     end,
    ?dbg(srv, "start_block_upload bytes=~p\n", [NBytes]),
    DoCrc = (S#co_session.ctx)#sdo_ctx.use_crc andalso 
						 (S#co_session.clientcrc =:= 1),
    CrcSup = ?UINT1(DoCrc),
    R = ?mk_scs_block_upload_response(CrcSup,?UINT1(NBytes > 0),IX,SI,NBytes),
    S1 = S#co_session { crc=DoCrc, blkcrc=co_crc:init(), blkbytes=0, buf=Buf },
    send(S1, R),
    {next_state, s_block_upload_start,S1,?TMO(S1)}.

%%
%% state: block_upload_start
%%    next_state:  block_upload_response or block_upload_response_last
%%
s_block_upload_start(M, S)  when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_block_upload_start() ->
	    read_block_segment(S#co_session {blkseq = 1});
	_ ->
	    co_session:l_abort(M, S, s_block_upload_start)
    end;
s_block_upload_start(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).


read_block_segment(S) ->
    ?dbg(srv, "read_block_segment: Seq=~p\n", [S#co_session.blkseq]),
    case co_data_buf:read(S#co_session.buf,7) of
	{ok, Data, Eod, Buf} ->
	    upload_block_segment(S#co_session {buf = Buf}, Data, Eod);
	{ok, Buf, Mref} ->
	    %% Called an application
	    ?dbg(srv, "read_block_segment: mref=~p\n", [Mref]),
	    S1 = S#co_session {mref = Mref, buf = Buf},
	    {next_state, s_reading_block_segment, S1, ?TMO(S1)};
	{error,Reason} ->
	    co_session:abort(S,Reason)
    end.

upload_block_segment(S, Data, Eod) ->
    ?dbg(srv, "upload_block_segment: Data = ~p, Eod = ~p\n", [Data, Eod]),
    Seq = S#co_session.blkseq,
    Last = ?UINT1(Eod),
    Data1 = co_sdo:pad(Data, 7),
    R = ?mk_block_segment(Last,Seq,Data1),
    NBytes = S#co_session.blkbytes + byte_size(Data),
    ?dbg(srv, "upload_block_segment: data1 = ~p, nbytes = ~p\n",
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
	    {next_state, s_block_upload_response_last, S1, ?TMO(S1)};
       Seq =:= S#co_session.blksize ->
	    ?dbg(srv, "upload_block_segment: Seq = ~p\n", [Seq]),
	    {next_state, s_block_upload_response, S1, ?TMO(S1)};
       true ->
	    read_block_segment(S1#co_session {blkseq = Seq + 1})
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
	    read_block_segment(S1#co_session {blkseq = 1});
	?ma_ccs_block_upload_response(_AckSeq,_BlkSize) ->
	    co_session:abort(S, ?abort_invalid_sequence_number);
	_ ->
	    co_session:l_abort(M, S, s_block_upload_response)
    end;
s_block_upload_response(timeout,S) ->
    co_session:abort(S, ?abort_timed_out).

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
	    co_session:abort(S, ?abort_invalid_sequence_number);	    
	_ ->
	    co_session:l_abort(M, S, s_block_upload_response_last)
    end;
s_block_upload_response_last(timeout,S) ->
    co_session:abort(S, ?abort_timed_out).

%%
%% state: block_upload_end_response
%%    next_state: No state
%%
s_block_upload_end_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_block_upload_end_response() ->
	    {stop, normal, S};
	_ ->
	    co_session:l_abort(M, S, s_block_upload_end_response)
    end;
s_block_upload_end_response(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

%%
%% state: reading_block_started (for application stored data)
%%    next_state:  blocked_upload
%%
s_reading_block_started({Mref, Reply} = M, S)  ->
    ?dbg(srv, "s_reading_block_started: Got event = ~p\n", [M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, _Value}} ->
	    %% Atomic
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    segment_or_block(S#co_session {buf = Buf});
	{Mref, {ok, _Ref, _Size}} ->
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    case co_data_buf:load(Buf) of
		{ok, Buf1} ->
		    %% Buffer loaded
		    start_block_upload(S#co_session {buf = Buf1});
		{ok, Buf1, Mref1} ->
		    start_block_upload(S#co_session {buf = Buf1, mref = Mref1})
	    end;
	_Other ->
	    co_session:l_abort(M, S, s_reading_block_started)
    end;
s_reading_block_started(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_reading_block_started(M, S)  ->
    ?dbg(srv, "s_reading_block_started: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).


%% Checks if protocol switch from block to segment should be done
segment_or_block(S) -> 
    NBytes = case co_data_buf:data_size(S#co_session.buf) of
		 undefined -> 0;
		 N -> N
	     end,
    if S#co_session.pst =/= 0, NBytes > 0, 
       NBytes =< S#co_session.pst ->
	    ?dbg(srv, "protocol switch\n",[]),
	    start_segmented_upload(S);
       true ->
	    start_block_upload(S)
    end.

s_reading_block_segment(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_reading_block_segment(M, S) ->
    %% All correct messages should be handled in handle_info()
    ?dbg(srv, "s_reading_segment: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).


    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% BLOCK DOWNLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start_block_download(S) ->
    IX = S#co_session.index,
    SI = S#co_session.subind,
    DoCrc = (S#co_session.ctx)#sdo_ctx.use_crc andalso (S#co_session.crc =:= 1),
    GenCrc = ?UINT1(DoCrc),
    %% FIXME: Calculate the BlkSize from data
    BlkSize = co_session:next_blksize(S),
    S1 = S#co_session { crc=DoCrc, blkcrc=co_crc:init(), blksize=BlkSize},
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
	?ma_block_segment(Last,CliSeq,Data) when CliSeq =:= NextSeq ->
	    case co_data_buf:write(S#co_session.buf, Data, false, block) of
		{ok, Buf} ->
		    block_segment_written(S#co_session {buf = Buf, last = Last});
		{ok, Buf, Mref} ->
		    block_segment_written(S#co_session {buf = Buf, last = Last, 
							mref = Mref});
		{error, Reason} ->
		    co_session:abort(S, Reason)
	    end;
	?ma_block_segment(_Last,Seq,_Data) when Seq =:= 0; Seq > S#co_session.blksize ->
	    co_session:abort(S, ?abort_invalid_sequence_number);
	?ma_block_segment(_Last,_Seq,_Data) ->
	    %% here we could takecare of out of order data
	    co_session:abort(S, ?abort_invalid_sequence_number);
	%% Handle abort and spurious packets ...
	%% We can not use l_abort here because we do not know if message
	%% is an abort or not.
	_ ->
	    co_session:abort(S, ?abort_command_specifier)
    end;
s_block_download(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).

block_segment_written(S) ->
    Last = S#co_session.last,
    NextSeq = S#co_session.blkseq + 1,
    if Last =:= 1; NextSeq =:= S#co_session.blksize ->
	    BlkSize = co_session:next_blksize(S),
	    S1 = S#co_session {blkseq=0, blksize=BlkSize},
	    R = ?mk_scs_block_download_response(NextSeq,BlkSize),
	    send(S1, R),
	    if Last =:= 1 ->
		    {next_state, s_block_download_end, S1,?TMO(S1)};
	       true ->
		    {next_state, s_block_download, S1, ?TMO(S1)}
	    end;
       true ->
	    S1 = S#co_session {blkseq=NextSeq},
	    {next_state, s_block_download, S1, ?BLKTMO(S1)}
    end.

%%
%% state: s_block_download_end
%%    next_state:  No state or s_writing_block_end
%%
s_block_download_end(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_ccs_block_download_end_request(N,CRC) ->
	    %% CRC ??
	    case co_data_buf:write(S#co_session.buf,N,true,block) of	    
		{ok, Buf, Mref} ->
		    %% Called an application
		    S1 = S#co_session {mref = Mref, buf = Buf},
		    {next_state, s_writing_block_end, S1, ?TMO(S1)};
		    
		{error,Reason} ->
		    co_session:abort(S, Reason);

		_ -> %% this can be any thing ok | true ..
		    R = ?mk_scs_block_download_end_response(),
		    send(S, R),
		    {stop, normal, S}
	    end;
	_ ->
	    co_session:l_abort(M, S, s_block_download_end)
    end;
s_block_download_end(timeout, S) ->
    co_session:abort(S, ?abort_timed_out).    

%%
%% state: writing_block_started (for application stored data)
%%    next_state:  s_block_download
%%
s_writing_block_started({Mref, Reply} = M, S)  ->
    ?dbg(srv, "s_writing_block_started: Got event = ~p\n", [M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, _Ref, _WriteSze}} ->
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    start_block_download(S#co_session {buf = Buf});
	_Other ->
	    co_session:l_abort(M, S, s_writing_block_started)
    end;
s_writing_block_started(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_writing_block_started(M, S)  ->
    ?dbg(srv, "s_writing_block_started: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).

s_writing_block_end(timeout, S) ->
    co_session:abort(S, ?abort_timed_out);
s_writing_block_end(M, S)  ->
    %% All correct messages should be taken care of in handle_info()
    ?dbg(srv, "s_writing_block: Got event = ~p, aborting\n", [M]),
    co_session:demonitor_and_abort(M, S).


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
    ?dbg(srv, "handle_event: Got event ~p\n",[Event]),
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
    ?dbg(srv, "handle_sync_event: Got event ~p\n",[Event]),
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
    ?dbg(srv, "handle_info: Reply = ~p, State = ~p\n",[Reply, StateName]),
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
	    ?dbg(srv, "handle_info: wrong mref, ignoring\n",[]),
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
    ?dbg(srv, "handle_info: Got info ~p\n",[Info]),
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
    ?dbg(srv, "check_writing_block_end: State = ~p\n",[StateName]),
    case S#co_session.mref of
	Mref ->
	    erlang:demonitor(Mref, [flush]),
	    case StateName of
		s_writing_block_end ->
		    ?dbg(srv, "handle_info: last reply, terminating\n",[]),
		    R = ?mk_scs_block_download_end_response(),
		    send(S, R),
		    {stop, normal, S};
		State ->
		    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
		    {next_state, State, S#co_session {buf = Buf}}
	    end;
	_OtherRef ->
	    %% Ignore reply
	    ?dbg(srv, "handle_info: wrong mref, ignoring\n",[]),
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

send(S, Data) when is_binary(Data) ->
    ?dbg(session, "send: ~s\n", [co_format:format_sdo(co_sdo:decode_tx(Data))]),
    co_session:send(S, Data).

