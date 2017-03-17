-module(lemma_erlang_util).
-include("lemma_erlang_types.hrl").
%% lemma_erlang_util: lemma_erlang_util library's entry point.

-export([async_start_link/5,async_func_wrapper/5]).


%% API
-spec async_start_link(atom(),atom(),[term()],{pid(),term()},state()) -> pid().
async_start_link(Module,Func,Args,From,State) ->
	proc_lib:spawn_link(?MODULE, async_func_wrapper, [Module, Func, Args, From, State]).


-spec async_func_wrapper(atom(),atom(),[term()],{pid(),term()},state()) -> term().
async_func_wrapper(Module,Func,Args,From,State) ->	
%	io:format("wrapper args: ~p~n", [Args]),
	Reply = apply(Module, Func, Args++[State]),
%	io:format("wrapper reply: ~p~n", [Reply]),
	gen_server:reply(From, Reply). 



%% End of Module.
