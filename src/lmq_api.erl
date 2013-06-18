-module(lmq_api).

-export([create/1, push/2]).

create(Name) when is_list(Name) ->
    ok = lmq_queue_mgr:create(Name),
    "ok".

push(Name, Msg) when is_list(Name) ->
    case lmq_queue_mgr:find(Name) of
        not_found -> throw(not_found);
        Pid ->
            lmq_queue:push(Pid, Msg),
            "ok"
    end.
