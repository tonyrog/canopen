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
%%% @author Malotte Westman Lonne <malotte@malotte.net>
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%% Intermediate data storage for an SDO session process.<br/>
%%% Responsible for setting up a connection to an application
%%% if needed.
%%% 
%%% File: co_data_buf.erl <br/>
%%% Created: 12 Dec 2011 by Malotte W Lonne
%%% @end
%%%-------------------------------------------------------------------
-module(co_data_buf).

-include("canopen.hrl").
-include("co_app.hrl").

%% API
-export([init/3, init/4, init/5,
	 read/2,
	 write/4,
	 update/2,
	 abort/2,
	 load/1,
	 eof/1,
	 data_size/1,
	 timeout/1]).

-record(co_data_buf,
	{
	  access           ::atom(),
	  data = (<<>>)    ::binary(),
	  i                ::{integer(), integer()},
	  type             ::integer() | undefined,
	  size = 0         ::non_neg_integer() | undefined,
	  buf_size = 0     ::non_neg_integer(),
	  load_level = 0   ::non_neg_integer(),
	  tmp = (<<>>)     ::binary(),
	  write_size = 0   ::non_neg_integer(),
	  pid              ::pid() | undefined,
	  ref              ::reference() | undefined,
	  mode             ::term(),
	  timeout          ::timeout() | undefined,
	  eof = false      ::boolean()
	}).


%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Initilizes the data buffer.
%% @end
%%--------------------------------------------------------------------
-spec init(read | write, 
	   Pid::pid(), Entry::#index_spec{}) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {ok, Mref::reference(), Buf::#co_data_buf{}} |
		  {error, Error::atom()};
	  (read | write, 
	   Dict::term(), Entry::#dict_entry{}) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {error, Error::atom()};
	  (read | write, 
	   Pid::pid(), {Data::binary(), I::{integer(),integer()}}) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {error, Error::atom()}.

init(Access, Pid, E) ->
    init(Access, Pid, E, undefined, undefined).

%%--------------------------------------------------------------------
%% @doc
%% Initilizes the data buffer.
%% @end
%%--------------------------------------------------------------------
-spec init(read | write, 
	   Pid::pid(), Entry::#index_spec{}, BufSize::integer()) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {ok, Mref::reference(), Buf::#co_data_buf{}} |
		  {error, Error::atom()};
	  (read | write, 
	   Dict::term(), Entry::#dict_entry{}, BufSize::integer()) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {error, Error::atom()};
	  (read | write, 
	   Pid::pid(), {Data::binary(), I::{integer(),integer()}},
	   BufSize::integer()) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {error, Error::atom()}.

init(Access, Pid, E, BSize) ->
    init(Access, Pid, E, BSize, undefined).

%%--------------------------------------------------------------------
%% @doc
%% Initilizes the data buffer.
%% @end
%%--------------------------------------------------------------------
-spec init(read | write, 
	   Pid::pid(), Entry::#index_spec{}, 
	   BufSize::integer(), LLevel::integer()) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {ok, Mref::reference(), Buf::#co_data_buf{}} |
		  {error, Error::atom()};
	  (read | write, 
	   Dict::term(), Entry::#dict_entry{}, 
	   BufSize::integer(), LLevel::integer()) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {error, Error::atom()};
	  (read | write, 
	   Pid::pid(), {Data::binary(), I::{integer(),integer()}},
	   BufSize::integer(), LLevel::integer()) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {error, Error::atom()}.

init(Access, Pid, E, BSize, LLevel) ->
    lager:debug("init: e = ~w,\n access = ~p, blocksize = ~p, load_level ~p",
	 [E, Access, BSize, LLevel]),
    init_i(Access, Pid, E, BSize, LLevel).

init_i(read, Pid, 
       #index_spec{index = I, type = Type, transfer = {value, Value} = M, timeout = Tout},
     BSize, LLevel) when is_pid(Pid) ->
    try co_codec:encode(Value, Type) of
	Data ->
	    open(read, #co_data_buf {access = read,
				     pid = Pid,
				     i = I,
				     data = Data,
				     size = size(Data),
				     eof = true,
				     type = Type,
				     buf_size = BSize,
				     load_level = LLevel,
				     mode = M,
				     timeout = Tout})
    catch
	error:_Reason ->
	    lager:debug([{index, I}], "init: encode of = ~p, ~p failed, Reason = ~p", 
		 [Value,  Type, _Reason]),
	    {error, ?abort_value_range_error}
    end;

init_i(read, Pid, 
       #index_spec{index = {Ix, Si} = I, type = Type, 
		   transfer = {dict, Dict} = M, timeout = Tout},
       BSize, LLevel) when is_pid(Pid) ->
    %% Fetch data from dictionary
    {ok, Value} = co_dict:value(Dict, Ix, Si),
    try co_codec:encode(Value, Type) of
	Data ->
	    open(read, #co_data_buf {access = read,
				     pid = Pid,
				     i = I,
				     data = Data,
			     size = size(Data),
				     eof = true,
				     type = Type,
				     buf_size = BSize,
				     load_level = LLevel,
				     mode = M,
				     timeout = Tout})
    catch
	error:_Reason ->
	    lager:debug([{index, I}], "init: encode of = ~p, ~p failed, Reason = ~p", 
		 [Value,  Type, _Reason]),
	    {error, ?abort_value_range_error}
    end;

init_i(Access, Pid, #index_spec{index = I, type = Type, 
				transfer = Mode, timeout = Tout}, 
       BSize, LLevel)  when is_pid(Pid) ->
    open(Access, #co_data_buf {access = Access,
			       pid = Pid,
			       i = I,
			       type = Type,
			       eof = false,
			       buf_size = BSize,
			       load_level = LLevel,
			       mode = Mode,
			       timeout = Tout});
