%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2013, Rogvall Invest AB, <tony@rogvall.se>
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
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%% CANopen protocol stack.
%%%
%%% File: co_sdo.erl<br/>
%%% Created: 12 Jan 2009 by Tony Rogvall  
%%% @end
%%%-------------------------------------------------------------------
-module(co_sdo).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/sdo.hrl").

-export([decode_tx/1, decode_rx/1, encode/1]).
-export([decode_abort_code/1,encode_abort_code/1]).
-export([pad/2]).

-define(ENDIAN, little).

co_log(Fmt, As) ->
    ?ew(Fmt, As).

%% Decode SDO - client side
decode_tx(Bin) when is_binary(Bin) ->
    case Bin of
	?ma_scs_initiate_upload_response(N,E,S,Index,SubInd,Data) ->
	    #sdo_scs_initiate_upload_response { n=N,e=E,s=S,
						index=Index,subind=SubInd,
						d=Data };

	?ma_scs_initiate_download_response(Index,SubInd) ->
	    #sdo_scs_initiate_download_response { index=Index, subind=SubInd };

	?ma_scs_upload_segment_response(T,N,C,Data) ->
	    #sdo_scs_upload_segment_response { t=T, n=N, c=C, d=Data };

	?ma_scs_download_segment_response(T) ->
	    #sdo_scs_download_segment_response { t=T };

	%% ABORT
	?ma_scs_abort_transfer(Index,SubInd,Code) ->
	    Code1 = decode_abort_code(Code),
	    #sdo_abort { index=Index, subind=SubInd, code=Code1 };

	%% BLOCK DOWLOAD
	?ma_scs_block_initiate_download_response(SC,Index,SubInd,BlkSize) ->
	    #sdo_scs_block_initiate_download_response { sc=SC,
							index=Index,
							subind=SubInd,
							blksize=BlkSize};
	?ma_scs_block_download_end_response() ->
	    #sdo_scs_block_download_end_response {};

	?ma_scs_block_download_response(AckSeq,BlkSize) ->
	    #sdo_scs_block_download_response { ackseq=AckSeq, blksize=BlkSize};
	
	%% BLOCK UPLOAD

	?ma_scs_block_upload_response(SC,S,Index,SubInd,Size) ->
	    #sdo_scs_block_upload_response { sc=SC, s=S,
					     index=Index, subind=SubInd,
					     size=Size};
	
	?ma_scs_block_upload_end_request(N,Crc) ->
	    #sdo_scs_block_upload_end_request { n=N, crc=Crc }
    end.

%% Decode SDO receive
decode_rx(Bin) when is_binary(Bin) ->
    case Bin of
	?ma_ccs_initiate_download_request(N,E,S,Index,SubInd,Data) ->
	    #sdo_ccs_initiate_download_request { n = N, e = E, s = S,
						 index = Index, subind = SubInd,
						 d = Data };

	?ma_ccs_download_segment_request(T,N,C,Data) ->
	    #sdo_ccs_download_segment_request {  t = T,n = N, c = C, d = Data };

	?ma_ccs_upload_segment_request(T) ->
	    #sdo_ccs_upload_segment_request { t=T };

	?ma_ccs_initiate_upload_request(Index,SubInd) ->
	    #sdo_ccs_initiate_upload_request { index=Index, subind=SubInd  };

	%% ABORT
	?ma_ccs_abort_transfer(Index,SubInd,Code) ->
	    Code1 = decode_abort_code(Code),
	    #sdo_abort { index = Index, subind = SubInd, code=Code1 };

	%% BLOCK-UPLOAD
	?ma_ccs_block_upload_request(CC,Index,SubInd,BlkSize,Pst) ->
	    #sdo_ccs_block_upload_request { cc=CC,
					    index=Index, subind=SubInd,
					    blksize = BlkSize, pst=Pst };

	?ma_ccs_block_upload_end_response() ->
	    #sdo_ccs_block_upload_end_response {};

	?ma_ccs_block_upload_start() ->
	    #sdo_ccs_block_upload_start {};

	?ma_ccs_block_upload_response(AckSeq,BlkSize) ->
	    #sdo_ccs_block_upload_response { ackseq=AckSeq, blksize=BlkSize };

	%% BLOCK-DOWNLOAD

	?ma_ccs_block_download_request(CC,SizeInd,Index,SubInd,Size) ->
	    #sdo_ccs_block_download_request { cc=CC, s=SizeInd, 
					      index=Index, subind=SubInd,
					      size=Size };

	?ma_ccs_block_download_end_request(N,Crc) ->
	    #sdo_ccs_block_download_end_request { n=N, crc=Crc}
    end.

