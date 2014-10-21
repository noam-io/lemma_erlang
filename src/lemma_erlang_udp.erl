-module(lemma_erlang_udp).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-include("lemma_erlang_types.hrl").
%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0,broadcast/5,broadcast/4]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------
-spec init(Args) -> {ok,Args}.
init(Args) -> {ok, Args}.

-spec handle_call({binary(),term()}|term(),{pid(),term()},term()) -> {noreply,term()}.
handle_call({<<"broadcast">>,Args},From,State) ->
	lemma_erlang_util:async_func_wrapper(?MODULE, broadcast, Args, From, State),
	{noreply,State}; 
	%async_start_link(broadcast,Args,From,State);

handle_call(_Request, _From, State) ->
	io:format("request: ~p ~n",[_Request]), 
	{reply, ok, State}.

-spec handle_cast(term(),term()) -> {noreply,term()}.
handle_cast(_Msg, State) -> {noreply, State}.

-spec handle_info(term(),term()) -> {noreply,term()}.
handle_info(_Info, State) -> {noreply, State}.

-spec terminate(term(), term()) -> ok.
terminate(_Reason, _State) -> ok.

-spec code_change(term(),term(),term()) -> {ok,term()}.
code_change(_OldVsn, State, _Extra) -> {ok, State}.



%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
-spec make_sock() -> port().
make_sock() ->
	{ok,Sock} = gen_udp:open(
		0, 
		[
			binary,
			{broadcast,true},
			{active,true}
		]),
	Sock.

-spec broadcast(guest(),room(),pid(),term()) -> {reply,[prop()],[]}.
broadcast(Guest,Room,From,_State) ->
	broadcast(Guest,Room,From,make_sock(),_State).

-spec broadcast(guest(),room(),pid(),port(),term()) -> {reply,[prop()],[]}.
broadcast(Guest,Room,From,Sock,_State) when is_port(Sock) ->
	broadcast(Guest,Room,Sock,{255,255,255,255},1030,From).

-spec broadcast(guest(),room(),port(),inet:ip_address(),inet:port_number(),pid()) -> {reply,[prop()],[]}.
broadcast(Guest,Room,Sock,IP,Port,From) ->
	Message = jsx:encode([<<"marco">>,Guest,Room,<<"erlang">>,<<"0.21">>]),
	ok = gen_udp:send(Sock,IP,Port,Message),
	gen_udp:controlling_process(Sock, From), 
	{reply,[{<<"socket">>,Sock}],[]}.





