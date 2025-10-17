# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

**Minecraft Education Edition Dedicated Server**のDocker環境です。Ubuntu 22.04上で動作し、初回起動時にAzure AD認証（Device Code認証）が必要です。

**複数ワールド運用対応**: デフォルトで複数ワールドを同時運用できる設計になっています。

## アーキテクチャ

### 設定管理パターン

**3段階フォールバック環境変数**による一元管理方式を採用:

1. すべてのサーバー設定を`.env`ファイルで定義（`_COMMON`と`_WORLD{N}`サフィックス）
2. `docker-compose.yml`が環境変数をコンテナに渡す（個別 → 共通 → デフォルトの順で解決）
3. `entrypoint.sh`が起動時に`sed`コマンドで`server.properties`を動的更新
4. `server.properties`はgit管理対象外（毎回生成される）

この設計により`.env`が唯一の設定情報源となります。

### ファイル永続化戦略

**ワールド別ディレクトリマウント方式**を採用し、すべての永続データを自動管理:

1. **永続データ**（ホストからディレクトリマウント - 自動作成）:
   - `worlds/world1/`, `worlds/world2/` - 各ワールドのセーブデータ（完全分離）
   - `sessions/world1/`, `sessions/world2/` - 各ワールドのAzure AD認証セッション（`edu_server_session.json`を含む）
   - `configs/world1/`, `configs/world2/` - 各ワールドの設定ファイル（`allowlist.json`, `permissions.json`, `packetlimitconfig.json`）

2. **実行時生成**（コンテナ内部）:
   - `server.properties` - 環境変数から動的生成・更新
   - シンボリックリンク（`configs/` → 設定ファイル, `sessions/` → `edu_server_session.json`）

3. **リポジトリ管理**（テンプレート/デフォルト値）:
   - `.env`, `entrypoint.sh`, `Dockerfile`, `docker-compose.yml`
   - `TEST_PLAN.md` - テスト計画書

### 認証フロー

初回起動時にAzure AD Device Code認証が必要:
- サーバーがコードとURLを表示
- ユーザーがブラウザで認証
- セッションが`edu_server_session.json`に保存
- 以降の起動ではこのセッションを再利用

## よく使うコマンド

### 開発・運用（単一ワールド）

```bash
# コンテナのビルド
docker-compose build

# サーバー起動（デタッチモード）
docker-compose up -d

# Device Code確認（全ワールド）
docker-compose logs | grep "devicelogin"           # Linux/Mac
docker-compose logs | Select-String "devicelogin"  # Windows PowerShell

# サーバーホスト情報確認（認証完了後）
docker-compose logs | grep "successfully hosted"           # Linux/Mac
docker-compose logs | Select-String "successfully hosted"  # Windows PowerShell

# 詳細ログ確認（特定ワールド）
docker-compose logs -f minecraft-edu-world1

# サーバー再起動（.envの変更を適用）
docker-compose restart

# サーバー停止
docker-compose down

# 完全削除（ボリューム/ワールドも削除）
docker-compose down -v
```

### 複数ワールド運用

```bash
# 全ワールドを起動
docker-compose up -d

# 特定のワールドのみ起動
docker-compose up -d minecraft-edu-world1
docker-compose up -d minecraft-edu-world2

# 特定のワールドのみ停止
docker-compose stop minecraft-edu-world2

# 全ワールドのDevice Code確認
docker-compose logs | grep "devicelogin"

# 特定のワールドのホスト情報確認
docker-compose logs minecraft-edu-world1 | grep "successfully hosted"

# 全ワールドのログを確認
docker-compose logs -f

# 特定のワールドのログのみ確認
docker-compose logs -f minecraft-edu-world2
```

### 設定変更

1. `.env`ファイルを編集
2. `docker-compose restart`を実行
3. `entrypoint.sh`が自動で設定を反映

### 再認証

```bash
# セッションをクリアして新規Device Code認証を実行
rm sessions/world1/edu_server_session.json
docker-compose restart minecraft-edu-world1
```

### 複数ワールド運用

複数のワールドを同時運用できます:

