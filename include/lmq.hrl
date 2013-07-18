-record(message, {id={lmq_misc:unixtime(), uuid:get_v4()},
                  active=false, retry, data}).
-record(queue_info, {name, props}).

-define(DEFAULT_QUEUE_PROPS, [{retry, 2}, {timeout, 30}]).
-define(QUEUE_INFO_TABLE, '__lmq_queue_info__').
-define(QUEUE_INFO_TABLE_DEFS, [{type, set},
    {attributes, record_info(fields, queue_info)},
    {record_name, queue_info}]).
