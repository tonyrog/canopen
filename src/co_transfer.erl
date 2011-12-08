%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%   Canopen data transfer functions
%%% @end
%%% Created :  4 Jun 2010 by Tony Rogvall <tony@rogvall.se>

-module(co_transfer).

-include_lib("can/include/can.hrl").
-include("canopen.hrl").
-include("sdo.hrl").
-include("co_app.hrl").

-export([write_begin/3, write/3, write_end/3]).
-export([write_data_begin/3]).
-export([write_max_size/2]).
-export([write_size/2]).
-export([write_data/2]).
-export([write_block_segment/3, write_block_segment_end/1,
	 write_block_end/5]).

-export([read_begin/3, read_block/2, read/2, read_from_app/2, read_end/1]).
-export([read_data_begin/4]).

-export([add_data/2, add_data/3]).
-export([add_bufdata/2, add_bufdata/3]).
-export([move_and_add_bufdata/2, move_and_add_bufdata/3]).
-export([update_data/2, update_data/3]).

-export([block_seqno/1]).
-export([max_size/1]).
-export([data_size/1]).
-export([bufdata_size/1]).
-export([type/1]).


-record(t_handle,
	{
	  storage,      %% copy of dictionary handle or pid
	  type,         %% item type
	  index,        %% item index
	  subind,       %% item sub-index
	  data,         %% item data
	  bufdata,      %% Buffered data, used when streaming blocks
	  size,         %% current item size
	  block=[],     %% block segment list [{1,Bin},...{127,Bin}]
	  max_size,     %% item max size
	  mode,         %% mode for transfer to application 
	  endf          %% transfer end callback
	}).
   
-define(is_seq(N), ((N) band -128)=:=0, (N) =/= 0).
-ifdef(debug).
-define(dbg(Fmt,As), io:format(Fmt, As)).
-else.
-define(dbg(Fmt, As), ok).
-endif.

