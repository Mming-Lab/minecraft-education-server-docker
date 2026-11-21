# 運用

[README に戻る](../README.md) ｜ [トラブルシューティング](troubleshooting.md)

---

## サーバーのバージョンアップ

サーバーバイナリの取得と更新は**ホスト側の `make update` だけが行います**。コンテナは `server/` に置かれているものをそのまま使うだけで、起動時にダウンロードも更新もしません。

```bash
make update CHECK=1   # 新しいバージョンが出ているか調べる（取得しない）
make update           # 取得して差し替え（直前の1世代は server.bak/ に退避）
make restart          # 反映
make props            # 設定項目が増えていないか確認
```

> **なぜ自動更新しないのか:** `server/` は全ワールドで共有している書き込み可能マウントです。以前はコンテナ起動時に自動更新していましたが、`make up` で複数ワールドが同時に起動すると全員が同じ「新しい」判定をして、同じファイルへ並行して unzip してしまいます。あるワールドが 200MB 超のバイナリをコピーしている最中に別のワールドがそれを truncate するため、壊れたバイナリで起動ループに入ります。バージョンが上がった瞬間にしか起きないので再現しづらく、しかも一番困るタイミング（授業直前の起動）で踏むことになります。
>
> 更新タイミングを人が決められること自体も重要です。クライアント（MCEE アプリ）の配布時期とサーバーのバージョンがずれると、参加者が全員接続できなくなりかねません。**バージョンを固定したいなら、単に `make update` を実行しなければよい**という運用になります。

### 戻したいとき

```bash
make rollback   # server/ と server.bak/ を入れ替える（もう一度叩けば元に戻る）
make restart
```

> **ワールドデータは戻せません。** 新しいバージョンで一度開いたワールドは不可逆にアップグレードされ、古いサーバーでは読めなくなります。`make rollback` が戻すのはバイナリだけなので、**更新前に `make backup` か `worlds/` のコピーを取っておいてください**。

### server.properties に項目が増えたとき

サーバー側で設定項目が増えても**起動は壊れません**。`entrypoint.sh` が起動ごとに `server/server.properties` を展開し直し、その上から環境変数を書き込む作りなので、新しい項目は公式の既定値で入ります。

ただし `/minecraft/server.properties` は永続化していないため差分が手元に残らず、項目が増えたことに気づく手がかりがありません。`make props` がその差分を出します。

```bash
make props
```

新しい項目を `.env` から制御したくなったら、次の3つを揃えます。

1. `property-definitions.json` に `"<キー>": { "env": "<環境変数名>" }` を追記
2. `docker-compose.world{N}.yml.example` の `environment` に環境変数の行を追記（`make sync` で既存ワールドに反映）
3. `make build`（`property-definitions.json` はイメージへ COPY されるため再ビルドが必要）

`make props` は逆方向の差分も出します。定義にあるのに `server.properties` のコメント行にも見当たらないキーは、サーバー側でリネームまたは廃止された疑いがあります。**BDS は未知のキーを黙って無視する**ため、`.env` で設定しても静かに効かなくなります。その場合は `server/bedrock_server_how_to.html` で正しい名前を確認してください（起動時にも警告が出ます）。

### バージョンの確認

配布元はバージョン別の URL を公開していないため、取得できるのは常に「最新版」だけです。`server/.server_version` には配布元の ETag（人間には読めない識別子）と取得日時が記録され、起動時のログにも出ます。

```bash
cat server/.server_version
docker logs minecraft-edu-world1 | grep 'サーバーバイナリ:'
```

---

## サーバーのコンソールにコマンドを送る

各ワールドのコンテナでは、サーバーの標準入力が FIFO（`/minecraft/console.in`）につながっています。
ホストから次のように送ると、サーバーのコンソールに打ち込んだのと同じになります（結果は `docker logs` に出ます）。

```bash
docker exec minecraft-edu-world<N> sh -c '[ -p /minecraft/console.in ] && echo "list" > /minecraft/console.in'
```

（`<N>` はワールド番号。例: `minecraft-edu-world1`）

- `[ -p ... ]` で FIFO があることを確かめてから書くこと（無いときに書くと普通のファイルができてしまう）
- entrypoint が FIFO を開いたままにしているので、サーバーは入力の終わり（EOF）を受け取らず、書き込みも待たされない
- サーバーの標準入力は FIFO なので、`docker attach` で打ち込んだ入力はサーバーに届かない（この方法で送る）
- FIFO を作れなかったときは、ログに警告を出して従来どおり（流し込みなし）で起動する
- オペレーター権限のコマンドがすべて通るので、`docker` を実行できる人だけが使える前提

---

## 通知（Vector + Apprise）

プレイヤーの参加/退出・チャット・サーバーイベントを ntfy や LINE 等に通知できます。

