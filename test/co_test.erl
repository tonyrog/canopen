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
    can_udp:start(co_test, Port, [{ttl, Ttl}]),
    co_proc:start_link([{linked, false}]),
    co_mgr:start([{linked, false}, 
		  {debug, true}]).

halt_mgr() ->
    co_mgr:stop(),
    co_proc:stop(),
    can_udp:stop(co_test),
    can_router:stop().

run_master(Serial) ->
    run_master(Serial, 2, 0).

run_master(Serial, Port, Ttl) ->
    run(Serial, Port, Ttl, [{nmt_role, master}, 
			    {supervision, node_guard}]),
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
