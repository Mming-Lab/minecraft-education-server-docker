# Minecraft Education Edition Dedicated Server - Docker

1台のサーバーで、複数グループ分のMinecraft Educationワールドを同時運用するためのDocker構成です。

> **前提**: 公式ドキュメントに記載のサーバー構築手順（デバイスコード認証・管理ツールによる有効化など）を理解していることを前提としています。
> - [Dedicated Server 101](https://edusupport.minecraft.net/hc/en-us/articles/41758309283348)
> - [Dedicated Server Tooling and Scripting Guide](https://edusupport.minecraft.net/hc/en-us/articles/41757415076884)

---

## セットアップ

### 1. 環境設定

```bash
cp .env.example .env
```

`.env` を編集して最低限以下を設定します。

```bash
SERVER_PUBLIC_IP=192.168.1.100  # サーバーのIPアドレス（必須）
```

その他の設定は `_COMMON` 項目で全ワールドのデフォルト値を一括設定できます。個別ワールドで上書きしたい場合は `_WORLD_1` のように指定します。

> **優先順位:** 個別設定（`_WORLD_N`）> 共通設定（`_COMMON`）> デフォルト値

### 2. ワールドを追加

```bash
make add PORT=19132   # ワールド1
make add PORT=19134   # ワールド2（複数運用する場合）
```

ワールド番号は自動採番されます。ポート番号は `.env` にも自動追記されます。

### 3. 起動

```bash
make up
```

サーバーバイナリは起動時に自動でダウンロードされます。`server/bedrock_server_edu` に手動配置するとダウンロードをスキップします。

### 4. デバイスコード認証

初回起動時にログ（`logs/world{N}/`）にデバイスコードとURLが出力されます。ブラウザでそのURLを開き、テナントのグローバル管理者アカウントでサインインしてください。

サインイン後に `sessions/world{N}/edu_server_session.json` が生成され、以降は自動更新されます。

### 5. サーバーを有効化

[Dedicated Server Admin Portal](https://aka.ms/dedicatedservers) でサーバーの **Enabled** と **Broadcast** をオンにしてください。

---

## Makefile コマンド一覧

> **Windows の場合:** Docker Desktop は WSL2 上で動作するため、WSL2 のターミナル（Ubuntu 等）で実行してください。

```bash
make up                    # 全ワールドを起動
make up WORLDS="1 2"       # 指定ワールドのみ起動
make up NOTIFY=true        # 通知スタックも一緒に起動
make down                  # 全ワールドを停止
make restart               # 全ワールドを再起動
make logs N=1              # ワールド1 のログを表示
make ps                    # 全コンテナの状態を表示
make add PORT=19134        # 新しいワールドを追加
```

---

## ディレクトリ構成

### プロジェクト構成（Git 管理対象）

```
Makefile                              # ワールドの起動・追加コマンド
docker-compose.world{N}.yml.example   # ワールド定義テンプレート（make add が使用）
docker-compose.notify.yml             # 通知スタック（Vector + Apprise）
Dockerfile / entrypoint.sh            # コンテナ定義
.env.example                          # 環境変数テンプレート
addons/                               # Script API チャットロガーアドオン
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

sessions/world{N}/                    # Entra 認証セッション（IP変更時に再取得が必要）
logs/world{N}/                        # サーバーログ
chat_logs/world{N}/                   # チャットログ（Vector 通知に使用）
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

---

## 参考資料

- [公式ドキュメント](https://edusupport.minecraft.net/hc/en-us/sections/46294021588884-Servers)

---

## ライセンス

リポジトリのコード: [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)（非商用利用のみ許可）

Minecraft Education Edition サーバーバイナリの利用は Microsoft の利用規約に従います。
