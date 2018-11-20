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
%%%    EDS file utility  (DSP-306) v1.0
%%% @end
%%% Created :  2 Dec 2010 by Tony Rogvall <tony@rogvall.se>

-module(eds_file).

-compile(export_all).

-export([load/1]).
-import(lists, [reverse/1, foldl/3, foldr/3]).

-define(is_dig(X), ((X) >= $0 andalso (X) =< $9)).

-define(is_hex(X), (?is_dig((X)) orelse (((X) >= $a) andalso (X) =< $f))).
-define(is_hex4(A,B,C,D),
	(?is_hex(A) andalso ?is_hex(B) andalso ?is_hex(C) andalso ?is_hex(D))).
-define(is_hex3(A,B,C),
	(?is_hex(A) andalso ?is_hex(B) andalso ?is_hex(C))).
-define(is_hex2(A,B),
	(?is_hex(A) andalso ?is_hex(B))).


-ifdef(OTP_RELEASE). %% this implies 21 or higher
-define(EXCEPTION(Class, Reason, Stacktrace), Class:Reason:Stacktrace).
-define(GET_STACK(Stacktrace), Stacktrace).
-else.
-define(EXCEPTION(Class, Reason, _), Class:Reason).
-define(GET_STACK(_), erlang:get_stacktrace()).
-endif.

load(File) ->
    case file:open(File, [read]) of
	{ok, Fd} ->
	    try scan_sections(Fd) of
		Sections -> 
		    reverse(parse_sections(File,Sections))
	    catch
		?EXCEPTION(error,Reason,Trace) ->
		    {error,{Reason,?GET_STACK(Trace)}}
	    after
		file:close(Fd)
	    end;
	Error -> Error
    end.


%%
%% Scan EDF/DCF sections return a list
%% of {Section, Entries}
%%
scan_sections(Fd) ->
    scan_sections(Fd, 1, undefined, [], []).
    
scan_sections(Fd, Ln, Section,Entries,Acc) ->
    case file:read_line(Fd) of
	{ok, Line0} ->
	    Line = trim(Line0),
	    case Line of
		"" -> %% blank ok
		    scan_sections(Fd,Ln+1,Section,Entries,Acc);
		";"++_ ->  %% comment ok
		    scan_sections(Fd,Ln+1,Section,Entries,Acc);
		"["++Name ->  %% section name
		    case reverse(Name) of
			"]"++RName ->
			    Name1 = string:to_lower(trim(reverse(RName))),
			    Acc1 = join_section(Section,Ln,Entries,Acc),
			    scan_sections(Fd,Ln+1,Name1, [], Acc1);
			_ ->
			    io:format("warning: bad section name ~s ignored\n", 
				      [Line]),
			    scan_sections(Fd,Ln+1,Section, Entries, Acc)
		    end;
		KeyValue -> %% must be key=Value
		    case string:chr(KeyValue, $=) of
			0 ->
			    io:format("warning: bad entry ~s ignored\n", 
				      [Line]),
			    scan_sections(Fd,Ln+1,Section, Entries, Acc);
			I ->
			    {Key,"="++Value} = lists:split(I-1, KeyValue),
			    Key1 = string:to_lower(trim(Key)),
			    Value1 = trim(Value),
			    scan_sections(Fd,Ln+1,Section,
					  [{Key1,Ln,Value1}|Entries],Acc)
		    end
	    end;
	eof ->
	    reverse(join_section(Section,Ln,Entries,Acc))
    end.