init_i(read, Dict, #dict_entry{index = I, type = Type, data = Data}, 
       BSize, LLevel) ->
    {ok, #co_data_buf {access = read,
		       i = I,
		       type = Type,
		       data = Data,
		       size = size(Data),
		       eof = true,
		       buf_size = BSize,
		       load_level = LLevel,
		       mode = {dict, Dict}}};

init_i(write, Dict, #dict_entry{index = I, type = Type}, BSize, LLevel) ->
    {ok, #co_data_buf {access = write,
		       i = I,
		       type = Type,
		       eof = true,
		       buf_size = BSize,
		       load_level = LLevel,
		       mode = {dict, Dict}}};
init_i(write, Pid, {Data, I, Client}, BSize, LLevel) when is_binary(Data) ->
    {ok, #co_data_buf {access = write,
		       i = I,
		       pid = Pid,
		       data = Data,
		       size = size(Data),
		       eof = true,
		       buf_size = BSize,
		       load_level = LLevel,
		       mode = {data, Client}}};
init_i(Access, Pid, {Data, I}, BSize, LLevel) when is_binary(Data) ->
    {ok, #co_data_buf {access = Access,
		       i = I,
		       pid = Pid,
		       data = Data,
		       size = size(Data),
		       eof = true,
		       buf_size = BSize,
		       load_level = LLevel,
		       mode = data}}.


    

