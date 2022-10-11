%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2017, Tony Rogvall
%%% @doc
%%%     object definition database
%%% @end
%%% Created : 11 Oct 2016 by Tony Rogvall <tony@rogvall.se>
%%%-------------------------------------------------------------------
-module(co_objdef).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([object/1, object/3]).
-export([entry/2, entry/4]).
-export([enum/1, enum/3]).
-export([next/1, prev/1]).
-export([add_object/3, add_enum/3, add_index/4]).
-export([lookup_object/1]).
-export([commit/0]).
-export([load_file/1, load/1, load/2]).

%% gen_server callbacks
-export([init/1,
	 handle_call/3,
	 handle_cast/2,
	 handle_info/2,
	 terminate/2,
	 code_change/3]).

%% test
-export([clear/0]).
-export([clear/1]).

-include_lib("canopen/include/canopen.hrl").
-include("../include/co_debug.hrl").

-define(TABLE, ?OBJDEF_TABLE).
-define(SERVER, ?MODULE).

-define(table_t(Record_t), term()).

%% debug
-export([next_/2, prev_/2]).
-export([version/1, date_time_version/2]).

-record(state,
	{
	  objtab :: ?table_t({Key::term(),Value::term()}),
	  pidtab :: ?table_t({User::pid(), ?table_t(#objdef)})
	}).

-define(DEFAULT_MOD,    '').
-define(DEFAULT_VERSION, 0).

-define(UNIX_SECONDS, 62167219200).  %% from year 0 Jan 1 to 1970 Jan 1
%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% try find object by index alone
object(Index) ->
    object(default,latest,Index).

%% try find object by module, version and index
object(Mod,latest,Index) when is_atom(Mod) ->
    Version = date_time_version(date(),time()),
    object(Mod,Version,Index);
object(Mod,DateString,Index) when is_list(DateString) ->
    Version = version(DateString),
    object(Mod,Version,Index);
object(Mod,Version,Index0) when is_atom(Index0) ->
    case lookup_(?TABLE, {index,Index0}) of
	false -> false;
	{Index,_Mod,_Version} when is_integer(Index) ->
	    object(Mod,Version,Index)
    end;
object(default,_Version,Index) ->
    case next_(?TABLE, {objdef,Index,'',-1}) of
	false -> false;
	Key={objdef,Index,_Mod1,_Version1} ->
	    lookup_(?TABLE, Key);
	_ -> false
    end;
object(Mod,Version,Index) 
  when is_atom(Mod), is_integer(Version),is_integer(Index) ->
    case prev_(?TABLE, {objdef,Index,Mod,Version+1}) of
	false -> false;
	Key={objdef,Index,Mod1,_Version1} ->
	    if Mod1 =:= Mod; Mod1 =:= ?DEFAULT_MOD; Mod =:= ?DEFAULT_MOD ->
		    lookup_(?TABLE, Key);
	       true -> false
	    end;
	_ -> false
    end.


%% same as object but for enum defs
%% try find object by index alone
enum(Name) ->
    enum(default,latest,Name).

%% try find object by module, version and index
enum(Mod,latest,Name) when is_atom(Mod) ->
    Version = date_time_version(date(),time()),
    enum(Mod,Version,Name);
enum(Mod,DateString,Name) when is_list(DateString) ->
    Version = version(DateString),
    enum(Mod,Version,Name);
enum(default,_Version,Name) ->
    case next_(?TABLE, {enum,Name,'', -1}) of
	false -> false;
	Key={enum,Name,_Mod1,_Version1} ->
	    lookup_(?TABLE, Key);
	_ -> false
    end;
enum(Mod,Version,Name) 
  when is_atom(Mod), is_integer(Version),is_atom(Name) ->
    case prev_(?TABLE, {enum,Name,Mod,Version+1}) of
	false -> false;
	Key={enum,Name,Mod1,_Version1} ->
	    if Mod1 =:= Mod; Mod1 =:= ?DEFAULT_MOD; Mod =:= ?DEFAULT_MOD ->
		    lookup_(?TABLE, Key);
	       true -> false
	    end;
	_ -> false
    end.


entry(Index,SubInd) ->
    case object(Index) of
	false -> false;
	ObjDef -> find_entry(SubInd,ObjDef#objdef.entries)
    end.

entry(Mod,Version,Index,SubInd) ->
    case object(Mod,Version,Index) of
	false -> false;
	ObjDef -> find_entry(SubInd,ObjDef#objdef.entries)
    end.

find_entry(SubInd,Entries) when ?is_subind(SubInd) ->
    find_entry_(SubInd,Entries);
find_entry(SubInd,Entries) when is_atom(SubInd) ->
    lists:keyfind(SubInd, #entdef.id, Entries);
find_entry(SubInd,Entries) when is_list(SubInd) ->
    lists:keyfind(SubInd, #entdef.name, Entries).

find_entry_(SubInd, [E|Es]) ->
    case match_index(SubInd, E#entdef.index) of
	true -> E;
	false -> find_entry_(SubInd, Es)
    end;
find_entry_(_SubInd, []) ->
    false.

match_index(Index, Index) -> true;
match_index(Index, {From,To}) 
  when Index >= From, Index =< To -> true;
match_index(Index, {From,To,Step}) 
  when Index >= From, Index =< To, (Index-From) rem Step == 0 ->
    true;
match_index(_, _) -> 
    false.
    
add_object(Mod,Version,ObjDef) ->
    Key = {objdef,ObjDef#objdef.index,Mod,Version},
    insert_object(Key,ObjDef),
    add_index(Mod,Version,ObjDef#objdef.id,ObjDef#objdef.index).

add_enum(Mod,Version,Enum={enum,Name,_Def}) ->
    insert_object({enum,Name,Mod,Version},Enum).

add_index(Mod,Version,Name,Index) ->
    insert_object({index,Index},{Name,Mod,Version}),
    insert_object({index,Name}, {Index,Mod,Version}).

insert_object(Key,Value) ->
    gen_server:call(?SERVER, {insert,Key,Value}).

lookup_object(Key) ->
    gen_server:call(?SERVER, {lookup,Key}).

next(Key) ->
    gen_server:call(?SERVER, {next,Key}).

prev(Key) ->
    gen_server:call(?SERVER, {prev,Key}).

commit() ->
    gen_server:call(?SERVER, commit).

load_file(File) ->
    load(filename:basename(File),[filename:dirname(File)]).

load(Module) ->
    load_path(Module, []).
    
load(Module, Path) when is_list(Module) ->
    load_path(list_to_atom(Module), Path);
load(Module, Path) when is_atom(Module) ->
    load_path(Module, Path).

clear(Table) ->
    gen_server:call(?SERVER, {clear, Table}).
clear() ->
    gen_server:call(?SERVER, {clear, ?TABLE}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    ets:new(?TABLE, [named_table, protected, ordered_set]),
    PidTab = ets:new(pidtab, []),
    {ok, #state{ objtab = ?TABLE, pidtab = PidTab }}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({lookup,Key}, From, State) ->
    {Pid,_} = From,
    Result = lookup_from_(Key, Pid, State),
    {reply, Result, State};
handle_call({insert,Key,Value}, From, State) ->
    {Pid,_} = From,
    Tab = lookup_or_create_pid_table(Pid, State),
    %% io:format("Insert ~p  = ~p\n", [Key,Value]),
    Result = ets:insert(Tab, {Key,Value}),
    {reply, Result, State};
handle_call({next,Key}, From, State) ->
    {Pid,_} = From,
    Result = next_from_(Key, Pid, State),
    {reply, Result, State};
handle_call({prev,Key}, From, State) ->
    {Pid,_} = From,
    Result = prev_from_(Key, Pid, State),
    {reply, Result, State};
handle_call(commit, From, State) ->
    {Pid,_} = From,
    Result = commit_from_(State#state.pidtab,Pid),
    {reply, Result, State};
handle_call({clear, Table}, _From, State) ->
    ets:delete_all_objects(Table),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error,bad_call}, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({'DOWN',Mon,process,Pid,_Reason}, State) ->
    case lookup_(State#state.pidtab, Pid) of
	false -> 
	    {noreply, State};
	{Mon,Tab} ->
	    ets:delete(Tab),
	    ets:delete(State#state.pidtab, Pid),
	    {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% two layered lookup
lookup_from_(Key, Pid, State) ->
    case lookup_(State#state.pidtab, Pid) of
	false ->
	    lookup_(?TABLE,Key);
	{_Mon,Tab} ->
	    case lookup_(Tab, Key) of
		false -> lookup_(?TABLE, Key);
		Obj -> Obj
	    end
    end.

lookup_(Tab,Key) ->
    case ets:lookup(Tab, Key) of
	[] -> false;
	[{_,Obj}] -> Obj
    end.

lookup_or_create_pid_table(Pid, State) ->
    case lookup_(State#state.pidtab, Pid) of
	false ->
	    Tab = ets:new(pidtmp, [ordered_set]),
	    Mon = erlang:monitor(process, Pid),
	    ets:insert(State#state.pidtab, {Pid,{Mon,Tab}}),
	    Tab;
	{_,Tab} ->
	    Tab
    end.

next_from_(Key, Pid, State) ->
    case lookup_(State#state.pidtab, Pid) of
	false ->
	    next_(?TABLE, Key);
	{_Mon,Tab} ->
	    case next_(Tab, Key) of
		false ->
		    next_(?TABLE, Key);
		Key1 ->
		    Key1
	    end
    end.

prev_from_(Key, Pid, State) ->
    case lookup_(State#state.pidtab, Pid) of
	false ->
	    prev_(?TABLE, Key);
	{_Mon,Tab} ->
	    case prev_(Tab, Key) of
		false ->
		    prev_(?TABLE, Key);
		Key1 ->
		    Key1
	    end
    end. 
    
next_(Tab, Key={objdef,Index,_Mod,_Vsn}) ->
    case ets:next(Tab, Key) of
	'$end_of_table' -> false;
	Next={objdef,Index,_,_} -> Next;
	_ -> false
    end;
next_(Tab, Key={enum,Name,_Mod,_Vsn}) ->
    case ets:next(Tab, Key) of
	'$end_of_table' -> false;
	Next={enum,Name,_,_} -> Next;
	_ -> false
    end;
next_(Tab,Key={index,_I}) ->
    case ets:next(Tab, Key) of
	'$end_of_table' -> false;
	Next = {index,_} -> Next;
	_ -> false
    end.

prev_(Tab, Key={objdef,Index,_Mod,_Vsn}) ->
    case ets:prev(Tab, Key) of
	'$end_of_table' -> false;
	Next={objdef,Index,_,_} -> Next;
	_ -> false
    end;
prev_(Tab, Key={enum,Name,_Mod,_Vsn}) ->
    case ets:prev(Tab, Key) of
	'$end_of_table' -> false;
	Next={enum,Name,_,_} -> Next;
	_ -> false
    end;
prev_(Tab,Key={index,_I}) ->
    case ets:prev(Tab, Key) of
	'$end_of_table' -> false;
	Next = {index,_} -> Next;
	_ -> false
    end.

commit_from_(PidTab,Pid) ->
    case lookup_(PidTab, Pid) of
	false ->
	    {error, no_transaction};
	{Mon,Tab} ->
	    erlang:demonitor(Mon,[flush]),
	    AllWritten = 
		ets:foldl(
		  fun(Element,Acc) ->
			  %% io:format("Commit ~p\n", [Element]),
			  ets:insert(?TABLE, Element) and Acc
		  end, true, Tab),
	    ets:delete(Tab),
	    ets:delete(PidTab, Pid),
	    if AllWritten ->
		    ok;
	       true ->
		    {error, bad_insert}
	    end
    end.

%% Loading

-record(ctx,
	{
	  module,                     %% module loading
	  definitions :: atom(),      %% definitions loading
	  version = ?DEFAULT_VERSION, %% version number
	  path=[]                     %% search path for require
	}).

load_path(Mod, Path) when is_atom(Mod), is_list(Path) ->
    case get_module_status(Mod) of
	loaded -> 
	    {error, already_loaded};
	false ->
	    Default = filename:join(code:priv_dir(canopen),"def"),
	    load_mod(Mod, #ctx { path = Path ++ [Default]}),
	    commit()
    end.

load_mod(Mod, Ctx) when is_atom(Mod) ->
    set_module_status(Mod, loading),
    Res = load_mod_(Mod, Ctx#ctx { definitions=undefined }),
    set_module_status(Mod, loaded),
    Res.


%% @private
load_mod_(Mod, Ctx) when is_atom(Mod) ->
    File = atom_to_list(Mod) ++ ".def",
    case file:path_consult(Ctx#ctx.path, File) of
	{ok, Forms,_} ->
	    scan_(Forms, Ctx);
	{error,Error} ->
	    ?ee("load_mod: loading ~p failed, reason ~p\n", 
		[File, Error]),
	    erlang:error(Error)
    end.

%% {module, abc} - define module
scan_([{module,Mod}|Forms], 
      Ctx = #ctx {definitions=undefined,module=undefined})
  when is_atom(Mod) ->
    case get_module_status(Mod) of
	loaded ->
	    erlang:error({already_loaded, Mod});
	loading ->
	    scan_(Forms, Ctx#ctx { module = Mod });
	false ->
	    scan_(Forms, Ctx#ctx { module = Mod })
    end;
scan_([{definitions,Name}|Forms], Ctx = #ctx {definitions=undefined})
  when is_atom(Name) ->
    case get_module_status(Name) of
	loaded ->
	    erlang:error({already_loaded, Name});
	loading ->
	    scan_(Forms, Ctx#ctx { definitions = Name, module=?DEFAULT_MOD });
	false ->
	    scan_(Forms, Ctx#ctx { definitions = Name, module=?DEFAULT_MOD})
    end;
scan_([_Prop|_Forms], #ctx { definitions=Name, module=Mod }) when
      Name =:= undefined, Mod =:= undefined ->
    erlang:error(definitions_or_module_required);
scan_([{version, Version}|Forms], Ctx) when is_integer(Version), Version >= 0; 
					    is_list(Version) ->
    V = version(Version),
    scan_(Forms, Ctx#ctx { version = V });
scan_([{version,Mod,Version,Defs}|Forms], Ctx)
    when is_atom(Mod), is_list(Defs), is_integer(Version), Version >= 0;
	 is_atom(Mod), is_list(Defs), is_list(Version) ->
    V = version(Version),
    scan_objdefs_(Defs, Ctx#ctx { version = V, module = Mod }),
    scan_(Forms, Ctx);
scan_([{require, Mod}|Forms], Ctx) when is_atom(Mod) ->
    case get_module_status(Mod) of
	loading ->
	    erlang:error({circular_definition, Mod});
	loaded -> %% already loaded skip
	    add_module_require(Ctx#ctx.module, Mod),
	    scan_(Forms, Ctx);
	false ->
	    add_module_require(Ctx#ctx.module, Mod),
	    load_mod(Mod, Ctx#ctx { version=?DEFAULT_VERSION }),
	    scan_(Forms, Ctx)
    end;
%% {enum, atom(), [{atom(),value()}]}
scan_([Enum={enum,Id,Enums}|Forms], Ctx) when 
      is_atom(Id),is_list(Enums) ->
    add_enum(Ctx#ctx.module,Ctx#ctx.version,Enum),
    scan_(Forms, Ctx);
scan_([Objdef={objdef,_Index,_Options}|Forms], Ctx) ->
    scan_objdefs_([Objdef], Ctx),
    scan_(Forms, Ctx);
scan_([], Ctx) ->
    Ctx.

scan_objdefs_([{objdef,Index,Options}|Ds], Ctx) ->
    NewIxs = 
	case Index of
	    I when I > 0, I =< 16#ffff ->
		[I];
	    {I,J} when I > 0, I =< 16#ffff, I =< J, J =< 16#ffff ->
		lists:seq(I,J,1);
	    {I,J,S} when I > 0, I =< 16#ffff, I =< J, J =< 16#ffff,
	                 S > 0, S < 16#ffff ->
		lists:seq(I,J,S)
	end,
    Obj0 = co_lib:decode_obj(Options, #objdef { index=hd(NewIxs)}),
    Obj1 = verify_obj_id(Obj0, Ctx),
    Obj2 = co_lib:verify_obj(Obj1),
    ?dbg("def_mod: obj ~p verified", [Obj1]),

    %% If no entries and 'simple' type add default entry for subindex 0
    %% If 'complex' type it structure needs to be checked at runtime
    Obj3 = case {Obj2#objdef.entries, co_lib:simple_type(Obj2#objdef.type)} of
	       {[], true} ->
		   ?dbg("def_mod: adding def entry with type ~p", 
			[Obj2#objdef.type]),
		   DefEntry = #entdef {index = 0,
				       type = Obj2#objdef.type,
				       range = Obj2#objdef.range,
				       access = Obj2#objdef.access},
		   Obj2#objdef {entries = [DefEntry]};
	       _Other ->
		   Obj2
	   end,

    Id = Obj3#objdef.id,
    ?dbg("def_mod: obj id ~p verified", [Id]),
    lists:foreach(
      fun(Ix) ->
	      add_object(Ctx#ctx.module,Ctx#ctx.version,
			 Obj3#objdef { index = Ix })
      end, NewIxs),
    scan_objdefs_(Ds, Ctx);
scan_objdefs_([], Ctx) ->
    Ctx.

version(V) when is_integer(V), V >= 0 ->
    V;
version(Version) when is_list(Version) ->
    case Version of
	[Y1,Y2,Y3,Y4,$-,Mon1,Mon2,$-,D1,D2] ->
	    Year = list_to_integer([Y1,Y2,Y3,Y4]),
	    Month = list_to_integer([Mon1,Mon2]),
	    Day = list_to_integer([D1,D2]),
	    date_time_version({Year,Month,Day},{23,59,59});
	[Y1,Y2,Y3,Y4,$-,Mon1,Mon2,$-,D1,D2,$T,H1,H2,$:,M1,M2,$:,S1,S2] ->
	    Year = list_to_integer([Y1,Y2,Y3,Y4]),
	    Month = list_to_integer([Mon1,Mon2]),
	    Day = list_to_integer([D1,D2]),
	    Hour = list_to_integer([H1,H2]),
	    Min = list_to_integer([M1,M2]),
	    Sec = list_to_integer([S1,S2]),
	    date_time_version({Year,Month,Day},{Hour,Min,Sec})	    
    end.

date_time_version(Date,Time) ->
    calendar:datetime_to_gregorian_seconds({Date,Time}) - ?UNIX_SECONDS.

%%
%% Verify object id
%% Check that id is uniq
%%
verify_obj_id(Obj=#objdef {id = undefined, index = Index}, Ctx) ->
    Id = list_to_atom("id" ++ erlang:integer_to_list(Index,10)),
    verify_obj_id(Obj#objdef {id = Id}, Ctx);
verify_obj_id(Obj=#objdef {id = Id}, _Ctx) when is_atom(Id) ->
    case lookup_object({index,Id}) of
	false -> Obj;
	{_Index,_Mod,_Version} -> Obj
    end;
verify_obj_id(_Obj=#objdef {id = Id},_Ctx) ->
    %% Not atom
    erlang:error({bad_entry_id, Id}).

%% Module 

set_module_status(Module, Status) ->
    insert_object({module,Module}, Status).

get_module_status(Module) ->
    lookup_object({module,Module}).

add_module_require(Module, Require) ->
    case lookup_object({require, Module}) of
	false ->
	    Rs1 = [Require],
	    insert_object({require,Module},Rs1),
	    Rs1;
	Rs when is_list(Rs) ->
	    Rs1 =  [Require|Rs],
	    insert_object({require,Module},Rs1),
	    Rs1
    end.
