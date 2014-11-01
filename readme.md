# Usage
The goal of the Erlang lemma is to let your application send and receive messages without having to worry much about the connection state.  Once you have a reference to send to, you can pretty much just start sending to it. See "Under the Hood" for more information.

## TL/DR
 - Start the lemma_erlang application as part of your Erlang application.
 - Create a listener to receive messages from the Noam server and handle your business logic.
 - Connect to a server instance and a room with ```lemma_erlang:connect/4```, which returns a reference to the room.
 - Send to the reference using lemma_erlang:send/3 (message can be any term).
 - Messages to the lemma are passed back to the listener as decoded Erlang/EJSON terms.
 - Use lemma_erlang:disconnect/1 to disconnect.
 - You CAN create multiple instances to different guest/room combinations.

## Under the Hood
Lemma_erlang is an OTP application with three main components:
 - a TCP server (gen_server) which sends TCP messages to Noam servers
 - a UDP server (also a gen_server) which broadcasts using UDP
 - finite state machines which handle individual connections to Noam servers

All messaging is done asynchronously and uses/abuses Erlang processes - don't rely on the order of responses. 
 
When you start the application it sets up a supervision tree and launches instances of the TCP and UDP servers.  When you create a finite state machine instance using lemma_erlang:connect/4, the state machine is added to the supervision tree and enters into its autodiscover/udp broadcast state.  Messages sent to the FSM while it is in autodiscover mode will be queued until the lemma registers with a Noam server. 

Upon registration, all messages dequeue and are sent to the server.  

The lemma does use heartbeats to maintain its connection to the server and will drop back into autodiscover state if the connection drops.  All messages should be preserved if the lemma does switch states.  

If a state machine crashes, it will be restarted via the supervisor and attempt to reconnect. This will cause messages to be lost if any are unsent, but won't affect your application otherwise.  You don't have to code defensively in the expectation of a crashed state machine.  Let it crash.



