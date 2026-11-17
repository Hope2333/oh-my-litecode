// src/index.tsx
import { createTextNode as _$createTextNode } from "@opentui/solid";
import { insertNode as _$insertNode } from "@opentui/solid";
import { createComponent as _$createComponent } from "@opentui/solid";
import { effect as _$effect } from "@opentui/solid";
import { insert as _$insert } from "@opentui/solid";
import { memo as _$memo } from "@opentui/solid";
import { use as _$use } from "@opentui/solid";
import { setProp as _$setProp } from "@opentui/solid";
import { createElement as _$createElement } from "@opentui/solid";
import { createMemo, createSignal, createEffect, onMount, onCleanup, untrack, Show, For } from "solid-js";

// src/_version.ts
var PLUGIN_VERSION = "1.5.2";

// src/clipboard.ts
import { spawn } from "node:child_process";
import { platform, release } from "node:os";
function runWithInput(command, args, input) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ["pipe", "ignore", "ignore"],
      windowsHide: true
    });
    child.once("error", reject);
    child.once("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} exited with code ${code}`));
    });
    child.stdin?.end(input);
  });
}
function writeOsc52(text) {
  if (!process.stdout.isTTY) return false;
  const payload = Buffer.from(text, "utf8").toString("base64");
  const sequence = `\x1B]52;c;${payload}\x07`;
  const wrapped = process.env.TMUX || process.env.STY ? `\x1BPtmux;\x1B${sequence}\x1B\\` : sequence;
  process.stdout.write(wrapped);
  return true;
}
async function tryCommand(method, command, args, text) {
  try {
    await runWithInput(command, args, text);
    return { copied: true, method };
  } catch {
    return void 0;
  }
}
async function copyText(text) {
  if (!text) return { copied: false, method: "none", error: "empty_text" };
  const os = platform();
  const isWsl = release().toLowerCase().includes("microsoft");
  const attempts = [];
  if (os === "darwin") {
    attempts.push(() => tryCommand("pbcopy", "pbcopy", [], text));
    attempts.push(
      () => tryCommand(
        "osascript",
        "osascript",
        ["-e", 'set the clipboard to (read (POSIX file "/dev/stdin") as text)'],
        text
      )
    );
  }
  if (os === "linux" && isWsl) {
    attempts.push(
      () => tryCommand(
        "powershell",
        "powershell.exe",
        [
          "-NonInteractive",
          "-NoProfile",
          "-Command",
          "[Console]::InputEncoding=[Text.Encoding]::UTF8; Set-Clipboard ([Console]::In.ReadToEnd())"
        ],
        text
      )
    );
  } else if (os === "linux") {
    if (process.env.WAYLAND_DISPLAY) {
      attempts.push(() => tryCommand("wl-copy", "wl-copy", [], text));
    }
    attempts.push(() => tryCommand("xclip", "xclip", ["-selection", "clipboard"], text));
    attempts.push(() => tryCommand("xsel", "xsel", ["--clipboard", "--input"], text));
  }
  if (os === "win32") {
    attempts.push(
      () => tryCommand(
        "powershell",
        "powershell.exe",
        [
          "-NonInteractive",
          "-NoProfile",
          "-Command",
          "[Console]::InputEncoding=[Text.Encoding]::UTF8; Set-Clipboard ([Console]::In.ReadToEnd())"
        ],
        text
      )
    );
  }
  for (const attempt of attempts) {
    const result = await attempt();
    if (result) return result;
  }
  try {
    if (writeOsc52(text)) return { copied: true, method: "osc52" };
  } catch {
  }
  return { copied: false, method: "none", error: "clipboard_unavailable" };
}

// src/i18n.ts
var ZH_T = {
  "panel.title": "\u5B50\u4EE3\u7406",
  "status.none": "\u6682\u65E0\u5B50\u4EE3\u7406",
  "agent.label": "\u4EE3\u7406",
  "status.label": "\u72B6\u6001",
  "time.label": "\u8017\u65F6",
  "tokens.label": "\u4E0A\u4E0B\u6587",
  "error.label": "\u9519\u8BEF",
  "model.label": "\u6A21\u578B",
  "todo.label": "\u8FDB\u5EA6",
  "session.label": "\u4F1A\u8BDD ID",
  "session.toast.copy": "\u53EF\u624B\u52A8\u590D\u5236\u4E0A\u65B9 ID",
  "session.toast.copied": "\u4F1A\u8BDD ID \u5DF2\u590D\u5236",
  "session.toast.copy_failed": "\u65E0\u6CD5\u8BBF\u95EE\u7CFB\u7EDF\u526A\u8D34\u677F\uFF0C\u8BF7\u624B\u52A8\u590D\u5236\u4E0A\u65B9 ID",
  "open.label": "\u8FDB\u5165\u4F1A\u8BDD",
  "cost.label": "\u8D39\u7528",
  "scroll.more": "\u66F4\u591A",
  "scroll.top": "\u56DE\u9876",
  "scroll.bottom": "\u56DE\u5E95",
  "dismiss.label": "\u6807\u8BB0\u5B8C\u6210",
  "cancel.label": "\u53D6\u6D88",
  "status.running": "\u8FD0\u884C\u4E2D",
  "status.done": "\u5DF2\u5B8C\u6210",
  "status.cancelled": "\u5DF2\u53D6\u6D88",
  "status.error": "\u9519\u8BEF",
  "order.desc": "\u964D\u5E8F\uFF08\u6700\u65B0\u5728\u524D\uFF09",
  "order.asc": "\u5347\u5E8F\uFF08\u6700\u65E9\u5728\u524D\uFF09",
  "scroll.wheel": "\u6EDA\u8F6E\u7FFB\u9875",
  "scroll.click": "\u70B9\u51FB\u7FFB\u9875",
  "ttl.label": "\u6E05\u7406\u5468\u671F",
  "ttl.3d": "3 \u5929",
  "ttl.7d": "7 \u5929",
  "ttl.14d": "14 \u5929",
  "ttl.30d": "30 \u5929",
  "ttl.unlimited": "\u65E0\u671F\u9650",
  "ttl.toast": "\u6E05\u7406\u5468\u671F\u5DF2\u8BBE\u4E3A {n} \u5929",
  "ttl.toast_unlimited": "\u6E05\u7406\u5468\u671F\u5DF2\u8BBE\u4E3A\u65E0\u671F\u9650",
  "clear.title": "\u786E\u8BA4\u6E05\u9664",
  "clear.prompt": "\u786E\u5B9A\u6E05\u9664\u5F53\u524D\u4F1A\u8BDD\u6240\u6709\u5B50\u4EE3\u7406\u8BB0\u5F55\uFF1F\u6B64\u64CD\u4F5C\u4E0D\u53EF\u64A4\u9500\u3002",
  "clear.prompt_running": "\u5F53\u524D\u6709 {n} \u4E2A\u8FD0\u884C\u4E2D\u7684\u5B50\u4EE3\u7406\uFF0C\u6E05\u9664\u540E\u5C06\u4E0D\u53EF\u6062\u590D\u3002\u786E\u5B9A\u7EE7\u7EED\uFF1F",
  "clear.done": "\u5DF2\u6E05\u9664 {n} \u6761\u5B50\u4EE3\u7406\u8BB0\u5F55",
  "clear.empty": "\u5F53\u524D\u4F1A\u8BDD\u65E0\u5B50\u4EE3\u7406\u8BB0\u5F55",
  "cancel.no_session": "\u5B50\u4F1A\u8BDD ID \u4E0D\u53EF\u7528",
  "cancel.not_child": "\u76EE\u6807\u4E0D\u662F\u5B50\u4F1A\u8BDD",
  "cancel.read_error": "\u65E0\u6CD5\u8BFB\u53D6\u4F1A\u8BDD\u4FE1\u606F",
  "cancel.outside_tree": "\u76EE\u6807\u4E0D\u5728\u5F53\u524D\u76D1\u63A7\u4F1A\u8BDD\u6811\u4E2D",
  "cancel.already_ended": "\u4F1A\u8BDD\u5DF2\u7ED3\u675F\uFF0C\u65E0\u9700\u53D6\u6D88",
  "cancel.status_error": "\u65E0\u6CD5\u67E5\u8BE2\u4F1A\u8BDD\u72B6\u6001",
  "cancel.sent": "\u5DF2\u53D1\u9001\u53D6\u6D88\u6307\u4EE4",
  "cancel.failed": "\u53D6\u6D88\u5931\u8D25"
};
var EN_T = {
  "panel.title": "SubAgent",
  "status.none": "No sub-agents yet",
  "agent.label": "agent",
  "status.label": "status",
  "time.label": "time",
  "tokens.label": "tokens",
  "error.label": "error",
  "model.label": "model",
  "todo.label": "todo",
  "session.label": "session ID",
  "session.toast.copy": "Copy the ID above manually",
  "session.toast.copied": "Session ID copied",
  "session.toast.copy_failed": "Cannot access the system clipboard; copy the ID above manually",
  "open.label": "Open session",
  "cost.label": "cost",
  "scroll.more": "more",
  "scroll.top": "Top",
  "scroll.bottom": "Bottom",
  "dismiss.label": "dismiss",
  "cancel.label": "Cancel",
  "status.running": "running",
  "status.done": "done",
  "status.cancelled": "cancelled",
  "status.error": "error",
  "order.desc": "Desc (newest first)",
  "order.asc": "Asc (oldest first)",
  "scroll.wheel": "Wheel Scroll",
  "scroll.click": "Click Scroll",
  "ttl.label": "TTL (Time to Live)",
  "ttl.3d": "3 days",
  "ttl.7d": "7 days",
  "ttl.14d": "14 days",
  "ttl.30d": "30 days",
  "ttl.unlimited": "Never",
  "ttl.toast": "TTL set to {n} days",
  "ttl.toast_unlimited": "TTL set to Never",
  "clear.title": "Confirm",
  "clear.prompt": "Clear all sub-agent records for this session? This cannot be undone.",
  "clear.prompt_running": "{n} sub-agent(s) are still running. Clearing will discard them permanently. Continue?",
  "clear.done": "Cleared {n} sub-agent record(s)",
  "clear.empty": "No sub-agent records in this session",
  "cancel.no_session": "Child session ID is unavailable",
  "cancel.not_child": "Target is not a child session",
  "cancel.read_error": "Cannot read session info",
  "cancel.outside_tree": "Target is outside the monitored session tree",
  "cancel.already_ended": "Session already ended, no need to cancel",
  "cancel.status_error": "Cannot query session status",
  "cancel.sent": "Cancel instruction sent",
  "cancel.failed": "Cancellation failed"
};
var JA_T = {
  "panel.title": "\u30B5\u30D6\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8",
  "status.none": "\u30B5\u30D6\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8\u306A\u3057",
  "agent.label": "\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8",
  "status.label": "\u72B6\u614B",
  "time.label": "\u6642\u9593",
  "tokens.label": "\u30B3\u30F3\u30C6\u30AD\u30B9\u30C8",
  "error.label": "\u30A8\u30E9\u30FC",
  "model.label": "\u30E2\u30C7\u30EB",
  "todo.label": "\u9032\u6357",
  "session.label": "\u30BB\u30C3\u30B7\u30E7\u30F3 ID",
  "session.toast.copy": "\u4E0A\u306E ID \u3092\u624B\u52D5\u3067\u30B3\u30D4\u30FC\u3057\u3066\u304F\u3060\u3055\u3044",
  "session.toast.copied": "\u30BB\u30C3\u30B7\u30E7\u30F3 ID \u3092\u30B3\u30D4\u30FC\u3057\u307E\u3057\u305F",
  "session.toast.copy_failed": "\u30B7\u30B9\u30C6\u30E0\u306E\u30AF\u30EA\u30C3\u30D7\u30DC\u30FC\u30C9\u306B\u30A2\u30AF\u30BB\u30B9\u3067\u304D\u306A\u3044\u305F\u3081\u3001\u4E0A\u306E ID \u3092\u624B\u52D5\u3067\u30B3\u30D4\u30FC\u3057\u3066\u304F\u3060\u3055\u3044",
  "open.label": "\u30BB\u30C3\u30B7\u30E7\u30F3\u3092\u958B\u304F",
  "cost.label": "\u8CBB\u7528",
  "scroll.more": "\u3082\u3063\u3068",
  "scroll.top": "\u5148\u982D\u3078",
  "scroll.bottom": "\u672B\u5C3E\u3078",
  "dismiss.label": "\u5B8C\u4E86\u306B\u3059\u308B",
  "cancel.label": "\u30AD\u30E3\u30F3\u30BB\u30EB",
  "status.running": "\u5B9F\u884C\u4E2D",
  "status.done": "\u5B8C\u4E86",
  "status.cancelled": "\u30AD\u30E3\u30F3\u30BB\u30EB\u6E08\u307F",
  "status.error": "\u30A8\u30E9\u30FC",
  "order.desc": "\u964D\u9806\uFF08\u65B0\u3057\u3044\u9806\uFF09",
  "order.asc": "\u6607\u9806\uFF08\u53E4\u3044\u9806\uFF09",
  "scroll.wheel": "\u30DB\u30A4\u30FC\u30EB\u30B9\u30AF\u30ED\u30FC\u30EB",
  "scroll.click": "\u30AF\u30EA\u30C3\u30AF\u30B9\u30AF\u30ED\u30FC\u30EB",
  "ttl.label": "\u4FDD\u6301\u671F\u9593",
  "ttl.3d": "3 \u65E5",
  "ttl.7d": "7 \u65E5",
  "ttl.14d": "14 \u65E5",
  "ttl.30d": "30 \u65E5",
  "ttl.unlimited": "\u7121\u671F\u9650",
  "ttl.toast": "\u4FDD\u6301\u671F\u9593\u3092 {n} \u65E5\u306B\u8A2D\u5B9A\u3057\u307E\u3057\u305F",
  "ttl.toast_unlimited": "\u4FDD\u6301\u671F\u9593\u3092\u7121\u671F\u9650\u306B\u8A2D\u5B9A\u3057\u307E\u3057\u305F",
  "clear.title": "\u524A\u9664\u306E\u78BA\u8A8D",
  "clear.prompt": "\u3053\u306E\u30BB\u30C3\u30B7\u30E7\u30F3\u306E\u5168\u30B5\u30D6\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8\u8A18\u9332\u3092\u524A\u9664\u3057\u307E\u3059\u304B\uFF1F\u3053\u306E\u64CD\u4F5C\u306F\u5143\u306B\u623B\u305B\u307E\u305B\u3093\u3002",
  "clear.prompt_running": "\u5B9F\u884C\u4E2D\u306E\u30B5\u30D6\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8\u304C {n} \u500B\u3042\u308A\u307E\u3059\u3002\u524A\u9664\u3059\u308B\u3068\u5FA9\u5143\u3067\u304D\u307E\u305B\u3093\u3002\u7D9A\u884C\u3057\u307E\u3059\u304B\uFF1F",
  "clear.done": "{n} \u4EF6\u306E\u30B5\u30D6\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8\u8A18\u9332\u3092\u524A\u9664\u3057\u307E\u3057\u305F",
  "clear.empty": "\u3053\u306E\u30BB\u30C3\u30B7\u30E7\u30F3\u306B\u30B5\u30D6\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8\u8A18\u9332\u306F\u3042\u308A\u307E\u305B\u3093",
  "cancel.no_session": "\u5B50\u30BB\u30C3\u30B7\u30E7\u30F3 ID \u304C\u5229\u7528\u3067\u304D\u307E\u305B\u3093",
  "cancel.not_child": "\u5BFE\u8C61\u306F\u5B50\u30BB\u30C3\u30B7\u30E7\u30F3\u3067\u306F\u3042\u308A\u307E\u305B\u3093",
  "cancel.read_error": "\u30BB\u30C3\u30B7\u30E7\u30F3\u60C5\u5831\u3092\u8AAD\u307F\u53D6\u308C\u307E\u305B\u3093",
  "cancel.outside_tree": "\u5BFE\u8C61\u306F\u76E3\u8996\u5BFE\u8C61\u306E\u30BB\u30C3\u30B7\u30E7\u30F3\u30C4\u30EA\u30FC\u5916\u3067\u3059",
  "cancel.already_ended": "\u30BB\u30C3\u30B7\u30E7\u30F3\u306F\u65E2\u306B\u7D42\u4E86\u3057\u3066\u3044\u307E\u3059",
  "cancel.status_error": "\u30BB\u30C3\u30B7\u30E7\u30F3\u72B6\u614B\u3092\u7167\u4F1A\u3067\u304D\u307E\u305B\u3093",
  "cancel.sent": "\u30AD\u30E3\u30F3\u30BB\u30EB\u6307\u793A\u3092\u9001\u4FE1\u3057\u307E\u3057\u305F",
  "cancel.failed": "\u30AD\u30E3\u30F3\u30BB\u30EB\u306B\u5931\u6557\u3057\u307E\u3057\u305F"
};
var KO_T = {
  "panel.title": "\uC11C\uBE0C \uC5D0\uC774\uC804\uD2B8",
  "status.none": "\uC11C\uBE0C \uC5D0\uC774\uC804\uD2B8 \uC5C6\uC74C",
  "agent.label": "\uC5D0\uC774\uC804\uD2B8",
  "status.label": "\uC0C1\uD0DC",
  "time.label": "\uC2DC\uAC04",
  "tokens.label": "\uCEE8\uD14D\uC2A4\uD2B8",
  "error.label": "\uC624\uB958",
  "model.label": "\uBAA8\uB378",
  "todo.label": "\uC9C4\uD589\uB3C4",
  "session.label": "\uC138\uC158 ID",
  "session.toast.copy": "\uC704 ID\uB97C \uC218\uB3D9\uC73C\uB85C \uBCF5\uC0AC\uD558\uC138\uC694",
  "session.toast.copied": "\uC138\uC158 ID\uAC00 \uBCF5\uC0AC\uB418\uC5C8\uC2B5\uB2C8\uB2E4",
  "session.toast.copy_failed": "\uC2DC\uC2A4\uD15C \uD074\uB9BD\uBCF4\uB4DC\uC5D0 \uC811\uADFC\uD560 \uC218 \uC5C6\uC5B4 \uC704 ID\uB97C \uC218\uB3D9\uC73C\uB85C \uBCF5\uC0AC\uD558\uC138\uC694",
  "open.label": "\uC138\uC158 \uC5F4\uAE30",
  "cost.label": "\uBE44\uC6A9",
  "scroll.more": "\uB354 \uBCF4\uAE30",
  "scroll.top": "\uB9E8 \uC704\uB85C",
  "scroll.bottom": "\uB9E8 \uC544\uB798\uB85C",
  "dismiss.label": "\uC644\uB8CC \uD45C\uC2DC",
  "cancel.label": "\uCDE8\uC18C",
  "status.running": "\uC2E4\uD589 \uC911",
  "status.done": "\uC644\uB8CC",
  "status.cancelled": "\uCDE8\uC18C\uB428",
  "status.error": "\uC624\uB958",
  "order.desc": "\uB0B4\uB9BC\uCC28\uC21C(\uCD5C\uC2E0\uC21C)",
  "order.asc": "\uC624\uB984\uCC28\uC21C(\uC624\uB798\uB41C\uC21C)",
  "scroll.wheel": "\uD720 \uC2A4\uD06C\uB864",
  "scroll.click": "\uD074\uB9AD \uC2A4\uD06C\uB864",
  "ttl.label": "\uBCF4\uC874 \uAE30\uAC04",
  "ttl.3d": "3\uC77C",
  "ttl.7d": "7\uC77C",
  "ttl.14d": "14\uC77C",
  "ttl.30d": "30\uC77C",
  "ttl.unlimited": "\uBB34\uAE30\uD55C",
  "ttl.toast": "\uBCF4\uC874 \uAE30\uAC04\uC744 {n}\uC77C\uB85C \uC124\uC815\uD588\uC2B5\uB2C8\uB2E4",
  "ttl.toast_unlimited": "\uBCF4\uC874 \uAE30\uAC04\uC744 \uBB34\uAE30\uD55C\uC73C\uB85C \uC124\uC815\uD588\uC2B5\uB2C8\uB2E4",
  "clear.title": "\uC0AD\uC81C \uD655\uC778",
  "clear.prompt": "\uC774 \uC138\uC158\uC758 \uBAA8\uB4E0 \uC11C\uBE0C \uC5D0\uC774\uC804\uD2B8 \uAE30\uB85D\uC744 \uC0AD\uC81C\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C? \uC774 \uC791\uC5C5\uC740 \uB418\uB3CC\uB9B4 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.",
  "clear.prompt_running": "\uC2E4\uD589 \uC911\uC778 \uC11C\uBE0C \uC5D0\uC774\uC804\uD2B8\uAC00 {n}\uAC1C \uC788\uC2B5\uB2C8\uB2E4. \uC0AD\uC81C\uD558\uBA74 \uBCF5\uAD6C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4. \uACC4\uC18D\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?",
  "clear.done": "\uC11C\uBE0C \uC5D0\uC774\uC804\uD2B8 \uAE30\uB85D {n}\uAC1C\uB97C \uC0AD\uC81C\uD588\uC2B5\uB2C8\uB2E4",
  "clear.empty": "\uC774 \uC138\uC158\uC5D0 \uC11C\uBE0C \uC5D0\uC774\uC804\uD2B8 \uAE30\uB85D\uC774 \uC5C6\uC2B5\uB2C8\uB2E4",
  "cancel.no_session": "\uD558\uC704 \uC138\uC158 ID\uB97C \uC0AC\uC6A9\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4",
  "cancel.not_child": "\uB300\uC0C1\uC774 \uD558\uC704 \uC138\uC158\uC774 \uC544\uB2D9\uB2C8\uB2E4",
  "cancel.read_error": "\uC138\uC158 \uC815\uBCF4\uB97C \uC77D\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4",
  "cancel.outside_tree": "\uB300\uC0C1\uC774 \uBAA8\uB2C8\uD130\uB9C1 \uC138\uC158 \uD2B8\uB9AC \uBC16\uC5D0 \uC788\uC2B5\uB2C8\uB2E4",
  "cancel.already_ended": "\uC138\uC158\uC774 \uC774\uBBF8 \uC885\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4",
  "cancel.status_error": "\uC138\uC158 \uC0C1\uD0DC\uB97C \uC870\uD68C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4",
  "cancel.sent": "\uCDE8\uC18C \uC9C0\uC2DC\uB97C \uBCF4\uB0C8\uC2B5\uB2C8\uB2E4",
  "cancel.failed": "\uCDE8\uC18C\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4"
};
var LANGS = { zh: ZH_T, en: EN_T, ja: JA_T, ko: KO_T };
var LANG_META = [
  { code: "zh", label: "\u4E2D\u6587" },
  { code: "en", label: "English" },
  { code: "ja", label: "\u65E5\u672C\u8A9E" },
  { code: "ko", label: "\uD55C\uAD6D\uC5B4" }
];
function applyParams(tpl, params) {
  if (!params) return tpl;
  return tpl.replace(
    /\{(\w+)\}/g,
    (m, k) => k in params ? String(params[k]) : m
  );
}
function createT(getCode) {
  return (key, params) => applyParams(LANGS[getCode()][key] ?? key, params);
}
function detectLang() {
  try {
    const loc = Intl.DateTimeFormat().resolvedOptions().locale.toLowerCase();
    if (loc.startsWith("zh")) return "zh";
    if (loc.startsWith("ja")) return "ja";
    if (loc.startsWith("ko")) return "ko";
    return "en";
  } catch {
    return "en";
  }
}