```bash
# docker-compose.ymlのテンプレートからワールド2を追加
# 1. docker-compose.ymlの末尾のテンプレートをコピー
# 2. {N} → 2 に置換
# 3. .envにSERVER_PORT_WORLD2を設定

# ワールド2を起動
docker-compose up -d minecraft-edu-world2

# 特定のワールドだけを起動/停止
docker-compose up -d minecraft-edu-world1
docker-compose stop minecraft-edu-world2

# 全ワールドのDevice Code確認（初回認証時）
docker-compose logs | grep "devicelogin"           # Linux/Mac
docker-compose logs | Select-String "devicelogin"  # Windows PowerShell

# 全ワールドのホスト情報確認（認証完了後）
docker-compose logs | grep "successfully hosted"           # Linux/Mac
docker-compose logs | Select-String "successfully hosted"  # Windows PowerShell

# 特定ワールドのログ確認
docker-compose logs -f minecraft-edu-world2
```

**特徴:**
- 3段階フォールバック環境変数（個別 → 共通 → デフォルト）
- 各ワールドのデータ完全分離（worlds/world1, worlds/world2）
- プレースホルダー `{N}` 形式のテンプレートで簡単にワールド追加可能

## 技術的な重要事項

### ポート設定
- **19132/udp**: IPv4接続（`SERVER_PORT`で設定可能）
- **19133/udp**: IPv6接続（`SERVER_PORTV6`で設定可能）
- 外部アクセスには両方のファイアウォール開放が必要

### entrypoint.shの役割
1. `configs/`と`sessions/`ディレクトリの自動作成
2. 設定ファイルの初期化（`configs/allowlist.json`, `permissions.json`, `packetlimitconfig.json`）
3. シンボリックリンクの作成（サーバーバイナリがファイルを参照できるように）
4. 環境変数から`server.properties`を`sed`パターンマッチングで動的更新
5. 初回起動時の認証プロンプト表示処理
6. `bedrock_server_edu`バイナリの実行

### 環境変数の命名規則

**3段階フォールバック構造（docker-compose.yml + .env）:**
- スネークケース大文字: `SERVER_PORT_WORLD_1`, `MAX_PLAYERS_COMMON`, `LEVEL_NAME_WORLD_2`
- 真偽値は文字列: `"true"` または `"false"`
- `server.properties`のキーと直接対応（snake_case → kebab-case）

**優先順位:**
1. `GAMEMODE_WORLD_1` - ワールド個別設定（最優先）
2. `GAMEMODE_COMMON` - 全ワールド共通設定
3. デフォルト値 - docker-compose.yml内で定義

**ワールド追加:**
- ワールド番号: `WORLD1`, `WORLD2`, `WORLD{N}` 形式
- テンプレート展開: `{N}` プレースホルダーを実際の番号に置換
- 必須設定: `SERVER_PORT_WORLD{N}`（各ワールドで異なるポート番号）
- 任意設定: `SERVER_PORTV6_WORLD{N}`（IPv6を使用する場合のみ）

## 重要な制約事項

- **`server.properties`を手動編集しない** - コンテナ起動時に毎回再生成されます
- **`sessions/`, `configs/`, `worlds/`ディレクトリをコミットしない** - 環境固有データと認証トークンが含まれます
- **DockerfileでUbuntu 18+以外を使用しない** - 公式要件です
- サーバーバイナリは`https://aka.ms/downloadmee-linuxServerBeta`からダウンロード（Microsoft公式エンドポイント）
- **ディレクトリとファイルは自動作成される** - 手動でのディレクトリ作成は不要

## 設定リファレンス

### 環境変数設定（.env）
すべての設定はファイル内にインラインドキュメントがあります。主なカテゴリ:
- **サーバー基本設定**: `SERVER_PUBLIC_IP`, `SERVER_PORT_WORLD{N}`, `SERVER_PORTV6_WORLD{N}`
- **共通設定（_COMMON）**: 全ワールドのデフォルト値
  - ゲームモード、難易度、最大プレイヤー数、チート、チャット制限
  - レベル名、描画距離、ティック距離
  - アイドルタイムアウト、デフォルト権限
  - 最大スレッド数、テクスチャパック強制、ログ記録
