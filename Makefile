# ================================================
# 使い方:
#
# 【本番運用】
#   make up NOTIFY=true BACKUP=true   # 全ワールド + 通知 + 自動バックアップ
#
# 【起動オプション】
#   make up                           # 全ワールドのみ起動
#   make up WORLDS="1 2"             # 指定ワールドのみ起動
#   make up NOTIFY=true              # 通知スタックも一緒に起動
#   make up BACKUP=true              # バックアップサービスも一緒に起動
#
# 【その他】
#   make down                        # 全ワールドを停止
#   make restart                     # 全ワールドを再起動
#   make logs N=1                    # ワールド1 のログを表示
#   make ps                          # 全コンテナの状態を表示
#   make build                       # イメージをビルド
#   make backup                      # 今すぐ手動バックアップ
#   make add PORT=19134              # 新しいワールドを追加
#   make sync                        # テンプレート変更を既存 worldN.yml に反映（再生成）
#
# 【テンプレート（docker-compose.world{N}.yml.example）を変更したとき】
#   docker-compose.world{N}.yml.example が唯一のテンプレート。
#   既存の docker-compose.worldN.yml は {N} を番号に置換しただけの派生物なので、
#   手で編集せずに make sync（または make up 時に自動）で再生成する。
#
# 【permission denied / make: command not found になる場合（NAS 等）】
#   Docker への接続に root 権限が必要で、かつ make が sudo の PATH に
#   含まれていない環境では、現在の PATH を引き継いで実行する:
#     sudo env "PATH=$PATH" make up
# ================================================

ifdef WORLDS
  _COMPOSE_FILES := $(foreach w,$(WORLDS),-f docker-compose.world$(w).yml)
else
  _COMPOSE_FILES := $(foreach f,$(wildcard docker-compose.world[0-9]*.yml),-f $(f))
endif

ifdef NOTIFY
  _COMPOSE_FILES += -f docker-compose.notify.yml
endif

ifdef BACKUP
  _COMPOSE_FILES += -f docker-compose.backup.yml
endif

.PHONY: up down restart logs ps build add backup sync

# 既存の docker-compose.worldN.yml をテンプレートから再生成する。
# テンプレート（docker-compose.world{N}.yml.example）を変更したら、
# 手で各ファイルを直さずにこれで一括反映する。
sync:
	@for f in docker-compose.world[0-9]*.yml; do \
	   [ -e "$$f" ] || continue; \
	   N=$$(echo "$$f" | sed 's/^docker-compose\.world\([0-9]*\)\.yml$$/\1/'); \
	   sed 's/{N}/'"$$N"'/g' 'docker-compose.world{N}.yml.example' > "$$f"; \
	   echo "同期: $$f （テンプレートから再生成）"; \
	 done

up: sync
	docker compose $(_COMPOSE_FILES) up -d

down:
	docker compose $(_COMPOSE_FILES) down

restart: sync
	docker compose $(_COMPOSE_FILES) restart

logs:
ifndef N
	$(error N が必要です。例: make logs N=1)
endif
	docker compose -f docker-compose.world$(N).yml logs -f

ps:
	docker compose $(_COMPOSE_FILES) ps

build: sync
	docker compose $(_COMPOSE_FILES) build

backup:
	@CONTAINER=$$(docker ps --filter "name=backup-weekly" --format "{{.Names}}" | head -1); \
	 if [ -z "$$CONTAINER" ]; then \
	   echo "エラー: バックアップサービスが起動していません。先に 'make up BACKUP=true' を実行してください"; \
	   exit 1; \
	 fi; \
	 docker exec $$CONTAINER backup

add:
ifndef PORT
	$(error PORT が必要です。例: make add PORT=19134)
endif
	@N=$$(find . -maxdepth 1 -name 'docker-compose.world[0-9]*.yml' 2>/dev/null | wc -l); \
	 N=$$((N + 1)); \
	 sed 's/{N}/'"$$N"'/g' 'docker-compose.world{N}.yml.example' > "docker-compose.world$$N.yml"; \
	 printf '\nSERVER_PORT_WORLD_%s=%s\n' "$$N" "$(PORT)" >> .env; \
	 echo "ワールド$$N を追加しました (ポート: $(PORT))"; \
	 echo "  → docker-compose.world$$N.yml を生成"; \
	 echo "  → .env に SERVER_PORT_WORLD_$$N=$(PORT) を追記"; \
	 echo "  → make up または sudo env \"PATH=\$$PATH\" make up で起動できます"
