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
#   make add                         # 新しいワールドを追加（ポートは自動採番）
#   make add PORT=19500              # ポートを明示して追加（100の倍数）
#   make sync                        # テンプレート変更を既存 worldN.yml に反映（再生成）
#   make ports                       # ポート割り当てと次に使えるポートを表示
#   make check-ports                 # ポート重複・UDP 範囲の未設定を検査
#   make dirs                        # マウント先ディレクトリを作成
#                                    #（up / restart / build 実行時にも自動で走る）
#
# 【ポートの割り当て】
#   1ワールドが連続した100ポートの帯を占める。先頭がシグナリング、
#   残り99本が nethernet のゲーム通信用。transport=nethernet は
#   「参加者1人につき UDP ポート1つ」を確保するため、同時接続数ぶんの
#   UDP 範囲が必要（単一ポートだと同時1接続に制限される）。
#   帯は100境界に揃うので重ならず、ファイアウォールや VPS の転送設定も
#   1ワールド1ルール（例: 19200-19299）で済む。make ports で確認できる。
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
#
# 【ログやワールドデータが作られない場合】
#   マウント先ディレクトリにコンテナ実行ユーザー（既定では make 実行ユーザーと
#   同じ UID）が書き込めていない。対処は README の「トラブルシューティング」を参照。
#   sudo make up で起動しても解決しない（コンテナ内は常に PUID で動くため）。
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

# コンテナ実行ユーザーの UID/GID。ホスト側ディレクトリの所有者と揃えるために使う。
# 通常は設定不要で、make 実行ユーザーの値を自動採用する。
# 別の値にしたい場合だけ .env に PUID= / PGID= を書く（変更後はイメージの再ビルドが必要）。
PUID := $(shell sed -n 's/^PUID=//p' .env 2>/dev/null | tail -1)
PGID := $(shell sed -n 's/^PGID=//p' .env 2>/dev/null | tail -1)
ifeq ($(strip $(PUID)),)
  PUID := $(shell id -u 2>/dev/null || echo 1000)
endif
ifeq ($(strip $(PGID)),)
  PGID := $(shell id -g 2>/dev/null || echo 1000)
endif
export PUID
export PGID

# ポート割り当てのパラメータ。
# PORT_BLOCK … 1ワールドが占めるポート数（先頭がシグナリング、残り99本がゲーム通信用）
# PORT_BASE  … 最初のワールドに割り当てるポート
# この帯は VPS の iptables 転送やクラウドのセキュリティリストにも登録することになり、
# 後から変えると外部設定の修正が連鎖するため、一度決めたら変えない運用を前提とする。
# なお Linux の既定エフェメラルポート帯（32768-60999）と重なる値は避けること
# （公式 how-to の例 49152-49200 はこの帯の内側で、ホストの他プロセスと衝突しうる）。
PORT_BLOCK ?= 100
PORT_BASE ?= 19200

# 次に使えるポート。既存のシグナリングポートと UDP 範囲の終端から、
# どちらも跨がない次の100境界を求める（ワールドが無ければ PORT_BASE）。
# make add がポート省略時に使い、make ports が提案値として表示する。
_NEXT_PORT = $(shell { sed -n 's/^SERVER_PORT_WORLD_[0-9]*=//p' .env 2>/dev/null; sed -n 's/^SERVER_UDP_RANGE_WORLD_[0-9]*=//p' .env 2>/dev/null | sed 's/.*-//'; } | tr -d "\r" | awk -v b=$(PORT_BLOCK) -v base=$(PORT_BASE) '{ if ($$1+0 == $$1 && $$1 != "") { p=(int($$1/b)+1)*b; if (p>m) m=p } } END { print (m>base ? m : base) }')

# make add のポート。PORT を渡さなければ自動採番する。
ifdef PORT
  _PORT := $(PORT)
else
  _PORT = $(_NEXT_PORT)
endif

.PHONY: up down restart logs ps build add backup sync dirs ports check-ports

