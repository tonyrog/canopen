%%% File    : co_test.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Protocol test
%%% Created : 13 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(co_test).

-export([run/1]).

run(Serial) ->
    {ok, _Pid} = co_node:start_link([{serial,Serial}, 
				     {options, [extended,
						{max_blksize, 7},
						{vendor,16#2A1},
						{dict_file, "test.dict"},
						{debug, true}]}]).