%%--------------------------------------------------------------------
%% @doc
%% If needed sets up connection to application.
%% @end
%%--------------------------------------------------------------------
-spec open(read | write, Buf::#co_data_buf{}) -> {ok, NewBuf::#co_data_buf{}} |
						 {ok, NewBuf::#co_data_buf{}, 
						  Mref::reference()} |
						 {error, Error::atom()}. 

open(Access, Buf=#co_data_buf {pid = _Pid, i = _I, mode = _M})  ->
    lager:debug([{index, _I}], "open: access = ~p, pid = ~p, i = ~p, mode = ~w", 
	 [Access, _Pid, _I, _M]),
    open_i(Access, Buf).

open_i(read, Buf=#co_data_buf {pid = Pid, i = I, mode = atomic})  ->
    app_call(Buf#co_data_buf {eof = false, data = (<<>>)}, Pid, {get, I});
open_i(read, Buf=#co_data_buf {pid = Pid, i = I, mode = streamed}) ->
    %% Call app async
    Ref = make_ref(),
    app_call(Buf#co_data_buf {ref = Ref}, Pid, {read_begin, I, Ref});
open_i(read, Buf=#co_data_buf {pid = Pid, i = I, type = Type, 
			       mode = {atomic, Module}}) ->
    %% Call app sync
    case Module:get(Pid, I) of
	{ok, Value} -> 
	    try co_codec:encode(Value, Type) of
		Data ->
		    {ok, Buf#co_data_buf {data = Data, 
					  size = size(Data),
					  eof = true}}
	    catch
		error:_Reason ->
		    lager:debug([{index, I}], 
			 "open: encode of = ~p, ~p failed, Reason = ~p", 
			 [Value,  Type, _Reason]),
		    {error, ?abort_value_range_error}
	    end;
	Other ->
	    Other
    end;
open_i(read, Buf=#co_data_buf {pid = Pid, i = I, 
			       mode = {streamed, Module}}) ->
    %% Call app sync
    Ref = make_ref(),
    case Module:read_begin(Pid, I, Ref) of
	{ok, Ref, Size} ->
	    {ok, Buf#co_data_buf {ref = Ref, size = Size}};
	Other ->
	    Other
    end;
open_i(read, Buf=#co_data_buf {mode = {dict, _Dict}}) ->
    %% All data already fetched
    {ok, Buf};
open_i(read, Buf=#co_data_buf {mode = {value, _Value}}) ->
    %% All data already fetched
    {ok, Buf};
open_i(write, Buf=#co_data_buf {pid = Pid, i = I, mode = streamed}) ->
    %% Call app async
    Ref = make_ref(),
    app_call(Buf#co_data_buf {ref = Ref}, Pid, {write_begin, I, Ref});
open_i(write, Buf=#co_data_buf {pid = Pid, i = I, 
				mode = {streamed, Module}}) ->
    %% Call app sync
    Ref = make_ref(),
    case Module:write_begin(Pid, I, Ref) of
	{ok, Ref, WriteBufSize} ->
	    {ok, Buf#co_data_buf {ref = Ref, write_size = WriteBufSize}};
	Other ->
	    Other
    end;
open_i(write, Buf) ->
    {ok, Buf}.

%%--------------------------------------------------------------------
%% @doc
%% If needed fetch data from an application.
%% @end
%%--------------------------------------------------------------------
-spec load(Buf::#co_data_buf{}) -> {ok, NewBuf::#co_data_buf{}} |
				   {ok, NewBuf::#co_data_buf{}, 
				    Mref::reference()} |
				   {error, Error::atom()}.
		  
load(Buf=#co_data_buf {i = _I})  ->
    lager:debug([{index, _I}], "load: available data = ~w, load_level = ~p", 
	 [size(Buf#co_data_buf.data),  Buf#co_data_buf.load_level]),
    if size(Buf#co_data_buf.data) =< Buf#co_data_buf.load_level andalso
       Buf#co_data_buf.eof =/= true ->
	    %% Time to fech more data
	    lager:debug([{index, _I}], "load: loading",[]), 
	    read_app_call(Buf);
       true ->
	    {ok, Buf}
    end.
	    

%%--------------------------------------------------------------------
%% @doc
%% Reads data in the buffer.<br/>
%% If needed more data is fetched from the application.
%% @end
%%--------------------------------------------------------------------
-spec read(Buf::#co_data_buf{}, Bytes::integer) -> 
		  {ok, Data::binary(), EofFlag::boolean(), 
		   NewBuf::#co_data_buf{}} |
		  {ok, Mref::reference()} |
		  {error, Error::atom()}.

read(Buf=#co_data_buf {i = _I}, Bytes) ->
    lager:debug([{index, _I}], "read: Bytes = ~p", [Bytes]),
    if Bytes =< size(Buf#co_data_buf.data) ->
	    %% Enough data is available
	    <<Data:Bytes/binary, NewData/binary>> = Buf#co_data_buf.data,
	    lager:debug([{index, _I}], "read: Data = ~w", [Data]),
	    {ok, Data, Buf#co_data_buf.eof andalso (size(NewData) =:= 0),
	     Buf#co_data_buf {data = NewData, size = size(NewData)}};
       true ->
	    %% More data is asked for
	    if Buf#co_data_buf.eof =:= true ->
		    %% No more data to fetch
		    lager:debug([{index, _I}], "read: Data = ~w, Eod = true", 
			 [Buf#co_data_buf.data]),
		    {ok, Buf#co_data_buf.data, true, 
		     Buf#co_data_buf {data = (<<>>), size = 0}};
	       true ->
		    %% Get more data from app
		    case read_app_call(Buf) of
			{ok, Buf1} ->
			    %% Data has been fetched
			    read(Buf1, Bytes);
			Other ->
			      Other
		    end
	    end
    end.
		
read_app_call(Buf=#co_data_buf {pid=Pid, buf_size=BSize, ref=Ref, 
				mode=streamed}) ->
    %% Async call
    app_call(Buf, Pid, {read, Ref, BSize});
read_app_call(Buf=#co_data_buf {pid=Pid, buf_size=BSize, ref=Ref, 
				mode={streamed, Mod}}) ->
    %% Sync call
    Reply = Mod:read(Pid, Ref, BSize),
    update(Buf, Reply);
read_app_call(_Buf) ->
    %% Should not happen!!
    %% Later mode can be file, socket etc ... ??
    {error, ?abort_internal_error}.
	    
%%--------------------------------------------------------------------
%% @doc
%% Write data to the buffer.<br/>
%% If needed data is sent to the application.
%% @end
%%--------------------------------------------------------------------
-spec write(Buf::#co_data_buf{}, Data::term(), EodFlag::boolean(), 
	    DownloadMode::segment | block) ->
		   {ok, NewBuf::#co_data_buf{}} |
		   {ok, NewBuf::#co_data_buf{}, Mref::reference()} |
		   {error, Error::atom()}.

%%%% End of Data
%% Transfer == atomic
write(Buf=#co_data_buf {mode = atomic, pid = Pid, type = Type, data = OldData, 
		     tmp = TmpData, i = I}, 
      Data, true, segment) ->
    lager:debug([{index, I}], 
	 "write: mode = atomic, Data = ~w, Eod = ~p", [Data, true]),
    %% All data received, time to transfer to app
    DataToSend = <<OldData/binary, TmpData/binary, Data/binary>>,
    try co_codec:decode(DataToSend, Type) of
	Value ->
	    lager:debug([{index, I}], "write: set Value = ~p", [Value]),
	    app_call(Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true},
		     Pid, {set, I, Value})
    catch
	error:_Reason ->
	    lager:debug([{index, I}], "write: decode of = ~p, ~p failed, Reason = ~p", 
		 [DataToSend,  Type, _Reason]),
	    {error, ?abort_value_range_error}
    end;
		
write(Buf=#co_data_buf {mode = atomic = _Mode, pid = Pid, type = Type, 
			data = Data, tmp = TmpData, i = I}, 
      N, true, block) ->
    lager:debug([{index, I}], "write: mode = ~w, N = ~p, Eod = ~p", [_Mode, N, true]),
    %% All data received, time to transfer to app
    Size = size(TmpData) - N,
    <<DataToAdd:Size/binary, _Filler:N/binary>> = TmpData,
    DataToSend = <<Data/binary, DataToAdd/binary>>,
    try co_codec:decode(DataToSend, Type) of
	Value ->
	    lager:debug([{index, I}], "write: set  Value = ~p", [Value]),
	    app_call(Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true},
		     Pid, {set, I, Value})
   catch
	error:_Reason ->
	    lager:debug([{index, I}], "write: decode of = ~p, ~p failed, Reason = ~p", 
		 [DataToSend,  Type, _Reason]),
	    {error, ?abort_value_range_error}
    end;

write(Buf=#co_data_buf {mode = {atomic, Module} = _Mode, pid = Pid, type = Type, 
		     data = OldData, tmp = TmpData, i = I}, 
      Data, true, segment) ->
    lager:debug([{index, I}], "write: mode = ~w, Data = ~w, Eod = ~p", 
	 [_Mode, Data, true]),
    %% All data received, time to transfer to app
    DataToSend = <<OldData/binary, TmpData/binary, Data/binary>>,
    Value = co_codec:decode(DataToSend, Type),
    lager:debug([{index, I}], "write: set Value = ~p", [Value]),
    case Module:set(Pid, I, Value) of
	ok ->
	    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
	Other ->
	    Other
    end;
write(Buf=#co_data_buf {mode = {atomic, Module} = _Mode, pid = Pid, type = Type, 
		     data = Data, tmp = TmpData, i = I}, 
      N, true, block) ->
    lager:debug([{index, I}], "write: mode = ~w, N = ~p, Eod = ~p", [_Mode, N, true]),
    %% All data received, time to transfer to app
    Size = size(TmpData) - N,
    <<DataToAdd:Size/binary, _Filler:N/binary>> = TmpData,
    DataToSend = <<Data/binary, DataToAdd/binary>>,
    try co_codec:decode(DataToSend, Type) of
	Value ->
	    lager:debug([{index, I}], "write: set  Value = ~p", [Value]),
	    case Module:set(Pid, I, Value) of
		ok ->
		    {ok, Buf#co_data_buf {data = (<<>>), 
					  tmp = (<<>>), 
					  eof = true}};
		Other ->
		    Other
	    end
   catch
	error:_Reason ->
	    lager:debug([{index, I}], "write: decode of = ~p, ~p failed, Reason = ~p", 
		 [DataToSend,  Type, _Reason]),
	    {error, ?abort_value_range_error}
    end;

%% Transfer == streamed
write(Buf=#co_data_buf {mode = streamed = _Mode, pid = Pid, data = OldData, 
			ref = Ref, tmp = TmpData, i = I}, 
      Data, true, segment) ->
    lager:debug([{index, I}], "write: mode = ~p,  Data = ~p, Eod = ~p", 
	 [_Mode, Data, true]),
    %% All data received, time to transfer rest to app
    DataToSend = <<OldData/binary, TmpData/binary, Data/binary>>,
    lager:debug([{index, I}], "write: send Data = ~p", [DataToSend]),
    app_call(Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}, Pid, 
	     {write, Ref, DataToSend, true});
write(Buf=#co_data_buf {mode = streamed = _Mode, pid = Pid, data = Data, 
			ref = Ref, tmp = TmpData, i = I}, 
      N, true, block) ->
    lager:debug([{index, I}], "write: mode = ~w,  N = ~p, Eod = ~p", [_Mode, N, true]),
    %% All data received, time to transfer rest to app
    Size = size(TmpData) - N,
    <<DataToAdd:Size/binary, _Filler:N/binary>> = TmpData,
    DataToSend = <<Data/binary, DataToAdd/binary>>,
    lager:debug([{index, I}], "write: send Data = ~w", [DataToSend]),
    app_call(Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}, Pid, 
	     {write, Ref, DataToSend, true});
write(Buf=#co_data_buf {mode = {streamed, Module} = _Mode, pid = Pid, 
			data = OldData,  ref = Ref, tmp = TmpData, i = I}, 
      Data, true, segment) ->
    lager:debug([{index, I}], "write: mode = ~w,  Data = ~w, Eod = ~p", 
	 [_Mode, Data, true]),
    %% All data received, time to transfer rest to app
    DataToSend = <<OldData/binary, TmpData/binary, Data/binary>>,
    lager:debug([{index, I}], "write: send Data = ~w", [DataToSend]),
    case Module:write(Pid, Ref, DataToSend, true) of
	{ok ,Ref} ->
	    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
	Other ->
	    Other
    end;
write(Buf=#co_data_buf {mode = {streamed, Module} = _Mode, pid = Pid, 
			data = Data, ref = Ref, tmp = TmpData, i = I}, 
      N, true, block) ->
    lager:debug([{index, I}], "write: mode = ~w,  N = ~p, TmpData = ~w, Eod = ~p", 
	 [_Mode, N, TmpData, true]),
    %% All data received, time to transfer rest to app
    Size = size(TmpData) - N,
    <<DataToAdd:Size/binary, _Filler:N/binary>> = TmpData,
    DataToSend = <<Data/binary, DataToAdd/binary>>,
    lager:debug([{index, I}], "write: send Data = ~w", [DataToSend]),
    case Module:write(Pid, Ref, DataToSend, true) of
	{ok ,Ref} ->
	    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
	Other ->
	    Other
    end;
%% Transfer == dict
write(Buf=#co_data_buf {mode = {dict, Dict} = _Mode, data = OldData, 
		     i = {Index, SubInd} = I, tmp = TmpData}, 
      Data, true, segment) -> 
    lager:debug([{index, I}], "write: mode = ~w, Data = ~w, Eod = ~p", 
	 [_Mode, Data, true]),
    DataToSave = <<OldData/binary, TmpData/binary, Data/binary>>,
    co_dict:direct_set_data(Dict, Index, SubInd, DataToSave),
    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
		
write(Buf=#co_data_buf {mode = {dict, Dict} = _Mode, data = OldData, 
			i = {Index, SubInd} = I, tmp = TmpData}, 
      N, true, block) -> 
    lager:debug([{index, I}], "write: mode = ~w, N = ~p, TmpData = ~w, Eod = ~p", 
	 [_Mode, N, TmpData, true]),
    Size = size(TmpData) - N,
    <<DataToAdd:Size/binary, _Filler:N/binary>> = TmpData,
    DataToSave = <<OldData/binary, DataToAdd/binary>>,
    co_dict:direct_set_data(Dict, Index, SubInd, DataToSave),
    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
		
write(Buf=#co_data_buf {mode = {data, Client} = _Mode, data = OldData, 
			i = {_Index, _SubInd} = I, tmp = TmpData}, 
      Data, true, segment) -> 
    lager:debug([{index, I}], "write: mode = ~w, Data = ~w, Eod = ~p", 
	 [_Mode, Data, true]),
    DataToSend = <<OldData/binary, TmpData/binary, Data/binary>>,
    lager:debug([{index, I}], "write: reply to ~w I = ~.16B:~.8B, Data = ~p", 
	 [Client, _Index, _SubInd, DataToSend]),
    gen_server:reply(Client, {ok, DataToSend}),
    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};

%%%% Not End of Data
%% Transfer == streamed => maybe send
write(Buf=#co_data_buf {mode = streamed = _Mode, pid = Pid, data = OldData, 
			write_size = WSize, ref = Ref, tmp = TmpData, i = I}, 
      Data, false, _DownloadMode) ->
    lager:debug([{index, I}], "write: mode = ~w, Data = ~w, Eod = ~p", 
	 [_Mode, Data, false]),
    %% Not the last data, store it
    NewData = <<OldData/binary, TmpData/binary>>,
    if size(NewData) >= WSize ->
	    %% Time to send to app
	    <<TransferData:WSize/binary, RestData/binary>> = NewData,
	    lager:debug([{index, I}], "write: send Data = ~w", [TransferData]),
	    app_call(Buf#co_data_buf {data = RestData, tmp = Data}, Pid, 
		     {write, Ref, TransferData, false});
       true ->
	    {ok, Buf#co_data_buf {data = NewData, tmp = Data}}
    end;
write(Buf=#co_data_buf {mode = {streamed, Module} = _Mode, pid = Pid, 
			data = OldData,  write_size = WSize, ref = Ref, 
			tmp = TmpData, i = I}, 
      Data, false, _DownloadMode) ->
    lager:debug([{index, I}], "write: mode = ~w, Data = ~w, Eod = ~p", 
	 [_Mode, Data, false]),
    %% Not the last data, store it
    NewData = <<OldData/binary, TmpData/binary>>,
    if size(NewData) >= WSize ->
	    %% Time to send to app
	    <<TransferData:WSize/binary, RestData/binary>> = NewData,
	    lager:debug([{index, I}], "write: send Data = ~w", [TransferData]),
	    case Module:write(Pid, Ref, TransferData, false) of
		{ok, Ref} ->
		    {ok, Buf#co_data_buf {data = RestData, tmp = Data}};
		Other ->
		    Other
	    end;
       true ->
	    {ok, Buf#co_data_buf {data = NewData, tmp = Data}}
    end;
%% Transfer =/= streamed => check size limit and store if OK
write(Buf=#co_data_buf {mode = _Mode, data = OldData, tmp = TmpData, i = I}, 
      Data, false, BlockOrSegment) ->
    lager:debug([{index, I}], "write: mode = ~w, Data = ~w, Eod = ~p, storing", 
	 [_Mode, Data, false]),
    CheckLimitResult = check_limit(Buf, Data, BlockOrSegment),
    if CheckLimitResult == ok ->
	    %% Move old from temp and store new in temp
	    NewData = <<OldData/binary, TmpData/binary>>,
	    {ok, Buf#co_data_buf {data = NewData, tmp = Data}};
       true ->
	    CheckLimitResult
    end.

%% Check limit based on transfer mode and type
check_limit(Buf=#co_data_buf {mode = atomic}, Data, BlockOrSegment) ->
    check_limit_i(Buf, Data, BlockOrSegment);
check_limit(Buf=#co_data_buf {mode = {atomic, _M}}, Data, BlockOrSegment) ->
    check_limit_i(Buf, Data, BlockOrSegment);
check_limit(_Buf, _Data, _BlockOrSegment) ->
    ok.

check_limit_i(Buf=#co_data_buf {data = OldData, tmp = TmpData}, 
	      Data, BlockOrSegment) ->
    TypeSize = case Buf#co_data_buf.type of
		   undefined -> 0;
		   Type -> co_codec:bytesize(Type)
	       end,
    Limit = case TypeSize of
		0 -> Buf#co_data_buf.buf_size;
		TS -> TS
	    end,
    DataSize = case BlockOrSegment of
		   segment ->
		       size(OldData) + size(TmpData) + size(Data);
		   block ->
		       %% Part of last data might be removed 
		       size(OldData) + size(TmpData)
	       end,
    if DataSize > Limit ->
	    {error, ?abort_data_length_too_high};
       true ->
	    ok
    end.
 
%%--------------------------------------------------------------------
%% @doc
%% Update buffer with reply from application.
%% @end
%%--------------------------------------------------------------------
-spec update(Buf::#co_data_buf{}, 
	     Reply::{ok, Value::term()} | 
		    {ok, Size::integer() | undefined} |
		    {ok, Ref::reference()} | 
		    {ok, Ref::reference(), Size::integer()} |
		    {ok, Ref::reference(), WSize::integer()} | 
		    {ok, Ref::reference(), Data::binary(), Eof::boolean()} |
		    ok) -> 
		    {ok, NewBuf::#co_data_buf{}} |
		    {error, Error::atom()}.
    

update(Buf=#co_data_buf {i = I}, {ok, Ref}) when is_reference(Ref) ->
    lager:debug([{index, I}], "update: Ref = ~p", [Ref]),
    case Buf#co_data_buf.ref of
	Ref ->  {ok, Buf};
	_OtherRef -> {error, ?abort_internal_error}
    end;
update(Buf=#co_data_buf {access = read, type = Type, i = I}, {ok, Value}) ->
    lager:debug([{index, I}], "update: Value = ~p", [Value]),
    try co_codec:encode(Value, Type) of
	Data ->
	    {ok, Buf#co_data_buf {data = Data, 
				  size = size(Data),
				  eof = true}}
   catch
	error:_Reason ->
	    lager:debug([{index, I}], "update: decode of = ~p, ~p failed, Reason = ~p", 
		 [Value,  Type, _Reason]),
	    {error, ?abort_value_range_error}
    end;
		
update(Buf=#co_data_buf {access = write, i = I}, {ok, Size}) ->
    lager:debug([{index, I}], "update: Size = ~p", [Size]),
    {ok, Buf#co_data_buf {size = Size}};
update(Buf=#co_data_buf {access = read, i = I}, {ok, Ref, Size}) ->
    lager:debug([{index, I}], "update: Ref = ~p, Size = ~p", [Ref, Size]),
    case Buf#co_data_buf.ref of
	Ref ->  {ok, Buf#co_data_buf {size=Size}};
	_OtherRef -> {error, ?abort_internal_error}
    end;
update(Buf=#co_data_buf {access = write, i = I}, {ok, Ref, WSize}) ->
    lager:debug([{index, I}], "update: Ref = ~p, WSize = ~p", [Ref, WSize]),
    case Buf#co_data_buf.ref of
	Ref ->  {ok, Buf#co_data_buf {write_size=WSize}};
	_OtherRef -> {error, ?abort_internal_error}
    end;
update(Buf=#co_data_buf {data = OldData, i = I}, {ok, Ref, Data, Eod}) ->
    lager:debug([{index, I}], "update: Ref = ~p, Data ~w, Eod = ~p", [Ref, Data, Eod]),
    case Buf#co_data_buf.ref of
	Ref -> 
	    NewData = <<OldData/binary, Data/binary>>,
	    {ok, Buf#co_data_buf {data = NewData, eof = Eod}};
	_OtherRef -> 
	    {error, ?abort_internal_error}
    end;    
update(Buf, ok) ->
    {ok, Buf};
update(_Buf=#co_data_buf {i = I}, Other) ->
    lager:debug([{index, I}], "update: Buf = ~w, Other = ~p", [_Buf, Other]),
    %% Error replies
    Other.

	    

%%--------------------------------------------------------------------
%% @doc
%% If needed abort connection with application.
%% @end
%%--------------------------------------------------------------------
-spec abort(Buf::#co_data_buf{}, Reason::integer()) ->
		   ok.

abort(_Buf=#co_data_buf {mode = streamed, pid = Pid, ref = Ref, i = I}, 
      Reason) -> 
    lager:debug([{index, I}], "abort: Buf = ~w, Reason = ~p", [_Buf, Reason]),
    gen_server:cast(Pid, {abort, Ref, Reason});
abort(_Buf=#co_data_buf {mode = {streamed, Module}, pid = Pid, 
			 ref = Ref, i = I}, 
      Reason) -> 
    lager:debug([{index, I}], "abort: Buf = ~w, Reason = ~p", [_Buf, Reason]),
    Module:abort(Pid, Ref, Reason);
abort(_Buf, _Reason) -> 
    ok.
%%--------------------------------------------------------------------
%% @doc
%% Check if all data is received from application.
%% @end
%%--------------------------------------------------------------------
-spec eof(Buf::#co_data_buf{}) -> boolean().

eof(Buf) when is_record(Buf, co_data_buf) ->
    Buf#co_data_buf.eof.

%%--------------------------------------------------------------------
%% @doc
%% Get size of data in buffer.
%% @end
%%--------------------------------------------------------------------
-spec data_size(Buf::#co_data_buf{}) -> integer() | undefined.

data_size(Buf) ->
    Buf#co_data_buf.size.

%%--------------------------------------------------------------------
%% @doc
%% Get timeout from buffer.
%% @end
%%--------------------------------------------------------------------
-spec timeout(Buf::#co_data_buf{}) -> timeout().

timeout(Buf) ->
    Buf#co_data_buf.timeout.

%%%===================================================================
%%% Internal functions
%%%===================================================================


app_call(Buf, Pid, Msg) ->
    case catch do_call(Pid, Msg) of 
	{'EXIT', Reason} ->
	    ?ew("app_call: catch error ~p\n",[Reason]), 
	    {error, ?abort_internal_error};
	Mref ->
	    {ok, Buf, Mref}
    end.


do_call(Process, Request) ->
    Mref = erlang:monitor(process, Process),
    ok = erlang:send(Process, {'$gen_call', {self(), Mref}, Request}, 
		     [noconnect]),
    Mref.