# 既存の docker-compose.worldN.yml をテンプレートから再生成する。
# テンプレート（docker-compose.world{N}.yml.example）を変更したら、
# 手で各ファイルを直さずにこれで一括反映する。
# transport=nethernet のワールドにだけ、テンプレートの #@nethernet 行
# （ゲーム通信用 UDP 範囲の公開）を出力する。raknet のワールドで使わない範囲を
# 公開すると、起動コストもファイアウォールの開放範囲も無駄になるため。
sync:
	@set -e; \
	 _env() { sed -n 's/^'"$$1"'=//p' .env 2>/dev/null | tr -d '\r' | tail -1; }; \
	 for f in docker-compose.world[0-9]*.yml; do \
	   [ -e "$$f" ] || continue; \
	   N=$$(echo "$$f" | sed 's/^docker-compose\.world\([0-9]*\)\.yml$$/\1/'); \
	   T=$$(_env "TRANSPORT_WORLD_$$N"); \
	   [ -n "$$T" ] || T=$$(_env TRANSPORT_COMMON); \
	   T=$${T:-raknet}; \
	   if [ "$$T" = "nethernet" ]; then \
	     sed 's/{N}/'"$$N"'/g' 'docker-compose.world{N}.yml.example' > "$$f"; \
	     echo "同期: $$f （transport=nethernet: ゲーム通信用 UDP 範囲も公開）"; \
	   else \
	     sed 's/{N}/'"$$N"'/g' 'docker-compose.world{N}.yml.example' \
	       | grep -v '#@nethernet' > "$$f"; \
	     echo "同期: $$f （transport=$$T: UDP 範囲行は出力しない）"; \
	   fi; \
	 done

# ホスト側のマウント先ディレクトリを先に作成する。
# 存在しないまま docker compose up すると Docker デーモン（root）が作成してしまい、
# 非 root で動くコンテナがログもワールドデータも書き込めなくなるため、
# make 実行ユーザーの権限で先回りして作る。
dirs:
	@BASE=$$(sed -n 's/^VOLUMES_BASE_PATH=//p' .env 2>/dev/null | tail -1); \
	 BASE=$${BASE:-./}; \
	 mkdir -p "$${BASE}server"; \
	 for f in docker-compose.world[0-9]*.yml; do \
	   [ -e "$$f" ] || continue; \
	   N=$$(echo "$$f" | sed 's/^docker-compose\.world\([0-9]*\)\.yml$$/\1/'); \
	   mkdir -p "$${BASE}worlds/world$$N" "$${BASE}sessions/world$$N" \
	            "$${BASE}logs/world$$N" "$${BASE}chat_logs/world$$N"; \
	 done

