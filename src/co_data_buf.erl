%%%-------------------------------------------------------------------
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2011, Marina Westman Lönne
%%% @doc
%%%
%%% @end
%%% Created : 12 Dec 2011 
%%%-------------------------------------------------------------------
-module(co_data_buf).

-include("canopen.hrl").
-include("co_app.hrl").
-include("co_debug.hrl").

%% API
-export([init/5,
	 open/2,
	 read/2,
	 write/4,
	 update/2,
	 load/1,
	 eof/1,
	 data_size/1]).

-record(co_data_buf,
	{
	  access          ::atom(),
	  data = (<<>>)   ::binary(),
	  i               ::{integer(), integer()},
	  type = undefined::integer(),
	  size = 0        ::integer(),
	  buf_size = 0    ::integer(),
	  load_level      ::integer(),
	  tmp = (<<>>)    ::binary(),
	  write_size = 0  ::integer(),
	  pid             ::pid(),
	  ref             ::reference(),
	  mode = undefined::term(),
	  eof = false     ::boolean()
	}).


%%%===================================================================
%%% API
%%%===================================================================
-spec init(read | write, Pid::pid(), Entry::#app_entry{}, BufSize::integer(), LLevel::integer()) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {ok, Mref::reference(), Buf::#co_data_buf{}} |
		  {error, Error::atom()};
	  (read | write, Dict::term(), Entry::#dict_entry{}, BufSize::integer(), LLevel::integer()) -> 
		  {ok, Buf::#co_data_buf{}} |
		  {error, Error::atom()}.

init(Access, Pid, E=#app_entry{index = I, type = Type, transfer = M}, 
     BSize, LLevel) ->
    ?dbg(data_buf, 
	 "init: access = ~p, i = ~p, type = ~p, mode = ~p, blocksize = ~p, load_level ~p",
	 [Access, I, Type, M, BSize, LLevel]),
    init_i(Access, Pid, E, BSize, LLevel).

init_i(read, Pid, #app_entry{index = I, type = Type, transfer = {value, Value} = M},
     BSize, LLevel) ->
    Data = co_codec:encode(Value, Type),
    open(read, #co_data_buf {access = read,
			  pid = Pid,
			  i = I,
			  data = Data,
			  size = size(Data),
			  eof = true,
			  type = Type,
			  buf_size = BSize,
			  load_level = LLevel,
			  mode = M});
init_i(Access, Pid, #app_entry{index = I, type = Type, transfer = Mode}, BSize, LLevel) ->
    open(Access, #co_data_buf {access = Access,
			    pid = Pid,
			    i = I,
			    type = Type,
			    eof = false,
			    buf_size = BSize,
			    load_level = LLevel,
			    mode = Mode});
init_i(read, Dict, #dict_entry{index = I, type = Type, value = Value}, BSize, LLevel) ->
    Data = co_codec:encode(Value, Type),
    {ok, #co_data_buf {access = read,
		    i = I,
		    type = Type,
		    data = Data,
		    size = size(Data),
		    eof = true,
		    buf_size = BSize,
		    load_level = LLevel,
		    mode = {dict, Dict}}}.

    

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec open(read | write, Buf::#co_data_buf{}) -> {ok, NewBuf::#co_data_buf{}} |
						 {ok, NewBuf::#co_data_buf{}, Mref::reference()} |
						 {error, Error::atom()}. 

open(Access, Buf=#co_data_buf {pid = Pid, i = I, mode = M})  ->
    ?dbg(data_buf, "open: access = ~p, pid = ~p, i = ~p, mode = ~p", 
	 [Access, Pid, I, M]),
    open_i(Access, Buf).

open_i(read, Buf=#co_data_buf {pid = Pid, i = I, mode = atomic})  ->
    app_call(Buf#co_data_buf {eof = false, data = (<<>>)}, Pid, {get, I});
open_i(read, Buf=#co_data_buf {pid = Pid, i = I, mode = streamed}) ->
    %% Call app async
    Ref = make_ref(),
    app_call(Buf#co_data_buf {ref = Ref}, Pid, {read_begin, I, Ref});
open_i(read, Buf=#co_data_buf {pid = Pid, i = I, type = Type, mode = {atomic, Module}}) ->
    %% Call app sync
    case Module:get(Pid, I) of
	{ok, Value} -> 
	    Data = co_codec:encode(Value, Type),
	    {ok, Buf#co_data_buf {data = Data, 
			       size = size(Data),
			       eof = true}};
	Other ->
	    Other
    end;
open_i(read, Buf=#co_data_buf {pid = Pid, i = I, mode = {streamed, Module}}) ->
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
open_i(write, Buf=#co_data_buf {pid = Pid, i = I, mode = {streamed, Module}}) ->
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
%% @end
%%--------------------------------------------------------------------
-spec load(Buf::#co_data_buf{}) -> {ok, NewBuf::#co_data_buf{}} |
				   {error, Error::atom()}.
		  
load(Buf) when is_record(Buf, co_data_buf) ->
    ?dbg(data_buf, "load: available data = ~p, load_level = ~p", 
	 [size(Buf#co_data_buf.data),  Buf#co_data_buf.load_level]),
    if size(Buf#co_data_buf.data) =< Buf#co_data_buf.load_level andalso
       Buf#co_data_buf.eof =/= true ->
	    %% Time to fech more data
	    ?dbg(data_buf, "load: loading",[]), 
	    read_app_call(Buf);
       true ->
	    {ok, Buf}
    end.
	    

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec read(Buf::#co_data_buf{}, Bytes::integer) -> 
		  {ok, Data::binary(), EofFlag::boolean(), NewBuf::#co_data_buf{}} |
		  {ok, Mref::reference()} |
		  {error, Error::atom()}.

read(Buf, Bytes) when is_record(Buf, co_data_buf) ->
    ?dbg(data_buf, "read: Bytes = ~p", [Bytes]),
    if Bytes =< size(Buf#co_data_buf.data) ->
	    %% Enough data is available
	    <<Data:Bytes/binary, NewData/binary>> = Buf#co_data_buf.data,
	    ?dbg(data_buf, "read: Data = ~p", [Data]),
	    {ok, Data, Buf#co_data_buf.eof andalso (size(NewData) =:= 0),
	     Buf#co_data_buf {data = NewData}};
       true ->
	    %% More data is asked for
	    if Buf#co_data_buf.eof =:= true ->
		    %% No more data to fetch
		    ?dbg(data_buf, "read: Data = ~p, Eod = true", 
			 [Buf#co_data_buf.data]),
		    {ok, Buf#co_data_buf.data, true, Buf};
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
		
read_app_call(Buf=#co_data_buf {pid=Pid, buf_size=BSize, ref=Ref, mode=streamed}) ->
    %% Async call
    app_call(Buf, Pid, {read, BSize, Ref});
read_app_call(Buf=#co_data_buf {pid=Pid, buf_size=BSize, ref=Ref, mode={streamed, Mod}}) ->
    %% Sync call
    Reply = Mod:read(Pid, BSize, Ref),
    update(Buf, Reply);
read_app_call(_Buf) ->
    %% Should not happen!!
    %% Later mode can be file, socket etc ... ??
    {error, ?abort_internal_error}.
	    
%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec write(Buf::#co_data_buf{}, Data::term(), EodFlag::boolean(), DownloadMode::atom()) ->
		   {ok, NewBuf::#co_data_buf{}} |
		   {ok, NewBuf::#co_data_buf{}, Mref::reference()} |
		   {error, Error::atom()}.

%%%% End of Data
%% Transfer == atomic
write(Buf=#co_data_buf {mode = atomic, pid = Pid, type = Type, data = OldData, 
		     tmp = TmpData, i = I}, 
      Data, true, segment) ->
    ?dbg(data_buf, "write: mode = atomic, Data = ~p, Eod = ~p", [Data, true]),
    %% All data received, time to transfer to app
    DataToSend = <<OldData/binary, TmpData/binary, Data/binary>>,
    {Value, _} = co_codec:decode(DataToSend, Type),
    ?dbg(data_buf, "write: set Value = ~p\n", [Value]),
    app_call(Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true} , 
	     Pid, {set, I, Value});
write(Buf=#co_data_buf {mode = atomic = Mode, pid = Pid, type = Type, data = Data, 
		     tmp = TmpData, i = I}, 
      N, true, block) ->
    ?dbg(data_buf, "write: mode = ~p, N = ~p, Eod = ~p", [Mode, N, true]),
    %% All data received, time to transfer to app
    Size = size(TmpData) - N,
    <<DataToAdd:Size/binary, _Filler:N/binary>> = TmpData,
    DataToSend = <<Data/binary, DataToAdd/binary>>,
    {Value, _} = co_codec:decode(DataToSend, Type),
    ?dbg(data_buf, "write: set  Value = ~p\n", [Value]),
    app_call(Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}, 
	     Pid, {set, I, Value});
write(Buf=#co_data_buf {mode = {atomic, Module} = Mode, pid = Pid, type = Type, 
		     data = OldData, tmp = TmpData, i = I}, 
      Data, true, segment) ->
    ?dbg(data_buf, "write: mode = ~p, Data = ~p, Eod = ~p", 
	 [Mode, Data, true]),
    %% All data received, time to transfer to app
    DataToSend = <<OldData/binary, TmpData/binary, Data/binary>>,
    {Value, _} = co_codec:decode(DataToSend, Type),
    ?dbg(data_buf, "write: set Value = ~p\n", [Value]),
    case Module:set(Pid, I, Value) of
	ok ->
	    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
	Other ->
	    Other
    end;
write(Buf=#co_data_buf {mode = {atomic, Module} = Mode, pid = Pid, type = Type, 
		     data = Data, tmp = TmpData, i = I}, 
      N, true, block) ->
    ?dbg(data_buf, "write: mode = ~p, N = ~p, Eod = ~p", [Mode, N, true]),
    %% All data received, time to transfer to app
    Size = size(TmpData) - N,
    <<DataToAdd:Size/binary, _Filler:N/binary>> = TmpData,
    DataToSend = <<Data/binary, DataToAdd/binary>>,
    {Value, _} = co_codec:decode(DataToSend, Type),
    ?dbg(data_buf, "write: set  Value = ~p\n", [Value]),
    case Module:set(Pid, I, Value) of
	ok ->
	    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
	Other ->
	    Other
    end;
%% Transfer == streamed
write(Buf=#co_data_buf {mode = streamed = Mode, pid = Pid, data = OldData, ref = Ref, 
		     tmp = TmpData}, 
      Data, true, segment) ->
    ?dbg(data_buf, "write: mode = ~p,  Data = ~p, Eod = ~p", [Mode, Data, true]),
    %% All data received, time to transfer rest to app
    DataToSend = <<OldData/binary, TmpData/binary, Data/binary>>,
    ?dbg(data_buf, "write: send Data = ~p\n", [DataToSend]),
    app_call(Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}, Pid, 
	     {write, Ref, DataToSend, true});
write(Buf=#co_data_buf {mode = streamed = Mode, pid = Pid, data = Data, ref = Ref, 
		     tmp = TmpData}, 
      N, true, block) ->
    ?dbg(data_buf, "write: mode = ~p,  N = ~p, Eod = ~p", [Mode, N, true]),
    %% All data received, time to transfer rest to app
    Size = size(TmpData) - N,
    <<DataToAdd:Size/binary, _Filler:N/binary>> = TmpData,
    DataToSend = <<Data/binary, DataToAdd/binary>>,
    ?dbg(data_buf, "write: send Data = ~p\n", [DataToSend]),
    app_call(Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}, Pid, 
	     {write, Ref, DataToSend, true});
write(Buf=#co_data_buf {mode = {streamed, Module} = Mode, pid = Pid, data = OldData, 
		     ref = Ref, tmp = TmpData}, 
      Data, true, segment) ->
    ?dbg(data_buf, "write: mode = ~p,  Data = ~p, Eod = ~p", [Mode, Data, true]),
    %% All data received, time to transfer rest to app
    DataToSend = <<OldData/binary, TmpData/binary, Data/binary>>,
    ?dbg(data_buf, "write: send Data = ~p\n", [DataToSend]),
    case Module:write(Pid, Ref, DataToSend, true) of
	{ok ,Ref} ->
	    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
	Other ->
	    Other
    end;
write(Buf=#co_data_buf {mode = {streamed, Module} = Mode, pid = Pid, data = Data, 
		     ref = Ref, tmp = TmpData}, 
      N, true, block) ->
    ?dbg(data_buf, "write: mode = ~p,  N = ~p, Eod = ~p", [Mode, N, true]),
    %% All data received, time to transfer rest to app
    Size = size(TmpData) - N,
    <<DataToAdd:Size/binary, _Filler:N/binary>> = TmpData,
    DataToSend = <<Data/binary, DataToAdd/binary>>,
    ?dbg(data_buf, "write: send Data = ~p\n", [DataToSend]),
    case Module:write(Pid, Ref, DataToSend, true) of
	{ok ,Ref} ->
	    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
	Other ->
	    Other
    end;
%% Transfer == dict
write(Buf=#co_data_buf {mode = {dict, Dict} = Mode, type = Type, data = OldData, 
		     i = {Index, SubInd}, tmp = TmpData}, 
      Data, true, segment) -> 
    ?dbg(data_buf, "write: mode = ~p, Data = ~p, Eod = ~p", [Mode, Data, true]),
    DataToSend = <<OldData/binary, TmpData/binary, Data/binary>>,
    {Value, _} = co_codec:decode(DataToSend, Type),
    ?dbg(data_buf, "write:store I = ~.16B:~.8B, Value = ~p\n", 
	 [Index, SubInd, Value]),
    co_dict:direct_set(Dict, Index, SubInd, Value),
    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
write(Buf=#co_data_buf {mode = {dict, Dict} = Mode, type = Type, data = Data, 
		     i = {Index, SubInd}, tmp = TmpData}, 
      N, true, block) -> 
    ?dbg(data_buf, "write: mode = ~p, N = ~p, Eod = ~p", [Mode, N, true]),
    Size = size(Data) - N,
    <<DataToAdd:Size/binary, _Filler:N/binary>> = TmpData,
    DataToSend = <<Data/binary, DataToAdd/binary>>,
    {Value, _} = co_codec:decode(DataToSend, Type),
    ?dbg(data_buf, "write: store I = ~.16B:~.8B, Value = ~p\n", 
	 [Index, SubInd, Value]),
    co_dict:direct_set(Dict, Index, SubInd, Value),
    {ok, Buf#co_data_buf {data = (<<>>), tmp = (<<>>), eof = true}};
%%%% Not End of Data
%% Transfer == streamed => maybe send
write(Buf=#co_data_buf {mode = streamed = Mode, pid = Pid, data = OldData, 
		     write_size = WSize, ref = Ref, tmp = TmpData}, 
      Data, false, _DownloadMode) ->
    ?dbg(data_buf, "write: mode = ~p, Data = ~p, Eod = ~p", [Mode, Data, false]),
    %% Not the last data, store it
    NewData = <<OldData/binary, TmpData/binary>>,
    if size(NewData) >= WSize ->
	    %% Time to send to app
	    <<TransferData:WSize/binary, RestData/binary>> = NewData,
	    ?dbg(data_buf, "write: send Data = ~p\n", [TransferData]),
	    app_call(Buf#co_data_buf {data = RestData, tmp = Data}, Pid, 
		     {write, Ref, TransferData, false});
       true ->
	    {ok, Buf#co_data_buf {data = NewData, tmp = Data}}
    end;
write(Buf=#co_data_buf {mode = {streamed, Module} = Mode, pid = Pid, data = OldData, 
		     write_size = WSize, ref = Ref, tmp = TmpData}, 
      Data, false, _DownloadMode) ->
    ?dbg(data_buf, "write: mode = ~p, Data = ~p, Eod = ~p", [Mode, Data, false]),
    %% Not the last data, store it
    NewData = <<OldData/binary, TmpData/binary>>,
    if size(NewData) >= WSize ->
	    %% Time to send to app
	    <<TransferData:WSize/binary, RestData/binary>> = NewData,
	    ?dbg(data_buf, "write: send Data = ~p\n", [TransferData]),
	    case Module:write(Pid, Ref, TransferData, false) of
		{ok, Ref} ->
		    {ok, Buf#co_data_buf {data = RestData, tmp = Data}};
		Other ->
		    Other
	    end;
       true ->
	    {ok, Buf#co_data_buf {data = NewData, tmp = Data}}
    end;
%% Transfer =/= streamed => just store
write(Buf=#co_data_buf {mode = Mode, data = OldData, tmp = TmpData}, 
      Data, false, _DownloadMode) ->
    ?dbg(data_buf, "write: mode = ~p, Data = ~p, Eod = ~p, storing", 
	 [Mode, Data, false]),
    %% Move old from temp and store new in temp
    NewData = <<OldData/binary, TmpData/binary>>,
    {ok, Buf#co_data_buf {data = NewData, tmp = Data}}.

    
  
%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec update(Buf::#co_data_buf{}, Reply::{ok, Value::term()} | 
					 {ok, Ref::reference(), Data::binary(), EofFlag::boolean()}) -> 
		    {ok, NewBuf::#co_data_buf{}} |
		    {error, Error::atom()}.
    

update(Buf, {ok, Ref}) when is_reference(Ref) ->
    ?dbg(data_buf, "update: Ref = ~p", [Ref]),
    case Buf#co_data_buf.ref of
	Ref ->  {ok, Buf};
	_OtherRef -> {error, ?abort_internal_error}
    end;
update(Buf=#co_data_buf {type = Type}, {ok, Value}) ->
    ?dbg(data_buf, "update: Value = ~p", [Value]),
    Data = co_codec:encode(Value, Type),
    {ok, Buf#co_data_buf {data = Data, 
		       size = size(Data),
		       eof = true}};
update(Buf=#co_data_buf {access = read}, {ok, Ref, Size}) ->
    ?dbg(data_buf, "update: Ref = ~p, Size = ~p", [Ref, Size]),
    case Buf#co_data_buf.ref of
	Ref ->  {ok, Buf#co_data_buf {size=Size}};
	_OtherRef -> {error, ?abort_internal_error}
    end;
update(Buf=#co_data_buf {access = write}, {ok, Ref, WSize}) ->
    ?dbg(data_buf, "update: Ref = ~p, WSize = ~p", [Ref, WSize]),
    case Buf#co_data_buf.ref of
	Ref ->  {ok, Buf#co_data_buf {write_size=WSize}};
	_OtherRef -> {error, ?abort_internal_error}
    end;
update(Buf=#co_data_buf {data = OldData}, {ok, Ref, Data, Eod}) ->
    ?dbg(data_buf, "update: Ref = ~p, Data ~p, Eod = ~p", [Ref, Data, Eod]),
    case Buf#co_data_buf.ref of
	Ref -> 
	    NewData = <<OldData/binary, Data/binary>>,
	    {ok, Buf#co_data_buf {data = NewData, eof = Eod}};
	_OtherRef -> 
	    {error, ?abort_internal_error}
    end;    
update(Buf, ok) ->
    {ok, Buf};
update(Buf, Other) ->
    ?dbg(data_buf, "update: Buf = ~p, Other = ~p", [Buf, Other]),
    %% Error replies
    Other.

	    

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec eof(Buf::#co_data_buf{}) -> boolean().

eof(Buf) when is_record(Buf, co_data_buf) ->
    Buf#co_data_buf.eof.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec data_size(Buf::#co_data_buf{}) -> integer().

data_size(Buf) ->
    Buf#co_data_buf.size.

%%%===================================================================
%%% Internal functions
%%%===================================================================


app_call(Buf, Pid, Msg) ->
    case catch do_call(Pid, Msg) of 
	{'EXIT', Reason} ->
	    io:format("app_call: catch error ~p\n",[Reason]), 
	    {error, ?abort_internal_error};
	Mref ->
	    {ok, Buf, Mref}
    end.


do_call(Process, Request) ->
    Mref = erlang:monitor(process, Process),

    erlang:send(Process, {'$gen_call', {self(), Mref}, Request}, [noconnect]),
    Mref.

