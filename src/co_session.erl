%%%---- BEGIN COPYRIGHT --------------------------------------------------------
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
%%%---- END COPYRIGHT ----------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%  CANopen SDO session handling
%%% @end
%%% Created : 27 May 2010 by Tony Rogvall <tony@rogvall.se>

-module(co_session).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/sdo.hrl").
-include("../include/co_debug.hrl").

-compile(export_all).

local_timeout(S) ->
    BufTimeout = 
	if S#co_session.buf =/= undefined ->
		co_data_buf:timeout(S#co_session.buf);
	   true ->
		undefined
	end,
    if BufTimeout =/= undefined ->
	    BufTimeout;
       true ->
	    (S#co_session.ctx)#sdo_ctx.timeout
    end.

remote_timeout(S) ->
    (S#co_session.ctx)#sdo_ctx.timeout.

block_timeout(S) ->
    (S#co_session.ctx)#sdo_ctx.blk_timeout.

next_blksize(S) ->
    %% We may want to alter this ...
    (S#co_session.ctx)#sdo_ctx.max_blksize.

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

