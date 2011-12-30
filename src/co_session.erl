%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%  CANopen SDO session handling
%%% @end
%%% Created : 27 May 2010 by Tony Rogvall <tony@rogvall.se>

-module(co_session).

-include_lib("can/include/can.hrl").
-include("canopen.hrl").
-include("sdo.hrl").
-include("co_debug.hrl").

-compile(export_all).

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
    Dst = S#co_session.dst,
    ID = if ?is_cobid_extended(Dst) ->
		 (Dst band ?CAN_EFF_MASK) bor ?CAN_EFF_FLAG;
	    true ->
		 (Dst band ?CAN_SFF_MASK)
	 end,
    %% send message as it where sent from the node process
    %% this inhibits the message to be delivered to the node process
    can:send_from(S#co_session.node_pid,ID,8,Data).

