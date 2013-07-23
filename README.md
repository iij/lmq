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

`$REPO_ROOT/rel/lmq` ディレクトリに必要なファイルが全てコピーされます。以下のコマンドで実行できます。

    $ cd rel/lmq
    $ bin/lmq start

## MessagePack-RPC API

LMQ は MessagePack-RPC インタフェースを 18800 番ポートで提供しています。ここでは、各 API について `method(args) -> return_value` の形式で説明します。

戻り値は正常に処理された時のものについて記載します。各 API はエラーを返す可能性がある点に留意してください。

### Request Message

#### create(name) -> "ok"

新しいキューを作成します。

<dl>
<dt>name (string)</dt><dd>作成するキューの名前</dd>
</dl>

#### delete(name) -> "ok"

指定したキューを削除します。

<dl>
<dt>name (string)</dt><dd>削除するキューの名前</dd>
</dl>

#### push(name, content) -> "ok"

指定したキューにメッセージを投入します。

<dl>
<dt>name (string)</dt><dd>キューの名前</dd>
<dt>content (object)</dt><dd>投入するデータで、形式は問わない</dd>
</dl>

#### pull(name[, timeout]) -> {"id": id, "content": content} | "empty"

指定したキューからメッセージを取り出します。

<dl>
<dt>name (string)</dt><dd>キューの名前</dd>
<dt>timeout (float)<dt><dd>タイムアウトまでの秒数</dd>
<dt>id (string)</dt><dd>メッセージの ID</dd>
<dt>content</dt><dd>push() により投入されたデータ</dd>
</dl>

#### push_all(regexp, content) -> "ok"

正規表現にマッチする全てのキューにメッセージを投入します。

<dl>
<dt>regexp (string)</dt><dd>正規表現</dd>
<dt>content (object)</dt><dd>投入するデータで、形式は問わない</dd>
</dl>

#### pull_any(regexp[, timeout]) -> {"id": id, "content": content} | "empty"

正規表現にマッチするキューの中から、最も早く取り出せたメッセージを取得します。

<dl>
<dt>regexp (string)</dt><dd>正規表現</dd>
<dt>timeout (float)<dt><dd>タイムアウトまでの秒数</dd>
<dt>id (string)</dt><dd>メッセージの ID</dd>
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
