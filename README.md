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
SERVER_PORT_WORLD_1=19132        # ワールド1のポート（必須）
```

その他の設定は `_COMMON` 項目で全ワールドのデフォルト値を一括設定できます。個別ワールドで上書きしたい場合は `_WORLD_1` のように指定します。

> **優先順位:** 個別設定（`_WORLD_N`）> 共通設定（`_COMMON`）> デフォルト値

### 2. ワールド2以降を追加する場合

```bash
cp docker-compose.world{N}.yml.example docker-compose.world2.yml
# ファイル内の {N} をすべて 2 に置換（エディタの検索・置換で一括変換）
```

`.env` にポート番号を追加：

```bash
SERVER_PORT_WORLD_2=19134
```

### 3. 起動

```bash
# ワールド1のみ
docker compose up -d

# ワールド1 + 2
docker compose -f docker-compose.yml -f docker-compose.world2.yml up -d
```

サーバーバイナリは起動時に自動でダウンロードされます。`server/bedrock_server_edu` に手動配置するとダウンロードをスキップします。

### 4. デバイスコード認証

初回起動時にログ（`logs/world{N}/`）にデバイスコードとURLが出力されます。ブラウザでそのURLを開き、テナントのグローバル管理者アカウントでサインインしてください。

サインイン後に `sessions/world{N}/edu_server_session.json` が生成され、以降は自動更新されます。

### 5. サーバーを有効化

[Dedicated Server Admin Portal](https://aka.ms/dedicatedservers) でサーバーの **Enabled** と **Broadcast** をオンにしてください。

---

## ディレクトリ構成

```
worlds/world{N}/              # ワールドデータ
├── worlds/{LEVEL_NAME}/      # ゲームワールドデータ
├── behavior_packs/           # ビヘイビアパック
├── resource_packs/           # リソースパック
├── allowlist.json
├── permissions.json
└── packetlimitconfig.json

sessions/world{N}/            # Entra 認証セッション
logs/world{N}/                # サーバーログ
chat_logs/world{N}/           # チャットログ（Vector 通知に使用）
server/                       # サーバーバイナリ手動配置用
```

---

## 通知（Vector + Apprise）

プレイヤーの参加/退出・チャット・サーバーイベントを ntfy や LINE 等に通知できます。

```bash
cp vector/vector.toml.example vector/vector.toml
# vector.toml を編集して ntfy トピック等を設定

cp apprise/minecraft.yml.example apprise/minecraft.yml
# minecraft.yml を編集して通知先 URL を設定（LINE 等）

docker compose -f docker-compose.yml -f docker-compose.notify.yml up -d
```

ChatLog ファイル（`chat_logs/world{N}/`）を監視し、`[日時] - ` で始まる行をすべて通知します。

---

## 参考資料

- [公式ドキュメント](https://edusupport.minecraft.net/hc/en-us/sections/46294021588884-Servers)

---

## ライセンス

リポジトリのコード: [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)（非商用利用のみ許可）

Minecraft Education Edition サーバーバイナリの利用は Microsoft の利用規約に従います。
