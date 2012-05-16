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
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%   SDO Pdu descriptions
%%% @end
%%% Created :  2 Jun 2010 by Tony Rogvall <tony@rogvall.se>

-ifndef(__SDO_HRL__).
-define(__SDO_HRL__, true).

-define(SDO_ENDIAN, little).

%% convert bool => integer
-define(UINT1(Cond), if (Cond) -> 1; true -> 0 end).
-define(NBYTES(X), (((X) + 7) bsr 3)).  %% number of bytes to fit x bits 
-define(NBITS(Y),  ((Y) bsl 3)).        %% bytes > bits
-define(MAX_BLK_ERR,  5).      %% Max 5 failed retransmits of block
-define(MAX_BLKSIZE, 127).
%% -define(USE_BLKSIZE, 74).      %% Max 518 bytes / block
-define(USE_BLKSIZE, 8).       %% Test and debug => 56 bytes

%% Client command specifier
-define(CCS_DOWNLOAD_SEGMENT_REQUEST,     0).
-define(CCS_INITIATE_DOWNLOAD_REQUEST,    1).
-define(CCS_INITIATE_UPLOAD_REQUEST,      2).
-define(CCS_UPLOAD_SEGMENT_REQUEST,       3).
-define(CCS_ABORT_TRANSFER,               4).
-define(CCS_BLOCK_UPLOAD,                 5).
-define(CCS_BLOCK_DOWNLOAD,               6).

%% Server command specifier
-define(SCS_UPLOAD_SEGMENT_RESPONSE,      0).
-define(SCS_DOWNLOAD_SEGMENT_RESPONSE,    1).
-define(SCS_INITIATE_UPLOAD_RESPONSE,     2).
-define(SCS_INITIATE_DOWNLOAD_RESPONSE,   3).
-define(SCS_ABORT_TRANSFER,               4).
-define(SCS_BLOCK_DOWNLOAD,               5).
-define(SCS_BLOCK_UPLOAD,                 6).

%% client & server
-define(CS_ABORT_TRANSFER,     4).    %% mux

%%
%% BLOCK 
%%
-define(CS_UPLOAD_REQUEST,      0).
-define(CS_UPLOAD_END_RESPONSE, 1).
-define(CS_UPLOAD_RESPONSE,     2).
-define(CS_UPLOAD_START,        3).

-define(CS_DOWNLOAD_REQUEST,      0).
-define(CS_DOWNLOAD_END_REQUEST,  1).

%%  ss     what
%%  0      initiate download response
%%  1      end block download response
%%  2      block download response
-define(SS_INITIATE_DOWNLOAD_RESPONSE,  0).
-define(SS_DOWNLOAD_END_RESPONSE,       1).
-define(SS_DOWNLOAD_RESPONSE,           2).

-define(SS_UPLOAD_RESPONSE,            0).
-define(SS_UPLOAD_END_REQUEST,         1).

-define(MULTIPLEXOR(IX,SI), IX:16/?SDO_ENDIAN, SI:8).
	
%% SERVER->CLIENT messages  (SDO_TX)  transmitted from node

-record(sdo_scs_initiate_upload_response,
	{
	  %% scs,      %% :3  command specifier (2=INITIATE_UPLOAD_RESPONSE)
	  %% unused,   %% :1  always = 0
	  n,        %% :2  bytes not used in data section
	  e,        %% :1  transfer type (0=normal,1=expedited)
	  s,        %% :1  size indicator 
	  index,    %% :16/little  object index
	  subind,   %% :8  sub index
	  d         %% :32/little (when e=0 and s=1)
	 }).

-define(sdo_scs_initiate_upload_response(R1,N,E,S,IX,SI,D),
	<<?SCS_INITIATE_UPLOAD_RESPONSE:3,R1:1,N:2,E:1,S:1,
	  ?MULTIPLEXOR(IX,SI), D:4/binary>>).

