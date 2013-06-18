-module(lmq_api).

-export([create/1, push/2]).

create(Name) when is_binary(Name) ->
    Name1 = binary_to_atom(Name, latin1),
    ok = lmq_queue_mgr:create(Name1),
    <<"ok">>.

push(Name, Msg) when is_binary(Name) ->
    Pid = find(Name),
    lmq_queue:push(Pid, Msg),
    <<"ok">>.

find(Name) when is_binary(Name) ->
    Name1 = binary_to_atom(Name, latin1),
    case lmq_queue_mgr:find(Name1) of
        not_found -> throw(not_found);
        Pid -> Pid
    end.
