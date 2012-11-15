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
%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%    Defines needed for applications wanting to attach to the
%%%    CANopen node co_node.
%%% @end
%%% Created : 26:th October 2011 by Tony Rogvall <tony@rogvall.se>
%%%-------------------------------------------------------------------
-ifndef(CO_APP_HRL).
-define(CO_APP_HRL, true).

-define(FBUF_MIN_SIZE, 256).      %% Min flash buffer size
-define(FBUF_MAX_SIZE, 8192).     %% Max flash buffer size

-define(UBOOT_HOLD_TMO,  2000).      %% 2s time to wait for signal
-define(POWERUP_TIME,    3000).      %% 3s max startup time 


-define(CMD_UBOOT_BLOCK,    16#01).      %% initialize block download
-define(CMD_UBOOT_ERASE,    16#02).      %% erase sector(s)
-define(CMD_UBOOT_BLOCK_END,16#03).      %% check crc & write block
-define(CMD_UBOOT_CRC,      16#04).      %% crc the memory

%% request contains the length (ignore length on reply)
-define(CMD_UBOOT_DATAn,    16#3).       %% as 3 bit number!!!
-define(CMD_UBOOT_DATA_0,   16#18).      %% upload block data 0 bytes
-define(CMD_UBOOT_DATA_1,   16#19).      %% upload block data 1 byte
-define(CMD_UBOOT_DATA_2,   16#1A).      %% upload block data 2 bytes
-define(CMD_UBOOT_DATA_3,   16#1B).      %% upload block data 3 bytes
-define(CMD_UBOOT_DATA_4,   16#1C).      %% upload block data 4 bytes
-define(CMD_UBOOT_DATA_5,   16#1D).      %% upload block data 5 bytes
-define(CMD_UBOOT_DATA_6,   16#1E).      %% upload block data 6 bytes
-define(CMD_UBOOT_DATA_7,   16#1F).      %% upload block data 7 bytes

%% request and response contains the length 0..7
-define(CMD_UBOOT_READn,    16#2).       %% as 3 bit number
-define(CMD_UBOOT_READ_0,   16#20).      %% read memory/eeprom
-define(CMD_UBOOT_READ_1,   16#21).      %% read memory/eeprom
-define(CMD_UBOOT_READ_2,   16#22).      %% read memory/eeprom
-define(CMD_UBOOT_READ_3,   16#23).      %% read memory/eeprom
-define(CMD_UBOOT_READ_4,   16#24).      %% read memory/eeprom
-define(CMD_UBOOT_READ_5,   16#25).      %% read memory/eeprom
-define(CMD_UBOOT_READ_6,   16#26).      %% read memory/eeprom
-define(CMD_UBOOT_READ_7,   16#27).      %% read memory/eeprom

-define(PROTO_OK,           0).
-define(PROTO_ERR_COMMAND,  1).
-define(PROTO_ERR_ARGUMENT, 2).
-define(PROTO_ERR_CRC,      3).
-define(PROTO_ERR_INDEX,    4).
-define(PROTO_ERR_SUBIND,   5).
-define(PROTO_ERR_TIMEOUT,  6).
-define(PROTO_ERR_UNKNOWN,  255).
-define(PROTO_DATA,         -1). %% 7 bytes of data

%%
%% Manufactor specific indexes
%%
-define(MAN_SPEC_MIN, 16#2000).
-define(MAN_SPEC_MAX, 16#5FFF).

%% General parameters
-define(INDEX_LOCATION,         16#2604).   %%  Location ID (1..254)
-define(INDEX_BOOT_SERIAL,      16#2607).
-define(INDEX_BOOT_PRODUCT,     16#2608).
-define(INDEX_BOOT_DATETIME,    16#2609).
-define(INDEX_BOOT_CRC,         16#260A).
-define(INDEX_BOOT_ID,          16#260B).   %% ID negotiation value
-define(INDEX_BOOT_APP_ADDR,    16#260D).   %% Application Flash address
-define(INDEX_BOOT_APP_VSN,     16#260E).   %% Application version
-define(INDEX_BOOT_VSN,         16#260F).   %% uBoot version
-define(INDEX_BOOT_VENDOR,      16#2610).   %% Vendor code (CANopen)
-define(INDEX_BOOT_NODE,        16#2611).   %% System nodes (1..128)

%% UBOOT control interface
-define(INDEX_UBOOT_ADDR,       16#2650).   %% set flash/eeprom start address
-define(INDEX_UBOOT_WRITE,      16#2651).   %% write 0..4 bytes
-define(INDEX_UBOOT_READ,       16#2652).   %% read 4 bytes of memory/eeprom
-define(INDEX_UBOOT_ERASE,      16#2653).   %% erase flash memory
-define(INDEX_UBOOT_FLASH,      16#2654).   %% flash memory

-define(INDEX_UBOOT_HOLD,       16#2655).   %% hold the boot loader 
-define(INDEX_UBOOT_GO,         16#26AA).   %% run application

-define(INDEX_PWM_DUTY,         16#2702).
-define(INDEX_PWM_RELOAD,       16#2703).
-define(INDEX_LED_GREEN,        16#2704).
-define(INDEX_LED_RED,          16#2705).
-define(INDEX_LED_GREEN_MASK,   16#2706).
-define(INDEX_LED_RED_MASK,     16#2707).

-define(INDEX_OUTPUT_BACKLIGHT, 16#2708).   %% PWM on panel backlight
-define(INDEX_OUTPUT_LEDLIGHT,  16#2709).   %% Pwm on leds
-define(INDEX_ENC_PRESCALE,     16#270A).   %% Divide encoder
-define(INDEX_FREQUENCY,        16#270B).   %% Flash interval 
-define(INDEX_FLASH,            16#270C).   %% Flash state - leds flashing
-define(INDEX_BUZZER,           16#270D).   %% Buzzer enable/disable
-define(INDEX_POWERDOWN,        16#270E).   %% Powerdown mode
-define(INDEX_BLOCK,		16#270F).   %% Default device block/unblock

%% SET/GET PDS output channels
-define(INDEX_OUTPUT_TYPE,       16#2701).  %% UNSIGNED8 - type code
-define(INDEX_OUTPUT_DELAY,      16#2710).  %% UNSIGNED32 - time
-define(INDEX_OUTPUT_DONEFN,     16#2711).  %% 
-define(INDEX_OUTPUT_WAIT,       16#2712).   
-define(INDEX_OUTPUT_WAITMULT,   16#2713).
-define(INDEX_OUTPUT_REPEAT,     16#2714).
-define(INDEX_OUTPUT_RAMPUP,     16#2715).
-define(INDEX_OUTPUT_RAMPDOWN,   16#2716).
-define(INDEX_OUTPUT_SUSTAIN,    16#2717).
-define(INDEX_OUTPUT_ALARM_LO,   16#2718).
-define(INDEX_OUTPUT_ALARM_HI,   16#2719).
-define(INDEX_OUTPUT_PRIO,       16#271A).
-define(INDEX_OUTPUT_BLOCK_NID,  16#271B).
-define(INDEX_OUTPUT_BLOCK_MASK, 16#271C).
-define(INDEX_OUTPUT_BLOCK_DEF,  16#271D).
-define(INDEX_OUTPUT_LOCATION,   16#271E).
-define(INDEX_OUTPUT_FLAGS,      16#271F).  %% more OUTPUT params at2780
-define(INDEX_OUTPUT_DEACT,      16#2780).  %% UNSIGNED32 - time
-define(INDEX_OUTPUT_STEPMAX,    16#2781).  %% UNSIGNED8  - max value on step
-define(INDEX_OUTPUT_STEP,       16#2782).  %% UNSIGNED8  - saved step value
-define(INDEX_OUTPUT_CONTROL,    16#2783).  %% UNSIGNED8  - saved control value
-define(INDEX_OUTPUT_CTLTYPE,    16#2784).  %% UNSIGNED8  - control function

%% SET/GET PDS input channels
-define(INDEX_INPUT_FLAGS,       16#2720).
-define(INDEX_INPUT_OUT,         16#2721).  %% UNSIGNED32 output channel mask
-define(INDEX_INPUT_NODE,        16#2722).  %% UNSIGEND32 input node id
-define(INDEX_INPUT_CHANNEL,     16#2723).  %% UNSIGNED8  input channel number
-define(INDEX_INPUT_AN_MIN,      16#2724).  %% UNSIGNED16
-define(INDEX_INPUT_AN_MAX,      16#2725).  %% UNSIGNED16
-define(INDEX_INPUT_AN_OFFS,     16#2726).  %% INTEGER16
-define(INDEX_INPUT_AN_SCALE,    16#2727).  %% UNSIGNED16  FIX-8.8
-define(INDEX_INPUT_CTL,         16#2728).  %% UNSIGNED32 output channel mask
%% Other
-define(INDEX_PAMP,              16#2729).  %% BOOLEAN, enable/disable power frame

%% Read only parameters
-define(INDEX_VIN100,            16#2730).  %% UNSIGNED16
-define(INDEX_HIS100,            16#2731).  %% UNSIGNED16
-define(INDEX_TEMP10,            16#2732).  %% INTEGER16
-define(INDEX_LOAD100,           16#2733).  %% UNSIGNED16
-define(INDEX_AN0,               16#2734).  %% UNSIGNED16 (10-bit)
-define(INDEX_AN1,               16#2735).  %% UNSIGNED16 (10-bit)
-define(INDEX_AN2,               16#2736).  %% UNSIGNED16 (10-bit)
-define(INDEX_W1A,               16#2737).  %% UNSIGNED16 (10-bit)
-define(INDEX_W10A,              16#2738).  %% UNSIGNED16 (10-bit)
-define(INDEX_WNA,               16#2739).  %% UNSIGNED16 (10-bit)

-define(INDEX_VIN_HIGH,          16#2740).  %% High shut-off level
-define(INDEX_VIN_MEDIUM,        16#2741).  %% Medium shut-off level
-define(INDEX_VIN_LOW,           16#2742).  %% Low shut-off level
-define(INDEX_VIN_WARN,          16#2743).  %% Warning level

%% RFID specific 
-define(INDEX_DISPLAY1,          16#2750).  %% character at position
-define(INDEX_DISPLAY4,          16#2751).  %% write 4 bytes segment
-define(INDEX_RTC,               16#2752).  %% Set RTC clock

%% PDD specific 
-define(INDEX_LCDPWM,            16#2760).  %% LCD LED backlight pwm
-define(INDEX_LCDREG0,           16#2761).  %% write REG only 16 bit
-define(INDEX_LCDREG1,           16#2762).  %% write REG & ARG only 16+16 bit
-define(INDEX_LCDDATA,           16#2763).  %% read/write DATA 16 bit


%% PDS - PDU's

%% UBOOT notification messages - switched to uboot mode
-define(MSG_UBOOT_ON,       16#28FF).

%% Notification/ALARM  0x28xx
-define(MSG_POWER_ON,       16#2800).    %% Power ON
-define(MSG_POWER_OFF,      16#2801).    %% Sent by unit before powerdown
-define(MSG_WAKEUP,         16#2802).    %% Sent in wakeup signal

-define(MSG_ALARM,          16#2803).   %% Alarm code notification

-define(MSG_OUTPUT_ADD,     16#2804).   %% Add output interface
-define(MSG_OUTPUT_DEL,     16#2805).   %% Delete output interface
-define(MSG_OUTPUT_ACTIVE,  16#2806).   %% Activate/Deactivate signal

-define(MSG_BACKLIGHT,      16#2807).   %% Set backlight value (global)
-define(MSG_LEDLIGHT,       16#2808).   %% Set led-light value (global)
-define(MSG_ALARM_ACK,      16#2809).   %% Alarm ack code notification

-define(MSG_NODE_ADD,       16#280A).   %% Add node to members
-define(MSG_NODE_DEL,       16#280B).   %% Delete node from members
-define(MSG_NODE_BACKUP,    16#280C).   %% Signal backup selection

-define(MSG_OUTPUT_VALUE,   16#280D).   %% Current value update

-define(MSG_ALARM_CNFRM,    16#280E).   %% Confirm larm condition (from client)

-define(MSG_BLOCK,          16#2810).   %% Block input from a node (in value)
-define(MSG_UNBLOCK,        16#2811).   %% Unblock input from a node (in value)

-define(MSG_ECHO_REQUEST,   16#2812).   %% Expect echo reply from matching node
-define(MSG_ECHO_REPLY,     16#2813).   %% This is the reply

-define(MSG_RESET,          16#28AA).   %%  Reset the node 

%%
%% Device specific indexes
%%
-define(DEV_SPEC_MIN, 16#6000).
-define(DEV_SPEC_MAX, 16#9FFF).

%% Notification data
-define(MSG_DIGITAL,        16#6000).  %% channel, 0|1
-define(MSG_ANALOG,         16#6400).  %% channel, 0x0000 - 0xFFFF
-define(MSG_ENCODER,        16#6100).  %% -1,+1

%% rfid node message
-define(MSG_RFID,           16#6200).  %% sub=type data=rfid:32

%% battery node PDB messages volt=V*100 (0.00 - 65.00), amp=A*100 
-define(MSG_BATTERY,        16#6201).  %% sub=bank, data=volt:16, amp:16

%% Alarm causes tied to MSG_ALARM_x notifications
-define(ALARM_CAUSE_OK,      16#00).  %% channel ok
%% Non-fatal alarm 
-define(ALARM_CAUSE_LOW,     16#01).  %% underload
-define(ALARM_CAUSE_OVERLOAD,16#02).  %% warning total overload
-define(ALARM_CAUSE_HOT,     16#03).  %% warning hot
-define(ALARM_CAUSE_LOW_BAT, 16#04).  %% low battery
%% Fatal alarms
-define(ALARM_CAUSE_FATAL,   16#80).  %% Fatal bit
-define(ALARM_CAUSE_FUSE,    16#81).  %% fuse broken
-define(ALARM_CAUSE_SHORT,   16#82).  %% short circuit
-define(ALARM_CAUSE_HIGH,    16#83).  %% overload
-define(ALARM_CAUSE_OVERHEAT,16#84).  %% fatal over heat
-define(ALARM_CAUSE_VIN_LEV, 16#85).  %% fatal vin level (internal)
-define(ALARM_CAUSE_HIS_LEV, 16#86).  %% fatal his level (internal)
-define(ALARM_CAUSE_HIS,     16#87).  %% fatal his < vin (internal)


%% Application get_entry return data
%% transfer: streamed, {streamed,Mod}, atomic, {atomic,Mod}, {value,Value}, {dict, Dict}
%% timeout is used when a longer session timeout than ordinary is needed
-record(index_spec,
	{
	  index,
	  type,
	  access,
	  transfer,
	  timeout
	}).

-type node_id()::
	{nodeid, ShortNodeId::integer()} |
	{xnodeid, ExtNodeId::integer()}.	

-type node_identity()::
	NodeId::node_id() |
	{name, NodeName::atom()} |
	integer() | %% Serial
	pid().

-endif.

