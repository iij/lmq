-record(message, {id={lmq_misc:unixtime(), uuid:get_v4()},
                  active=false, data}).

-define(DEFAULT_TIMEOUT, 30).
