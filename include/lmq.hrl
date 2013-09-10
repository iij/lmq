-record(message, {id={lmq_misc:unixtime(), uuid:get_v4()},
                  state=available, type=normal, retry, content}).
-record(queue_info, {name, props}).
-record(lmq_info, {key, value}).

-define(DEFAULT_QUEUE_PROPS, [{pack, 0}, {retry, 2}, {timeout, 30}]).
-define(LMQ_INFO_TABLE, '__lmq_info__').
-define(LMQ_INFO_TABLE_DEFS, [{type, set},
    {attributes, record_info(fields, lmq_info)},
    {record_name, lmq_info}]).
-define(QUEUE_INFO_TABLE, '__lmq_queue_info__').
-define(QUEUE_INFO_TABLE_DEFS, [{type, set},
    {attributes, record_info(fields, queue_info)},
    {record_name, queue_info}]).