-define(ma_scs_initiate_upload_response(N,E,S,IX,SI,D),
	?sdo_scs_initiate_upload_response(_,N,E,S,IX,SI,D)).
-define(mk_scs_initiate_upload_response(N,E,S,IX,SI,D),
	?sdo_scs_initiate_upload_response(0,(N),(E),(S),(IX),(SI),(D))).


-record(sdo_scs_initiate_download_response,
	{
	  %% scs,      %% :3  command specifier (2=INITIATE_DOWNLOAD_RESPONSE)
	  %% unused,   %% :5  always=0
	  index,       %% :16/little  object index
	  subind       %% :8  sub index
	  %% reserved  %% :32
	 }).

-define(sdo_scs_initiate_download_response(R1,IX,SI,R2),
	<<?SCS_INITIATE_DOWNLOAD_RESPONSE:3,R1:5,
	  ?MULTIPLEXOR(IX,SI),R2:32>>).

-define(ma_scs_initiate_download_response(IX,SI),
	?sdo_scs_initiate_download_response(_,IX,SI,_)).
-define(mk_scs_initiate_download_response(IX,SI),
	?sdo_scs_initiate_download_response(0,(IX),(SI),0)).

-record(sdo_scs_upload_segment_response,
	{
	  t,        %% :1  toggle bit
	  n,        %% :3  number of bytes that do not contain data
	  c,        %% :1  more segments
	  d         %% :7/binary
	 }).

-define(sdo_scs_upload_segment_response(T,N,C,D),
	<<?SCS_UPLOAD_SEGMENT_RESPONSE:3,T:1,N:3,C:1,D:7/binary>>).

-define(ma_scs_upload_segment_response(T,N,C,D),
	?sdo_scs_upload_segment_response(T,N,C,D)).
-define(mk_scs_upload_segment_response(T,N,C,D),
	?sdo_scs_upload_segment_response((T),(N),(C),(D))).

%%
-record(sdo_scs_download_segment_response,
	{
	  %% cs,                %% :3 command specifier 
	  %% 
	  t                     %% :1 toggle bit
	  %% unused:4;          %% always = 0
	  %% _reserved:56       %% reserved
	 }).

-define(sdo_scs_download_segment_response(T,R1,R2),
	<<?SCS_DOWNLOAD_SEGMENT_RESPONSE:3,T:1,R1:4,R2:56>>).

-define(ma_scs_download_segment_response(T),
	?sdo_scs_download_segment_response(T,_,_)).
-define(mk_scs_download_segment_response(T),
	?sdo_scs_download_segment_response((T),0,0)).

-record(sdo_abort,
	{
	  %% cs,      %% :3 command specifier (4=ABORT)
	  %% unused,  %% :5 always = 0

	  index,  %% :16/little object index
	  subind,  %% :8 sub-index
	  code   %% :32/little abort code
	 }).

%% use same structure for all cases to simplify abort...
-define(sdo_abort_transfer(CS,R1,IX,SI,Code),
	<<CS:3,R1:5,?MULTIPLEXOR(IX,SI),Code:32/?SDO_ENDIAN>>).

-define(ma_abort_transfer(IX,SI,Code),
	?sdo_abort_transfer(?CS_ABORT_TRANSFER,_,IX,SI,Code)).
-define(mk_abort_transfer(IX,SI,Code),
	?sdo_abort_transfer(?CS_ABORT_TRANSFER,0,(IX),(SI),(Code))).

-define(ma_scs_abort_transfer(IX,SI,Code),
	?sdo_abort_transfer(?SCS_ABORT_TRANSFER,_,IX,SI,Code)).
-define(mk_scs_abort_transfer(IX,SI,Code),
	?sdo_abort_transfer(?SCS_ABORT_TRANSFER,0,(IX),(SI),(Code))).

-define(ma_ccs_abort_transfer(IX,SI,Code),
	?sdo_abort_transfer(?CCS_ABORT_TRANSFER,_,IX,SI,Code)).
