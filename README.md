# Minecraft Education Edition Dedicated Server - Docker

Docker環境でMinecraft Education Edition Dedicated Serverを実行します。

> サーバーバイナリはコンテナ起動時に自動で最新版がダウンロードされます。

## システム要件

- Docker & Docker Compose
- Azure AD グローバル管理者権限

## クイックスタート

### 1. 環境設定

```bash
cp .env.example .env
```

`.env` を編集し、最低限以下を設定してください（詳細は `.env.example` 参照）：

```bash
SERVER_PUBLIC_IP=192.168.1.100
SERVER_PORT_WORLD_1=19132
```

### 2. サーバー起動

```bash
docker compose up -d minecraft-edu-world1
docker compose logs -f minecraft-edu-world1
```

### 3. サーバー有効化

起動後、[サーバー管理ツール（Python Notebook）](https://aka.ms/MCEDU-DS-Tooling)で `Enabled=True` に設定してください。

詳細は[公式ガイド](https://edusupport.minecraft.net/hc/en-us/articles/41757415076884)を参照してください。

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

## 複数ワールド運用

```bash
# テンプレートをコピーして {N} を実際の番号に置換
cp docker-compose.world{N}.yml.example docker-compose.world2.yml

# .env にポート番号を追加
SERVER_PORT_WORLD_2=19134

# 起動
docker compose -f docker-compose.yml -f docker-compose.world2.yml up -d
```

設定の優先順位: **個別設定（`_WORLD_N`）> 共通設定（`_COMMON`）> デフォルト値**

## ログ監視・通知（LoggiFly）

[LoggiFly](https://github.com/clemcer/LoggiFly)でプレイヤーの参加/退出やサーバーイベントを通知できます。

```bash
cp loggifly/config.yaml.example loggifly/config.yaml
# config.yaml を編集して通知先を設定

docker compose -f docker-compose.yml -f docker-compose.loggifly.yml up -d
```

設定例は `loggifly/config.yaml.example` を参照してください。

## 参考資料

- [公式ドキュメント](https://edusupport.minecraft.net/hc/en-us/sections/46294021588884-Servers)

## ライセンス

リポジトリのコード: [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)（非商用利用のみ許可）

Minecraft Education Edition サーバーバイナリの利用は Microsoft の利用規約に従います。
