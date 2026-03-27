# AI-LTC Init Questionnaire Template

Purpose:
- use this bounded intake when Qwen is initializing AI-LTC in a target repository
- keep the intake small and structured
- use the answers to populate `.ai/system/ai-ltc-config.json`

Question cap:
- ask at most 6 answers
- prefer 4 to 5 when possible

Suggested questions:
1. `Human-Facing Output Language`
- summary language for human-facing output
- working language remains English

2. `AI-LTC Source Mode`
- `local_path`
- `git_repo`
- `cloud_reference`

3. `AI-LTC Location`
- if `local_path`: local root path
- if `git_repo`: repo URL and ref
- if `cloud_reference`: canonical URL or mirror identifier

4. `Remote Fallback And Refresh Policy`
- remote repo URL or cloud reference
- whether Qwen may refresh the local checkout when needed

5. `Project State`
- `greenfield`
- `midstream`
- `chaotic`

6. `Default Operator Model, GPT Bootstrap Need, And Human Input Policy`
- usually `qwen-3.5-plus`
- whether GPT bootstrap is needed now
- input language policy for human requests

Writeback rule:
- after the questionnaire, write one resolver config file:
  - `.ai/system/ai-ltc-config.json`
- do not scatter raw source paths across multiple `.ai` docs
- lane docs may say `Resolver: .ai/system/ai-ltc-config.json`
- update `.ai/system/init-status.md` before and after the questionnaire so interrupted init can resume
