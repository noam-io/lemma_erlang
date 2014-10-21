-module(lemma_erlang_tcp).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-include("lemma_erlang_types.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0,register/8,message_transformer/4,send_message_back_to_listener/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    terminate/2, code_change/3]).

-export([format_message/1]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------
init(Args) -> {ok, Args}.

% register - create a sending and
handle_call({<<"register">>,Guest,Topics,Speaks,IP,Port,Listener,FSMRef},From,State) ->
    lemma_erlang_util:async_func_wrapper(
        ?MODULE, 
        register, 
        [Guest,Topics,Speaks,IP,Port,Listener,FSMRef], 
        From, 
        State
        ),
    {noreply,State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({<<"heartbeat">>,Sock,Guest},State) ->
    heartbeat(Sock,Guest),
    {noreply,State};

handle_cast({<<"message">>,Sock,Name,Message,Guest},State) ->
    message(Sock,Name,Message,Guest),
    {noreply,State};

handle_cast(_Msg, State) ->
    io:format("cast with bad pattern: ~p~n", [_Msg]),
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
-spec message(port(),atom(),term(),guest()) -> ok | {error, close|inet:posix()}.
message(Sock,Name,Message,Guest) ->
    Msg = format_message([<<"event">>,Guest,Name,Message]),
    gen_tcp:send(Sock,Msg). 

-spec heartbeat(port(),guest()) -> ok | {error, close|inet:posix()}.
heartbeat(Sock,Guest) ->
    Msg = format_message([<<"heartbeat">>,Guest]),
    gen_tcp:send(Sock, Msg). 

-spec message_transformer(guest(),topics(),listener(),atom()) -> ok.
message_transformer(Guest,Topics,Listener,FSMRef) ->
    receive
        {tcp,_,Message} ->
            _Msg = handle_message(Message,Guest,Topics,Listener),
            message_transformer(Guest,Topics,Listener,FSMRef);
        {tcp_closed,_} ->
            ok = gen_fsm:sync_send_event(FSMRef, <<"dropped">>),
            gen_fsm:send_event(FSMRef, <<"broadcast">>);
        MSG -> io:format("recieved unknown message message: ~p~n", [MSG]) 
    after 10000 ->
            ok = gen_fsm:sync_send_event(FSMRef, <<"dropped">>),
            gen_fsm:send_event(FSMRef, <<"broadcast">>)
    end.

-spec handle_message(message(),guest(),topics(),listener()) -> ok.
handle_message(Message,Guest,Topics,Listener) ->
    Msgs = decode_message(Message),
    Msglist = [{Msg,Guest,Topics,Listener} || Msg <- Msgs],
    lists:foreach(fun(Elem) -> spawn_link(?MODULE, send_message_back_to_listener, [Elem]) end, Msglist).


-spec send_message_back_to_listener({decoded_message(),guest(),topics(),listener()}) -> ok | {invalid,term()}.
send_message_back_to_listener({Msg,Guest,Topics,Listener}) ->
    Tested = validate_message(Msg, Guest,Topics),
    case Tested of
        % we got a legit message
        {ok,message,_,_} ->
            Listener ! Tested,
            ok;
        % we got a heartbeat.  That's fine, but we 
        %don't send it back to the listener
        {ok,heartbeat,_} -> ok;
        
        % we got a known error. Let the listener know
        % and figure out how to handle it
        {error,_} -> 
            Listener ! Tested,
            ok
    end.

-spec validate_message(decoded_message(),guest(),topics()) -> Response when
    Response :: {error,binary()} |
        {ok,hearbeat,guest()} |
        {ok,message,guest(),term()}.
% known error
validate_message({error,Reason},_,_) ->
    {error,Reason};

% 
validate_message({ok,heartbeat,Guest},Guest,_) ->
    {ok,heartbeat,Guest};

validate_message({ok,heartbeat,Guest2},Guest,_) when (Guest2 =/= Guest) ->
    {error,<<"wrong guest">>};

validate_message({ok,message,Sender,Topic,EventValue},_Guest,Topics) ->
    case lists:member(Topic, Topics)  of
        true -> {ok,message,Sender,EventValue};
        false -> {error,<<"wrong topic">>}
    end.


-spec register(guest(),topics(),term(),inet:ip_address(),inet:port_number(),listener(),atom(),State) ->
    {reply, {ok,[prop()]}, State}.
register(Guest,Topics,Speaks,IP,Port,Listener,FSMRef,_State) ->
    %% set up the listener and associated process
    {ok,ListenSock} = setup_listener(),
    Pid = spawn(?MODULE,message_transformer,[Guest,Topics,Listener,FSMRef]),
    {ok,ListenPort} = inet:port(ListenSock), 
    
    %make the registration call
    {ok,SendSock} = setup_sender(IP,Port),
    RegMsg = [<<"register">>,Guest,ListenPort,Topics,Speaks,<<"erlang">>,<<"0.21">>,[{<<"heartbeat">>,2},{<<"heartbeat_ack">>,true}]],
    gen_tcp:send(SendSock, format_message(RegMsg)),
    
    {ok, Lsock} = gen_tcp:accept(ListenSock,10000),
    ok = gen_tcp:controlling_process(Lsock, Pid),
    
    %send an initial heartbeat
    gen_server:cast(?MODULE, {<<"heartbeat">>,SendSock,Guest}),
    
    %start the heartbeat loop
    {ok,Timer} = timer:apply_interval(2000, gen_server, cast, [?MODULE,{<<"heartbeat">>,SendSock,Guest}]),
    {reply,{ok,[{<<"sendsock">>,SendSock},{<<"listensock">>,ListenSock},{<<"timer">>,Timer}]},_State}.

-spec setup_sender(inet:ip_address(),inet:port_number()) -> {'error',atom()} | {'ok',port()}.
setup_sender(IP,Port) ->
    gen_tcp:connect(IP, Port, [binary], 10000).

-spec setup_listener() -> {ok, port()} | {error, system_limit | inet:posix()}.
setup_listener() ->
    gen_tcp:listen(
            0, [binary,{active,true}]
            ).

-spec decode_message(message()) -> [decoded_message()].
decode_message(Msg) when is_binary(Msg)->
    decode_message(Msg,[]).

-spec decode_message(binary(),[decoded_message()]) -> [decoded_message()].
decode_message(<<"">>,Out) ->
    Out;

decode_message(Msg,Out) when is_list(Out),is_binary(Msg) ->
    Len = binary_to_integer(binary:part(Msg, 0, 6)),
    Event = binary:part(Msg, 6, Len),
    OutMsg = [unformat_event(jsx:decode(Event))|Out],
    decode_message(binary:part(Msg, (6+Len), (byte_size(Msg) - (6+Len))),OutMsg).

-spec unformat_event(term()) -> decoded_message().
unformat_event([<<"event">>, Guest, Topic, EventValue]) ->
    {ok,message,Guest,Topic,EventValue};

unformat_event([<<"heartbeat_ack">>,Guest]) ->
    {ok,heartbeat,Guest};

unformat_event(_) ->
    {error,<<"unrecognized_message">>}.

-spec format_message(list()) -> binary().
format_message(Msg) when is_list(Msg) ->
    Enc = jsx:encode(Msg),
    Byt = list_to_binary(io_lib:format("~6..0B",[byte_size(Enc)])),
    <<Byt/binary,Enc/binary>>. 

