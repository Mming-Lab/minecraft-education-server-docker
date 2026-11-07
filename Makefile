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
# 【サーバーバイナリの更新】
#   make update                      # 新しければ確認の上で取得（直前の1世代を退避）
#   make update CHECK=1              # 新しいかどうかだけ調べる
#   make rollback                    # 直前のバージョンに戻す
#   make props                       # server.properties と定義ファイルの差分を表示
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

# サーバーバイナリの配布元。バージョン別の URL は公開されていないため、ここから
# 取れるのは常に「最新版」だけになる。だから更新は自動化せず、make update を
# 明示的に叩いたときだけ動かす（理由は update ターゲットのコメントを参照）。
SERVER_URL ?= https://aka.ms/downloadmee-linuxserver
# 展開後のバイナリがこのサイズ未満なら取得失敗とみなす（実物は 200MB 超）。
# 配布元が障害時に HTML のエラーページを 200 で返すことがあり、それをバイナリとして
# 配置してしまうと起動ループになるため検査する。
SERVER_MIN_SIZE ?= 50000000

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

.PHONY: up down restart logs ps build add backup sync dirs ports check-ports \
        update rollback props check-server

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
	@BASE=$$(sed -n 's/^VOLUMES_BASE_PATH=//p' .env 2>/dev/null | tr -d '\r' | tail -1); \
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

up: sync check-ports dirs check-server
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

