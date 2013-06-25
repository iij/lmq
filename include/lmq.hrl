-record(message, {id={lmq_misc:unixtime(), uuid:get_v4()},
                  active=false, data}).

-define(DEFAULT_QUEUE_PROPS, [{timeout, 30}]).
