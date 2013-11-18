# LMQ - Lightweight Message Queue

LMQ は Erlang で書かれたメッセージキューです。名前を付けて複数のキューを作成することができ、用途に応じてキューを使い分けることができます。

他の MQ と異なり、メッセージのルーティング等は行いません。LMQ は以下の機能を提供します。

* 複数のキューを作成
* メッセージの再送

**※仕様は開発中のもので、将来のバージョンで非互換の変更が加わる可能性があります。**

## インストール

リポジトリを取得し、以下のコマンドを実行します。

    $ cd $REPO_ROOT
    $ make rel

これにより、`$REPO_ROOT/rel/lmq` ディレクトリに必要なファイルが全てコピーされます。

## 使い方

起動するには以下のコマンドを実行します。

    $ bin/lmq start

起動しているか確認するには以下のようにします。

    $ bin/lmq ping
    pong

これでシングル構成で動作するようになります。

*Note: 0.2.0 以前のバージョンでは手動で DB を初期化する必要がありましたが、必要に応じて自動的に初期化するようになりました。*

メッセージの投入は HTTP 経由で行います。以下では重要でないヘッダは省略しています。

    $ curl -i -XPOST localhost:8180/msgs/myqueue -H 'content-type: text/plain' -d 'hello world!'
    HTTP/1.1 200 OK
    content-length: 15
    content-type: application/json

    {"accum":"no"}