# ワールドごとのポート割り当てを一覧表示し、次に使えるポートも示す。
# ファイアウォール申請や手順書の更新で毎回 .env を読み解くのは事故るため、
# 「今どこを使っているか」を1コマンドで確認できるようにしてある。
ports:
	@_env() { sed -n 's/^'"$$1"'=//p' .env 2>/dev/null | tr -d '\r' | tail -1; }; \
	 echo "1ワールド = 連続した $(PORT_BLOCK) ポートの帯。先頭がシグナリング、残りがゲーム通信用"; \
	 echo "SIGNALING … raknet では UDP、nethernet では TCP で待ち受ける"; \
	 echo "UDP_RANGE … nethernet のゲーム通信用（接続ごとに1ポート消費）"; \
	 echo ""; \
	 printf '%-9s %-11s %-10s %-14s %s\n' WORLD TRANSPORT SIGNALING UDP_RANGE PORTS; \
	 for f in docker-compose.world[0-9]*.yml; do \
	   [ -e "$$f" ] || continue; \
	   N=$$(echo "$$f" | sed 's/^docker-compose\.world\([0-9]*\)\.yml$$/\1/'); \
	   P=$$(_env "SERVER_PORT_WORLD_$$N"); \
	   T=$$(_env "TRANSPORT_WORLD_$$N"); \
	   [ -n "$$T" ] || T=$$(_env TRANSPORT_COMMON); \
	   T=$${T:-raknet}; \
	   R=$$(_env "SERVER_UDP_RANGE_WORLD_$$N"); \
	   if [ -n "$$R" ]; then \
	     C=$$(( $${R##*-} - $${R%%-*} + 1 )); \
	   else \
	     C="-"; \
	     if [ "$$T" = "nethernet" ]; then R="(未設定)"; fi; \
	   fi; \
	   printf '%-9s %-11s %-10s %-14s %s\n' "world$$N" "$$T" "$${P:--}" "$${R:--}" "$$C"; \
	 done; \
	 echo ""; \
	 echo "次に使えるポート: $(_NEXT_PORT)   →   make add   （PORT を省略すればこれが使われます）"; \
	 echo "  帯は $(_NEXT_PORT)-$$(($(_NEXT_PORT) + $(PORT_BLOCK) - 1))。nethernet のワールドは、この帯を UDP で"; \
	 echo "  ホストのファイアウォール／VPS の iptables 転送／クラウドのセキュリティリストに開放します"

# ポート設定の整合性を検査する（up / restart / build の前に自動で走る）。
# 帯が重ならないことは make add の100境界チェックで担保されるので、ここでは
# 「静かに壊れる」2つだけを見る: ポートの重複と、nethernet なのに UDP 範囲が無い状態。
check-ports:
	@_env() { sed -n 's/^'"$$1"'=//p' .env 2>/dev/null | tr -d '\r' | tail -1; }; \
	 ERR=0; COUNT=0; \
	 DUP=$$(sed -n 's/^SERVER_PORT_WORLD_[0-9]*=//p' .env 2>/dev/null | tr -d '\r' | sort | uniq -d); \
	 if [ -n "$$DUP" ]; then \
	   echo "エラー: 複数のワールドが同じポートを使っています: $$DUP"; \
	   echo "        同一ホストでポートが重複すると、参加者側に「無効なテナントID」エラーが出ます"; \
	   ERR=1; \
	 fi; \
	 for f in docker-compose.world[0-9]*.yml; do \
	   [ -e "$$f" ] || continue; \
	   N=$$(echo "$$f" | sed 's/^docker-compose\.world\([0-9]*\)\.yml$$/\1/'); \
	   COUNT=$$((COUNT + 1)); \
	   P=$$(_env "SERVER_PORT_WORLD_$$N"); \
	   T=$$(_env "TRANSPORT_WORLD_$$N"); \
	   [ -n "$$T" ] || T=$$(_env TRANSPORT_COMMON); \
	   T=$${T:-raknet}; \
	   R=$$(_env "SERVER_UDP_RANGE_WORLD_$$N"); \
	   O=$$(_env "SERVER_UDP_PORTS_WORLD_$$N"); \
	   [ -n "$$O" ] || O=$$(_env SERVER_UDP_PORTS_COMMON); \
	   if [ -z "$$P" ]; then \
	     echo "エラー: world$$N の SERVER_PORT_WORLD_$$N が .env にありません"; \
	     ERR=1; continue; \
	   fi; \
	   if [ "$$T" = "nethernet" ] && [ -z "$$R" ] && [ -z "$$O" ]; then \
	     echo "エラー: world$$N は transport=nethernet ですが SERVER_UDP_RANGE_WORLD_$$N が未設定です"; \
	     echo "        NetherNet は接続ごとに UDP ポートを1つ消費するため、範囲の確保が必須です"; \
	     echo "        .env に SERVER_UDP_RANGE_WORLD_$$N=$$((P + 1))-$$((P + $(PORT_BLOCK) - 1)) を追記してください"; \
	     ERR=1; \
	   fi; \
	 done; \
	 if [ "$$ERR" != 0 ]; then \
	   echo ""; \
	   echo "ポート設定に問題があります。make ports で割り当てを確認してください"; \
	   exit 1; \
	 fi; \
	 if [ "$$COUNT" != 0 ]; then echo "ポート検査: OK（$$COUNT ワールド）"; fi

up: sync check-ports dirs
	docker compose $(_COMPOSE_FILES) up -d

down:
	docker compose $(_COMPOSE_FILES) down

restart: sync check-ports dirs
	docker compose $(_COMPOSE_FILES) restart

logs:
ifndef N
	$(error N が必要です。例: make logs N=1)
endif
	docker compose -f docker-compose.world$(N).yml logs -f

ps:
	docker compose $(_COMPOSE_FILES) ps

build: sync check-ports dirs
	docker compose $(_COMPOSE_FILES) build

backup:
	@CONTAINER=$$(docker ps --filter "name=backup-weekly" --format "{{.Names}}" | head -1); \
	 if [ -z "$$CONTAINER" ]; then \
	   echo "エラー: バックアップサービスが起動していません。先に 'make up BACKUP=true' を実行してください"; \
	   exit 1; \
	 fi; \
	 docker exec $$CONTAINER backup

# 新しいワールドを追加する。
# PORT を省略すると _NEXT_PORT（次の空き境界）を使う。明示する場合は
# PORT_BLOCK の倍数で指定する（例: make add PORT=19500）。
# ゲーム通信用の UDP 範囲は常にその直後 99 本（PORT+1 〜 PORT+99）。
add:
	@set -e; \
	 _env() { sed -n 's/^'"$$1"'=//p' .env 2>/dev/null | tr -d '\r' | tail -1; }; \
	 P=$(_PORT); \
	 if [ $$((P % $(PORT_BLOCK))) != 0 ]; then \
	   echo "エラー: PORT は $(PORT_BLOCK) の倍数で指定してください（例: 19200, 19300）"; \
	   echo "        1ワールドが $(PORT_BLOCK) ポートの帯を使うため、境界を揃えないと"; \
	   echo "        隣のワールドの帯に食い込みます。PORT を省略すれば自動採番されます"; \
	   exit 1; \
	 fi; \
	 RS=$$((P + 1)); \
	 RE=$$((P + $(PORT_BLOCK) - 1)); \
	 if [ "$$RE" -gt 65535 ]; then \
	   echo "エラー: PORT=$$P では帯の終端が 65535 を超えます"; \
	   exit 1; \
	 fi; \
	 for pp in $$(sed -n 's/^SERVER_PORT_WORLD_[0-9]*=//p' .env 2>/dev/null | tr -d '\r'); do \
	   case "$$pp" in ''|*[!0-9]*) continue;; esac; \
	   if [ "$$pp" -ge "$$P" ] && [ "$$pp" -le "$$RE" ]; then \
	     echo "エラー: ポート $$pp を使っているワールドがあり、帯 $$P-$$RE と重なります"; \
	     echo "        make ports で次に使えるポートを確認してください"; \
	     exit 1; \
	   fi; \
	 done; \
	 N=$$(find . -maxdepth 1 -name 'docker-compose.world[0-9]*.yml' 2>/dev/null | wc -l); \
	 N=$$((N + 1)); \
	 while [ -e "docker-compose.world$$N.yml" ]; do N=$$((N + 1)); done; \
	 T=$$(_env TRANSPORT_COMMON); \
	 T=$${T:-raknet}; \
	 if [ "$$T" = "nethernet" ]; then \
	   sed 's/{N}/'"$$N"'/g' 'docker-compose.world{N}.yml.example' > "docker-compose.world$$N.yml"; \
	 else \
	   sed 's/{N}/'"$$N"'/g' 'docker-compose.world{N}.yml.example' \
	     | grep -v '#@nethernet' > "docker-compose.world$$N.yml"; \
	 fi; \
	 printf '\nSERVER_PORT_WORLD_%s=%s\n' "$$N" "$$P" >> .env; \
	 printf 'SERVER_UDP_RANGE_WORLD_%s=%s-%s\n' "$$N" "$$RS" "$$RE" >> .env; \
	 echo "ワールド$$N を追加しました (transport=$$T)"; \
	 echo "  → docker-compose.world$$N.yml を生成"; \
	 echo "  → 帯: $$P-$$RE（シグナリング $$P / ゲーム通信 $$RS-$$RE）"; \
	 echo "  → .env に SERVER_PORT_WORLD_$$N / SERVER_UDP_RANGE_WORLD_$$N を追記"; \
	 if [ "$$T" != "nethernet" ]; then \
	   echo "     ※ transport=$$T のため UDP 範囲はまだ公開されません"; \
	   echo "       nethernet に切り替えるときは .env に TRANSPORT_WORLD_$$N=nethernet を"; \
	   echo "       書いて make up（compose の公開ポートが再生成されます）"; \
	 fi; \
	 echo "  → make up または sudo env \"PATH=\$$PATH\" make up で起動できます"