# ================================================
# サーバーバイナリの取得と更新
# ================================================
# 取得はホスト側のこのターゲットだけが行う。コンテナ側（entrypoint.sh）は
# server/ に置かれているものをそのまま使うだけで、ダウンロードも更新もしない。
#
# 以前はコンテナ起動時に自動更新していたが、server/ は全ワールドで共有している
# 書き込み可能マウントなので、make up で複数ワールドが同時に起動すると全員が
# 同じ「新しい」判定をして同じファイルへ並行して unzip してしまう。あるワールドが
# 200MB 超のバイナリをコピーしている最中に別のワールドがそれを truncate するため、
# 壊れたバイナリで起動ループに入る。バージョンが上がった瞬間にしか起きないので
# 再現しづらく、しかも一番困るタイミング（授業直前の起動）で踏むことになる。
#
# 更新タイミングを人が決められること自体も重要で、クライアント（MCEE アプリ）の
# 配布時期とサーバーのバージョンがずれると参加者が全員接続できなくなりかねない。
# バージョンを固定したいなら、単に make update を実行しなければよい。
#
#   make update              # 新しければ確認の上で取得（直前の1世代を server.bak/ に退避）
#   make update CHECK=1      # 新しいかどうかだけ調べる（取得しない）
#   make update YES=1        # 確認を省略（非対話環境から呼ぶとき）
#   make update FORCE=1      # バージョンが同じでも取り直す
#
# 【ワールドデータは戻せない】
# 新しいバージョンで一度開いたワールドは不可逆にアップグレードされ、古いサーバーでは
# 読めなくなる。make rollback はバイナリを戻すだけなので、更新前に make backup か
# worlds/ のコピーを取っておくこと。
update:
	@set -e; \
	 BASE=$$(sed -n 's/^VOLUMES_BASE_PATH=//p' .env 2>/dev/null | tr -d '\r' | tail -1); \
	 BASE=$${BASE:-./}; \
	 SRV="$${BASE}server"; BAK="$${BASE}server.bak"; NEW="$${BASE}server.new"; \
	 VER="$$SRV/.server_version"; \
	 if command -v curl >/dev/null 2>&1; then \
	   _head() { curl -sIL --max-time 30 -A "Mozilla/5.0" "$$1"; }; \
	   _get() { curl -fL --progress-bar -A "Mozilla/5.0" -o "$$2" "$$1"; }; \
	 elif command -v wget >/dev/null 2>&1; then \
	   _head() { wget --spider -S --no-cache --timeout=30 --user-agent="Mozilla/5.0" "$$1" 2>&1; }; \
	   _get() { wget -q --show-progress --no-cache --user-agent="Mozilla/5.0" -O "$$2" "$$1"; }; \
	 else \
	   echo "エラー: curl か wget が必要です"; exit 1; \
	 fi; \
	 mkdir -p "$$SRV"; \
	 echo "配布元を確認しています: $(SERVER_URL)"; \
	 H=$$(_head "$(SERVER_URL)" 2>/dev/null || true); \
	 REMOTE=$$(echo "$$H" | grep -i '^[[:space:]]*ETag:' | tail -1 | sed 's/.*[Ee][Tt][Aa][Gg]:[[:space:]]*//' | tr -d '\r'); \
	 if [ -z "$$REMOTE" ]; then \
	   REMOTE=$$(echo "$$H" | grep -i '^[[:space:]]*Last-Modified:' | tail -1 | sed 's/.*[Mm]odified:[[:space:]]*//' | tr -d '\r'); \
	 fi; \
	 LOCAL=$$(sed -n '1p' "$$VER" 2>/dev/null | tr -d '\r'); \
	 FETCHED=$$(sed -n 's/^# fetched: //p' "$$VER" 2>/dev/null | tail -1); \
	 if [ -f "$$SRV/bedrock_server_edu" ]; then \
	   echo "  手元  : $${LOCAL:-（.server_version なし＝手動配置）}$${FETCHED:+   取得日 $$FETCHED}"; \
	 else \
	   echo "  手元  : バイナリがありません（初回構築）"; \
	 fi; \
	 echo "  配布元: $${REMOTE:-（取得できませんでした）}"; \
	 if [ -z "$$REMOTE" ]; then \
	   echo ""; \
	   echo "警告: 配布元のバージョン情報を取得できませんでした（ネットワークか配布元の問題）"; \
	   if [ -f "$$SRV/bedrock_server_edu" ] && [ -z "$(FORCE)" ]; then \
	     echo "      手元のバイナリはそのまま使えます。強制的に取り直すなら make update FORCE=1"; \
	     exit 0; \
	   fi; \
	 fi; \
	 if [ -f "$$SRV/bedrock_server_edu" ] && [ -n "$$REMOTE" ] && [ "$$REMOTE" = "$$LOCAL" ] && [ -z "$(FORCE)" ]; then \
	   echo ""; echo "サーバーは最新です"; exit 0; \
	 fi; \
	 if [ -n "$(CHECK)" ]; then \
	   echo ""; \
	   if [ -f "$$SRV/bedrock_server_edu" ]; then \
	     echo "更新があります（make update で取得できます）"; \
	   else \
	     echo "バイナリがありません（make update で取得してください）"; \
	   fi; \
	   exit 0; \
	 fi; \
	 RUNNING=$$(docker ps --filter "name=minecraft-edu-world" --format '{{.Names}}' 2>/dev/null | tr '\n' ' '); \
	 echo ""; \
	 if [ -n "$$RUNNING" ]; then \
	   echo "稼働中のワールド: $$RUNNING"; \
	   echo "  起動中のサーバーはコンテナ内にコピーされたバイナリで動いているため、"; \
	   echo "  差し替えても落ちません。反映は次の make restart からになります"; \
	 fi; \
	 echo "直前のバージョンは $$BAK/ に退避します（make rollback で戻せます）"; \
	 echo "※ ワールドデータは新バージョンで開くと不可逆にアップグレードされ、"; \
	 echo "   古いサーバーでは読めなくなります。先に make backup を推奨します"; \
	 if [ -z "$(YES)" ]; then \
	   if [ ! -t 0 ]; then \
	     echo ""; \
	     echo "エラー: 対話端末ではないため確認できません。make update YES=1 で実行してください"; \
	     exit 1; \
	   fi; \
	   printf '取得して差し替えますか? [y/N] '; read ANS; \
	   case "$$ANS" in y|Y|yes|YES) ;; *) echo "中止しました"; exit 0;; esac; \
	 fi; \
	 rm -rf "$$NEW"; mkdir -p "$$NEW"; \
	 echo "ダウンロード中..."; \
	 _get "$(SERVER_URL)" "$$NEW/server.zip"; \
	 unzip -q -o "$$NEW/server.zip" -d "$$NEW"; \
	 rm -f "$$NEW/server.zip"; \
	 if [ ! -f "$$NEW/bedrock_server_edu" ]; then \
	   echo "エラー: 展開結果に bedrock_server_edu がありません。$$NEW/ の中身を確認してください"; \
	   exit 1; \
	 fi; \
	 SZ=$$(wc -c < "$$NEW/bedrock_server_edu" | tr -d ' '); \
	 if [ "$$SZ" -lt $(SERVER_MIN_SIZE) ]; then \
	   echo "エラー: 取得したバイナリが小さすぎます（$$SZ バイト）"; \
	   echo "        配布元がエラーページを返した可能性があります。$$NEW/ は残してあるので中身を確認してください"; \
	   exit 1; \
	 fi; \
	 chmod +x "$$NEW/bedrock_server_edu"; \
	 rm -rf "$$BAK"; mkdir -p "$$BAK"; \
	 find "$$SRV" -maxdepth 1 -mindepth 1 -exec mv {} "$$BAK/" \; ; \
	 find "$$NEW" -maxdepth 1 -mindepth 1 -exec mv {} "$$SRV/" \; ; \
	 rmdir "$$NEW"; \
	 { echo "$${REMOTE:-(unknown)}"; \
	   echo "# fetched: $$(date '+%Y-%m-%d %H:%M:%S')"; \
	   echo "# source: $(SERVER_URL)"; \
	   echo "# size: $$SZ"; } > "$$VER"; \
	 echo ""; \
	 echo "更新しました（$$SZ バイト）"; \
	 echo "  → 反映するには make restart（起動していなければ make up）"; \
	 echo "  → 設定項目が増えていないかは make props で確認できます"

