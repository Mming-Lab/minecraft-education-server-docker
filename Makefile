# ================================================
# 使い方:
#   make up                    # 全ワールドを起動
#   make up WORLDS="1 2"       # 指定ワールドのみ起動
#   make up NOTIFY=true        # 通知スタックも一緒に起動
#   make down                  # 全ワールドを停止
#   make restart               # 全ワールドを再起動
#   make logs N=1              # ワールド1 のログを表示
#   make ps                    # 全コンテナの状態を表示
#   make build                 # イメージをビルド
#   make add PORT=19134        # 新しいワールドを追加
# ================================================

ifdef WORLDS
  _COMPOSE_FILES := $(foreach w,$(WORLDS),-f docker-compose.world$(w).yml)
else
  _COMPOSE_FILES := $(foreach f,$(wildcard docker-compose.world[0-9]*.yml),-f $(f))
endif

ifdef NOTIFY
  _COMPOSE_FILES += -f docker-compose.notify.yml
endif

.PHONY: up down restart logs ps build add

up:
	docker compose $(_COMPOSE_FILES) up -d

down:
	docker compose $(_COMPOSE_FILES) down

restart:
	docker compose $(_COMPOSE_FILES) restart

logs:
ifndef N
	$(error N が必要です。例: make logs N=1)
endif
	docker compose -f docker-compose.world$(N).yml logs -f

ps:
	docker compose $(_COMPOSE_FILES) ps

build:
	docker compose $(_COMPOSE_FILES) build

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
	 echo "  → make up で起動できます"
