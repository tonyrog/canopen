%%% File    : co_test.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Protocol test
%%% Created : 13 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(co_test).

-compile(export_all).

run() ->
    can_router:start(),
    can_udp:start(0),
    {ok, Pid} = co_node:start(16#80030003, [{serial,16#03000301},{vendor,0}]),
    co_node:load_dict(Pid, filename:join(code:priv_dir(canopen), "test.dict")).