```bash
cp vector/vector.toml.example vector/vector.toml
# vector.toml を編集して ntfy トピック等を設定

cp apprise/minecraft.yml.example apprise/minecraft.yml
# minecraft.yml を編集して通知先 URL を設定（LINE 等）

make up NOTIFY=true
```

ChatLog ファイル（`chat_logs/world{N}/`）を監視し、`[日時] - ` で始まる行をすべて通知します。

あわせて**サーバーログ（`logs/world{N}/`）も監視し、サーバーの状態変化を通知します**。

| 通知 | 契機 |
|---|---|
| `[UP] minecraft-edu-worldN` | サーバーが起動し、参加できる状態になった |
| `[STOP] minecraft-edu-worldN` | サーバーが停止した |
| `[OFFLINE] minecraft-edu-worldN` | Microsoft のサービスへ接続できなかった |

ヘルスチェックが unhealthy を返しても Docker はコンテナを再起動しません（restart ポリシーはヘルス状態では発火しません）。そのため、通知が無いとサーバーが止まったことに誰も気づかないままになります。起動の通知は、授業前の確認にも使えます。

> **サーバーログの行はそのまま通知しません。** サーバーログにはサーバー ID・テナント ID・デバイスコード・IP アドレスが含まれるため、「何が起きたか」だけを固定文で送っています。通知先が公開トピック（ntfy など）の場合に備えた措置です。
>
> 通知のタイトルは ASCII にしています。ntfy では HTTP ヘッダー（`Title`）で送られるため、日本語を入れると受け手で文字化けします。
>
> `Could not contact Services to fetch joiners` のような一時的なサービス断は、継続中に何十行も出るため通知対象にしていません（通知が埋もれるため）。ログで確認してください。

**既存環境では実ファイルの更新が必要です。** `vector/vector.toml` は `.gitignore` 対象なので、`git pull` しても新しい設定は入りません。差分を確認して取り込んでください。

```bash
diff vector/vector.toml vector/vector.toml.example
# サーバーログ関連のセクションを vector.toml に取り込み、通知先 URL は自分の値を残す
docker restart vector
```

> **前提:** ChatLog ファイルはサーバー本体の機能で出力されます。`.env` の `CHAT_LOGGING_ENABLED_COMMON=true`（既定値）が必要です。この設定はあとから変更できますが、反映にはサーバーの再起動が必要です。
>
> **設定名が 1.26.33 で変わりました。** `chat-logging-enabled`（1.21.133〜1.26.32）→ **`chat-log-file-enabled`**（1.26.33 以降）。`property-definitions.json` 側のキーは追従済みですが、`.env` の変数名は `CHAT_LOGGING_ENABLED` のまま維持しています（各環境の `.env` を黙って無効にしないため）。出力先も `chat-log-file-path` で変更できるようになりましたが、既定値が従来と同じ `chat_logs/ChatLog_<time>` なので Vector の監視パスはそのまま使えます。

---

## ディレクトリ構成

### プロジェクト構成（Git 管理対象）

```
README.md                             # 概要・セットアップ・コマンド一覧
manual/operations.md                   # 運用（このファイル）
manual/troubleshooting.md              # トラブルシューティング
Makefile                              # ワールドの起動・追加コマンド
docker-compose.world{N}.yml.example   # ワールド定義テンプレート（make add が使用）
docker-compose.notify.yml             # 通知スタック（Vector + Apprise）
docker-compose.backup.yml             # 自動バックアップ（make up BACKUP=true）
Dockerfile / entrypoint.sh            # コンテナ定義
property-definitions.json             # 環境変数 → server.properties のマッピング定義
.env.example                          # 環境変数テンプレート
vector/vector.toml.example            # Vector 設定テンプレート
apprise/minecraft.yml.example         # 通知先設定テンプレート
```

### 実行時データ（Git 管理外）

```
docker-compose.world1.yml             # make add で生成
docker-compose.world2.yml             # make add で生成
.env                                  # .env.example からコピー

worlds/world{N}/                      # ワールドデータ
├── worlds/{LEVEL_NAME}/              # ゲームワールドデータ
├── behavior_packs/                   # ビヘイビアパック
├── resource_packs/                   # リソースパック
├── allowlist.json
├── permissions.json
└── packetlimitconfig.json

sessions/world{N}/                    # Entra 認証セッション（自動更新。失効時は再度デバイスコード認証）
logs/world{N}/                        # サーバーログ（ワールドごとに分離）
├── server_<日付>.log                 # サーバーの全出力。Device Code 認証の案内もここ
└── ContentLog_<時刻>N.txt            # アドオンの出力・警告・エラー（既定で有効）
chat_logs/world{N}/                   # チャットログ（CHAT_LOGGING_ENABLED=true のとき出力）
└── ChatLog_<時刻>.txt                # Vector の監視対象
server/                               # サーバーバイナリ（make update が取得・更新。全ワールドで共有）
server.bak/                           # 直前のバージョン（make rollback で戻せる）
```
