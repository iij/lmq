-record(message, {id={lmq_misc:unixtime(), lmq_misc:uuid()},
                  active=false, data}).

-define(DEFAULT_TIMEOUT, 30).