# server/ と server.bak/ の中身を入れ替えて直前のバージョンに戻す。
# もう一度叩けば元に戻る（捨てずに入れ替えるだけ）。
# server/ ディレクトリ自体は mv しない。バインドマウントは inode を見ているため、
# ディレクトリを差し替えると稼働中のコンテナが古い方を参照し続けてしまう。
rollback:
	@set -e; \
	 BASE=$$(sed -n 's/^VOLUMES_BASE_PATH=//p' .env 2>/dev/null | tr -d '\r' | tail -1); \
	 BASE=$${BASE:-./}; \
	 SRV="$${BASE}server"; BAK="$${BASE}server.bak"; SWP="$${BASE}server.swap"; \
	 if [ ! -f "$$BAK/bedrock_server_edu" ]; then \
	   echo "エラー: 退避されたバイナリがありません（$$BAK/bedrock_server_edu）"; \
	   echo "        退避は make update が作ります。まだ一度も更新していない場合は戻せません"; \
	   exit 1; \
	 fi; \
	 echo "入れ替えます:"; \
	 echo "  現在: $$(sed -n '1p' "$$SRV/.server_version" 2>/dev/null || echo '(不明)')$$(sed -n 's/^# fetched: /   取得日 /p' "$$SRV/.server_version" 2>/dev/null | tail -1)"; \
	 echo "  退避: $$(sed -n '1p' "$$BAK/.server_version" 2>/dev/null || echo '(不明)')$$(sed -n 's/^# fetched: /   取得日 /p' "$$BAK/.server_version" 2>/dev/null | tail -1)"; \
	 if [ -z "$(YES)" ]; then \
	   if [ ! -t 0 ]; then \
	     echo "エラー: 対話端末ではありません。make rollback YES=1 で実行してください"; \
	     exit 1; \
	   fi; \
	   printf '戻しますか? [y/N] '; read ANS; \
	   case "$$ANS" in y|Y|yes|YES) ;; *) echo "中止しました"; exit 0;; esac; \
	 fi; \
	 rm -rf "$$SWP"; mkdir -p "$$SWP"; \
	 find "$$SRV" -maxdepth 1 -mindepth 1 -exec mv {} "$$SWP/" \; ; \
	 find "$$BAK" -maxdepth 1 -mindepth 1 -exec mv {} "$$SRV/" \; ; \
	 find "$$SWP" -maxdepth 1 -mindepth 1 -exec mv {} "$$BAK/" \; ; \
	 rmdir "$$SWP"; \
	 echo ""; \
	 echo "戻しました（もう一度 make rollback を叩けば元に戻ります）"; \
	 echo "  → 反映するには make restart"; \
	 echo "  ※ ワールドデータは新しいバージョンで開いた時点でアップグレードされており、"; \
	 echo "     古いサーバーでは読めません。必要なら worlds/ もバックアップから戻してください"

