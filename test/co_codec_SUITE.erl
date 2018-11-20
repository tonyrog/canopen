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
%%% @copyright (C) 2018, Tony Rogvall
%%% @doc
%%%  encoding text
%%% @end
%%%-------------------------------------------------------------------
-module(co_codec_SUITE).
-compile(export_all).

-include("../include/canopen.hrl").

suite() ->
    [].

all() -> 
    [test0,
     test1,
     test2,
     test_nmea
    ].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

test0(_Config) ->
    T = [{integer,10},{unsigned,5}],
    Bits = co_codec:encode([-423, 30], T),
    [-423,30] = co_codec:decode(Bits,T),
    ok.

test1(_Config) ->
    T = [{unsigned,1},{unsigned,2},{unsigned,3},{unsigned,4},{unsigned,5},
	 {unsigned,6},{unsigned,7},{unsigned,8},{unsigned,9},{unsigned,10}],
    Bin = co_codec:encode([1,2,3,4,5,6,7,8,9,10], T),
    [1,2,3,4,5,6,7,8,9,10] = co_code:decode(Bin, T),
    ok.

test2(_Config) ->
    T = [{integer,1},{integer,2},{integer,3},{integer,4},{integer,5},
	 {integer,6},{integer,7},{integer,8},{integer,9},{integer,10}],
    Bin = co_codec:encode([0,-1,2,-3,4,-5,6,-7,8,-9], T),
    [-1,2,-3,4,-5,6,-7,8,-9,10] = co_codec:decode(Bin, T),
    ok.

test_nmea(_Config) ->
    case co_codec:decode(<<0,156,49,255,255,255,255,255>>,
			     [{unsigned,4},{unsigned,4},
			      {unsigned,16},{unsigned,32}]) of
	[Instance,Type,Level,Capacity] ->
	    {fluidLevel,[{instance,Instance},{type,Type},
			 {level,Level},{capacity,Capacity}]}
    end.
