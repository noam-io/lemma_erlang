-module(lemma_erlang_fsm).
-behaviour(gen_fsm).
-define(SERVER, ?MODULE).
-include("lemma_erlang_types.hrl").



%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/1,broadcast_udp/2,build_fsm_name/1]).

%% ------------------------------------------------------------------
%% gen_fsm Function Exports
%% ------------------------------------------------------------------

-export([init/1, autodiscover/2, autodiscover/3, connected/2, send_message/2, connected/3, handle_event/3,
         handle_sync_event/4, handle_info/3, terminate/3,
         code_change/4]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

-spec start_link(config()) -> {ok,pid()} | ignore | {error,term()}.
start_link(Config) ->
    gen_fsm:start_link(
        {local, build_fsm_name(Config)}, 
        ?MODULE, Config, []).

-spec build_fsm_name(config() | {guest(),room(),topics(),listener(),term()}) -> fsmRef().
build_fsm_name({Guest,Room,Topics,Listener}) ->
    build_fsm_name({Guest,Room,Topics,Listener,undefined});

build_fsm_name({Guest,Room,_Topics,_Listener,_Speaks}) ->
    list_to_atom("FSM"++binary_to_list(Guest)++binary_to_list(Room)). 



%% ------------------------------------------------------------------
%% gen_fsm Function Definitions
%% ------------------------------------------------------------------

%%-spec init()
-spec init(config() | {guest(),room(),topics(),listener(),term()}) -> {ok, autodiscover, [prop()]}.
init({Guest,Room,Topics,Listener}) ->
    init({Guest,Room,Topics,Listener,[]});

init({Guest,Room,Topics,Listener,Speaks}) ->
    process_flag(trap_exit, true),
    {ok, autodiscover, [
        {<<"guest">>,Guest},
        {<<"room">>,Room},
        {<<"topics">>,Topics},
        {<<"speaks">>,Speaks},
        {<<"listener">>,Listener},
        {<<"queue">>,[]}]}.

-spec autodiscover(message(),[prop()]) -> {atom(),atom(),[prop()]}.
autodiscover(<<"broadcast">>, State) ->
    Registered = broadcast_and_register(State),
    {next_state, connected, Registered};

autodiscover({<<"message">>,Topic,Contents},State) ->
    NextState = enqueue({<<"message">>,Topic,Contents},State),
    {next_state,autodiscover,NextState}.

-spec autodiscover(message(),{pid(),term()},[prop()]) -> {atom(),atom(),atom(),[prop()]}.
autodiscover(<<"broadcast">>, _From, State) ->
    Registered = broadcast_and_register(State),
    {reply, ok, connected, Registered};

autodiscover({<<"message">>,Topic,Contents}, _From, State) ->
    NewState = enqueue({<<"message">>,Topic,Contents},State),
    {reply, ok, autodiscover, NewState}.

-spec connected(message(),[prop()]) -> {atom(),atom(),[prop()]}.
connected({<<"message">>,Topic,Contents},State) ->
    ok = send_message({<<"message">>,Topic,Contents},State),
    {next_state, connected, State};

connected(<<"dropped">>,State) ->
    NewState = drop_connection(State),
    {next_state,autodiscover,NewState}.

-spec connected(message(),{pid(),term()},[prop()]) -> {atom(),atom(),atom(),[prop()]}.
connected({<<"message">>,Topic,Contents},_From,State) ->
    ok = send_message({<<"message">>,Topic,Contents},State),
    {reply,ok, connected, State};

connected(<<"dropped">>,_From,State) ->
    NewState = drop_connection(State),
    {reply,ok,autodiscover,NewState}.



handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, StateName, State) ->
    {reply, ok, StateName, State}.

handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

terminate(_Reason,connected,State) ->
    drop_connection(State);

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
-spec send_message(message(),state()) -> ok.
send_message({<<"message">>,Topic,Contents},State) ->
    Sock = proplists:get_value(<<"sendsock">>, State),
    Guest = proplists:get_value(<<"guest">>, State),  
    gen_server:cast(lemma_erlang_tcp, {<<"message">>,Sock,Topic,Contents,Guest}),
    ok.   

-spec enqueue(message(),state()) -> state().
enqueue(Item,State) ->
    Queue = proplists:get_value(<<"queue">>, State),
    Queue2 = [Item|Queue],
    [{<<"queue">>,Queue2}|proplists:delete(<<"queue">>, State)].

-spec dequeue(list(),state()) -> ok.
dequeue([],_) -> ok;

dequeue([QHead|QTail],State)->
    send_message(QHead,State),
    dequeue(QTail,State).

-spec dequeue(state()) -> state().
dequeue(State) ->
    Queue = proplists:get_value(<<"queue">>, State),
    ok = dequeue(Queue,State),
    [{<<"queue">>,[]}|proplists:delete(<<"queue">>, State)].

-spec drop_connection(state()) -> state().
drop_connection(State) ->
    %stop the timer
    Timer = proplists:get_value(<<"timer">>, State),
    timer:cancel(Timer),

    %close the listen socket
    ListenSock = proplists:get_value(<<"listensock">>, State), 
    gen_tcp:close(ListenSock), 

    %close the send socket
    SendSock = proplists:get_value(<<"sendsock">>, State),
    gen_tcp:close(SendSock),

    %remove the refs from the state
    Nstate1 = proplists:delete(<<"timer">>, State),
    Nstate2 = proplists:delete(<<"listensock">>, Nstate1),
    proplists:delete(<<"sendsock">>, Nstate2).   


-spec broadcast_and_register(state()) -> state().
broadcast_and_register(State) ->
    Pd = spawn(?MODULE,broadcast_udp,[State,self()]),
    receive
        {ok,Msg} -> Msg
    end,
    register_lemma(Msg++State).

-spec register_lemma(state()) -> state().
register_lemma(State) ->
    Guest = proplists:get_value(<<"guest">>, State),
    Room = proplists:get_value(<<"room">>, State), 
    Topics = proplists:get_value(<<"topics">>, State),
    Speaks = proplists:get_value(<<"speaks">>, State),
    IP = proplists:get_value(<<"ip">>, State),
    Port = proplists:get_value(<<"port">>, State),
    Listener = proplists:get_value(<<"listener">>, State),   
    Call = {<<"register">>,Guest,Topics,Speaks,IP,Port,Listener,lemma_erlang_fsm:build_fsm_name({Guest,Room,Topics,Listener,Speaks}) },
    {reply,{ok, TCPinfo},_} = gen_server:call(lemma_erlang_tcp, Call, infinity),
    dequeue(TCPinfo++State).

-spec broadcast_udp(state(),pid()) -> {ok,state()}.
broadcast_udp(State,Instance) ->
    Guest = proplists:get_value(<<"guest">>, State),
    Room = proplists:get_value(<<"room">>, State),
    Sck = proplists:get_value(<<"socket">>, State),
    Args = case Sck of
        undefined  -> [Guest,Room,self()];
        _ -> [Guest,Room,self(),Sck]
    end,
    {reply,Sockinfo,_State} = gen_server:call(lemma_erlang_udp, {<<"broadcast">>,Args}, infinity), 
    Sock = proplists:get_value(<<"socket">>, Sockinfo),
    NewState = [{<<"socket">>,Sock}|proplists:delete(<<"socket">>, State)],
    receive
        {udp, Socket, IP, InPortNo, Packet} ->
            [<<"polo">>,Room,Port] = jsx:decode(Packet),             
            Instance ! {ok,[{<<"port">>,Port},{<<"ip">>,IP}]}
        after 5000 ->
            broadcast_udp(NewState,Instance)
    end.



