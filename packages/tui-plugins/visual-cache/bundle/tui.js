// src/index.tsx
import { createComponent as _$createComponent } from "@opentui/solid";
import { effect as _$effect } from "@opentui/solid";
import { createTextNode as _$createTextNode } from "@opentui/solid";
import { insertNode as _$insertNode } from "@opentui/solid";
import { insert as _$insert } from "@opentui/solid";
import { setProp as _$setProp } from "@opentui/solid";
import { use as _$use } from "@opentui/solid";
import { spread as _$spread } from "@opentui/solid";
import { mergeProps as _$mergeProps } from "@opentui/solid";
import { memo as _$memo } from "@opentui/solid";
import { createElement as _$createElement } from "@opentui/solid";
import { createMemo, createSignal, createEffect, onMount, onCleanup, Show, For, untrack } from "solid-js";

// src/_version.ts
var PLUGIN_VERSION = "1.6.2";

// src/balance-providers.ts
var BalanceError = class extends Error {
};
var siliconflowProvider = {
  id: "siliconflow",
  name: "SiliconFlow",
  keyPlaceholder: "sk-...",
  async fetchBalance(apiKey, signal) {
    const res = await fetch("https://api.siliconflow.cn/v1/user/info", {
      headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" },
      signal
    });
    if (!res.ok) {
      if (res.status === 401) throw new BalanceError("401");
      if (res.status === 403) throw new BalanceError("403");
      throw new BalanceError(String(res.status));
    }
    const json = await res.json();
    const total = json.data?.totalBalance ?? json.data?.balance;
    if (typeof total === "undefined" || total === null) throw new BalanceError("EMPTY");
    return [{ currency: "CNY", total: String(total) }];
  }
};
var deepseekProvider = {
  id: "deepseek",
  name: "DeepSeek",
  keyPlaceholder: "sk-...",
  async fetchBalance(apiKey, signal) {
    const res = await fetch("https://api.deepseek.com/user/balance", {
      headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" },
      signal
    });
    if (!res.ok) {
      if (res.status === 401) throw new BalanceError("401");
      if (res.status === 402 || res.status === 403) throw new BalanceError("403");
      throw new BalanceError(String(res.status));
    }
    const json = await res.json();
    const infos = json.balance_infos ?? [];
    if (infos.length === 0) throw new BalanceError("EMPTY");
    return infos.map((info) => ({
      currency: info.currency ?? "CNY",
      total: info.total_balance ?? "0"
    }));
  }
};
var openrouterProvider = {
  id: "openrouter",
  name: "OpenRouter",
  keyPlaceholder: "sk-or-...",
  async fetchBalance(apiKey, signal) {
    const res = await fetch("https://openrouter.ai/api/v1/credits", {
      headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" },
      signal
    });
    if (!res.ok) {
      if (res.status === 401 || res.status === 403) throw new BalanceError("403");
      throw new BalanceError(String(res.status));
    }
    const json = await res.json();
    const credits = json.data?.total_credits;
    const usage = json.data?.total_usage;
    if (typeof credits !== "number" || typeof usage !== "number") throw new BalanceError("EMPTY");
    return [{ currency: "USD", total: (credits - usage).toFixed(2) }];
  }
};
var moonshotProvider = {
  id: "moonshot",
  name: "Moonshot",
  keyPlaceholder: "sk-...",
  async fetchBalance(apiKey, signal) {
    const res = await fetch("https://api.moonshot.cn/v1/users/me/balance", {
      headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" },
      signal
    });
    if (!res.ok) {
      if (res.status === 401) throw new BalanceError("401");
      if (res.status === 403) throw new BalanceError("403");
      throw new BalanceError(String(res.status));
    }
    const json = await res.json();
    const balance = json.data?.available_balance;
    if (typeof balance === "undefined" || balance === null) throw new BalanceError("EMPTY");
    return [{ currency: "CNY", total: String(balance) }];
  }
};
var balanceProviders = [deepseekProvider, siliconflowProvider, openrouterProvider, moonshotProvider];
function getBalanceProvider(id) {
  return balanceProviders.find((p) => p.id === id) ?? balanceProviders[0] ?? deepseekProvider;
}
function matchBalanceProvider(providerId) {
  const id = providerId.toLowerCase();
  const exact = balanceProviders.find((p) => p.id.toLowerCase() === id);
  if (exact) return exact;
  return balanceProviders.find((p) => id.startsWith(p.id.toLowerCase()));
}
function maskKey(k) {
  if (!k) return "";
  if (k.length <= 10) return k.slice(0, 5) + "*".repeat(Math.max(3, k.length - 5));
  return k.slice(0, 5) + "*".repeat(Math.max(3, k.length - 10)) + k.slice(-5);
}

