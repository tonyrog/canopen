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
%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% Description : CCITT CRC 16 (initial=0)
%%%
%%% File    : co_crc.erl
%%%
%%% Created : 5 Feb 2008 by Tony Rogvall 
%%% @end
%%%-------------------------------------------------------------------
-module(co_crc).

-export([init/0]).
-export([final/1]).
-export([update/2]).
-export([checksum/1]).


%%--------------------------------------------------------------------
%% @doc
%% Initialize the CRC computation.
%%
%% @end
%%--------------------------------------------------------------------
-spec init() -> CRC::integer().
				  
init() -> 0.

%%--------------------------------------------------------------------
%% @doc
%% Finalize the CRC computation.
%%
%% @end
%%--------------------------------------------------------------------
-spec final(CRC::integer()) -> CRC::integer().

final(CRC) -> CRC.

%%--------------------------------------------------------------------
%% @doc
%% Updates the CRC checksum.
%%
%% @end
%%--------------------------------------------------------------------
-spec update(CRC::integer(), Data::term()) -> CRC::integer().

update(CRC, [H|T]) ->
    if is_integer(H) ->
	    update(update_byte(CRC,H), T);
       true ->
	    update(update(CRC, H), T)
    end;
update(CRC, []) -> CRC;
update(CRC, Value) when is_integer(Value) ->
    update_byte(CRC, Value);
update(CRC, Bin) when is_binary(Bin) ->
    update_bin(CRC, Bin).

update_bin(CRC, <<>>) ->
    CRC;
update_bin(CRC, <<Value:8,Bin/binary>>) ->
    update_bin(update_byte(CRC,Value), Bin).

-define(u8(X), ((X) band 16#ff)).
-define(u16(X), ((X) band 16#ffff)).

update_byte(CRC, Val) ->
    CRC0 = ?u8(CRC bsr 8) bor (CRC bsl 8),
    CRC1 = ?u16(CRC0 bxor Val),
    CRC2 = CRC1 bxor (?u8(CRC1) bsr 4),
    CRC3 = CRC2 bxor ?u16(?u16(CRC2 bsl 8) bsl 4),
    CRC3 bxor ?u16(?u16(?u8(CRC3) bsl 4) bsl 1).
	     
%%--------------------------------------------------------------------
%% @doc
%% Calculate CRC for Data.
%%
%% @end
%%--------------------------------------------------------------------
-spec checksum(Data::term()) -> CRC::integer().

checksum(Data) ->
    CRC0 = init(),
    CRC1 = update(CRC0, Data),
    final(CRC1).