- **個別設定（_WORLD{N}）**: 特定ワールドのカスタマイズ（共通設定を上書き）

### 設定例
```bash
# 全ワールド共通
GAMEMODE_COMMON=survival
MAX_PLAYERS_COMMON=40

# World1だけクリエイティブモード
GAMEMODE_WORLD_1=creative

# World2は共通設定を使用（GAMEMODE_COMMON=survivalが適用される）
```

## サーバーバイナリの更新

```bash
# 1. コンテナを停止
docker-compose down

# 2. イメージを再ビルド（最新バイナリを取得）
docker-compose build --no-cache

# 3. 新しいバイナリで起動
docker-compose up -d
```

**重要**: ワールドデータ・認証セッション・設定ファイルはすべて保持されます。

## テスト

包括的なテスト計画は[TEST_PLAN.md](TEST_PLAN.md)を参照してください。

### 主なテストカテゴリ
1. **基本動作テスト**: イメージビルド、コンテナ起動、ログ出力、ディレクトリ生成
2. **設定変更テスト**: 環境変数反映、ポート設定、IP設定
3. **認証フローテスト**: 初回認証、セッション再利用、再認証
4. **複数ワールド運用テスト**: フォールバック動作、同時起動、ポート分離
5. **エラーハンドリングテスト**: 不正値、ポート競合、パーミッション、ネットワーク切断
6. **クライアント接続テスト**: サーバーID取得、有効化、ゲームプレイ
7. **永続化テスト**: ワールドデータ、設定ファイルの永続化
8. **パフォーマンステスト**: 負荷テスト、長時間稼働テスト
9. **アップグレードテスト**: サーバーバイナリ更新

## ファイル修正ガイド

### 修正可能なファイル
- **.env**: 自由に修正可能。変更後は`docker-compose restart`で反映
- **docker-compose.yml**: ワールド追加・設定調整時に修正
- **entrypoint.sh**: 起動スクリプトのカスタマイズが必要な場合のみ修正
- **Dockerfile**: Ubuntu/依存ライブラリの更新が必要な場合のみ修正
- **README.md / CLAUDE.md**: ドキュメント更新

