# トラブルシューティング

[README に戻る](../README.md) ｜ [運用](operations.md)

---

## ログやワールドデータが作られない

コンテナはホストの実行ユーザーと同じ UID で動きます（`make` が `id -u` / `id -g` の値を自動で渡すため、設定は不要です）。ホスト側ディレクトリがその UID で書き込めないと、ログもワールドデータも保存できません。`server/` が読めない場合は、バイナリが見つからないというエラーで起動が止まります。

**症状の確認:**

```bash
docker logs --tail 30 minecraft-edu-world1     # Permission denied が出ていないか
ls -ld worlds/world1 logs/world1 server        # 所有者が root になっていないか
docker exec minecraft-edu-world1 id            # コンテナ実行ユーザーの UID
```

**対処:** 所有者を自分（`make` を実行するユーザー）に揃えます。

```bash
make down
sudo chown -R $(id -u):$(id -g) worlds sessions logs chat_logs server
make up
```

> **`sudo make up` では解決しません。** `sudo` が影響するのは docker クライアントの実行権限までで、コンテナ内のプロセスは常に `PUID` のユーザーとして動作するためです。

この問題は、`worlds/` などが存在しない状態で `docker compose up` すると **Docker デーモン（root）がマウント元ディレクトリを root 所有で作成してしまう**ために起きます。現在は `make up` / `restart` / `build` が実行前に `make dirs` でディレクトリを作成するため、新規環境では発生しません。

なお、この問題が出るのは Linux ホストのみです。Docker Desktop（Windows / macOS）は VM 経由のバインドマウントが UID を無視し、NAS も共有フォルダのパーミッションが緩いため表面化しません。

## コンテナを作り直した後に接続できない

ホスト側（NAS 製品など）が Docker の転送ルールを独自に管理している環境で起きます。

**症状**

`make down` → `make up` でコンテナを作り直したあと、クライアントから接続できたりできなかったりします。

- クライアントに「マルチプレイサービスへの接続を確立できません」「サーバーは無効化されました」と表示される
- 同じポートなのに、ホストのアドレスによって結果が変わる（片方は拒否される、など）
- 接続が別のワールドに届く
- サーバーのログに `Could not connect to Minecraft services` → `Server stop requested` が出て止まっているのに、`docker ps` では healthy のまま

**原因**

一部のホスト環境では、OS が Docker の作るポート転送（DNAT）と FORWARD のルールを独自の nftables テーブルに取り込んで管理しています。**OS のファイアウォール機能をオフにしていても、このテーブルは使われます。**

このテーブルはコンテナやネットワークを作り直しても自動では更新されず、**管理画面でファイアウォール設定を適用したときにだけ**作り直されます。

そのため、作り直しで内部 IP やブリッジ名が変わると古いルールと食い違います。

| 変わるもの | 古いルールが残ると |
|---|---|
| コンテナの内部 IP | 転送先が別のワールドや存在しない IP を指す → 接続が拒否される、別のワールドに届く |
| ブリッジ名（`br-<id>`） | 新しいブリッジからの外向き通信が FORWARD で通らない → サーバーが Microsoft のサービスへ接続できず起動直後に停止する |

ルールの確認にはホスト側で `sudo nft list ruleset` を使います（`iptables-legacy` の nat テーブルは空で、ルールは nft 側にあることが多いです）。

**対処（順番が重要）**

```bash
# 1. ホストの管理画面でファイアウォール設定を適用する（ルールが作り直される）
# 2. そのあとで再起動する
make restart
```

> **逆にすると直りません。** 先に再起動すると、古い FORWARD ルールのままサーバーが起動し、Microsoft のサービスへ接続できずに停止します。コンテナは残るので、一見起動しているように見えます。

直ったかどうかは、**別の端末から実際に繋いで**確認するのが確実です。

```bash
nc -z <公開アドレス> <シグナリングポート>   # make ports で確認できます
```

転送ルールを実際に通るので、ルールの中身を調べるより確実です。`transport=nethernet` ではゲーム通信が別の UDP 範囲を使うため、最終確認は**クライアント1台で実際に入室する**のが確実です。

**予防（この構成で既に入れている対策）**

作り直しても内部 IP とブリッジ名が変わらないように固定してあります。

| 項目 | 値 |
|---|---|
| ワールドの内部 IP | `<DOCKER_SUBNET_PREFIX>.<ワールド番号>.10`（既定 `172.30.N.10`） |
| ブリッジ名 | `DOCKER_BRIDGE_NAME`（既定 `br-mcedu`） |
| 自動割り当ての範囲 | `<DOCKER_SUBNET_PREFIX>.0.x`（通知・バックアップ用のコンテナ） |

自動割り当てを `.0.x` に閉じ込めてあるので、通知やバックアップのコンテナがワールドの固定 IP を先に取ることはありません。ワールド番号は **1〜254** の範囲で使えます。

これで、**コンテナを作り直しても適用は不要**になります（`make restart`、`make build` 後の `make up`、バックアップ中の停止起動など）。適用が必要なのは**ネットワークが作り直されたとき**、つまり `make down` → `make up` をしたときだけです。

**日常の停止と起動には `make stop` / `make start` を使ってください。**コンテナを削除しないので、内部 IP もネットワークもそのまま残り、適用が不要です。

```bash
make stop     # 日常の停止（コンテナもネットワークも残る）
make start    # 起動
make down     # 設定を変えるときだけ。ネットワークも削除される → 次の up のあとに適用が必要
```

**既存環境でこの設定を反映するとき**

```bash
git pull
make down        # 既存のネットワークを削除する
make build       # healthcheck.sh がイメージに含まれるため必要
make up
# この時点でホストの管理画面でファイアウォール設定を適用する
make restart
```

> `make build` を省くと、ヘルスチェックの改善が反映されません（`healthcheck.sh` はイメージに COPY されるため、`make up` だけでは入れ替わりません）。
>
> 通知・バックアップも動かしている場合は `make down NOTIFY=true BACKUP=true` にしてください。これらが残っているとネットワークが削除されず、`network ... has active endpoints` で失敗します。
>
> 既定のサブネット `172.30.0.0/16` やブリッジ名 `br-mcedu` が他の Docker ネットワークと衝突していると起動できません（`Pool overlaps`、`networks have same bridge name` 等）。その場合は `.env` の `DOCKER_SUBNET_PREFIX` / `DOCKER_BRIDGE_NAME` を変えてください。

---

## 既存環境を更新した場合（UID 999 → 実行ユーザー）

以前のバージョンはコンテナ実行ユーザーが UID 999 固定でした。更新後はホストの実行ユーザーと同じ UID になるため、一度だけ所有者を移し替えてイメージを再ビルドしてください。

```bash
make down
sudo chown -R $(id -u):$(id -g) worlds sessions logs chat_logs server
make build
make up
```

所有者がホストの自分のユーザーになるため、以降はビヘイビアパックの配置やワールドデータのバックアップに `sudo` が不要になります。

> 別の UID で動かしたい場合（共有サーバーで専用アカウントを使う等）のみ、`.env` に `PUID=` / `PGID=` を書けばそちらが優先されます。変更後は `make build` が必要です。
