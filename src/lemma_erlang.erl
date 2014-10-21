-module(lemma_erlang).

-export([test/2,listener/0,connect/4,send/3,disconnect/1]).

ensure_deps_started(App) ->
	application:load(App), 
	{ok, Deps} = application:get_key(App, applications),
	true = lists:all(fun ensure_started/1, Deps),
	ensure_started(App).
ensure_started(App) ->
	case application:start(App) of
		ok ->
			true;
		{error, {already_started, App}} ->
			true;
		Else ->
			error_logger:error_msg("Couldn't start ~p: ~p", [App, Else]),
			Else
	end.

connect(Guest,Room,Topics,Listener) when is_binary(Guest), 
	is_binary(Room),
	is_list(Topics),
	is_pid(Listener) ->
	Config = {Guest,Room,Topics,Listener},
	ChildSpec = {
			lemma_erlang_fsm:build_fsm_name(Config),
			{lemma_erlang_fsm,start_link,[Config]},
			transient,
			3000,
			worker,
			[]
			},
	
	{ok, _Pid} = supervisor:start_child(lemma_erlang_sup, ChildSpec),
	_Resp = gen_fsm:sync_send_event(_Pid, <<"broadcast">>,infinity),	
	lemma_erlang_fsm:build_fsm_name(Config).

send(FsmRef,Topic,Message) ->
	gen_fsm:send_event(FsmRef, {<<"message">>,Topic,Message}).

disconnect(FsmRef)->
	supervisor:terminate_child(lemma_erlang_sup, FsmRef),
	supervisor:delete_child(lemma_erlang_sup, FsmRef). 

test(Guest,Room) when is_binary(Guest), is_binary(Room)  ->
	true = ensure_deps_started(lemma_erlang),
	Listener = spawn(?MODULE, listener, []), 
	Name = connect(Guest,Room,[<<"stuff">>],Listener),
	send(Name,<<"stuff">>,[1,2,3,4]),
	send(Name,<<"offtopic">>,[1,2,3,4]),
	Name.



listener() ->
	receive
		Pattern -> 
			io:format("Listener received: ~p~n", [Pattern]),
			listener()
	end.