// src/i18n.ts
var ZH_T = {
  title: "\u7F13\u5B58\u7EDF\u8BA1",
  hit: "\u547D\u4E2D\u7387",
  totalHit: "\u603B\u547D\u4E2D:",
  read: "\u7F13\u5B58\u8BFB:",
  write: "\u7F13\u5B58\u5199:",
  miss: "\u672A\u547D\u4E2D:",
  out: "\u8F93\u51FA:",
  cost: "\u8D39\u7528:",
  saved: "\u7D2F\u8BA1\u8282\u7701:",
  model: "\u6A21\u578B:",
  provider: "\u63D0\u4F9B\u5546:",
  rate: "\u5355\u4EF7:",
  hitFolded: "\u547D\u4E2D",
  inputRate: "\u8F93\u5165",
  cacheRate: "\u7F13\u5B58",
  writeRate: "\u5199\u5165",
  noData: "\u7B49\u5F85\u7F13\u5B58\u6570\u636E...",
  tok: "tok",
  distTitle: "\u4F30\u7B97 Token \u5206\u5E03",
  distSys: "\u7CFB\u7EDF\u63D0\u793A:",
  distUser: "\u7528\u6237:",
  distAgent: "\u5B50\u4EE3\u7406\u6307\u4EE4:",
  distTool: "Tool \u8C03\u7528:",
  distRes: "Tool \u7ED3\u679C:",
  distReason: "\u63A8\u7406:",
  stepsCount: "\u672C\u56DE\u5408 {n} \u6B21\u8C03\u7528:",
  secDetail: "\u660E\u7EC6",
  secModel: "\u6A21\u578B",
  secSkills: "\u5DF2\u52A0\u8F7D\u6280\u80FD",
  balTotal: "\u603B\u4F59\u989D:",
  balNoKey: "\u672A\u914D\u7F6E {p} API Key",
  balLoading: "\u67E5\u8BE2\u4E2D...",
  balError: "\u67E5\u8BE2\u5931\u8D25",
  balErr401: "API Key \u65E0\u6548",
  balErr403: "\u4F59\u989D\u67E5\u8BE2\u88AB\u62D2\u7EDD",
  balErrEmpty: "\u672A\u83B7\u53D6\u5230\u4F59\u989D\u6570\u636E",
  balErrTimeout: "\u67E5\u8BE2\u8D85\u65F6",
  balUnsupported: "\u5F53\u524D\u63D0\u4F9B\u5546\u4E0D\u652F\u6301\u4F59\u989D\u67E5\u8BE2",
  barHit: "\u547D\u4E2D\u7387",
  barBal: "\u4F59\u989D",
  barTok: "Tokens",
  // ── /cache-section 面板 ──
  secToggle: "\u5207\u6362\u533A\u5757",
  secBalance: "\u4F59\u989D",
  secBottom: "\u5E95\u90E8\u72B6\u6001\u680F",
  secBorder: "\u9762\u677F\u8FB9\u6846",
  // ── toast ──
  keySaved: "API Key \u5DF2\u4FDD\u5B58\uFF0C\u6B63\u5728\u67E5\u8BE2\u4F59\u989D...",
  keyCleared: "API Key \u5DF2\u6E05\u9664",
  currencySet: "\u5E01\u79CD: {v} ({s}), \u6C47\u7387: {r}",
  rateSet: "\u6C47\u7387\u5DF2\u8BBE\u4E3A {r}",
  panelConfigTitle: "\u7F13\u5B58\u9762\u677F\u914D\u7F6E",
  panelConfigMsg: "\u5E01\u79CD: {c} | \u6C47\u7387: {r} | \u660E\u7EC6: {d} | \u6A21\u578B: {m} | \u5206\u5E03: {t} | \u6280\u80FD: {k} | \u4F59\u989D: {b} | \u5E95\u90E8: {f}",
  borderShown: "\u9762\u677F\u8FB9\u6846 \u5DF2\u663E\u793A",
  borderHidden: "\u9762\u677F\u8FB9\u6846 \u5DF2\u9690\u85CF",
  sectionShown: "{s} \u5DF2\u663E\u793A",
  sectionHidden: "{s} \u5DF2\u9690\u85CF",
  langSwitched: "\u8BED\u8A00\u5DF2\u5207\u6362\u4E3A\u4E2D\u6587",
  autoSwitchOn: "\u81EA\u52A8\u5207\u6362\u4F59\u989D\u63D0\u4F9B\u5546: \u5F00",
  autoSwitchOff: "\u81EA\u52A8\u5207\u6362\u4F59\u989D\u63D0\u4F9B\u5546: \u5173",
  providerManual: "\u4F59\u989D\u63D0\u4F9B\u5546: {p}\uFF08\u81EA\u52A8\u5207\u6362\u5DF2\u5173\u95ED\uFF09",
  runInSession: "\u8BF7\u5728\u4F1A\u8BDD\u5185\u8FD0\u884C\u6B64\u547D\u4EE4",
  backToMain: "\u5DF2\u5207\u56DE\u4E3B\u4F1A\u8BDD",
  subAgentSwitched: "\u5DF2\u5207\u6362\u81F3\u5B50\u4EE3\u7406: {s}",
  // ── 对话框 / 菜单 ──
  langTitle: "\u663E\u793A\u8BED\u8A00",
  subPrefix: "\u5B50\u4EE3\u7406: ",
  keyUser: "\uFF08\u7528\u6237 key\uFF09",
  keyOpenCode: "\uFF08OpenCode\uFF09",
  keyNotSet: "\uFF08\u672A\u914D\u7F6E\uFF09",
  balKeyPrompt: "\u8F93\u5165 {p} API Key \u4EE5\u663E\u793A\u8D26\u6237\u4F59\u989D\uFF08\u7559\u7A7A\u6E05\u9664\uFF09",
  balProvTitle: "\u4F59\u989D\u63D0\u4F9B\u5546 / \u81EA\u52A8\u5207\u6362",
  autoSwitchOpt: "\u81EA\u52A8\u5207\u6362\u63D0\u4F9B\u5546",
  balSelectTitle: "\u9009\u62E9\u4F59\u989D\u63D0\u4F9B\u5546",
  backToMainTitle: "\u56DE\u5230\u4E3B\u4F1A\u8BDD",
  subSelectTitle: "\u9009\u62E9\u5B50\u4EE3\u7406",
  subSwitchTitle: "\u5207\u6362\u5B50\u4EE3\u7406",
  subViewTitle: "\u67E5\u770B\u5B50\u4EE3\u7406\u7F13\u5B58",
  subNoFound: "\u672A\u627E\u5230\u5B50\u4EE3\u7406\uFF0C\u8BF7\u624B\u52A8\u7C98\u8D34 Session ID"
};
var EN_T = {
  title: "Token Cache",
  hit: "Hit",
  totalHit: "Total Hit:",
  read: "Read:",
  write: "Write:",
  miss: "Miss:",
  out: "Out:",
  cost: "Cost:",
  saved: "Total Saved:",
  model: "Model:",
  provider: "Provider:",
  rate: "Rate:",
  hitFolded: "hit",
  inputRate: "in",
  cacheRate: "cache",
  writeRate: "write",
  noData: "Waiting for cache data...",
  tok: "tok",
  distTitle: "Estimated Token Dist.",
  distSys: "System:",
  distUser: "User:",
  distAgent: "Sub-Agent Instr:",
  distTool: "Tool Call:",
  distRes: "Tool Result:",
  distReason: "Reasoning:",
  stepsCount: "Turn #{n} calls:",
  secDetail: "Detail",
  secModel: "Model",
  secSkills: "Loaded Skills",
  balTotal: "Total:",
  balNoKey: "{p} API Key not set",
  balLoading: "Fetching...",
  balError: "Fetch failed",
  balErr401: "Invalid API Key",
  balErr403: "Balance request rejected",
  balErrEmpty: "No balance data",
  balErrTimeout: "Request timed out",
  balUnsupported: "Balance query unsupported",
  barHit: "Hit",
  barBal: "Balance",
  barTok: "Tokens",
  // ── /cache-section panel ──
  secToggle: "Toggle Section",
  secBalance: "Balance",
  secBottom: "Bottom Bar",
  secBorder: "Panel Border",
  // ── toasts ──
  keySaved: "API Key saved, fetching balance...",
  keyCleared: "API Key cleared",
  currencySet: "Currency: {v} ({s}), rate: {r}",
  rateSet: "Exchange rate set to {r}",
  panelConfigTitle: "Cache Panel Config",
  panelConfigMsg: "Currency: {c} | Rate: {r} | Detail: {d} | Model: {m} | Dist: {t} | Skills: {k} | Balance: {b} | Bottom: {f}",
  borderShown: "Panel border shown",
  borderHidden: "Panel border hidden",
  sectionShown: "{s} section shown",
  sectionHidden: "{s} section hidden",
  langSwitched: "Switched to English",
  autoSwitchOn: "Auto-switch balance provider: ON",
  autoSwitchOff: "Auto-switch balance provider: OFF",
  providerManual: "Balance provider: {p} (auto-switch off)",
  runInSession: "Please run this command inside a session",
  backToMain: "Switched to main session",
  subAgentSwitched: "Showing sub-agent: {s}",
  // ── dialogs / menus ──
  langTitle: "Display Language",
  subPrefix: "Sub: ",
  keyUser: " (user key)",
  keyOpenCode: " (OpenCode)",
  keyNotSet: " (not set)",
  balKeyPrompt: "Enter your {p} API key to show account balance (leave empty to clear)",
  balProvTitle: "Balance Provider / Auto-switch",
  autoSwitchOpt: "Auto-switch provider",
  balSelectTitle: "Select Balance Provider",
  backToMainTitle: "Back to Main",
  subSelectTitle: "Select Sub-Agent",
  subSwitchTitle: "Switch Sub",
  subViewTitle: "View Sub Cache",
  subNoFound: "No sub-agents found. Paste a Session ID manually"
};
var JA_T = {
  title: "\u30AD\u30E3\u30C3\u30B7\u30E5\u7D71\u8A08",
  hit: "\u30D2\u30C3\u30C8\u7387",
  totalHit: "\u7DCF\u30D2\u30C3\u30C8:",
  read: "\u30AD\u30E3\u30C3\u30B7\u30E5\u8AAD\u8FBC:",
  write: "\u30AD\u30E3\u30C3\u30B7\u30E5\u66F8\u8FBC:",
  miss: "\u672A\u30D2\u30C3\u30C8:",
  out: "\u51FA\u529B:",
  cost: "\u8CBB\u7528:",
  saved: "\u7D2F\u8A08\u7BC0\u7D04:",
  model: "\u30E2\u30C7\u30EB:",
  provider: "\u30D7\u30ED\u30D0\u30A4\u30C0:",
  rate: "\u5358\u4FA1:",
  hitFolded: "\u30D2\u30C3\u30C8",
  inputRate: "\u5165\u529B",
  cacheRate: "\u30AD\u30E3\u30C3\u30B7\u30E5",
  writeRate: "\u66F8\u8FBC",
  noData: "\u30AD\u30E3\u30C3\u30B7\u30E5\u30C7\u30FC\u30BF\u5F85\u6A5F\u4E2D...",
  tok: "tok",
  distTitle: "Token \u5206\u5E03\uFF08\u63A8\u5B9A\uFF09",
  distSys: "\u30B7\u30B9\u30C6\u30E0:",
  distUser: "\u30E6\u30FC\u30B6\u30FC:",
  distAgent: "\u30B5\u30D6\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8\u6307\u793A:",
  distTool: "Tool \u547C\u3073\u51FA\u3057:",
  distRes: "Tool \u7D50\u679C:",
  distReason: "\u63A8\u8AD6:",
  stepsCount: "\u4ECA\u56DE {n} \u56DE\u547C\u51FA:",
  secDetail: "\u660E\u7D30",
  secModel: "\u30E2\u30C7\u30EB",
  secSkills: "\u8AAD\u307F\u8FBC\u307F\u6E08\u307F\u30B9\u30AD\u30EB",
  balTotal: "\u7DCF\u6B8B\u9AD8:",
  balNoKey: "{p} \u306E API Key \u672A\u8A2D\u5B9A",
  balLoading: "\u53D6\u5F97\u4E2D...",
  balError: "\u53D6\u5F97\u5931\u6557",
  balErr401: "API Key \u7121\u52B9",
  balErr403: "\u6B8B\u9AD8\u7167\u4F1A\u304C\u62D2\u5426\u3055\u308C\u307E\u3057\u305F",
  balErrEmpty: "\u6B8B\u9AD8\u30C7\u30FC\u30BF\u306A\u3057",
  balErrTimeout: "\u30BF\u30A4\u30E0\u30A2\u30A6\u30C8",
  balUnsupported: "\u3053\u306E\u30D7\u30ED\u30D0\u30A4\u30C0\u306F\u6B8B\u9AD8\u7167\u4F1A\u975E\u5BFE\u5FDC",
  barHit: "\u30D2\u30C3\u30C8\u7387",
  barBal: "\u6B8B\u9AD8",
  barTok: "Tokens",
  // ── /cache-section パネル ──
  secToggle: "\u30BB\u30AF\u30B7\u30E7\u30F3\u5207\u66FF",
  secBalance: "\u6B8B\u9AD8",
  secBottom: "\u4E0B\u90E8\u30B9\u30C6\u30FC\u30BF\u30B9\u30D0\u30FC",
  secBorder: "\u30D1\u30CD\u30EB\u67A0\u7DDA",
  // ── toast ──
  keySaved: "API Key \u4FDD\u5B58\u6E08\u307F\u3001\u6B8B\u9AD8\u3092\u53D6\u5F97\u4E2D...",
  keyCleared: "API Key \u3092\u30AF\u30EA\u30A2\u3057\u307E\u3057\u305F",
  currencySet: "\u901A\u8CA8: {v} ({s}), \u30EC\u30FC\u30C8: {r}",
  rateSet: "\u30EC\u30FC\u30C8\u3092 {r} \u306B\u8A2D\u5B9A\u3057\u307E\u3057\u305F",
  panelConfigTitle: "\u30D1\u30CD\u30EB\u8A2D\u5B9A",
  panelConfigMsg: "\u901A\u8CA8: {c} | \u30EC\u30FC\u30C8: {r} | \u660E\u7D30: {d} | \u30E2\u30C7\u30EB: {m} | \u5206\u5E03: {t} | \u30B9\u30AD\u30EB: {k} | \u6B8B\u9AD8: {b} | \u4E0B\u90E8: {f}",
  borderShown: "\u30D1\u30CD\u30EB\u67A0\u7DDA \u8868\u793A",
  borderHidden: "\u30D1\u30CD\u30EB\u67A0\u7DDA \u975E\u8868\u793A",
  sectionShown: "{s} \u8868\u793A",
  sectionHidden: "{s} \u975E\u8868\u793A",
  langSwitched: "\u65E5\u672C\u8A9E\u306B\u5207\u308A\u66FF\u3048\u307E\u3057\u305F",
  autoSwitchOn: "\u6B8B\u9AD8\u30D7\u30ED\u30D0\u30A4\u30C0\u81EA\u52D5\u5207\u66FF: \u30AA\u30F3",
  autoSwitchOff: "\u6B8B\u9AD8\u30D7\u30ED\u30D0\u30A4\u30C0\u81EA\u52D5\u5207\u66FF: \u30AA\u30D5",
  providerManual: "\u6B8B\u9AD8\u30D7\u30ED\u30D0\u30A4\u30C0: {p}\uFF08\u81EA\u52D5\u5207\u66FF\u30AA\u30D5\uFF09",
  runInSession: "\u30BB\u30C3\u30B7\u30E7\u30F3\u5185\u3067\u5B9F\u884C\u3057\u3066\u304F\u3060\u3055\u3044",
  backToMain: "\u30E1\u30A4\u30F3\u30BB\u30C3\u30B7\u30E7\u30F3\u306B\u623B\u308A\u307E\u3057\u305F",
  subAgentSwitched: "\u30B5\u30D6\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8\u3078\u5207\u66FF: {s}",
  // ── ダイアログ / メニュー ──
  langTitle: "\u8868\u793A\u8A00\u8A9E",
  subPrefix: "\u30B5\u30D6: ",
  keyUser: "\uFF08\u30E6\u30FC\u30B6\u30FC key\uFF09",
  keyOpenCode: "\uFF08OpenCode\uFF09",
  keyNotSet: "\uFF08\u672A\u8A2D\u5B9A\uFF09",
  balKeyPrompt: "{p} \u306E API Key \u3092\u5165\u529B\u3057\u3066\u6B8B\u9AD8\u3092\u8868\u793A\uFF08\u7A7A\u6B04\u3067\u30AF\u30EA\u30A2\uFF09",
  balProvTitle: "\u6B8B\u9AD8\u30D7\u30ED\u30D0\u30A4\u30C0 / \u81EA\u52D5\u5207\u66FF",
  autoSwitchOpt: "\u81EA\u52D5\u5207\u66FF\u30D7\u30ED\u30D0\u30A4\u30C0",
  balSelectTitle: "\u6B8B\u9AD8\u30D7\u30ED\u30D0\u30A4\u30C0\u9078\u629E",
  backToMainTitle: "\u30E1\u30A4\u30F3\u306B\u623B\u308B",
  subSelectTitle: "\u30B5\u30D6\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8\u9078\u629E",
  subSwitchTitle: "\u30B5\u30D6\u5207\u66FF",
  subViewTitle: "\u30B5\u30D6\u30AD\u30E3\u30C3\u30B7\u30E5\u8868\u793A",
  subNoFound: "\u30B5\u30D6\u30A8\u30FC\u30B8\u30A7\u30F3\u30C8\u304C\u898B\u3064\u304B\u308A\u307E\u305B\u3093\u3002Session ID \u3092\u624B\u52D5\u3067\u8CBC\u308A\u4ED8\u3051\u3066\u304F\u3060\u3055\u3044"
};
var KO_T = {
  title: "\uCE90\uC2DC \uD1B5\uACC4",
  hit: "\uD788\uD2B8\uC728",
  totalHit: "\uCD1D \uD788\uD2B8:",
  read: "\uCE90\uC2DC \uC77D\uAE30:",
  write: "\uCE90\uC2DC \uC4F0\uAE30:",
  miss: "\uBBF8\uD788\uD2B8:",
  out: "\uCD9C\uB825:",
  cost: "\uBE44\uC6A9:",
  saved: "\uB204\uC801 \uC808\uC57D:",
  model: "\uBAA8\uB378:",
  provider: "\uD504\uB85C\uBC14\uC774\uB354:",
  rate: "\uB2E8\uAC00:",
  hitFolded: "\uD788\uD2B8",
  inputRate: "\uC785\uB825",
  cacheRate: "\uCE90\uC2DC",
  writeRate: "\uC4F0\uAE30",
  noData: "\uCE90\uC2DC \uB370\uC774\uD130 \uB300\uAE30 \uC911...",
  tok: "tok",
  distTitle: "Token \uBD84\uD3EC(\uCD94\uC815)",
  distSys: "\uC2DC\uC2A4\uD15C:",
  distUser: "\uC0AC\uC6A9\uC790:",
  distAgent: "\uC11C\uBE0C \uC5D0\uC774\uC804\uD2B8 \uC9C0\uC2DC:",
  distTool: "Tool \uD638\uCD9C:",
  distRes: "Tool \uACB0\uACFC:",
  distReason: "\uCD94\uB860:",
  stepsCount: "\uC774\uBC88 \uD134 {n}\uD68C \uD638\uCD9C:",
  secDetail: "\uC0C1\uC138",
  secModel: "\uBAA8\uB378",
  secSkills: "\uB85C\uB4DC\uB41C \uC2A4\uD0AC",
  balTotal: "\uCD1D \uC794\uC561:",
  balNoKey: "{p} API Key \uBBF8\uC124\uC815",
  balLoading: "\uC870\uD68C \uC911...",
  balError: "\uC870\uD68C \uC2E4\uD328",
  balErr401: "API Key \uBB34\uD6A8",
  balErr403: "\uC794\uC561 \uC870\uD68C\uAC00 \uAC70\uBD80\uB418\uC5C8\uC2B5\uB2C8\uB2E4",
  balErrEmpty: "\uC794\uC561 \uB370\uC774\uD130 \uC5C6\uC74C",
  balErrTimeout: "\uC2DC\uAC04 \uCD08\uACFC",
  balUnsupported: "\uC774 \uD504\uB85C\uBC14\uC774\uB354\uB294 \uC794\uC561 \uC870\uD68C \uBBF8\uC9C0\uC6D0",
  barHit: "\uD788\uD2B8\uC728",
  barBal: "\uC794\uC561",
  barTok: "Tokens",
  // ── /cache-section 패널 ──
  secToggle: "\uC139\uC158 \uC804\uD658",
  secBalance: "\uC794\uC561",
  secBottom: "\uD558\uB2E8 \uC0C1\uD0DC\uBC14",
  secBorder: "\uD328\uB110 \uD14C\uB450\uB9AC",
  // ── toast ──
  keySaved: "API Key \uC800\uC7A5\uB428, \uC794\uC561 \uC870\uD68C \uC911...",
  keyCleared: "API Key \uC0AD\uC81C\uB428",
  currencySet: "\uD1B5\uD654: {v} ({s}), \uD658\uC728: {r}",
  rateSet: "\uD658\uC728\uC744 {r}(\uC73C)\uB85C \uC124\uC815\uD588\uC2B5\uB2C8\uB2E4",
  panelConfigTitle: "\uD328\uB110 \uC124\uC815",
  panelConfigMsg: "\uD1B5\uD654: {c} | \uD658\uC728: {r} | \uC0C1\uC138: {d} | \uBAA8\uB378: {m} | \uBD84\uD3EC: {t} | \uC2A4\uD0AC: {k} | \uC794\uC561: {b} | \uD558\uB2E8: {f}",
  borderShown: "\uD328\uB110 \uD14C\uB450\uB9AC \uD45C\uC2DC",
  borderHidden: "\uD328\uB110 \uD14C\uB450\uB9AC \uC228\uAE40",
  sectionShown: "{s} \uD45C\uC2DC",
  sectionHidden: "{s} \uC228\uAE40",
  langSwitched: "\uD55C\uAD6D\uC5B4\uB85C \uC804\uD658\uD588\uC2B5\uB2C8\uB2E4",
  autoSwitchOn: "\uC794\uC561 \uD504\uB85C\uBC14\uC774\uB354 \uC790\uB3D9 \uC804\uD658: \uCF1C\uC9D0",
  autoSwitchOff: "\uC794\uC561 \uD504\uB85C\uBC14\uC774\uB354 \uC790\uB3D9 \uC804\uD658: \uAEBC\uC9D0",
  providerManual: "\uC794\uC561 \uD504\uB85C\uBC14\uC774\uB354: {p}(\uC790\uB3D9 \uC804\uD658 \uAEBC\uC9D0)",
  runInSession: "\uC138\uC158 \uB0B4\uC5D0\uC11C \uC2E4\uD589\uD574 \uC8FC\uC138\uC694",
  backToMain: "\uBA54\uC778 \uC138\uC158\uC73C\uB85C \uB3CC\uC544\uAC14\uC2B5\uB2C8\uB2E4",
  subAgentSwitched: "\uC11C\uBE0C \uC5D0\uC774\uC804\uD2B8\uB85C \uC804\uD658: {s}",
  // ── 다이얼로그 / 메뉴 ──
  langTitle: "\uD45C\uC2DC \uC5B8\uC5B4",
  subPrefix: "\uC11C\uBE0C: ",
  keyUser: "(\uC0AC\uC6A9\uC790 key)",
  keyOpenCode: "(OpenCode)",
  keyNotSet: "(\uBBF8\uC124\uC815)",
  balKeyPrompt: "{p} API Key\uB97C \uC785\uB825\uD558\uC5EC \uC794\uC561 \uD45C\uC2DC(\uBE44\uC6B0\uBA74 \uC0AD\uC81C)",
  balProvTitle: "\uC794\uC561 \uD504\uB85C\uBC14\uC774\uB354 / \uC790\uB3D9 \uC804\uD658",
  autoSwitchOpt: "\uC790\uB3D9 \uC804\uD658 \uD504\uB85C\uBC14\uC774\uB354",
  balSelectTitle: "\uC794\uC561 \uD504\uB85C\uBC14\uC774\uB354 \uC120\uD0DD",
  backToMainTitle: "\uBA54\uC778\uC73C\uB85C \uB3CC\uC544\uAC00\uAE30",
  subSelectTitle: "\uC11C\uBE0C \uC5D0\uC774\uC804\uD2B8 \uC120\uD0DD",
  subSwitchTitle: "\uC11C\uBE0C \uC804\uD658",
  subViewTitle: "\uC11C\uBE0C \uCE90\uC2DC \uBCF4\uAE30",
  subNoFound: "\uC11C\uBE0C \uC5D0\uC774\uC804\uD2B8\uB97C \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4. Session ID\uB97C \uC9C1\uC811 \uBD99\uC5EC\uB123\uC73C\uC138\uC694"
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
  return (key, params) => applyParams(LANGS[getCode()][key], params);
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
function charColumns(c) {
  const code = c.codePointAt(0) ?? 0;
  if (code < 32) return 0;
  if (code < 127) return 1;
  if (code < 160) return 0;
  if (code >= 4352 && code <= 4447 || // Hangul Jamo
  code >= 11904 && code <= 42191 || // CJK Radicals … Yi
  code >= 44032 && code <= 55203 || // Hangul
  code >= 63744 && code <= 64255 || // CJK Compat
  code >= 65040 && code <= 65135 || // Vertical / Compat
  code >= 65281 && code <= 65376 || // Fullwidth
  code >= 65504 && code <= 65510 || // Fullwidth signs
  code >= 127744 && code <= 128591 || // Misc Symbols (emoji)
  code >= 131072 && code <= 262141)
    return 2;
  return 1;
}
function visualWidth(s) {
  let w = 0;
  for (const c of s) w += charColumns(c);
  return w;
}
function visualPadEnd(s, cols) {
  const pad = cols - visualWidth(s);
  return pad > 0 ? s + " ".repeat(pad) : s;
}
function truncateVisual(s, maxCols) {
  if (visualWidth(s) <= maxCols) return s;
  let result = "", w = 0;
  for (const c of s) {
    const cw = charColumns(c);
    if (w + cw > maxCols - 1) {
      result += "\u2026";
      break;
    }
    result += c;
    w += cw;
  }
  return result;
}
var DEBUG_LANG = typeof process !== "undefined" ? process.env?.CACHE_TUI_LANG : void 0;
var INIT_LANG = DEBUG_LANG !== void 0 && LANG_META.some((m) => m.code === DEBUG_LANG) ? DEBUG_LANG : detectLang();
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
function progressBar(percent, width) {
  const clamped = Math.max(0, Math.min(100, percent));
  const filled = Math.round(clamped / 100 * width);
  const empty = Math.max(0, width - filled);
  return "\u2588".repeat(filled) + "\u2591".repeat(empty);
}
function fmt(n) {
  if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
  if (n >= 1e4) return (n / 1e3).toFixed(1) + "K";
  return n.toLocaleString("en-US");
}
function num(v) {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}
function fmtCost(n, symbol = "$", rate = 1) {
  const v = n * rate;
  if (v >= 1) return symbol + v.toFixed(2);
  if (v >= 0.01) return symbol + v.toFixed(3);
  return symbol + v.toFixed(4);
}
function estimateTokens(text) {
  if (!text || text.length === 0) return 0;
  let ascii = 0;
  let cjk = 0;
  for (const c of text) {
    const code = c.codePointAt(0) ?? 0;
    if (code >= 19968 && code <= 40959) cjk++;
    else if (code >= 12352 && code <= 12543) cjk++;
    else if (code >= 44032 && code <= 55203) cjk++;
    else if (code >= 4352 && code <= 4607) cjk++;
    else if (code >= 11904 && code <= 12031) cjk++;
    else ascii++;
  }
  const trimmed = text.trimStart();
  const strippedFence = trimmed.replace(/^\x60{3}\w*\s*\n?/, "");
  const jsonLike = (strippedFence.startsWith("{") || strippedFence.startsWith("[")) && /"[^"]+"\s*:/.test(text);
  const codeLike = !jsonLike && /```|^import |^export |^function |^const |^let |^var |^class |^interface |^type |^def |^fn |^pub |^use |^mod |^package /m.test(text);
  const asciiPerToken = jsonLike ? 3.5 : codeLike ? 3.5 : 4;
  return Math.max(1, Math.ceil(ascii / asciiPerToken + cjk / 1));
}
var BALANCE_POLL_MS = 5 * 60 * 1e3;
function convertBalance(target, targetRate, amount, from) {
  if (from === target) return amount;
  const fromRate = DEFAULT_RATES[from] ?? 1;
  const usd = from === "USD" ? amount : amount / fromRate;
  return target === "USD" ? usd : usd * targetRate;
}
function findOpencodeKey(api, provider) {
  try {
    const provs = api.state.provider;
    const id = provider.id.toLowerCase();
    const hit = provs.find((p) => p.id.toLowerCase() === id) ?? provs.find((p) => p.id.toLowerCase().startsWith(id));
    if (!hit) return "";
    const k = typeof hit.key === "string" ? hit.key : "";
    if (k) return k;
    return typeof hit.options?.apiKey === "string" ? hit.options.apiKey : "";
  } catch {
    return "";
  }
}
function balanceSymbol(currency) {
  const sym = CURRENCIES[currency];
  return sym ?? currency + " ";
}
function fmtCompact(n) {
  if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
  if (n >= 1e3) return (n / 1e3).toFixed(1) + "K";
  return String(Math.round(n));
}
function formatBalanceAmount(total) {
  const n = parseFloat(total);
  if (!Number.isFinite(n)) return total;
  if (n === 0 || n >= 1) return n.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
  return n.toLocaleString("en-US", {
    maximumFractionDigits: 6
  });
}
function formatBalanceText(list, pref, rate) {
  const native = pref ? list.find((x) => x.currency === pref) : void 0;
  if (native) return balanceSymbol(native.currency) + formatBalanceAmount(native.total);
  const base = list[0];
  const baseAmt = parseFloat(base.total);
  const converted = Number.isFinite(baseAmt) ? convertBalance(pref || base.currency, rate, baseAmt, base.currency) : baseAmt;
  const shown = pref && base.currency !== pref ? converted.toLocaleString("en-US", {
    maximumFractionDigits: 2
  }) : formatBalanceAmount(base.total);
  return balanceSymbol(pref || base.currency) + shown;
}
var CURRENCIES = {
  USD: "$",
  CNY: "\xA5",
  EUR: "\u20AC",
  JPY: "JP\xA5",
  GBP: "\xA3",
  KRW: "\u20A9"
};
var DEFAULT_RATES = {
  USD: 1,
  CNY: 7.2,
  EUR: 0.92,
  JPY: 150,
  GBP: 0.79,
  KRW: 1350
};
var MIN_PANEL_WIDTH = 20;
var DEFAULT_PANEL_WIDTH = 26;
var LABEL_GAP = 1;
var BAR_BRACKETS = 2;
var BAR_GAP = 1;
var PCT_FIXED_WIDTH = 5;
var HEADER_PREFIX = 2;
var UNIT_GAP = 1;
function TokenCachePanel(props) {
  const [panelWidth, setPanelWidth] = createSignal(DEFAULT_PANEL_WIDTH);
  const [open, setOpen] = createSignal(true);
  const [detailOpen, setDetailOpen] = createSignal(true);
  const [modelOpen, setModelOpen] = createSignal(true);
  const [distOpen, setDistOpen] = createSignal(false);
  const [skillsOpen, setSkillsOpen] = createSignal(true);
  let boxEl;
  createEffect(() => {
    props.signals.setSidebarVisible(true);
    onCleanup(() => props.signals.setSidebarVisible(false));
  });
  const {
    currencySymbol,
    setCurrencySymbol,
    exchangeRate,
    setExchangeRate,
    langCode,
    sectionDetail,
    setSectionDetail,
    sectionModel,
    setSectionModel,
    sectionDist,
    setSectionDist,
    sectionSkills,
    setSectionSkills,
    sectionBalance,
    setSectionBalance,
    balanceRefresh,
    balanceProviderId,
    setBalanceProviderId,
    autoBalance,
    setAutoBalance,
    balanceUnsupported,
    setBalanceUnsupported,
    balanceState,
    balanceCurrency,
    setBalanceCurrency,
    borderVisible,
    setBorderVisible
  } = props.signals;
  const t = createT(() => langCode());
  const [lastDist, setLastDist] = createSignal({
    system: 0,
    user: 0,
    agent: 0,
    toolCall: 0,
    toolResult: 0,
    output: 0,
    reasoning: 0,
    apiOutput: 0,
    apiInput: 0,
    stepCost: 0,
    stepCount: 0
  });
  const [lastHasDist, setLastHasDist] = createSignal(false);
  const [dataSignal, setDataSignal] = createSignal({
    hitRate: 0,
    read: 0,
    write: 0,
    freshInput: 0,
    output: 0,
    cost: 0,
    saved: 0,
    model: "",
    inputRate: 0,
    cacheReadRate: 0,
    cacheWriteRate: 0,
    hasPricing: false,
    hasData: false,
    trend: 0,
    hasTrendData: false,
    providerName: "",
    sessionHitRate: 0,
    dist: {
      system: 0,
      user: 0,
      agent: 0,
      toolCall: 0,
      toolResult: 0,
      output: 0,
      reasoning: 0,
      apiOutput: 0,
      apiInput: 0,
      stepCost: 0,
      stepCount: 0
    },
    hasDistData: false,
    skills: [],
    hasSkills: false
  });
  const [refreshTick, setRefreshTick] = createSignal(0);
  const providerName = createMemo(() => getBalanceProvider(balanceProviderId()).name);
  createEffect(() => {
    if (!autoBalance()) return;
    const sid = props.signals.overrideSessionId() ?? props.sessionId;
    const msgs = props.api.state.session.messages(sid);
    let pid = "";
    for (let i = msgs.length - 1; i >= 0; i--) {
      const m = msgs[i];
      if (m.role === "assistant" && m.providerID) {
        pid = m.providerID;
        break;
      }
    }
    if (!pid) {
      try {
        const session = props.api.state.session.get(sid);
        pid = session?.model?.providerID ?? "";
      } catch {
      }
    }
    if (!pid) return;
    const hit = matchBalanceProvider(pid);
    if (hit) {
      setBalanceUnsupported(false);
      if (hit.id !== balanceProviderId()) {
        setBalanceProviderId(hit.id);
        props.signals.setBalanceRefresh(props.signals.balanceRefresh() + 1);
      }
    } else {
      setBalanceUnsupported(true);
    }
  });
  let lastMainSid = props.sessionId;
  createEffect(() => {
    const sid = props.sessionId;
    if (sid !== lastMainSid) {
      lastMainSid = sid;
      if (props.signals.overrideSessionId()) {
        props.signals.setOverrideSessionId(void 0);
        props.api.kv.set(`${KV_PREFIX}.session`, "");
      }
    }
  });
  createEffect(() => {
    const sid = props.signals.overrideSessionId() ?? props.sessionId;
    void refreshTick();
    void partVersion();
    const msgs = props.api.state.session.messages(sid);
    const session = typeof props.api.state.session.get === "function" ? props.api.state.session.get(sid) : void 0;
    let input = session?.tokens?.input ?? 0;
    let read = session?.tokens?.cache?.read ?? 0;
    let write = session?.tokens?.cache?.write ?? 0;
    let output = session?.tokens?.output ?? 0;
    let cost = session?.cost ?? 0;
    let pid = session?.model?.providerID ?? "";
    let mid = session?.model?.id ?? "";
    const fallbackTokens = session?.tokens == null;
    const fallbackCost = session?.cost == null;
    const fallbackModel = !pid || !mid;
    let prevMsgHitRate = -1, lastMsgHitRate = -1;
    for (const msg of msgs) {
      if (msg.role !== "assistant") continue;
      const tok = msg.tokens;
      if (!tok) continue;
      const mit = num(tok.input) + num(tok.cache?.read) + num(tok.cache?.write), mrt = num(tok.cache?.read);
      if (mit > 0) {
        prevMsgHitRate = lastMsgHitRate;
        lastMsgHitRate = mrt / mit * 100;
      }
      if (fallbackTokens) {
        input += num(tok.input);
        read += num(tok.cache?.read);
        write += num(tok.cache?.write);
        output += num(tok.output);
      }
      if (fallbackCost) {
        cost += num(msg.cost);
      }
      if (fallbackModel && msg.providerID && msg.modelID) {
        pid = msg.providerID;
        mid = msg.modelID;
      }
    }
    let saved = 0, inputRate = 0, cacheReadRate = 0, cacheWriteRate = 0;
    if (read > 0 && pid && mid && Array.isArray(props.api.state.provider)) for (const provider of props.api.state.provider) {
      if (provider.id !== pid) continue;
      const model2 = provider.models[mid];
      if (!model2?.cost) continue;
      inputRate = num(model2.cost.input);
      cacheReadRate = num(model2.cost.cache?.read);
      cacheWriteRate = num(model2.cost.cache?.write);
      if (inputRate > cacheReadRate) saved = read * (inputRate - cacheReadRate) / 1e6;
      break;
    }
    const hitRate = lastMsgHitRate >= 0 ? lastMsgHitRate : 0;
    const freshTotal = input + read + write, sessionHitRate = freshTotal > 0 ? read / freshTotal * 100 : 0;
    const model = mid.split("/").pop() ?? mid, hasPricing = inputRate > 0 || cacheReadRate > 0 || cacheWriteRate > 0;
    const hasTrendData = prevMsgHitRate >= 0 && lastMsgHitRate >= 0;
    const trend = hasTrendData ? lastMsgHitRate - prevMsgHitRate : 0, providerName2 = pid || "";
    const distData = untrack(() => {
      let dist = {
        system: 0,
        user: 0,
        agent: 0,
        toolCall: 0,
        toolResult: 0,
        output: 0,
        reasoning: 0,
        apiOutput: 0,
        apiInput: 0,
        stepCost: 0,
        stepCount: 0
      };
      let hasDistData = false;
      const loadedSkills = /* @__PURE__ */ new Map();
      try {
        const cfg = props.api.state.config;
        const agentName = String(session?.agent ?? cfg?.default_agent ?? "build");
        const agents = cfg?.agent;
        const agentCfg = agents?.[agentName];
        const sysPrompt = typeof agentCfg?.prompt === "string" ? agentCfg.prompt : "";
        if (sysPrompt) dist.system = estimateTokens(sysPrompt);
        let lastAssMsg;
        for (const msg of msgs) {
          if (msg.role === "user") {
            const um = msg;
            if (um.system) dist.system += estimateTokens(um.system);
            let parts = [];
            try {
              parts = props.api.state.part(msg.id);
            } catch {
            }
            for (const p of parts) {
              if (p.type === "text" && !p.synthetic && !p.ignored) dist.user += estimateTokens(p.text);
              else if (p.type === "file") {
                const fp = p;
                if (fp.source?.text?.value) dist.user += estimateTokens(fp.source.text.value);
              }
            }
          } else if (msg.role === "assistant") {
            const am = msg;
            dist.output += num(am.tokens?.output);
            dist.reasoning += num(am.tokens?.reasoning);
            let parts = [];
            try {
              parts = props.api.state.part(msg.id);
            } catch {
            }
            for (const p of parts) {
              if (p.type === "tool") {
                const tp = p;
                let rawInput = "";
                try {
                  rawInput = tp.state.raw ?? (tp.state.input != null ? JSON.stringify(tp.state.input) : "");
                } catch {
                }
                if (rawInput) dist.toolCall += estimateTokens(rawInput);
                if (tp.tool === "task" && tp.state?.input) {
                  const ti = tp.state.input;
                  const prompt = typeof ti.prompt === "string" ? ti.prompt : "";
                  const desc = typeof ti.description === "string" ? ti.description : "";
                  dist.agent += estimateTokens(prompt || desc);
                }
                if (tp.state.status === "completed") {
                  const c = tp.state;
                  if (c.output) dist.toolResult += estimateTokens(c.output);
                } else if (tp.state.status === "error") {
                  const e = tp.state;
                  if (e.error) dist.toolResult += estimateTokens(e.error);
                }
                if (tp.tool === "skill" && tp.state.status === "completed") {
                  let name = tp.state.metadata?.name;
                  if (typeof name !== "string") {
                    const m = typeof tp.state.output === "string" ? tp.state.output.match(/^#{1,2}\s*Skill:\s*(.+)/m) : null;
                    if (m) name = m[1].trim();
                  }
                  if (typeof name === "string") {
                    const tokens = typeof tp.state.output === "string" ? estimateTokens(tp.state.output) : 0;
                    const existing = loadedSkills.get(name);
                    if (!existing || existing.tokens < tokens) {
                      loadedSkills.set(name, {
                        name,
                        tokens
                      });
                    }
                  }
                }
              } else if (p.type === "subtask") {
                const sub = p;
                dist.agent += estimateTokens(sub.prompt || sub.description || "");
              }
            }
          }
        }
        for (let i = msgs.length - 1; i >= 0; i--) {
          if (msgs[i].role !== "assistant") continue;
          const tok = msgs[i].tokens;
          if (tok && ((tok.input ?? 0) > 0 || (tok.cache?.read ?? 0) > 0 || (tok.cache?.write ?? 0) > 0)) {
            lastAssMsg = msgs[i];
            break;
          }
        }
        dist.apiInput = num(lastAssMsg?.tokens?.input) + num(lastAssMsg?.tokens?.cache?.read) + num(lastAssMsg?.tokens?.cache?.write);
        dist.apiOutput = num(lastAssMsg?.tokens?.output);
        if (lastAssMsg) {
          const roundParent = lastAssMsg.parentID;
          let lastCost;
          for (let i = msgs.length - 1; i >= 0; i--) {
            const m = msgs[i];
            if (m.role !== "assistant") continue;
            if (m.parentID !== roundParent) break;
            let parts = [];
            try {
              parts = props.api.state.part(m.id);
            } catch {
            }
            for (const p of parts) {
              if (p.type !== "step-finish") continue;
              dist.stepCount++;
              const sc = p.cost;
              if (lastCost === void 0 && typeof sc === "number" && Number.isFinite(sc)) lastCost = sc;
            }
          }
          if (lastCost !== void 0) dist.stepCost = lastCost;
        }
        hasDistData = dist.system + dist.user + dist.agent + dist.toolCall + dist.toolResult > 0 || dist.apiOutput > 0 || dist.apiInput > 0 || dist.reasoning > 0;
      } catch {
      }
      const finalDist = hasDistData ? dist : lastDist(), finalHasDist = hasDistData || lastHasDist();
      const skills = [...loadedSkills.values()];
      return {
        finalDist,
        finalHasDist,
        skills
      };
    });
    setDataSignal({
      hitRate,
      read,
      write,
      freshInput: input,
      output,
      cost,
      saved,
      model,
      inputRate,
      cacheReadRate,
      cacheWriteRate,
      hasPricing,
      hasData: read > 0 || write > 0 || input > 0 || output > 0 || cost > 0,
      trend,
      hasTrendData,
      providerName: providerName2,
      sessionHitRate,
      dist: distData.finalDist,
      hasDistData: distData.finalHasDist,
      skills: distData.skills,
      hasSkills: distData.skills.length > 0
    });
  });
  const data = createMemo(() => {
    return dataSignal();
  });
  createEffect(() => {
    const d = data();
    if (d.hasDistData) {
      setLastDist({
        ...d.dist
      });
      setLastHasDist(true);
      try {
        props.api.kv.set(`${KV_PREFIX}.dist_snapshot`, {
          ...d.dist
        });
      } catch {
      }
    }
  });
  const [partVersion, setPartVersion] = createSignal(0);
  const KV_PREFIX = "cache_panel";
  const persistFold = (key, val) => {
    try {
      props.api.kv.set(`${KV_PREFIX}.${key}`, val);
    } catch {
    }
  };
  onMount(() => {
    setPanelWidth(DEFAULT_PANEL_WIDTH);
    try {
      setOpen(Boolean(props.api.kv.get(`${KV_PREFIX}.open`, false)));
      setDetailOpen(Boolean(props.api.kv.get(`${KV_PREFIX}.detail`, true)));
      setModelOpen(Boolean(props.api.kv.get(`${KV_PREFIX}.model`, true)));
      setDistOpen(Boolean(props.api.kv.get(`${KV_PREFIX}.dist`, false)));
      setSkillsOpen(Boolean(props.api.kv.get(`${KV_PREFIX}.skills`, true)));
    } catch {
    }
    const doRestore = () => {
      try {
        const sym = props.api.kv.get(`${KV_PREFIX}.currency`);
        const rate = props.api.kv.get(`${KV_PREFIX}.rate`);
        if (typeof sym === "string") setCurrencySymbol(sym);
        if (typeof rate === "number" && rate > 0) setExchangeRate(rate);
        const balCur = props.api.kv.get(`${KV_PREFIX}.balance_currency`);
        if (typeof balCur === "string") setBalanceCurrency(balCur);
        const savedProvider = props.api.kv.get(`${KV_PREFIX}.balance.provider`);
        if (typeof savedProvider === "string" && balanceProviders.some((p) => p.id === savedProvider)) {
          setBalanceProviderId(savedProvider);
          setBalanceUnsupported(false);
        }
        const savedAuto = props.api.kv.get(`${KV_PREFIX}.balance.auto`);
        if (typeof savedAuto === "boolean") setAutoBalance(savedAuto);
        const legacyKey = props.api.kv.get(`${KV_PREFIX}.ds_key`, "");
        if (legacyKey) {
          const dsKey = props.api.kv.get(`${KV_PREFIX}.balance.deepseek.key`, "");
          if (!dsKey) props.api.kv.set(`${KV_PREFIX}.balance.deepseek.key`, legacyKey);
          props.api.kv.set(`${KV_PREFIX}.ds_key`, "");
        }
        props.signals.setBalanceRefresh(props.signals.balanceRefresh() + 1);
        setSectionDetail(Boolean(props.api.kv.get(`${KV_PREFIX}.section.detail`, true)));
        setSectionModel(Boolean(props.api.kv.get(`${KV_PREFIX}.section.model`, true)));
        setSectionDist(Boolean(props.api.kv.get(`${KV_PREFIX}.section.dist`, true)));
        setSectionSkills(Boolean(props.api.kv.get(`${KV_PREFIX}.section.skills`, true)));
        setSectionBalance(Boolean(props.api.kv.get(`${KV_PREFIX}.section.balance`, true)));
        const bv = props.api.kv.get(`${KV_PREFIX}.border`, true);
        setBorderVisible(bv !== false);
        const cachedDist = props.api.kv.get(`${KV_PREFIX}.dist_snapshot`);
        if (cachedDist) {
          setLastDist(cachedDist);
          setLastHasDist(true);
        }
      } catch {
      }
      if (boxEl && typeof boxEl.width === "number" && boxEl.width > 0) {
        setPanelWidth(Math.max(MIN_PANEL_WIDTH, boxEl.width));
      }
    };
    if (props.api.kv.ready) {
      doRestore();
    } else {
      const MAX_POLL = 100;
      let tries = 0;
      const pollRestore = () => {
        if (!props.api.kv.ready) {
          if (++tries > MAX_POLL) {
            doRestore();
            return;
          }
          setTimeout(pollRestore, 10);
          return;
        }
        doRestore();
      };
      pollRestore();
    }
    let partTimer;
    const bumpPartVersion = () => {
      clearTimeout(partTimer);
      partTimer = setTimeout(() => setPartVersion((v) => v + 1), 100);
    };
    const unsubPart = props.api.event.on("message.part.updated", () => {
      bumpPartVersion();
      setRefreshTick((v) => v + 1);
    });
    const unsubMsg = props.api.event.on("message.updated", () => {
      bumpPartVersion();
      setRefreshTick((v) => v + 1);
    });
    const unsubSession = props.api.event.on("session.updated", () => {
      setRefreshTick((v) => v + 1);
    });
    setRefreshTick((v) => v + 1);
    onCleanup(() => {
      clearTimeout(partTimer);
      unsubPart();
      unsubMsg();
      unsubSession();
    });
  });
  const pal = createMemo(() => {
    const t2 = props.theme;
    const sat = (k, fb) => desaturateTo(t2[k], MAX_SAT, fb);
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
  const hitColor = createMemo(() => {
    const r = data().hitRate;
    if (r >= 85) return pal().success;
    if (r >= 70) return pal().warning;
    return pal().error;
  });
  const gutter = createMemo(() => borderVisible() ? 6 : 0);
  const sep = createMemo(() => "\u2500".repeat(Math.max(1, panelWidth() - gutter())));
  function trendLabel(t2) {
    if (Math.abs(t2) < 0.05) return "-";
    return (t2 > 0 ? "\u2191" : "\u2193") + Math.abs(t2).toFixed(1) + "%";
  }
  const barW = createMemo(() => {
    const trendSpace = data().hasTrendData ? LABEL_GAP + visualWidth(trendLabel(data().trend)) : 0;
    const overhead = visualWidth(t("hit")) + LABEL_GAP + BAR_BRACKETS + BAR_GAP + PCT_FIXED_WIDTH + trendSpace + gutter();
    return Math.max(3, panelWidth() - overhead);
  });
  const bar = createMemo(() => progressBar(data().hitRate, barW()));
  const pct = createMemo(() => (Math.floor(data().hitRate * 10) / 10).toFixed(1) + "%");
  createEffect(() => {
    borderVisible();
    if (boxEl && typeof boxEl.width === "number" && boxEl.width > 0) {
      const w = Math.max(MIN_PANEL_WIDTH, boxEl.width);
      setPanelWidth((prev) => prev === w ? prev : w);
    }
  });
  const justify = (label, value, unit = "") => {
    const gauge = panelWidth() - gutter();
    const used = visualWidth(label) + visualWidth(value) + (unit ? visualWidth(unit) + UNIT_GAP : 0);
    const gap = Math.max(1, gauge - used);
    return label + " ".repeat(gap) + value + (unit ? " " + unit : "");
  };
  return (() => {
    var _el$ = _$createElement("box"), _el$2 = _$createElement("text"), _el$3 = _$createElement("span"), _el$4 = _$createElement("span"), _el$5 = _$createElement("b");
    _$insertNode(_el$, _el$2);
    var _ref$ = boxEl;
    typeof _ref$ === "function" ? _$use(_ref$, _el$) : boxEl = _el$;
    _$spread(_el$, _$mergeProps({
      get border() {
        return borderVisible();
      }
    }, () => borderVisible() ? {
      borderColor: pal().border
    } : {}, {
      "paddingTop": 0,
      "paddingBottom": 0,
      get paddingLeft() {
        return borderVisible() ? 2 : 0;
      },
      get paddingRight() {
        return borderVisible() ? 2 : 0;
      },
      "flexDirection": "column",
      "gap": 0,
      "onSizeChange": () => {
        const w = boxEl ? Math.max(MIN_PANEL_WIDTH, boxEl.width ?? 0) : DEFAULT_PANEL_WIDTH;
        setPanelWidth((prev) => prev === w ? prev : w);
      }
    }), true);
    _$insertNode(_el$2, _el$3);
    _$insertNode(_el$2, _el$4);
    _$setProp(_el$2, "onMouseUp", () => setOpen((o) => {
      const n = !o;
      persistFold("open", n);
      return n;
    }));
    _$insert(_el$3, () => open() ? "\u25BC " : "\u25B6 ");
    _$insertNode(_el$4, _el$5);
    _$insert(_el$5, () => t("title"));
    _$insert(_el$4, _$createComponent(Show, {
      get when() {
        return open();
      },
      get children() {
        var _el$6 = _$createElement("span"), _el$7 = _$createTextNode(` v`);
        _$insertNode(_el$6, _el$7);
        _$insert(_el$6, PLUGIN_VERSION, null);
        _$effect((_$p) => _$setProp(_el$6, "style", {
          fg: dimColor(pal().muted, 0.75)
        }, _$p));
        return _el$6;
      }
    }), null);
    _$insert(_el$2, _$createComponent(Show, {
      get when() {
        return _$memo(() => !!!open())() && data().hasData;
      },
      get children() {
        return [_$createComponent(Show, {
          get when() {
            return data().hasTrendData;
          },
          get children() {
            return [(() => {
              var _el$8 = _$createElement("span");
              _$insert(_el$8, () => " ".repeat(Math.max(1, panelWidth() - gutter() - HEADER_PREFIX - visualWidth(t("title")) - visualWidth(pct() + " " + t("hitFolded") + " " + trendLabel(data().trend)))));
              return _el$8;
            })(), (() => {
              var _el$9 = _$createElement("span"), _el$0 = _$createTextNode(` `);
              _$insertNode(_el$9, _el$0);
              _$insert(_el$9, pct, _el$0);
              _$insert(_el$9, () => t("hitFolded"), null);
              _$effect((_$p) => _$setProp(_el$9, "style", {
                fg: hitColor()
              }, _$p));
              return _el$9;
            })(), (() => {
              var _el$1 = _$createElement("span"), _el$10 = _$createTextNode(` `);
              _$insertNode(_el$1, _el$10);
              _$insert(_el$1, () => trendLabel(data().trend), null);
              _$effect((_$p) => _$setProp(_el$1, "style", {
                fg: Math.abs(data().trend) >= 0.05 ? data().trend > 0 ? pal().success : pal().error : pal().text
              }, _$p));
              return _el$1;
            })()];
          }
        }), _$createComponent(Show, {
          get when() {
            return !data().hasTrendData;
          },
          get children() {
            return [(() => {
              var _el$11 = _$createElement("span");
              _$insert(_el$11, () => " ".repeat(Math.max(1, panelWidth() - gutter() - HEADER_PREFIX - visualWidth(t("title")) - visualWidth(pct() + " " + t("hitFolded")))));
              return _el$11;
            })(), (() => {
              var _el$12 = _$createElement("span"), _el$13 = _$createTextNode(` `);
              _$insertNode(_el$12, _el$13);
              _$insert(_el$12, pct, _el$13);
              _$insert(_el$12, () => t("hitFolded"), null);
              _$effect((_$p) => _$setProp(_el$12, "style", {
                fg: hitColor()
              }, _$p));
              return _el$12;
            })()];
          }
        })];
      }
    }), null);
    _$insert(_el$, _$createComponent(Show, {
      get when() {
        return open();
      },
      get children() {
        return [_$createComponent(Show, {
          get when() {
            return props.signals.overrideSessionId();
          },
          get children() {
            return (() => {
              const prefix = "  \u21B3 " + t("subPrefix");
              const maxSidW = Math.max(6, panelWidth() - visualWidth(prefix));
              return (() => {
                var _el$70 = _$createElement("text"), _el$71 = _$createElement("span"), _el$72 = _$createElement("span");
                _$insertNode(_el$70, _el$71);
                _$insertNode(_el$70, _el$72);
                _$insert(_el$71, prefix);
                _$insert(_el$72, () => truncateVisual(props.signals.overrideSessionId(), maxSidW));
                _$effect((_p$) => {
                  var _v$17 = {
                    fg: pal().muted
                  }, _v$18 = {
                    fg: pal().text
                  };
                  _v$17 !== _p$.e && (_p$.e = _$setProp(_el$71, "style", _v$17, _p$.e));
                  _v$18 !== _p$.t && (_p$.t = _$setProp(_el$72, "style", _v$18, _p$.t));
                  return _p$;
                }, {
                  e: void 0,
                  t: void 0
                });
                return _el$70;
              })();
            })();
          }
        }), _$createComponent(Show, {
          get when() {
            return data().hasData;
          },
          get fallback() {
            return [(() => {
              var _el$73 = _$createElement("text");
              _$insert(_el$73, sep);
              _$effect((_$p) => _$setProp(_el$73, "fg", pal().muted, _$p));
              return _el$73;
            })(), (() => {
              var _el$74 = _$createElement("text"), _el$75 = _$createElement("span"), _el$77 = _$createElement("span");
              _$insertNode(_el$74, _el$75);
              _$insertNode(_el$74, _el$77);
              _$insertNode(_el$75, _$createTextNode(`> `));
              _$insert(_el$77, () => t("noData"));
              _$effect((_p$) => {
                var _v$19 = {
                  fg: pal().muted
                }, _v$20 = {
                  fg: pal().muted
                };
                _v$19 !== _p$.e && (_p$.e = _$setProp(_el$75, "style", _v$19, _p$.e));
                _v$20 !== _p$.t && (_p$.t = _$setProp(_el$77, "style", _v$20, _p$.t));
                return _p$;
              }, {
                e: void 0,
                t: void 0
              });
              return _el$74;
            })()];
          },
          get children() {
            return [(() => {
              var _el$14 = _$createElement("text");
              _$insert(_el$14, sep);
              _$effect((_$p) => _$setProp(_el$14, "fg", pal().muted, _$p));
              return _el$14;
            })(), (() => {
              var _el$15 = _$createElement("text"), _el$16 = _$createElement("span"), _el$17 = _$createTextNode(` `), _el$18 = _$createElement("span"), _el$19 = _$createTextNode(`[`), _el$20 = _$createTextNode(`] `), _el$21 = _$createElement("span");
              _$insertNode(_el$15, _el$16);
              _$insertNode(_el$15, _el$18);
              _$insertNode(_el$15, _el$21);
              _$insertNode(_el$16, _el$17);
              _$insert(_el$16, () => t("hit"), _el$17);
              _$insertNode(_el$18, _el$19);
              _$insertNode(_el$18, _el$20);
              _$insert(_el$18, bar, _el$20);
              _$insert(_el$21, pct);
              _$insert(_el$15, _$createComponent(Show, {
                get when() {
                  return data().hasTrendData;
                },
                get children() {
                  var _el$22 = _$createElement("span"), _el$23 = _$createTextNode(` `);
                  _$insertNode(_el$22, _el$23);
                  _$insert(_el$22, () => trendLabel(data().trend), null);
                  _$effect((_$p) => _$setProp(_el$22, "style", {
                    fg: Math.abs(data().trend) >= 0.05 ? data().trend > 0 ? pal().success : pal().error : pal().text
                  }, _$p));
                  return _el$22;
                }
              }), null);
              _$effect((_p$) => {
                var _v$ = {
                  fg: pal().text
                }, _v$2 = {
                  fg: hitColor()
                }, _v$3 = {
                  fg: pal().text
                };
                _v$ !== _p$.e && (_p$.e = _$setProp(_el$16, "style", _v$, _p$.e));
                _v$2 !== _p$.t && (_p$.t = _$setProp(_el$18, "style", _v$2, _p$.t));
                _v$3 !== _p$.a && (_p$.a = _$setProp(_el$21, "style", _v$3, _p$.a));
                return _p$;
              }, {
                e: void 0,
                t: void 0,
                a: void 0
              });
              return _el$15;
            })(), (() => {
              var _el$24 = _$createElement("text");
              _$insert(_el$24, () => justify(t("totalHit"), (Math.floor(data().sessionHitRate * 10) / 10).toFixed(1) + "%"));
              _$effect((_$p) => _$setProp(_el$24, "fg", pal().muted, _$p));
              return _el$24;
            })(), _$createComponent(Show, {
              get when() {
                return sectionDetail();
              },
              get children() {
                return [(() => {
                  var _el$25 = _$createElement("text"), _el$26 = _$createElement("span"), _el$27 = _$createElement("span"), _el$28 = _$createElement("b"), _el$29 = _$createElement("span");
                  _$insertNode(_el$25, _el$26);
                  _$insertNode(_el$25, _el$27);
                  _$insertNode(_el$25, _el$29);
                  _$setProp(_el$25, "onMouseUp", () => setDetailOpen((o) => {
                    const n = !o;
                    persistFold("detail", n);
                    return n;
                  }));
                  _$insert(_el$26, () => detailOpen() ? "\u25BC " : "\u25B6 ");
                  _$insertNode(_el$27, _el$28);
                  _$insert(_el$28, () => t("secDetail"));
                  _$insert(_el$29, () => sep().slice(visualWidth((detailOpen() ? "\u25BC " : "\u25B6 ") + t("secDetail"))));
                  _$effect((_p$) => {
                    var _v$4 = {
                      fg: pal().muted
                    }, _v$5 = {
                      fg: pal().primary
                    }, _v$6 = {
                      fg: pal().muted
                    };
                    _v$4 !== _p$.e && (_p$.e = _$setProp(_el$26, "style", _v$4, _p$.e));
                    _v$5 !== _p$.t && (_p$.t = _$setProp(_el$27, "style", _v$5, _p$.t));
                    _v$6 !== _p$.a && (_p$.a = _$setProp(_el$29, "style", _v$6, _p$.a));
                    return _p$;
                  }, {
                    e: void 0,
                    t: void 0,
                    a: void 0
                  });
                  return _el$25;
                })(), _$createComponent(Show, {
                  get when() {
                    return detailOpen();
                  },
                  get children() {
                    return [_$createComponent(Show, {
                      get when() {
                        return data().read > 0;
                      },
                      get children() {
                        var _el$30 = _$createElement("text");
                        _$insert(_el$30, () => justify(t("read"), fmt(data().read), t("tok")));
                        _$effect((_$p) => _$setProp(_el$30, "fg", pal().muted, _$p));
                        return _el$30;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return data().write > 0;
                      },
                      get children() {
                        var _el$31 = _$createElement("text");
                        _$insert(_el$31, () => justify(t("write"), fmt(data().write), t("tok")));
                        _$effect((_$p) => _$setProp(_el$31, "fg", pal().muted, _$p));
                        return _el$31;
                      }
                    }), (() => {
                      var _el$32 = _$createElement("text");
                      _$insert(_el$32, () => justify(t("miss"), fmt(data().freshInput + data().write), t("tok")));
                      _$effect((_$p) => _$setProp(_el$32, "fg", pal().muted, _$p));
                      return _el$32;
                    })(), (() => {
                      var _el$33 = _$createElement("text");
                      _$insert(_el$33, () => justify(t("out"), fmt(data().output), t("tok")));
                      _$effect((_$p) => _$setProp(_el$33, "fg", pal().muted, _$p));
                      return _el$33;
                    })(), _$createComponent(Show, {
                      get when() {
                        return data().dist.stepCount >= 2;
                      },
                      get children() {
                        var _el$34 = _$createElement("text");
                        _$insert(_el$34, () => justify(t("stepsCount", {
                          n: data().dist.stepCount
                        }), fmtCost(data().dist.stepCost, currencySymbol(), exchangeRate())));
                        _$effect((_$p) => _$setProp(_el$34, "fg", pal().muted, _$p));
                        return _el$34;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return data().saved > 0;
                      },
                      get children() {
                        var _el$35 = _$createElement("text"), _el$36 = _$createElement("span"), _el$37 = _$createElement("span"), _el$38 = _$createElement("span"), _el$39 = _$createTextNode(`~`);
                        _$insertNode(_el$35, _el$36);
                        _$insertNode(_el$35, _el$37);
                        _$insertNode(_el$35, _el$38);
                        _$insert(_el$36, () => t("saved"));
                        _$insert(_el$37, () => " ".repeat(Math.max(1, panelWidth() - gutter() - visualWidth(t("saved")) - visualWidth("~" + fmtCost(data().saved, currencySymbol(), exchangeRate())))));
                        _$insertNode(_el$38, _el$39);
                        _$insert(_el$38, () => fmtCost(data().saved, currencySymbol(), exchangeRate()), null);
                        _$effect((_p$) => {
                          var _v$7 = {
                            fg: pal().muted
                          }, _v$8 = {
                            fg: pal().success
                          };
                          _v$7 !== _p$.e && (_p$.e = _$setProp(_el$36, "style", _v$7, _p$.e));
                          _v$8 !== _p$.t && (_p$.t = _$setProp(_el$38, "style", _v$8, _p$.t));
                          return _p$;
                        }, {
                          e: void 0,
                          t: void 0
                        });
                        return _el$35;
                      }
                    })];
                  }
                })];
              }
            }), _$createComponent(Show, {
              get when() {
                return sectionModel();
              },
              get children() {
                return [_$memo(() => (() => {
                  var _el$78 = _$createElement("text"), _el$79 = _$createElement("span"), _el$80 = _$createElement("span"), _el$81 = _$createElement("b"), _el$82 = _$createElement("span");
                  _$insertNode(_el$78, _el$79);
                  _$insertNode(_el$78, _el$80);
                  _$insertNode(_el$78, _el$82);
                  _$setProp(_el$78, "onMouseUp", () => setModelOpen((o) => {
                    const n = !o;
                    persistFold("model", n);
                    return n;
                  }));
                  _$insert(_el$79, () => modelOpen() ? "\u25BC " : "\u25B6 ");
                  _$insertNode(_el$80, _el$81);
                  _$insert(_el$81, () => t("secModel"));
                  _$insert(_el$82, () => sep().slice(visualWidth((modelOpen() ? "\u25BC " : "\u25B6 ") + t("secModel"))));
                  _$effect((_p$) => {
                    var _v$21 = {
                      fg: pal().muted
                    }, _v$22 = {
                      fg: pal().primary
                    }, _v$23 = {
                      fg: pal().muted
                    };
                    _v$21 !== _p$.e && (_p$.e = _$setProp(_el$79, "style", _v$21, _p$.e));
                    _v$22 !== _p$.t && (_p$.t = _$setProp(_el$80, "style", _v$22, _p$.t));
                    _v$23 !== _p$.a && (_p$.a = _$setProp(_el$82, "style", _v$23, _p$.a));
                    return _p$;
                  }, {
                    e: void 0,
                    t: void 0,
                    a: void 0
                  });
                  return _el$78;
                })()), _$createComponent(Show, {
                  get when() {
                    return modelOpen();
                  },
                  get children() {
                    return [(() => {
                      var _el$40 = _$createElement("text");
                      _$insert(_el$40, () => justify(t("cost"), fmtCost(data().cost, currencySymbol(), exchangeRate())));
                      _$effect((_$p) => _$setProp(_el$40, "fg", pal().text, _$p));
                      return _el$40;
                    })(), _$createComponent(Show, {
                      get when() {
                        return data().providerName;
                      },
                      get children() {
                        var _el$41 = _$createElement("text");
                        _$insert(_el$41, () => justify(t("provider"), data().providerName));
                        _$effect((_$p) => _$setProp(_el$41, "fg", pal().muted, _$p));
                        return _el$41;
                      }
                    }), (() => {
                      var _el$42 = _$createElement("text");
                      _$insert(_el$42, () => justify(t("model"), data().model));
                      _$effect((_$p) => _$setProp(_el$42, "fg", pal().muted, _$p));
                      return _el$42;
                    })(), _$createComponent(Show, {
                      get when() {
                        return data().hasPricing;
                      },
                      get children() {
                        return [(() => {
                          var _el$43 = _$createElement("text");
                          _$insert(_el$43, () => justify(t("rate"), currencySymbol() + (data().inputRate * exchangeRate()).toFixed(2) + "/M " + t("inputRate")));
                          _$effect((_$p) => _$setProp(_el$43, "fg", pal().muted, _$p));
                          return _el$43;
                        })(), _$createComponent(Show, {
                          get when() {
                            return data().cacheReadRate > 0;
                          },
                          get children() {
                            var _el$44 = _$createElement("text");
                            _$insert(_el$44, () => justify("", currencySymbol() + (data().cacheReadRate * exchangeRate()).toFixed(2) + "/M " + t("cacheRate")));
                            _$effect((_$p) => _$setProp(_el$44, "fg", pal().muted, _$p));
                            return _el$44;
                          }
                        }), _$createComponent(Show, {
                          get when() {
                            return data().cacheWriteRate > 0;
                          },
                          get children() {
                            var _el$45 = _$createElement("text");
                            _$insert(_el$45, () => justify("", currencySymbol() + (data().cacheWriteRate * exchangeRate()).toFixed(2) + "/M " + t("writeRate")));
                            _$effect((_$p) => _$setProp(_el$45, "fg", pal().muted, _$p));
                            return _el$45;
                          }
                        })];
                      }
                    })];
                  }
                })];
              }
            }), _$createComponent(Show, {
              get when() {
                return sectionDist();
              },
              get children() {
                return _$createComponent(Show, {
                  get when() {
                    return data().hasDistData;
                  },
                  get children() {
                    return [_$memo(() => (() => {
                      var _el$83 = _$createElement("text"), _el$84 = _$createElement("span"), _el$85 = _$createElement("span"), _el$86 = _$createElement("b"), _el$87 = _$createElement("span");
                      _$insertNode(_el$83, _el$84);
                      _$insertNode(_el$83, _el$85);
                      _$insertNode(_el$83, _el$87);
                      _$setProp(_el$83, "onMouseUp", () => setDistOpen((o) => {
                        const n = !o;
                        persistFold("dist", n);
                        return n;
                      }));
                      _$insert(_el$84, () => distOpen() ? "\u25BC " : "\u25B6 ");
                      _$insertNode(_el$85, _el$86);
                      _$insert(_el$86, () => t("distTitle"));
                      _$insert(_el$87, () => sep().slice(visualWidth((distOpen() ? "\u25BC " : "\u25B6 ") + t("distTitle"))));
                      _$effect((_p$) => {
                        var _v$24 = {
                          fg: pal().muted
                        }, _v$25 = {
                          fg: pal().primary
                        }, _v$26 = {
                          fg: pal().muted
                        };
                        _v$24 !== _p$.e && (_p$.e = _$setProp(_el$84, "style", _v$24, _p$.e));
                        _v$25 !== _p$.t && (_p$.t = _$setProp(_el$85, "style", _v$25, _p$.t));
                        _v$26 !== _p$.a && (_p$.a = _$setProp(_el$87, "style", _v$26, _p$.a));
                        return _p$;
                      }, {
                        e: void 0,
                        t: void 0,
                        a: void 0
                      });
                      return _el$83;
                    })()), _$createComponent(Show, {
                      get when() {
                        return distOpen();
                      },
                      get children() {
                        return [_$createComponent(Show, {
                          get when() {
                            return data().dist.system > 0;
                          },
                          get children() {
                            var _el$46 = _$createElement("text");
                            _$insert(_el$46, () => justify(t("distSys"), fmt(data().dist.system), t("tok")));
                            _$effect((_$p) => _$setProp(_el$46, "fg", pal().muted, _$p));
                            return _el$46;
                          }
                        }), _$createComponent(Show, {
                          get when() {
                            return data().dist.user > 0;
                          },
                          get children() {
                            var _el$47 = _$createElement("text");
                            _$insert(_el$47, () => justify(t("distUser"), fmt(data().dist.user), t("tok")));
                            _$effect((_$p) => _$setProp(_el$47, "fg", pal().muted, _$p));
                            return _el$47;
                          }
                        }), _$createComponent(Show, {
                          get when() {
                            return data().dist.agent > 0;
                          },
                          get children() {
                            var _el$48 = _$createElement("text");
                            _$insert(_el$48, () => justify(t("distAgent"), fmt(data().dist.agent), t("tok")));
                            _$effect((_$p) => _$setProp(_el$48, "fg", pal().muted, _$p));
                            return _el$48;
                          }
                        }), _$createComponent(Show, {
                          get when() {
                            return data().dist.toolCall > 0;
                          },
                          get children() {
                            var _el$49 = _$createElement("text");
                            _$insert(_el$49, () => justify(t("distTool"), fmt(data().dist.toolCall), t("tok")));
                            _$effect((_$p) => _$setProp(_el$49, "fg", pal().muted, _$p));
                            return _el$49;
                          }
                        }), _$createComponent(Show, {
                          get when() {
                            return data().dist.toolResult > 0;
                          },
                          get children() {
                            var _el$50 = _$createElement("text");
                            _$insert(_el$50, () => justify(t("distRes"), fmt(data().dist.toolResult), t("tok")));
                            _$effect((_$p) => _$setProp(_el$50, "fg", pal().muted, _$p));
                            return _el$50;
                          }
                        }), _$createComponent(Show, {
                          get when() {
                            return data().dist.reasoning > 0;
                          },
                          get children() {
                            var _el$51 = _$createElement("text");
                            _$insert(_el$51, () => justify(t("distReason"), fmt(data().dist.reasoning), t("tok")));
                            _$effect((_$p) => _$setProp(_el$51, "fg", pal().muted, _$p));
                            return _el$51;
                          }
                        })];
                      }
                    })];
                  }
                });
              }
            }), _$createComponent(Show, {
              get when() {
                return sectionSkills();
              },
              get children() {
                return _$createComponent(Show, {
                  get when() {
                    return data().hasSkills;
                  },
                  get children() {
                    return [_$memo(() => (() => {
                      var _el$88 = _$createElement("text"), _el$89 = _$createElement("span"), _el$90 = _$createElement("span"), _el$91 = _$createElement("b"), _el$92 = _$createElement("span"), _el$93 = _$createTextNode(` (`), _el$94 = _$createTextNode(`)`), _el$95 = _$createElement("span");
                      _$insertNode(_el$88, _el$89);
                      _$insertNode(_el$88, _el$90);
                      _$insertNode(_el$88, _el$92);
                      _$insertNode(_el$88, _el$95);
                      _$setProp(_el$88, "onMouseUp", () => setSkillsOpen((o) => {
                        const n = !o;
                        persistFold("skills", n);
                        return n;
                      }));
                      _$insert(_el$89, () => skillsOpen() ? "\u25BC " : "\u25B6 ");
                      _$insertNode(_el$90, _el$91);
                      _$insert(_el$91, () => t("secSkills"));
                      _$insertNode(_el$92, _el$93);
                      _$insertNode(_el$92, _el$94);
                      _$insert(_el$92, () => data().skills.length, _el$94);
                      _$insert(_el$95, () => sep().slice(visualWidth((skillsOpen() ? "\u25BC " : "\u25B6 ") + t("secSkills") + ` (${data().skills.length})`)));
                      _$effect((_p$) => {
                        var _v$27 = {
                          fg: pal().muted
                        }, _v$28 = {
                          fg: pal().primary
                        }, _v$29 = {
                          fg: pal().muted
                        }, _v$30 = {
                          fg: pal().muted
                        };
                        _v$27 !== _p$.e && (_p$.e = _$setProp(_el$89, "style", _v$27, _p$.e));
                        _v$28 !== _p$.t && (_p$.t = _$setProp(_el$90, "style", _v$28, _p$.t));
                        _v$29 !== _p$.a && (_p$.a = _$setProp(_el$92, "style", _v$29, _p$.a));
                        _v$30 !== _p$.o && (_p$.o = _$setProp(_el$95, "style", _v$30, _p$.o));
                        return _p$;
                      }, {
                        e: void 0,
                        t: void 0,
                        a: void 0,
                        o: void 0
                      });
                      return _el$88;
                    })()), _$createComponent(Show, {
                      get when() {
                        return skillsOpen();
                      },
                      get children() {
                        return data().skills.map((sk) => {
                          const rightW = visualWidth(fmt(sk.tokens)) + UNIT_GAP + visualWidth(t("tok"));
                          const maxLabel = Math.max(4, panelWidth() - gutter() - rightW - 1);
                          const label = truncateVisual(sk.name, maxLabel);
                          return (() => {
                            var _el$96 = _$createElement("text");
                            _$insert(_el$96, () => justify(label, fmt(sk.tokens), t("tok")));
                            _$effect((_$p) => _$setProp(_el$96, "fg", pal().muted, _$p));
                            return _el$96;
                          })();
                        });
                      }
                    })];
                  }
                });
              }
            }), _$createComponent(Show, {
              get when() {
                return sectionBalance();
              },
              get children() {
                return [(() => {
                  var _el$52 = _$createElement("text");
                  _$insert(_el$52, sep);
                  _$effect((_$p) => _$setProp(_el$52, "fg", pal().muted, _$p));
                  return _el$52;
                })(), _$createComponent(Show, {
                  get when() {
                    return balanceUnsupported();
                  },
                  get children() {
                    var _el$53 = _$createElement("text"), _el$54 = _$createElement("span"), _el$56 = _$createElement("span");
                    _$insertNode(_el$53, _el$54);
                    _$insertNode(_el$53, _el$56);
                    _$insertNode(_el$54, _$createTextNode(`> `));
                    _$insert(_el$56, () => t("balUnsupported"));
                    _$effect((_p$) => {
                      var _v$9 = pal().muted, _v$0 = {
                        fg: pal().muted
                      };
                      _v$9 !== _p$.e && (_p$.e = _$setProp(_el$53, "fg", _v$9, _p$.e));
                      _v$0 !== _p$.t && (_p$.t = _$setProp(_el$54, "style", _v$0, _p$.t));
                      return _p$;
                    }, {
                      e: void 0,
                      t: void 0
                    });
                    return _el$53;
                  }
                }), _$createComponent(Show, {
                  get when() {
                    return !balanceUnsupported();
                  },
                  get children() {
                    return [_$createComponent(Show, {
                      get when() {
                        return balanceState().status === "idle";
                      },
                      get children() {
                        var _el$57 = _$createElement("text"), _el$58 = _$createElement("span"), _el$60 = _$createElement("span");
                        _$insertNode(_el$57, _el$58);
                        _$insertNode(_el$57, _el$60);
                        _$insertNode(_el$58, _$createTextNode(`> `));
                        _$insert(_el$60, () => t("balNoKey", {
                          p: providerName()
                        }));
                        _$effect((_p$) => {
                          var _v$1 = pal().muted, _v$10 = {
                            fg: pal().muted
                          };
                          _v$1 !== _p$.e && (_p$.e = _$setProp(_el$57, "fg", _v$1, _p$.e));
                          _v$10 !== _p$.t && (_p$.t = _$setProp(_el$58, "style", _v$10, _p$.t));
                          return _p$;
                        }, {
                          e: void 0,
                          t: void 0
                        });
                        return _el$57;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return balanceState().status === "loading";
                      },
                      get children() {
                        var _el$61 = _$createElement("text"), _el$62 = _$createElement("span"), _el$64 = _$createElement("span");
                        _$insertNode(_el$61, _el$62);
                        _$insertNode(_el$61, _el$64);
                        _$insertNode(_el$62, _$createTextNode(`> `));
                        _$insert(_el$64, () => t("balLoading"));
                        _$effect((_p$) => {
                          var _v$11 = pal().muted, _v$12 = {
                            fg: pal().muted
                          };
                          _v$11 !== _p$.e && (_p$.e = _$setProp(_el$61, "fg", _v$11, _p$.e));
                          _v$12 !== _p$.t && (_p$.t = _$setProp(_el$62, "style", _v$12, _p$.t));
                          return _p$;
                        }, {
                          e: void 0,
                          t: void 0
                        });
                        return _el$61;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return balanceState().status === "error";
                      },
                      get children() {
                        var _el$65 = _$createElement("text"), _el$66 = _$createElement("span"), _el$68 = _$createElement("span");
                        _$insertNode(_el$65, _el$66);
                        _$insertNode(_el$65, _el$68);
                        _$insertNode(_el$66, _$createTextNode(`> `));
                        _$insert(_el$68, () => {
                          const code = balanceState().error;
                          if (code === "401") return t("balErr401");
                          if (code === "403") return t("balErr403");
                          if (code === "EMPTY") return t("balErrEmpty");
                          if (code === "TIMEOUT") return t("balErrTimeout");
                          return t("balError") + (code ? ` (${code})` : "");
                        });
                        _$effect((_p$) => {
                          var _v$13 = pal().error, _v$14 = {
                            fg: pal().muted
                          };
                          _v$13 !== _p$.e && (_p$.e = _$setProp(_el$65, "fg", _v$13, _p$.e));
                          _v$14 !== _p$.t && (_p$.t = _$setProp(_el$66, "style", _v$14, _p$.t));
                          return _p$;
                        }, {
                          e: void 0,
                          t: void 0
                        });
                        return _el$65;
                      }
                    }), _$createComponent(Show, {
                      get when() {
                        return _$memo(() => balanceState().status === "ok")() && balanceState().data;
                      },
                      get children() {
                        var _el$69 = _$createElement("text");
                        _$insert(_el$69, () => justify(t("balTotal"), formatBalanceText(balanceState().data, balanceCurrency(), exchangeRate())));
                        _$effect((_$p) => _$setProp(_el$69, "fg", pal().text, _$p));
                        return _el$69;
                      }
                    })];
                  }
                })];
              }
            })];
          }
        })];
      }
    }), null);
    _$effect((_p$) => {
      var _v$15 = {
        fg: pal().muted
      }, _v$16 = {
        fg: pal().primary
      };
      _v$15 !== _p$.e && (_p$.e = _$setProp(_el$3, "style", _v$15, _p$.e));
      _v$16 !== _p$.t && (_p$.t = _$setProp(_el$4, "style", _v$16, _p$.t));
      return _p$;
    }, {
      e: void 0,
      t: void 0
    });
    return _el$;
  })();
}
var PATH_CHROME = 2;
var HIDE_PATH_BELOW = 14;
function keyShortcut(api, command, fallback) {
  try {
    const binds = api.tuiConfig.keybinds.get(command);
    const seq = binds?.map((b) => ({
      key: b.key
    }));
    const s = api.keys.formatBindings(seq);
    return s || fallback;
  } catch {
    return fallback;
  }
}
function BottomStatusBar(props) {
  const KV_PREFIX = "cache_panel";
  const t = createT(() => props.signals.langCode());
  const sid = props.sessionId;
  const stats = createMemo(() => {
    const id = sid;
    if (!id) return null;
    const msgs = props.api.state.session.messages(id);
    const session = typeof props.api.state.session.get === "function" ? props.api.state.session.get(id) : void 0;
    let input = session?.tokens?.input ?? 0;
    let read = session?.tokens?.cache?.read ?? 0;
    let write = session?.tokens?.cache?.write ?? 0;
    if (session?.tokens == null) {
      for (const m of msgs) {
        if (m.role !== "assistant") continue;
        const tk = m.tokens;
        if (!tk) continue;
        input += num(tk.input);
        read += num(tk.cache?.read);
        write += num(tk.cache?.write);
      }
    }
    let hitRate = -1, prevHitRate = -1;
    for (let i = msgs.length - 1; i >= 0; i--) {
      const m = msgs[i];
      if (m.role !== "assistant") continue;
      const tk = m.tokens;
      if (!tk) continue;
      const mit = num(tk.input) + num(tk.cache?.read) + num(tk.cache?.write);
      const mrt = num(tk.cache?.read);
      if (mit <= 0) continue;
      const rate = mrt / mit * 100;
      if (hitRate < 0) {
        hitRate = rate;
        continue;
      }
      prevHitRate = rate;
      break;
    }
    return {
      hitRate,
      prevHitRate,
      input,
      read,
      write
    };
  });
  createEffect(() => {
    if (!props.signals.autoBalance()) return;
    const id = sid;
    if (!id) return;
    const msgs = props.api.state.session.messages(id);
    let pid = "";
    for (let i = msgs.length - 1; i >= 0; i--) {
      const m = msgs[i];
      if (m.role === "assistant" && m.providerID) {
        pid = m.providerID;
        break;
      }
    }
    if (!pid) {
      try {
        pid = props.api.state.session.get(id)?.model?.providerID ?? "";
      } catch {
      }
    }
    if (!pid) return;
    const hit = matchBalanceProvider(pid);
    if (hit) {
      props.signals.setBalanceUnsupported(false);
      if (hit.id !== props.signals.balanceProviderId()) {
        props.signals.setBalanceProviderId(hit.id);
        props.signals.setBalanceRefresh(props.signals.balanceRefresh() + 1);
      }
    } else {
      props.signals.setBalanceUnsupported(true);
    }
  });
  const pal = createMemo(() => {
    const th = props.api.theme.current;
    const sat = (k, fb) => desaturateTo(th[k], MAX_SAT, fb);
    return {
      text: sat("text", FALLBACK.text),
      muted: sat("textMuted", FALLBACK.muted),
      success: sat("success", FALLBACK.success),
      warning: sat("warning", FALLBACK.warning),
      error: sat("error", FALLBACK.error)
    };
  });
  const hitColor = createMemo(() => {
    const r = stats()?.hitRate ?? -1;
    if (r >= 85) return pal().success;
    if (r >= 70) return pal().warning;
    return pal().error;
  });
  const trend = createMemo(() => {
    const s = stats();
    if (!s || s.prevHitRate < 0 || s.hitRate < 0) return null;
    const d = s.hitRate - s.prevHitRate;
    return Math.abs(d) < 0.05 ? null : d;
  });
  const balanceText = createMemo(() => {
    const s = props.signals.balanceState();
    if (s.status === "ok" && s.data) return formatBalanceText(s.data, props.signals.balanceCurrency(), props.signals.exchangeRate());
    if (s.status === "loading") return "\u2026";
    if (s.status === "error") return "\u26A0";
    return "-";
  });
  const directory = createMemo(() => {
    try {
      return props.api.state.path.directory;
    } catch {
      return "";
    }
  });
  const [termW, setTermW] = createSignal(props.api.renderer.terminalWidth);
  createEffect(() => {
    const r = props.api.renderer;
    if (typeof r.on !== "function" || typeof r.off !== "function") return;
    const onResize = () => setTermW(props.api.renderer.terminalWidth);
    r.on("resize", onResize);
    onCleanup(() => r.off("resize", onResize));
  });
  createEffect(() => {
    const timer = setInterval(() => setTermW(props.api.renderer.terminalWidth), 500);
    onCleanup(() => clearInterval(timer));
  });
  const statsSegs = createMemo(() => {
    const s = stats();
    const hr = s && s.hitRate >= 0 ? (Math.floor(s.hitRate * 10) / 10).toFixed(1) + "%" : "--";
    const segs = [{
      text: t("barHit") + " ",
      color: pal().muted
    }, {
      text: hr,
      color: hitColor()
    }];
    const tr = trend();
    if (tr !== null) {
      segs.push({
        text: " " + (tr > 0 ? "\u2191" : "\u2193") + Math.abs(tr).toFixed(1) + "%",
        color: tr > 0 ? pal().success : pal().error
      });
    }
    segs.push({
      text: " \xB7 " + t("barTok") + " ",
      color: pal().muted
    });
    segs.push({
      text: s ? fmtCompact(s.input + s.read + s.write) : "--",
      color: pal().text
    });
    if (!props.signals.balanceUnsupported()) {
      segs.push({
        text: " \xB7 " + t("barBal") + " ",
        color: pal().muted
      });
      segs.push({
        text: balanceText(),
        color: pal().text
      });
    }
    segs.push({
      text: " \xB7 ",
      color: pal().muted
    });
    return segs;
  });
  const statsW = createMemo(() => {
    let w = 0;
    for (const sg of statsSegs()) w += visualWidth(sg.text);
    return w;
  });
  const sessionCost = createMemo(() => {
    try {
      return num(props.api.state.session.get(sid)?.cost);
    } catch {
      return 0;
    }
  });
  const usageText = createMemo(() => {
    const id = sid;
    if (!id) return "";
    const msgs = props.api.state.session.messages(id);
    let last;
    for (let i = msgs.length - 1; i >= 0; i--) {
      const m = msgs[i];
      if (m.role !== "assistant") continue;
      const tk2 = m.tokens;
      if (tk2 && num(tk2.output) > 0) {
        last = m;
        break;
      }
    }
    if (!last) return "";
    const tk = last.tokens;
    if (!tk) return "";
    const tokens = num(tk.input) + num(tk.output) + num(tk.reasoning) + num(tk.cache?.read) + num(tk.cache?.write);
    if (tokens <= 0) return "";
    let pct = "";
    try {
      const p = props.api.state.provider.find((x) => x.id === last.providerID);
      const limit = p?.models?.[last.modelID]?.limit?.context;
      if (typeof limit === "number" && limit > 0) pct = ` (${Math.round(tokens / limit * 100)}%)`;
    } catch {
    }
    const context = fmtCompact(tokens) + pct;
    const cost = sessionCost();
    return cost > 0 ? context + " \xB7 " + fmtCost(cost) : context;
  });
  const rightText = createMemo(() => {
    const cmds = keyShortcut(props.api, "command.palette.show", "ctrl+p") + " commands";
    const u = usageText();
    if (u) return u + " " + cmds;
    return keyShortcut(props.api, "agent.cycle", "") + " agents " + cmds;
  });
  const rightW = createMemo(() => visualWidth(rightText()));
  const inputW = createMemo(() => termW() - (props.signals.sidebarVisible() ? 42 : 0) - 4);
  const dirDisplay = createMemo(() => {
    const avail = inputW() - statsW() - rightW() - PATH_CHROME;
    if (avail < HIDE_PATH_BELOW) return "";
    return truncateVisual(directory(), avail);
  });
  const dirFallback = createMemo(() => {
    const avail = inputW() - rightW() - PATH_CHROME;
    if (avail < HIDE_PATH_BELOW) return "";
    return truncateVisual(directory(), avail);
  });
  onMount(() => {
    try {
      const v = props.api.kv.get(`${KV_PREFIX}.section.bottom`, true);
      props.signals.setSectionBottom(v !== false);
    } catch {
    }
  });
  return _$createComponent(Show, {
    get when() {
      return props.signals.sectionBottom();
    },
    get fallback() {
      return (() => {
        var _el$101 = _$createElement("text");
        _$insert(_el$101, dirFallback);
        _$effect((_$p) => _$setProp(_el$101, "fg", pal().muted, _$p));
        return _el$101;
      })();
    },
    get children() {
      var _el$97 = _$createElement("box"), _el$98 = _$createElement("text"), _el$99 = _$createElement("box"), _el$100 = _$createElement("text");
      _$insertNode(_el$97, _el$98);
      _$insertNode(_el$97, _el$99);
      _$setProp(_el$97, "marginLeft", 1);
      _$setProp(_el$97, "flexGrow", 1);
      _$setProp(_el$97, "flexShrink", 0);
      _$setProp(_el$97, "flexDirection", "row");
      _$setProp(_el$97, "justifyContent", "space-between");
      _$insert(_el$98, dirDisplay);
      _$insertNode(_el$99, _el$100);
      _$setProp(_el$99, "flexDirection", "row");
      _$insert(_el$100, _$createComponent(For, {
        get each() {
          return statsSegs();
        },
        children: (sg) => (() => {
          var _el$102 = _$createElement("span");
          _$insert(_el$102, () => sg.text);
          _$effect((_$p) => _$setProp(_el$102, "style", {
            fg: sg.color
          }, _$p));
          return _el$102;
        })()
      }));
      _$effect((_$p) => _$setProp(_el$98, "fg", pal().muted, _$p));
      return _el$97;
    }
  });
}
function createSidebarSlot(api, signals) {
  let lastSlotSid = "";
  return {
    order: 55,
    slots: {
      sidebar_content(ctx, input) {
        if (input.session_id !== lastSlotSid) {
          lastSlotSid = input.session_id;
          if (signals.overrideSessionId()) {
            signals.setOverrideSessionId(void 0);
            api.kv.set("cache_panel.session", "");
          }
        }
        return _$createComponent(TokenCachePanel, {
          get theme() {
            return ctx.theme.current;
          },
          api,
          get sessionId() {
            return input.session_id;
          },
          signals
        });
      }
    }
  };
}
var tui = async (api) => {
  const [currencySymbol, setCurrencySymbol] = createSignal("$");
  const [exchangeRate, setExchangeRate] = createSignal(1);
  const [sectionDetail, setSectionDetail] = createSignal(true);
  const [sectionModel, setSectionModel] = createSignal(true);
  const [sectionDist, setSectionDist] = createSignal(true);
  const [sectionSkills, setSectionSkills] = createSignal(true);
  const [sectionBalance, setSectionBalance] = createSignal(true);
  const [sectionBottom, setSectionBottom] = createSignal(true);
  const [balanceRefresh, setBalanceRefresh] = createSignal(0);
  const [balanceProviderId, setBalanceProviderId] = createSignal("deepseek");
  const [autoBalance, setAutoBalance] = createSignal(true);
  const [balanceUnsupported, setBalanceUnsupported] = createSignal(false);
  const [balanceCurrency, setBalanceCurrency] = createSignal("");
  const [borderVisible, setBorderVisible] = createSignal(true);
  const [langCode, setLangCode] = createSignal(INIT_LANG);
  const [overrideSessionId, setOverrideSessionId] = createSignal(void 0);
  const [sidebarVisible, setSidebarVisible] = createSignal(false);
  const [balanceState, setBalanceState] = createSignal({
    status: "idle",
    data: null,
    lastFetch: 0
  });
  let balanceSeq = 0;
  const signals = {
    currencySymbol,
    setCurrencySymbol,
    exchangeRate,
    setExchangeRate,
    langCode,
    setLangCode,
    sectionDetail,
    setSectionDetail,
    sectionModel,
    setSectionModel,
    sectionDist,
    setSectionDist,
    sectionSkills,
    setSectionSkills,
    sectionBalance,
    setSectionBalance,
    sectionBottom,
    setSectionBottom,
    balanceRefresh,
    setBalanceRefresh,
    balanceProviderId,
    setBalanceProviderId,
    autoBalance,
    setAutoBalance,
    balanceUnsupported,
    setBalanceUnsupported,
    balanceState,
    balanceCurrency,
    setBalanceCurrency,
    borderVisible,
    setBorderVisible,
    overrideSessionId,
    setOverrideSessionId,
    sidebarVisible,
    setSidebarVisible
  };
  api.slots.register(createSidebarSlot(api, signals));
  api.slots.register({
    order: 55,
    slots: {
      session_prompt(_ctx, input) {
        return _$createComponent(api.ui.Prompt, {
          get sessionID() {
            return input.session_id;
          },
          get visible() {
            return input.visible;
          },
          get disabled() {
            return input.disabled;
          },
          get onSubmit() {
            return input.on_submit;
          },
          ref(r$) {
            var _ref$2 = input.ref;
            typeof _ref$2 === "function" ? _ref$2(r$) : input.ref = r$;
          },
          get hint() {
            return _$createComponent(BottomStatusBar, {
              api,
              signals,
              get sessionId() {
                return input.session_id;
              }
            });
          }
        });
      }
    }
  });
  const KV_PREFIX = "cache_panel";
  const restoreLang = () => {
    try {
      const saved = api.kv.get(`${KV_PREFIX}.lang`);
      if (saved && LANG_META.some((m) => m.code === saved)) setLangCode(saved);
    } catch {
    }
  };
  if (api.kv.ready) {
    restoreLang();
  } else {
    const langTimer = setInterval(() => {
      if (api.kv.ready) {
        clearInterval(langTimer);
        restoreLang();
      }
    }, 10);
    api.lifecycle.onDispose(() => clearInterval(langTimer));
  }
  const pollBalance = async () => {
    const provider = getBalanceProvider(balanceProviderId());
    const key = api.kv.get(`${KV_PREFIX}.balance.${provider.id}.key`, "") || findOpencodeKey(api, provider);
    if (balanceUnsupported()) {
      setBalanceState({
        status: "idle",
        data: null,
        lastFetch: 0,
        error: void 0,
        key: void 0
      });
      return;
    }
    if (!key) {
      setBalanceState({
        status: "idle",
        data: null,
        lastFetch: 0,
        error: void 0,
        key: void 0
      });
      return;
    }
    const now = Date.now();
    const prev = balanceState();
    if (prev.status === "ok" && prev.key === key && now - prev.lastFetch < BALANCE_POLL_MS) return;
    const seq = ++balanceSeq;
    setBalanceState({
      ...prev,
      status: "loading",
      error: void 0,
      key
    });
    const controller = new AbortController();
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, 1e4);
    try {
      const data = await provider.fetchBalance(key, controller.signal);
      clearTimeout(timer);
      if (seq !== balanceSeq) return;
      setBalanceState({
        status: "ok",
        data,
        lastFetch: Date.now(),
        error: void 0,
        key
      });
    } catch (err) {
      clearTimeout(timer);
      if (seq !== balanceSeq) return;
      const code = timedOut ? "TIMEOUT" : err instanceof Error ? err.message : "";
      setBalanceState({
        status: "error",
        data: null,
        lastFetch: 0,
        error: code,
        key
      });
    }
  };
  createEffect(() => {
    void balanceRefresh();
    untrack(() => {
      void pollBalance();
    });
  });
  const balanceTimer = setInterval(pollBalance, BALANCE_POLL_MS);
  api.lifecycle.onDispose(() => clearInterval(balanceTimer));
  const providerOptionTitle = (p, current) => {
    const t = createT(() => langCode());
    const hasManual = !!api.kv.get(`${KV_PREFIX}.balance.${p.id}.key`, "");
    const hasAuto = !hasManual && !!findOpencodeKey(api, p);
    const mark = hasManual ? t("keyUser") : hasAuto ? t("keyOpenCode") : t("keyNotSet");
    return p.name + mark + (current && p.id === current ? " *" : "");
  };
  const promptBalanceKey = (dialog, provider) => {
    const t = createT(() => langCode());
    const current = api.kv.get(`${KV_PREFIX}.balance.${provider.id}.key`, "");
    const masked = maskKey(current);
    dialog?.replace(() => _$createComponent(api.ui.DialogPrompt, {
      get title() {
        return provider.name;
      },
      description: () => (() => {
        var _el$103 = _$createElement("text");
        _$insert(_el$103, () => t("balKeyPrompt", {
          p: provider.name
        }));
        return _el$103;
      })(),
      get placeholder() {
        return provider.keyPlaceholder ?? "sk-...";
      },
      value: masked,
      onConfirm: (val) => {
        const input = val.trim();
        let key;
        if (input === "") {
          key = "";
        } else if (input.includes("*")) {
          key = current;
        } else {
          key = input;
        }
        api.kv.set(`${KV_PREFIX}.balance.${provider.id}.key`, key);
        setBalanceRefresh((v) => v + 1);
        if (key) {
          api.ui.toast({
            message: t("keySaved")
          });
        } else {
          api.ui.toast({
            message: t("keyCleared")
          });
        }
        dialog?.clear();
      },
      onCancel: () => dialog?.clear()
    }));
  };
  api.command?.register(() => [{
    title: "Cache: Set Currency",
    value: "cache.currency",
    description: "Change the currency unit for cost display",
    slash: {
      name: "cache-currency"
    },
    onSelect: (dialog) => {
      dialog?.replace(() => _$createComponent(api.ui.DialogSelect, {
        title: "Select Currency",
        get options() {
          return Object.entries(CURRENCIES).map(([code, sym]) => ({
            title: `${code}  (${sym})`,
            value: code
          }));
        },
        onSelect: (opt) => {
          const t = createT(() => langCode());
          const sym = CURRENCIES[opt.value] ?? "$";
          const defRate = DEFAULT_RATES[opt.value] ?? 1;
          api.kv.set(`${KV_PREFIX}.currency`, sym);
          api.kv.set(`${KV_PREFIX}.rate`, defRate);
          api.kv.set(`${KV_PREFIX}.balance_currency`, opt.value);
          signals.setBalanceCurrency(opt.value);
          signals.setCurrencySymbol(sym);
          signals.setExchangeRate(defRate);
          api.ui.toast({
            message: t("currencySet", {
              v: opt.value,
              s: sym,
              r: defRate
            })
          });
          dialog?.clear();
        }
      }));
    }
  }, {
    title: "Cache: Set Exchange Rate",
    value: "cache.rate",
    description: "Set the exchange rate multiplier for the selected currency",
    slash: {
      name: "cache-rate"
    },
    onSelect: (dialog) => {
      dialog?.replace(() => _$createComponent(api.ui.DialogPrompt, {
        title: "Exchange Rate",
        description: () => (() => {
          var _el$104 = _$createElement("text");
          _$insertNode(_el$104, _$createTextNode(`Enter the exchange rate from USD to your currency (e.g. 7.2 for CNY)`));
          return _el$104;
        })(),
        placeholder: "1.0",
        get value() {
          return String(api.kv.get(`${KV_PREFIX}.rate`, 1));
        },
        onConfirm: (val) => {
          const t = createT(() => langCode());
          const n = parseFloat(val);
          if (n > 0) {
            api.kv.set(`${KV_PREFIX}.rate`, n);
            signals.setExchangeRate(n);
            api.ui.toast({
              message: t("rateSet", {
                r: n
              })
            });
          }
          dialog?.clear();
        }
      }));
    }
  }, {
    title: "Cache: Toggle Section",
    value: "cache.section",
    description: "Show or hide a sidebar section",
    slash: {
      name: "cache-section"
    },
    onSelect: (dialog) => {
      const t = createT(() => langCode());
      const detailOn = Boolean(api.kv.get(`${KV_PREFIX}.section.detail`, true));
      const modelOn = Boolean(api.kv.get(`${KV_PREFIX}.section.model`, true));
      const distOn = Boolean(api.kv.get(`${KV_PREFIX}.section.dist`, true));
      const skillsOn = Boolean(api.kv.get(`${KV_PREFIX}.section.skills`, true));
      const balanceOn = Boolean(api.kv.get(`${KV_PREFIX}.section.balance`, true));
      const bottomOn = Boolean(api.kv.get(`${KV_PREFIX}.section.bottom`, true));
      const borderOn = Boolean(api.kv.get(`${KV_PREFIX}.border`, true));
      const labels = {
        detail: t("secDetail"),
        model: t("secModel"),
        dist: t("distTitle"),
        skills: t("secSkills"),
        balance: t("secBalance"),
        bottom: t("secBottom"),
        border: t("secBorder")
      };
      const optTitle = (label, on) => `${visualPadEnd(label, 15)}[${on ? "ON" : "OFF"}]`;
      dialog?.replace(() => _$createComponent(api.ui.DialogSelect, {
        get title() {
          return t("secToggle");
        },
        get options() {
          return [{
            title: optTitle(labels.detail, detailOn),
            value: "detail"
          }, {
            title: optTitle(labels.model, modelOn),
            value: "model"
          }, {
            title: optTitle(labels.dist, distOn),
            value: "dist"
          }, {
            title: optTitle(labels.skills, skillsOn),
            value: "skills"
          }, {
            title: optTitle(labels.balance, balanceOn),
            value: "balance"
          }, {
            title: optTitle(labels.bottom, bottomOn),
            value: "bottom"
          }, {
            title: optTitle(labels.border, borderOn),
            value: "border"
          }];
        },
        onSelect: (opt) => {
          if (opt.value === "border") {
            const cur = Boolean(api.kv.get(`${KV_PREFIX}.border`, true));
            api.kv.set(`${KV_PREFIX}.border`, !cur);
            signals.setBorderVisible(!cur);
            api.ui.toast({
              message: !cur ? t("borderShown") : t("borderHidden")
            });
          } else {
            const key = `${KV_PREFIX}.section.${opt.value}`;
            const cur = Boolean(api.kv.get(key, true));
            api.kv.set(key, !cur);
            if (opt.value === "detail") signals.setSectionDetail(!cur);
            if (opt.value === "model") signals.setSectionModel(!cur);
            if (opt.value === "dist") signals.setSectionDist(!cur);
            if (opt.value === "skills") signals.setSectionSkills(!cur);
            if (opt.value === "balance") signals.setSectionBalance(!cur);
            if (opt.value === "bottom") signals.setSectionBottom(!cur);
            const name = labels[opt.value] ?? opt.value;
            api.ui.toast({
              message: t(!cur ? "sectionShown" : "sectionHidden", {
                s: name
              })
            });
          }
          dialog?.clear();
        }
      }));
    }
  }, {
    title: "Cache: Show Config",
    value: "cache.config",
    description: "Display the current plugin configuration",
    slash: {
      name: "cache-config"
    },
    onSelect: (dialog) => {
      const t = createT(() => langCode());
      const sym = api.kv.get(`${KV_PREFIX}.currency`) ?? "$";
      const rate = api.kv.get(`${KV_PREFIX}.rate`) ?? 1;
      const detail = Boolean(api.kv.get(`${KV_PREFIX}.section.detail`, true));
      const model = Boolean(api.kv.get(`${KV_PREFIX}.section.model`, true));
      const dist = Boolean(api.kv.get(`${KV_PREFIX}.section.dist`, true));
      const skills = Boolean(api.kv.get(`${KV_PREFIX}.section.skills`, true));
      const balance = Boolean(api.kv.get(`${KV_PREFIX}.section.balance`, true));
      const bottom = Boolean(api.kv.get(`${KV_PREFIX}.section.bottom`, true));
      const on = (v) => v ? "ON" : "OFF";
      api.ui.toast({
        title: t("panelConfigTitle"),
        message: t("panelConfigMsg", {
          c: sym,
          r: rate,
          d: on(detail),
          m: on(model),
          t: on(dist),
          k: on(skills),
          b: on(balance),
          f: on(bottom)
        }),
        duration: 8e3
      });
      dialog?.clear();
    }
  }, {
    title: "Cache: Switch Language",
    value: "cache.lang",
    description: "Switch between Chinese and English display",
    slash: {
      name: "cache-lang"
    },
    onSelect: (dialog) => {
      const t = createT(() => langCode());
      const cur = langCode();
      dialog?.replace(() => _$createComponent(api.ui.DialogSelect, {
        get title() {
          return t("langTitle");
        },
        get options() {
          return LANG_META.map((m) => ({
            title: `${visualPadEnd(m.label, 9)}${cur === m.code ? "\u2713" : ""}`,
            value: m.code
          }));
        },
        onSelect: (opt) => {
          const code = opt.value;
          api.kv.set(`${KV_PREFIX}.lang`, code);
          setLangCode(code);
          api.ui.toast({
            message: t("langSwitched")
          });
          dialog?.clear();
        }
      }));
    }
  }, {
    title: "Cache: Switch Balance Provider",
    value: "cache.balance",
    description: "\u5207\u6362\u4F59\u989D\u63D0\u4F9B\u5546 / \u81EA\u52A8\u5207\u6362\u5F53\u524D\u4F1A\u8BDD\u63D0\u4F9B\u5546 | Switch balance provider / auto-switch session provider",
    slash: {
      name: "cache-balance"
    },
    onSelect: (dialog) => {
      const t = createT(() => langCode());
      const current = signals.balanceProviderId();
      const auto = signals.autoBalance();
      const autoLabel = `${t("autoSwitchOpt")} [${auto ? "ON" : "OFF"}]`;
      dialog?.replace(() => _$createComponent(api.ui.DialogSelect, {
        get title() {
          return t("balProvTitle");
        },
        get options() {
          return [{
            title: autoLabel,
            value: "__auto__"
          }, ...balanceProviders.map((p) => ({
            title: providerOptionTitle(p, current),
            value: p.id
          }))];
        },
        onSelect: (opt) => {
          if (opt.value === "__auto__") {
            const next = !auto;
            api.kv.set(`${KV_PREFIX}.balance.auto`, next);
            signals.setAutoBalance(next);
            api.ui.toast({
              message: next ? t("autoSwitchOn") : t("autoSwitchOff")
            });
            dialog?.clear();
          } else {
            const provider = getBalanceProvider(opt.value);
            api.kv.set(`${KV_PREFIX}.balance.provider`, provider.id);
            api.kv.set(`${KV_PREFIX}.balance.auto`, false);
            signals.setBalanceProviderId(provider.id);
            signals.setAutoBalance(false);
            signals.setBalanceUnsupported(false);
            signals.setBalanceRefresh(signals.balanceRefresh() + 1);
            const hasKey = !!api.kv.get(`${KV_PREFIX}.balance.${provider.id}.key`, "");
            if (!hasKey) {
              promptBalanceKey(dialog, provider);
            } else {
              api.ui.toast({
                message: t("providerManual", {
                  p: provider.name
                })
              });
              dialog?.clear();
            }
          }
        }
      }));
    }
  }, {
    title: "Cache: Set Balance API Key",
    value: "cache.balance.key",
    description: "Select a provider and set its API key for balance display",
    slash: {
      name: "cache-balance-key"
    },
    onSelect: (dialog) => {
      const t = createT(() => langCode());
      dialog?.replace(() => _$createComponent(api.ui.DialogSelect, {
        get title() {
          return t("balSelectTitle");
        },
        get options() {
          return balanceProviders.map((p) => ({
            title: providerOptionTitle(p),
            value: p.id
          }));
        },
        onSelect: (opt) => {
          const provider = getBalanceProvider(opt.value);
          api.kv.set(`${KV_PREFIX}.balance.provider`, provider.id);
          api.kv.set(`${KV_PREFIX}.balance.auto`, false);
          signals.setBalanceProviderId(provider.id);
          signals.setAutoBalance(false);
          signals.setBalanceRefresh(signals.balanceRefresh() + 1);
          promptBalanceKey(dialog, provider);
        }
      }));
    }
  }, {
    title: "Cache: Debug Skills Detection",
    value: "cache.debug-skills",
    description: "Dump all tool parts found in the current session for skill detection debugging",
    slash: {
      name: "cache-debug-skills"
    },
    onSelect: () => {
      const t = createT(() => langCode());
      const rt = api.route.current;
      if (rt.name !== "session" || !rt.params) {
        api.ui.toast({
          message: t("runInSession"),
          variant: "warning"
        });
        return;
      }
      const sid = String(rt.params.sessionID);
      const msgs = api.state.session.messages(sid);
      const byTool = {};
      const skillParts = [];
      for (const msg of msgs) {
        if (msg.role !== "assistant") continue;
        let parts = [];
        try {
          parts = api.state.part(msg.id);
        } catch {
        }
        for (const p of parts) {
          if (p.type === "tool") {
            const t2 = String(p.tool ?? "?");
            byTool[t2] = (byTool[t2] ?? 0) + 1;
            if (t2 === "skill") {
              const meta = p.state?.metadata;
              const rootMeta = p.metadata;
              skillParts.push(`state.metadata=${JSON.stringify(meta)} | root.metadata=${JSON.stringify(rootMeta)} | state.title="${p.state?.title}" | state.output[:80]="${String(p.state?.output ?? "").slice(0, 80)}"`);
            }
          }
        }
      }
      const summary = Object.entries(byTool).map(([k, v]) => `${k}: ${v}`).join(" | ");
      const extra = skillParts.length > 0 ? "\n\nSkill parts:\n" + skillParts.join("\n") : "\n\n\u26A0 No skill tool parts found \u2014 AI may be reading SKILL.md instead. Try: 'Use the skill tool to load karpathy-guidelines'";
      api.ui.toast({
        title: `Tool Summary (${Object.keys(byTool).length} types)`,
        message: summary + extra,
        duration: 15e3
      });
    }
  }, {
    title: "Cache: Sub-Agent Stats",
    value: "cache.session",
    description: "View token cache statistics for a sub-agent by session ID",
    slash: {
      name: "cache-session"
    },
    onSelect: (dialog) => {
      const rt = api.route.current;
      const parentSid = rt.name === "session" && rt.params ? String(rt.params.sessionID) : "";
      const SUBAGENT_TOOLS = /* @__PURE__ */ new Set(["task", "delegate", "call_omo_agent"]);
      const children = [];
      if (parentSid) {
        try {
          const msgs = api.state.session.messages(parentSid);
          for (const msg of msgs) {
            if (msg.role !== "assistant") continue;
            let parts = [];
            try {
              parts = api.state.part(msg.id);
            } catch {
            }
            for (const p of parts) {
              if (p.type !== "tool") continue;
              const tool = String(p.tool ?? "");
              if (!SUBAGENT_TOOLS.has(tool)) continue;
              const st = p.state;
              const stMeta = st?.metadata;
              const subSid = stMeta?.session_id ?? stMeta?.sessionId;
              if (!subSid) continue;
              const sidStr = String(subSid);
              const input = st?.input;
              const agent = String(p.subagent_type ?? input?.subagent_type ?? input?.category ?? tool);
              const prompt = String(input?.prompt ?? "");
              const desc = input?.description ? String(input.description) : "";
              const title = desc || prompt.replace(/\n/g, " ").replace(/\s+/g, " ").trim().slice(0, 40) || agent;
              children.push({
                title,
                value: sidStr,
                description: `${agent} \xB7 ${sidStr.slice(0, 24)}\u2026`
              });
            }
          }
        } catch {
        }
      }
      const seen = /* @__PURE__ */ new Set();
      const unique = children.filter((c) => {
        if (seen.has(c.value)) return false;
        seen.add(c.value);
        return true;
      });
      if (unique.length > 0) {
        const t = createT(() => langCode());
        const currentSid = signals.overrideSessionId() ?? api.kv.get(`${KV_PREFIX}.session`, "");
        const options = unique.map((c, i) => ({
          title: `${i + 1}. ${c.title}`,
          value: c.value,
          description: c.description
        }));
        const backValue = "__main__";
        const backTitle = `\u2500 ${t("backToMainTitle")}`;
        options.unshift({
          title: backTitle,
          value: backValue,
          description: ""
        });
        options.push({
          title: backTitle,
          value: backValue,
          description: ""
        });
        const currentIdx = currentSid ? options.findIndex((o) => o.value === currentSid) : -1;
        dialog?.replace(() => _$createComponent(api.ui.DialogSelect, {
          get title() {
            return t("subSelectTitle");
          },
          options,
          get current() {
            return currentIdx >= 0 ? options[currentIdx].value : void 0;
          },
          onSelect: (opt) => {
            if (opt.value === backValue) {
              signals.setOverrideSessionId(void 0);
              api.kv.set(`${KV_PREFIX}.session`, "");
              api.ui.toast({
                message: t("backToMain")
              });
            } else {
              signals.setOverrideSessionId(opt.value);
              api.kv.set(`${KV_PREFIX}.session`, opt.value);
              api.ui.toast({
                message: t("subAgentSwitched", {
                  s: opt.value.slice(0, 24) + "\u2026"
                })
              });
            }
            dialog?.clear();
          }
        }));
      } else {
        const t = createT(() => langCode());
        dialog?.replace(() => _$createComponent(api.ui.DialogPrompt, {
          get title() {
            return _$memo(() => !!signals.overrideSessionId())() ? t("subSwitchTitle") : t("subViewTitle");
          },
          description: () => (() => {
            var _el$106 = _$createElement("text");
            _$insert(_el$106, () => t("subNoFound"));
            return _el$106;
          })(),
          placeholder: "ses_...",
          get value() {
            return signals.overrideSessionId() ?? api.kv.get(`${KV_PREFIX}.session`, "") ?? "";
          },
          onConfirm: (val) => {
            const sid = val.trim();
            if (sid) {
              signals.setOverrideSessionId(sid);
              api.kv.set(`${KV_PREFIX}.session`, sid);
              api.ui.toast({
                message: t("subAgentSwitched", {
                  s: sid.slice(0, 24) + "\u2026"
                })
              });
            }
            dialog?.clear();
          },
          onCancel: () => dialog?.clear()
        }));
      }
    }
  }, {
    title: "Cache: Back to Main",
    value: "cache.session.back",
    description: "Return to main session stats",
    slash: {
      name: "cache-session-back"
    },
    onSelect: (dialog) => {
      const t = createT(() => langCode());
      signals.setOverrideSessionId(void 0);
      api.kv.set(`${KV_PREFIX}.session`, "");
      api.ui.toast({
        message: t("backToMain")
      });
      dialog?.clear();
    }
  }]);
};
var mod = {
  id: "opencode-visual-cache",
  tui
};
var index_default = mod;
export {
  index_default as default
};