// src/index.tsx
var SUBAGENT_TOOLS = /* @__PURE__ */ new Set(["task", "delegate", "call_omo_agent"]);
function charColumns(c) {
  const code = c.codePointAt(0) ?? 0;
  if (code < 32) return 0;
  if (code < 127) return 1;
  if (code < 160) return 0;
  if (code >= 4352 && code <= 4447 || code >= 11904 && code <= 42191 || code >= 44032 && code <= 55203 || code >= 63744 && code <= 64255 || code >= 65040 && code <= 65135 || code >= 65281 && code <= 65376 || code >= 65504 && code <= 65510 || code >= 127744 && code <= 128591 || code >= 131072 && code <= 262141) return 2;
  return 1;
}
function visualWidth(s) {
  let w = 0;
  for (const c of s) w += charColumns(c);
  return w;
}
function truncate(text, maxCols) {
  if (visualWidth(text) <= maxCols) return text;
  let cols = 0;
  let i = 0;
  for (const c of text) {
    const w = charColumns(c);
    if (cols + w > maxCols - 1) break;
    cols += w;
    i += c.length;
  }
  return text.slice(0, i) + "\u2026";
}
function fmtDurationShort(ms, running) {
  if (running && ms < 2e3) return "";
  if (ms < 1e3) return (ms / 1e3).toFixed(2) + "s";
  if (ms < 6e4) return (ms / 1e3).toFixed(2) + "s";
  const m = Math.floor(ms / 6e4);
  const s = Math.round(ms % 6e4 / 1e3);
  return `${m}m${s}s`;
}
function fmtTokens(n) {
  if (n < 1e3) return `${n}`;
  if (n < 1e6) return `${(n / 1e3).toFixed(1)}k`;
  return `${(n / 1e6).toFixed(1)}M`;
}
function rgb(raw) {
  if (typeof raw === "string" && raw.startsWith("#")) {
    const h = raw.slice(1);
    return {
      r: parseInt(h.slice(0, 2), 16),
      g: parseInt(h.slice(2, 4), 16),
      b: parseInt(h.slice(4, 6), 16)
    };
  }
  if (raw && typeof raw === "object") {
    const o = raw;
    if (typeof o.r === "number" && typeof o.g === "number" && typeof o.b === "number") {
      const scale = o.r > 1 || o.g > 1 || o.b > 1 ? 1 : 255;
      return {
        r: Math.round(o.r * scale),
        g: Math.round(o.g * scale),
        b: Math.round(o.b * scale)
      };
    }
  }
  return null;
}
function saturation(r, g, b) {
  const max = Math.max(r, g, b) / 255;
  const min = Math.min(r, g, b) / 255;
  const delta = max - min;
  if (delta === 0) return 0;
  const L = (max + min) / 2;
  return L <= 0.5 ? delta / (max + min) : delta / (2 - max - min);
}
function desaturateTo(raw, maxSat, fallback) {
  const c = rgb(raw);
  if (!c) return fallback;
  const sat = saturation(c.r, c.g, c.b);
  if (sat <= maxSat) {
    return "#" + [c.r, c.g, c.b].map((v) => v.toString(16).padStart(2, "0")).join("");
  }
  const luma = c.r * 0.299 + c.g * 0.587 + c.b * 0.114;
  let lo = 0, hi = 1;
  for (let i = 0; i < 12; i++) {
    const mid = (lo + hi) / 2;
    const nr2 = Math.round(c.r + (luma - c.r) * mid);
    const ng2 = Math.round(c.g + (luma - c.g) * mid);
    const nb2 = Math.round(c.b + (luma - c.b) * mid);
    if (saturation(nr2, ng2, nb2) > maxSat) lo = mid;
    else hi = mid;
  }
  const nr = Math.round(c.r + (luma - c.r) * hi);
  const ng = Math.round(c.g + (luma - c.g) * hi);
  const nb = Math.round(c.b + (luma - c.b) * hi);
  return "#" + [nr, ng, nb].map((v) => Math.max(0, Math.min(255, v)).toString(16).padStart(2, "0")).join("");
}
function dimColor(hex, factor = 0.5) {
  const c = rgb(hex);
  if (!c) return hex;
  const r = Math.round(c.r * factor);
  const g = Math.round(c.g * factor);
  const b = Math.round(c.b * factor);
  return "#" + [r, g, b].map((v) => Math.max(0, Math.min(255, v)).toString(16).padStart(2, "0")).join("");
}
var FALLBACK = {
  primary: "#8B9DAF",
  text: "#C5C5BB",
  muted: "#7A7A72",
  success: "#9CAF8B",
  warning: "#C5B88D",
  error: "#B08A8A",
  border: "#6B6B63"
};
var MAX_SAT = 0.28;
var LEFT_PAD = 4;
var INDENT = 2;
function safeErrorMsg(err) {
  if (!err) return "";
  if (typeof err === "string") return err;
  if (typeof err === "object") return String(err.message || err.code || "");
  return "";
}
var globalEntryCache = /* @__PURE__ */ new Map();
var [clearTick, setClearTick] = createSignal(0);
function SubAgentPanel(props) {
  const t = createT(() => props.lang());
  const SESSION_DATA_KEY = `${KV_PREFIX}.session_data`;
  const ttlDaysRaw = parseInt(String(props.api.kv.get(`${KV_PREFIX}.ttl_days`, "3")), 10);
  const ttlDays = Number.isNaN(ttlDaysRaw) ? 3 : ttlDaysRaw;
  const TTL_MS = ttlDays * 24 * 60 * 60 * 1e3;
  const loadSessionData = () => {
    try {
      const raw = props.api.kv.get(SESSION_DATA_KEY, "{}");
      return JSON.parse(String(raw));
    } catch {
      return {};
    }
  };
  const saveSessionData = (data) => {
    try {
      props.api.kv.set(SESSION_DATA_KEY, JSON.stringify(data));
    } catch {
    }
  };
  const resolveParent = (sid) => {
    try {
      const session = props.api.state.session.get(sid);
      const parentID = session?.parentID;
      if (parentID) return {
        parentSid: parentID,
        isChild: true
      };
    } catch {
    }
    return {
      parentSid: sid,
      isChild: false
    };
  };
  const loadEntries = (sid) => {
    const m = /* @__PURE__ */ new Map();
    try {
      const {
        parentSid,
        isChild
      } = resolveParent(sid);
      const rec = loadSessionData()[parentSid];
      if (rec) {
        const source = isChild ? rec.children?.[sid]?.entries : rec.entries;
        if (source) {
          for (const e of source) m.set(e.id, e);
        }
      }
    } catch {
    }
    return m;
  };
  let persistTimer;
  const persistEntries = (sid, entries2) => {
    clearTimeout(persistTimer);
    persistTimer = setTimeout(() => {
      try {
        const data = loadSessionData();
        const {
          parentSid,
          isChild
        } = resolveParent(sid);
        if (isChild) {
          if (!data[parentSid]) data[parentSid] = {
            ts: Date.now(),
            entries: [],
            scroll: 0,
            expanded: "",
            children: {}
          };
          if (!data[parentSid].children) data[parentSid].children = {};
          if (!data[parentSid].children[sid]) data[parentSid].children[sid] = {
            scroll: 0,
            expanded: "",
            entries: []
          };
          data[parentSid].children[sid] = {
            ...data[parentSid].children[sid],
            entries: [...entries2.values()]
          };
        } else {
          data[sid] = {
            ...data[sid],
            ts: Date.now(),
            entries: [...entries2.values()],
            children: data[sid]?.children ?? {}
          };
        }
        saveSessionData(data);
      } catch {
      }
    }, 200);
  };
  const persistScroll = (sid, scroll) => {
    try {
      const data = loadSessionData();
      const {
        parentSid,
        isChild
      } = resolveParent(sid);
      if (isChild) {
        if (!data[parentSid]) data[parentSid] = {
          ts: Date.now(),
          entries: [],
          scroll: 0,
          expanded: "",
          children: {}
        };
        if (!data[parentSid].children) data[parentSid].children = {};
        if (!data[parentSid].children[sid]) data[parentSid].children[sid] = {
          scroll: 0,
          expanded: "",
          entries: []
        };
        data[parentSid].children[sid] = {
          ...data[parentSid].children[sid],
          scroll
        };
      } else {
        data[sid] = {
          ...data[sid],
          ts: Date.now(),
          scroll,
          children: data[sid]?.children ?? {}
        };
      }
      saveSessionData(data);
    } catch {
    }
  };
  const persistExpanded = (sid, expanded2) => {
    try {
      const data = loadSessionData();
      const {
        parentSid,
        isChild
      } = resolveParent(sid);
      if (isChild) {
        if (!data[parentSid]) data[parentSid] = {
          ts: Date.now(),
          entries: [],
          scroll: 0,
          expanded: "",
          children: {}
        };
        if (!data[parentSid].children) data[parentSid].children = {};
        if (!data[parentSid].children[sid]) data[parentSid].children[sid] = {
          scroll: 0,
          expanded: "",
          entries: []
        };
        data[parentSid].children[sid] = {
          ...data[parentSid].children[sid],
          expanded: expanded2
        };
      } else {
        data[sid] = {
          ...data[sid],
          ts: Date.now(),
          expanded: expanded2,
          children: data[sid]?.children ?? {}
        };
      }
      saveSessionData(data);
    } catch {
    }
  };
  const cleanupOldSessions = () => {
    if (ttlDays <= 0) return;
    try {
      const data = loadSessionData();
      const cutoff = Date.now() - TTL_MS;
      let changed = false;
      for (const sid of Object.keys(data)) {
        if (data[sid].ts < cutoff) {
          delete data[sid];
          changed = true;
        }
      }
      if (changed) saveSessionData(data);
    } catch {
    }
  };
  cleanupOldSessions();
  const [entryMap, setEntryMapRaw] = createSignal(loadEntries(props.sessionId));
  const setEntryMap = (arg) => {
    setEntryMapRaw((prev) => {
      const next = typeof arg === "function" ? arg(prev) : arg;
      let needsImmediateFlush = false;
      for (const [id, entry] of next) {
        const prevEntry = prev.get(id);
        if (prevEntry?.status === "running" && (entry.status === "done" || entry.status === "error" || entry.status === "cancelled")) {
          needsImmediateFlush = true;
          break;
        }
      }
      if (needsImmediateFlush) {
        clearTimeout(persistTimer);
        try {
          const data = loadSessionData();
          const {
            parentSid,
            isChild
          } = resolveParent(props.sessionId);
          if (isChild) {
            if (!data[parentSid]) data[parentSid] = {
              ts: Date.now(),
              entries: [],
              scroll: 0,
              expanded: "",
              children: {}
            };
            if (!data[parentSid].children) data[parentSid].children = {};
            if (!data[parentSid].children[props.sessionId]) data[parentSid].children[props.sessionId] = {
              scroll: 0,
              expanded: "",
              entries: []
            };
            data[parentSid].children[props.sessionId] = {
              ...data[parentSid].children[props.sessionId],
              entries: [...next.values()]
            };
          } else {
            data[props.sessionId] = {
              ...data[props.sessionId],
              ts: Date.now(),
              entries: [...next.values()],
              children: data[props.sessionId]?.children ?? {}
            };
          }
          saveSessionData(data);
        } catch {
        }
      } else {
        persistEntries(props.sessionId, next);
      }
      globalEntryCache.set(props.sessionId, new Map(next));
      return next;
    });
  };
  const [panelWidth, setPanelWidth] = createSignal(28);
  const [open, setOpen] = createSignal((() => {
    try {
      return props.api.kv.get(`${KV_PREFIX}.open`, true);
    } catch {
      return true;
    }
  })());
  const [expanded, setExpanded] = createSignal((() => {
    try {
      const {
        parentSid,
        isChild
      } = resolveParent(props.sessionId);
      const rec = loadSessionData()[parentSid];
      if (rec) return isChild ? rec.children?.[props.sessionId]?.expanded || void 0 : rec.expanded || void 0;
    } catch {
    }
    return void 0;
  })());
  const [hoveredOpen, setHoveredOpen] = createSignal(void 0);
  const [hoveredDismiss, setHoveredDismiss] = createSignal(void 0);
  const [hoveredCancel, setHoveredCancel] = createSignal(void 0);
  const [hoveredTop, setHoveredTop] = createSignal(false);
  const [hoveredMoreAbove, setHoveredMoreAbove] = createSignal(false);
  const [hoveredMoreBelow, setHoveredMoreBelow] = createSignal(false);
  const [scrollOffset, setScrollOffset] = createSignal((() => {
    try {
      const {
        parentSid,
        isChild
      } = resolveParent(props.sessionId);
      const rec = loadSessionData()[parentSid];
      return isChild ? rec?.children?.[props.sessionId]?.scroll ?? 0 : rec?.scroll ?? 0;
    } catch {
      return 0;
    }
  })());
  const [now, setNow] = createSignal(Date.now());
  const [renderTick, setRenderTick] = createSignal(0);
  let boxEl;
  let disposed = false;
  const readSessionTokens = (sid) => {
    if (!sid) return void 0;
    try {
      const msgs = props.api.state.session.messages(sid);
      if (msgs) {
        for (let i = msgs.length - 1; i >= 0; i--) {
          const m = msgs[i];
          if (m.role !== "assistant") continue;
          const t2 = m.tokens;
          if (!t2 || !(Number(t2.output) > 0)) continue;
          const ctx = (Number(t2.input) || 0) + (Number(t2.output) || 0) + (Number(t2.reasoning) || 0) + (Number(t2.cache?.read) || 0) + (Number(t2.cache?.write) || 0);
          if (ctx > 0) return ctx;
        }
      }
      return void 0;
    } catch {
      return void 0;
    }
  };
  const readSessionCost = (sid) => {
    if (!sid) return void 0;
    try {
      const session = props.api.state.session.get(sid);
      if (session?.cost != null && session.cost > 0) return session.cost;
      const msgs = props.api.state.session.messages(sid);
      if (!msgs) return void 0;
      let total = 0;
      for (const m of msgs) {
        if (m.role === "assistant" && typeof m.cost === "number") total += m.cost;
      }
      return total > 0 ? total : void 0;
    } catch {
      return void 0;
    }
  };
  const readSessionModel = (sid) => {
    if (!sid) return void 0;
    try {
      const msgs = props.api.state.session.messages(sid);
      if (msgs) {
        for (let i = msgs.length - 1; i >= 0; i--) {
          const m = msgs[i];
          if (m.role === "assistant" && m.modelID) return String(m.modelID);
        }
      }
      return void 0;
    } catch {
      return void 0;
    }
  };
  const readSessionTodo = (sid) => {
    if (!sid) return void 0;
    try {
      const todos = props.api.state.session.todo(sid);
      if (!todos || todos.length === 0) return void 0;
      let done = 0;
      for (const t2 of todos) {
        if (t2.status === "completed" || t2.status === "cancelled") done++;
      }
      return {
        total: todos.length,
        done
      };
    } catch {
      return void 0;
    }
  };
  const upsertEntry = (partial) => {
    setEntryMap((prev) => {
      const existing = prev.get(partial.id);
      const next = new Map(prev);
      const nowTs = Date.now();
      const e = partial.status;
      const ended = e === "done" || e === "error" || e === "cancelled";
      next.set(partial.id, {
        ...existing ?? {
          startedAt: nowTs
        },
        ...partial,
        startedAt: existing?.startedAt || partial.startedAt || nowTs,
        endedAt: ended ? existing?.endedAt || nowTs : void 0
      });
      return next;
    });
  };
  const isDescendantOf = (childId, rootId) => {
    const visited = /* @__PURE__ */ new Set();
    try {
      let current = props.api.state.session.get(childId);
      while (current?.parentID) {
        if (visited.has(current.id)) return false;
        visited.add(current.id);
        if (current.parentID === rootId) return true;
        current = props.api.state.session.get(current.parentID);
      }
    } catch {
    }
    return false;
  };
  const settleOnIdle = (entry) => {
    if (entry.status === "cancel_requested" && entry.abortAccepted) return "cancelled";
    return "done";
  };
  const cancelEntry = async (entry) => {
    const childId = entry.sessionId;
    if (!childId) {
      props.api.ui.toast({
        title: entry.title || entry.agent,
        message: t("cancel.label") + ": " + t("cancel.no_session")
      });
      return;
    }
    try {
      const child = props.api.state.session.get(childId);
      if (!child?.parentID) {
        props.api.ui.toast({
          title: entry.title || entry.agent,
          message: t("cancel.label") + ": " + t("cancel.not_child")
        });
        return;
      }
    } catch {
      props.api.ui.toast({
        title: entry.title || entry.agent,
        message: t("cancel.label") + ": " + t("cancel.read_error")
      });
      return;
    }
    if (!isDescendantOf(childId, props.sessionId)) {
      props.api.ui.toast({
        title: entry.title || entry.agent,
        message: t("cancel.label") + ": " + t("cancel.outside_tree")
      });
      return;
    }
    try {
      const st = props.api.state.session.status(childId);
      if (st?.type !== "busy") {
        const tokens = readSessionTokens(childId);
        const cost = readSessionCost(childId);
        upsertEntry({
          id: entry.id,
          title: entry.title,
          agent: entry.agent,
          prompt: entry.prompt,
          status: "done",
          sessionId: entry.sessionId,
          tokens,
          cost
        });
        return;
      }
    } catch {
      props.api.ui.toast({
        title: entry.title || entry.agent,
        message: t("cancel.label") + ": " + t("cancel.status_error")
      });
      return;
    }
    upsertEntry({
      id: entry.id,
      title: entry.title,
      agent: entry.agent,
      prompt: entry.prompt,
      status: "cancel_requested",
      sessionId: entry.sessionId,
      cancelRequestedAt: Date.now(),
      abortAccepted: false,
      cancelReason: "manual"
    });
    try {
      await props.api.client.session.abort({
        sessionID: childId
      });
      upsertEntry({
        id: entry.id,
        title: entry.title,
        agent: entry.agent,
        prompt: entry.prompt,
        status: "cancel_requested",
        sessionId: entry.sessionId,
        abortAccepted: true
      });
      props.api.ui.toast({
        message: t("cancel.label") + ": " + t("cancel.sent")
      });
    } catch (err) {
      upsertEntry({
        id: entry.id,
        title: entry.title,
        agent: entry.agent,
        prompt: entry.prompt,
        status: "error",
        sessionId: entry.sessionId,
        error: String(err)
      });
      props.api.ui.toast({
        title: entry.title || entry.agent,
        message: t("cancel.label") + ": " + t("cancel.failed")
      });
    }
  };
  const handlePartUpdated = (event) => {
    const e = event;
    const props_ = e.properties;
    const part = props_?.part;
    if (!part) return;
    if (part.type === "subtask") {
      const agent = String(part.agent ?? "?");
      const prompt = String(part.prompt ?? "");
      const desc = String(part.description ?? "");
      const title = desc || truncate(prompt.replace(/\n/g, " ").replace(/\s+/g, " ").trim(), 40);
      const id = `sub:${String(part.id ?? crypto.randomUUID())}`;
      const subSid = part.sessionID !== void 0 ? String(part.sessionID) : void 0;
      const partModel = part.model;
      const modelId = partModel?.modelID ? String(partModel.modelID) : void 0;
      upsertEntry({
        id,
        title,
        agent,
        prompt,
        sessionId: subSid,
        status: "running",
        model: modelId
      });
    }
    if (part.type === "tool") {
      const tool = String(part.tool ?? "");
      if (!SUBAGENT_TOOLS.has(tool)) return;
      const st = part.state;
      const rawStatus = String(st?.status ?? "");
      if (rawStatus === "pending" || rawStatus === "") return;
      if (rawStatus === "error") {
        const id2 = `tool:${String(part.id ?? "")}`;
        if (!part.id) return;
        const existing = entryMap().get(id2);
        if (existing) {
          upsertEntry({
            id: id2,
            title: existing.title,
            agent: existing.agent,
            prompt: existing.prompt,
            status: "error"
          });
        }
        return;
      }
      const input = st?.input;
      let status = "running";
      if (rawStatus === "completed") status = "done";
      if ((input?.run_in_background === true || input?.background === true) && status === "done") {
        const stMetaCheck = st?.metadata;
        const hasChild = stMetaCheck?.session_id !== void 0 || stMetaCheck?.sessionId !== void 0;
        if (hasChild) status = "running";
      }
      const agent = String(part.subagent_type ?? input?.subagent_type ?? input?.category ?? tool);
      const prompt = String(input?.prompt ?? part.description ?? "");
      const desc = input?.description !== void 0 ? String(input.description) : "";
      const title = desc || truncate(prompt.replace(/\n/g, " ").replace(/\s+/g, " ").trim(), 40);
      const id = `tool:${String(part.id ?? crypto.randomUUID())}`;
      const stMeta = st?.metadata;
      const subSid = stMeta?.session_id !== void 0 ? String(stMeta.session_id) : stMeta?.sessionId !== void 0 ? String(stMeta.sessionId) : void 0;
      upsertEntry({
        id,
        title,
        agent,
        prompt,
        sessionId: subSid,
        status
      });
    }
  };
  const handleSessionEnd = (event, status) => {
    const e = event;
    const props_ = e.properties;
    const sid = String(props_?.sessionID ?? "");
    if (!sid) return;
    const sessionTokens = readSessionTokens(sid);
    const sessionCost = readSessionCost(sid);
    const sessionModel = readSessionModel(sid);
    const sessionTodo = readSessionTodo(sid);
    let sessionAgent;
    let errorMsg;
    try {
      const s = props.api.state.session.get(sid);
      sessionAgent = s?.agent;
      if (status === "error") {
        const evtErr = props_?.error;
        errorMsg = safeErrorMsg(evtErr) || safeErrorMsg(props_?.message);
        if (!errorMsg) {
          const msgs = props.api.state.session.messages(sid);
          if (msgs) {
            for (let i = msgs.length - 1; i >= 0; i--) {
              const m = msgs[i];
              if (m.role === "assistant" && m.error) {
                errorMsg = safeErrorMsg(m.error);
                break;
              }
            }
          }
        }
      }
    } catch {
    }
    const tryMatchAndUpdate = (entriesMap, targetSid, targetStatus, nowTs) => {
      for (const [, entry] of entriesMap) {
        if (entry.sessionId === targetSid && (entry.status === "running" || entry.status === "cancel_requested")) {
          const finalStatus = targetStatus === "error" ? "error" : settleOnIdle(entry);
          entry.status = finalStatus;
          entry.endedAt = nowTs;
          entry.tokens = entry.tokens ?? sessionTokens;
          entry.cost = entry.cost ?? sessionCost;
          entry.model = entry.model ?? sessionModel;
          entry.todoTotal = entry.todoTotal ?? sessionTodo?.total;
          entry.todoDone = entry.todoDone ?? sessionTodo?.done;
          entry.error = errorMsg || entry.error;
          return true;
        }
      }
      if (sessionAgent) {
        const normalize = (s) => s.toLowerCase().replace(/[^a-z0-9-]/g, "");
        const saNorm = normalize(sessionAgent);
        let best = null;
        for (const [, entry] of entriesMap) {
          if (entry.status !== "running" && entry.status !== "cancel_requested") continue;
          const eaNorm = normalize(entry.agent);
          if (!eaNorm || !saNorm) continue;
          if (!eaNorm.includes(saNorm) && !saNorm.includes(eaNorm)) continue;
          const gap = nowTs - (entry.startedAt || 0);
          if (!best || gap > best.gap) best = {
            entry,
            gap
          };
        }
        if (!best) {
          for (const [, entry] of entriesMap) {
            if (entry.status !== "running" && entry.status !== "cancel_requested") continue;
            if (entry.sessionId) continue;
            const gap = nowTs - (entry.startedAt || 0);
            if (!best || gap > best.gap) best = {
              entry,
              gap
            };
          }
        }
        if (best) {
          const finalStatus = targetStatus === "error" ? "error" : settleOnIdle(best.entry);
          best.entry.status = finalStatus;
          best.entry.endedAt = nowTs;
          best.entry.tokens = best.entry.tokens ?? sessionTokens;
          best.entry.cost = best.entry.cost ?? sessionCost;
          best.entry.model = best.entry.model ?? sessionModel;
          best.entry.todoTotal = best.entry.todoTotal ?? sessionTodo?.total;
          best.entry.todoDone = best.entry.todoDone ?? sessionTodo?.done;
          best.entry.sessionId = targetSid;
          best.entry.error = errorMsg || best.entry.error;
          return true;
        }
      }
      return false;
    };
    setEntryMap((prev) => {
      let changed = false;
      const next = new Map(prev);
      for (const [id, entry] of next) {
        if (entry.sessionId !== sid) continue;
        if (entry.status !== "running" && entry.status !== "done" && entry.status !== "cancel_requested") continue;
        if (sid === props.sessionId) continue;
        const alreadySettled = entry.status !== "running" && entry.status !== "cancel_requested";
        const finalStatus = status === "error" ? "error" : settleOnIdle(entry);
        next.set(id, {
          ...entry,
          ...alreadySettled ? {} : {
            status: finalStatus,
            endedAt: Date.now()
          },
          tokens: entry.tokens ?? sessionTokens,
          cost: entry.cost ?? sessionCost,
          model: entry.model ?? sessionModel,
          todoTotal: entry.todoTotal ?? sessionTodo?.total,
          todoDone: entry.todoDone ?? sessionTodo?.done,
          error: errorMsg || entry.error
        });
        changed = true;
      }
      if (!changed && sessionAgent) {
        const nowTs = Date.now();
        const normalize = (s) => s.toLowerCase().replace(/[^a-z0-9-]/g, "");
        const saNorm = normalize(sessionAgent);
        let best = null;
        for (const [id, entry] of next) {
          if (entry.status !== "running" && entry.status !== "cancel_requested") continue;
          const eaNorm = normalize(entry.agent);
          if (!eaNorm || !saNorm) continue;
          if (!eaNorm.includes(saNorm) && !saNorm.includes(eaNorm)) continue;
          const gap = nowTs - (entry.startedAt || 0);
          if (!best || gap > best.gap) best = {
            id,
            gap
          };
        }
        if (!best) {
          for (const [id, entry] of next) {
            if (entry.status !== "running" && entry.status !== "cancel_requested") continue;
            if (entry.sessionId) continue;
            const gap = nowTs - (entry.startedAt || 0);
            if (!best || gap > best.gap) best = {
              id,
              gap
            };
          }
        }
        if (best) {
          const entry = next.get(best.id);
          const finalStatus = status === "error" ? "error" : settleOnIdle(entry);
          next.set(best.id, {
            ...entry,
            status: finalStatus,
            endedAt: nowTs,
            tokens: sessionTokens || entry.tokens,
            cost: sessionCost || entry.cost,
            sessionId: sid,
            error: errorMsg || entry.error
          });
          changed = true;
        }
      }
      return changed ? next : prev;
    });
    try {
      const sessionObj = props.api.state.session.get(sid);
      const parentSid = sessionObj?.parentID;
      if (parentSid && parentSid !== props.sessionId) {
        const parentCache = globalEntryCache.get(parentSid);
        const nowTs = Date.now();
        let found = false;
        if (parentCache) {
          found = tryMatchAndUpdate(parentCache, sid, status, nowTs);
        }
        if (!found) {
          const data = loadSessionData();
          const rec = data[parentSid];
          if (rec?.entries) {
            const fallbackMap = new Map(rec.entries.map((e2) => [e2.id, e2]));
            found = tryMatchAndUpdate(fallbackMap, sid, status, nowTs);
            if (found) {
              data[parentSid] = {
                ...rec,
                ts: nowTs,
                entries: [...fallbackMap.values()]
              };
              saveSessionData(data);
              globalEntryCache.set(parentSid, fallbackMap);
            }
          }
        }
        if (found && parentCache) {
          const data = loadSessionData();
          data[parentSid] = {
            ...data[parentSid],
            ts: nowTs,
            entries: [...parentCache.values()]
          };
          saveSessionData(data);
        }
      }
    } catch {
    }
    setTimeout(() => {
      if (disposed) return;
      const finalTokens = readSessionTokens(sid);
      const finalCost = readSessionCost(sid);
      const finalModel = readSessionModel(sid);
      const finalTodo = readSessionTodo(sid);
      setEntryMap((prev) => {
        let changed = false;
        const next = new Map(prev);
        for (const [id, entry] of next) {
          if (entry.sessionId !== sid) continue;
          const t2 = finalTokens ?? entry.tokens;
          const c = finalCost ?? entry.cost;
          const m = finalModel ?? entry.model;
          const tt = finalTodo?.total ?? entry.todoTotal;
          const td = finalTodo?.done ?? entry.todoDone;
          if (t2 !== entry.tokens || c !== entry.cost || m !== entry.model || tt !== entry.todoTotal || td !== entry.todoDone) {
            next.set(id, {
              ...entry,
              tokens: t2,
              cost: c,
              model: m,
              todoTotal: tt,
              todoDone: td
            });
            changed = true;
          }
        }
        return changed ? next : prev;
      });
      bump();
    }, 150);
  };
  const bump = () => setRenderTick((v) => v + 1);
  onMount(() => {
    const clock = setInterval(() => {
      setNow(Date.now());
      bump();
    }, 100);
    const tokenTimer = setInterval(() => {
      untrack(() => {
        setEntryMapRaw((prev) => {
          let changed = false;
          const next = new Map(prev);
          for (const [id, entry] of next) {
            if (entry.status === "running" && entry.sessionId) {
              let isChild = false;
              try {
                const s = props.api.state.session.get(entry.sessionId);
                isChild = s?.parentID === props.sessionId;
              } catch {
              }
              if (!isChild) continue;
              const total = readSessionTokens(entry.sessionId);
              const todo = readSessionTodo(entry.sessionId);
              const model = entry.model ?? readSessionModel(entry.sessionId);
              const nextEntry = {
                ...entry
              };
              if (total !== void 0 && total !== entry.tokens) {
                nextEntry.tokens = total;
                changed = true;
              }
              if (todo !== void 0) {
                if (todo.total !== entry.todoTotal || todo.done !== entry.todoDone) {
                  nextEntry.todoTotal = todo.total;
                  nextEntry.todoDone = todo.done;
                  changed = true;
                }
              }
              if (model && !entry.model) {
                nextEntry.model = model;
                changed = true;
              }
              if (changed) next.set(id, nextEntry);
            }
          }
          return changed ? next : prev;
        });
      });
      bump();
    }, 500);
    bump();
    const unsubPart = props.api.event.on("message.part.updated", (e) => {
      handlePartUpdated(e);
      bump();
    });
    const unsubMsg = props.api.event.on("message.updated", () => bump());
    const unsubIdle = props.api.event.on("session.idle", (e) => {
      handleSessionEnd(e, "done");
      bump();
    });
    const unsubError = props.api.event.on("session.error", (e) => {
      handleSessionEnd(e, "error");
      bump();
    });
    onCleanup(() => {
      disposed = true;
      clearInterval(clock);
      clearInterval(tokenTimer);
      unsubPart();
      unsubMsg();
      unsubIdle();
      unsubError();
    });
  });
  let lastSid = props.sessionId;
  let lastTick = 0;
  createEffect(() => {
    const sid = props.sessionId;
    const switched = sid !== lastSid;
    lastSid = sid;
    const tick = clearTick();
    const forceReload = tick !== lastTick && !switched;
    lastTick = tick;
    const t2 = setTimeout(() => {
      untrack(() => {
        if (switched) {
          const {
            parentSid,
            isChild
          } = resolveParent(sid);
          const data = loadSessionData();
          const saved = isChild ? data[parentSid]?.children?.[sid]?.scroll ?? 0 : data[sid]?.scroll ?? 0;
          setScrollOffset(saved);
          if (!isChild && data[sid]?.entries?.length) {
            data[sid].ts = Date.now();
            saveSessionData(data);
          }
        }
        setEntryMapRaw((prev) => {
          const next = switched || forceReload ? new Map(globalEntryCache.get(sid) ?? loadEntries(sid)) : new Map(prev);
          const {
            parentSid: scanPSid,
            isChild: scanChild
          } = resolveParent(sid);
          const scanRec = loadSessionData()[scanPSid];
          const clearedIds = new Set(scanChild ? scanRec?.children?.[sid]?.clearedIds : scanRec?.clearedIds);
          try {
            const msgs = props.api.state.session.messages(sid);
            if (msgs && msgs.length) {
              for (const msg of msgs) {
                const parts = props.api.state.part(msg.id) ?? [];
                for (const partRaw of parts) {
                  const part = partRaw;
                  if (part.type === "tool") {
                    const tool = String(part.tool ?? "");
                    if (!SUBAGENT_TOOLS.has(tool)) continue;
                    const id = `tool:${String(part.id ?? "")}`;
                    if (!part.id) continue;
                    const st = part.state;
                    const rawStatus = String(st?.status ?? "");
                    const exists = next.get(id);
                    if (!exists && clearedIds.has(id)) continue;
                    if ((rawStatus === "pending" || rawStatus === "") && !exists) continue;
                    if (rawStatus === "error") {
                      if (exists && exists.status === "running") {
                        next.set(id, {
                          ...exists,
                          status: "error",
                          endedAt: Date.now()
                        });
                      }
                      continue;
                    }
                    let status = "running";
                    if (rawStatus === "completed") status = "done";
                    if ((st?.input?.run_in_background === true || st?.input?.background === true) && status === "done") {
                      const scanStMeta = st?.metadata;
                      const scanHasChild = scanStMeta?.session_id !== void 0 || scanStMeta?.sessionId !== void 0;
                      if (scanHasChild) status = "running";
                    }
                    if (exists && exists.status !== "running" && exists.status !== "cancel_requested") continue;
                    if (exists && status === "running") {
                      if (!rawStatus) {
                        const msgTokens = msg?.tokens;
                        if (msgTokens && (Number(msgTokens.input) > 0 || Number(msgTokens.output) > 0)) {
                          status = "done";
                        } else if (Date.now() - exists.startedAt > 30 * 60 * 1e3) {
                          status = "done";
                        } else {
                          continue;
                        }
                      } else {
                        continue;
                      }
                    }
                    const input = st?.input;
                    const agent = String(part.subagent_type ?? input?.subagent_type ?? tool);
                    const prompt = String(input?.prompt ?? part.description ?? "");
                    const desc = input?.description !== void 0 ? String(input.description) : "";
                    const title = desc || truncate(prompt.replace(/\n/g, " ").trim(), 40);
                    let tokens;
                    const scanStMeta2 = st?.metadata;
                    const scanSubSid = scanStMeta2?.session_id !== void 0 ? String(scanStMeta2.session_id) : scanStMeta2?.sessionId !== void 0 ? String(scanStMeta2.sessionId) : void 0;
                    if (scanSubSid) tokens = readSessionTokens(scanSubSid);
                    const ended = status === "done";
                    next.set(id, {
                      id,
                      title,
                      agent,
                      prompt,
                      // Preserve existing values (from handleSessionEnd / KV) — scan must not overwrite
                      tokens: exists?.tokens ?? tokens,
                      sessionId: exists?.sessionId ?? scanSubSid,
                      status,
                      startedAt: exists?.startedAt || Date.now(),
                      endedAt: ended ? exists?.endedAt || Date.now() : void 0
                    });
                  }
                }
              }
            }
          } catch {
          }
          return next;
        });
        setEntryMapRaw((prev) => {
          let changed = false;
          const next = new Map(prev);
          for (const [id, entry] of next) {
            if (entry.status !== "running" && entry.status !== "cancel_requested" || !entry.sessionId) continue;
            try {
              const st = props.api.state.session.status(entry.sessionId);
              if (!st || st.type !== "idle") continue;
              const tokens = readSessionTokens(entry.sessionId);
              const cost = readSessionCost(entry.sessionId);
              const finalStatus = entry.status === "cancel_requested" && entry.abortAccepted ? "cancelled" : "done";
              next.set(id, {
                ...entry,
                status: finalStatus,
                endedAt: Date.now(),
                tokens: tokens ?? entry.tokens,
                cost: cost ?? entry.cost
              });
              changed = true;
            } catch {
            }
          }
          return changed ? next : prev;
        });
        bump();
      });
    }, 150);
    onCleanup(() => clearTimeout(t2));
  });
  const pal = createMemo(() => {
    const th = props.theme;
    const sat = (k, fb) => desaturateTo(th[k], MAX_SAT, fb);
    return {
      primary: sat("primary", FALLBACK.primary),
      text: sat("text", FALLBACK.text),
      muted: sat("textMuted", FALLBACK.muted),
      success: sat("success", FALLBACK.success),
      warning: sat("warning", FALLBACK.warning),
      error: sat("error", FALLBACK.error),
      border: sat("border", FALLBACK.border)
    };
  });
  const entryList = createMemo(() => {
    const entries2 = [...entryMap().values()];
    if (props.sortOrder() === "desc") {
      return entries2.sort((a, b) => b.startedAt - a.startedAt);
    }
    return entries2.sort((a, b) => a.startedAt - b.startedAt);
  });
  const max = props.maxEntries;
  const clampedOffset = createMemo(() => {
    const total = entryList().length;
    const m = max();
    if (total <= m) return 0;
    return Math.min(scrollOffset(), total - m);
  });
  const visibleList = createMemo(() => entryList().slice(clampedOffset(), clampedOffset() + max()));
  const hiddenAbove = createMemo(() => clampedOffset());
  const hiddenBelow = createMemo(() => Math.max(0, entryList().length - clampedOffset() - max()));
  createEffect(() => {
    if (hiddenAbove() === 0) setHoveredMoreAbove(false);
  });
  let sortInitialized = false;
  createEffect(() => {
    props.sortOrder();
    if (!sortInitialized) {
      sortInitialized = true;
      return;
    }
    const total = untrack(() => entryList().length);
    const m = untrack(() => max());
    const target = props.sortOrder() === "desc" ? 0 : Math.max(0, total - m);
    setScrollOffset(target);
    setTimeout(() => {
      try {
        persistScroll(props.sessionId, target);
      } catch {
      }
    }, 0);
  });
  let prevEntryCount = 0;
  createEffect(() => {
    const total = entryList().length;
    if (prevEntryCount === 0) {
      prevEntryCount = total;
      return;
    }
    if (total === prevEntryCount) return;
    const m = max();
    const wasAtNewest = props.sortOrder() === "desc" ? untrack(() => scrollOffset() === 0) : untrack(() => scrollOffset() >= prevEntryCount - m);
    prevEntryCount = total;
    if (wasAtNewest) {
      const target = props.sortOrder() === "desc" ? 0 : Math.max(0, total - m);
      setScrollOffset(target);
      setTimeout(() => {
        try {
          persistScroll(props.sessionId, target);
        } catch {
        }
      }, 0);
    }
  });
  const entries = createMemo(() => {
    const nowVal = now();
    return entryList().map((e) => ({
      ...e,
      elapsed: (e.endedAt ?? nowVal) - e.startedAt
    }));
  });
  const doneCount = createMemo(() => entryList().filter((e) => e.status === "done" || e.status === "cancelled").length);
  const runningCount = createMemo(() => entryList().filter((e) => e.status === "running" || e.status === "cancel_requested").length);
  const errCount = createMemo(() => entryList().filter((e) => e.status === "error").length);
  const anyEntry = () => entryList().length > 0;
  const totalTokens = createMemo(() => {
    let sum = 0;
    for (const e of entryList()) {
      if (e.tokens) sum += e.tokens;
    }
    return sum;
  });
  const totalCost = createMemo(() => {
    let sum = 0;
    for (const e of entryList()) {
      if (e.cost) sum += e.cost;
    }
    return sum;
  });
  const toggleExpand = (id) => {
    setExpanded((prev) => {
      const next = prev === id ? void 0 : id;
      try {
        persistExpanded(props.sessionId, next ?? "");
      } catch {
      }
      return next;
    });
  };
  const sep = () => "\u2500".repeat(Math.max(1, panelWidth()));
  const expandedMaxLabelW = createMemo(() => {
    const labels = [t("agent.label"), t("status.label"), t("time.label"), t("tokens.label"), t("error.label"), t("cost.label"), t("model.label"), t("todo.label"), t("session.label")];
    return Math.max(...labels.map((l) => visualWidth(l + ": ")));
  });
  const expandedPad = (label) => Math.max(0, expandedMaxLabelW() - visualWidth(label + ": "));
  const expandedValAvail = () => Math.max(6, panelWidth() - INDENT - expandedMaxLabelW());
  const summaryParts = createMemo(() => {
    if (!anyEntry()) return null;
    const dot = "\u25CF";
    const cost = totalCost();
    return {
      done: `${dot}${doneCount()}`,
      running: runningCount() > 0 ? `${dot}${runningCount()}` : null,
      err: errCount() > 0 ? `${dot}${errCount()}` : null,
      duration: totalTokens() > 0 ? fmtTokens(totalTokens()) : "",
      cost: cost > 0 ? `$${cost.toFixed(2)}` : ""
    };
  });
  const summaryCols = createMemo(() => {
    const p = summaryParts();
    if (!p) return 0;
    let w = visualWidth(p.done);
    if (p.running) w += 1 + visualWidth(p.running);
    if (p.err) w += 1 + visualWidth(p.err);
    w += p.duration ? 1 + visualWidth(p.duration) : 0;
    w += p.cost ? 1 + visualWidth(p.cost) : 0;
    return w;
  });
  const versionText = ` v${PLUGIN_VERSION}`;
  const versionW = visualWidth(versionText);
  const showVersion = createMemo(() => {
    if (!open()) return false;
    const icon = "\u25BC";
    const need = visualWidth(icon) + 1 + visualWidth(t("panel.title")) + versionW + summaryCols();
    return need <= panelWidth();
  });
  const leftCols = createMemo(() => {
    const icon = open() ? "\u25BC" : "\u25B6";
    let w = visualWidth(icon) + 1 + visualWidth(t("panel.title"));
    if (showVersion()) w += versionW;
    return w;
  });
  const spacerCols = createMemo(() => {
    if (!anyEntry()) return 0;
    return Math.max(0, panelWidth() - leftCols() - summaryCols());
  });
  const valueCols = (label) => Math.max(4, panelWidth() - INDENT - visualWidth(label + ": "));
  return (() => {
    var _el$ = _$createElement("box"), _el$2 = _$createElement("text"), _el$3 = _$createElement("span"), _el$4 = _$createElement("span");
    _$insertNode(_el$, _el$2);
    var _ref$ = boxEl;
    typeof _ref$ === "function" ? _$use(_ref$, _el$) : boxEl = _el$;
    _$setProp(_el$, "border", false);
    _$setProp(_el$, "paddingTop", 0);
    _$setProp(_el$, "paddingBottom", 0);
    _$setProp(_el$, "paddingLeft", 0);
    _$setProp(_el$, "paddingRight", 0);
    _$setProp(_el$, "flexDirection", "column");
    _$setProp(_el$, "gap", 0);
    _$setProp(_el$, "onSizeChange", () => {
      const w = boxEl ? Math.max(20, boxEl.width ?? 0) : 28;
      setPanelWidth((prev) => prev === w ? prev : w);
    });
    _$insertNode(_el$2, _el$3);
    _$insertNode(_el$2, _el$4);
    _$setProp(_el$2, "onMouseUp", () => {
      setOpen((o) => {
        const n = !o;
        try {
          props.api.kv.set(`${KV_PREFIX}.open`, n);
        } catch {
        }
        return n;
      });
      bump();
    });
    _$insert(_el$3, () => renderTick() >= 0 && open() ? "\u25BC " : "\u25B6 ");
    _$insert(_el$4, () => t("panel.title"));
    _$insert(_el$2, _$createComponent(Show, {
      get when() {
        return showVersion();
      },
      get children() {
        var _el$5 = _$createElement("span");
        _$insert(_el$5, versionText);
        _$effect((_$p) => _$setProp(_el$5, "style", {
          fg: dimColor(pal().muted, 0.75)
        }, _$p));
        return _el$5;
      }
    }), null);
    _$insert(_el$2, (() => {
      var _c$ = _$memo(() => !!anyEntry());
      return () => _c$() ? [(() => {
        var _el$11 = _$createElement("span");
        _$insert(_el$11, () => " ".repeat(spacerCols()));
        _$effect((_$p) => _$setProp(_el$11, "style", {
          fg: pal().muted
        }, _$p));
        return _el$11;
      })(), (() => {
        var _el$12 = _$createElement("span");
        _$insert(_el$12, () => summaryParts().done);
        _$effect((_$p) => _$setProp(_el$12, "style", {
          fg: pal().success
        }, _$p));
        return _el$12;
      })(), _$memo(() => _$memo(() => runningCount() > 0)() && (() => {
        var _el$13 = _$createElement("span"), _el$14 = _$createTextNode(` `);
        _$insertNode(_el$13, _el$14);
        _$insert(_el$13, () => summaryParts().running, null);
        _$effect((_$p) => _$setProp(_el$13, "style", {
          fg: pal().warning
        }, _$p));
        return _el$13;
      })()), _$memo(() => _$memo(() => errCount() > 0)() && (() => {
        var _el$15 = _$createElement("span"), _el$16 = _$createTextNode(` `);
        _$insertNode(_el$15, _el$16);
        _$insert(_el$15, () => summaryParts().err, null);
        _$effect((_$p) => _$setProp(_el$15, "style", {
          fg: pal().error
        }, _$p));
        return _el$15;
      })()), _$memo(() => _$memo(() => !!summaryParts().duration)() ? (() => {
        var _el$17 = _$createElement("span"), _el$18 = _$createTextNode(` `);
        _$insertNode(_el$17, _el$18);
        _$insert(_el$17, () => summaryParts().duration, null);
        _$effect((_$p) => _$setProp(_el$17, "style", {
          fg: pal().muted
        }, _$p));
        return _el$17;
      })() : null), _$memo(() => _$memo(() => !!summaryParts().cost)() ? (() => {
        var _el$19 = _$createElement("span"), _el$20 = _$createTextNode(` `);
        _$insertNode(_el$19, _el$20);
        _$insert(_el$19, () => summaryParts().cost, null);
        _$effect((_$p) => _$setProp(_el$19, "style", {
          fg: pal().warning
        }, _$p));
        return _el$19;
      })() : null)] : null;
    })(), null);
    _$insert(_el$, _$createComponent(Show, {
      get when() {
        return open();
      },
      get children() {
        return [(() => {
          var _el$6 = _$createElement("text");
          _$insert(_el$6, sep);
          _$effect((_$p) => _$setProp(_el$6, "fg", pal().muted, _$p));
          return _el$6;
        })(), _$createComponent(Show, {
          get when() {
            return anyEntry();
          },
          get fallback() {
            return (() => {
              var _el$21 = _$createElement("text"), _el$22 = _$createTextNode(`  &gt; `), _el$24 = _$createTextNode(` `);
              _$insertNode(_el$21, _el$22);
              _$insertNode(_el$21, _el$24);
              _$insert(_el$21, () => t("status.none"), _el$24);
              _$effect((_$p) => _$setProp(_el$21, "style", {
                fg: pal().muted
              }, _$p));
              return _el$21;
            })();
          },
          get children() {
            var _el$7 = _$createElement("box");
            _$setProp(_el$7, "onMouseScroll", (e) => {
              if (props.scrollMode() === "click") return;
              const total = entryList().length;
              const m = max();
              if (total <= m) return;
              const dir = e.button === 0 ? 1 : -1;
              setScrollOffset((prev) => {
                const next = Math.max(0, Math.min(prev + dir, total - m));
                try {
                  persistScroll(props.sessionId, next);
                } catch {
                }
                return next;
              });
            });
            _$insert(_el$7, _$createComponent(Show, {
              get when() {
                return hiddenAbove() > 0;
              },
              get children() {
                var _el$8 = _$createElement("text"), _el$9 = _$createElement("span"), _el$0 = _$createTextNode(`  &uarr; `), _el$10 = _$createTextNode(` `);
                _$insertNode(_el$8, _el$9);
                _$setProp(_el$8, "onMouseOver", () => setHoveredMoreAbove(true));
                _$setProp(_el$8, "onMouseOut", () => setHoveredMoreAbove(false));
                _$setProp(_el$8, "onMouseUp", () => {
                  const total = entryList().length;
                  const m = max();
                  if (total <= m) return;
                  const next = Math.max(0, scrollOffset() - m);
                  if (next === 0) {
                    setTimeout(() => {
                      setScrollOffset(next);
                      try {
                        persistScroll(props.sessionId, next);
                      } catch {
                      }
                    }, 0);
                  } else {
                    setScrollOffset(next);
                    try {
                      persistScroll(props.sessionId, next);
                    } catch {
                    }
                  }
                });
                _$insertNode(_el$9, _el$0);
                _$insertNode(_el$9, _el$10);
                _$insert(_el$9, hiddenAbove, _el$10);
                _$insert(_el$9, () => t("scroll.more"), null);
                _$effect((_$p) => _$setProp(_el$9, "style", {
                  fg: hoveredMoreAbove() ? pal().warning : pal().muted
                }, _$p));
                return _el$8;
              }
            }), null);
            _$insert(_el$7, _$createComponent(For, {
              get each() {
                return visibleList();
              },
              children: (entry) => {
                const isExpanded = () => expanded() === entry.id;
                const isRunning = entry.status === "running";
                const isCancelRequested = entry.status === "cancel_requested";
                const isCancelled = entry.status === "cancelled";
                const isError = entry.status === "error";
                const isActiveRunning = isRunning || isCancelRequested;
                const elapsed = () => (entry.endedAt ?? now()) - entry.startedAt;
                const statusDot = () => "\u25CF";
                const statusColor = () => {
                  if (isCancelled) return pal().muted;
                  if (!isActiveRunning) return isError ? pal().error : pal().success;
                  const t2 = (Math.sin(now() % 2e3 / 2e3 * Math.PI * 2 - Math.PI / 2) + 1) / 2;
                  const a = rgb(pal().muted), b = rgb(pal().warning);
                  if (!a || !b) return pal().warning;
                  const r = Math.round(a.r + (b.r - a.r) * t2);
                  const g = Math.round(a.g + (b.g - a.g) * t2);
                  const bl = Math.round(a.b + (b.b - a.b) * t2);
                  return "#" + [r, g, bl].map((v) => Math.max(0, Math.min(255, v)).toString(16).padStart(2, "0")).join("");
                };
                const timeColor = () => isActiveRunning ? pal().warning : isError ? pal().error : pal().muted;
                const tokenText = () => !isExpanded() && entry.tokens !== void 0 && entry.tokens > 0 ? ` ${fmtTokens(entry.tokens)}` : "";
                const timeText = () => !isExpanded() && (elapsed() >= 2e3 || entry.endedAt !== void 0) ? fmtDurationShort(elapsed(), isActiveRunning) : "";
                const suffixW = () => {
                  let w = 0;
                  const t2 = timeText();
                  if (t2) w += 1 + visualWidth(t2);
                  const tk = tokenText();
                  if (tk) w += visualWidth(tk);
                  return w;
                };
                const labelAvail = () => Math.max(6, panelWidth() - LEFT_PAD - suffixW());
                const labelText = () => {
                  const max2 = labelAvail();
                  const text = entry.title || entry.agent;
                  const truncated = truncate(text, max2);
                  const pad = Math.max(0, max2 - visualWidth(truncated));
                  return truncated + " ".repeat(pad);
                };
                return [(() => {
                  var _el$25 = _$createElement("text"), _el$26 = _$createElement("span"), _el$27 = _$createTextNode(` `), _el$28 = _$createElement("span"), _el$29 = _$createTextNode(` `), _el$30 = _$createElement("span");
                  _$insertNode(_el$25, _el$26);
                  _$insertNode(_el$25, _el$27);
                  _$insertNode(_el$25, _el$28);
                  _$insertNode(_el$25, _el$29);
                  _$insertNode(_el$25, _el$30);
                  _$setProp(_el$25, "onMouseUp", () => toggleExpand(entry.id));
                  _$insert(_el$26, () => isExpanded() ? "\u25BC" : "\u25B6");
                  _$insert(_el$28, statusDot);
                  _$insert(_el$30, labelText);
                  _$insert(_el$25, (() => {
                    var _c$2 = _$memo(() => !!timeText());
                    return () => _c$2() ? [" ", (() => {
                      var _el$82 = _$createElement("span");
                      _$insert(_el$82, timeText);
                      _$effect((_$p) => _$setProp(_el$82, "style", {
                        fg: timeColor()
                      }, _$p));
                      return _el$82;
                    })()] : null;
                  })(), null);
                  _$insert(_el$25, (() => {
                    var _c$3 = _$memo(() => !!tokenText());
                    return () => _c$3() ? (() => {
                      var _el$83 = _$createElement("span");
                      _$insert(_el$83, tokenText);
                      _$effect((_$p) => _$setProp(_el$83, "style", {
                        fg: pal().muted
                      }, _$p));
                      return _el$83;
                    })() : null;
                  })(), null);
                  _$effect((_p$) => {
                    var _v$3 = {
                      fg: pal().muted
                    }, _v$4 = {
                      fg: statusColor()
                    }, _v$5 = {
                      fg: pal().text
                    };
                    _v$3 !== _p$.e && (_p$.e = _$setProp(_el$26, "style", _v$3, _p$.e));
                    _v$4 !== _p$.t && (_p$.t = _$setProp(_el$28, "style", _v$4, _p$.t));
                    _v$5 !== _p$.a && (_p$.a = _$setProp(_el$30, "style", _v$5, _p$.a));
                    return _p$;
                  }, {
                    e: void 0,
                    t: void 0,
                    a: void 0
                  });
                  return _el$25;
                })(), _$createComponent(Show, {
                  get when() {
                    return isExpanded();
                  },
                  get children() {
                    return [(() => {
                      var _el$31 = _$createElement("text"), _el$32 = _$createTextNode(`  `), _el$33 = _$createElement("span"), _el$34 = _$createTextNode(`: `), _el$35 = _$createElement("span"), _el$36 = _$createElement("span");
                      _$insertNode(_el$31, _el$32);
                      _$insertNode(_el$31, _el$33);
                      _$insertNode(_el$31, _el$35);
                      _$insertNode(_el$31, _el$36);
                      _$insertNode(_el$33, _el$34);
                      _$insert(_el$33, () => t("agent.label"), _el$34);
                      _$insert(_el$35, () => " ".repeat(expandedPad(t("agent.label"))));
                      _$insert(_el$36, () => entry.agent);
                      _$effect((_p$) => {
                        var _v$6 = {
                          fg: pal().primary
                        }, _v$7 = {
                          fg: pal().muted
                        }, _v$8 = {
                          fg: pal().muted
                        };
                        _v$6 !== _p$.e && (_p$.e = _$setProp(_el$33, "style", _v$6, _p$.e));
                        _v$7 !== _p$.t && (_p$.t = _$setProp(_el$35, "style", _v$7, _p$.t));
                        _v$8 !== _p$.a && (_p$.a = _$setProp(_el$36, "style", _v$8, _p$.a));
                        return _p$;
                      }, {
                        e: void 0,
                        t: void 0,
                        a: void 0
                      });
                      return _el$31;
                    })(), (() => {
                      var _el$37 = _$createElement("text"), _el$38 = _$createTextNode(`  `), _el$39 = _$createElement("span"), _el$40 = _$createTextNode(`: `), _el$41 = _$createElement("span"), _el$42 = _$createElement("span");
                      _$insertNode(_el$37, _el$38);
                      _$insertNode(_el$37, _el$39);
                      _$insertNode(_el$37, _el$41);
                      _$insertNode(_el$37, _el$42);
                      _$insertNode(_el$39, _el$40);
                      _$insert(_el$39, () => t("status.label"), _el$40);
                      _$insert(_el$41, () => " ".repeat(expandedPad(t("status.label"))));
                      _$insert(_el$42, () => isActiveRunning ? t("status.running") : isCancelled ? t("status.cancelled") : isError ? t("status.error") : t("status.done"));
                      _$effect((_p$) => {
                        var _v$9 = {
                          fg: pal().primary
                        }, _v$0 = {
                          fg: pal().muted
                        }, _v$1 = {
                          fg: isActiveRunning ? pal().warning : isCancelled ? pal().muted : isError ? pal().error : pal().success
                        };
                        _v$9 !== _p$.e && (_p$.e = _$setProp(_el$39, "style", _v$9, _p$.e));
                        _v$0 !== _p$.t && (_p$.t = _$setProp(_el$41, "style", _v$0, _p$.t));
                        _v$1 !== _p$.a && (_p$.a = _$setProp(_el$42, "style", _v$1, _p$.a));
                        return _p$;
                      }, {
                        e: void 0,
                        t: void 0,
                        a: void 0
                      });
                      return _el$37;
                    })(), _$createComponent(Show, {
                      get when() {
                        return elapsed() >= 2e3 || entry.endedAt !== void 0;
                      },
                      get children() {
                        var _el$43 = _$createElement("text"), _el$44 = _$createTextNode(`  `), _el$45 = _$createElement("span"), _el$46 = _$createTextNode(`: `), _el$47 = _$createElement("span"), _el$48 = _$createElement("span");
                        _$insertNode(_el$43, _el$44);
                        _$insertNode(_el$43, _el$45);
                        _$insertNode(_el$43, _el$47);
                        _$insertNode(_el$43, _el$48);
                        _$insertNode(_el$45, _el$46);
                        _$insert(_el$45, () => t("time.label"), _el$46);
                        _$insert(_el$47, () => " ".repeat(expandedPad(t("time.label"))));
                        _$insert(_el$48, () => fmtDurationShort(elapsed(), isActiveRunning));
                        _$effect((_p$) => {
                          var _v$10 = {
                            fg: pal().primary
                          }, _v$11 = {
                            fg: pal().muted
                          }, _v$12 = {
                            fg: pal().muted
                          };
                          _v$10 !== _p$.e && (_p$.e = _$setProp(_el$45, "style", _v$10, _p$.e));
                          _v$11 !== _p$.t && (_p$.t = _$setProp(_el$47, "style", _v$11, _p$.t));
                          _v$12 !== _p$.a && (_p$.a = _$setProp(_el$48, "style", _v$12, _p$.a));
                          return _p$;
                        }, {
                          e: void 0,
                          t: void 0,
                          a: void 0
                        });
                        return _el$43;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return entry.tokens !== void 0;
                      },
                      get children() {
                        var _el$49 = _$createElement("text"), _el$50 = _$createTextNode(`  `), _el$51 = _$createElement("span"), _el$52 = _$createTextNode(`: `), _el$53 = _$createElement("span"), _el$54 = _$createElement("span");
                        _$insertNode(_el$49, _el$50);
                        _$insertNode(_el$49, _el$51);
                        _$insertNode(_el$49, _el$53);
                        _$insertNode(_el$49, _el$54);
                        _$insertNode(_el$51, _el$52);
                        _$insert(_el$51, () => t("tokens.label"), _el$52);
                        _$insert(_el$53, () => " ".repeat(expandedPad(t("tokens.label"))));
                        _$insert(_el$54, () => fmtTokens(entry.tokens));
                        _$effect((_p$) => {
                          var _v$13 = {
                            fg: pal().primary
                          }, _v$14 = {
                            fg: pal().muted
                          }, _v$15 = {
                            fg: pal().muted
                          };
                          _v$13 !== _p$.e && (_p$.e = _$setProp(_el$51, "style", _v$13, _p$.e));
                          _v$14 !== _p$.t && (_p$.t = _$setProp(_el$53, "style", _v$14, _p$.t));
                          _v$15 !== _p$.a && (_p$.a = _$setProp(_el$54, "style", _v$15, _p$.a));
                          return _p$;
                        }, {
                          e: void 0,
                          t: void 0,
                          a: void 0
                        });
                        return _el$49;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return entry.error;
                      },
                      get children() {
                        var _el$55 = _$createElement("text"), _el$56 = _$createTextNode(`  `), _el$57 = _$createElement("span"), _el$58 = _$createTextNode(`: `), _el$59 = _$createElement("span"), _el$60 = _$createElement("span");
                        _$insertNode(_el$55, _el$56);
                        _$insertNode(_el$55, _el$57);
                        _$insertNode(_el$55, _el$59);
                        _$insertNode(_el$55, _el$60);
                        _$insertNode(_el$57, _el$58);
                        _$insert(_el$57, () => t("error.label"), _el$58);
                        _$insert(_el$59, () => " ".repeat(expandedPad(t("error.label"))));
                        _$insert(_el$60, () => truncate(String(entry.error), expandedValAvail()));
                        _$effect((_p$) => {
                          var _v$16 = {
                            fg: pal().error
                          }, _v$17 = {
                            fg: pal().muted
                          }, _v$18 = {
                            fg: pal().error
                          };
                          _v$16 !== _p$.e && (_p$.e = _$setProp(_el$57, "style", _v$16, _p$.e));
                          _v$17 !== _p$.t && (_p$.t = _$setProp(_el$59, "style", _v$17, _p$.t));
                          _v$18 !== _p$.a && (_p$.a = _$setProp(_el$60, "style", _v$18, _p$.a));
                          return _p$;
                        }, {
                          e: void 0,
                          t: void 0,
                          a: void 0
                        });
                        return _el$55;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return entry.cost !== void 0;
                      },
                      get children() {
                        return (() => {
                          const cost = entry.cost;
                          return (() => {
                            var _el$84 = _$createElement("text"), _el$85 = _$createTextNode(`  `), _el$86 = _$createElement("span"), _el$87 = _$createTextNode(`: `), _el$88 = _$createElement("span"), _el$89 = _$createElement("span"), _el$90 = _$createTextNode(`$`);
                            _$insertNode(_el$84, _el$85);
                            _$insertNode(_el$84, _el$86);
                            _$insertNode(_el$84, _el$88);
                            _$insertNode(_el$84, _el$89);
                            _$insertNode(_el$86, _el$87);
                            _$insert(_el$86, () => t("cost.label"), _el$87);
                            _$insert(_el$88, () => " ".repeat(expandedPad(t("cost.label"))));
                            _$insertNode(_el$89, _el$90);
                            _$insert(_el$89, () => cost.toFixed(4), null);
                            _$effect((_p$) => {
                              var _v$29 = {
                                fg: pal().primary
                              }, _v$30 = {
                                fg: pal().muted
                              }, _v$31 = {
                                fg: pal().muted
                              };
                              _v$29 !== _p$.e && (_p$.e = _$setProp(_el$86, "style", _v$29, _p$.e));
                              _v$30 !== _p$.t && (_p$.t = _$setProp(_el$88, "style", _v$30, _p$.t));
                              _v$31 !== _p$.a && (_p$.a = _$setProp(_el$89, "style", _v$31, _p$.a));
                              return _p$;
                            }, {
                              e: void 0,
                              t: void 0,
                              a: void 0
                            });
                            return _el$84;
                          })();
                        })();
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return entry.model;
                      },
                      get children() {
                        var _el$61 = _$createElement("text"), _el$62 = _$createTextNode(`  `), _el$63 = _$createElement("span"), _el$64 = _$createTextNode(`: `), _el$65 = _$createElement("span"), _el$66 = _$createElement("span");
                        _$insertNode(_el$61, _el$62);
                        _$insertNode(_el$61, _el$63);
                        _$insertNode(_el$61, _el$65);
                        _$insertNode(_el$61, _el$66);
                        _$insertNode(_el$63, _el$64);
                        _$insert(_el$63, () => t("model.label"), _el$64);
                        _$insert(_el$65, () => " ".repeat(expandedPad(t("model.label"))));
                        _$insert(_el$66, () => truncate(entry.model, expandedValAvail()));
                        _$effect((_p$) => {
                          var _v$19 = {
                            fg: pal().primary
                          }, _v$20 = {
                            fg: pal().muted
                          }, _v$21 = {
                            fg: pal().muted
                          };
                          _v$19 !== _p$.e && (_p$.e = _$setProp(_el$63, "style", _v$19, _p$.e));
                          _v$20 !== _p$.t && (_p$.t = _$setProp(_el$65, "style", _v$20, _p$.t));
                          _v$21 !== _p$.a && (_p$.a = _$setProp(_el$66, "style", _v$21, _p$.a));
                          return _p$;
                        }, {
                          e: void 0,
                          t: void 0,
                          a: void 0
                        });
                        return _el$61;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return entry.todoTotal !== void 0;
                      },
                      get children() {
                        var _el$67 = _$createElement("text"), _el$68 = _$createTextNode(`  `), _el$69 = _$createElement("span"), _el$70 = _$createTextNode(`: `), _el$71 = _$createElement("span"), _el$72 = _$createElement("span"), _el$73 = _$createTextNode(`/`);
                        _$insertNode(_el$67, _el$68);
                        _$insertNode(_el$67, _el$69);
                        _$insertNode(_el$67, _el$71);
                        _$insertNode(_el$67, _el$72);
                        _$insertNode(_el$69, _el$70);
                        _$insert(_el$69, () => t("todo.label"), _el$70);
                        _$insert(_el$71, () => " ".repeat(expandedPad(t("todo.label"))));
                        _$insertNode(_el$72, _el$73);
                        _$insert(_el$72, () => entry.todoDone, _el$73);
                        _$insert(_el$72, () => entry.todoTotal, null);
                        _$effect((_p$) => {
                          var _v$22 = {
                            fg: pal().primary
                          }, _v$23 = {
                            fg: pal().muted
                          }, _v$24 = {
                            fg: pal().muted
                          };
                          _v$22 !== _p$.e && (_p$.e = _$setProp(_el$69, "style", _v$22, _p$.e));
                          _v$23 !== _p$.t && (_p$.t = _$setProp(_el$71, "style", _v$23, _p$.t));
                          _v$24 !== _p$.a && (_p$.a = _$setProp(_el$72, "style", _v$24, _p$.a));
                          return _p$;
                        }, {
                          e: void 0,
                          t: void 0,
                          a: void 0
                        });
                        return _el$67;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return entry.sessionId;
                      },
                      get children() {
                        var _el$74 = _$createElement("text"), _el$75 = _$createTextNode(`  `), _el$76 = _$createElement("span"), _el$77 = _$createTextNode(`: `), _el$78 = _$createElement("span"), _el$79 = _$createElement("span"), _el$80 = _$createElement("span");
                        _$insertNode(_el$74, _el$75);
                        _$insertNode(_el$74, _el$76);
                        _$insertNode(_el$74, _el$78);
                        _$insertNode(_el$74, _el$79);
                        _$insertNode(_el$74, _el$80);
                        _$setProp(_el$74, "onMouseUp", async () => {
                          const sessionId = entry.sessionId;
                          if (!sessionId) return;
                          const result = await copyText(sessionId);
                          if (result.copied) {
                            props.api.ui.toast({
                              variant: "success",
                              title: entry.title || entry.agent,
                              message: t("session.toast.copied"),
                              duration: 2500
                            });
                            return;
                          }
                          props.api.ui.toast({
                            variant: "warning",
                            title: entry.title || entry.agent,
                            message: `${sessionId}

${t("session.toast.copy_failed")}`,
                            duration: 8e3
                          });
                        });
                        _$insertNode(_el$76, _el$77);
                        _$insert(_el$76, () => t("session.label"), _el$77);
                        _$insert(_el$78, () => " ".repeat(expandedPad(t("session.label"))));
                        _$insert(_el$79, () => truncate(entry.sessionId, expandedValAvail() - visualWidth(" \u2398")));
                        _$insertNode(_el$80, _$createTextNode(` \u2398`));
                        _$effect((_p$) => {
                          var _v$25 = {
                            fg: pal().primary
                          }, _v$26 = {
                            fg: pal().muted
                          }, _v$27 = {
                            fg: pal().muted
                          }, _v$28 = {
                            fg: pal().warning
                          };
                          _v$25 !== _p$.e && (_p$.e = _$setProp(_el$76, "style", _v$25, _p$.e));
                          _v$26 !== _p$.t && (_p$.t = _$setProp(_el$78, "style", _v$26, _p$.t));
                          _v$27 !== _p$.a && (_p$.a = _$setProp(_el$79, "style", _v$27, _p$.a));
                          _v$28 !== _p$.o && (_p$.o = _$setProp(_el$80, "style", _v$28, _p$.o));
                          return _p$;
                        }, {
                          e: void 0,
                          t: void 0,
                          a: void 0,
                          o: void 0
                        });
                        return _el$74;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return entry.sessionId || isRunning;
                      },
                      get children() {
                        return (() => {
                          const openPrefix = () => "  \u2192 ";
                          const openFull = () => entry.sessionId ? openPrefix() + t("open.label") : "";
                          const openW = () => entry.sessionId ? visualWidth(openFull()) : 0;
                          const cancelLabel = () => ` ${t("cancel.label")}`;
                          const dismissLabel = () => ` ${t("dismiss.label")}`;
                          const rightW = (isRunning ? visualWidth(dismissLabel()) : 0) + (isRunning && entry.sessionId ? visualWidth(cancelLabel()) : 0);
                          const spacerW = () => Math.max(1, panelWidth() - openW() - rightW - 2);
                          return (() => {
                            var _el$91 = _$createElement("box"), _el$95 = _$createElement("text");
                            _$insertNode(_el$91, _el$95);
                            _$setProp(_el$91, "flexDirection", "row");
                            _$insert(_el$91, _$createComponent(Show, {
                              get when() {
                                return entry.sessionId;
                              },
                              get children() {
                                var _el$92 = _$createElement("text"), _el$93 = _$createElement("span"), _el$94 = _$createElement("span");
                                _$insertNode(_el$92, _el$93);
                                _$insertNode(_el$92, _el$94);
                                _$setProp(_el$92, "onMouseOver", () => setHoveredOpen(entry.id));
                                _$setProp(_el$92, "onMouseOut", () => setHoveredOpen(void 0));
                                _$setProp(_el$92, "onMouseUp", () => {
                                  if (entry.sessionId) {
                                    props.api.route.navigate("session", {
                                      sessionID: entry.sessionId
                                    });
                                  }
                                });
                                _$insert(_el$93, openPrefix);
                                _$insert(_el$94, () => t("open.label"));
                                _$effect((_p$) => {
                                  var _v$32 = {
                                    fg: hoveredOpen() === entry.id ? pal().warning : pal().primary
                                  }, _v$33 = {
                                    fg: hoveredOpen() === entry.id ? pal().warning : pal().primary
                                  };
                                  _v$32 !== _p$.e && (_p$.e = _$setProp(_el$93, "style", _v$32, _p$.e));
                                  _v$33 !== _p$.t && (_p$.t = _$setProp(_el$94, "style", _v$33, _p$.t));
                                  return _p$;
                                }, {
                                  e: void 0,
                                  t: void 0
                                });
                                return _el$92;
                              }
                            }), _el$95);
                            _$insert(_el$95, () => " ".repeat(spacerW()));
                            _$insert(_el$91, _$createComponent(Show, {
                              get when() {
                                return isRunning && entry.sessionId;
                              },
                              get children() {
                                var _el$96 = _$createElement("text"), _el$97 = _$createElement("span");
                                _$insertNode(_el$96, _el$97);
                                _$setProp(_el$96, "onMouseOver", () => setHoveredCancel(entry.id));
                                _$setProp(_el$96, "onMouseOut", () => setHoveredCancel(void 0));
                                _$setProp(_el$96, "onMouseUp", () => cancelEntry(entry));
                                _$insert(_el$97, cancelLabel);
                                _$effect((_$p) => _$setProp(_el$97, "style", {
                                  fg: hoveredCancel() === entry.id ? pal().warning : pal().error
                                }, _$p));
                                return _el$96;
                              }
                            }), null);
                            _$insert(_el$91, _$createComponent(Show, {
                              when: isRunning,
                              get children() {
                                var _el$98 = _$createElement("text"), _el$99 = _$createElement("span");
                                _$insertNode(_el$98, _el$99);
                                _$setProp(_el$98, "onMouseOver", () => setHoveredDismiss(entry.id));
                                _$setProp(_el$98, "onMouseOut", () => setHoveredDismiss(void 0));
                                _$setProp(_el$98, "onMouseUp", () => {
                                  upsertEntry({
                                    id: entry.id,
                                    title: entry.title,
                                    agent: entry.agent,
                                    prompt: entry.prompt,
                                    status: "done"
                                  });
                                });
                                _$insert(_el$99, dismissLabel);
                                _$effect((_$p) => _$setProp(_el$99, "style", {
                                  fg: hoveredDismiss() === entry.id ? pal().warning : pal().muted
                                }, _$p));
                                return _el$98;
                              }
                            }), null);
                            _$effect((_$p) => _$setProp(_el$95, "style", {
                              fg: pal().muted
                            }, _$p));
                            return _el$91;
                          })();
                        })();
                      }
                    })];
                  }
                })];
              }
            }), null);
            _$insert(_el$7, _$createComponent(Show, {
              get when() {
                return hiddenBelow() > 0 || (props.sortOrder() === "desc" ? scrollOffset() > 0 : entryList().length > max() && clampedOffset() < entryList().length - max());
              },
              get children() {
                return (() => {
                  const showMore = hiddenBelow() > 0;
                  const showTop = props.sortOrder() === "desc" ? scrollOffset() > 0 : entryList().length > max() && clampedOffset() < entryList().length - max();
                  const left = showMore ? `  \u2193 ${hiddenBelow()} ${t("scroll.more")}` : "  ";
                  const right = props.sortOrder() === "desc" ? `\u2191 ${t("scroll.top")}` : `\u2193 ${t("scroll.bottom")}`;
                  const pad = showTop ? Math.max(1, panelWidth() - visualWidth(left) - visualWidth(right)) : 0;
                  return (() => {
                    var _el$100 = _$createElement("box"), _el$101 = _$createElement("text"), _el$102 = _$createElement("span");
                    _$insertNode(_el$100, _el$101);
                    _$setProp(_el$100, "flexDirection", "row");
                    _$insertNode(_el$101, _el$102);
                    _$setProp(_el$101, "onMouseOver", () => showMore && setHoveredMoreBelow(true));
                    _$setProp(_el$101, "onMouseOut", () => setHoveredMoreBelow(false));
                    _$setProp(_el$101, "onMouseUp", () => {
                      if (!showMore) return;
                      const total = entryList().length;
                      const m = max();
                      if (total <= m) return;
                      setScrollOffset((prev) => Math.min(total - m, prev + m));
                      try {
                        persistScroll(props.sessionId, scrollOffset());
                      } catch {
                      }
                      setHoveredMoreBelow(false);
                    });
                    _$insert(_el$102, left);
                    _$insert(_el$100, showTop ? [(() => {
                      var _el$103 = _$createElement("text");
                      _$insert(_el$103, () => " ".repeat(pad));
                      _$effect((_$p) => _$setProp(_el$103, "style", {
                        fg: pal().muted
                      }, _$p));
                      return _el$103;
                    })(), (() => {
                      var _el$104 = _$createElement("text"), _el$105 = _$createElement("span");
                      _$insertNode(_el$104, _el$105);
                      _$setProp(_el$104, "onMouseOver", () => setHoveredTop(true));
                      _$setProp(_el$104, "onMouseOut", () => setHoveredTop(false));
                      _$setProp(_el$104, "onMouseUp", () => {
                        const total = entryList().length;
                        const m = max();
                        if (props.sortOrder() === "desc") {
                          setScrollOffset(0);
                        } else {
                          setScrollOffset(Math.max(0, total - m));
                        }
                        setHoveredTop(false);
                      });
                      _$insert(_el$105, right);
                      _$effect((_$p) => _$setProp(_el$105, "style", {
                        fg: hoveredTop() ? pal().warning : pal().muted
                      }, _$p));
                      return _el$104;
                    })()] : null, null);
                    _$effect((_$p) => _$setProp(_el$102, "style", {
                      fg: showMore && hoveredMoreBelow() ? pal().warning : pal().muted
                    }, _$p));
                    return _el$100;
                  })();
                })();
              }
            }), null);
            return _el$7;
          }
        })];
      }
    }), null);
    _$effect((_p$) => {
      var _v$ = {
        fg: pal().muted
      }, _v$2 = {
        fg: pal().primary
      };
      _v$ !== _p$.e && (_p$.e = _$setProp(_el$3, "style", _v$, _p$.e));
      _v$2 !== _p$.t && (_p$.t = _$setProp(_el$4, "style", _v$2, _p$.t));
      return _p$;
    }, {
      e: void 0,
      t: void 0
    });
    return _el$;
  })();
}
function createSidebarSlot(api, sig) {
  return {
    order: 60,
    slots: {
      sidebar_content(ctx, input) {
        sig.sessionId = input.session_id;
        return _$createComponent(SubAgentPanel, {
          get theme() {
            return ctx.theme.current;
          },
          api,
          get lang() {
            return sig.lang;
          },
          get maxEntries() {
            return sig.maxEntries;
          },
          get sortOrder() {
            return sig.sortOrder;
          },
          get scrollMode() {
            return sig.scrollMode;
          },
          get sessionId() {
            return input.session_id;
          }
        });
      }
    }
  };
}
var KV_PREFIX = "subagent_magazine";
var tui = async (api) => {
  const stored = String(api.kv.get(`${KV_PREFIX}.lang`, ""));
  const initialLang = LANG_META.some((m) => m.code === stored) ? stored : detectLang();
  const [lang, setLang] = createSignal(initialLang);
  const [maxEntries, setMaxEntries] = createSignal(parseInt(String(api.kv.get(`${KV_PREFIX}.max_entries`, "10")), 10) || 10);
  const [sortOrder, setSortOrder] = createSignal(String(api.kv.get(`${KV_PREFIX}.order`, "desc")) === "asc" ? "asc" : "desc");
  const [scrollMode, setScrollMode] = createSignal(String(api.kv.get(`${KV_PREFIX}.scroll_mode`, "wheel")) === "click" ? "click" : "wheel");
  const signals = {
    lang,
    setLang,
    maxEntries,
    setMaxEntries,
    sortOrder,
    setSortOrder,
    scrollMode,
    setScrollMode,
    sessionId: ""
  };
  api.slots.register(createSidebarSlot(api, signals));
  api.command?.register(() => [{
    title: "SubAgent Magazine: Language",
    value: "subagent-lang",
    description: "Switch display language (\u4E2D\u6587 / English)",
    slash: {
      name: "subagent-lang"
    },
    onSelect: (dialog) => {
      dialog?.replace(() => _$createComponent(api.ui.DialogSelect, {
        title: "Language / \u8BED\u8A00",
        get options() {
          return LANG_META.map((m) => ({
            title: m.label,
            value: m.code
          }));
        },
        onSelect: (opt) => {
          const l = opt.value;
          setLang(l);
          api.kv.set(`${KV_PREFIX}.lang`, l);
          api.ui.toast({
            message: "Language: " + (LANG_META.find((m) => m.code === l)?.label ?? l)
          });
          dialog?.clear();
        }
      }));
    }
  }, {
    title: "SubAgent Magazine: Sort Order",
    value: "subagent-order",
    description: "Set sub-agent entry sort order (desc / asc)",
    slash: {
      name: "subagent-order"
    },
    onSelect: (dialog) => {
      const t = createT(() => lang());
      dialog?.replace(() => _$createComponent(api.ui.DialogSelect, {
        title: "Sort Order / \u6392\u5E8F\u65B9\u5F0F",
        get options() {
          return [{
            title: t("order.desc"),
            value: "desc"
          }, {
            title: t("order.asc"),
            value: "asc"
          }];
        },
        onSelect: (opt) => {
          const o = opt.value;
          setSortOrder(o);
          api.kv.set(`${KV_PREFIX}.order`, o);
          api.ui.toast({
            message: o === "desc" ? t("order.desc") : t("order.asc")
          });
          dialog?.clear();
        }
      }));
    }
  }, {
    title: "SubAgent Magazine: Scroll Mode",
    value: "subagent-scroll",
    description: "Set scroll mode (wheel / click)",
    slash: {
      name: "subagent-scroll"
    },
    onSelect: (dialog) => {
      const t = createT(() => lang());
      dialog?.replace(() => _$createComponent(api.ui.DialogSelect, {
        title: "Scroll Mode / \u6EDA\u52A8\u6A21\u5F0F",
        get options() {
          return [{
            title: t("scroll.wheel"),
            value: "wheel"
          }, {
            title: t("scroll.click"),
            value: "click"
          }];
        },
        onSelect: (opt) => {
          const m = opt.value;
          setScrollMode(m);
          api.kv.set(`${KV_PREFIX}.scroll_mode`, m);
          api.ui.toast({
            message: m === "wheel" ? t("scroll.wheel") : t("scroll.click")
          });
          dialog?.clear();
        }
      }));
    }
  }, {
    title: "SubAgent Magazine: Max Entries",
    value: "subagent-max",
    description: "Set max visible sub-agent entries in sidebar",
    slash: {
      name: "subagent-max"
    },
    onSelect: (dialog) => {
      dialog?.replace(() => _$createComponent(api.ui.DialogPrompt, {
        title: "Max Visible Entries",
        description: () => (() => {
          var _el$106 = _$createElement("text");
          _$insertNode(_el$106, _$createTextNode(`Number of entries to show in the sidebar (1\u201350)`));
          return _el$106;
        })(),
        get value() {
          return String(maxEntries());
        },
        onConfirm: (val) => {
          const n = Math.max(1, Math.min(50, parseInt(val, 10) || 10));
          setMaxEntries(n);
          api.kv.set(`${KV_PREFIX}.max_entries`, n);
          api.ui.toast({
            message: `Max entries: ${n}`
          });
          dialog?.clear();
        }
      }));
    }
  }, {
    title: "SubAgent Magazine: Version",
    value: "subagent-version",
    description: "Show plugin version",
    slash: {
      name: "subagent-version"
    },
    onSelect: (dialog) => {
      api.ui.toast({
        message: `opencode-subagent-magazine v${PLUGIN_VERSION}`
      });
      dialog?.clear();
    }
  }, {
    title: "SubAgent Magazine: Session",
    value: "subagent-session",
    description: "Show current session ID",
    slash: {
      name: "subagent-session"
    },
    onSelect: (dialog) => {
      api.ui.toast({
        message: `Session: ${signals.sessionId}`
      });
      dialog?.clear();
    }
  }, {
    title: "SubAgent Magazine: Clear Running",
    value: "subagent-clear-running",
    description: "Mark all running sub-agent entries as done (for stuck/zombie entries)",
    slash: {
      name: "subagent-clear-running"
    },
    onSelect: (dialog) => {
      const sid = signals.sessionId;
      const entries = globalEntryCache.get(sid);
      if (!entries || entries.size === 0) {
        const msg = signals.lang() === "zh" ? "\u6682\u65E0\u5B50\u4EE3\u7406\u6761\u76EE" : "No sub-agent entries found";
        api.ui.toast({
          message: msg
        });
        dialog?.clear();
        return;
      }
      let count = 0;
      for (const [, entry] of entries) {
        if (entry.status === "running" || entry.status === "cancel_requested") {
          entry.status = "done";
          entry.endedAt = Date.now();
          count++;
        }
      }
      if (count > 0) {
        try {
          const data = JSON.parse(String(api.kv.get(`${KV_PREFIX}.session_data`, "{}")));
          const sessionObj = api.state.session.get(sid);
          const parentID = sessionObj?.parentID;
          if (parentID) {
            if (!data[parentID]) data[parentID] = {
              ts: Date.now(),
              entries: [],
              scroll: 0,
              expanded: "",
              children: {}
            };
            if (!data[parentID].children) data[parentID].children = {};
            if (!data[parentID].children[sid]) data[parentID].children[sid] = {
              scroll: 0,
              expanded: "",
              entries: []
            };
            data[parentID].children[sid] = {
              ...data[parentID].children[sid],
              entries: [...entries.values()]
            };
          } else {
            data[sid] = {
              ts: Date.now(),
              entries: [...entries.values()],
              scroll: data[sid]?.scroll ?? 0,
              expanded: data[sid]?.expanded ?? "",
              children: data[sid]?.children ?? {}
            };
          }
          api.kv.set(`${KV_PREFIX}.session_data`, JSON.stringify(data));
        } catch {
        }
        const msg = signals.lang() === "zh" ? `\u5DF2\u6807\u8BB0 ${count} \u4E2A\u8FD0\u884C\u4E2D\u7684\u6761\u76EE\u4E3A\u5B8C\u6210` : `Marked ${count} running entries as done`;
        api.ui.toast({
          message: msg
        });
      } else {
        const msg = signals.lang() === "zh" ? "\u6CA1\u6709\u9700\u8981\u6E05\u7406\u7684\u8FD0\u884C\u4E2D\u6761\u76EE" : "No running entries to clear";
        api.ui.toast({
          message: msg
        });
      }
      dialog?.clear();
    }
  }, {
    title: "SubAgent Magazine: TTL",
    value: "subagent-ttl",
    description: "Set session data retention period (days before auto-cleanup)",
    slash: {
      name: "subagent-ttl"
    },
    onSelect: (dialog) => {
      const t = createT(() => signals.lang());
      const curRaw = parseInt(String(api.kv.get(`${KV_PREFIX}.ttl_days`, "3")), 10);
      const curDays = Number.isNaN(curRaw) ? 3 : curRaw;
      const curLabel = curDays === 0 ? t("ttl.unlimited") : `${curDays}d`;
      dialog?.replace(() => _$createComponent(api.ui.DialogSelect, {
        get title() {
          return `${t("ttl.label")}  (${curLabel})`;
        },
        get options() {
          return [{
            title: t("ttl.3d"),
            value: "3"
          }, {
            title: t("ttl.7d"),
            value: "7"
          }, {
            title: t("ttl.14d"),
            value: "14"
          }, {
            title: t("ttl.30d"),
            value: "30"
          }, {
            title: t("ttl.unlimited"),
            value: "0"
          }];
        },
        onSelect: (opt) => {
          const days = parseInt(opt.value, 10);
          api.kv.set(`${KV_PREFIX}.ttl_days`, String(days));
          const msg = days === 0 ? t("ttl.toast_unlimited") : t("ttl.toast", {
            n: days
          });
          api.ui.toast({
            message: msg
          });
          dialog?.clear();
        }
      }));
    }
  }, {
    title: "SubAgent Magazine: Clear Entries",
    value: "subagent-clear-entries",
    description: "Delete all sub-agent records for the current session (cannot be undone)",
    slash: {
      name: "subagent-clear-entries"
    },
    onSelect: (dialog) => {
      const t = createT(() => signals.lang());
      const sid = signals.sessionId;
      const sessionObj = api.state.session.get(sid);
      const parentID = sessionObj?.parentID;
      const cached = globalEntryCache.get(sid);
      let runningCount = 0;
      if (cached) {
        for (const [, e] of cached) {
          if (e.status === "running") runningCount++;
        }
      }
      const msg = runningCount > 0 ? t("clear.prompt_running", {
        n: runningCount
      }) : t("clear.prompt");
      dialog?.replace(() => _$createComponent(api.ui.DialogConfirm, {
        get title() {
          return t("clear.title");
        },
        message: msg,
        onConfirm: () => {
          try {
            const data = JSON.parse(String(api.kv.get(`${KV_PREFIX}.session_data`, "{}")));
            let count = 0;
            if (parentID) {
              if (data[parentID]?.children?.[sid]) {
                const child = data[parentID].children[sid];
                const ids = child.entries?.map((e) => e.id) ?? [];
                count = ids.length;
                child.entries = [];
                child.scroll = 0;
                child.expanded = "";
                child.clearedIds = [.../* @__PURE__ */ new Set([...child.clearedIds ?? [], ...ids])];
              }
            } else {
              count = data[sid]?.entries?.length ?? 0;
              if (data[sid]) {
                const ids = data[sid].entries?.map((e) => e.id) ?? [];
                data[sid].entries = [];
                data[sid].scroll = 0;
                data[sid].expanded = "";
                data[sid].clearedIds = [.../* @__PURE__ */ new Set([...data[sid].clearedIds ?? [], ...ids])];
              }
            }
            api.kv.set(`${KV_PREFIX}.session_data`, JSON.stringify(data));
            globalEntryCache.delete(sid);
            setClearTick((v) => v + 1);
            const msg2 = t("clear.done", {
              n: count
            });
            api.ui.toast({
              message: msg2
            });
          } catch {
          }
          dialog?.clear();
        }
      }));
    }
  }]);
};
var mod = {
  id: "opencode-subagent-magazine",
  tui
};
var index_default = mod;
export {
  index_default as default
};
