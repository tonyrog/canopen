%%% File    : co_test.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Protocol test
%%% Created : 13 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(co_test).

-export([run/0]).

run() ->
    {ok, _Pid} = co_node:start([{serial,16#03000301}, 
			       {options, [extended, {vendor,0}]}]).