-define(mk_ccs_abort_transfer(IX,SI,Code),
	?sdo_abort_transfer(?CCS_ABORT_TRANSFER,0,(IX),(SI),(Code))).


-record(sdo_scs_block_initiate_download_response,
	{
	  %% scs,        %% :3 command specifier (5=BLOCK_DOWNLOAD + ss=0)
	  %% unused,     %% :2 always = 0
	  sc,            %% :1 server CRC support
	  %% ss,         %% :2 server subcommand (ss=0)

	  index,         %% :16/little object index
	  subind,        %% :8  entry  sub-index
	  blksize        %% :8 number of segments / block [1,127]
	  %% _reserved:24  %% reserved = 0
	 }).

-define(sdo_scs_block_initiate_download_response(R1,SC,IX,SI,BlkSz,R2),
	<<?SCS_BLOCK_DOWNLOAD:3,R1:2,SC:1,?SS_INITIATE_DOWNLOAD_RESPONSE:2,
	  ?MULTIPLEXOR(IX,SI), BlkSz:8, R2:24>>).

-define(ma_scs_block_initiate_download_response(SC,IX,SI,BlkSz),
	?sdo_scs_block_initiate_download_response(_,SC,IX,SI,BlkSz,_)).
-define(mk_scs_block_initiate_download_response(SC,IX,SI,BlkSz),
	?sdo_scs_block_initiate_download_response(0,(SC),(IX),(SI),(BlkSz),0)).


-record(sdo_scs_block_download_end_response,
	{
	  %% scs,        %% :3 command specifier (5=BLOCK_DOWNLOAD + ss=1)
	  %% unused,     %% :3 always = 0
	  %% ss,         %% :2 end block download response = 1
	  
	  %% _reserved:56 %% reserved
	 }).

-define(sdo_scs_block_download_end_response(R1,R2),
	<<?SCS_BLOCK_DOWNLOAD:3,R1:3,?SS_DOWNLOAD_END_RESPONSE:2,R2:56>>).

-define(ma_scs_block_download_end_response(),
	?sdo_scs_block_download_end_response(_,_)).
-define(mk_scs_block_download_end_response(),
	?sdo_scs_block_download_end_response(0,0)).

-record(sdo_scs_block_download_response,
	{
	  %% scs,     %% :3 command specifier (5=BLOCK_DOWNLOAD + ss=2)
	  %% unused,  %% :3 always = 0
	  %% ss,      %% :2 server subcommand (ss=2)
	  
	  ackseq,  %% :8 sequence number of last segment receiced
	  blksize  %% :8 number of segment/block for next round [1,127]
	  %% _reserved:40
	 }).

-define(sdo_scs_block_download_response(R1,AckSeq,BlkSize,R2),
	       <<?SCS_BLOCK_DOWNLOAD:3,R1:3,?SS_DOWNLOAD_RESPONSE:2,
		 AckSeq:8, BlkSize:8, R2:40>>).

-define(ma_scs_block_download_response(AckSeq,BlkSize),
	?sdo_scs_block_download_response(_,AckSeq,BlkSize,_)).
-define(mk_scs_block_download_response(AckSeq,BlkSize),
	?sdo_scs_block_download_response(0,(AckSeq),(BlkSize),0)).

-record(sdo_scs_block_upload_response,
	{
	  %% scs,     %% :3 command specifier (6=BLOCK_UPLOAD + ss=0)
	  %% unused,  %% :2 always = 0
	  sc,      %% :1 server CRC support
	  s,       %% :1 size indicator
	  %% ss,      %% :1 server subcommand (initiate upload response=0)

	  index,  %% :16/little  object index
	  subind, %% :8 entry  sub-index
	  size       %% :32/little;     %% upload size in bytes
	 }).