%%
%% Parse sections into co_file Erlang format
%%
parse_sections(File,Sections) ->
    foldl(
      fun({"fileinfo",Ln,Entries},Acc) ->
	      Ents = file_info(File,Entries),
	      [{file_info,Ln,Ents}|Acc];
	 ({"deviceinfo",Ln,Entries},Acc) ->
	      Ents = device_info(File,Entries),
	      [{device_info,Ln,Ents}|Acc];
	 ({"dummyusage",Ln,Entries},Acc) ->
	      Ents = dummy_usage(File,Entries),
	      [{dummy_usage,Ln,Ents}|Acc];
	 ({"optionalobjects",Ln,Entries},Acc) ->
	      %% 0x1000-0x1FFF, 0x6000-0xFFFF except mandatory objects
	      Objs = objects(File,[{16#1000,16#1FFF},{16#6000,16#FFFF}],
			     Entries),
	      [{optional_objects,Ln,Objs}|Acc];
	 ({"mandatoryobjects",Ln,Entries},Acc) ->
	      %% at least 0x1000, 0x1001 (0x1018)
	      Objs = objects(File,[16#1000,16#1001,16#1018],Entries),
	      [{mandatory_objects,Ln,Objs}|Acc];
	 ({"manufacturerobjects",Ln,Entries},Acc) ->
	      %% list of objects used in 0x2000-0x5FFF
	      Objs = objects(File,[{16#2000,16#5FFF}],Entries),
	      [{manufacturer_objects,Ln,Objs}|Acc];
	 ({"devicecomissioning",Ln,Entries},Acc) ->
	      Ents = device_comissioning(File, Entries),
	      [{device_comissioning,Ln,Ents}|Acc];
	 ({"supportedmodules",Ln,Entries},Acc) ->
	      [{supported_modules,Ln,Entries}|Acc];
	 ({"comments",Ln,Entries},Acc) ->
	      [{comments,Ln,Entries}|Acc];
	 ({"dynamicchannels",Ln,Entries},Acc) ->
	      [{dynamic_channels,Ln,Entries}|Acc];
	 ({[$m, X | "moduleinfo"],Ln,Entries},Acc) when ?is_dig(X) ->
	      I = list_to_integer([X]),
	      [{{module,I,info},Ln,Entries}|Acc];
	 ({[$m, X | "comments"],Ln,Entries},Acc) when ?is_dig(X) ->
	      I = list_to_integer([X]),
	      [{{module,I,comments},Ln,Entries}|Acc];
	 ({[$m, X | "fixedobjects"],Ln,Entries},Acc) when ?is_dig(X) ->
	      I = list_to_integer([X]),
	      [{{module,I,fixed_objects},Ln,Entries}|Acc];
	 ({[$m, X | "subextends"],Ln,Entries},Acc) when ?is_dig(X) ->
	      I = list_to_integer([X]),
	      [{{module,I,sub_extends},Ln,Entries}|Acc];
	 ({[$m, X, $f,$i,$x,$e,$d, A,B,C,D, $s,$u,$b,S],Ln,Entries},Acc)
	    when ?is_dig(X), ?is_hex4(A,B,C,D), ?is_hex(S) ->
	      I     = list_to_integer([X]),
	      Index = erlang:list_to_integer([A,B,C,D], 16),
	      Sub   = erlang:list_to_integer([S], 16),
	      [{{module,I,fixed,Index,sub,Sub},Ln,Entries}|Acc];

	 ({[A,B,C,D | "name"],Ln,Entries},Acc) when ?is_hex4(A,B,C,D) ->
	      Index = erlang:list_to_integer([A,B,C,D], 16),
	      Ent = sub_names(File, Index, Entries),
	      [{{name,Index},Ln,Ent}|Acc];

	 ({[A,B,C,D | "denotation"],Ln,Entries},Acc) when ?is_hex4(A,B,C,D) ->
	      Index = erlang:list_to_integer([A,B,C,D], 16),
	      Ent = sub_names(File, Index, Entries),
	      [{{denotation,Index},Ln,Ent}|Acc];

	 ({[A,B,C,D | "value"],Ln,Entries},Acc) when ?is_hex4(A,B,C,D) ->
	      Index = erlang:list_to_integer([A,B,C,D], 16),
	      Ent = sub_values(File, Index, Entries),
	      [{{value,Index},Ln,Ent}|Acc];
	 
	 ({[A,B,C,D | "objectlinks"],Ln,Entries},Acc) when ?is_hex4(A,B,C,D) ->
	      Index = erlang:list_to_integer([A,B,C,D], 16),
	      Ent = objectlinks(File,Index,Entries),
	      [{{object_links,Index},Ln,Ent}|Acc];
		    
	({[A,B,C,D],Ln,Entries},Acc) when ?is_hex4(A,B,C,D) ->
	      Index = erlang:list_to_integer([A,B,C,D], 16),
	      Ents = object(File, Index, Entries),
	      [{Index,Ln,Ents}|Acc];
	 ({[A,B,C,D,$s,$u,$b,S],Ln,Entries},Acc) 
	    when ?is_hex4(A,B,C,D), ?is_hex(S) ->
	      Index = erlang:list_to_integer([A,B,C,D], 16),
	      Subind = erlang:list_to_integer([S], 16),
	      Ents = sub(File, Index, Subind, Entries),
	      [{{Index,Subind},Ln,Ents}|Acc];
	 ({[A,B,C,D,$s,$u,$b,S,T],Ln,Entries},Acc) 
	    when ?is_hex4(A,B,C,D), ?is_hex2(S,T) ->
	      Index = erlang:list_to_integer([A,B,C,D], 16),
	      Subind = erlang:list_to_integer([S,T], 16),
	      Ents = sub(File, Index, Subind, Entries),
	      [{{Index,Subind},Ln,Ents}|Acc];
	 ({Name,Ln,_Entries},Acc) ->
	      io:format("~s:~w: unrecognised section ~s ignored\n",
			[File, Ln, Name]),
	      Acc
      end, [], Sections).

	
%% parse file section entries
file_info(File,Ents) ->
    foldr(
      fun({"filename",Ln,Name},Acc) ->
	      [{file_name,Ln,Name}|Acc];
	 ({"fileversion",Ln,Value},Acc) ->
	      [{file_version,Ln,Value}|Acc];
	 ({"filerevision",Ln,Value},Acc) ->
	      [{file_revision,Ln,Value}|Acc];
	 ({"edsversion",Ln,Value},Acc) ->
	      [{eds_version,Ln,Value}|Acc];
	 ({"description",Ln,Value},Acc) ->
	      [{description,Ln,Value}|Acc];
	 ({"creationtime",Ln,Value},Acc) ->
	      [{create_time,Ln,Value}|Acc];
	 ({"creationdate",Ln,Value},Acc) ->
	      [{create_date,Ln,Value}|Acc];
	 ({"createdby",Ln,Value},Acc) ->
	      [{created_by,Ln,Value}|Acc];
	 ({"modificationtime",Ln,Value},Acc) ->
	      [{modification_time,Ln,Value}|Acc];
	 ({"modificationdate",Ln,Value},Acc) ->
	      [{modification_date,Ln,Value}|Acc];
	 ({"modifiedby",Ln,Value},Acc) ->
	      [{modified_by,Ln,Value}|Acc];
	 ({"lasteds",Ln,Name},Acc) ->  %% DCF
	      [{last_eds,Ln,Name}|Acc];
	 ({Key,Ln,_Value}, Acc) ->
	      io:format("~s:~w: keyword ~s not recoginsed in FileInfo\n",
			[File,Ln,Key]),
	      Acc
      end, [], Ents).
%%
%% [DeviceInfo] section
%%
device_info(File,Ents) ->
    foldr(
      fun({"vendorname",Ln,Name}, Acc) ->
	      [{vendor_name,Ln,Name}|Acc];
	 ({"vendornumber",Ln,Value}, Acc) ->
	      %% identity sub 1
	      parse_unsigned32(File,Ln,vendor_number,Value,Acc);
	 ({"productname",Ln,Value}, Acc) ->
	      [{product_name,Ln,Value}|Acc];
	 ({"productnumber",Ln,Value},Acc) ->
	      %% identity sub 2
	      parse_unsigned32(File,Ln,product_number,Value,Acc);
	 ({"revisionnumber",Ln,Value},Acc) ->
	      %% identity sub 3
	      parse_unsigned32(File,Ln,revision_number,Value,Acc);
	 ({"ordercode",Ln,Code}, Acc) ->
	      [{order_code,Ln,Code}|Acc];
	 ({"baudrate_10",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,baudrate__10,Value,Acc);
	 ({"baudrate_20",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,baudrate__20,Value,Acc);
	 ({"baudrate_50",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,baudrate__50,Value,Acc);
	 ({"baudrate_125",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,baudrate__125,Value,Acc);
	 ({"baudrate_250",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,baudrate__250,Value,Acc);
	 ({"baudrate_500",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,baudrate__500,Value,Acc);
	 ({"baudrate_800",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,baudrate__800,Value,Acc);
	 ({"baudrate_1000",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,baudrate__1000,Value,Acc);
	 ({"simplebootupmaster",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,simple_bootup_master,Value,Acc);
	 ({"simplebootupslave",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,simple_bootup_slave,Value,Acc);
	 ({"granularity",Ln,Value}, Acc) ->
	      parse_unsigned8(File,Ln,granularity,Value,Acc);
	 ({"dynamicchannelssupported",Ln,Value},Acc) ->
	      [{dynamic_channels_supported,Ln,Value}|Acc];
	 ({"groupmessaging",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,group_messaging,Value,Acc);
	 ({"nrofrxpdo",Ln,Value}, Acc) ->
	      parse_unsigned8(File,Ln,nr_of_rx_pdo,Value,Acc);
	 ({"nroftxpdo",Ln,Value}, Acc) ->
	      parse_unsigned8(File,Ln,nr_of_tx_pdo,Value,Acc);
	 ({"lss_supported",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,lss_supported,Value,Acc);
	 ({"compactpdo",Ln,Value}, Acc) ->
	      parse_unsigned8(File,Ln,compact_pdo,Value,Acc);
	 ({"compactsubobj",Ln,Value},Acc) ->
	      parse_unsigned8(File,Ln,compact_sub_obj,Value,Acc);
	 ({Key,Ln,_Value}, Acc) ->
	      io:format("~s:~w: keyword ~s not recoginsed in DeviceInfo\n",
			[File,Ln,Key]),
	      Acc
      end, [], Ents).

%%
%% [DummyUsage]
%%
dummy_usage(File,Ents) ->
    foldr(
      fun
	  ({"dummy"++[A,B,C,D],Ln,Value},Acc) when ?is_hex4(A,B,C,D) ->
	      Dummy = erlang:list_to_integer([A,B,C,D], 16),
	      parse_bool(File,Ln,Dummy,Value,Acc);
	  ({Key,Ln,_Value}, Acc) ->
	      io:format("~s:~w: keyword ~s not recoginsed in Dummy\n",
			[File,Ln,Key]),
	      Acc
      end, [], Ents).
	
	
    
%%
%% [DeviceComissioning] section DFC
%%
device_comissioning(File,Ents) ->
    foldr(
      fun
	  ({"nodeid",Ln,Value}, Acc) ->
	      parse_unsigned8(File,Ln,node_id,Value,Acc);
	  ({"nodename",Ln,Value}, Acc) ->
	      [{node_name,Ln,Value}|Acc];
	  ({"baudrate",Ln,Value}, Acc) ->
	      parse_unsigned16(File,Ln,baudrate,Value,Acc);
	  ({"netnumber",Ln,Value}, Acc) ->
	      parse_unsigned32(File,Ln,net_number,Value,Acc);
	  ({"networkname",Ln,Value},Acc) ->
	      %% max 243 chars
	      [{network_name,Ln,Value}|Acc];
	  ({"canopenmanager",Ln,Value},Acc) ->
	      parse_bool(File,Ln,canopen_manager,Value,Acc);
	  ({"lss_serialnumber",Ln,Value},Acc) ->
	      %% identity sub 4
	      parse_unsigned32(File,Ln,lss_serialnumber,Value,Acc);
	 ({Key,Ln,_Value}, Acc) ->
	      io:format("~s:~w: keyword ~s not recoginsed in DeviceComissioning\n",
			[File,Ln,Key]),
	      Acc
      end, [], Ents).
    
%%
%%  [XXXX]  object section
%%
object(File, Index, Ents) ->
    foldr(
      fun
	  ({"subnumber",Ln,Value}, Acc) ->
	      %% Number of IMPLEMENTED sub including 0
	      parse_unsigned8(File,Ln,sub_number,Value,Acc);
	 ({"parametername",Ln,Name}, Acc) ->
	      %% FIXME: Check range 0-241 chars
	      [{parameter_name,Ln,Name}|Acc];
	  ({"denotation",Ln,Name}, Acc) ->  %% DCF
	      [{denotation,Ln,Name}|Acc];
	 ({"parametervalue",Ln,Value},Acc) ->  % DCF
	      [{parameter_value,Ln,Value}|Acc];
	 ({"objecttype",Ln,Value}, Acc) ->
	      parse_unsigned8(File,Ln,object_type,Value,Acc);
	 ({"datatype",Ln,Value}, Acc) ->
	      parse_unsigned16(File,Ln,data_type,Value,Acc);	      
	 ({"lowlimit",Ln,Value}, Acc) ->
	      %% FIXME: next pass, depend on type
	      [{low_limit,Ln,Value}|Acc];
	 ({"highlimit",Ln,Value}, Acc) ->  
	      %% FIXME: next pass, depend on type
	      [{high_limit,Ln,Value}|Acc];
	 ({"accesstype",Ln,Value}, Acc) ->
	      %% ro,wo,rw,rwr,rww,const
	      [{access_type,Ln,Value}|Acc];
	 ({"defaultvalue",Ln,Value}, Acc) ->
	      [{default_value,Ln,Value} | Acc];
	 ({"pdomapping",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,pdo_mapping,Value,Acc);
	 ({"objflags",Ln,Value}, Acc) ->
	      %% unsigned32, 0x0,0x1,0x2,0x3
	      parse_unsigned32(File,Ln,obj_flags,Value,Acc);
	 ({"downloadfile",Ln,Name}, Acc) -> %% DCF
	      [{download_file,Ln,Name}|Acc];
	 ({"uploadfile",Ln,Name}, Acc) -> %% DCF
	      [{upload_file,Ln,Name}|Acc];
	 ({Key,Ln,_Value}, Acc) ->
	      io:format("~s:~w: keyword ~s not recoginsed in section ~4.16.0B\n",
			[File,Ln,Key,Index]),
	      Acc
      end, [], Ents).

%%
%%  [XXXXsubYY] object entry section
%%
sub(File, Index, Subind, Ents) ->
    foldr(
      fun ({"parametername",Ln,Name}, Acc) ->
	      %% FIXME: Check range 0-241 chars
	      [{parameter_name,Ln,Name}|Acc];
	  ({"denotation",Ln,Name}, Acc) ->  %% DCF
	      [{denotation,Ln,Name}|Acc];
	 ({"parametervalue",Ln,Value},Acc) ->  % DCF
	      [{parameter_value,Ln,Value}|Acc];
	  ({"objecttype",Ln,Value}, Acc) ->
	      parse_unsigned8(File,Ln,object_type,Value,Acc);
	  ({"datatype",Ln,Value}, Acc) ->
	      parse_unsigned16(File,Ln,data_type,Value,Acc);
	  ({"lowlimit",Ln,Value}, Acc) ->
	      [{low_limit,Ln,Value}|Acc];
	  ({"highlimit",Ln,Value}, Acc) ->
	      [{high_limit,Ln,Value}|Acc];
	  ({"accesstype",Ln,Value}, Acc) ->
	      %% ro,wo,rw,rwr,rww,const
	      [{access_type,Ln,Value}|Acc];
	  ({"defaultvalue",Ln,Value}, Acc) ->
	      [{default_value,Ln,Value} | Acc];
	  ({"pdomapping",Ln,Value}, Acc) ->
	      parse_bool(File,Ln,pdo_mapping,Value,Acc);
	  ({"objflags",Ln,Value}, Acc) ->
	      parse_unsigned32(File,Ln,obj_flags,Value,Acc);
	 ({"downloadfile",Ln,Name}, Acc) -> %% DCF
	      [{download_file,Ln,Name}|Acc];
	 ({"uploadfile",Ln,Name}, Acc) -> %% DCF
	      [{upload_file,Ln,Name}|Acc];
	  ({Key,Ln,_Value}, Acc) ->
	      io:format("~s:~w: keyword ~s not recoginsed in section ~4.16.0Bsub~2.16.0B\n",
			[File,Ln,Key,Index,Subind]),
	      Acc
      end, [], Ents).

%%
%% [XXXXNames]/[XXXXDenotation] section
%% CompactSubObj
%%
sub_names(File, Index, Entries) ->
    foldr(    
      fun({"nrofentries",Ln,Value},Acc) ->
	      parse_unsigned8(File,Ln,nr_of_entries,Value,Acc);
	 ({Key,Ln,Value},Acc) ->
	      try parse_unsigned(Key) of
		  K when K >= 1, K =< 254 ->
		      [{K,Value}|Acc];
		  _ ->
		      io:format("~s:~w: key ~s, is not in range [1-254]\n",
				[File,Ln,Key]),
		      Acc
	      catch
		  error:_ ->
		      io:format("~s:~w: keyword ~s not recoginsed in section ~4.16.0BName\n",
				[File,Ln,Key,Index]),
		      Acc
	      end
      end, [], Entries).

%%
%% [XXXXValues] section
%% CompactSubObj
%%
sub_values(File, Index, Entries) ->
    foldr(    
      fun({"nrofentries",Ln,Value},Acc) ->
	      parse_unsigned8(File,Ln,nr_of_entries,Value,Acc);
	 ({Key,Ln,Value},Acc) ->
	      try parse_unsigned(Key) of
		  K when K >= 1, K =< 254 ->
		      [{K,Value}|Acc];
		  _ ->
		      io:format("~s:~w: key ~s, is not in range [1-254]\n",
				[File,Ln,Key]),
		      Acc
	      catch
		  error:_ ->
		      io:format("~s:~w: keyword ~s not recoginsed in section ~4.16.0BValue\n",
				[File,Ln,Key,Index]),
		      Acc
	      end
      end, [], Entries).
%%
%% [MandatoryObjects]/[OptionalObjects]/[ManufacturerObjects]
%%
objects(File,Range,Entries) ->
    foldr(    
      fun({"supportedobjects",Ln,Value},Acc) ->
	      parse_unsigned16(File,Ln,supported_objects,Value,Acc);
	 ({Key,Ln,Value},Acc) ->
	      try parse_unsigned(Key) of
		  K when K >= 1, K =< 16#ffff ->
		      parse_unsigned(File,Ln,K,Value,unsinged16,Range,Acc);
		  _ ->
		      io:format("~s:~w: key ~s, is not in range [1-65535]\n",
				[File,Ln,Key]),
		      Acc
	      catch
		  error:_ ->
		      io:format("~s:~w: keyword ~s not recoginsed in objects section\n",
				[File,Ln,Key]),
		      Acc
	      end
      end, [], Entries). 

%%
%% [XXXXObjectLinks]
%%
objectlinks(File,Index,Entries) ->
    foldr(    
      fun({"objectlinks",Ln,Value},Acc) ->
	      parse_unsigned16(File,Ln,object_links,Value,Acc);
	 ({Key,Ln,Value},Acc) ->
	      try parse_unsigned(Key) of
		  K when K >= 1, K =< 16#ffff ->
		      parse_unsigned16(File,Ln,K,Value,Acc);
		  _ ->
		      io:format("~s:~w: key ~s, is not in range [1-65535]\n",
				[File,Ln,Key]),
		      Acc
	      catch
		  error:_ ->
		      io:format("~s:~w: keyword ~s not recoginsed in section ~4.16.0BObjectLinks\n",
				[File,Ln,Key,Index]),
		      Acc
	      end
      end, [], Entries). 

%% parse unsigned
parse_bool(File,Ln,Key,Value,Acc) ->
    parse_unsigned(File,Ln,Key,Value,boolean,[0,1],Acc).

parse_unsigned1(File,Ln,Key,Value,Acc) ->
    parse_unsigned(File,Ln,Key,Value,unsigned1,Acc).
parse_unsigned8(File,Ln,Key,Value,Acc) ->
    parse_unsigned(File,Ln,Key,Value,unsigned8,Acc).
parse_unsigned16(File,Ln,Key,Value,Acc) ->
    parse_unsigned(File,Ln,Key,Value,unsigned16,Acc).
parse_unsigned32(File,Ln,Key,Value,Acc) ->
    parse_unsigned(File,Ln,Key,Value,unsigned32,Acc).

parse_unsigned(File,Ln,Key,Value,unsigned1,Acc) ->
    parse_unsigned(File,Ln,Key,Value,unsigned1,[0,1],Acc);
parse_unsigned(File,Ln,Key,Value,unsigned8,Acc) ->
    parse_unsigned(File,Ln,Key,Value,unsigned8,[{0,16#ff}],Acc);
parse_unsigned(File,Ln,Key,Value,unsigned16,Acc) ->
    parse_unsigned(File,Ln,Key,Value,unsigned16,[{0,16#ffff}],Acc);
parse_unsigned(File,Ln,Key,Value,unsigned32,Acc) ->
    parse_unsigned(File,Ln,Key,Value,unsigned32,[{0,16#ffffffff}],Acc).

parse_unsigned(File,Ln,Key,Value,Type,Range,Acc) ->
    try parse_unsigned(Value) of
	V ->
	    case in_range(V,Range) of
		true ->
		    [{Key,V}|Acc];
		false ->
		    io:format("~s:~w: value [~s] for ~s is out of range ~s (~s)\n",
			      [File,Ln,Value,format_key(Key),format_range(Range),Type]),
		    Acc
	    end
    catch
	error:_ ->
	    io:format("~s:~w: value [~s] for ~s is not a number (~s)\n",
		      [File,Ln,Value,format_key(Key),Type]),
	    Acc
    end.

parse_unsigned("0") -> 
    0;
parse_unsigned("0x"++Value) ->
    erlang:list_to_integer(Value, 16);
parse_unsigned("0"++Value) ->
    erlang:list_to_integer(Value, 8);
parse_unsigned(Value=[C|_]) when ?is_dig(C) ->
    erlang:list_to_integer(Value, 10).

format_key(Key) when is_integer(Key) ->
    integer_to_list(Key);
format_key(pdo_mapping) -> "PDOMapping";
format_key(Key) when is_atom(Key) ->
    [C|Cs] = atom_to_list(Key),
    [string:to_upper(C)|format_name(Cs)].

format_name([$_,C|Cs]) ->
    [string:to_upper(C)|format_name(Cs)];
format_name([C|Cs]) ->
    [C|format_name(Cs)];
format_name([]) ->
    [].

in_range(V, [{Min,Max}|_]) when V >= Min, V =< Max -> true;
in_range(V, [V|_]) -> true;
in_range(V, [_|Rs]) -> in_range(V, Rs);
in_range(_V, []) -> false.


format_range([R]) ->
    format_interval(R);
format_range([R|Rs]) ->
    [format_interval(R),"," | format_range(Rs)];
format_range([]) ->
    [].

format_interval({A,B}) ->
    [erlang:integer_to_list(A,16),$H,"-",erlang:integer_to_list(B,16),$H];
format_interval(A) when is_integer(A) ->
    [erlang:integer_to_list(A,16),$H].
	

join_section(undefined,_Ln,_,Acc) ->
    Acc;
join_section(Name,Ln,Entries,Acc) ->
    [{Name,Ln,reverse(Entries)} |Acc].

trim(Cs) ->
    trim_trailing(trim_leading(Cs)).

trim_trailing(Cs) ->
    reverse(trim_leading(reverse(Cs))).

trim_leading([$\s|Cs]) -> trim_leading(Cs);
trim_leading([$\t|Cs]) -> trim_leading(Cs);
trim_leading([$\n|Cs]) -> trim_leading(Cs);
trim_leading([$\r|Cs]) -> trim_leading(Cs);
trim_leading(Cs) -> Cs.
    
			    
			    
