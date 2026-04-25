# Hermes 可攜式佈署 SOP

這份文件是給人看的中文版，對應同 repo 裡給 AI agent 用的 runbook。

## 目標

在一台全新的 Hermes 機器上，建立一個新的 profile，並安裝：

- `notebooklm-hermes-skill`
- `notebooklm-py`
- `lancedb-pro-hermes-plugin`
- `codex-dispatch-hermes-plugin`

## 這份 SOP 的定位

這不是把舊機 `m2` 整包複製過去。

這份 SOP 做的是：

- 用新的 profile 名稱也能安裝
- 把必要 repo 與能力裝起來
- 把 secrets 和資料遷移拆開處理
- 讓 AI agent 可以照著做，不用自己猜

## 重要說明

目前本機 `m2` 的記憶 provider 仍是 `openclaw_lancedb`。

這個 `openclaw_lancedb` 依目前本機狀態來看，**不是一個獨立公開 GitHub repo 依賴**，而是 OpenClaw 遷移到 Hermes 時留下來的本地 migration adapter。

它目前依賴的本地資料位置是：

- `~/.hermes/migration/openclaw-lancedb-pro-export/`

但這份 SOP 的**目標方案**是：

- `lancedb-pro-hermes-plugin`

所以新機建出來的 profile 會是「能力相近、結構可攜」，不是硬複製目前 `m2` 的每一項內部狀態。

換句話說，目前這份 bootstrap SOP 只把以下四個 GitHub 來源視為正式可攜依賴：

- `notebooklm-hermes-skill`
- `notebooklm-py`
- `lancedb-pro-hermes-plugin`
- `codex-dispatch-hermes-plugin`

而 `openclaw_lancedb` 只做來源註記，不列入新機標準安裝件。

如果之後要搬舊記憶，請另外看正式 migration 文件：

- [docs/new-machine-quickstart.zh-TW.md](/Users/sscomp/hermes-portable-bootstrap/docs/new-machine-quickstart.zh-TW.md)
- [docs/openclaw-memory-export.md](/Users/sscomp/hermes-portable-bootstrap/docs/openclaw-memory-export.md)
- [docs/hermes-to-hermes-memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/hermes-to-hermes-memory-migration.md)
- [docs/memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/memory-migration.md)

## 你需要先準備

1. 新機已安裝 Hermes
2. Hermes CLI 可用
3. 已決定新的 profile 名稱
4. 已決定 LanceDB 的資料路徑與 scope 名稱
5. 已決定是否要把舊機的 LanceDB 資料搬過去
6. 願意在安裝後手動完成 NotebookLM login

## 建議流程

1. 先複製 `templates/bootstrap.env.example` 成 `bootstrap.env`
2. 把 profile 名稱、repo URL、路徑都填好
3. 依序執行：

```bash
bash scripts/01-prepare-repos.sh bootstrap.env
bash scripts/02-create-profile.sh bootstrap.env
bash scripts/03-install-notebooklm.sh bootstrap.env
bash scripts/04-install-memory.sh bootstrap.env
bash scripts/05-install-codex-dispatch.sh bootstrap.env
bash scripts/06-smoke-test.sh bootstrap.env
```

如果舊 OpenClaw 機器還需要先把 JSON 匯出，先執行：

```bash
bash scripts/00-export-openclaw-memory.sh
```

如果你要再做 Hermes 端的舊記憶搬移規劃或匯入，再執行：

```bash
bash scripts/07-migrate-memory.sh bootstrap.env
```

## 哪些東西不會自動完成

以下項目故意不自動化：

- profile `.env` 真實憑證
- Telegram / LINE / Slack token
- Google / NotebookLM 登入
- 既有 LanceDB 記憶資料搬移

原因很簡單：這些不是「程式安裝」而是「環境祕密與資料遷移」，交給 AI agent 自行猜測反而危險。

記憶資料遷移的規格，已獨立整理在：

- [docs/memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/memory-migration.md)

目前這套流程的名詞建議這樣理解：

- `export`：從 OpenClaw 舊機台把記憶匯出成 JSON
- `import`：把已準備好的 JSON 寫入目標 memory store
- `migration`：在 Hermes 端做 scope mapping、review、dedupe、驗證後再匯入

目前 `scripts/07-migrate-memory.sh` 已支援三種 Hermes 端 migration 模式：

- `plan`：產生 migration report、review candidates 與 decisions template
- `apply`：保守匯入，只匯入 `keep` bucket，並跳過明顯重複資料
- `apply-reviewed`：在 `apply` 基礎上，再匯入 decisions file 中明確標為 `approve` 的 review records

另外，現在匯入時也會保留原始 `timestamp` 與來源 metadata，不會只剩簡化後的文字內容。

## 安裝完成後你應該看到

- `<PROFILE_HOME>/bin/nb`
- `<PROFILE_HOME>/skills/research/notebooklm`
- `<PROFILE_HOME>/plugins/hermes_lancedb`
- `<PROFILE_HOME>/plugins/codex-dispatch`
- `<PROFILE_HOME>/codex-dispatch/config.json`
- `<PROFILE_HOME>/codex-dispatch/codex-projects.json`

而且 `<PROFILE_HOME>/config.yaml` 內至少要有：

- `memory.provider: hermes_lancedb`
- `plugins.enabled` 內包含 `codex-dispatch`
- NotebookLM quick commands

## 最後驗證

重啟 gateway 後，建議至少測：

- `/nb-list`
- `/nb-login`
- `/codex-projects`
- `hermes --profile <profile> memory status`

## 建議的下一步

如果這套流程之後要正式交給別的 Claude / Codex 使用，建議再補：

- 一份 secrets 填寫規格
- 一份 LanceDB 遷移規格
- 一份 gateway 平台綁定規格
