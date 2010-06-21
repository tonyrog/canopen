%%
%% Can dump program
%%

-module(co_probe).
-export([start/0, init/0]).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/sdo.hrl").

-record(s,
	{
	  id,    %% {Tx, Rx}
	  block  %% undefined, upload, download
	}).

-record(state,
	{
	  session = []
	}).

start() ->
    can_udp:start(),  %% testing
    spawn_link(?MODULE, init, []).

init() ->
    can_router:attach(),
    loop(#state{}).

loop(S) ->
    receive
	Msg = #can_frame {} ->
	    S1 = print_message(S, Msg),
	    loop(S1);
	Other ->
	    io:format("other: ~p\n", [Other]),
	    ?MODULE:loop(S)
    end.

print_message(S, Msg) ->
    case Msg#can_frame.id of
	?NMT_ID ->
	    io:format("NMT: ~p\n", [Msg]),
	    S;
	?SYNC_ID ->
	    io:format("SYNC: ~p\n", [Msg]),
	    S;
	?TIME_STAMP_ID ->
	    io:format("TIME-STAMP: ~p\n", [Msg]),
	    S;
	MID ->
	    case ?FUNCTION_CODE(MID) of
		?NODE_GUARD ->
		    print_node_guard(Msg),
		    S;
		?LSS ->
		    io:format("LSS: ~p\n", [Msg]),
		    S;
		?EMERGENCY ->
		    io:format("EMERGENCY: ~p\n", [Msg]),
		    S;
		?PDO1_TX -> print_pdo_tx(Msg), S;
		?PDO2_TX -> print_pdo_tx(Msg), S;
		?PDO3_TX -> print_pdo_tx(Msg), S;
		?PDO4_TX -> print_pdo_tx(Msg), S;
		?PDO1_RX -> print_pdo_rx(Msg), S;
		?PDO2_RX -> print_pdo_rx(Msg), S;
		?PDO3_RX -> print_pdo_rx(Msg), S;
		?PDO4_RX -> print_pdo_rx(Msg), S;
		?SDO_TX ->
		    Tx = Msg#can_frame.id,
		    NodeId = ?NODE_ID(Tx),
		    Rx = ?COB_ID(?SDO_RX, NodeId),
		    ID = {Tx, Rx},  %% {ToClient,ToServer}
		    Session0 = S#state.session,
		    io:format("LOOKUP: id=~p\n", [ID]),
		    case lists:keytake(ID, #s.id, Session0) of
			false ->
			    case print_sdo_tx(Msg) of
				false -> S;
				Block ->
				    io:format("ADD: id=~p,block=~p\n", 
					      [ID, Block]),
				    E=#s{id=ID,block=Block},
				    Session2 = [E|Session0],
				    S#state{session=Session2}
			    end;
			{value,E,Session1} ->
			    case E#s.block of
				upload ->
				    case print_sdo_tx_block(Msg) of
					true ->
					    Session2 = 
						[E#s{block=false}|Session1],
					    S#state{session=Session2};
					false ->
					    S
				    end;
				_ ->
				    case print_sdo_tx(Msg) of
					false -> S;
					Block ->
					    io:format("ADD: id=~p,block=~p\n", 
						      [ID, Block]),
					    E1=E#s{block=Block},
					    Session2 = [E1|Session1],
					    S#state{session=Session2}
				    end
			    end
		    end;

		?SDO_RX ->
		    Rx = Msg#can_frame.id,
		    NodeId = ?NODE_ID(Rx),
		    Tx = ?COB_ID(?SDO_TX, NodeId),
		    ID = {Tx, Rx},  %% {ToClient,ToServer}
		    Session0 = S#state.session,
		    io:format("LOOKUP: id=~p\n", [ID]),
		    case lists:keytake(ID, #s.id, Session0) of
			false ->
			    case print_sdo_rx(Msg) of
				false -> 
				    S;
				Block ->
				    io:format("ADD: id=~p,block=~p\n", 
					      [ID, Block]),
				    E=#s{id=ID,block=Block},
				    Session2 = [E|Session0],
				    S#state{session=Session2}
			    end;
			{value,E,Session1} ->
			    case E#s.block of
				download ->
				    case print_sdo_rx_block(Msg) of
					true ->
					    Session2 = 
						[E#s{block=false}|Session1],
					    S#state{session=Session2};
					false ->
					    S
				    end;
				_ ->
				    case print_sdo_rx(Msg) of
					false -> S;
					Block ->
					    io:format("ADD: id=~p,block=~p\n", 
						      [ID, Block]),
					    E1=E#s{block=Block},
					    Session2 = [E1|Session1],
					    S#state{session=Session2}
				    end
			    end
		    end;
		_ ->
		    io:format("UNKNOWN: ~p\n", [Msg])
	    end
    end.


print_node_guard(Msg) ->    
    io:format("NODE-GUARD(~w): ~s: ~s\n", 
	      [?NODE_ID(Msg#can_frame.id),
	       co_format:message_id(Msg),
	       format_node_guard(Msg#can_frame.data)
	      ]).

%% fmt_verify_crc(Serial, Crc) ->
%%    case crc:checksum(<<Serial:32/little>>) of
%%	Crc -> "ok";
%%	_ -> "failed"
%%    end.


format_node_guard(Data) ->
    case Data of
	<<Toggle:1, State:7, _/binary>> ->
	    io_lib:format("state=~s, toggle=~w",
			  [co_format:state(State), Toggle])
    end.

print_sdo_tx_block(Msg) ->
    case Msg#can_frame.data of
	?ma_block_segment(Last,Seq,Data) ->
	    Pdu = #sdo_block_segment{last=Last,seqno=Seq,d=Data},
	    io:format("SDO_TX(~w): ~s: ~s\n", 
		      [?NODE_ID(Msg#can_frame.id), 
		       co_format:message_id(Msg),
		       co_format:format_sdo(Pdu)]),
	    Last =:= 1
    end.


print_sdo_tx(Msg) ->
    case catch co_sdo:decode_tx(Msg#can_frame.data) of
	{'EXIT', Reason} ->
	    io:format("SDO_TX(~w): ~s: decode-error: ~p, ~p\n", 
		      [?NODE_ID(Msg#can_frame.id), 
		       co_format:message_id(Msg),
		       Reason,Msg]);
	Pdu ->	    
	    io:format("SDO_TX(~w): ~s: ~s\n", 
		      [?NODE_ID(Msg#can_frame.id), 
		       co_format:message_id(Msg),
		       co_format:format_sdo(Pdu)]),
	    case Pdu of
		#sdo_scs_block_initiate_download_response{} ->
		    download;
		_ ->
		    false
	    end
    end.

print_sdo_rx_block(Msg) ->
    case Msg#can_frame.data of
	?ma_block_segment(Last,Seq,Data) ->
	    Pdu = #sdo_block_segment{last=Last,seqno=Seq,d=Data},
	    io:format("SDO_RX(~w): ~s: ~s\n", 
		      [?NODE_ID(Msg#can_frame.id), 
		       co_format:message_id(Msg),
		       co_format:format_sdo(Pdu)]),
	    Last =:= 1
    end.


print_sdo_rx(Msg) ->
    case catch co_sdo:decode_rx(Msg#can_frame.data) of
	{'EXIT', Reason} ->
	    io:format("SDO_RX(~w): ~s: decode-error: ~p, ~p\n", 
		      [?NODE_ID(Msg#can_frame.id), 
		       co_format:message_id(Msg),
		       Reason,Msg]);
	Pdu ->
	    io:format("SDO_RX(~w): ~s: ~s\n", 
		      [?NODE_ID(Msg#can_frame.id),
		       co_format:message_id(Msg),
		       co_format:format_sdo(Pdu)]),
	    case Pdu of
		#sdo_ccs_block_upload_start{} ->
		    upload;
		_ ->
		    false
	    end
    end.

print_pdo_tx(Msg) ->
    io:format("TPDO: ~s: ~p\n", 
	      [co_format:message_id(Msg), Msg#can_frame.data]).

print_pdo_rx(Msg) ->
    io:format("RPDO: ~s: ~p\n", 
	      [co_format:message_id(Msg), Msg#can_frame.data]).

	    
