%%% File    : co_test.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Protocol test
%%% Created : 13 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(co_test).

-export([run/1, halt/1]).

run(Serial) ->
    Dict = filename:join(code:priv_dir(canopen), "default.dict"),
    co_test_lib:start_node(Serial, Dict).

halt(Serial) ->
    co_node:stop(Serial),
    co_proc:stop().
