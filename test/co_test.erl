%%% File    : co_test.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Protocol test
%%% Created : 13 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(co_test).

-export([run/1, halt/1]).

run(Serial) ->
    {ok, _PPid} = co_proc:start_link([]),
    {ok, _NPid} = co_node:start_link([{serial,Serial}, 
				      {options, [{use_serial_as_nodeid, true},
						 {short_nodeid, 7},
						 {max_blksize, 7},
						 {vendor,16#2A1},
						 {debug, true}]}]),
    
    co_node:load_dict(Serial, filename:join(code:priv_dir(canopen), "default.dict")).


halt(Serial) ->
    co_node:stop(Serial),
    co_proc:stop().
