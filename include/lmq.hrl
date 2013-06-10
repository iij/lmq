-record(message, {id={lmq_misc:unixtime(), lmq_misc:uuid()},
                  processing=false, data}).

-define(DEFAULT_TIMEOUT, 30).
