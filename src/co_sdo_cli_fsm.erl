%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2012, Rogvall Invest AB, <tony@rogvall.se>
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
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%%   CANopen SDO Client Finite State Machine
%%%
%%%    Started by the CANOpen node when an SDO session is initialized.
%%%
%%% File: co_sdo_srv_fsm.erl<br/>
%%% Created:  4 Jun 2010 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(co_sdo_cli_fsm).

-behaviour(gen_fsm).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/sdo.hrl").
-include("../include/co_app.hrl").

%% API
-export([store/8, fetch/8]).

%% gen_fsm callbacks
-export([init/1, handle_event/3,
	 handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% States
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
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize.
%%
%% @end
%%--------------------------------------------------------------------
-spec store(Ctx::#sdo_ctx{},
	    Mode:: segment | block,
	    Client::pid(), 
	    Src::integer(),
	    Dst::integer(),
	    Ix::integer(),
	    Si::integer(),
	    Source:: {app, Pid::pid(), Mod::atom()} | 
		     {data, Bin::binary}) -> 
		   {ok, Pid::pid()} | 
		   ignore | 
		   {error, Error::term()}.

store(Ctx,Mode,Client,Src,Dst,Ix,Si,Source) when is_record(Ctx, sdo_ctx) ->
    lager:debug([{index, Ix}], 
		"store: mode = ~p, from = ~p, ix = ~.16.0#, si = ~p, source = ~p",
		[Mode, Client, Ix, Si, Source]),
    gen_fsm:start(?MODULE, 
		  {store,Mode,Ctx,Client,self(),Src,Dst,Ix,Si,Source}, []).

%%--------------------------------------------------------------------
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. 
%%
%% @end
%%--------------------------------------------------------------------
-spec fetch(Ctx::#sdo_ctx{},
	    Mode:: segment | block,
	    Client::term(), %% gen_server-From 
	    Src::integer(),
	    Dst::integer(),
	    Ix::integer(),
	    Si::integer(),
	    Destination:: {app, Pid::pid(), Mod::atom()} | 
			  data) -> 
		   {ok, Pid::pid()} | 
		   ignore | 
		   {error, Error::term()}.

fetch(Ctx,Mode,Client,Src,Dst,Ix,Si,data) ->
    lager:debug([{index, {Ix, Si}}], 
	 "fetch: mode = ~p, from = ~w, ix = ~.16.0#, si = ~p, "
	 "destination = data", [Mode, Client, Ix, Si]),
    gen_fsm:start(?MODULE, 
	    {fetch,Mode,Ctx,Client,self(),Src,Dst,Ix,Si,{data, Client}}, []);
fetch(Ctx,Mode,Client,Src,Dst,Ix,Si,Destination) ->
    lager:debug([{index, {Ix, Si}}], 
	 "fetch: mode = ~p, from = ~w, ix = ~.16.0#, si = ~p, "
	 "destination = ~w", [Mode, Client, Ix, Si, Destination]),
    gen_fsm:start(?MODULE, 
		  {fetch,Mode,Ctx,Client,self(),Src,Dst,Ix,Si,Destination}, []).

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
%%
%% @end
%%--------------------------------------------------------------------
init({Action,Mode,Ctx,Client,NodePid,Src,Dst,Ix,Si,Term}) ->
    case Ctx#sdo_ctx.debug of 
        true -> co_lib:debug(true);
        _ -> do_nothing
    end,
    lager:debug([{index, {Ix, Si}}], 
		"init: ~p ~p src=~.16#, dst=~.16#", [Action, Mode, Src, Dst]),
    lager:debug([{index, {Ix, Si}}], 
		"init: from = ~w, index = ~4.16.0B:~p, term = ~w",
		[Client, Ix, Si, Term]),
    S = new_session(Ctx,Client,NodePid,Src,Dst,Ix,Si),
    apply(?MODULE, Action, [S, Mode, Term]).

%% @private
store(S=#co_session {ctx = Ctx, index = Ix, subind = Si}, Mode, 
      {app, Pid, Module}) 
  when is_pid(Pid), is_atom(Module) ->
    case read_begin(Ctx, Ix, Si, Pid, Module) of
	{ok, Buf} ->
	    case Mode of
		block ->
		    start_block_download(S#co_session {buf = Buf}, ok);
		segment ->
		    start_segmented_download(S#co_session {buf = Buf}, ok)
	    end;
	{ok, Buf, Mref} when is_reference(Mref) ->
	    %% Application called, wait for reply
	    S1 = S#co_session {mref = Mref, buf = Buf},
	    case Mode of 
		block ->
		    {ok, s_reading_block_started, S1, local_timeout(S1)};
		segment ->
		    {ok, s_reading_segment_started, S1, local_timeout(S1)}
	    end;
	{error,Reason} ->
	    lager:debug([{index, {Ix, Si}}], 
		 "store: read failed, reason = ~p", [Reason]),	    
	    abort(S, Reason)
    end;
store(S=#co_session {ctx = Ctx, index = Ix, subind = Si}, Mode, {data, Data}) 
  when is_binary(Data) ->
    case co_data_buf:init(read, self(), {Data, {Ix, Si}}, 
			  Ctx#sdo_ctx.readbufsize, 
			  trunc(Ctx#sdo_ctx.readbufsize * 
				    Ctx#sdo_ctx.load_ratio)) of 
	{ok, Buf} ->
	    case Mode of 
		block ->
		    start_block_download(S#co_session {buf = Buf}, ok);
		segment ->
		    start_segmented_download(S#co_session {buf = Buf}, ok)
		end;
	{error, Reason} ->
	    lager:debug([{index, {Ix, Si}}], 
		 "store: init failed, reason = ~p", [Reason]),	    
	    abort(S, Reason)
    end.

%% @private
fetch(S=#co_session {ctx = Ctx, index = Ix, subind = Si}, Mode, 
      {app, Pid, Module}) 
  when is_pid(Pid), is_atom(Module) ->
    case write_begin(Ctx, Ix, Si, Pid, Module) of
	{ok, Buf}  -> 
	    case Mode of
		block ->
		    start_block_upload(S#co_session {buf = Buf}, ok);
		segment ->
		    start_segmented_upload(S#co_session {buf = Buf}, ok)
		end;
	{ok, Buf, Mref} ->
	    %% Application called, wait for reply
	    S1 = S#co_session { buf=Buf, mref=Mref },
	    case Mode of 
		block ->
		    {ok, s_writing_block_started,S1,local_timeout(S1)};
		segment ->
		    {ok, s_writing_segment_started,S1,local_timeout(S1)}
	    end;
	{error,Reason} ->
	    lager:debug([{index, {Ix, Si}}], 
		 "fetch: write failed, reason = ~p", [Reason]),	    
	    abort(S, Reason)
    end;
fetch(S=#co_session {ctx = Ctx, index = Ix, subind = Si}, Mode, 
      {data, Client}) ->
    case co_data_buf:init(write, self(), {(<<>>), {Ix, Si}, Client}, 
			  Ctx#sdo_ctx.atomic_limit) of
	{ok, Buf} ->
	    case Mode of 
		block ->
		    start_block_upload(S#co_session {buf = Buf}, ok);
		segment ->
		    start_segmented_upload(S#co_session {buf = Buf}, ok)
		end;
	{error, Reason} ->
	    lager:debug([{index, {Ix, Si}}], 
		 "fetch: init failed, reason = ~p", [Reason]),
	    abort(S, Reason)
    end.
	
read_begin(Ctx, Ix, Si, Pid, Mod) ->
    case Mod:index_specification(Pid, {Ix, Si}) of
	{spec, Spec} ->
	    if (Spec#index_spec.access band ?ACCESS_RO) =:= ?ACCESS_RO ->
		    lager:debug([{index, {Ix, Si}}], 
				"read_begin: Read access ok", []),
		    lager:debug([{index, {Ix, Si}}], 
				"read_begin: Transfer mode = ~p", 
			 [Spec#index_spec.transfer]),
		    co_data_buf:init(read, Pid, Spec, 
				     Ctx#sdo_ctx.readbufsize, 
				     trunc(Ctx#sdo_ctx.readbufsize * 
					       Ctx#sdo_ctx.load_ratio));
	       true ->
		    {spec, ?abort_read_not_allowed}
	    end;
	Error ->
	    Error
    end.

write_begin(Ctx, Ix, Si, Pid, Mod) ->
    case Mod:index_specification(Pid, {Ix, Si}) of
	{spec, Spec} ->
	    if (Spec#index_spec.access band ?ACCESS_WO) =:= ?ACCESS_WO ->
		    lager:debug([{index, {Ix, Si}}], 
			 "write_begin: transfer=~p, type = ~p",
			 [Spec#index_spec.transfer, Spec#index_spec.type]),
		    co_data_buf:init(write, Pid, Spec, Ctx#sdo_ctx.atomic_limit);
	       true ->
		    {error, ?abort_unsupported_access}
	    end;
	{error, Reason}  ->
	    {error, Reason}
    end.
    


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% SEGMENT DOWNLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%--------------------------------------------------------------------
%% @doc 
%% Start downloading segments.
%% @end
%%--------------------------------------------------------------------
start_segmented_download(S=#co_session {buf = Buf, index = Ix, subind = Si}, 
			 Reply) ->
    NBytes = co_data_buf:data_size(Buf),
    EofFlag = co_data_buf:eof(Buf),
    lager:debug([{index, {Ix, Si}}], 
		"start_segmented_download: nbytes = ~p, eof = ~p",
	 [NBytes, EofFlag]),
    if NBytes =/= 0, NBytes =< 4 andalso EofFlag =:= true ->
	    case co_data_buf:read(Buf, NBytes) of
		{ok, Data, true, Buf1} ->
		    lager:debug([{index, {Ix, Si}}], 
			 "start_segmented_download, expediated.", []),
		    N = 4-size(Data),
		    Data1 = co_sdo:pad(Data,4),
		    Expedited = 1,
		    SizeInd   = 1,
		    R=?mk_ccs_initiate_download_request(N,Expedited,SizeInd,
							Ix,Si,Data1),
		    send(S, R),
		    {Reply, s_segmented_download_end, 
		     S#co_session {buf = Buf1}, remote_timeout(S)};
		{error, Reason} ->
		    lager:debug([{index, {Ix, Si}}], 
			 "start_segmented_download: read failed, "
			 "reason = ~p", [Reason]),
		    abort(S, Reason)
	    end;
       true ->
	    %% FIXME: add streaming protocol Size=0
	    N = 0,
	    Data1 = <<NBytes:32/?SDO_ENDIAN>>,
	    Expedited = 0,
	    SizeInd = 1,
	    R=?mk_ccs_initiate_download_request(N,Expedited,SizeInd,
						Ix,Si,Data1),
	    send(S, R),
	    {Reply, s_segmented_download, S, remote_timeout(S)}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Reading and sending segments.<br/>
%% Expected events are:
%% <ul>
%% <li>initiate_download_response</li>
%% <li>download_segment_response</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_reading_segment </li>
%% <li> s_segment_download </li>
%% <li> s_segment_download_end </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_segmented_download(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_segmented_download(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_initiate_download_response(Ix,Si) when 
	      Ix =:= S#co_session.index,
	      Si =:= S#co_session.subind ->
	    read_segment(S);
	?ma_scs_download_segment_response(T) when T =/= S#co_session.t ->
	    abort(S, ?abort_toggle_not_alternated);
	?ma_scs_download_segment_response(T) ->
	    read_segment(S#co_session {t=1-T} );
	_ ->
	    remote_abort(M, S, s_segmented_download)
    end;
s_segmented_download(timeout, S) ->
    abort(S, ?abort_timed_out).

read_segment(S=#co_session{buf = OldBuf, index = Ix, subind = Si}) ->
    case co_data_buf:read(OldBuf,7) of
	{ok, Data, Eod, Buf} ->
	    lager:debug([{index, {Ix, Si}}], "read_segment: data=~p, Eod=~p", 
		 [Data, Eod]),
	    send_segment(S#co_session {buf = Buf}, Data, Eod);
	{ok, Buf, Mref} ->
	    %% Called an application
	    lager:debug([{index, {Ix, Si}}], "read_segment: mref=~p", [Mref]),
	    S1 = S#co_session {mref = Mref, buf = Buf},
	    {next_state, s_reading_segment, S1, local_timeout(S1)};
	{error, Reason} ->
	    lager:debug([{index, {Ix, Si}}], 
		 "read_segment: read failed, reason = ~p", [Reason]),
	    abort(S, Reason)
    end.

send_segment(S, Data, Eod) ->
    Data1 = co_sdo:pad(Data, 7),
    T = S#co_session.t,
    N = 7 - size(Data),
    Last = ?UINT1(Eod),
    R = ?mk_ccs_download_segment_request(T,N,Last,Data1),
    send(S, R),
    if Eod =:= true ->
	    {next_state, s_segmented_download_end, S, remote_timeout(S)};
       true ->
	    {next_state, s_segmented_download, S, remote_timeout(S)}
    end.
 
%%--------------------------------------------------------------------
%% @doc
%% Finalizing download of segments.<br/>
%% Expected events are:
%% <ul>
%% <li>initiate_download_response</li>
%% <li>download_segment_response</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> stop </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_segmented_download_end(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_segmented_download_end(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_initiate_download_response(Ix,Si) when 
	      Ix =:= S#co_session.index,
	      Si =:= S#co_session.subind ->
	    co_api:session_over(S#co_session.node_pid, normal),
	    gen_server:reply(S#co_session.client, ok),
	    {stop,normal,S};
	?ma_scs_download_segment_response(T) when T =/= S#co_session.t ->
	    abort(S, ?abort_toggle_not_alternated);
	?ma_scs_download_segment_response(_T) ->
	    co_api:session_over(S#co_session.node_pid, normal),
	    gen_server:reply(S#co_session.client, ok),
	    {stop,normal,S};
	_ ->
	    remote_abort(M, S, s_segmented_download)
    end;
s_segmented_download_end(timeout, S) ->
    abort(S, ?abort_timed_out).

%%--------------------------------------------------------------------
%% @doc
%% Initializing reading for application stored data.<br/>
%% Expected events are:
%% <ul>
%% <li>{Mref, {ok, Value}}</li>
%% <li>{Mref, {ok, Ref, Size}}</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_segment_download </li>
%% <li> s_segment_download_end </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_reading_segment_started(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_reading_segment_started({Mref, Reply} = _M, 
			  S=#co_session{buf = OldBuf, index = Ix, subind = Si})  ->
    lager:debug([{index, {Ix, Si}}], 
		"s_reading_segment_started: Got event = ~p", [_M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, _Value}} ->
	    %% Atomic
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(OldBuf, Reply),
	    start_segmented_download(S#co_session {buf = Buf}, next_state);	    
	{Mref, {ok, _Ref, _Size}} ->
	    %% Streamed
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(OldBuf, Reply),
	    %% Start to fill data buffer
	    case co_data_buf:load(Buf) of
		{ok, Buf1} ->
		    %% Buffer loaded
		    start_segmented_download(S#co_session {buf = Buf1}, 
					     next_state);
		{ok, Buf1, Mref1} ->
		    %% Wait for data ??
		    start_segmented_download(S#co_session {buf = Buf1, 
							   mref = Mref1},
					     next_state);
		{error, Reason} ->
		    lager:debug([{index, {Ix, Si}}], 
			 "s_reading_segment_start: load failed, "
			 "reason = ~p", [Reason]),
		    abort(S, Reason)
	    end;
	_Other ->
	    lager:debug([{index, {Ix, Si}}], "s_reading_segment_start: received = ~p, "
		 "aborting", [_Other]),
	    abort(S,?abort_internal_error)
    end;
s_reading_segment_started(timeout, S) ->
    abort(S, ?abort_timed_out);
s_reading_segment_started(M, S=#co_session{index = Ix, subind = Si})  ->
    lager:debug([{index, {Ix, Si}}], 
	 "s_reading_segment_started: Got event = ~p, aborting", [M]),
    demonitor_and_abort(M, S).

%%--------------------------------------------------------------------
%% @doc
%% Reading application stored data.<br/>
%% Expected events are:
%% <ul>
%% <li>{Mref, {ok, Ref, Data, Eod}}</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_segment_download </li>
%% <li> s_segment_download_end </li>
%% <li> s_reading_segment </li>
%% <li> stop </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_reading_segment(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_reading_segment(timeout, S) ->
    abort(S, ?abort_timed_out);
s_reading_segment(M, S=#co_session{index = Ix, subind = Si})  ->
    %% All correct messages should be handled in handle_info()
    lager:debug([{index, {Ix, Si}}], 
	 "s_reading_segment: Got event = ~p, aborting", [M]),
    demonitor_and_abort(M, S).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% SEGMENTED UPLOAD 
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_segmented_upload(S=#co_session {index = Ix, subind = Si}, Reply) ->
    lager:debug([{index, {Ix, Si}}], 
		"start_segmented_upload: ~4.16.0B:~p", [Ix, Si]),
    R = ?mk_ccs_initiate_upload_request(Ix,Si),
    send(S, R),
    {Reply, s_segmented_upload_response, S, remote_timeout(S)}.

%%--------------------------------------------------------------------
%% @doc
%% Receiving first segment.<br/>
%% Expected events are:
%% <ul>
%% <li>initiate_upload_response</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_writing_segment </li>
%% <li> s_segmented_upload </li>
%% <li> stop </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_segmented_upload_response(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_segmented_upload_response(M, S) 
  when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_initiate_upload_response(N,Expedited,SizeInd,Ix,Si,Data) when
	      Ix =:= S#co_session.index,
	      Si =:= S#co_session.subind ->
	    lager:debug([{index, {Ix, Si}}], "s_segmented_upload_response", []),

	    if Expedited =:= 1 ->
		    NBytes = if SizeInd =:= 1 -> 4 - N;
				true -> 0
			     end,
		    <<Data1:NBytes/binary, _Filler/binary>> = Data,
		    lager:debug([{index, {Ix, Si}}], 
			 "s_segmented_upload_response: expedited, "
			 "Data = ~p", [Data1]),
		    NBytes = if SizeInd =:= 1 -> 4-N; true -> 4 end,
		    case co_data_buf:write(S#co_session.buf, Data1, 
					   true, segment) of
			{ok, _Buf1} ->
			    co_api:object_event(S#co_session.node_pid, 
						{Ix, Si}),
			    co_api:session_over(S#co_session.node_pid, normal),
			    {stop, normal, S};
			{ok, Buf1, Mref} when is_reference(Mref) ->
			    %% Called an application
			    S1 = S#co_session {mref = Mref, buf = Buf1},
			    {next_state, s_writing_segment, S1, 
			     local_timeout(S1)};
			{error, Reason} ->
			    lager:debug([{index, {Ix, Si}}], 
				 "s_segmented_upload_response: write "
				 "failed, reason = ~p", [Reason]),
			    abort(S, Reason)
		    end;
	       true -> 
		    %% Not expedited
		    lager:debug([{index, {Ix, Si}}], 
			 "s_segmented_upload_response: Size = ~p", [N]),
		    case co_data_buf:update(S#co_session.buf, {ok, N}) of
			{ok, Buf1} ->
			    T = S#co_session.t,
			    R = ?mk_ccs_upload_segment_request(T),
			    send(S, R),
			    S1 = S#co_session { buf=Buf1 },
			    {next_state, s_segmented_upload, S1, 
			     remote_timeout(S1)};
			{error, Reason} ->
			    lager:debug([{index, {Ix, Si}}], 
				 "s_segmented_upload_response: update "
				 "failed, reason = ~p", [Reason]),
			    abort(S, Reason)
		    end
	    end;
	_ ->
	    remote_abort(M, S, s_segmented_upload_response)
    end;
s_segmented_upload_response(timeout, S) ->
    abort(S, ?abort_timed_out).

%%--------------------------------------------------------------------
%% @doc
%% Receiving segments.<br/>
%% Expected events are:
%% <ul>
%% <li>upload_segment_response</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_writing_segment </li>
%% <li> s_segmented_upload </li>
%% <li> stop </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_segmented_upload(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_segmented_upload(M, S=#co_session {index = Ix, subind = Si, 
				     node_pid = NPid, client = Client}) 
  when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_upload_segment_response(T,_N,_C,_D) 
	  when T =/= S#co_session.t ->
	    abort(S, ?abort_toggle_not_alternated);
	?ma_scs_upload_segment_response(T,N,C,Data) ->
	    lager:debug([{index, {Ix, Si}}], 
		 "s_segmented_upload: Data = ~p", [Data]),	    
	    NBytes = 7-N,
	    Eod = (C =:= 1),
	    <<DataToWrite:NBytes/binary, _Filler/binary>> = Data,
	    case co_data_buf:write(S#co_session.buf, DataToWrite, 
				   Eod, segment) of
		{ok, Buf1} ->
		    if Eod ->
			    co_api:object_event(NPid, {Ix, Si}),
			    co_api:session_over(NPid, normal),
			    gen_server:reply(Client, ok),
			    {stop, normal, S};
		       true ->
			    T1 = 1-T,
			    S1 = S#co_session { t=T1, buf=Buf1 },
			    R = ?mk_ccs_upload_segment_request(T1),
			    send(S1, R),
			    {next_state, s_segmented_upload, S1, 
			     remote_timeout(S1)}
		    end;
		{ok, Buf1, Mref} when is_reference(Mref) ->
		    %% Called an application
		    S1 = S#co_session {mref = Mref, buf = Buf1},
		    {next_state, s_writing_segment, S1, local_timeout(S1)};
		{error, Reason} ->
		    lager:debug([{index, {Ix, Si}}], 
				"s_segmented_upload: update failed, reason = ~p",
				[Reason]),
		    abort(S, Reason)
	    end;
	_ ->
	    remote_abort(M, S, s_segmented_upload)
    end;
s_segmented_upload(timeout, S) ->
    abort(S, ?abort_timed_out).

%%--------------------------------------------------------------------
%% @doc
%% Initializing write for application stored data.<br/>
%% Expected events are:
%% <ul>
%% <li>{Mref, {ok, Ref, Size}}</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_segmented_upload_response </li>
%% <li> stop </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_writing_segment_started(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_writing_segment_started({Mref, Reply} = _M, 
			  S=#co_session{index = Ix, subind = Si})  ->
    lager:debug([{index, {Ix, Si}}], 
		"s_writing_segment_started: Got event = ~p", [_M]),
    case S#co_session.mref of
	Mref ->
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    start_segmented_upload(S#co_session {buf = Buf}, next_state);
	_Other ->
	    lager:debug([{index, {Ix, Si}}], 
		 "s_writing_segment_started: received = ~p, aborting", 
		 [_Other]),
	    abort(S, ?abort_internal_error)
    end;
s_writing_segment_started(timeout, S) ->
    abort(S, ?abort_timed_out);
s_writing_segment_started(M, S=#co_session{index = Ix, subind = Si})  ->
    lager:debug([{index, {Ix, Si}}], 
	 "s_writing_segment_started: Got event = ~p, aborting", [M]),
    demonitor_and_abort(M, S).


%%--------------------------------------------------------------------
%% @doc
%% Writing segments to application. <br/>
%% Expected events are:
%% <ul>
%% <li>{Mref, ok}</li>
%% <li>{Mref, {ok, Ref}}</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> stop </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_writing_segment(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_writing_segment({Mref, Reply} = _M, 
		  S=#co_session {index = Ix, subind = Si, 
				 node_pid = NPid, client = Client})  ->
    lager:debug([{index, {Ix, Si}}], "s_writing_segment: Got event = ~p", [_M]),
    case {S#co_session.mref, Reply} of
	{Mref, ok} ->
	    %% Atomic reply
	    erlang:demonitor(Mref, [flush]),
	    co_api:object_event(NPid, {Ix, Si}),
	    co_api:session_over(NPid, normal),
	    gen_server:reply(S#co_session.client, ok),
	    {stop, normal, S};
	{Mref, {ok, Ref}} when is_reference(Ref)->
	    %% Streamed reply
	    erlang:demonitor(Mref, [flush]),
	    co_api:object_event(NPid, {Ix, Si}),
	    co_api:session_over(NPid, normal),
	    gen_server:reply(Client, ok),
	    {stop, normal, S};
	_Other ->
	    lager:debug([{index, {Ix, Si}}], 
		 "s_writing_segment: received = ~p, aborting", [_Other]),
	    abort(S, ?abort_internal_error)
    end;
s_writing_segment(timeout, S) ->
    abort(S, ?abort_timed_out);
s_writing_segment(M, S=#co_session{index = Ix, subind = Si})  ->
    lager:debug([{index, {Ix, Si}}], 
	 "s_writing_segment: Got event = ~p, aborting", [M]),
    demonitor_and_abort(M, S).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% BLOCK DOWNLOAD
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_block_download(S=#co_session {buf = Buf, ctx = Ctx, 
				    index = Ix, subind = Si}, 
		     Reply) ->
    NBytes = co_data_buf:data_size(Buf),
    UseCrc = ?UINT1(Ctx#sdo_ctx.use_crc),
    SizeInd = 1, %% ???
    R = ?mk_ccs_block_download_request(UseCrc,SizeInd,Ix,Si,NBytes),
    send(S, R),
    {Reply, s_block_initiate_download_response, S, remote_timeout(S)}.
    

%%--------------------------------------------------------------------
%% @doc
%% Block download initialization.<br/>
%% Expected events are:
%% <ul>
%% <li> block_initiate_download_response</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_reading_block_segment </li>
%% <li> s_block_download_response </li>
%% <li> s_block_download_response_last </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_block_initiate_download_response(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_block_initiate_download_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_initiate_download_response(GenCrc,Ix,Si,BlkSize) when
	      Ix =:= S#co_session.index,
	      Si =:= S#co_session.subind ->
	    DoCrc = (S#co_session.ctx)#sdo_ctx.use_crc andalso (GenCrc =:= 1),
	    S1 = S#co_session { crc = DoCrc, blksize=BlkSize,
				blkcrc=co_crc:init(), blkbytes=0 },
	    read_block_segment(S1#co_session {blkseq = 1});
	?ma_scs_block_initiate_download_response(_SC,_Ix,_Si,_BlkSz) ->
	    abort(S, ?abort_command_specifier);
	_ ->
	    remote_abort(M, S, s_block_initiate_download_response)
    end;
s_block_initiate_download_response(timeout, S) ->
    abort(S, ?abort_timed_out).
	    
read_block_segment(S=#co_session{index = Ix, subind = Si}) ->
    lager:debug([{index, {Ix, Si}}], 
	  "read_block_segment: Seq=~p", [S#co_session.blkseq]),
    case co_data_buf:read(S#co_session.buf,7) of
	{ok, Data, Eod, Buf} ->
	    send_block_segment(S#co_session {buf = Buf}, Data, Eod);
	{ok, Buf, Mref} ->
	    %% Called an application
	    lager:debug([{index, {Ix, Si}}], 
			"read_block_segment: mref=~p", [Mref]),
	    S1 = S#co_session {mref = Mref, buf = Buf},
	    {next_state, s_reading_block_segment, S1, remote_timeout(S1)};
	{error, Reason} ->
	    lager:debug([{index, {Ix, Si}}], 
		 "read_block_segment: read failed, reason = ~p", [Reason]),
	    abort(S, Reason)
    end.

send_block_segment(S=#co_session{index = Ix, subind = Si}, Data, Eod) ->
    lager:debug([{index, {Ix, Si}}], 
	  "send_block_segment: Data = ~p, Eod = ~p", [Data, Eod]),
    Seq = S#co_session.blkseq,
    Last = ?UINT1(Eod),
    Data1 = co_sdo:pad(Data, 7),
    R = ?mk_block_segment(Last,Seq,Data1),
    NBytes = S#co_session.blkbytes + byte_size(Data),
    lager:debug([{index, {Ix, Si}}], "send_block_segment: data1 = ~p, nbytes = ~p",
	 [Data1, NBytes]),
    Crc = if S#co_session.crc ->
		  co_crc:update(S#co_session.blkcrc, Data);
	     true ->
		  S#co_session.blkcrc
	  end,
    S1 = S#co_session { blkseq=Seq, blkbytes=NBytes, blkcrc=Crc},
    send(S1, R),
    if Eod ->
	    lager:debug([{index, {Ix, Si}}], 
			"upload_block_segment: Last = ~p", [Last]),
	    {next_state, s_block_download_response_last, S1, 
	     remote_timeout(S1)};
       Seq =:= S#co_session.blksize ->
	    lager:debug([{index, {Ix, Si}}], 
			"upload_block_segment: Seq = ~p", [Seq]),
	    {next_state, s_block_download_response, S1, remote_timeout(S1)};
       true ->
	    read_block_segment(S1#co_session {blkseq = Seq + 1})
    end.

%%--------------------------------------------------------------------
%% @doc
%% Downloading block segments.<br/>
%% Expected events are:
%% <ul>
%% <li> block_download_response</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_reading_block_segment </li>
%% <li> s_block_download_response </li>
%% <li> s_block_download_response_last </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_block_download_response(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_block_download_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_download_response(AckSeq,BlkSize) when 
	      AckSeq =:= S#co_session.blkseq ->
	    read_block_segment(S#co_session { blkseq=0, blksize=BlkSize });
	?ma_scs_block_download_response(_AckSeq,_BlkSize) ->
	    abort(S, ?abort_invalid_sequence_number);
	_ ->
	    remote_abort(M, S, s_block_download_response)
    end;
s_block_download_response(timeout, S) ->
    abort(S, ?abort_timed_out).    
	

%%--------------------------------------------------------------------
%% @doc
%% Downloading last block segment.<br/>
%% Expected events are:
%% <ul>
%% <li> block_download_response</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_block_download_end_response </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_block_download_response_last(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_block_download_response_last(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_download_response(AckSeq,BlkSize) when 
	      AckSeq =:= S#co_session.blkseq ->
	    S1 = S#co_session { blkseq=0, blksize=BlkSize },
	    CRC = co_crc:final(S1#co_session.blkcrc),
	    N   = if S1#co_session.blkbytes =:= 0 ->
			  7;
		     true ->
			  (7- (S1#co_session.blkbytes rem 7)) rem 7
		  end,
	    R = ?mk_ccs_block_download_end_request(N,CRC),
	    send(S1, R),
	    {next_state, s_block_download_end_response, S1, remote_timeout(S1)};
	?ma_scs_block_download_response(_AckSeq,_BlkSz) ->
	    abort(S, ?abort_invalid_sequence_number);
	_ ->
	    remote_abort(M, S, s_block_download_response_last)
    end;
s_block_download_response_last(timeout, S) ->
    abort(S, ?abort_timed_out).    


%%--------------------------------------------------------------------
%% @doc
%% Finalizing downloading blocks.<br/>
%% Expected events are:
%% <ul>
%% <li> block_download_end_response</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> stop </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_block_download_end_response(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_block_download_end_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_download_end_response() ->
	    co_api:session_over(S#co_session.node_pid, normal),
	    gen_server:reply(S#co_session.client, ok),
	    {stop, normal, S};
	_ ->
	    remote_abort(M, S, s_block_download_end_response)
    end;
s_block_download_end_response(timeout, S) ->
    abort(S, ?abort_timed_out).

%%--------------------------------------------------------------------
%% @doc
%% Initilize reading data from application.<br/>
%% Expected events are:
%% <ul>
%% <li>{Mref, {ok, Value}</li>
%% <li>{Mref, {ok, Ref, Size}</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li>  s_block_initiate_download_response</li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_reading_block_started(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_reading_block_started({Mref, Reply} = _M, 
			S=#co_session{index = Ix, subind = Si})  ->
    lager:debug([{index, {Ix, Si}}], 
		"s_reading_block_started: Got event = ~p", [_M]),
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
		    start_block_download(S#co_session {buf = Buf1, 
						       mref = Mref1}, 
					 next_state)
	    end;
	_Other ->
	    lager:debug([{index, {Ix, Si}}], 
		 "s_reading_block_started: received = ~p, aborting", 
		 [_Other]),
	    abort(S, ?abort_internal_error)
    end;
s_reading_block_started(M, S=#co_session{index = Ix, subind = Si})  ->
    lager:debug([{index, {Ix, Si}}], 
	 "s_reading_block_started: Got event = ~p, aborting", [M]),
    demonitor_and_abort(M, S).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% BLOCK UPLOAD 
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_block_upload(S=#co_session {buf = Buf, ctx = Ctx, 
				  index = Ix, subind = Si}, 
		   Reply) ->
    CrcSup = ?UINT1(Ctx#sdo_ctx.use_crc),
    BlkSize = Ctx#sdo_ctx.max_blksize,  %% max number of segments/block
    Pst     = Ctx#sdo_ctx.pst,          %% protcol switch limit 
    R = ?mk_ccs_block_upload_request(CrcSup,Ix,Si,BlkSize,Pst),
    send(S, R),
    S1 = S#co_session { blksize = BlkSize, blkcrc = co_crc:init(), pst = Pst },
    {Reply, s_block_upload_response, S1#co_session {buf = Buf}, 
     remote_timeout(S)}.

%%--------------------------------------------------------------------
%% @doc
%% Uploading block segments.<br/>
%% Expected events are:
%% <ul>
%% <li>block_upload_response</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_block_upload </li>
%% <li> s_writing_segment (protocol switch)</li>
%% <li> s_segmented_upload (protocol switch)</li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_block_upload_response(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_block_upload_response(M, S) when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_upload_response(CrcSup,_SizeInd,Ix,Si,_Size) when
	      Ix =:= S#co_session.index,
	      Si =:= S#co_session.subind ->
	    R = ?mk_ccs_block_upload_start(),
	    send(S, R),
	    %% Size ?? FIXME
	    S1 = S#co_session { crc = CrcSup =:= 1, blkseq = 0 },
	    {next_state, s_block_upload, S1, remote_timeout(S1)};
	?ma_scs_initiate_upload_response(_N,_E,_SizeInd,_Ix,_Si,_Data) ->
	    %% protocol switched
	    s_segmented_upload_response(M, S);
	_ ->
	    %% check if this was a protcol switch...
	    s_segmented_upload_response(M, S)
    end;
s_block_upload_response(timeout, S) ->
    abort(S, ?abort_timed_out).

%%--------------------------------------------------------------------
%% @doc
%% Receiving block segments.<br/>
%% Expected events are:
%% <ul>
%% <li>block_segment</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_block_upload </li>
%% <li> s_block_upload_end </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_block_upload(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_block_upload(M, S=#co_session{index = Ix, subind = Si}) 
  when is_record(M, can_frame) ->
    NextSeq = S#co_session.blkseq+1,
    Crc = S#co_session.blkcrc,
    case M#can_frame.data of
	?ma_block_segment(Last,Seq,Data) when Seq =:= NextSeq ->
	    lager:debug([{index, {Ix, Si}}], "s_block_upload: Data = ~p", [Data]),
	    S1 = if Last =:= 1 ->
			 S#co_session {lastblk = Data};
		    S#co_session.crc->
			 S#co_session {blkcrc = co_crc:update(Crc, Data)};
		    true ->
			  S
		 end,
	    case co_data_buf:write(S1#co_session.buf, Data, false, block) of
		{ok, Buf} ->
		    block_segment_written(S1#co_session {buf = Buf, 
							 last = Last});
		{ok, Buf, Mref} when is_reference(Mref) ->
		    %% Called an application
		    block_segment_written(S1#co_session {buf = Buf, 
							 last = Last, 
							 mref = Mref});
		{error, Reason} ->
		    lager:debug([{index, {Ix, Si}}], 
			 "s_block_upload: write failed, reason = ~p", 
			 [Reason]),	    
		    abort(S, Reason)
	    end;
	?ma_block_segment(_Last,Seq,_Data) 
	  when Seq =:= 0; Seq > S#co_session.blksize ->
	    abort(S, ?abort_invalid_sequence_number);
	?ma_block_segment(_Last,_Seq,_Data) ->
	    %% here we could takecare of out of order data
	    abort(S, ?abort_invalid_sequence_number);
	%% Handle abort and spurious packets ...
	%% We can not use remote_abort here because we do not know if message
	%% is an abort or not.
	_ ->
	    abort(S, ?abort_command_specifier)
    end;
s_block_upload(timeout, S) ->
    abort(S, ?abort_timed_out).


block_segment_written(S=#co_session {last = Last}) ->
    NextSeq = S#co_session.blkseq + 1,
    if Last =:= 1; NextSeq =:= S#co_session.blksize ->
	    BlkSize = co_session:next_blksize(S),
	    S1 = S#co_session {blkseq=0, blksize=BlkSize},
	    R = ?mk_scs_block_download_response(NextSeq,BlkSize),
	    send(S1, R),
	    if Last =:= 1 ->
		    {next_state, s_block_upload_end, S1, remote_timeout(S1)};
	       true ->
		    {next_state, s_block_upload, S1, remote_timeout(S1)}
	    end;
       true ->
	    S1 = S#co_session {blkseq=NextSeq},
	    {next_state, s_block_upload, S1, block_timeout(S1)}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Block upload, last block.<br/>
%% Expected events are:
%% <ul>
%% <li>block_upload_end_request</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_writing_block_end </li>
%% <li> stop </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_block_upload_end(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_block_upload_end(M, S=#co_session {index = Ix, subind = Si, 
				     node_pid = NPid, client = Client}) 
  when is_record(M, can_frame) ->
    case M#can_frame.data of
	?ma_scs_block_upload_end_request(N,ServerCrc) ->
	    %% CRC ??
	    NodeCrc = 
		if S#co_session.crc ->
			CrcN = 7 - N,
			<<CrcData:CrcN/binary, _Pad/binary>> = 
			    S#co_session.lastblk,
			Crc = co_crc:update(S#co_session.blkcrc,CrcData),
			co_crc:final(Crc);
		   true ->
			ServerCrc
		end,
	    
	    case ServerCrc of
		NodeCrc ->
		    %% CRC OK
		    case co_data_buf:write(S#co_session.buf,N,true,block) of
			{ok, Buf, Mref} ->
			    %% Called an application
			    S1 = S#co_session {mref = Mref, buf = Buf},
			    {next_state, s_writing_block_end, S1, 
			     remote_timeout(S1)};
			{ok, _Buf} -> 
			    R = ?mk_scs_block_download_end_response(),
			    send(S, R),
			    co_api:object_event(NPid, {Ix, Si}),
			    co_api:session_over(NPid, normal),
			    gen_server:reply(Client, ok),
			    {stop, normal, S};
			{error,Reason} ->
			    lager:debug([{index, {Ix, Si}}], 
				 "s_block_upload_end: write failed, "
				 "reason = ~p", [Reason]),
			    abort(S, Reason)
		    end;
		_Crc ->
		    lager:debug([{index, {Ix, Si}}], 
			  "s_block_upload_end: crc error, server_crc = ~p, "
			 "node_crc = ~p", [ServerCrc, NodeCrc]),
		    abort(S, ?abort_crc_error)
	    end;
	_ ->
	    remote_abort(M, S, s_block_upload_end)
    end;
s_block_upload_end(timeout, S) ->
    abort(S, ?abort_timed_out).
		
%%--------------------------------------------------------------------
%% @doc
%% Initialize writing data to application.<br/>
%% Expected events are:
%% <ul>
%% <li>{Mref, {ok, Ref, WriteSze}}</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_block_upload_response </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_writing_block_started(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_writing_block_started({Mref, Reply} = _M, 
			S=#co_session{index = Ix, subind = Si})  ->
    lager:debug([{index, {Ix, Si}}], 
		"s_writing_block_started: Got event = ~p", [_M]),
    case {S#co_session.mref, Reply} of
	{Mref, {ok, _Ref, _WriteSze}} ->
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
	    start_block_upload(S#co_session {buf = Buf}, next_state);
	_Other ->
	    lager:debug([{index, {Ix, Si}}], 
		 "s_writing_block_started: received = ~p, aborting", 
		 [_Other]),
	    abort(S, ?abort_internal_error)
    end;
s_writing_block_started(M, S=#co_session{index = Ix, subind = Si})  ->
    lager:debug([{index, {Ix, Si}}], 
	 "s_writing_block_started: Got event = ~p, aborting", [M]),
    demonitor_and_abort(M, S).


%%--------------------------------------------------------------------
%% @doc
%% Writing last data to application.<br/>
%% Expected events are:
%% <ul>
%% <li>{Mref, {ok, Ref}}</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> stop </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_writing_block_end(M::term(), S::#co_session{}) -> 
		       {next_state, NextState::atom(), NextS::#co_session{}} |
		       {next_state, NextState::atom(), NextS::#co_session{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextS::#co_session{}}.

s_writing_block_end(M, S=#co_session{index = Ix, subind = Si})  ->
    %% All correct messages should be taken care of in handle_info()
    lager:debug([{index, {Ix, Si}}], 
		"s_writing_block: Got event = ~p, aborting", [M]),
    demonitor_and_abort(M, S).

	    
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
    {next_state, StateName, S, remote_timeout(S)}.

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
			 {next_state, NextState::atom(), NextS::#co_session{}, 
			  Tout::timeout()} |
			 {stop, Reason::atom(), NewS::#co_session{}}.
			 
handle_info({Mref, {ok, _Ref, _Data, _Eod} = Reply}, StateName, 
	    S=#co_session{index = Ix, subind = Si}) ->
    %% Streamed data read from application
    lager:debug([{index, {Ix, Si}}], 
	 "handle_info: Reply = ~p, State = ~p",[Reply, StateName]),
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
		{error, Reason} ->
		    lager:debug([{index, {Ix, Si}}], 
			 "handle_info: load failed, reason = ~p", [Reason]),
		    abort(S, Reason)
	    end;
	_OtherRef ->
	    %% Ignore reply
	    lager:debug([{index, {Ix, Si}}], 
			"handle_info: wrong mref, ignoring",[]),
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
handle_info(Info, StateName, S=#co_session{index = Ix, subind = Si}) ->
    lager:debug([{index, {Ix, Si}}], "handle_info: Got info ~p",[Info]),
    %% "Converting" info to event
    apply(?MODULE, StateName, [Info, S]).


check_reading(s_reading_segment, S) ->
    read_segment(S);
check_reading(s_reading_block_segment, S) ->
    read_block_segment(S);
check_reading(State, S) -> 
    {next_state, State, S}.
	    

check_writing_block_end({Mref, Reply}, StateName, 
			S=#co_session {index = Ix, subind = Si, 
				       node_pid = NPid, client = Client}) ->
    %% Streamed data write acknowledged
    lager:debug([{index, {Ix, Si}}], 
		"check_writing_block_end: State = ~p", [StateName]),
    case S#co_session.mref of
	Mref ->
	    erlang:demonitor(Mref, [flush]),
	    case StateName of
		s_writing_block_end ->
		    lager:debug([{index, {Ix, Si}}], 
			 "handle_info: last reply, terminating",[]),
		    R = ?mk_scs_block_download_end_response(),
		    send(S, R),
		    co_api:object_event(NPid, {Ix, Si}),
		    co_api:session_over(NPid, normal),
		    gen_server:reply(Client, ok),
		    {stop, normal, S};
		State ->
		    {ok, Buf} = co_data_buf:update(S#co_session.buf, Reply),
		    {next_state, State, S#co_session {buf = Buf}}
	    end;
	_OtherRef ->
	    %% Ignore reply
	    lager:debug([{index, {Ix, Si}}], "handle_info: wrong mref, ignoring",[]),
	    {next_state, StateName, S}
    end.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec terminate(Reason::term(), StateName::atom(), S::#co_session{}) -> 
		       no_return().

terminate(_Reason, _StateName, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term(), StateName::atom(), 
		  S::#co_session{}, Extra::term()) -> 
			 {ok, StateName::atom(), NewS::#co_session{}}.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

new_session(Ctx,Client,NodePid,Src,Dst,Ix,Si) ->
    #co_session {
	     src       = Src,
	     dst       = Dst,
	     index     = Ix,
	     subind    = Si,
	     t         = 0,         %% Toggle value
	     crc       = false,
	     blksize   = 0,
	     blkseq    = 0,
	     blkbytes  = 0,
	     node_pid  = NodePid,
	     client    = Client,
	     ctx       = Ctx
	    }.

local_timeout(S) -> co_session:local_timeout(S).

remote_timeout(S) -> co_session:remote_timeout(S).

block_timeout(S) -> co_session:block_timeout(S).

demonitor_and_abort(_M, S) ->
    case S#co_session.mref of
	Mref when is_reference(Mref)->
	    erlang:demonitor(Mref, [flush]);
	_NoRef ->
	    do_nothing
    end,
    abort(S, ?abort_internal_error).

remote_abort(M, S, StateName) ->
    case M#can_frame.data of
	?ma_scs_abort_transfer(Ix,Si,Code) when
	      Ix =:= S#co_session.index,
	      Si =:= S#co_session.subind ->
	    Reason = co_sdo:decode_abort_code(Code),
	    %% remote party has aborted
	    lager:debug([{index, {Ix, Si}}], 
		 "remote_abort: Other side has aborted in state ~p, \n"
		 "reason ~p, sending error to ~w",
		 [StateName, Reason, S#co_session.client]),
	    co_api:session_over(S#co_session.node_pid, abort),
	    gen_server:reply(S#co_session.client, {error,Reason}),
	    %% If needed add:
	    %% co_api:session_over(S#co_session.node_pid, 
            %%                     {abort, {Ix, Si}, Code}),
	    {stop,  normal, S};
	?ma_scs_abort_transfer(_Ix,_Si, _Code) ->
	    %% probably a delayed abort for an old session ignore
	    lager:debug([{index, {_Ix, _Si}}], 
		 "remote_abort: Old abort in state ~p, reason ~p",
		 [StateName, co_sdo:decode_abort_code(_Code)]),
	    {next_state, StateName, S, remote_timeout(S)};
	_ ->
	    %% we did not expect this command abort
	    lager:debug([{index, {S#co_session.index, S#co_session.subind}}], 
		 "remote_abort: Unexpected frame ~p in state ~p",
		 [M#can_frame.data, StateName]),
	    abort(S, ?abort_command_specifier)
    end.
	    

abort(S=#co_session {buf = Buf, client = Client, index = Ix, subind = Si},
      Reason) ->
    lager:debug([{index, {Ix, Si}}], 
		"abort: Aborting, reason ~p, sending error to ~w", 
		[Reason,Client]),
    Code = co_sdo:encode_abort_code(Reason),
    co_data_buf:abort(Buf, Code),
    co_api:session_over(S#co_session.node_pid, {abort, {Ix, Si}, Code}),
    R = ?mk_ccs_abort_transfer(Ix, Si, Code),
    send(S, R),
    gen_server:reply(Client, {error,Reason}),
    {stop, normal, S}.
    

send(S=#co_session {index = Ix, subind = Si}, Data) 
  when is_binary(Data) ->
    lager:debug([{index, {Ix, Si}}], "send: ~s", 
	 [co_format:format_sdo(co_sdo:decode_rx(Data))]),
    co_session:send(S, Data).