`{"accum":"no"}` は、キューがメッセージをどのように処理したかを示しています。詳細は[メッセージの集約](#accumlate)を参照してください。

キューに投入したメッセージを取り出します。

    $ curl -i localhost:8180/msgs/myqueue
    HTTP/1.1 200 OK
    content-length: 12
    content-type: text/plain
    x-lmq-queue-name: myqueue
    x-lmq-message-id: f0eca12e-19f2-4922-bcc9-6e42bd585937
    x-lmq-message-type: normal

    hello world!

レスポンスボディは投入したメッセージがそのまま返ってきます。`content-type` も同様です。

その他、メッセージを処理するために重要な情報が HTTP ヘッダに含まれます。`x-lmq-message-id` は各メッセージに割り当てられたユニークな ID です。LMQ はメッセージの再送処理のために、処理が完了したら ack を返すことになっています。この時にメッセージ ID を用います。

    $ curl -i -XPOST 'localhost:8180/msgs/myqueue/f0eca12e-19f2-4922-bcc9-6e42bd585937?reply=ack'
    HTTP/1.1 204 No Content

`404 Not Found` が返ってきた場合は、既にメッセージがタイムアウトして再送待ちになっている可能性があります。メッセージを取り出すところからやり直してみてください。デフォルトでは、再送までの時間は30秒に設定されています。

LMQ には他にも API が用意されています。詳細は [HTTP API](#http_api) を参照してください。

## <a name="properties">キューのプロパティ</a>
キューにはプロパティを設定することができ、その値により各キューの動作をカスタマイズすることができます。利用可能なプロパティと、デフォルト値は以下の通りです。

name    | type    | default | description
---     | ---     | ---:    | ---
accum (pack)  | float   | 0       | メッセージを集約する期間（秒）、0 で無効
retry   | integer | 2       | メッセージの再送回数
timeout | float   | 30      | メッセージが再送されるまでの時間（秒）

LMQ はキューのプロパティを設定するための複数の方法を用意しています。プロパティを設定する全ての API は、変更したいプロパティを投入することが可能です。設定されなかったプロパティにはデフォルト値が使われます。

プロパティは以下の順に優先されます。

1. キューに設定されたプロパティ
2. デフォルトプロパティリストの最初にマッチしたもの
3. システムのデフォルト値（変更不可）

例えば、キュー `foo` に `{"accum": 15}` というプロパティを設定し、デフォルトプロパティに `[[".*", {"timeout": 60}]]` を設定した場合、キュー `foo` の実際のプロパティは以下のようになります。

    {"accum": 15, "retry": 2, "timeout": 60}

プロパティの変更はいつでも可能ですが、新しいプロパティが反映されるのは、変更後に `push` したメッセージだけです。

## タイムアウトと再送
LMQ はメッセージが `pull` されてからの経過時間を管理しており、これが `timeout` 値を超えると、そのメッセージは正しく処理されなかったと見なしてメッセージをキューに戻します。これにより、他のクライアントがメッセージを `pull` できるようになります。これが LMQ における再送処理です。

LMQ はメッセージを再送する際にメッセージ ID を変更します。そのため、メッセージ ID を指定する全ての API は、再送された元のメッセージに対して呼び出しても失敗します。これらの API には、`done`, `retain`, `release` があります。

メッセージは `retry` 回数だけ再送されます。そして、この回数を超過したメッセージは破棄されます。`retry` を 0 に設定したキューでは、メッセージは決して自動的には再送されませんが、タイムアウトの発生によって破棄される点は同一なので注意してください。メッセージ ID を指定する全ての API は、破棄されたメッセージに対して呼び出しても失敗します。

タイムアウトは `retain` を呼ぶことでリセットできます。時間のかかる処理をする前に `retain` を呼び出せば、処理がタイムアウトする可能性を低くすることができます。

また、`release` を呼ぶ事でメッセージを意図的にキューに戻すことが可能です。結果として、メッセージは即座に再送されますが、この場合に限り再送カウンタは消費されません。クライアントがメッセージを処理できない状態になった時は、明示的に `release` を呼び出すことで、LMQ による再送を待たずに他のクライアントにメッセージを渡すことができます。

## <a name="accumlate">メッセージの集約</a>
LMQ には、一定時間内に特定のキューに `push` された全てのメッセージを集約して、時間経過後に一つのメッセージとしてキューに入れる集約機能があります。この集約されたメッセージのことを複合メッセージと呼びます。複合メッセージは通常のメッセージと同様に処理されます。すなわち、再送処理や API による操作は複合メッセージ単位になります。

この機能を有効にするには、キューのプロパティの `accum` を 0 より大きくしてください。なお、集約が有効なキューでは、`push` されたメッセージは `accum` 時間が経過するまで取り出せないことに注意してください。

## クラスタリング
耐障害性を向上させるために、2つ以上の LMQ ノードを使ってクラスタを組むことができます。LMQ クラスタは P2P 方式で実装され、マスターレスモデルになっています。キューのデータはクラスタ内の全ノードで同期されるため、クラスタを構成するノードが落ちたとしても影響はほとんどありません。また、クライアントはクラスタ内のどのノードに対してもリクエストを送ることができます。

クラスタを組むには以下のようにします。説明上は *lmq1.example.com* と *lmq2.example.com* でクラスタを組むことにします。

1. `etc/vm.args` ファイルを編集します。

    `-name lmq@127.0.0.1` という行の *127.0.0.1* を他のノードからアクセスできる IP アドレス、もしくはホスト名に変更します。例として、それぞれ *lmq1.example.com* と *lmq2.example.com* にします。

2. それぞれのホストで LMQ を起動します。

        lmq1.example.com$ bin/lmq start
        lmq2.example.com$ bin/lmq start

3. クラスタを組みます。

        lmq2.example.com$ bin/lmq-admin join lmq@lmq1.example.com

*lmq2.example.com* をクラスタから抜くには以下のようにします。

    lmq2.example.com$ bin/lmq-admin leave

## ステータス表示
LMQ の現在のステータスを表示するには、以下のコマンドを実行します。

    $ bin/lmq-admin status

## パフォーマンスチューニング
高いパフォーマンスが必要な環境では、API のアクセスログを無効化することで 15-30% ほど多くの API リクエストを処理できるようになります。

API のアクセスログは `info` レベルで吐かれるので、lager の全てのハンドラのログレベルを `notice` 以上にすればアクセスログによるオーバーヘッドが無くなります。

例えば、以下のように `app.config` を設定できます。

```erlang
{lager, [
  {handlers, [
    {lager_file_backend, [
      [{file, "./log/console.log"}, {level, notice}, {size, 0}, {date, "$D0"}, {count, 14}]
    ]}
  ]},
```

## <a name="http_api">HTTP API</a>
LMQ は HTTP インタフェースを 8180 番ポートで提供しています（ポートは変更可能）。URL に渡す値は全て URL エンコードしてください。

リクエスト/レスポンスは JSON 形式です。

### メッセージ操作
#### GET /msgs/:name
* 概要: メッセージをキューから1つ取得する
* パラメータ:
    * name: キュー名
* クエリパラメータ（オプション）
    * t: Timeout, メッセージを取得できるまで待つ時間（秒）
    * cf: Compound Format, 複合メッセージのフォーマット
        * multipart: `multipart/mixed` 形式。デフォルト
        * msgpack: `msgpack` 形式
* レスポンスコード: `200 OK`
* レスポンスヘッダ:
    * content-type: POST 時の content-type
    * x-lmq-queue-name: メッセージを取り出したキュー名
    * x-lmq-message-id: メッセージの ID
    * x-lmq-message-type: メッセージの種類
        * normal: 通常のメッセージ
        * compound: 複合メッセージ
* レスポンスボディ: POST されたデータ

#### POST /msgs/:name
* 概要: メッセージをキューに追加する
* パラメータ:
    * name: キュー名
* リクエストボディ: メッセージの内容となるデータ
* レスポンスコード: `200 OK`
* レスポンスボディ:

```json
{"accum": "FLAG"}
```

* FLAG: 集約処理が行われたかどうか
    * new: 新たに集約が開始された
    * yes: 既存のメッセージと集約された
    * no: 集約されなかった

#### GET /msgs?qre=:regexp
* 概要: メッセージを regexp にマッチするキューの**いずれか**から1つ取得する
* パラメータ:
    * qre: 対象のキューを絞り込む正規表現
* クエリパラメータ（オプション）: `GET /msgs/:name` と同様
* レスポンス: `GET /msgs/:name` と同様

#### POST /msgs?qre=:regexp
* 概要: メッセージを regexp にマッチする**全ての**キューに追加する
* パラメータ:
    * qre: 対象のキューを絞り込む正規表現
* リクエストボディ: メッセージの内容となるデータ
* レスポンスコード: `200 OK`
* レスポンスボディ:

```json
{
    "QUEUE NAME 1": {"accum": "FLAG 1"},
    "QUEUE NAME 2": {"accum": "FLAG 2"},
    ...
}
```

* QUEUE NAME N: メッセージを追加したキュー名
* FLAG N: 集約処理が行われたかどうか
    * new: 新たに集約が開始された
    * yes: 既存のメッセージと集約された
    * no: 集約されなかった

#### POST /msgs/:name/:msgid?reply=:type
* 概要: 取得したメッセージの処理結果を通知する
* パラメータ:
    * name: キュー名
    * msgid: 対象メッセージの ID
    * type: 処理結果
        * ack: 処理が正常に終了 -> メッセージをキューから削除
        * nack: 処理が継続できなくなった -> メッセージをキューに戻す
        * ext: 処理に時間がかかっている -> メッセージの処理可能時間を延長
* レスポンスコード: `204 No Content`

### キュー操作
#### DELETE /queues/:name
* 概要: キューを削除する。キュー内のメッセージは全て破棄される
* パラメータ:
    * name: キュー名
* レスポンスコード: `204 No Content`

### プロパティ操作
#### GET /props
* 概要: デフォルトプロパティを取得する
* レスポンスコード: `200 OK`
* レスポンスボディ:

```json
[[REGEXP, PROPS], ...]
```

* REGEXP: 対象のキューを絞り込む正規表現
* PROPS: REGEXP にマッチしたキューに設定するプロパティ

#### PUT /props
* 概要: デフォルトプロパティを設定する。既存の設定があれば上書きされる
* リクエストボディ: `GET /props` のレスポンスと同様
* レスポンスコード: `204 No Content`

#### DELETE /props
* 概要: デフォルトプロパティを初期化する
* レスポンスコード: `204 No Content`

#### GET /props/:name
* 概要: キューのプロパティを取得する
* パラメータ:
    * name: キュー名
* レスポンスコード: `200 OK`
* レスポンスボディ:

```json
{
    "accum": ACCUM,
    "retry": RETRY,
    "timeout": TIMEOUT
}
```

詳細は[キューのプロパティ](#properties)を参照

#### PATCH /props/:name
* 概要: キューのプロパティを部分的に更新する。指定しなかったプロパティは既存の値を踏襲する
* パラメータ:
    * name: キュー名
* リクエストボディ:
    プロパティの内、変更したいものだけを記したもの

例:

```json
{"accum": 30}
{"accum": 30, "retry": 5}
```

* レスポンスコード: `204 No Content`

#### DELETE /props/:name
* 概要: キューのプロパティを初期化する
* パラメータ:
    * name: キュー名
* レスポンスコード: `204 No Content`

## MessagePack-RPC API

LMQ は MessagePack-RPC インタフェースを 18800 番ポートで提供しています。ここでは、各 API について `method(args) -> return_value` の形式で説明します。

戻り値は正常に処理された時のものについて記載します。各 API はエラーを返す可能性がある点に留意してください。

*MessagePack-RPC API は、後方互換性のために 0.6 でのメッセージ集約プロパティの変更の影響を受けていません。そのため、HTTP API とは一部異なります。*

### Request Message

#### create(name[, property]) -> "ok"
**この API は 0.4.0 で削除されました。代わりに `update_props` を使用してください。**

#### delete(name) -> "ok"

指定したキューを削除します。

<dl>
<dt>name (string)</dt><dd>削除するキューの名前</dd>
</dl>

#### push(name, content) -> "ok"
指定したキューにメッセージを投入します。キューがなければ作成します。

<dl>
<dt>name (string)</dt><dd>キューの名前</dd>
<dt>content (object)</dt><dd>投入するデータで、形式は問わない</dd>
</dl>

#### pull(name[, timeout]) -> {"queue": name, "id": id, "type": type, "content": content} | "empty"
指定したキューからメッセージを取り出します。キューがなければ作成します。

timeout を指定し、タイムアウトした時は `empty` 文字列が返ります。

`type` が "package" の場合、`content` は `push` されたデータの配列になります。

<dl>
<dt>name (string)</dt><dd>キューの名前</dd>
<dt>timeout (float)<dt><dd>タイムアウトまでの秒数</dd>
<dt>id (string)</dt><dd>メッセージの ID</dd>
<dt>type (string)</dt><dd>メッセージのタイプ。normal: 通常、package: パッケージ</dd>
<dt>content</dt><dd>push() により投入されたデータ</dd>
</dl>

#### push_all(regexp, content) -> "ok"

正規表現にマッチする全てのキューにメッセージを投入します。

<dl>
<dt>regexp (string)</dt><dd>正規表現</dd>
<dt>content (object)</dt><dd>投入するデータで、形式は問わない</dd>
</dl>

#### pull_any(regexp[, timeout]) -> {"queue": name, "id": id, "type": type, "content": content} | "empty"

正規表現にマッチするキューの中から、最も早く取り出せたメッセージを取得します。

timeout を指定し、タイムアウトした時は `empty` 文字列が返ります。

`type` が "package" の場合、`content` は `push` されたデータの配列になります。

<dl>
<dt>regexp (string)</dt><dd>正規表現</dd>
<dt>timeout (float)<dt><dd>タイムアウトまでの秒数</dd>
<dt>name (string)</dt><dd>キューの名前</dd>
<dt>id (string)</dt><dd>メッセージの ID</dd>
<dt>type (string)</dt><dd>メッセージのタイプ。normal: 通常、package: パッケージ</dd>
<dt>content</dt><dd>push() により投入されたデータ</dd>
</dl>

#### done(name, id) -> "ok"

メッセージの完了報告をし、キューからメッセージを取り除きます。pull() により取り出されたメッセージが一定時間内に完了しなかった場合、LMQ は自動的にメッセージを再送します。

メッセージが再送されると、古い ID は無効になり、完了報告が失敗します。

<dl>
<dt>name (string)</dt><dd>キューの名前</dd>
<dt>id (string)</dt><dd>完了報告するメッセージの ID</dd>
</dl>

#### retain(name, id) -> "ok"

メッセージの再送タイマーをリセットします。
これにより、再送までの時間を延長することができます。

メッセージが既に再送されていた場合、呼び出しは失敗します。

<dl>
<dt>name (string)</dt><dd>キューの名前</dd>
<dt>id (string)</dt><dd>再送をリセットするメッセージの ID</dd>
</dl>

#### release(name, id) -> "ok"

メッセージをキューに戻します。メッセージは即座に再送されます。

<dl>
<dt>name (string)</dt><dd>キューの名前</dd>
<dt>id (string)</dt><dd>キューに戻すメッセージの ID</dd>
</dl>

#### update_props(name[, property]) -> "ok"
キューのプロパティを更新します。キューがなければ作成します。

変更したいプロパティだけ指定すれば、残りはデフォルト値が使用されます。
また、`property` 自体を省略すると、全てデフォルト値に設定されます。

<dl>
<dt>name (string)</dt><dd>キューの名前</dd>
<dt>property (dict)</dt><dd>キューの動作に関わるプロパティ</dd>
</dl>

### set_default_props(props_list) -> "ok"
デフォルトプロパティを設定します。既存の内容は完全に上書きされます。

props_list は [[regexp, property], ...] の構造を持つリストです。
キューの作成時に、新しいキューの名前が regexp にマッチするかを先頭から評価していき、初めてマッチした property を使用します。どのルールにもマッチしなければ、システムのデフォルトを使用します。

### get_default_props() -> props_list
設定されているデフォルトプロパティを取得する。