encode(SDO) ->
    case SDO of
	#sdo_block_segment { last=L, seqno=SeqNo, d=Data } ->
	    ?mk_block_segment(L,SeqNo,(pad(Data,7)));

	#sdo_scs_initiate_upload_response { n=N,e=E,s=S,index=IX,subind=SI,
					    d=D } ->
	    ?mk_scs_initiate_upload_response(N,E,S,IX,SI,(pad(D,4)));

	#sdo_scs_initiate_download_response { index=IX, subind=SI } ->
	    ?mk_scs_initiate_download_response(IX,SI);

	#sdo_scs_upload_segment_response { t=T, n=N, c=C, d=Data } ->
	    ?mk_scs_upload_segment_response(T,N,C,(pad(Data,7)));

	#sdo_ccs_download_segment_request { t=T, n=N, c=C, d=Data } ->
	    ?mk_ccs_download_segment_request(T,N,C,(pad(Data,7)));
	    
	#sdo_ccs_upload_segment_request { t=T } ->
	    ?mk_ccs_upload_segment_request(T);

	#sdo_scs_download_segment_response { t=T } ->
	    ?mk_scs_download_segment_response(T);

	#sdo_abort { index=IX, subind=SI, code=Code } ->
	    Code1 = encode_abort_code(Code),
	    ?mk_abort_transfer(IX,SI,Code1);
	
	#sdo_scs_block_initiate_download_response { sc=SC,
						    index=IX, subind=SI,
						    blksize=BlkSize} ->
	    ?mk_scs_block_initiate_download_response(SC,IX,SI,BlkSize);
	    
	#sdo_scs_block_download_end_response {} ->
	    ?mk_scs_block_download_end_response();

	#sdo_scs_block_download_response { ackseq=AckSeq, blksize=BlkSize} ->
	    ?mk_scs_block_download_response(AckSeq, BlkSize);
	    
	#sdo_scs_block_upload_response { sc=SC, s=S,index=IX, subind=SI,
					 size=Size} ->
	    ?mk_scs_block_upload_response(SC,S,IX,SI,Size);
	    
	#sdo_scs_block_upload_end_request { n=N, crc=Crc } ->
	    ?mk_scs_block_upload_end_request(N,Crc);

	#sdo_ccs_initiate_download_request { n = N, e = E, s = S,
					     index = IX, subind = SI,
					     d = Data } ->
	    ?mk_ccs_initiate_download_request(N,E,S,IX,SI,(pad(Data,4)));


	#sdo_ccs_initiate_upload_request { index=IX, subind=SI  } ->
	    ?mk_ccs_initiate_upload_request(IX,SI);

	#sdo_ccs_block_upload_request { cc=CC,index=IX, subind=SI,
					blksize=BlkSize, pst=Pst } ->
	    ?mk_ccs_block_upload_request(CC,IX,SI,BlkSize,Pst);
	    
	#sdo_ccs_block_upload_end_response {} ->
	    ?mk_ccs_block_upload_end_response();

	#sdo_ccs_block_upload_start {} ->
	    ?mk_ccs_block_upload_start();

	#sdo_ccs_block_upload_response { ackseq=AckSeq, blksize=BlkSize } ->
	    ?mk_ccs_block_upload_response(AckSeq, BlkSize);

	#sdo_ccs_block_download_request { cc=CC, s=S, index=IX, subind=SI,
					  size=Size } ->
	    ?mk_ccs_block_download_request(CC,S,IX,SI,Size);

	#sdo_ccs_block_download_end_request { n=N, crc=Crc} ->
	    ?mk_ccs_block_download_end_request(N,Crc)

    end.

pad(Bin,Size) ->
    Sz = byte_size(Bin),
    if Sz==Size -> Bin;
       Sz>Size ->
	    erlang:error(pad_error);
       Sz<Size ->
	    Pad = Size-Sz,
	    (<<Bin/binary, 0:Pad/unit:8>>)
    end.

decode_abort_code(Code) when is_atom(Code) ->
    Code;
