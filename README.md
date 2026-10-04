# Minecraft Education Edition Dedicated Server - Docker

1台のサーバーで、複数グループ分のMinecraft Educationワールドを同時運用するためのDocker構成です。

> **前提**: 公式ドキュメントに記載のサーバー構築手順（デバイスコード認証・管理ツールによる有効化など）を理解していることを前提としています。
> - [Dedicated Server FAQ](https://edusupport.minecraft.net/hc/en-us/articles/41758309283348)
> - [Dedicated Server Alternate Configuration](https://edusupport.minecraft.net/hc/en-us/articles/41757415076884)（Tooling and Scripting Notebook）

---

## セットアップ

### 1. 環境設定

```bash
cp .env.example .env
```

`.env` を編集して最低限以下を設定します。

```bash
SERVER_PUBLIC_IP_LAN=192.168.1.100   # LAN 内からの接続先IP（必須）
# SERVER_PUBLIC_IP_WAN=example.com   # LAN 外から接続させる場合のみ設定
```

LAN 内用と LAN 外用のアドレスを両方定義しておき、ワールドごとに `SERVER_NETWORK_WORLD_N=wan` のように指定すれば、どちらの接続先を広告するかをワールド単位で切り替えられます（未指定なら `SERVER_NETWORK_COMMON`、それも無ければ `lan`）。

その他の設定は `_COMMON` 項目で全ワールドのデフォルト値を一括設定できます。個別ワールドで上書きしたい場合は `_WORLD_1` のように指定します。

> **優先順位:** 個別設定（`_WORLD_N`）> 共通設定（`_COMMON`）> デフォルト値


### 2. ワールドを追加

```bash
make add   # ワールド1（帯 19200-19299）
make add   # ワールド2（帯 19300-19399）
```

**ポートは自動採番されます。** 1ワールドが連続した100ポートの帯を占め、先頭がシグナリング、残り99本が `nethernet` のゲーム通信用になります（理由は下記「トランスポートとポート」）。ワールド番号・ポート・UDP 範囲がすべて `.env` に自動追記されます。

```bash
make ports            # 割り当て一覧と、次に使えるポートを表示
make add PORT=19500   # ポートを明示したい場合（100の倍数で指定）
```

> **ポート番号の注意:**
> - 自動採番は 19200 から始まり、既存の帯を跨がない次の100境界を選びます（開始値は `Makefile` の `PORT_BASE`）。
> - `PORT=` を明示する場合は**100の倍数**にしてください（`make add` が拒否します）。帯の境界を揃えないと隣のワールドの帯に食い込みます。
> - 同一ホスト上のワールドには**必ず別々のポート**を割り当ててください。同じポートで2つ起動すると、参加者側に「無効なテナントID（Invalid Tenant ID）」エラーが出ます。
> - 先頭の番号は **UDP と TCP の両方**で公開されます。`transport=nethernet` のワールドでは、残り99本も UDP で公開されます。ルーターやファイアウォールには**帯ごと（例: 19200-19299/udp）**を開けておけば足ります。
> - 既定ポート（19132）を避けるという公式の推奨にも、この採番は合致しています。

### トランスポートとポート

`.env` の `TRANSPORT_COMMON` で接続方式を選べます。**`.env.example` の既定は `nethernet`** です。RakNet は将来のバージョンで削除される見込みのため、新規構築は NetherNet から始める想定にしています。既存環境で確実に動かしたい場合は `raknet` に変更してください。

> **補足:** `.env` に `TRANSPORT_COMMON` の行自体が無い場合は `raknet` で動きます（compose テンプレートのフォールバック）。既存環境を更新したときに、意図せず方式が切り替わらないようにするためです。

| | `raknet` | `nethernet`（`.env.example` の既定） |
|---|---|---|
| 方式 | 従来の Bedrock UDP トランスポート | WebRTC ベース |
| `server-port` | **UDP** で直接待ち受け | **TCP**（HTTP シグナリング用のデュアルスタックソケット） |
| ゲーム通信 | 同じ UDP ポート | クライアントごとにネゴシエートされる **UDP** |
| 必要な公開ポート | UDP のみ | TCP（シグナリング）＋ UDP（ゲーム通信） |

#### nethernet は「参加者1人につき UDP ポート1つ」を使う

`nethernet` のゲーム通信は、既定では OS のエフェメラルポートから確保されるため、そのままでは Docker で公開できません。そこで `server-udp-ports` で範囲を固定し、クライアントへ広告する外部アドレスも宣言します。

ここが重要な点で、**NetherNet はプレイヤー1人が参加するごとに UDP ポートを1つ確保します**。プレイヤーが自宅で世界をホストする P2P 実装をそのまま流用しているためです。単一ポートを指定すると内部的に `min=max` となり、**同時1接続しか受け付けられません**（1人目は入れてしまうので、2人目が入れないまで気づけません）。

そのため本リポジトリでは、**1ワールド = 連続した100ポートの帯**として割り当てます。

| 用途 | 設定 | 例（最初のワールド） |
|---|---|---|
| シグナリング | `SERVER_PORT_WORLD_N`（TCP。raknet では UDP） | 19200 |
| ゲーム通信 | `SERVER_UDP_RANGE_WORLD_N`（UDP 範囲） | 19201-19299（99本） |

ポートは100飛ばしで採番されるので、UDP 範囲は常にその直後の99本になり、**帯どうしが重なることが原理的にありません**。ファイアウォールや VPS の転送設定も、ワールドあたり `19200-19299/udp` の1ルールで済みます。99本は `max-players=40` に対して十分な本数です。

```bash
make ports         # 割り当て一覧と、次に使えるポートを表示
make check-ports   # ポート重複・UDP 範囲の未設定を検査（up / restart / build 前に自動実行）
```

帯の幅は `Makefile` の `PORT_BLOCK`、`make ports` の提案開始値は `PORT_BASE` で変えられます。ただし**この帯は VPS の iptables 転送やクラウドのセキュリティリストにも登録することになる**ため、一度決めたら変えない運用を前提にしています。また Linux の既定エフェメラルポート帯（`32768-60999`）と重なる番号は避けてください（公式 how-to の例 `49152-49200` はこの帯の内側にあり、ホスト上の他プロセスと衝突しえます）。

compose が公開する UDP 範囲の行は、`transport=nethernet` のワールドにだけ `make sync` が出力します（raknet のワールドで使わない 100 ポートを公開しないため）。`.env` の `TRANSPORT_WORLD_N` を変えたら `make up` を実行すれば再生成されます。

> **ホスト側の設定:** 範囲公開では Docker が1ポートごとに iptables ルール（userland proxy 有効時は `docker-proxy` プロセスも1つずつ）を作るため、ポート数が増えると起動が遅くなります。`/etc/docker/daemon.json` に `{"userland-proxy": false}` を設定すると iptables DNAT のみになり、コストが大幅に下がります。

> **補足:** `raknet` では `enable-lan-visibility=true`（デフォルト）のため、サーバーは LAN 探索用に UDP 19132 も内部でバインドします。各ワールドは独立したコンテナ内で動くのでホスト側の衝突は起きません。
>
> **インターネット公開時:** 公式 how-to では、`nethernet` のシグナリングが HTTP/TCP であることから、`server-port` の前段にリバースプロキシ（nginx 等）を置いてレート制限を行うことを推奨しています。ゲーム通信そのものは UDP で直接流れるため、プロキシを通す必要があるのはシグナリングだけです。
>
> なお iOS 系クライアントはシグナリングポートに **TLS** で接続しますが、サーバー側は平文 HTTP を話すため、LAN 外からの接続が失敗する事例が報告されています（[BDS-23108](https://mojira.dev/BDS-23108)）。この場合は Caddy / nginx で TCP 側を TLS 終端する必要があります。**この構成はまだ本リポジトリに含まれていません。**

### 3. 起動

```bash
make up
```

サーバーバイナリは起動時に自動でダウンロードされます。`server/bedrock_server_edu` に手動配置するとダウンロードをスキップします。

### 4. デバイスコード認証

初回起動時にログ（`logs/world{N}/`）にデバイスコードとURLが出力されます。ブラウザでそのURLを開き、テナントのグローバル管理者アカウントでサインインしてください。

> テナント設定で「Allow Teachers to Manage Servers」が有効な場合は、教員（Faculty）アカウントでもサーバーの作成・認証ができます。ただしテナント側の Dedicated Server 有効化そのものは、グローバル管理者しか行えません。

サインイン後に `sessions/world{N}/edu_server_session.json` が生成され、以降は自動更新されます。

### 5. サーバーを有効化

[Dedicated Server Admin Portal](https://aka.ms/dedicatedservers) でサーバーの **Enabled** をオンにしてください（オフのままでは誰も参加できません）。

**Broadcast** は任意です。

- **オン**: テナント内の全ユーザーのサーバー一覧に自動表示されます（ユーザー側から一覧を削除することはできません）。
- **オフ**: ユーザーがクライアントの「サーバーを追加」から、12桁の英数字（大文字小文字の区別なし）のサーバーIDを手入力して参加します。

---

## Makefile コマンド一覧

> **Windows の場合:** Docker Desktop は WSL2 上で動作するため、WSL2 のターミナル（Ubuntu 等）で実行してください。
>
> **`permission denied while trying to connect to the Docker daemon socket` になる場合:** 実行ユーザーが `docker` グループに属していません。以下で追加し、**一度ログアウトして入り直して**ください。
>
> ```bash
> sudo usermod -aG docker $USER    # 再ログイン後に有効
> ```
>
> **`make: command not found` になる場合（NAS 等）:** Docker デーモンへの接続に root 権限が必要で、かつ `make` が sudo の `PATH` に含まれていない環境では、以下のように現在の `PATH` を引き継いで実行してください。
>
> ```bash
> sudo env "PATH=$PATH" make up
> ```

```bash
# 本番運用
make up NOTIFY=true BACKUP=true    # 全ワールド + 通知 + 自動バックアップ

# 起動オプション
make up                            # 全ワールドのみ起動
make up WORLDS="1 2"              # 指定ワールドのみ起動
make up NOTIFY=true               # 通知スタックも一緒に起動
make up BACKUP=true               # バックアップサービスも一緒に起動

# その他
make build                        # イメージを再ビルド
make down                         # 全ワールドを停止
make restart                      # 全ワールドを再起動
make logs N=1                     # ワールド1 のログを表示
make ps                           # 全コンテナの状態を表示
make backup                       # 今すぐ手動バックアップ
make add                          # 新しいワールドを追加（ポート・UDP 範囲を自動採番）
make add PORT=19500               # ポートを明示して追加（100の倍数）
make ports                        # ポート割り当てと次に使えるポートを表示
make check-ports                  # ポート重複・UDP 範囲の未設定を検査（up 時に自動実行）
make dirs                         # マウント先ディレクトリを作成（up 時に自動実行）
```

> **設定ファイルを更新したときは再ビルドが必要:** `property-definitions.json` / `entrypoint.sh` / `Dockerfile` はビルド時にイメージへ COPY されるため、これらの変更（新バージョン対応の取り込みなど）を反映するにはイメージの再ビルドが必要です。
>
> ```bash
> make build   # イメージを再ビルド
> make down
> make up
> ```
>
> なお **Minecraft サーバーバイナリ自体は起動時に自動更新**されるため、バイナリのバージョンアップだけであれば再ビルドは不要です（再ビルドが必要なのは上記リポジトリ側ファイルを変更した場合）。

---

## トラブルシューティング

### ログやワールドデータが作られない / サーバーバイナリを毎回ダウンロードし直す

コンテナはホストの実行ユーザーと同じ UID で動きます（`make` が `id -u` / `id -g` の値を自動で渡すため、設定は不要です）。ホスト側ディレクトリがその UID で書き込めないと、ログもワールドデータも保存できず、サーバーバイナリも毎回ダウンロードし直しになります。

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

### 既存環境を更新した場合（UID 999 → 実行ユーザー）

以前のバージョンはコンテナ実行ユーザーが UID 999 固定でした。更新後はホストの実行ユーザーと同じ UID になるため、一度だけ所有者を移し替えてイメージを再ビルドしてください。

```bash
make down
sudo chown -R $(id -u):$(id -g) worlds sessions logs chat_logs server
make build
make up
```

所有者がホストの自分のユーザーになるため、以降はビヘイビアパックの配置やワールドデータのバックアップに `sudo` が不要になります。

> 別の UID で動かしたい場合（共有サーバーで専用アカウントを使う等）のみ、`.env` に `PUID=` / `PGID=` を書けばそちらが優先されます。変更後は `make build` が必要です。

---

## ディレクトリ構成

### プロジェクト構成（Git 管理対象）

```
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
logs/world{N}/                        # サーバーログ
chat_logs/world{N}/                   # チャットログ（CHAT_LOGGING_ENABLED=true のとき出力）
server/                               # サーバーバイナリ手動配置用（省略可）
```

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

> **前提:** ChatLog ファイルはサーバー本体の機能（`chat-logging-enabled`、1.21.133 以降）で出力されます。`.env` の `CHAT_LOGGING_ENABLED_COMMON=true`（既定値）が必要です。この設定はあとから変更できますが、反映にはサーバーの再起動が必要です。

---

## 参考資料

- [公式ドキュメント（Servers セクション）](https://edusupport.minecraft.net/hc/en-us/sections/46294021588884-Servers)
  - [Dedicated Server FAQ](https://edusupport.minecraft.net/hc/en-us/articles/41758309283348)
  - [Dedicated Server System Requirements](https://edusupport.minecraft.net/hc/en-us/articles/46913335157140)
  - [IT Admin: Create Dedicated Servers](https://edusupport.minecraft.net/hc/en-us/articles/46370720373908)
  - [Teacher View: Create Dedicated Servers](https://edusupport.minecraft.net/hc/en-us/articles/46295348713236)
  - [Dedicated Server Alternate Configuration](https://edusupport.minecraft.net/hc/en-us/articles/41757415076884)
  - [Modifying Existing Servers](https://edusupport.minecraft.net/hc/en-us/articles/46295288885268)（`server.properties` の各項目一覧）
  - [Dedicated Server Advanced Setup](https://edusupport.minecraft.net/hc/en-us/articles/48786821856532)（allowlist・パスコード）
  - [Enabling Cross-Tenant Play](https://edusupport.minecraft.net/hc/en-us/articles/51711271699092)（他テナントからの参加。本構成では未検証）

---

## ライセンス

リポジトリのコード: [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)（非商用利用のみ許可）

Minecraft Education Edition サーバーバイナリの利用は Microsoft の利用規約に従います。
