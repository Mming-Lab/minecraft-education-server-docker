# Minecraft Education Edition Dedicated Server - Docker

1台のサーバーで、複数クラス分のMinecraft Educationワールドを同時運用するための構成です。

クラスごとに異なるのはポート番号とわずかな差分だけ——
全クラス共通の設定を一か所にまとめ、クラスごとに変えたい項目だけ上書きします。

**学校のMicrosoft 365（Azure AD）アカウントで認証するため、外部サービスへの新規登録は不要です。**

---

## こんな場面で役立ちます

- クラス間でワールドデータやログが混在するのを防ぎたい
- クラスが増えるたびに同じ設定を一から繰り返したくない
- サーバー台数を増やさず1台でまとめて管理したい

---

## システム要件

- Docker & Docker Compose
- Azure AD グローバル管理者権限

---

## セットアップ

### 1. 環境設定ファイルをコピー

```bash
cp .env.example .env
```

### 2. 全クラス共通の設定を決める

`.env` の `_COMMON` 項目に、全クラスで使う共通値を設定します。

```bash
SERVER_PUBLIC_IP=192.168.1.100  # サーバーのIPアドレス（必須）
GAMEMODE_COMMON=creative         # 全クラス共通のゲームモード
MAX_PLAYERS_COMMON=10            # 全クラス共通の最大人数
```

設定できる項目と選択肢は `.env.example` のコメントを参照してください。

### 3. クラスごとの差分を設定する

ポート番号は必須です。それ以外は共通設定と変えたい項目だけ設定します。

```bash
SERVER_PORT_WORLD_1=19132   # クラス1のポート（必須）
SERVER_PORT_WORLD_2=19134   # クラス2のポート（必須）

GAMEMODE_WORLD_2=survival   # クラス2だけゲームモードを変更
```

設定しなかった項目は自動的に `_COMMON` の値が使われます。

> **優先順位:** 個別設定（`_WORLD_N`）> 共通設定（`_COMMON`）> デフォルト値

### 4. クラス2以降のComposeファイルを追加する

クラス1は `docker-compose.yml` に含まれています。クラス2以降はテンプレートから作成します。

```bash
cp docker-compose.world{N}.yml.example docker-compose.world2.yml
```

コピーしたファイルを開き、**ファイル内の `{N}` をすべて番号に置換**します（エディタの検索・置換で一括変換）。

### 5. 起動する

```bash
# クラス1のみ
docker compose up -d

# クラス1 + 2
docker compose -f docker-compose.yml -f docker-compose.world2.yml up -d
```

サーバーバイナリはコンテナ起動時に自動で最新版がダウンロードされます。

### 6. サーバーを有効化する

起動後、[サーバー管理ツール（Python Notebook）](https://aka.ms/MCEDU-DS-Tooling)で `Enabled=True` に設定してください。

詳細は[公式ガイド](https://edusupport.minecraft.net/hc/en-us/articles/41757415076884)を参照してください。

---

## ディレクトリ構成

```
worlds/world{N}/              # ワールドデータ（フォルダごと移植可能）
├── worlds/{LEVEL_NAME}/      # ゲームワールドデータ
│   ├── world_behavior_packs.json  # 適用するビヘイビアパック
│   └── world_resource_packs.json  # 適用するリソースパック
├── behavior_packs/           # ビヘイビアパック置き場
├── resource_packs/           # リソースパック置き場
├── allowlist.json            # ホワイトリスト
├── packetlimitconfig.json    # パケット制限

sessions/world{N}/            # Azure AD認証セッション
logs/world{N}/                # サーバーログ
```

---

## アドオン（Add-on）

1. パックを `worlds/world{N}/behavior_packs/` または `worlds/world{N}/resource_packs/` に配置
2. `worlds/{LEVEL_NAME}/world_behavior_packs.json` にパックのUUIDを記載

```json
[
  {
    "pack_id": "パックのmanifest.jsonにあるUUID",
    "version": [1, 0, 0]
  }
]
```

3. コンテナを再起動

---

## ログ監視・通知（LoggiFly）

[LoggiFly](https://github.com/clemcer/LoggiFly)でプレイヤーの参加/退出やサーバーイベントを通知できます。

```bash
cp loggifly/config.yaml.example loggifly/config.yaml
# config.yaml を編集して通知先を設定

docker compose -f docker-compose.yml -f docker-compose.loggifly.yml up -d
```

設定例は `loggifly/config.yaml.example` を参照してください。

---

## 参考資料

- [公式ドキュメント](https://edusupport.minecraft.net/hc/en-us/sections/46294021588884-Servers)

---

## ライセンス

リポジトリのコード: [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)（非商用利用のみ許可）

Minecraft Education Edition サーバーバイナリの利用は Microsoft の利用規約に従います。
