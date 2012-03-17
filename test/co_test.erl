%%% File    : co_test.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Protocol test
%%% Created : 13 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(co_test).

-export([run/1, run/2, halt/1]).

run(Serial) ->
    Dict = filename:join(code:priv_dir(canopen), "default.dict"),
    co_test_lib:start_node(Serial, Dict).

run(Serial, Port) ->
    Dict = filename:join(code:priv_dir(canopen), "default.dict"),
    co_test_lib:start_node(Serial, Dict, Port).

halt(Serial) ->
    co_test_lib:stop_node(Serial).
