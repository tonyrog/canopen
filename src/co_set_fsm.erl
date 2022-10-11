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
%%% @author Malotte W Lonne <malotte@malotte.net>
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%%    CANopen set Finite State Machine.<br/>
%%%    Used by the CANOpen node when unpacking of an RPDO requires setting
%%%    of an index belonging to an application.
%%%
%%% File: co_set_fsm.erl<br/>
%%% Created:  18 Jan 2012<br/>
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(co_set_fsm).

-behaviour(gen_fsm).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/sdo.hrl").
-include("../include/co_app.hrl").
-include("../include/co_debug.hrl").

%% API
-export([start/3]).

%% gen_fsm callbacks
-export([init/1, handle_event/3,
	 handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% s_writing
-export([s_writing_started/2]). 
-export([s_writing/2]). 

-record(loop_data,
	{
	  index,
	  app,
	  data,
	  buf,
	  mref
	}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @spec start(App, Index, Data) -> {ok, Pid} | ignore | {error, Error}
%%
%% @doc
%% Start the fsm.
%%
%% @end
%%--------------------------------------------------------------------
start(App, Index = {_Ix, _Si}, Data)  ->
    lager:debug([{index, Index}], 
	  "start: App = ~p, Index = ~7.16.0#:~w, Data = ~w", 
	 [App, _Ix, _Si, Data]),
    gen_fsm:start(?MODULE, [App, Index, Data], []).

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @spec init(Args) -> {ok, State, LoopData} |
%%                     {ok, State, LoopData, Timeout} |
%%                     ignore |
%%                     {stop, StopReason}
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
init([App, I = {_Ix, _Si}, Data]) ->
    %% co_lib:debug(??),
    lager:debug([{index, I}], 
	 "init: App = ~p, Index = ~7.16.0#:~w, Data = ~w", 
	 [App, _Ix, _Si, Data]),
    LD = #loop_data{ index = I, app = App, data = Data },
      
    case write_begin(App, I) of
	{ok, Buf}  -> 
	    start_writing(LD#loop_data {buf=Buf}, ok);
	{ok, Buf, Mref} ->
	    %% Application called, wait for reply
	    {ok, s_writing_started, LD#loop_data{ buf=Buf, mref=Mref }};
	{error, Reason} ->
	    demonitor_and_abort(initial, LD, Reason)
    end.

%%--------------------------------------------------------------------
%% @doc Start a write operation
%% @end
%%--------------------------------------------------------------------
-spec write_begin({Pid::pid(), Mod::atom()}, 
		  {Ix::integer(), Si::integer()}) ->
			{ok, Mref::reference(), Buf::term()} | 
			{ok, Buf::term()} |
			{error, Error::atom()}.

write_begin({Pid, Mod}, {_Ix, _Si} = I) ->
    case Mod:index_specification(Pid, I) of
	{spec, Spec} ->
	    if (Spec#index_spec.access band ?ACCESS_WO) =:= ?ACCESS_WO ->
		    lager:debug([{index, I}], 
			 "write_begin: transfer=~p, type = ~p",
			 [Spec#index_spec.transfer, Spec#index_spec.type]),
		    co_data_buf:init(write, Pid, Spec);
	       true ->
		    {error, ?abort_unsupported_access}
	    end;
	{error, Reason}  ->
	    {error, Reason}
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% Write
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_writing(LD, Reply) ->
    case co_data_buf:write(LD#loop_data.buf, LD#loop_data.data, true, segment) of
	{ok, Buf, Mref} when is_reference(Mref) ->
	    %% Called an application
	    {Reply, s_writing, LD#loop_data {mref = Mref, buf = Buf}};
	{ok, _Buf} ->
	    %% All data written
	    case Reply of
		ok ->
		    %% No state transition performed
		    ignore;
		next_state ->
		    %% Have passed through at least on state
		    {stop, normal, LD}
	    end;
	{error, Reason} ->
	    demonitor_and_abort(initial, LD, Reason)
    end.
 

%%--------------------------------------------------------------------
%% @doc
%% Initializing write for application stored data.<br/>
%% Expected events are:
%% <ul>
%% <li>{Mref, {ok, Ref, Size}}</li>
%% </ul>
%% Next state can be:
%% <ul>
%% <li> s_writing </li>
%% <li> stop </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec s_writing_started(M::term(), LD::#loop_data{}) -> 
			       {next_state, NextState::atom(), 
				NextLD::#loop_data{}} |
			       {next_state, NextState::atom(), 
				NextLD::#loop_data{}, 
				Tout::timeout()} |
			       {stop, Reason::atom(), NextS::#loop_data{}}.

s_writing_started({Mref, Reply} = _M, LD=#loop_data {index = I})  ->
    lager:debug([{index, I}], "s_writing_started: Got event = ~p", [_M]),
    case {LD#loop_data.mref, Reply} of
	{Mref, {ok, _Ref, _WriteSze}} ->
	    erlang:demonitor(Mref, [flush]),
	    {ok, Buf} = co_data_buf:update(LD#loop_data.buf, Reply),
	    start_writing(LD#loop_data {buf = Buf}, next_state);
	_Other ->
	    lager:debug([{index, I}], 
		 "s_writing_started: Got event = ~p, aborting", [_Other]),
	    demonitor_and_abort(s_writing_started, LD, ?abort_internal_error)
    end;
s_writing_started(timeout, LD) ->
    demonitor_and_abort(s_writing, LD, ?abort_timed_out);
s_writing_started(_M, LD=#loop_data {index = I})  ->
    lager:debug([{index, I}], 
		"s_writing_started: Got event = ~p, aborting", [_M]),
    demonitor_and_abort(s_writing_started, LD, ?abort_internal_error).



%%--------------------------------------------------------------------
%% @doc
%% Writing to application. <br/>
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
-spec s_writing(M::term(), LD::#loop_data{}) -> 
		       {next_state, NextState::atom(), NextLD::#loop_data{}} |
		       {next_state, NextState::atom(), NextLD::#loop_data{}, 
			Tout::timeout()} |
		       {stop, Reason::atom(), NextLD::#loop_data{}}.

s_writing({Mref, Reply} = _M, LD=#loop_data {index = I})  ->
    lager:debug([{index, I}], "s_writing: Got event = ~p", [_M]),
    case {LD#loop_data.mref, Reply} of
	{Mref, ok} ->
	    %% Atomic reply
	    erlang:demonitor(Mref, [flush]),
%%	    co_api:object_event(LD#loop_data.node_pid, 
%%				 {LD#loop_data.index, LD#loop_data.subind}),
	    {stop, normal, LD};
	{Mref, {ok, Ref}} when is_reference(Ref)->
	    %% Streamed reply
	    erlang:demonitor(Mref, [flush]),
%%	    co_api:object_event(LD#loop_data.node_pid, 
%%				 {LD#loop_data.index, LD#loop_data.subind}),
	    {stop, normal, LD};
	_Other ->
	    demonitor_and_abort(s_writing, LD, ?abort_internal_error)
    end;
s_writing(timeout, LD) ->
    demonitor_and_abort(s_writing, LD, ?abort_timed_out);
s_writing(_M, LD=#loop_data {index = I})  ->
    lager:debug([{index, I}], 
		"s_writing_segment: Got event = ~p, aborting", [_M]),
    demonitor_and_abort(s_writing, LD, ?abort_internal_error).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_all_state_event/2, this function is called to handle
%% the event.
%%
%% @spec handle_event(Event, State, LoopData) ->
%%                   {next_state, NextState, NextLoopData} |
%%                   {next_state, NextState, NextLoopData, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_event(Event, State, LD=#loop_data {index = I}) ->
    lager:debug([{index, I}], "handle_event: Got event ~p",[Event]),
    %% FIXME: handle abort here!!!
    apply(?MODULE, State, [Event, LD]).

%%--------------------------------------------------------------------
%% @private
%% @spec handle_sync_event(Event, From, State, LoopData) ->
%%                   {next_state, NextState, NextLoopData} |
%%                   {next_state, NextState, NextLoopData, Timeout} |
%%                   {reply, Reply, NextState, NextLoopData} |
%%                   {reply, Reply, NextState, NextLoopData, Timeout} |
%%                   {stop, Reason, NewLoopData} |
%%                   {stop, Reason, Reply, NewLoopData}
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_all_state_event/[2,3], this function is called
%% to handle the event.
%%
%% @end
%%--------------------------------------------------------------------
handle_sync_event(_Event, _From, State, LD=#loop_data {index = I}) ->
    lager:debug([{index, I}], "handle_sync_event: Got event ~p",[_Event]),
    Reply = ok,
    {reply, Reply, State, LD}.

%%--------------------------------------------------------------------
%% @doc
%% This function is called by a gen_fsm when it receives any
%% message other than a synchronous or asynchronous event
%% (or a system message).
%%
%% NOTE!!! This actually where all the replies from the application
%% are received. They are then normally sent on to the appropriate
%% state-function.
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info::term(), State::atom(), S::#loop_data{}) ->
			 {next_state, NextState::atom(), NextS::#loop_data{}} |
			 {next_state, NextState::atom(), NextS::#loop_data{}, Tout::timeout()} |
			 {stop, Reason::atom(), NewS::#loop_data{}}.
			 
handle_info({_Mref, ok} = Info, State, S) 
  when State =:= s_writing ->
    %% "Converting" info to event
    apply(?MODULE, State, [Info, S]);
handle_info({_Mref, {ok, Ref}} = Info, State, S) 
  when is_reference(Ref) andalso
	State =:= s_writing ->
    %% "Converting" info to event
    apply(?MODULE, State, [Info, S]);
handle_info({'DOWN',_Ref,process,_Pid,_Reason}, State, S) ->
    demonitor_and_abort(State, S, ?abort_internal_error);
handle_info(Info, State, S=#loop_data {index = I}) ->
    lager:debug([{index, I}], "handle_info: Got info ~p",[Info]),
    %% "Converting" info to event
    apply(?MODULE, State, [Info, S]).


%%--------------------------------------------------------------------
%% @private
%% @spec terminate(Reason, State, LoopData) -> void()
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State, _LoopData) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, LoopData, Extra) ->
%%                   {ok, State, NewLoopData}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, LoopData, _Extra) ->
    {ok, State, LoopData}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
demonitor_and_abort(_State, LD=#loop_data {index = I}, _Reason) ->
    case LD#loop_data.mref of
	Mref when is_reference(Mref)->
	    erlang:demonitor(Mref, [flush]);
	_NoRef ->
	    do_nothing
    end,
    lager:debug([{index, I}], 
		"Aborting in state = ~p, reason = ~p", [_State, _Reason]),
    {stop, normal, LD}.
    

