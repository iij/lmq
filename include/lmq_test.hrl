-define(LMQ_EVENT, lmq_event).

-define(EVENT_OR_FAIL(Event), receive {test_handler, Event} -> ok
                              after 50 -> ct:fail(no_response)
                              end).
-define(EVENT_AND_FAIL(Event), receive {test_handler, Event} ->
                                   ct:fail(invalid_event)
                               after 50 -> ok
                               end).
