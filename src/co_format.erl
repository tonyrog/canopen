%%% File    : co_format.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Formatting
%%% Created : 13 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(co_format).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/sdo.hrl").

-compile(export_all).

state(State) ->	    
    case State of
	?Initialisation -> "initialisation";
	?Stopped        -> "stopped";
	?Operational    -> "operational";
	?PreOperational -> "preoperational";
	?UnknownState   -> "unknown";
	_ -> io_lib:format("~w", [State])
    end.
	    
message_id(Frame) when ?is_can_frame_eff(Frame) ->
    io_lib:format("~8.16.0B", [Frame#can_frame.id band ?CAN_EFF_MASK]);
message_id(Frame) ->
    io_lib:format("~3.16.0B", [Frame#can_frame.id band ?CAN_SFF_MASK]).

node_id(Frame) when ?is_can_frame_eff(Frame) ->
    io_lib:format("~8.16.0B", [?XNODE_ID(Frame#can_frame.id)]);
node_id(Frame) ->
    io_lib:format("~3.16.0B", [?NODE_ID(Frame#can_frame.id)]).

format_record(R, Fields) ->
    ["#",atom_to_list(element(1, R)),"{",
     format_fields(R, 2, Fields), "}"].

format_fields(_R, _I, []) ->
    [];
format_fields(R, I, [F]) ->
    format_field(R,I,F);
format_fields(R, I, [F|Fs]) ->
    [format_field(R,I,F), "," | format_fields(R,I+1,Fs)].

%% some special cases
format_field(R, I, index) ->
    ["index=", io_lib:format("16#~4.16.0B", [element(I,R)])];
format_field(R, I, subind) ->
    ["subind=", io_lib:format("16#~2.16.0B", [element(I,R)])];
%% General case
format_field(R, I, F) ->
    [atom_to_list(F), "=", io_lib:format("~p", [element(I,R)])].


-define(FREC(R,Rn),
	#Rn{} -> format_record(R,record_info(fields,Rn))).

format_sdo(R) ->
    case R of
	?FREC(R,sdo_scs_initiate_upload_response);
	?FREC(R,sdo_scs_initiate_download_response);
	?FREC(R,sdo_scs_upload_segment_response);
	?FREC(R,sdo_scs_block_initiate_download_response);
	?FREC(R,sdo_scs_block_download_end_response);
	?FREC(R,sdo_scs_block_download_response);
	?FREC(R,sdo_scs_block_upload_response);
	?FREC(R,sdo_scs_block_upload_end_request);

	?FREC(R,sdo_ccs_download_segment_request);
	?FREC(R,sdo_ccs_upload_segment_request);
	?FREC(R,sdo_ccs_initiate_download_request);
	?FREC(R,sdo_ccs_initiate_upload_request);
	?FREC(R,sdo_ccs_block_upload_request);
	?FREC(R,sdo_ccs_block_upload_end_response);
	?FREC(R,sdo_ccs_block_upload_start);
	?FREC(R,sdo_ccs_block_upload_response);
	?FREC(R,sdo_ccs_block_download_request);
	?FREC(R,sdo_ccs_block_download_end_request);

	?FREC(R,sdo_block_segment);
	?FREC(R,sdo_scs_download_segment_response);
        ?FREC(R,sdo_abort);
	_ ->
	    io_lib:format("~p", [R])
    end.
		

    
     


