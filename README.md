# Minecraft Education Edition Dedicated Server - Docker

1台のサーバーで、複数グループ分のMinecraft Educationワールドを同時運用するためのDocker構成です。

グループごとに異なるのはポート番号とわずかな差分だけ——
全グループ共通の設定を一か所にまとめ、グループごとに変えたい項目だけ上書きします。

> **前提**: このリポジトリは、公式ドキュメントに記載されているサーバーの構築・管理手順（デバイスコード認証、管理ツールによる有効化など）を理解していることを前提としています。
> - [Dedicated Server 101](https://edusupport.minecraft.net/hc/en-us/articles/41758309283348)
> - [Dedicated Server Tooling and Scripting Guide](https://edusupport.minecraft.net/hc/en-us/articles/41757415076884)

---

## こんな場面で役立ちます

- グループ間でワールドデータやログが混在するのを防ぎたい
- グループが増えるたびに同じ設定を一から繰り返したくない
- サーバー台数を増やさず1台でまとめて管理したい

---

## システム要件

- Docker & Docker Compose
- Microsoft Entra テナントのグローバル管理者権限

---

## セットアップ

### 1. 環境設定ファイルをコピー

```bash
cp .env.example .env
```

### 2. 全グループ共通の設定を決める

`.env` の `_COMMON` 項目に、全グループで使う共通値を設定します。

```bash
SERVER_PUBLIC_IP=192.168.1.100  # サーバーのIPアドレス（必須）
GAMEMODE_COMMON=creative         # 全グループ共通のゲームモード
MAX_PLAYERS_COMMON=10            # 全グループ共通の最大人数
```

設定できる項目と選択肢は `.env.example` のコメントを参照してください。

### 3. グループごとの差分を設定する

ポート番号は必須です。それ以外は共通設定と変えたい項目だけ設定します。

```bash
SERVER_PORT_WORLD_1=19132   # グループ1のポート（必須）
SERVER_PORT_WORLD_2=19134   # グループ2のポート（必須）

GAMEMODE_WORLD_2=survival   # グループ2だけゲームモードを変更
```

設定しなかった項目は自動的に `_COMMON` の値が使われます。

> **優先順位:** 個別設定（`_WORLD_N`）> 共通設定（`_COMMON`）> デフォルト値

### 4. グループ2以降のComposeファイルを追加する

グループ1は `docker-compose.yml` に含まれています。グループ2以降はテンプレートから作成します。

```bash
cp docker-compose.world{N}.yml.example docker-compose.world2.yml
```

コピーしたファイルを開き、**ファイル内の `{N}` をすべて番号に置換**します（エディタの検索・置換で一括変換）。

### 5. 起動する

```bash
# グループ1のみ
docker compose up -d

# グループ1 + 2
docker compose -f docker-compose.yml -f docker-compose.world2.yml up -d
```

サーバーバイナリはコンテナ起動時に自動で最新版がダウンロードされます。

### 6. デバイスコード認証を行う

初回起動時、サーバーはログにデバイスコードを出力します。ログファイルを確認してブラウザでサインインしてください。

```
logs/world1/
```

ログにデバイスコードとURLが表示されたら、ブラウザでそのURLを開き、テナントのグローバル管理者アカウントでサインインします。
サインインが完了すると `sessions/world1/edu_server_session.json` が生成され、次回以降は自動的に認証が更新されます。

### 7. サーバーを有効化する

[Dedicated Server Admin Portal](https://aka.ms/dedicatedservers) にグローバル管理者アカウントでログインし、対象サーバーの **Enabled** トグルをオンにしてください。合わせて **Broadcast** トグルをオンにすると、クライアントのサーバー一覧に表示されます。

詳細は[公式ガイド](https://edusupport.minecraft.net/hc/en-us/articles/46295288885268)を参照してください。

---

## ディレクトリ構成

```
addons/                       # 自動配置されるビヘイビアパック（全ワールド共通）
└── chat_logger_bp/           # 同梱: チャットロガー

worlds/world{N}/              # ワールドデータ（フォルダごと移植可能）
├── worlds/{LEVEL_NAME}/      # ゲームワールドデータ
│   ├── world_behavior_packs.json  # 適用するビヘイビアパック（自動更新）
│   └── world_resource_packs.json  # 適用するリソースパック
├── behavior_packs/           # ビヘイビアパック置き場
├── resource_packs/           # リソースパック置き場
├── allowlist.json            # ホワイトリスト
├── permissions.json          # プレイヤー権限（operator/member/visitor）
└── packetlimitconfig.json    # パケット制限

sessions/world{N}/            # Entra認証セッション
logs/world{N}/                # サーバーログ
```

---

## アドオン（Add-on）

`addons/` フォルダに置いたビヘイビアパックは、コンテナ起動時に自動で配置・登録されます。

### 同梱アドオン

| アドオン | 説明 |
|---|---|
| `chat_logger_bp` | チャットメッセージをサーバーログに出力（LoggiFly 通知用） |

> **Script API について**: `addons/` のアドオンが Script API を使う場合、Beta APIs（`gametest=1`）がコンテナ起動時に自動で有効化されます。

### カスタムアドオンを追加する

`addons/` にパックフォルダを追加してコンテナを再起動するだけです。`manifest.json` の `header.uuid` と `version` が自動で `world_behavior_packs.json` に登録されます。

ワールドデータ側（`worlds/world{N}/behavior_packs/`）に直接配置する従来の方法も引き続き使えます。

---

## ログ監視・通知（LoggiFly）

[LoggiFly](https://github.com/clemcer/LoggiFly)でプレイヤーの参加/退出・チャット・サーバーイベントを通知できます。

```bash
cp loggifly/config.yaml.example loggifly/config.yaml
# config.yaml を編集して通知先（ntfy / LINE / Discord 等）を設定

docker compose -f docker-compose.yml -f docker-compose.loggifly.yml up -d
```

`global_keywords` を使っているため、ワールドを追加しても設定の変更は不要です。設定例は `loggifly/config.yaml.example` を参照してください。

---

## 参考資料

- [公式ドキュメント](https://edusupport.minecraft.net/hc/en-us/sections/46294021588884-Servers)

---

## ライセンス

リポジトリのコード: [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)（非商用利用のみ許可）

Minecraft Education Edition サーバーバイナリの利用は Microsoft の利用規約に従います。