%%
%% Start a write operation 
%% return
%%     {error, AbortCcode}
%%  |  {ok, Handle, MaxSize}
%%
%%
write_begin(Ctx, Index, SubInd) ->
    case co_node:reserver_with_module(Ctx#sdo_ctx.res_table, Index) of
	[] ->
	    ?dbg("~p: write_begin: No reserver for index ~7.16.0#\n", [?MODULE,Index]),
	    central_write_begin(Ctx, Index, SubInd);
	{Pid, Mod} when is_pid(Pid) ->
	    ?dbg("~p: write_begin: Process ~p has reserved index ~7.16.0#\n", 
		 [?MODULE, Pid, Index]),
	    app_write_begin(Index, SubInd, Pid, Mod);
	{dead, _Mod} ->
	    ?dbg("~p: write_begin: Reserver process dead.\n", [?MODULE]),
	    {error, ?abort_internal_error}; %% ???
	_Other ->
	    ?dbg("~p: write_begin: Other case = ~p\n", [?MODULE,_Other]),
	    {error, ?abort_internal_error}
    end.


central_write_begin(Ctx, Index, SubInd) ->
    Dict = Ctx#sdo_ctx.dict,
    case co_dict:lookup_entry(Dict, {Index,SubInd}) of
	Err = {error,_} ->
	    Err;
	{ok,E=#dict_entry{type=Type}} ->
	    if E#dict_entry.access =:= ?ACCESS_RO;
	       E#dict_entry.access =:= ?ACCESS_C ->
		    {error,?abort_write_not_allowed};
	       true ->
		    MaxSize = co_codec:bytesize(Type),
		    Handle = #t_handle { storage = Dict, type=Type,
					 index=Index, subind=SubInd,
					 data=(<<>>), size=0, 
					 max_size=MaxSize },
		    {ok, Handle, MaxSize}
	    end
    end.

app_write_begin(Index, SubInd, Pid, Mod) ->
    case Mod:get_entry(Pid, {Index, SubInd}) of
	{entry, Entry} ->
	    if (Entry#app_entry.access band ?ACCESS_WO) =:= ?ACCESS_WO ->
		    MaxSize = co_codec:bytesize(Entry#app_entry.type),
		    ?dbg("~p: app_write_begin: transfer=~p, type = ~p\n",
			 [?MODULE, Entry#app_entry.transfer, Entry#app_entry.type]),
		    app_transfer_begin(Entry#app_entry.transfer, 
				       Pid, {Index, SubInd}, MaxSize, 
				       Entry#app_entry.type);
	       true ->
		    {entry, ?abort_unsupported_access}
	    end;
	{error, Reason}  ->
	    {error, Reason}
    end.
    
app_transfer_begin(streamed, Pid, {Index, SubInd}, MaxSize, Type) ->
    Ref = make_ref(),
    case app_call(Pid, {write_begin, {Index, SubInd}, Ref}) of
	{ok, Mref} -> 
	    {ok, handle(Pid, {Index, SubInd}, MaxSize, Type, {streamed, Ref}), Mref};
	Other -> 
	    Other
    end;
app_transfer_begin(_T={streamed, Module},Pid,{Index, SubInd}, MaxSize, Type) ->
    ?dbg("~p: app_write_begin: Transfer mode = ~p\n", [?MODULE, _T]),    
    Ref = make_ref(),
    case Module:write_begin(Pid, {Index, SubInd}, Ref) of
	ok -> 
	    {ok, handle(Pid, {Index, SubInd}, MaxSize, Type, 
			{streamed, Module, Ref}), MaxSize};
	_Other -> 
	    {error, ?abort_internal_error}
    end;
app_transfer_begin(Other, Pid, {Index, SubInd}, MaxSize, Type) ->
    %% Atomic
    ?dbg("~p: app_write_begin: Transfer mode = ~p\n", [?MODULE, Other]),
    {ok, handle(Pid, {Index, SubInd}, MaxSize, Type, Other), MaxSize}.

handle(Pid, {Index, SubInd}, MaxSize, Type, Transfer) ->
    #t_handle { storage = Pid,  type=Type,
		index=Index, subind=SubInd,
		max_size=MaxSize,
		data=(<<>>), size=0,
		mode=Transfer }.

    
%% 
%%  Start a write operation with just a value no dictionary
%% 
write_data_begin(Index, SubInd, EndF) ->
    MaxSize = 0,
    Handle = #t_handle { index=Index, subind=SubInd,
			 data=(<<>>), size=0, 
			 max_size=MaxSize,
			 endf = EndF
		       },
    {ok, Handle, MaxSize}.

%%
%% Set maximum write size if not set already
%%
write_max_size(TH, Size) when TH#t_handle.max_size =:= Size ->
    TH;
write_max_size(TH, Size) when 
      TH#t_handle.size =:= 0; 
      TH#t_handle.max_size =:= undefined ->
    TH#t_handle { max_size=Size };
write_max_size(_TH, _Size) ->
    {error, ?abort_data_length_error}.

write_size(TH, Size) ->
    TH#t_handle {size=Size}.

write_data(TH, Data) ->
    TH#t_handle {data=Data}.

%% Write data
%%  return 
%%     {error, AbortCode}
%%   | {ok, Handle', NBytesWritten}
%%
write(Handle, Data, NBytes) ->
    ?dbg("~p: write: data = ~p, nbytes = ~p\n", [?MODULE, Data, NBytes]),
    <<Data1:NBytes/binary, _/binary>> = Data,
    NewSize = Handle#t_handle.size + NBytes,
    NewData = <<(Handle#t_handle.data)/binary, Data1/binary>>,
    if Handle#t_handle.max_size =:= 0;
       NewSize =< Handle#t_handle.max_size ->

	    %% Check if streaming to application
	    case Handle#t_handle.mode of
		{streamed, Ref} ->
		    gen_server:cast(Handle#t_handle.storage, {write, Ref, Data1});
		{streamed, Mod, Ref} ->
		    Mod:write(Handle#t_handle.storage, Ref, Data1);
		_Other ->
		    %% Atomic
		    do_nothing
	    end,
	    {ok, Handle#t_handle {size=NewSize, data=NewData}, NBytes};
       
       true ->
	    abort_transfer(Handle),
	    {error, ?abort_unsupported_access}

    end.

stream_data(Handle, Data) ->
    ?dbg("~p: stream_data: data = ~p\n", [?MODULE, Data]),
    case Handle#t_handle.mode of
	{streamed, Ref} ->
	    gen_server:cast(Handle#t_handle.storage, {write, Ref, Data}),
	    ok;
	{streamed, Mod, Ref} ->
	    Mod:write(Handle#t_handle.storage, Ref, Data),
	    ok;
	_Other ->
	    %% Should not happen
	    {error, ?abort_internal_error}
    end.



%% Write block segment data (7 bytes) Seq=1..127 
%% Imply that max block size 127*7 = 889 bytes
write_block_segment(Handle, Seq, Data) when ?is_seq(Seq),
					    byte_size(Data) =:= 7 ->
    Block = [{Seq,Data} | Handle#t_handle.block],
    ?dbg("~p: write_block_segment: data = ~p, size = ~p\n", 
	 [?MODULE, Data, Handle#t_handle.size]),
    {ok, Handle#t_handle { block = Block}, 7};
write_block_segment(Handle, _Seq, _Data) ->
    abort_transfer(Handle),
    {error, ?abort_invalid_sequence_number}.

%% Concatenate and write all segments
write_block_segment_end(TH) ->
    Bin = list_to_binary(lists:map(fun({_,Data}) -> Data end,
				   lists:reverse(TH#t_handle.block))),
    MaxSize = TH#t_handle.max_size,
    Size = byte_size(Bin),
    ?dbg("~p: write_block_segment_end: max=~w, bin=~p, szofbin=~w, size=~p\n", 
	 [?MODULE, MaxSize, Bin, Size, TH#t_handle.size]),
    case TH#t_handle.mode of
	{streamed, _Ref} ->
	    write_block_segment_end_streamed(TH, Bin, Size);
	{streamed, _Mod, _Ref} ->
	    write_block_segment_end_streamed(TH, Bin, Size);
	_Other ->
	    if MaxSize =:= 0 ->
		    write(TH#t_handle {block = []}, Bin, Size);
	       true ->
		    Remain = MaxSize - TH#t_handle.size,
		    if Remain =< 0 ->
			    abort_transfer(TH),
			    {error, ?abort_data_length_too_high};
		       Size =< Remain; (Size-Remain) < 7 ->
			    %% Add Bin to data
			    NewData = <<(TH#t_handle.data)/binary, Bin/binary>>,
			    NewSize = TH#t_handle.size + Size,
			    TH1 = TH#t_handle {size=NewSize,data=NewData,block=[]},
			    {ok, TH1, Size};
		       true ->
			    abort_transfer(TH),
			    {error, ?abort_data_length_too_high}
		    end		    
	    end
    end.

write_block_segment_end_streamed(TH, Bin, Size) ->
    if TH#t_handle.data =:= (<<>>) ->
	    %% First block end ??
	    %% Move bin to data
	    {ok, TH#t_handle {data = Bin, block = []}, Size};
       true ->
	    %% Consequtive blocks
	    %% Write data and move bin to data
	    Data = TH#t_handle.data,
	    TH1 = TH#t_handle {data = Bin, block = []},
	    stream_data(TH1, Data),
	    SentSize = TH#t_handle.size + size(Bin),
	    {ok ,TH1#t_handle {size = SentSize}, Size}
    end.

%% Handle the end of block data
%% Check CRC if needed.

write_block_end(Ctx,TH,N,CRC,CheckCrc) ->
    ?dbg("~p: write_block_end\n",[?MODULE]), 
    %% Check if streaming to application
    case TH#t_handle.mode of
	{streamed, _Ref} ->
	    write_block_end_streamed(Ctx,TH,N,CRC,CheckCrc);
	{streamed, _Mod, _Ref} ->
	    write_block_end_streamed(Ctx,TH,N,CRC,CheckCrc);
	_Other ->
	    write_block_end_atomic(Ctx,TH,N,CRC,CheckCrc)
    end.

write_block_end_streamed(Ctx,TH,N,CRC,CheckCrc) ->
    Size = size(TH#t_handle.data) - N,
    <<TruncData:Size/binary,_/binary>> = TH#t_handle.data,
    %% Write last stored buffer
    stream_data(TH, TruncData),
    %% CRC to be investigated ???
    SentSize = TH#t_handle.size + size(TruncData),
    write_end(Ctx, TH#t_handle {size = SentSize}, 0).

    
    
write_block_end_atomic(Ctx,Handle,N,CRC,CheckCrc) ->
    Handle1 =
	if N =:= 0 ->
		Handle;
	   true ->
		Size1 = Handle#t_handle.size - N,
		<<Data1:Size1/binary,_/binary>> = Handle#t_handle.data,
		Handle#t_handle { data=Data1, size=Size1 }
	end,

    if Handle1#t_handle.max_size > 0,
       Handle1#t_handle.size > Handle1#t_handle.max_size ->
	    abort_transfer(Handle1),
	    {error, ?abort_data_length_too_high};
       CheckCrc ->
	    _Data = Handle1#t_handle.data,
	    ?dbg("~p: write_block_end: data0=~p, size=~w, data=~p\n", 
		 [?MODULE, Handle#t_handle.data, size(_Data), _Data]),
	    
	    case co_crc:checksum(Handle1#t_handle.data) of
		CRC ->
		    write_end(Ctx, Handle1, N);
		_ ->
		    abort_transfer(Handle1),
		    {error, ?abort_crc_error}
	    end;
       true ->
	    write_end(Ctx, Handle1, N)
    end.
    

%% Finalize write
%%  return 
%%    {error, AbortCode}
%%  | ok
%%  | {ok, Data}   - no dictionary
%%
write_end(_Ctx, TH, _N) when TH#t_handle.storage == undefined ->
    (TH#t_handle.endf)(TH#t_handle.data);
write_end(Ctx, TH, N) ->
    ?dbg("~p: write_end: max_size=~p, size=~p, n=~p\n", 
	 [?MODULE, TH#t_handle.max_size, TH#t_handle.size, N]),
    if TH#t_handle.max_size =:= 0;
       TH#t_handle.size == TH#t_handle.max_size ->
	    Index = TH#t_handle.index,
	    SubInd = TH#t_handle.subind,
	    Value = case streaming(TH) of 
			false -> value(TH);
			true -> not_used
		    end,
	    case Value of
		{error, E} ->
		    {error, E};
		_OK ->
		    case TH#t_handle.storage of
			Pid when is_pid(Pid) ->
			    %% An application is responsible for the data
			    ?dbg("~p: write_end: To app ~.16B:~.8B\n", 
				 [?MODULE, Index, SubInd]),
			    %% Check if streaming to application
			    case TH#t_handle.mode of
				{streamed, Ref} ->
				    app_call(Pid, {write_end, Ref, N});
				{streamed, Mod, Ref} ->
				    Mod:write_end(Pid, Ref, N);
				atomic ->
				    app_call(Pid, {set, {Index, SubInd}, Value});
				{atomic, Module} ->
				    Module:set(Pid, {Index, SubInd}, Value)
			    end;
			Dict ->
			    ?dbg("~p: write_to_dict: ~.16B:~.8B, Value = ~p\n", 
				 [?MODULE, Index, SubInd, Value]),
			    Res = co_dict:direct_set(Dict, Index, SubInd, Value),
			    inform_subscribers(Index, Ctx),
			    Res
		    end
	    end;

       true ->
	    abort_transfer(TH),
	    {error, ?abort_data_length_too_low}
    end.

value(Handle) ->
    try co_codec:decode(Handle#t_handle.data, 
			Handle#t_handle.type) of
	{Value,_} ->
	    Value
    catch
	error:_ ->
	    abort_transfer(Handle),
	    {error, ?abort_internal_error}
    end.

inform_subscribers(I, Ctx) ->
    ?dbg("~s: inform_subscribers: Searching for subscribers for ~p\n", [?MODULE, I]),
    lists:foreach(
      fun(Pid) ->
	      ?dbg("~s: inform_subscribers: Sending object changed to ~p\n", 
		   [?MODULE, Pid]),
	      gen_server:cast(Pid, {object_changed, I}) 
      end,
      co_node:subscribers(Ctx#sdo_ctx.sub_table, I)).

%%
%% Start a read operation 
%% return
%%     {error, AbortCcode}
%%  |  {ok, Handle, MaxSize}
%%
%%

read_begin(Ctx, Index, SubInd) ->
    case co_node:reserver_with_module(Ctx#sdo_ctx.res_table, Index) of
	[] ->
	    ?dbg("~p: read_begin: No reserver for index ~7.16.0#\n", [?MODULE,Index]),
	    central_read_begin(Ctx, Index, SubInd);
	{Pid, Mod} when is_pid(Pid)->
	    ?dbg("~p: read_begin: Process ~p subscribes to index ~7.16.0#\n", 
		 [?MODULE, Pid, Index]),
	    app_read_begin(Index, SubInd, Pid, Mod);
	{dead, _Mod} ->
	    ?dbg("~p: read_begin: Reserver process dead.\n", [?MODULE]),
	    {error, ?abort_internal_error}; %% ???
	_Other ->
	    ?dbg("~p: read_begin: Other case = ~p\n", [?MODULE,_Other]),
	    {error, ?abort_internal_error}
    end.

central_read_begin(Ctx, Index, SubInd) ->
    Dict = Ctx#sdo_ctx.dict,
    case co_dict:lookup_entry(Dict, {Index,SubInd}) of
	Err = {error,_} ->
	    Err;
	{ok,E=#dict_entry{type=Type,value=Value}} ->
	    if E#dict_entry.access =:= ?ACCESS_WO ->
		    {error, ?abort_read_not_allowed};
	       true ->
		    ?dbg("~p: central_read_begin: Read access ok\n", [?MODULE]),
		    Data = co_codec:encode(Value, Type),
		    MaxSize = byte_size(Data),
		    TH = #t_handle { storage = Dict, type=Type,
				     index=Index, subind=SubInd,
				     data=Data, size=MaxSize,
				     max_size=MaxSize },

		    {ok, TH, MaxSize}
	    end
    end.

app_read_begin(Index, SubInd, Pid, Mod) ->
    case Mod:get_entry(Pid, {Index, SubInd}) of
	{entry, Entry} ->
	    if (Entry#app_entry.access band ?ACCESS_RO) =:= ?ACCESS_RO ->
		    ?dbg("~p: app_read_begin: Read access ok\n", [?MODULE]),
		    ?dbg("~p: app_read_begin: Transfer mode = ~p\n", 
			 [?MODULE, Entry#app_entry.transfer]),
		    TH = #t_handle { storage = Pid, bufdata=(<<>>),
				     index=Index, subind=SubInd,
				     type=Entry#app_entry.type
				   },

		    case Entry#app_entry.transfer of
			streamed -> 
			    Ref = make_ref(),
			    case app_call(Pid, {read_begin, {Index, SubInd}, Ref}) of
				{ok, Mref} -> 
				    {ok, TH#t_handle {mode = {streamed, Ref}}, Mref};
				Other ->
				    Other
			    end;
			{streamed, Module} -> 
			    Ref = make_ref(),
			    case Module:read_begin(Pid, {Index, SubInd}, Ref) of
				{ok, Ref, Size} ->
				    {ok, TH#t_handle {max_size=Size, size=Size,
						      mode={streamed, Module, Ref}},
				     Size};
				Other -> 
				    Other
			    end;
			atomic ->
			    case app_call(Pid, {get, {Index, SubInd}}) of
				{ok, Mref} -> 
				    {ok, TH#t_handle {mode = atomic}, Mref};
				Other -> 
				    Other
			    end;
			{atomic, Module} ->
			    case Module:get(Pid, {Index, SubInd}) of
				{ok, Value} ->
				    Data = co_codec:encode(Value, Entry#app_entry.type),
				    MaxSize = byte_size(Data),
				    {ok, TH#t_handle {data=Data, size=MaxSize,
						     max_size=MaxSize,
						     mode={atomic, Module}},
				     MaxSize};
				Other ->
				    Other
			    end;
			{value,Value} ->
			    Data = co_codec:encode(Value, Entry#app_entry.type),
			    MaxSize = byte_size(Data),
			    {ok, TH#t_handle {data=Data, size=MaxSize,
					      max_size=MaxSize,
					      mode=atomic},
			     MaxSize}
		    end;

	       true ->
		    {entry, ?abort_read_not_allowed}
	    end;
	Error ->
	    Error
    end.
	
%% 
%%  Start a read operation with just a value no dcitionary 
%% 
read_data_begin(Data, Index, SubInd, EndF) when is_binary(Data) ->
    MaxSize = byte_size(Data),
    TH = #t_handle { index=Index, subind=SubInd,
		     data=Data, size=MaxSize,
		     max_size=MaxSize,
		     endf = EndF
		   },
    {ok, TH, MaxSize}.

%%
%% Read at most NBytes from store
%% return:
%%    {error,AbortCode}
%% |  {ok,Handle',Data}
%%
read(Handle, NBytes) ->
    if is_integer(Handle#t_handle.size) andalso
       Handle#t_handle.size > 0 andalso
       Handle#t_handle.data =/= undefined ->
       	    read_from_handle(Handle, NBytes);
       true ->
	    case streaming(Handle) of
		true -> read_from_app(Handle, NBytes);
		false -> read_from_handle(Handle, NBytes)
	    end
    end.


read_from_handle(Handle, NBytes) ->
    ?dbg("~p: read_from_handle: NBytes = ~p, size = ~p, maxsize  = ~p, data = ~p\n", 
	 [?MODULE, NBytes, Handle#t_handle.size, Handle#t_handle.max_size, Handle#t_handle.data]),
    if NBytes =< Handle#t_handle.size ->
	    <<Data:NBytes/binary, NewData/binary>> = Handle#t_handle.data,
	    NewSize = Handle#t_handle.size - NBytes,
	    NewMax = case Handle#t_handle.max_size of
			     unknown -> unknown;
			     MaxSize -> MaxSize - NBytes
			 end,
	    {ok, Handle#t_handle { data=NewData, size=NewSize, max_size=NewMax }, Data};
       true ->
	    Data = Handle#t_handle.data,
	    {ok, Handle#t_handle { data=(<<>>), size=0, max_size=0}, Data }
    end.
	       
		           

read_from_app(Handle, NBytes) ->
    ?dbg("~p: read_from_app: NBytes = ~p, Mode = ~p\n", 
	 [?MODULE, NBytes, Handle#t_handle.mode]),
    case Handle#t_handle.mode of
	{streamed, Ref} ->
	    app_call(Handle#t_handle.storage, {read, NBytes, Ref});
	{streamed, Module, Ref} ->
	    case Module:read(Handle#t_handle.storage, NBytes, Ref) of
		{ok, Ref, Data} ->
		    Size = size(Data),
		    NewSize = case Handle#t_handle.size of
				  OldSize when is_integer(OldSize) -> 
				      OldSize - Size;
				  unknown -> unknown
			      end,
		    ?dbg("~p: read_from_app: data = ~p size = ~p, rem size = ~p\n", 
			 [?MODULE, Data, Size, NewSize]),
		    {ok, Handle#t_handle { size = NewSize , data = Data}, Data};
		Other ->
		    Other
	    end;
	_OtherMode -> 
	    ?dbg("~p: read_from_app: mode = ~p should not be possible\n",
		 [?MODULE, _OtherMode]),
	    {error, ?abort_internal_error}
    end.

read_block(Handle, NBytes) ->
    case Handle#t_handle.mode of
	{streamed, Ref} ->
	    app_call(Handle#t_handle.storage, {read, NBytes, Ref});
	{streamed, Module, Ref} ->
	    case Module:read(Handle#t_handle.storage, NBytes, Ref) of
		{ok, Ref, Data} ->
		    Size = size(Data),
		    NewSize = case Handle#t_handle.size of
				  OldSize when is_integer(OldSize) -> 
				      OldSize - Size;
				  unknown -> 
				      unknown
			      end,
		    ?dbg("~p: read_block: data = ~p size = ~p, rem size = ~p\n", 
			 [?MODULE, Data, Size, NewSize]),
		    {ok, Handle#t_handle { size = NewSize , data = Data}};
		Other ->
		    Other
			end;
	_OtherMode -> 
	    ?dbg("~p: read_block: mode = ~p should not be possible\n",
		 [?MODULE, _OtherMode]),
	    {error, ?abort_internal_error}
    end.



read_end(Handle) when Handle#t_handle.storage == undefined ->
    (Handle#t_handle.endf)(Handle#t_handle.data);
read_end(_Handle) ->
    ok.

true_streaming(TH) ->
    case {TH#t_handle.max_size, TH#t_handle.mode} of
	{0, {streamed, _Ref}} -> true;
	{0, {streamed, _Mod, _Ref}} -> true;
	_Other -> false
    end.
	     
streaming(TH) ->
    case TH#t_handle.mode of
	{streamed, _Ref} -> true;
	{streamed, _Mod, _Ref} -> true;
	_Other -> false
    end.
	     

%% Return the last received sequence number
block_seqno(Handle) ->
    case Handle#t_handle.block of
	[{Seq,_}|_] -> Seq;
	_ -> 0
    end.

max_size(Handle) ->
    Handle#t_handle.max_size.
    

data_size(Handle) ->
    Handle#t_handle.size.

bufdata_size(Handle) ->
    size(Handle#t_handle.bufdata).

type(Handle) ->
    Handle#t_handle.type.

add_data(TH, Data) when is_binary(Data) ->
    ?dbg("~p: add_data: Data = ~p, size = ~p\n",[?MODULE, Data, size(Data)]),
    TH#t_handle { data=Data, size=size(Data) }.


add_data(TH, Ref, Data) when is_binary(Data) ->
    case ref(TH) of
	Ref -> 
	    add_data(TH, Data);
	_OtherRef ->
	    {error, ?abort_internal_error}
    end.

add_bufdata(TH, Data) when is_binary(Data) ->
    ?dbg("~p: add_data: Data = ~p, size = ~p\n",[?MODULE, Data, size(Data)]),
    TH#t_handle { bufdata=Data }.


add_bufdata(TH, Ref, Data) when is_binary(Data) ->
    case ref(TH) of
	Ref -> 
	    add_data(TH, Data);
	_OtherRef ->
	    {error, ?abort_internal_error}
    end.

move_and_add_bufdata(TH, Data) when is_binary(Data) ->
    ?dbg("~p: move_and_add_data: Data = ~p, size = ~p\n",
	 [?MODULE, Data, size(Data)]),
    BufData = TH#t_handle.bufdata,
    TH#t_handle { data=BufData, size=size(BufData), bufdata=Data }.


move_and_add_bufdata(TH, Ref, Data) when is_binary(Data) ->
    case ref(TH) of
	Ref -> 
	    add_data(TH, Data);
	_OtherRef ->
	    {error, ?abort_internal_error}
    end.

update_data(TH, Data) when is_binary(Data) ->
    OldData = TH#t_handle.data,
    NewData = <<OldData/binary, Data/binary>>,
    TH#t_handle { data=NewData }. %% Size ?

update_data(TH, Ref, Data) when is_binary(Data) ->
    case ref(TH) of
	Ref -> 
	    update_data(TH, Data);
	_OtherRef ->
	    {error, ?abort_internal_error}
    end.

ref(TH) when is_record(TH, t_handle) ->
    case TH#t_handle.mode of
	{streamed, Ref} -> Ref;
	{streamed, _Mod, Ref} -> Ref
    end.
    


app_call(Pid, Msg) ->
    case catch do_call(Pid, Msg) of 
	{'EXIT', Reason} ->
	    io:format("app_call: catch error ~p\n",[Reason]), 
	    {error, ?abort_internal_error};
	Mref ->
	    {ok, Mref}
    end.


do_call(Process, Request) ->
    Mref = erlang:monitor(process, Process),

    erlang:send(Process, {'$gen_call', {self(), Mref}, Request}, [noconnect]),
    Mref.

abort_transfer(Handle) ->
    case Handle#t_handle.storage of
	Pid when is_pid(Pid) ->
	    case Handle#t_handle.mode of
		{streamed, Ref} ->
		    gen_server:cast(Pid, {abort, Ref});
		{streamed, Mod, Ref} ->
		    Mod:abort(Pid, Ref)
	    end;
	_Other ->
	    do_nothing
    end.
