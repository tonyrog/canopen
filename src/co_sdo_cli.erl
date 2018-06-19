%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2018, Tony Rogvall
%%% @doc
%%%    expedited mode set/download and get/upload
%%% @end
%%% Created : 16 Jun 2018 by Tony Rogvall <tony@rogvall.se>

-module(co_sdo_cli).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/sdo.hrl").
-include("../include/co_app.hrl").

-export([get/4, set/5, set_batch/2]).
-export([attach/1]).

-export([send_sdo_set/4, send_sdo_get/3]).
-export([sdo_recv/3]).

%% -define(dbg(F,A), io:format((F),(A))).
-define(dbg(F,A), ok).
-define(warn(F,A), io:format((F),(A))).
-define(error(F,A), io:format((F),(A))).

get(Nid,Index,SubInd,Timeout) ->
    send_sdo_get(Nid, Index, SubInd),
    sdo_recv(Nid, {get,Index,SubInd}, Timeout).

set(Nid,Index,SubInd,Value,Timeout) ->
    send_sdo_set(Nid, Index, SubInd, Value),
    sdo_recv(Nid, {set,Index,SubInd}, Timeout).

%% set multiple commands using pipelining (when possible)
set_batch(Batch,Timeout) ->
    L = expand_batch(Batch),
    set_batch_(L,[],Timeout).

set_batch_([{Nid,Index,SubInd,Value}|L],Err,Timeout) ->
    case set(Nid,Index,SubInd,Value,Timeout) of
	ok ->
	    set_batch_(L,Err,Timeout);
	{error,Reason} ->
	    set_batch_(L,[{error,{Index,SubInd,Reason}}|Err],Timeout)
    end;
set_batch_([],[],_Timeout) ->
    ok;
set_batch_([],Err,_Timeout) ->
    {error,lists:reverse(Err)}.


%% attach caller to can_router with filter for SDO_TX only
attach(Nid) ->
    SdoCanId = sdo_tx_canid(Nid),
    SdoCanMask = sdo_tx_canmask(Nid),
    can_router:attach([{false,SdoCanId,SdoCanMask}]).

%% generate a request to read node values
send_sdo_get(Nid, Index, SubInd) ->
    SdoCanId = sdo_rx_canid(Nid),
    send_sdo_rx_get(SdoCanId, Index, SubInd).

%% generate a request to read node values
send_sdo_rx_get(SdoCanId, Index, SubInd) ->
    Bin = ?sdo_ccs_initiate_upload_request(0,Index,SubInd,0),
    Frame = #can_frame { id=SdoCanId,len=8,data=Bin },
    can:send(Frame).
	
%% generate a request to read node values
send_sdo_set(Nid, Index, SubInd, Value) when is_integer(Value) ->
    send_sdo_set_(Nid, Index, SubInd,<<Value:32/little>>);
send_sdo_set(Nid, Index, SubInd, Value) when is_binary(Value) ->
    send_sdo_set_(Nid, Index, SubInd,Value).

send_sdo_set_(Nid, Index, SubInd, Data) ->
    SdoCanId = sdo_rx_canid(Nid),
    send_sdo_rx_set(SdoCanId, Index, SubInd, Data).

send_sdo_rx_set(SdoCanId, Index, SubInd, Data) ->
    N = 4-size(Data),
    Data1 = case N of
		0 -> Data;
		1 -> <<Data/binary,0>>;
		2 -> <<Data/binary,0,0>>;
		3 -> <<Data/binary,0,0,0>>
	    end,
    Bin = ?sdo_ccs_initiate_download_request(0,N,1,1,Index,SubInd,Data1),
    Frame = #can_frame { id=SdoCanId,len=8,data=Bin},
    can:send(Frame).

sdo_recv(Nid,Request,Timeout) ->
    SdoCanId = sdo_tx_canid(Nid),
    sdo_recv_(SdoCanId,Request,Timeout).
    
sdo_recv_(SdoCanId,Req={Op,Index,SubInd},Timeout) ->
    receive
	#can_frame { id=CanId, data=Bin } when CanId =:= SdoCanId ->
	    case sdo_reply_(Bin) of
		{Op,Index,SubInd} -> 
		    ok;
		{Op,Index,SubInd,Value} -> 
		    {ok,Value};
		{error,Index,SubInd,Code} ->
		    {error, co_sdo:decode_abort_code(Code)};
		_ -> sdo_recv_(SdoCanId,Req,Timeout)
	    end
    after Timeout ->
	    {error, timeout}
    end.

