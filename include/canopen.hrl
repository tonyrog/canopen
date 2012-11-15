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
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% File    : canopen.hrl
%%% Description : Can Open definitions
%%% Created :  9 Jan 2008 by Tony Rogvall <tony@PBook.local>
%%% @end

-ifndef(__CAN_OPEN_HRL__).
-define(__CAN_OPEN_HRL__, true).

%% Serial number of CANOpen manager
-define(MGR_NODE, 16#00).

%% Basic data types (DEFTYPE)
-define(BOOLEAN,         16#0001).
-define(INTEGER8,        16#0002).
-define(INTEGER16,       16#0003).
-define(INTEGER32,       16#0004).
-define(INTEGER,         ?INTEGER32).  %% alias
-define(UNSIGNED8,       16#0005).
-define(UNSIGNED16,      16#0006).
-define(UNSIGNED32,      16#0007).
-define(UNSIGNED,        ?UNSIGNED32). %% alias
-define(REAL32,          16#0008).
-define(FLOAT,           ?REAL32).    %% alias
-define(VISIBLE_STRING,  16#0009).
-define(STRING,          ?VISIBLE_STRING). %% alias
-define(OCTET_STRING,    16#000A).
-define(UNICODE_STRING,  16#000B).
-define(TIME_OF_DAY,     16#000C).
-define(TIME_DIFFERENCE, 16#000D).
-define(BIT_STRING,      16#000E).
-define(DOMAIN,          16#000F).
-define(INTEGER24,       16#0010).
-define(REAL64,          16#0011).
-define(DOUBLE,          ?REAL64).  %% alias
-define(INTEGER40,       16#0012).
-define(INTEGER48,       16#0013).
-define(INTEGER56,       16#0014).
-define(INTEGER64,       16#0015).
-define(UNSIGNED24,      16#0016).
%% Reserved     0017
-define(UNSIGNED40,      16#0018).
-define(UNSIGNED48,      16#0019).
-define(UNSIGNED56,      16#001A).
-define(UNSIGNED64,      16#001B).
%% Reserved  001C - 001F

%% Complex data structures
-define(PDO_PARAMETER,   16#0020).
-define(PDO_MAPPING,     16#0021).
-define(SDO_PARAMETER,   16#0022).
-define(IDENTITY,        16#0023).
-define(DEBUGGER_PAR,    16#0024).
-define(COMMAND_PAR,     16#0025).

%% Reserved 0024 - 003F

%% 0040 - 005F - DEFSTRUCT - Manufacturer Specific Complex Data Types
%%
%% 0060 - 007F - DEFFTYPE   - Device Profile (0) Specific Standard Data Types
%% 0080 - 009F - DEFSTRUCT  - Device Profile (0) Specific Complex Data Types
%%
%% 00A0 - 00BF - DEFFTYPE   - Device Profile (1) Specific Standard Data Types
%% 00C0 - 00DF - DEFSTRUCT  - Device Profile (1) Specific Complex Data Types
%%
%% 00E0 - 00FF - DEFFTYPE   - Device Profile (2) Specific Standard Data Types
%% 0100 - 011F - DEFSTRUCT  - Device Profile (2) Specific Complex Data Types
%%
%% 0120 - 013F - DEFFTYPE   - Device Profile (3) Specific Standard Data Types
%% 0140 - 015F - DEFSTRUCT  - Device Profile (3) Specific Complex Data Types
%%
%% 0160 - 017F - DEFFTYPE   - Device Profile (4) Specific Standard Data Types
%% 0180 - 019F - DEFSTRUCT  - Device Profile (4) Specific Complex Data Types
%%
%% 01A0 - 01BF - DEFFTYPE   - Device Profile (5) Specific Standard Data Types
%% 01C0 - 01DF - DEFSTRUCT  - Device Profile (5) Specific Complex Data Types
%%
%% 01E0 - 01FF - DEFFTYPE   - Device Profile (6) Specific Standard Data Types
%% 0200 - 021F - DEFSTRUCT  - Device Profile (6) Specific Complex Data Types
%%
%% 0220 - 023F - DEFFTYPE   - Device Profile (7) Specific Standard Data Types
%% 0240 - 025F - DEFSTRUCT  - Device Profile (7) Specific Complex Data Types

%%  access_code:2 (check standard)
-define(ACCESS_C,   2#0000).
-define(ACCESS_RO,  2#0001).
-define(ACCESS_WO,  2#0010).
-define(ACCESS_RW,  2#0011).
-define(ACCESS_PTR, 2#0100).
-define(ACCESS_STO, 2#1000).

%%  object_code:2 (according to standard)
-define(OBJECT_NULL,          0).
-define(OBJECT_DOMAIN,        2).
-define(OBJECT_DEFTYPE,       5).
-define(OBJECT_DEFSTRUCT,     6).
-define(OBJECT_VAR,           7).
-define(OBJECT_ARRAY,         8).
-define(OBJECT_RECORD,        9).
-define(OBJECT_DEFPDO,       10).  %% Seazone - special

-define(is_index(I),  (I)>=0, (I)=<16#ffff).
-define(is_subind(I), (I)>=0, (I)=<16#ff).

%% SI unit coding DR-303-2
-define(SI_NONE,     16#00).
-define(SI_METER,    16#01).   %% m
-define(SI_KILOGRAM, 16#02).   %% kg
-define(SI_SECOND,   16#03).   %% s
-define(SI_AMPERE,   16#04).   %% A
-define(SI_KELVIN,   16#05).   %% K
-define(SI_MOLE,     16#06).   %% mol
-define(SI_CANDELA,  16#07).   %% cd

-define(SI_RADIAN,   16#10).   %% rad
-define(SI_STERADIN, 16#11).   %% sr

-define(SI_HERTZ,    16#20).   %% HZ
-define(SI_NEWTON,   16#21).   %% N
-define(SI_PASCAL,   16#22).   %% PA
-define(SI_JOULE,    16#23).   %% J
-define(SI_WATT,     16#24).   %% W
-define(SI_COULOMB,  16#25).   %% C
-define(SI_VOLT,     16#26).   %% V
-define(SI_FARAD,    16#27).   %% F
-define(SI_OHM,      16#28).   %% W
-define(SI_SIEMENS,  16#29).   %% S
-define(SI_WEBER,    16#2A).   %% Wb
-define(SI_TESLA,    16#2B).   %% T
-define(SI_HENRY,    16#2C).   %% H
-define(SI_CELSIUS,  16#2D).   %% °C
-define(SI_LUMEN,    16#2E).   %% lm
-define(SI_LUX,      16#2F).   %% lx
-define(SI_BECQUEREL,16#30).   %% Bq
-define(SI_GRAY,     16#31).   %% Gy
-define(SI_SIEVERT,  16#32).   %% Sv

%% add more SI units and SI prefix encoding

%% Dictionary entry
%% Note:
%%      For arrays and record the entry {Ix,0} is special and contains
%%      the number of entries [0..253]. For variables var the {Ix,0}
%%      store the actual value.
%%
%%      The optional entry {Ix,255} contains meta information on form
%%          <<Reserved:16, ObjectCode:8, TypeCode:8>>
%%      I guess it's not useful for complex user defined data types...
%%
%%  ADD ACCESS TYPES:
%%     STORE      - store in dictionary
%%     NOTIFY     - notify application 
%%     TRANSFER   - transfer data to application
%%     STREAM     - transfer segments to application
%%
%%  THEN an application PID
%%
-record(dict_object,
	{
	  index,     %% {index:16, 0}
	  access,    %% access for var - overall access for array/rec
	  type,      %% type of object for record/var - main type for array
	  struct     %% structure type - var/rec/array/deftype/defstruct ...
	 }).
	  
-record(dict_entry, 
	{
	  index,      %% {index:16, subindex:8}
	  access,     %% ACCESS_ C|RO|WO|RW|STO|PTR
	  type,       %% data type (integer:16)
	  data        %% data  (encoded)
	 }).

%%  category_code:2 (check standard)
-define(CATEGORY_OPTIONAL,    0).
-define(CATEGORY_MANDATORY,   1).
-define(CATEGORY_CONDITIONAL, 2).

%% PDO mapping style
-define(MAPPING_NO,           0).
-define(MAPPING_OPTIONAL,     1).
-define(MAPPING_DEFAULT,      2).

%% External description entries (could be mapped to XML etc)
-record(objdef,
	{
	  index,       %% default index
	  name,        %% Object name (string)
	  id,          %% Object id (atom)
	  description, %% Object documentation
	  struct,      %% variable,array,record ...
	  type,        %% unsigned8, ....
	  access,      %% ro=Read only, wo=Write only, rw=Read Write,
	               %% c=Constant
	  category,    %% optional,mandatory,conditional
	  range,       %% allowed value range for this object
	  entry,       %% default entry for array
	  entries=[]
	 }).

-record(entdef,
	{
	  index,           %% sub-index
	  name,            %% Descriptiv name of the Sub-Index
	  id,              %% entry id (atom)
	  description,     %% entry documentation
	  type,            %% Unsigned8, Boolean, Integer16 etc
	  category,        %% optional,mandatory,conditional
	  access,          %% ro=Read only, wo=Write only, rw=Read Write,
	                   %% c=Constant
	  pdo_mapping,     %% no(default), optional, default
	  range,           %% allowed value range for this object
	  default,         %% value of this object after device initialization
	  substitute       %% value of this object if it is not implemented
	 }).


%% COB function codes
-define(NMT,               2#0000).
-define(SYNC,              2#0001).
-define(TIME_STAMP,        2#0010).
-define(PDO1_TX,           2#0011).
-define(PDO1_RX,           2#0100).
-define(PDO2_TX,           2#0101).
-define(PDO2_RX,           2#0110).
-define(PDO3_TX,           2#0111).
-define(PDO3_RX,           2#1000).
-define(PDO4_TX,           2#1001).
-define(PDO4_RX,           2#1010).
-define(SDO_TX,            2#1011).
-define(SDO_RX,            2#1100).
-define(NODE_GUARD,        2#1110).
-define(LSS,               2#1111).

-define(EMERGENCY,         2#0001).

%%
-define(COBID_TO_CANID(ID),
	if ?is_cobid_extended((ID)) ->
		((ID) band ?COBID_ENTRY_ID_MASK) bor ?CAN_EFF_FLAG;
	   true ->
		((ID) band ?CAN_SFF_MASK)
	end).

-define(CANID_TO_COBID(ID),
	if ?is_can_id_eff((ID)) ->
		((ID) band ?CAN_EFF_MASK) bor ?COBID_ENTRY_EXTENDED;
	   true ->
		((ID) band ?CAN_SFF_MASK)
	end).
	

%% COB 11-bit, 7 bit node id
-define(NODE_ID_MASK,  16#7f).
-define(COB_ID(Func,Nid), (((Func) bsl 7) bor ((Nid) band ?NODE_ID_MASK))).

-define(FUNCTION_CODE(COB_ID), (((COB_ID) bsr 7) band 16#f)).
-define(NODE_ID(COB_ID), ((COB_ID) band ?NODE_ID_MASK)).

%% COB 29-bit 25 bit node id
-define(XNODE_ID_MASK,     16#01FFFFFF).  %% 25 bit node id
-define(XCOB_ID(Func,Nid), 
	(((Func) bsl 25) bor ((Nid) band ?XNODE_ID_MASK) bor 
	     ?COBID_ENTRY_EXTENDED)).
-define(XFUNCTION_CODE(COB_ID), (((COB_ID) bsr 25) band 16#F)).
-define(XNODE_ID(COB_ID),      ((COB_ID) band ?XNODE_ID_MASK)).

-define(is_cobid_extended(COBID),
	((COBID) band ?COBID_ENTRY_EXTENDED) =/= 0).
-define(is_not_cobid_extended(COBID),
	((COBID) band ?COBID_ENTRY_EXTENDED) =:= 0).

%% Is NodeID an extended node id 
-define(is_nodeid_extended(NodeID),
	(?is_cobid_extended((NodeID)) andalso
	((NodeID) band 16#2E000000 =:= ?COBID_ENTRY_EXTENDED))).

%% Is NodeID a plain node Id
-define(is_nodeid(NodeID),
	((NodeID)>0), ((NodeID)=<127)).

-define(NMT_ID, ?COB_ID(?NMT, 0)).
-define(SYNC_ID, ?COB_ID(?SYNC, 0)).
-define(TIME_STAMP_ID, ?COB_ID(?TIME_STAMP, 0)).


%%
%% Node state 
%%
-define(Initialisation,  16#00).
-define(Stopped,         16#04).
-define(Operational,     16#05).
-define(PreOperational,  16#7F).
-define(UnknownState,    16#0F).
-define(LssTimingDelay,  16#10).  %% ?

%% COBID=2021 16#7E5 -  Master->Slave 2#1111 1100101
-define(LssSwitchModeGlbal,     16#04).
-define(LssSelectVendor,        16#64).
-define(LssSelectProduct,       16#65).
-define(LssSelectRevision,      16#66).
-define(LssSelectSerial,        16#67).
-define(LssConfigureNodeId,     16#17).
-define(LssConfigureBitTimeing, 16#19).
-define(LssActivateBitTimeing,  16#21).
-define(LssStoreConfiguration,  16#23).
-define(LssRequestVendor,       16#90).
-define(LssRequestProduct,      16#91).
-define(LssRequestRevision,     16#92).
-define(LssRequestSerial,       16#93).
-define(LssIdentifyVendor,      16#70).
-define(LssIdentifyProduct,     16#71).
-define(LssIdentifyRevisionLow, 16#72).
-define(LssIdentifyRevisionHigh,16#73).
-define(LssIdentifySerialLow,   16#74).
-define(LssIdentifySerialHigh,  16#75).

%% COBID=2020  16#7E4 - Slave->Master  2#1111 1100100
-define(LssSlaveMode,           16#68).
-define(LssIdentifySlave,       16#79).
-define(LssReplyNodeId,         16#17).
-define(LssReplyBitTimeing,     16#19).
-define(LssReplyConfiguration,  16#23).
-define(LssReplyVendor,         16#90).
-define(LssReplyProduct,        16#91).
-define(LssReplyRevision,       16#92).
-define(LssReplySerial,         16#93).
-define(LssReplyIdentity,       16#79).


%% DEFSTRUCT 16#0020 (pdo_parameter)
-record(pdo_parameter,  
	{
	  offset,             %% offset from TPDO_PARAM_FIRST (0...N)
	  valid       = true, %% Entry is valid
	  rtr_allowed = true, %% Entry allow RTR
	  cob_id,             %% 1. unsigned32
	  transmission_type,  %% 2. unsigned8
	  inhibit_time,       %% 3. unsigned16
	  event_timer         %% 5. unsigned16
	 }).

%% DEFSTRUCT 16#0022 (sdo_parameter)
-record(sdo_parameter,
	{
	  client_to_server_id,     %% unsigned:32 (Rx/Tx)
	  server_to_client_id,     %% unsigned:32 (Rx/Tx)
	  node_id                  %% Node:8 (extension 25/32 bits)
	}).

%% DEFSTRUCT 16#0023  (identity)
-define(DEF_IDENTITY,
	{object,?IDENTITY,
	 [{struct,defstruct},
	  {name,identity},
	  {access,ro},
	  {type,unsigned32},
	  {entry,0,[{access,c},{type,unsigned8},{value,4}]},
	  {entry,1,[{name,vendor},{access,c},
		    {type,unsigned8},{value,?UNSIGNED32}]},
	  {entry,2,[{name,product},{access,c},
		    {type,unsigned8},{value,?UNSIGNED32}]},
	  {entry,3,[{name,revision},{access,c},
		    {type,unsigned8},{value,?UNSIGNED32}]},
	  {entry,4,[{name,serial},{access,c},
		    {type,unsigned8},{value,?UNSIGNED32}]}]}).

-define(DAYS_FROM_0_TO_1970,    719528).
-define(DAYS_FROM_0_TO_1984,    724641).
-define(TIMEOFDAY_MS(H,M,S,Ms), (1000*((S)+60*((M) + (H)*60)) + (Ms))).
-define(MAX_TIMEOFDAY_MS,       ?TIMEOFDAY_MS(23,59,59,0)).
-define(SECS_PER_DAY,           86400).
-define(MS_PER_DAY,             86400000).

%% Time since January 1, 1984
-record(time_of_day,
	{
	  ms,     %% unsigned:28
	          %% void:4
	  days    %% unsigned:16
	 }).

-record(time_difference,
	{
	  ms,     %% unsigned:28
	          %% void:4
	  days    %% unsigned:16
	 }).





-type cobid() :: non_neg_integer().
-type index() :: non_neg_integer().
-type subind() :: non_neg_integer().
-type uint1() :: non_neg_integer().
-type uint8() :: non_neg_integer().
-type uint16() :: non_neg_integer().
-type uint32() :: non_neg_integer().

-type nmt_role() :: slave | master | autonomous.

%% SDO configuration parameters
-record(sdo_ctx,
	{
	  timeout,      %% session timeout value (ms)
	  blk_timeout,  %% timeout value for block segments
	  pst,          %% pst parameter
	  max_blksize,  %% max block size to use when sending blocks
	  use_crc,      %% use crc
	  dict,         %% copy of can dictionary in co_ctx
	  sub_table,    %% copy of subscriber table in co_ctx
	  res_table,    %% copy of reserver table in co_ctx
	  readbufsize,  %% Size of bufer when reading from application
	  load_ratio,   %% Trigger for loading read buffer
	  atomic_limit, %% Limit for atomic transfer when size unknown
	  debug         %% enable/disable debug
	}).

-record(co_session,
	{
	  src    :: cobid(),       %% Sender COBID
	  dst    :: cobid(),       %% Receiver COBID
	  index  :: uint16(),      %% object being transfered 1-16#ffff
	  subind :: uint8(),       %% sub-index of object 1-16#ff
	  data   :: binary(),      %% Data if expedited
	  exp    :: uint1(),       %% Expedited flag
	  n      :: uint8(),       %% bytes not used in data section
	  size_ind :: uint1(),     %% Size indication
	  t      :: uint1(),       %% session toggle bit (0|1)
	  pst    :: uint8(),       %% Protocol switch threshold (block request)
	  crc    :: boolean(),     %% Generate/check CRC for block data
	  clientcrc :: boolean(),  %% Client CRC support (for block request)
	  size    :: uint32(),     %% Total data size (for block request)
	  blksize :: uint8(),      %% Max number of segment per block
	  blkseq  :: uint8(),      %% Block number to expect or to send
	  blkbytes :: uint16(),    %% Number of bytes transfered so far
	  lastblk  :: binary(),    %% last received block segment (7 bytes)
	  blkcrc   :: uint16(),    %% Current block CRC value
	  last     ::uint1(),      %% Flag indicating if last segment is received
	  node_pid :: pid(),       %% Pid of the node
	  client   :: term(),     %% Delayed gen_server:reply caller
	  ctx      :: record(sdo_ctx),  %% general parameters
	  buf      :: term(),      %% Data buffer
	  mref     :: term()      %% Ref to application
      }).

-record(app,
	{
	  pid,    %% application pid
	  mon,    %% application monitor
	  mod,    %% application module - init/restart etc
	  rc=0    %% restart_counter
	 }).

%% SDO session descriptor
-record(sdo,
	{
	  dest_node,
	  id,             %% {src,dst}
	  pid,            %% fsm pid
	  state = active, %% active until session_over is received
	  mon             %% fsm monitor
	}).

%% TPDO process context
-record(tpdo_ctx,
	{
	  nodeid,     %% (Short) CANOpen node id (for SAM-MPDOs)
	  node_pid,   %% co_node process id
	  dict,       %% copy of dictionary in co_ctx
	  tpdo_cache, %% copy of tpdo cache in co_ctx
	  res_table,  %% copy of reserver table in co_ctx
	  debug
	}).

%% TPDO descriptor
-record(tpdo,
	{
	  offset, %% Offset from IX_TPDO_PARAM_FIRST
	  cob_id, %% Active TPDO cobid
	  pid,    %% gen_server pid
	  mon,    %% gen_server monitor
	  rc=0    %% restart counter
	}).

%% Action on upload / download
-record(notify,
	{
	  index,  %% Index | {Index,SubIndex}
	  pid,    %% application pid - use mod otherwise
	  type    %% object, fragment
	 }).

%% Node context
-record(co_ctx,
	{
	  %% ID
	  nodeid,           %% can bus id
	  xnodeid,          %% extended can bus id
	  name,             %% node (process) name
	  vendor,           %% CANopen vendor code
	  product,          %% CANopen product code
	  revision,         %% CANopen revision code
	  serial,           %% string version of node serial number

	  %% NMT
	  state,            %% CANopen node state
	  supervision = none, %% Type of supervision
	  toggle = 0,       %% Node guard toggle for nodeid
	  xtoggle = 0,      %% Node guard toggle for xnodeid
	  nmt_role = autonomous, %% NMT role (master/slav/autonomous)
	  node_guard_timer, %% Node guard supervision of master
	  node_guard_error = false, %% Lost contact with NMT master
	  node_life_time = 0, %% Node guard supervision of master
	  heartbeat_time = 0, %% Heartbeat producer time
	  heartbeat_timer,  %% Heartbeat supervision

	  %% Object dict handling
	  dict,             %% can dictionary
	  mpdo_dispatch,    %% MPDO dispatch list 
	  res_table,        %% dictionary reservations
	  sub_table,        %% dictionary subscriptions
	  xnot_table,       %% extended notify subscriptions
	  cob_table,        %% COB lookup table
	  tpdo_cache,       %% caching values used in tpdos
	  tpdo_cache_limit, %% max number of cached values for one index
	  tpdo_restart_limit, %% max number of restarts for tpdo processes
	  tpdo,             %% tpdo context
	  tpdo_list=[],     %% [#tpdo{}]
	  app_list=[],      %% [#app{}]
	  data,             %% application data?
	  sdo,              %% sdo context
	  sdo_list=[],      %% [#sdo{}]

	  %% SYNC
	  sync_tmr = false, %% TimerRef
	  sync_time = 0,    %% Sync timer value (ms) should be us
	  sync_id,          %% COBID
	  time_stamp_time = 0,    %% Time stamp timer value ms
	  time_stamp_tmr = false, %% Time stamp timer
	  time_stamp_id = 0,      %% Time stamp COBID
	  emcy_id = 0,
	  error_list = [],        %% time unique ordered list (0-254)

	  %% DEBUG
	  debug         %% enable/disable debug
	}).


-define(ABORT_TOGGLE_NOT_ALTERNATED,    16#05030000).
-define(ABORT_TIMED_OUT,                16#05040000).
-define(ABORT_COMMAND_SPECIFIER,        16#05040001).
-define(ABORT_INVALID_BLOCK_SIZE,       16#05040002).
-define(ABORT_INVALID_SEQUENCE_NUMBER,  16#05040003).
-define(ABORT_CRC_ERROR,                16#05040004).
-define(ABORT_OUT_OF_MEMORY,            16#05040005).

-define(ABORT_UNSUPPORTED_ACCESS,       16#06010000).
-define(ABORT_READ_NOT_ALLOWED,         16#06010001).
-define(ABORT_WRITE_NOT_ALLOWED,        16#06010002).

-define(ABORT_NO_SUCH_OBJECT,           16#06020000).
-define(ABORT_NOT_MAPPABLE,             16#06040041).
-define(ABORT_BAD_MAPPING_SIZE,         16#06040042).
-define(ABORT_PARAMETER_ERROR,          16#06040043).
-define(ABORT_INTERNAL_ERROR,           16#06040047).

-define(ABORT_HARDWARE_FAILURE,         16#06060000).

-define(ABORT_DATA_LENGTH_ERROR,        16#06070010).
-define(ABORT_DATA_LENGTH_TOO_HIGH,     16#06070012).
-define(ABORT_DATA_LENGTH_TOO_LOW,      16#06070013).

-define(ABORT_NO_SUCH_SUBINDEX,	        16#06090011).
-define(ABORT_VALUE_RANGE_EXCEEDED,     16#06090030).
-define(ABORT_VALUE_TOO_LOW,            16#06090031).
-define(ABORT_VALUE_TOO_HIGH,           16#06090032).
-define(ABORT_VALUE_RANGE_ERROR,        16#06090036).

-define(ABORT_GENERAL_ERROR,            16#08000000).

-define(ABORT_LOCAL_DATA_ERROR,         16#08000020).
-define(ABORT_LOCAL_CONTROL_ERROR,      16#08000021).
-define(ABORT_LOCAL_STATE_ERROR,        16#08000022).
-define(ABORT_DICTIONARY_ERROR,         16#08000023).

%%
%% SDO symbolic abort codes
%%
-define(abort_toggle_not_alternated,    toggle_not_alternated).
-define(abort_timed_out,                timed_out).
-define(abort_command_specifier,        command_specifier).
-define(abort_invalid_block_size,       invalid_block_size).
-define(abort_invalid_sequence_number,  invalid_sequence_number).
-define(abort_crc_error,                crc_error).
-define(abort_out_of_memory,            out_of_memory).

-define(abort_unsupported_access,       unsupported_access).
-define(abort_read_not_allowed,         read_not_allowed).
-define(abort_write_not_allowed,        write_not_allowed).

-define(abort_no_such_object,           no_such_object).
-define(abort_not_mappable,             not_mappable).
-define(abort_bad_mapping_size,         bad_mapping_size).
-define(abort_parameter_error,          parameter_error).
-define(abort_internal_error,           internal_error).

-define(abort_hardware_failure,         hardware_failure).

-define(abort_data_length_error,        data_length_error).
-define(abort_data_length_too_high,     data_length_too_high).
-define(abort_data_length_too_low,      data_length_too_low).

-define(abort_no_such_subindex,	        no_such_subindex).
-define(abort_value_range_exceeded,     value_range_exceeded).
-define(abort_value_too_low,            value_too_low).
-define(abort_value_too_high,           value_too_high).
-define(abort_value_range_error,        value_range_error).

-define(abort_general_error,            general_error).

-define(abort_local_data_error,         local_data_error).
-define(abort_local_control_error,      local_control_error).
-define(abort_local_state_error,        local_state_error).
-define(abort_dictionary_error,         dictionary_error).




%% Error register codes
-define(ERROR_GENERIC,       2#00000001).
-define(ERROR_CURRENT,       2#00000010).
-define(ERROR_VOLTAGE,       2#00000100).
-define(ERROR_TEMPERATURE,   2#00001000).
-define(ERROR_COMMUNICATION, 2#00010000).
-define(ERROR_DEVICE,        2#00100000).
-define(ERROR_RESERVED,      2#01000000).
-define(ERROR_MANUFACTURER,  2#10000000).

%%
%% NMT Codes  <<CS:8, Node-ID:8>>
%%
%%  Node-ID = 0 => every one
%%
-define(NMT_UNKOWN,                0).
-define(NMT_START_REMOTE_NODE,     1).
-define(NMT_STOP_REMOTE_NODE,      2).
-define(NMT_ENTER_PRE_OPERATIONAL, 128).
-define(NMT_RESET_NODE,            129).
-define(NMT_RESET_COMMUNICATION,   130).

%%
%% Standard INDEX defs
%%
-define(IX_DEVICE_TYPE,                16#1000).
-define(IX_ERROR_REGISTER,             16#1001).
-define(IX_MANUF_STATUS_REGISTER,      16#1002).
-define(IX_PREDEFINED_ERROR_FIELD,     16#1003).
-define(IX_COB_ID_SYNC_MESSAGE,        16#1005).
-define(IX_COM_CYCLE_PERIOD,           16#1006).
-define(IX_SYNC_WINDOW_LENGTH,         16#1007).
-define(IX_MANUF_DEVICE_NAME,          16#1008).
-define(IX_MANUF_HW_VERSION,           16#1009).
-define(IX_MANUF_SW_VERSION,           16#100A).
-define(IX_GUARD_TIME,                 16#100C).
-define(IX_LIFE_TIME_FACTOR,           16#100D).

-define(IX_STORE_PARAMETERS,           16#1010).
-define(SI_STORE_ALL, 1).
-define(SI_STORE_COM, 2).
-define(SI_STORE_APP, 3).

-define(IX_RESTORE_DEFAULT_PARAMETERS, 16#1011).
-define(SI_RESTORE_ALL, 1).
-define(SI_RESTORE_COM, 2).
-define(SI_RESTORE_APP, 3).

-define(IX_COB_ID_TIME_STAMP,          16#1012).
-define(IX_HIGHRES_TIME_STAMP,         16#1013).
-define(IX_COB_ID_EMERGENCY,           16#1014).
-define(IX_INHIBIT_TIME_EMERGENCY,     16#1015).
-define(IX_CONSUMER_HEARTBEAT_TIME,    16#1016).
-define(IX_PRODUCER_HEARTBEAT_TIME,    16#1017).

-define(IX_IDENTITY_OBJECT,            16#1018).
-define(SI_IDENTITY_VENDOR,   1).
-define(SI_IDENTITY_PRODUCT,  2).
-define(SI_IDENTITY_REVISION, 3).
-define(SI_IDENTITY_SERIAL,   4).

-define(IX_STORE_EDS,                  16#1021).
-define(IX_STORE_EDS_FORMAT,           16#1022).

-define(IX_OS_COMMAND,                 16#1023).  %% Type=0025
-define(SI_OS_COMMAND,  1).
-define(SI_OS_STATUS,   2).
-define(SI_OS_REPLY,    3).

-define(IX_OS_COMMAND_MODE,            16#1024).
-define(IX_OS_DEBUGGER,                16#1025).  %% Type=0024
-define(IX_OS_PROMPT,                  16#1026).  %% Type=ARRAY UNSIGNED8

-define(SI_STDIN,   1).  %% UNSIGNED8
-define(SI_STDOUT,  2).  %% UNSIGNED8
-define(SI_STDERR,  3).  %% UNSIGNED8

%% SDO
-define(IX_SDO_SERVER_FIRST,           16#1200).
-define(IX_SDO_SERVER_LAST,            16#127F).

-define(IX_SDO_CLIENT_FIRST,           16#1280).
-define(IX_SDO_CLIENT_LAST,            16#12FF).

-define(SI_SDO_CLIENT_TO_SERVER,    1).
-define(SI_SDO_SERVER_TO_CLIENT,    2).
-define(SI_SDO_NODEID,              3).

%% PDO
-define(IX_RPDO_PARAM_FIRST,           16#1400).
-define(IX_RPDO_PARAM_LAST,            16#15FF).
-define(IX_RPDO_MAPPING_FIRST,         16#1600).
-define(IX_RPDO_MAPPING_LAST,          16#17FF).
-define(IX_TPDO_PARAM_FIRST,           16#1800).
-define(IX_TPDO_PARAM_LAST,            16#19FF).
-define(IX_TPDO_MAPPING_FIRST,         16#1A00).
-define(IX_TPDO_MAPPING_LAST,          16#1BFF).

%% MPDO
-define(IX_OBJECT_SCANNER_FIRST,       16#1FA0).
-define(IX_OBJECT_SCANNER_LAST,        16#1FCF).
-define(IX_OBJECT_DISPATCH_FIRST,      16#1FD0).
-define(IX_OBJECT_DISPATCH_LAST,       16#1FFF).


-define(SI_PDO_COB_ID,            1).
-define(SI_PDO_TRANSMISSION_TYPE, 2).
-define(SI_PDO_INHIBIT_TIME,      3).
-define(SI_PDO_EVENT_TIMER,       5).

%% PDO parameter remote access
%% COB-ID entry field
%%  Invalid:1, RtrAllowed:1, Extended:1, Id:29
-define(COBID_ENTRY_INVALID,        16#80000000).
-define(COBID_ENTRY_TIME_CONSUMER,  16#80000000).   %% 0x1012 TIME_STAMP consumer
-define(COBID_ENTRY_SYNC,           16#40000000).   %% 0x1005 usage produce SYNC
-define(COBID_ENTRY_TIME_PRODUCER,  16#40000000).   %% 0x1012 usage produce TIME_STAMP
-define(COBID_ENTRY_RTR_DISALLOWED, 16#40000000).
-define(COBID_ENTRY_EXTENDED,       16#20000000).
-define(COBID_ENTRY_ID_MASK,        16#1FFFFFFF).

%%
%% Symbolic cobid handling
%%  COBID =
%%    {cob,i}        == ?PDOi_TX_ID(NodeId)
%%    {cob,i,serial} == ?PDOi_TX_ID(node_from_serial(serial))
%%    ID             == ID  (11 bit)
%% 
%%  {pdo,Invalid,RtrDisallowed,Extended,COBID}
%%  
%% In erlang we can keep theese as terms until we use them
%% but how do we do that in C?
%%

%% FIXME: allow cobid = serial-number for dynamic can-id translation
-define(PDO_ENTRY(Invalid,RtrDisallowed,Ext,COBID),
	(((Invalid) bsl 31) bor ((RtrDisallowed) bsl 30) bor
	 ((Ext) bsl 29) bor (COBID))).


%% Transmission type
-define(TRANS_SYNC_ONCE,       0).    %% send at SYNC when requested by app
-define(TRANS_SYNC_MIN,        1).    %% send after next SYNC
-define(TRANS_SYNC_MAX,        240).  %% send after 240 SYNC
-define(TRANS_EVERY_N_SYNC(N), (N)).  %% send after n SYNC
%% 241-251 reserved
-define(TRANS_RTR_SYNC,        252).  %% send at SYNC when requested by RTR
-define(TRANS_RTR,             253).  %% send when requesed by RTR
-define(TRANS_EVENT_SPECIFIC,  254).  %% async
-define(TRANS_EVENT_PROFILE,   255).  %% async

%% MPDO Flags
-define(SAM_MPDO,   254).  %% 
-define(DAM_MPDO,   255).  %% 
-define(MPDO_DATA_SIZE,   32).  %% 

%% PDO mapping remote access
-define(PDO_MAP(Index,Subind,BitLen),
	( ((Index) bsl 16) bor ((Subind) bsl 8) bor BitLen)).

-define(PDO_MAP_INDEX(Map),  (((Map) bsr 16) band 16#ffff)).
-define(PDO_MAP_SUBIND(Map), (((Map) bsr 8) band 16#ff)).
-define(PDO_MAP_BITS(Map),   ((Map) band 16#ff)).

%% Receive MPDO map  UNSIGNED64 entry (Dispatch List)
%% BlockSize:8  - number of consecutive sub-indices used
%%    Index:16  - local dictionary index
%%   Subind:8   - local dictionary sub-index (base)
%%   RIndex:8   - sender dictionary index
%%  RSubinx:8   - sender dictionary sub-index (base)
%%      Nid:8   - sender node id
-define(RMPDO_MAP(BlockSize,Index,Subind,RIndex,RSubind,Nid),
	(((BlockSize) band 16#ff) bsl 56) bor 
	    (((Index) band 16#ffff) bsl 40) bor 
	    (((Subind) band 16#ff) bsl 32) bor
	    (((RIndex) band 16#ffff) bsl 16) bor
	    (((RSubind) band 16#ff) bsl 8) bor 
	    ((Nid) band 16#ff)).

-define(RMPDO_MAP_SIZE(Map),    (((Map) bsr 56) band 16#ff)).
-define(RMPDO_MAP_INDEX(Map),   (((Map) bsr 40) band 16#ffff)).
-define(RMPDO_MAP_SUBIND(Map),  (((Map) bsr 32) band 16#ff)).
-define(RMPDO_MAP_RINDEX(Map),  (((Map) bsr 16) band 16#ffff)).
-define(RMPDO_MAP_RSUBIND(Map), (((Map) bsr 8) band 16#ff)).
-define(RMPDO_MAP_RNID(Map),    ((Map) band 16#ff)).

%% Transmit MPDO map UNSIGNED32 entry (Scan List) 
%% BlockSize:8  - number of consecutive sub-indices used
%%    Index:16  - local dictionary index
%%   Subind:8   - local dictionary sub-index (base)
-define(TMPDO_MAP(BlockSize,Index,Subind),
	(((BlockSize) band 16#ff) bsl 24) bor 
	    (((Index) band 16#ffff) bsl 8) bor
	    ((Subind) band 16#ff)).

-define(TMPDO_MAP_SIZE(Map),   (((Map)  bsr 24) band 16#ff)).
-define(TMPDO_MAP_INDEX(Map),  (((Map) bsr 8) band 16#ffff)).
-define(TMPDO_MAP_SUBIND(Map), ((Map)  band 16#ff)).


-endif.
