# 新機安裝順序

這份是給人看的超精簡版。

## 目的

在新 Hermes 機器上快速建出一個可用 profile，包含：

- `notebooklm-hermes-skill`
- `notebooklm-py`
- `lancedb-pro-hermes-plugin`
- `codex-dispatch-hermes-plugin`

## 最短順序

1. 準備 Hermes 與新的 profile 名稱
2. `git clone` [sscomp/hermes-portable-bootstrap](https://github.com/sscomp/hermes-portable-bootstrap)
3. 複製 `templates/bootstrap.env.example` 成 `bootstrap.env`
4. 修改 `bootstrap.env`
5. 依序執行：

```bash
bash scripts/01-prepare-repos.sh bootstrap.env
bash scripts/02-create-profile.sh bootstrap.env
bash scripts/03-install-notebooklm.sh bootstrap.env
bash scripts/04-install-memory.sh bootstrap.env
bash scripts/05-install-codex-dispatch.sh bootstrap.env
bash scripts/06-smoke-test.sh bootstrap.env
```

6. 補好 `<PROFILE_HOME>/.env`
7. 重啟 gateway
8. 驗證：

```bash
/nb-list
/nb-login
/codex-projects
hermes --profile <profile-name> memory status
```

## 如果還要搬記憶

分兩種來源：

- 舊 OpenClaw 機器：
  先跑 [scripts/00-export-openclaw-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/00-export-openclaw-memory.sh)
- 舊 Hermes 機器：
  先跑 [scripts/08-export-hermes-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/08-export-hermes-memory.sh)

之後在新機再跑：

```bash
bash scripts/07-migrate-memory.sh bootstrap.env
```