sdo_reply_(Bin) ->
    case Bin of
	?ma_scs_initiate_download_response(Index,SubInd) ->
	    ?dbg("sdo_tx: SET RESP index=~w, si=~w\n",
		 [Index,SubInd]),
	    {set,Index,SubInd};
	?ma_scs_initiate_upload_response(N,E,S,Index,SubInd,Data) when E =:= 1 ->
	    Value = sdo_value(S,N,Data),
	    ?dbg("sdo_tx: GET RESP index=~w, si=~w, value=~w\n", 
		 [Index,SubInd,Value]),
	    {get,Index,SubInd,Value};

	?ma_abort_transfer(Index,SubInd,Code) ->
	    ?dbg("sdo_tx: ABORT index=~w, si=~w, code=~w\n",
		 [Index,SubInd,Code]),
	    {error,Index,SubInd,Code};
	_ ->
	    ?warn("sdo_tx: only  expedited mode supported\n", []),
	    false
    end.


sdo_value(0,_N,_Bin) -> <<>>;
sdo_value(1,0,<<Value:32/little>>) -> Value;
sdo_value(1,1,<<Value:24/little,_:8>>) -> Value;
sdo_value(1,2,<<Value:16/little,_:16>>) -> Value;
sdo_value(1,3,<<Value:8/little,_:24>>) -> Value.

sdo_rx_cobid(Nid) ->
    case ?is_cobid_extended(Nid) orelse (Nid > 127) of
	true ->
	    NodeId = ?XNODE_ID(Nid),
	    ?XCOB_ID(?SDO_RX,NodeId);
	false ->
	    NodeId = ?NODE_ID(Nid),
	    ?COB_ID(?SDO_RX,NodeId)
    end.

%% SDO_TX as CanID
sdo_tx_canid(Nid) ->
    case ?is_cobid_extended(Nid) orelse (Nid > 127) of
	true ->
	    ?CAN_EFF_FLAG bor (?SDO_TX bsl 25) bor 
		((Nid) band ?XNODE_ID_MASK);
	false ->
	    (?SDO_TX bsl 7) bor ((Nid) band ?NODE_ID_MASK)
    end.

sdo_tx_canmask(Nid) ->
    case ?is_cobid_extended(Nid) orelse (Nid > 127) of
	true -> ?CAN_EFF_MASK;
	false -> ?CAN_SFF_MASK
    end.
	     
%% SDO_RX as CanID
sdo_rx_canid(Nid) ->
    case ?is_cobid_extended(Nid) orelse (Nid > 127) of
	true ->
	    ?CAN_EFF_FLAG bor (?SDO_RX bsl 25) bor 
		((Nid) band ?XNODE_ID_MASK);
	false ->
	    (?SDO_RX bsl 7) bor ((Nid) band ?NODE_ID_MASK)
    end.

expand_batch([{Nids,Indices,SubInds,Ds}|Bs]) ->
    [{Nid,Index,SubInd,Data} ||
	Nid <- nid_list(Nids),
	Index <- index_list(Indices),
	SubInd <- sub_index_list(SubInds),
	Data <- data_list(Ds)] ++ expand_batch(Bs);
expand_batch([{Nids,Indices,{SubInds,Ds}}|Bs]) ->
    SiData = lists:zip(sub_index_list(SubInds),
		       data_list(Ds)),
    [{Nid,Index,SubInd,Data} ||
	Nid <- nid_list(Nids),
	Index <- index_list(Indices),
	{SubInd,Data} <- SiData]  ++ expand_batch(Bs);
expand_batch([]) ->
    [].


nid_list(Nid) when is_integer(Nid) ->
    [Nid];
nid_list(Ns) when is_list(Ns) ->
    Ns.

index_list(Index) when is_integer(Index) ->
    [Index];
index_list({I1,I2}) when is_integer(I1), is_integer(I2) ->
    lists:seq(I1,I2);
index_list(List) when is_list(List) ->
    List.

sub_index_list(Si) when is_integer(Si) ->
    [Si];
sub_index_list({SiA,SiB}) when is_integer(SiA), is_integer(SiB) ->
    lists:seq(SiA,SiB);
sub_index_list(List) when is_list(List) ->
    List.

data_list(Value) when is_integer(Value) ->
    [Value];
data_list(List) when is_list(List) ->
    data_list_(list_to_binary(List));
data_list(Bin) when is_binary(Bin) ->
    data_list_(Bin).

data_list_(Bin) when byte_size(Bin) rem 4 =:= 0 ->
    [Data || <<Data:4/binary>> <= Bin];
data_list_(Bin) ->
    Pad = 8*(4 - (byte_size(Bin) rem 4)),
    [Data || <<Data:4/binary>> <= <<Bin/binary, 0:Pad>> ].








			   

    

	

