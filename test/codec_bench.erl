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
%%% File    : codec_bench.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Bench mark codec implementation
%%% Created : 10 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(codec_bench).

-include("../include/canopen.hrl").
-compile(export_all).

-define(T1(M), M:encode([1,100,10],[{?INTEGER,2},{?INTEGER,10},{?INTEGER,4}])).
-define(T2(M), M:encode([0,0, 0,1, 0,2, 0,3,
			 1,0, 1,1, 1,2, 1,3],
			[{?INTEGER,2},{?INTEGER,2},
			 {?INTEGER,2},{?INTEGER,2},
			 {?INTEGER,2},{?INTEGER,2},
			 {?INTEGER,2},{?INTEGER,2},
			 {?INTEGER,2},{?INTEGER,2},
			 {?INTEGER,2},{?INTEGER,2},
			 {?INTEGER,2},{?INTEGER,2},
			 {?INTEGER,2},{?INTEGER,2}])).

verify() ->
    Ts1 = [{integer,10},{unsigned,5}],
    <<16#59,16#7A>> = co_codec:encode([-423, 30], Ts1),
    {[-423,30],_} = co_codec:decode(<<16#59,16#7A>>,Ts1),
    <<101,160>> = ?T1(co_codec),
    <<64,200,81,217>> = ?T2(co_codec),
    ok.


a1(0) ->  ok;
a1(N) ->  ?T1(co_codec), a1(N-1).

a2(0) -> ok;
a2(N) -> ?T2(co_codec), a2(N-1).

%%d2(_D,0) -> ok;
%%d2(D,N) -> co_api:tpdo_pack(0, D), d2(D,N-1).

dict() ->
    {ok,D} = co_dict:from_file("bench.dict"),
    co_dict:set_value(D, {16#2500,1}, 1),
    co_dict:set_value(D, {16#2500,2}, 2),
    co_dict:set_value(D, {16#2500,3}, 3),
    co_dict:set_value(D, {16#2500,4}, 0),
    co_dict:set_value(D, {16#2500,5}, 1),
    co_dict:set_value(D, {16#2500,6}, 2),
    co_dict:set_value(D, {16#2500,7}, 3),
    co_dict:set_value(D, {16#2500,8}, 0),
    co_dict:set_value(D, {16#2501,1}, 3),
    co_dict:set_value(D, {16#2501,2}, 2),
    co_dict:set_value(D, {16#2501,3}, 3),
    co_dict:set_value(D, {16#2501,4}, 2),
    co_dict:set_value(D, {16#2501,5}, 3),
    co_dict:set_value(D, {16#2501,6}, 2),
    co_dict:set_value(D, {16#2501,7}, 3),
    co_dict:set_value(D, {16#2501,8}, 2),
    D.