-define(sdo_scs_block_upload_response(R1,SC,S,IX,SI,Size),
	<<?SCS_BLOCK_UPLOAD:3,R1:2,SC:1,S:1,?SS_UPLOAD_RESPONSE:1,
	  ?MULTIPLEXOR(IX,SI),Size:32/?SDO_ENDIAN>>).

-define(ma_scs_block_upload_response(SC,S,IX,SI,Size),
	?sdo_scs_block_upload_response(_,SC,S,IX,SI,Size)).
-define(mk_scs_block_upload_response(SC,S,IX,SI,Size),
	?sdo_scs_block_upload_response(0,(SC),(S),(IX),(SI),(Size))).


-record(sdo_scs_block_upload_end_request,
	{
	  %% scs,     %% :3 command specifier (6=BLOCK_UPLOAD + ss=1)
	  n,       %% :3 Number of bytes in last segment of last, not used!
	  %% unused,  %% :0 Must be = 0
	  %% ss,      %% :1 server subcommand (ss=1 SS_UPLOAD_END_REQUEST)
	  
	  crc      %% :16/little CRC
	  %% _reserved:40
	 }).

-define(sdo_scs_block_upload_end_request(N,R1,CRC,R2),
	<<?SCS_BLOCK_UPLOAD:3,N:3,R1:1, ?SS_UPLOAD_END_REQUEST:1,
	  CRC:16/?SDO_ENDIAN, R2:40>>).

-define(ma_scs_block_upload_end_request(N,CRC),
	?sdo_scs_block_upload_end_request(N,_,CRC,_)).
-define(mk_scs_block_upload_end_request(N,CRC),
	?sdo_scs_block_upload_end_request((N),0,(CRC),0)).

%% CLIENT->SERVER  messages (SDO_RX) received by node

-record(sdo_ccs_initiate_download_request,
	{
	  %% ccs,   %%  :3  command specifier (1=INITIATE_DOWNLOAD_REQUEST)
	  %% unused,%%  :1  always=0
	  n,        %%  :2  number of bytes not containing data (e=1,s=1)
	  e,        %%  :1  transfer type (0=normal,1=expedited)
	  s,        %%  :1  size indicated
	  index,    %%  :16/little  object index
	  subind,   %%  :8  sub index 
	  d         %%  :32/little (e=0, s=1)
	 }).

-define(sdo_ccs_initiate_download_request(R1,N,E,S,IX,SI,Data),
	<<?CCS_INITIATE_DOWNLOAD_REQUEST:3, R1:1,N:2,E:1,S:1,
	  ?MULTIPLEXOR(IX,SI), Data:4/binary>>).

-define(ma_ccs_initiate_download_request(N,E,S,IX,SI,Data),
	?sdo_ccs_initiate_download_request(_,N,E,S,IX,SI,Data)).
-define(mk_ccs_initiate_download_request(N,E,S,IX,SI,Data),
	?sdo_ccs_initiate_download_request(0,(N),(E),(S),(IX),(SI),(Data))).

-record(sdo_ccs_download_segment_request,
	{
	  t,        %% :1  toggle bit
	  n,        %% :3  number of bytes that do not contain data
	  c,        %% :1  more segments
	  d         %% :7/binary	
	}).

-define(sdo_ccs_download_segment_request(T,N,C,Data),
	<<?CCS_DOWNLOAD_SEGMENT_REQUEST:3, T:1, N:3, C:1, Data:7/binary>>).

-define(ma_ccs_download_segment_request(T,N,C,Data),
	?sdo_ccs_download_segment_request(T,N,C,Data)).
-define(mk_ccs_download_segment_request(T,N,C,Data),
	?sdo_ccs_download_segment_request((T),(N),(C),(Data))).

-record(sdo_ccs_upload_segment_request,
	{
	  %% cs,                %% :3 command specifier 
	  %% CCS_UPLOAD_SEGMENT_REQUEST
	  t                     %% :1 toggle bit
	  %% unused:4;          %% always = 0
	  %% _reserved:56      %% reserved
	 }).

