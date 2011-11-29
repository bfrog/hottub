%% @author Tom Burdick <thomas.burdick@gmail.com>
%% @copyright 2011 Tom Burdick
%% @doc Hot Tub Pool Manager. Manages an ETS table that contains the current list
%% of workers. Monitors workers for crashes and removes them from the ETS table.
%% @end

-module(ht_pool).

-behaviour(gen_server).

%% api
-export([start_link/1, add_worker/2, checkout_worker/1, checkin_worker/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, pool_items/1]).

-record(state, {poolname=undefined, unused=queue:new(), checkouts=queue:new()}).


%% ----------------------------------------------------------------------------
%% api
%% ----------------------------------------------------------------------------

%% @doc Start a linked pool manager.
-spec start_link(PoolName::atom()) -> {ok, pid()}.
start_link(PoolName) ->
    gen_server:start_link({local, PoolName}, ?MODULE, [PoolName], []).

%% @doc Called by ht_worker after the worker process has started.
-spec add_worker(PoolName::atom(), Pid::pid()) -> term().
add_worker(PoolName, Pid) ->
    gen_server:cast(PoolName, {add_worker, Pid}).

%% @doc Checkin a worker.
-spec checkin_worker(PoolName::atom(), Pid::pid()) -> term().
checkin_worker(PoolName, Pid) ->
    gen_server:cast(PoolName, {checkin_worker, Pid}).

%% @doc Checkout a worker.
-spec checkout_worker(PoolName::atom()) -> Worker::pid() | undefined.
checkout_worker(PoolName) ->
    gen_server:call(PoolName, {checkout_worker}).

%% @doc Returns the sum of message_queue_len for each worker.
-spec pool_items(PoolName::atom()) -> term().
pool_items(PoolName) ->
    gen_server:call(PoolName, {pool_items}).

%% ------------------------------------------------------------------
%% gen_server callbacks
%% ------------------------------------------------------------------

%% @private
init([PoolName]) ->
    {ok, #state{poolname=PoolName}}.

%% @private
handle_call({pool_items}, _From, State) ->
    Items = lists:sum(lists:map(fun(Pid) -> 
        {_, ItemCount} = process_info(Pid, message_queue_len), 
        ItemCount
    end, queue:to_list(State#state.unused) ++ queue:to_list(State#state.checkouts))),
    {reply, Items, State};

handle_call({checkout_worker}, From, State) ->
    case queue:out(State#state.unused) of
        {{value, Worker}, Unused} ->
            {reply, Worker, State#state{unused=Unused}};
        {empty, _Unused} ->
            Checkouts = queue:in(From, State#state.checkouts),
            {noreply, State#state{checkouts=Checkouts}}
    end.

%% @private
handle_cast({checkin_worker, Worker}, State) ->
    case queue:out(State#state.checkouts) of
        {{value, P}, Checkouts} ->
            gen_server:reply(P, Worker),
            {noreply, State#state{checkouts=Checkouts}};
        {empty, _Checkouts} ->
            Unused = queue:in(Worker, State#state.unused),
            {noreply, State#state{unused=Unused}}
        end;
handle_cast({add_worker, Worker}, State) ->
    erlang:monitor(process, Worker),
    case queue:out(State#state.checkouts) of
        {{value, P}, Checkouts} ->
            gen_server:reply(P, Worker),
            {noreply, State#state{checkouts=Checkouts}};
        {empty, _Checkouts} ->
            Unused = queue:in(Worker, State#state.unused),
            {noreply, State#state{unused=Unused}}
    end.

%% @private
handle_info({'DOWN', _, _, Worker, _}, State) ->
    Unused = queue:from_list(lists:delete(Worker, queue:to_list(State#state.unused))),
    {noreply, State#state{unused=Unused}}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