decode_abort_code(Code) ->
    case Code of
	?ABORT_TOGGLE_NOT_ALTERNATED -> ?abort_toggle_not_alternated;
	?ABORT_TIMED_OUT -> ?abort_timed_out;
	?ABORT_COMMAND_SPECIFIER -> ?abort_command_specifier;
	?ABORT_INVALID_BLOCK_SIZE -> ?abort_invalid_block_size;
	?ABORT_INVALID_SEQUENCE_NUMBER -> ?abort_invalid_sequence_number;
	?ABORT_CRC_ERROR -> ?abort_crc_error;
	?ABORT_OUT_OF_MEMORY -> ?abort_out_of_memory;
	?ABORT_UNSUPPORTED_ACCESS -> ?abort_unsupported_access;
	?ABORT_READ_NOT_ALLOWED -> ?abort_read_not_allowed;
	?ABORT_WRITE_NOT_ALLOWED -> ?abort_write_not_allowed;
	?ABORT_NO_SUCH_OBJECT -> ?abort_no_such_object;
	?ABORT_NOT_MAPPABLE -> ?abort_not_mappable;
	?ABORT_BAD_MAPPING_SIZE -> ?abort_bad_mapping_size;
	?ABORT_PARAMETER_ERROR -> ?abort_parameter_error;
	?ABORT_INTERNAL_ERROR -> ?abort_internal_error;
	?ABORT_HARDWARE_FAILURE -> ?abort_hardware_failure;
	?ABORT_DATA_LENGTH_ERROR -> ?abort_data_length_error;
	?ABORT_DATA_LENGTH_TOO_HIGH -> ?abort_data_length_too_high;
	?ABORT_DATA_LENGTH_TOO_LOW -> ?abort_data_length_too_low;
	?ABORT_NO_SUCH_SUBINDEX -> ?abort_no_such_subindex;
	?ABORT_VALUE_RANGE_EXCEEDED -> ?abort_value_range_exceeded;
	?ABORT_VALUE_TOO_LOW -> ?abort_value_too_low;
	?ABORT_VALUE_TOO_HIGH -> ?abort_value_too_high;
	?ABORT_VALUE_RANGE_ERROR -> ?abort_value_range_error;
	?ABORT_GENERAL_ERROR -> ?abort_general_error;
	?ABORT_LOCAL_DATA_ERROR -> ?abort_local_data_error;
	?ABORT_LOCAL_CONTROL_ERROR -> ?abort_local_control_error;
	?ABORT_LOCAL_STATE_ERROR -> ?abort_local_state_error;
	?ABORT_DICTIONARY_ERROR -> ?abort_dictionary_error;
	_AppAbortCode -> Code
    end.
    
encode_abort_code(Code) when is_integer(Code) ->
    Code;
encode_abort_code(Code) ->
    case Code of
	?abort_toggle_not_alternated -> ?ABORT_TOGGLE_NOT_ALTERNATED;
	?abort_timed_out -> ?ABORT_TIMED_OUT;
	?abort_command_specifier -> ?ABORT_COMMAND_SPECIFIER;
	?abort_invalid_block_size -> ?ABORT_INVALID_BLOCK_SIZE;
	?abort_invalid_sequence_number -> ?ABORT_INVALID_SEQUENCE_NUMBER;
	?abort_crc_error -> ?ABORT_CRC_ERROR;
	?abort_out_of_memory -> ?ABORT_OUT_OF_MEMORY;
	?abort_unsupported_access -> ?ABORT_UNSUPPORTED_ACCESS;
	?abort_read_not_allowed -> ?ABORT_READ_NOT_ALLOWED;
	?abort_write_not_allowed -> ?ABORT_WRITE_NOT_ALLOWED;
	?abort_no_such_object -> ?ABORT_NO_SUCH_OBJECT;
	?abort_not_mappable -> ?ABORT_NOT_MAPPABLE;
	?abort_bad_mapping_size -> ?ABORT_BAD_MAPPING_SIZE;
	?abort_parameter_error -> ?ABORT_PARAMETER_ERROR;
	?abort_internal_error -> ?ABORT_INTERNAL_ERROR;
	?abort_hardware_failure -> ?ABORT_HARDWARE_FAILURE;
	?abort_data_length_error -> ?ABORT_DATA_LENGTH_ERROR;
	?abort_data_length_too_high -> ?ABORT_DATA_LENGTH_TOO_HIGH;
	?abort_data_length_too_low -> ?ABORT_DATA_LENGTH_TOO_LOW;
	?abort_no_such_subindex -> ?ABORT_NO_SUCH_SUBINDEX;
	?abort_value_range_exceeded -> ?ABORT_VALUE_RANGE_EXCEEDED;
	?abort_value_too_low -> ?ABORT_VALUE_TOO_LOW;
	?abort_value_too_high -> ?ABORT_VALUE_TOO_HIGH;
	?abort_value_range_error -> ?ABORT_VALUE_RANGE_ERROR;
	?abort_general_error -> ?ABORT_GENERAL_ERROR;
	?abort_local_data_error -> ?ABORT_LOCAL_DATA_ERROR;
	?abort_local_control_error -> ?ABORT_LOCAL_CONTROL_ERROR;
	?abort_local_state_error -> ?ABORT_LOCAL_STATE_ERROR;
	?abort_dictionary_error -> ?ABORT_DICTIONARY_ERROR;
	_ ->
	    co_log("~p: abort code ~p not defined\n", [self(),Code]),
	    ?ABORT_INTERNAL_ERROR
    end.