-define(sdo_ccs_upload_segment_request(T,R1,R2),
	<<?CCS_UPLOAD_SEGMENT_REQUEST:3, T:1, R1:4, R2:56>>).

-define(ma_ccs_upload_segment_request(T),
	?sdo_ccs_upload_segment_request(T,_,_)).
-define(mk_ccs_upload_segment_request(T),
	?sdo_ccs_upload_segment_request((T),0,0)).


-record(sdo_ccs_initiate_upload_request,
	{
	  %% ccs,   %% :3  command specifier (2=INITIATE_UPLOAD_REQUEST)
	  %% unused,%% :5  always = 0
	  index,    %% :16/little  object index
	  subind    %% :8  sub index
	  %% _reserved  %% :32
	 }).

-define(sdo_ccs_initiate_upload_request(R1,IX,SI,R2),
	<<?CCS_INITIATE_UPLOAD_REQUEST:3,R1:5,?MULTIPLEXOR(IX,SI),R2:32>>).

-define(ma_ccs_initiate_upload_request(IX,SI),
	?sdo_ccs_initiate_upload_request(_,IX,SI,_)).
-define(mk_ccs_initiate_upload_request(IX,SI),
	?sdo_ccs_initiate_upload_request(0,(IX),(SI),0)).


-record(sdo_ccs_block_upload_request,
	{
	  %% ccs,        %% :3 command specifier  (5=BLOCK_UPLOAD + cs=0)
	  %% unused,     %% :2 always = 0
	  cc,            %% :1 client CRC support
	  %% cs,         %% :2 client sub command = 0
	  
	  index,         %% :16/little object index 
	  subind,        %% :8  entry sub-index
	  blksize,       %% :8  number of segments/block [1,127]
	  pst            %% :8  Protocol switch threshold
	  %% _reserved  :16 - not used
	 }).

-define(sdo_ccs_block_upload_request(R1,CC,IX,SI,BlkSize,Pst,R2),
	<<?CCS_BLOCK_UPLOAD:3, R1:2, CC:1, ?CS_UPLOAD_REQUEST:2, 
	  ?MULTIPLEXOR(IX,SI), BlkSize:8, Pst:8, R2:16>>).

-define(ma_ccs_block_upload_request(CC,IX,SI,BlkSize,Pst),
	?sdo_ccs_block_upload_request(_,CC,IX,SI,BlkSize,Pst,_)).
-define(mk_ccs_block_upload_request(CC,IX,SI,BlkSize,Pst),
	?sdo_ccs_block_upload_request(0,(CC),(IX),(SI),(BlkSize),(Pst),0)).

-record(sdo_ccs_block_upload_end_response,
	{
	  %% ccs,    %% :3 command specifier  (5=BLOCK_UPLOAD + cs=1)
	  %% unused, %% :3 not used
	  %% cs,     %% :2 client sub command = 1
	  
	  %% _reserved:56
	 }).

-define(sdo_ccs_block_upload_end_response(R1,R2),
	<<?CCS_BLOCK_UPLOAD:3, R1:3, ?CS_UPLOAD_END_RESPONSE:2, R2:56>>).

-define(ma_ccs_block_upload_end_response(),
	?sdo_ccs_block_upload_end_response(_,_)).
-define(mk_ccs_block_upload_end_response(),
	?sdo_ccs_block_upload_end_response(0,0)).

-record(sdo_ccs_block_upload_start,
	{
	  %% ccs,        %% :3 command specifier  (5=BLOCK_UPLOAD + cs=3)
	  %% unused,     %% :3 always = 0
	  %% cs,         %% :2 client sub command = 3
	  
	  %% _reserved:56
	 }).

-define(sdo_ccs_block_upload_start(R1,R2),
	<<?CCS_BLOCK_UPLOAD:3, R1:3,  ?CS_UPLOAD_START:2, R2:56>>).

-define(ma_ccs_block_upload_start(),
	?sdo_ccs_block_upload_start(_,_)).
