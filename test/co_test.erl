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
%%% File    : co_test.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Protocol test
%%% Created : 13 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(co_test).

-export([run/1, run/3, run/2, run/4, 
	 run_mgr/0, run_mgr/2, 
	 run_master/1, run_master/3,
	 run_slave/1, run_slave/3,
	 halt/1, 
	 halt_mgr/0, 
	 load/1]).

run(Serial) ->
    run(Serial, []).

run(Serial, Port, Ttl) ->
    run(Serial, Port, Ttl, []).

run(Serial, Opts) ->
    Dict = filename:join(code:priv_dir(canopen), "default.dict"),
    co_test_lib:start_system(),
    co_test_lib:start_node(Serial, Dict, Opts).

run(Serial, Port, Ttl, Opts) ->
    Dict = filename:join(code:priv_dir(canopen), "default.dict"),
    co_test_lib:start_system(Port, Ttl),
    co_test_lib:start_node(Serial, Dict, Opts).

halt(Serial) ->
    co_test_lib:stop_node(Serial),
    co_test_lib:stop_system().


run_mgr() ->
    run_mgr(1, 0).

run_mgr(Port, Ttl) ->
    can_udp:start(Port, [{ttl, Ttl}]),
    co_proc:start_link([{linked, false}]),
    co_mgr:start([{linked, false}, 
		  {debug, true}]).

halt_mgr() ->
    halt_mgr(1).

halt_mgr(Port) ->
    co_mgr:stop(),
    co_proc:stop(),
    can_udp:stop(Port),
    can_router:stop().

run_master(Serial) ->
    run_master(Serial, 2, 0).

run_master(Serial, Port, Ttl) ->
    run(Serial, Port, Ttl, [{nmt_role, master}, 
			    {supervision, node_guard}]),
    co_api:load_dict(Serial, 
		     "/Users/malotte/erlang/canopen/test/co_nmt_SUITE_data/test.dict"),
    co_nmt:debug(true).

run_slave(Serial) ->
    run(Serial, [{nmt_role, slave}, 
		 {supervision, node_guard}, 
		 {nodeid, co_lib:serial_to_nodeid(Serial)},
		 {debug, true}]).

run_slave(Serial, Port, Ttl) ->
    run(Serial, Port, Ttl, [{supervision, node_guard}]).

load(Serial) ->
    co_api:load_dict(Serial, "/Users/malotte/erlang/canopen/test/co_tpdo_SUITE_data/test.dict").
