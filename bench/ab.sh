#!/usr/bin/env bash
# bench/ab.sh —— 同一把尺子量 OML：4 组单变量对照。
#
# 变量只有两个：OML 插件是否加载、外部技能目录是否扫描。
# 其余全部固定：同一模型、同一句提示词、空项目、同一份宿主配置。
#
# 用法：bash bench/ab.sh [输出目录]
# 依赖：opencode 在 PATH；~/.config/opencode/plugin/omo.ts 存在（omo install --apply 生成）
set -euo pipefail

MODEL="${OML_AB_MODEL:-opencode/deepseek-v4.1-flash-free}"
PROMPT="${OML_AB_PROMPT:-只回复两个字：收到}"
PLUGIN="${HOME}/.config/opencode/plugin/omo.ts"
PROJ="${1:-/tmp/oml-ab/proj}"
OUT="${PROJ}/../ab-result.tsv"

mkdir -p "$PROJ"
cd "$PROJ"
: > "$OUT"

one() {
  local id="$1" omo="$2" skills="$3"
  local moved=0
  if [ "$omo" = "off" ] && [ -f "$PLUGIN" ]; then
    mv "$PLUGIN" "$PLUGIN.off"
    moved=1
  fi
  local raw tokens sid
  raw=$(OPENCODE_DISABLE_EXTERNAL_SKILLS=$([ "$skills" = "off" ] && echo 1 || echo 0) \
        timeout 300 opencode run --format json -m "$MODEL" "$PROMPT" 2>/dev/null || true)
  if [ "$moved" = "1" ]; then mv "$PLUGIN.off" "$PLUGIN"; fi

  tokens=$(printf '%s' "$raw" | grep -o '"type":"step-finish".*' | grep -o '"input":[0-9]*' | head -1 | cut -d: -f2)
  sid=$(printf '%s' "$raw" | head -1 | grep -o '"sessionID":"[^"]*"' | head -1 | cut -d'"' -f4)
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$omo" "$skills" "${tokens:-NA}" "${sid:-NA}" | tee -a "$OUT"
}

echo -e "组\tOML\t外部技能\ttokens.input\tsession"
one A off on
one B on  on
one C on  off
one D off off

echo
echo "原始结果：$OUT"
echo "把 token 数填进 docs/bench/ab-input.json，再跑 bun run bench:parity 更新对照表。"