-define(mk_ccs_block_upload_start(),
	?sdo_ccs_block_upload_start(0,0)).

-record(sdo_ccs_block_upload_response,
	{
	  %% ccs,     %% :3 command specifier (5=BLOCK_UPLOAD + cs=2)
	  %% unused,  %% :3 always = 0
	  %% cs,      %% :2 client sub command = 2

	  ackseq,    %% :8 sequence number of last segment in last block upload
	  blksize    %% :8 number of segment/block in following upload [1,127]
	  %% _reserved:40 %% reserved 
	 }).

-define(sdo_ccs_block_upload_response(R1,AckSeq,BlkSize,R2),
	<<?CCS_BLOCK_UPLOAD:3, R1:3, ?CS_UPLOAD_RESPONSE:2, 
	  AckSeq:8, BlkSize:8, R2:40>>).

-define(ma_ccs_block_upload_response(AckSeq,BlkSize),
	?sdo_ccs_block_upload_response(_,AckSeq,BlkSize,_)).
-define(mk_ccs_block_upload_response(AckSeq,BlkSize),
	?sdo_ccs_block_upload_response(0,(AckSeq),(BlkSize),0)).


-record(sdo_ccs_block_download_request,
	{
	  %% ccs,     %% :3 command specifier  (6=BLOCK_DOWNLOAD + cs=0)
	  %% unused,  %% :2 always = 0
	  cc,         %% :1 client CRC support
	  s,          %% :1 size indicator
	  %% cs,      %% :1 client sub command = 0
	  
	  index,      %% :16/little object index 
	  subind,     %% :8  entry sub-index
	  size        %% :32/little - total size of data
	 }).

-define(sdo_ccs_block_download_request(CC,S,IX,SI,Size),
	<<?CCS_BLOCK_DOWNLOAD:3,0:2,CC:1, S:1, ?CS_DOWNLOAD_REQUEST:1,
	  ?MULTIPLEXOR(IX,SI), Size:32/?SDO_ENDIAN>>).

-define(ma_ccs_block_download_request(CC,S,IX,SI,Size),
	?sdo_ccs_block_download_request(CC,S,IX,SI,Size)).
-define(mk_ccs_block_download_request(CC,S,IX,SI,Size),
	?sdo_ccs_block_download_request((CC),(S),(IX),(SI),(Size))).


-record(sdo_ccs_block_download_end_request,
	{
	  %% ccs,    %% :3 command specifier  (6=BLOCK_DOWNLOAD + cs=1)
	  n,         %% :3 number of bytes in last segment not used
	  %% unused, %% :1 not used always 0
	  %% cs      %% :1 client sub command = 1
	  
	  crc        %% :16/little block CRC
	  %% _reserved:40
	 }).

-define(sdo_ccs_block_download_end_request(N,R1,Crc,R2),
	<<?CCS_BLOCK_DOWNLOAD:3,N:3, R1:1, ?CS_DOWNLOAD_END_REQUEST:1,
	  Crc:16/?SDO_ENDIAN, R2:40>>).

-define(ma_ccs_block_download_end_request(N,Crc),
	?sdo_ccs_block_download_end_request(N,_,Crc,_)).
-define(mk_ccs_block_download_end_request(N,Crc),
	?sdo_ccs_block_download_end_request((N),0,(Crc),0)).

%% Used by both download and upload block
-record(sdo_block_segment,
	{
	  last,       %% :1 last segment
	  seqno,      %% :7 sequence number
	  d           %% :7/binary data
	}).

-define(sdo_block_segment(Last,Seq,Data),
	<<Last:1, Seq:7, Data:7/binary>>).
-define(ma_block_segment(Last,Seq,Data),
	?sdo_block_segment(Last,Seq,Data)).
-define(mk_block_segment(Last,Seq,Data),
	?sdo_block_segment((Last),(Seq),(Data))).


-endif.

