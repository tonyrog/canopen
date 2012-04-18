%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% CAN dump program.
%%%
%%% File: co_probe.erl<br/>
%%% @end
%%%-------------------------------------------------------------------
-module(co_probe).
-export([start/0, init/0]).

-include_lib("can/include/can.hrl").
-include("canopen.hrl").
-include("sdo.hrl").

%% @private
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

print_message(S, Frame) ->
    if ?is_can_frame_eff(Frame) ->
	    CobId   = Frame#can_frame.id band ?CAN_EFF_MASK,
	    Func = ?XFUNCTION_CODE(CobId),
	    NodeId = ?XNODE_ID(CobId),
	    print_message(S,true,Func,CobId,NodeId,Frame);
       true ->
	    CobId = Frame#can_frame.id band ?CAN_SFF_MASK,
	    Func = ?FUNCTION_CODE(CobId),
	    NodeId  = ?NODE_ID(CobId),
	    print_message(S,false,Func,CobId,NodeId,Frame)
    end.

print_message(S,Ext,Func,CobId,NodeId,Frame) ->
    case CobId of
	?NMT_ID ->
	    io:format("NMT: ~p\n", [Frame]),
	    S;
	?SYNC_ID ->
	    io:format("SYNC: ~p\n", [Frame]),
	    S;
	?TIME_STAMP_ID ->
	    io:format("TIME-STAMP: ~p\n", [Frame]),
	    S;
	_ ->
	    case Func of
		?NODE_GUARD ->
		    print_node_guard(Frame),
		    S;
		?LSS ->
		    io:format("LSS: ~p\n", [Frame]),
		    S;
		?EMERGENCY ->
		    io:format("EMERGENCY: ~p\n", [Frame]),
		    S;
		?PDO1_TX -> print_pdo_tx(Frame), S;
		?PDO2_TX -> print_pdo_tx(Frame), S;
		?PDO3_TX -> print_pdo_tx(Frame), S;
		?PDO4_TX -> print_pdo_tx(Frame), S;
		?PDO1_RX -> print_pdo_rx(Frame), S;
		?PDO2_RX -> print_pdo_rx(Frame), S;
		?PDO3_RX -> print_pdo_rx(Frame), S;
		?PDO4_RX -> print_pdo_rx(Frame), S;
		?SDO_TX ->
		    Tx = Frame#can_frame.id band ?CAN_EFF_MASK,
		    Rx = if Ext ->
				 ?XCOB_ID(?SDO_RX, NodeId);
			    true ->
				 ?COB_ID(?SDO_RX, NodeId)
			 end,
		    ID = {Tx, Rx},  %% {ToClient,ToServer}
		    Session0 = S#state.session,
		    io:format("LOOKUP: id=~p\n", [ID]),
		    case lists:keytake(ID, #s.id, Session0) of
			false ->
			    case print_sdo_tx(Frame) of
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
				    case print_sdo_tx_block(Frame) of
					true ->
					    Session2 = 
						[E#s{block=false}|Session1],
					    S#state{session=Session2};
					false ->
					    S
				    end;
				_ ->
				    case print_sdo_tx(Frame) of
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
		    Rx = Frame#can_frame.id band ?CAN_EFF_MASK,
		    Tx = if Ext ->
				 ?XCOB_ID(?SDO_TX, NodeId);
			    true ->
				 ?COB_ID(?SDO_TX, NodeId)
			 end,
		    ID = {Tx, Rx},  %% {ToClient,ToServer}
		    Session0 = S#state.session,
		    io:format("LOOKUP: id=~p\n", [ID]),
		    case lists:keytake(ID, #s.id, Session0) of
			false ->
			    case print_sdo_rx(Frame) of
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
				    case print_sdo_rx_block(Frame) of
					true ->
					    Session2 = 
						[E#s{block=false}|Session1],
					    S#state{session=Session2};
					false ->
					    S
				    end;
				_ ->
				    case print_sdo_rx(Frame) of
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
		    io:format("~s\n", [can_probe:format_frame(Frame)]),
		    S
	    end
    end.


print_node_guard(Frame) ->    
    io:format("NODE-GUARD(~s): ~s: ~s\n", 
	      [co_format:node_id(Frame),
	       co_format:message_id(Frame),
	       format_node_guard(Frame#can_frame.data)
	      ]).

%% fmt_verify_crc(Serial, Crc) ->
%%    case co_crc:checksum(<<Serial:32/little>>) of
%%	Crc -> "ok";
%%	_ -> "failed"
%%    end.


format_node_guard(Data) ->
    case Data of
	<<Toggle:1, State:7, _/binary>> ->
	    io_lib:format("state=~s, toggle=~w",
			  [co_format:state(State), Toggle])
    end.

print_sdo_tx_block(Frame) ->
    case Frame#can_frame.data of
	?ma_block_segment(Last,Seq,Data) ->
	    Pdu = #sdo_block_segment{last=Last,seqno=Seq,d=Data},
	    io:format("SDO_TX(~s): ~s: ~s\n", 
		      [co_format:node_id(Frame), 
		       co_format:message_id(Frame),
		       co_format:format_sdo(Pdu)]),
	    Last =:= 1
    end.


print_sdo_tx(Frame) ->
    case catch co_sdo:decode_tx(Frame#can_frame.data) of
	{'EXIT', Reason} ->
	    io:format("SDO_TX(~s): ~s: decode-error: ~p, ~p\n", 
		      [co_format:node_id(Frame), 
		       co_format:message_id(Frame),
		       Reason,Frame]);
	Pdu ->	    
	    io:format("SDO_TX(~s): ~s: ~s\n", 
		      [co_format:node_id(Frame), 
		       co_format:message_id(Frame),
		       co_format:format_sdo(Pdu)]),
	    case Pdu of
		#sdo_scs_block_initiate_download_response{} ->
		    download;
		_ ->
		    false
	    end
    end.

print_sdo_rx_block(Frame) ->
    case Frame#can_frame.data of
	?ma_block_segment(Last,Seq,Data) ->
	    Pdu = #sdo_block_segment{last=Last,seqno=Seq,d=Data},
	    io:format("SDO_RX(~s): ~s: ~s\n", 
		      [co_format:node_id(Frame), 
		       co_format:message_id(Frame),
		       co_format:format_sdo(Pdu)]),
	    Last =:= 1
    end.


print_sdo_rx(Frame) ->
    case catch co_sdo:decode_rx(Frame#can_frame.data) of
	{'EXIT', Reason} ->
	    io:format("SDO_RX(~s): ~s: decode-error: ~p, ~p\n", 
		      [co_format:node_id(Frame), 
		       co_format:message_id(Frame),
		       Reason,Frame]);
	Pdu ->
	    io:format("SDO_RX(~s): ~s: ~s\n", 
		      [co_format:node_id(Frame), 
		       co_format:message_id(Frame),
		       co_format:format_sdo(Pdu)]),
	    case Pdu of
		#sdo_ccs_block_upload_start{} ->
		    upload;
		_ ->
		    false
	    end
    end.

print_pdo_tx(Frame) ->
    io:format("TPDO: ~s: ~p\n", 
	      [co_format:message_id(Frame), Frame#can_frame.data]).

print_pdo_rx(Frame) ->
    io:format("RPDO: ~s: ~p\n", 
	      [co_format:message_id(Frame), Frame#can_frame.data]).

	    
