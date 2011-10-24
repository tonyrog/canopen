%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%    SDO PDU test module
%%% @end
%%% Created :  3 Jun 2010 by Tony Rogvall <tony@rogvall.se>

-module(co_sdo_test).

-include_lib("can/include/can.hrl").
-include_lib("canopen/include/canopen.hrl").
-include("../include/sdo.hrl").

-compile(export_all).

verify_tx() ->
    check_tx(#sdo_scs_initiate_upload_response { n=2,e=1,s=1,
						 index=1000,subind=7,
						 d= <<1,2,3,4>> }),
    check_tx(#sdo_scs_initiate_upload_response { n=2,e=0,s=1,
						 index=1000,subind=7,
						 d= <<1000:32/little>>}),
    check_tx(#sdo_scs_initiate_download_response { index=1000, subind=7 }),
    check_tx(#sdo_scs_upload_segment_response { t=1, n=2, c=1, d= <<1,2,3,4,5,6,7>> }),
    check_tx(#sdo_scs_download_segment_response { t=1 }),
    check_tx(#sdo_abort { index=1000, subind=7, code=?abort_internal_error }),
    check_tx(#sdo_scs_block_initiate_download_response { sc=1,
							 index=1000,
							 subind=7,
							 blksize=123}),
    check_tx(#sdo_scs_block_download_end_response{}),
    check_tx(#sdo_scs_block_download_response { ackseq=8, blksize=123}),
    
    check_tx(#sdo_scs_block_upload_response { sc=1, s=1,
					      index=1000, subind=7,
					      size=100000 }),
    check_tx(#sdo_scs_block_upload_end_request { n=1, crc=1234 }),
    ok.

verify_rx() ->
    check_rx(#sdo_ccs_initiate_download_request { n = 2, e=1, s=1,
						  index=1000, subind=7,
						  d = <<1,2,3,4>> }),
    check_rx(#sdo_ccs_initiate_download_request { n = 2, e=0, s=1,
						  index=1000, subind=7,
						  d = <<1000:32/little>> }),
    check_rx(#sdo_ccs_download_segment_request {  t=1,n=1,c=1, 
						  d= <<1,2,3,4,5,6,7>>}),
    check_rx(#sdo_ccs_upload_segment_request { t=1 }),
    check_rx(#sdo_ccs_initiate_upload_request { index=1000, subind=7 }),
    check_rx(#sdo_abort { index=1000, subind=7, code=?abort_internal_error }),
    check_rx(#sdo_ccs_block_upload_request { cc=1,index=1000, subind=7,
					     blksize=80, pst=50 }),
    check_rx(#sdo_ccs_block_upload_end_response {}),    
    check_rx(#sdo_ccs_block_upload_start {}),
    check_rx(#sdo_ccs_block_upload_response { ackseq=9, blksize=134 }),
    check_rx(#sdo_ccs_block_download_request { cc=1, s=1, 
					      index=1000, subind=7,
					       size=1234 }),
    check_rx(#sdo_ccs_block_download_end_request { n=1, crc=1234}),
    ok.
    

check_tx(PDU) ->
    io:format("Checking ~p\n", [PDU]),
    Data = co_sdo:encode(PDU),
    case co_sdo:decode_tx(Data) of
	PDU -> ok
    end.

check_rx(PDU) ->
    io:format("Checking ~p\n", [PDU]),
    Data = co_sdo:encode(PDU),
    case co_sdo:decode_rx(Data) of
	PDU -> ok
    end.

	     