# server/ にバイナリが無ければ取得する（up の前段で自動的に走る）。
# コンテナ側は取得しない設計なので、無いまま up すると起動時にエラーで止まる。
# 初回構築のときだけ動き、以降は何もしない（更新は make update を明示的に叩く）。
check-server:
	@BASE=$$(sed -n 's/^VOLUMES_BASE_PATH=//p' .env 2>/dev/null | tr -d '\r' | tail -1); \
	 BASE=$${BASE:-./}; \
	 if [ ! -f "$${BASE}server/bedrock_server_edu" ]; then \
	   echo "サーバーバイナリがありません。取得します（初回のみ）"; \
	   $(MAKE) --no-print-directory update YES=1; \
	 fi

# ================================================
# server.properties と property-definitions.json の差分
# ================================================
# サーバー側で設定項目が増えても起動は壊れない。entrypoint.sh が起動ごとに
# server/ の server.properties を /minecraft/ へ展開し直すので、新しい項目は
# 公式の既定値で入ってくる。ただし /minecraft/server.properties は永続化して
# いないため差分が手元に残らず、「項目が増えたこと」に気づく手がかりがない。
# このターゲットはその差分を可視化する。
props:
	@set -e; \
	 BASE=$$(sed -n 's/^VOLUMES_BASE_PATH=//p' .env 2>/dev/null | tr -d '\r' | tail -1); \
	 BASE=$${BASE:-./}; \
	 P="$${BASE}server/server.properties"; D=property-definitions.json; \
	 if [ ! -f "$$P" ]; then \
	   echo "エラー: $$P がありません。先に make update でバイナリを取得してください"; \
	   exit 1; \
	 fi; \
	 T=$$(mktemp -d); trap 'rm -rf "$$T"' EXIT INT TERM; \
	 sed -n 's/^[[:space:]]*"\([a-z0-9-]*\)"[[:space:]]*:.*/\1/p' "$$D" | LC_ALL=C sort -u > "$$T/defs"; \
	 sed -n 's/^\([a-z0-9-]*\)=.*/\1/p' "$$P" | LC_ALL=C sort -u > "$$T/props"; \
	 echo "server.properties: $$(wc -l < "$$T/props" | tr -d ' ') 項目   property-definitions.json: $$(wc -l < "$$T/defs" | tr -d ' ') 項目"; \
	 echo ""; \
	 UN=$$(LC_ALL=C comm -23 "$$T/props" "$$T/defs"); \
	 if [ -n "$$UN" ]; then \
	   echo "■ .env から制御できない項目（server.properties にあるが未定義）"; \
	   for k in $$UN; do \
	     printf '    %-54s %s\n' "$$k" "$$(sed -n 's/^'"$$k"'=/既定 /p' "$$P" | head -1)"; \
	   done; \
	   echo ""; \
	   echo "  使いたいものがあれば、この3つを揃えてください"; \
	   echo "   1. property-definitions.json に  \"<キー>\": { \"env\": \"<環境変数名>\" }  を追記"; \
	   echo '   2. docker-compose.world{N}.yml.example の environment に  <環境変数名>: $${..._WORLD_{N}:-$${..._COMMON:-既定}}  を追記'; \
	   echo "   3. make build（定義ファイルはイメージに COPY されるため再ビルドが必要）"; \
	 else \
	   echo "■ 未対応の項目はありません"; \
	 fi; \
	 MISS=$$(LC_ALL=C comm -13 "$$T/props" "$$T/defs"); \
	 if [ -n "$$MISS" ]; then \
	   echo ""; \
	   echo "■ 定義にあるが server.properties に書かれていない項目"; \
	   W=0; \
	   for k in $$MISS; do \
	     if grep -q "^#[[:space:]]*$$k=" "$$P"; then \
	       S="既定で無効（コメント行にあり。entrypoint が必要なときだけ追記します）"; \
	     else \
	       S="見当たりません（リネームか削除の疑い。設定しても無視されます）"; W=1; \
	     fi; \
	     printf '    %-54s %s\n' "$$k" "$$S"; \
	   done; \
	   if [ "$$W" = 1 ]; then \
	     echo ""; \
	     echo "  「見当たりません」の項目は、サーバー側で名前が変わったか廃止された可能性があります。"; \
	     echo "  BDS は未知のキーを黙って無視するため、.env で設定しても静かに効かなくなります。"; \
	     echo "  server/bedrock_server_how_to.html で正しい名前を確認し、property-definitions.json を直してください"; \
	   fi; \
	 fi