### 修正してはいけないファイル
- **server.properties**: コンテナ起動時に毎回再生成されます（手動編集は無視される）
- **worlds/**, **sessions/**, **configs/**: 環境固有データなのでコミットしない

### entrypoint.sh修正時の注意点
`entrypoint.sh`を修正した場合、以下を確認してください:
1. LF形式（Unix改行）を使用していることを確認
2. `server.properties`の更新パターンが正しいか確認（sed置換パターン）
3. ディレクトリ・シンボリックリンクの作成順序は変えない
4. 最後の`exec ./bedrock_server_edu`は保持する

## ログ管理と Zabbix 監視

### アーキテクチャ

```
Minecraft サーバー stdout/stderr
     ↓
Docker local ドライバー（自動管理）
├─ 最大 100MB でファイルをローテーション
├─ 7世代保持（超過分は自動削除）
└─ 自動 gzip 圧縮
     ↓ ボリュームマウント
./logs/world1/ に永続化
     ↓
Zabbix Agent コンテナ
     ↓ logrt[] で監視
Zabbix Server へレポート
```

### ログファイル

```
logs/
├── world1/
│   ├── server_2025-10-18.log
│   ├── server_2025-10-17.log.gz
│   ├── server_2025-10-16.log.gz
│   └── ... (最大 7 世代)
└── world2/
    └── server_2025-10-18.log
```

### Docker local ドライバーの機能

| 機能 | 詳細 |
|------|------|
| **自動ローテーション** | max-size に達したら自動実行 |
| **自動削除** | max-file を超えた古いファイルは自動削除 |
| **自動圧縮** | 回転したファイルは自動 gzip 圧縮 |
| **ディスク効率化** | 圧縮により 70-80% のディスク節約 |

### 設定（docker-compose.yml）

```yaml
logging:
  driver: "local"
  options:
    max-size: "100m"    # ファイルが 100MB で自動ローテーション
    max-file: "7"       # 7世代保持（超過分は自動削除）
    compress: "true"    # 自動圧縮（デフォルト有効）
```

**計算：** 100MB × 7 世代 = 約 700MB ディスク容量

### セットアップ手順

#### 1. docker-compose.yml を起動
```bash
docker-compose up -d
```

#### 2. ログファイルを確認
```bash
# ログが生成されているか確認
ls -la logs/world1/

# ファイルサイズを確認
du -sh logs/world1/
```

#### 3. Zabbix Server と連携（別途設定）

Zabbix Server を構築後、以下で Zabbix Agent を登録：
- **ホスト名**: minecraft-monitoring
- **ホスト IP**: Docker ホストの IP アドレス
- **エージェントポート**: 10050

### Zabbix での監視設定

#### ログアイテム（Zabbix Server 側）

```
アイテムタイプ: Zabbix エージェント
ホスト: minecraft-monitoring

キー: log[/var/log/minecraft/world1.log,ERROR|Exception|Crash]
  → エラーログを監視

キー: log[/var/log/minecraft/world1.log,Player connected]
  → プレイヤー接続を監視

キー: log[/var/log/minecraft/world1.log,devicelogin]
  → 初回認証を監視
```

#### トリガー例

```
{minecraft-monitoring:log[/var/log/minecraft/world1.log,ERROR|Exception|Crash].nodata(5m)}>0
  → 5分間にエラーが発生した場合にアラート

{minecraft-monitoring:log[/var/log/minecraft/world1.log,Crash].regexp(Crash,0)}
  → クラッシュログを検出したら即座にアラート
```

### ログローテーション（自動実行）

Docker local ドライバーが自動で管理するため、手動操作は不要です。

```bash
# ログファイルの状態確認
ls -lah logs/world1/

# 7世代を超えたら古いファイルは自動削除
# 100MB を超えたら自動ローテーション
# 圧縮済みファイルは .gz 拡張子
```

### トラブルシューティング

#### Zabbix Agent が接続できない
```bash
# Zabbix Agent コンテナのログを確認
docker-compose logs zabbix-agent -f

# ポート 10050 がリッスンしているか確認
netstat -tulnp | grep 10050
```

#### ログファイルが削除されない
```bash
# docker-compose.yml の設定を確認
grep -A 5 "logging:" docker-compose.yml

# Docker ドライバーのログを確認
docker inspect minecraft-edu-world1 | grep -A 10 "LogConfig"
```

#### ログディレクトリの権限問題
```bash
# logs ディレクトリの権限を確認
ls -la logs/

# 必要に応じて権限を修正
chmod 755 logs/
chmod 644 logs/world1/*.log
```

---

## 開発時のトラブルシューティング

### ポート競合エラー
```bash
# ポートが既に使用されているか確認
docker-compose logs minecraft-edu-world1 | grep "address already in use"

# 別のプロセスがポートを使用しているか確認（Linux/Mac）
lsof -i :19132

# 別のワールドとポート番号が重複していないか確認
grep SERVER_PORT_WORLD .env
```

### 設定が反映されない
```bash
# 1. .envファイルの内容を確認
cat .env | grep GAMEMODE

# 2. コンテナの環境変数を確認
docker exec minecraft-edu-world1 env | grep GAMEMODE

# 3. server.propertiesの内容を確認
docker exec minecraft-edu-world1 cat server.properties | grep gamemode
```

### 認証セッションの問題
```bash
# 既存セッションを削除して再認証
rm sessions/world1/edu_server_session.json
docker-compose restart minecraft-edu-world1

# セッションファイルのサイズを確認（0でなければOK）
ls -la sessions/world1/edu_server_session.json
```

### Device Codeが表示されない
```bash
# ログから認証関連のメッセージをフィルタリング
docker-compose logs minecraft-edu-world1 | grep -i "device\|auth\|code"

# コンテナが正常に起動しているか確認
docker-compose ps

# 前回のセッションファイルが有効なまま存在しているか確認
ls -la sessions/world1/
```
