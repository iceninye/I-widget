// scriptable/i-widget.js 嘅測試：用假 Scriptable 環境執行，檢查各尺寸砌得出。
// 執行：node scriptable/test-i-widget.js
"use strict";

const fs = require("fs");
const path = require("path");

const SOURCE = fs.readFileSync(path.join(__dirname, "i-widget.js"), "utf8");
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

// ---- 假 Scriptable ----------------------------------------------------

class Color {
  constructor(hex, alpha = 1) { this.hex = hex; this.alpha = alpha; }
  static dynamic(light, dark) { return { dynamic: true, light, dark }; }
}
class Font {
  constructor(name, size) { this.name = name; this.size = size; }
  static systemFont(size) { return new Font("system", size); }
  static boldSystemFont(size) { return new Font("bold", size); }
  static semiboldSystemFont(size) { return new Font("semibold", size); }
}
class Size { constructor(width, height) { this.width = width; this.height = height; } }

class Element {
  constructor(kind) { this.kind = kind; this.children = []; }
  add(kind, init) { const el = new Element(kind); Object.assign(el, init); this.children.push(el); return el; }
  addText(string) { return this.add("text", { text: string }); }
  addDate(date) { return this.add("date", { date }); }
  addImage(image) { return this.add("image", { image }); }
  addSpacer(length) { return this.add("spacer", { length }); }
  addStack() { return this.add("stack", {}); }
  setPadding(...p) { this.padding = p; }
  layoutHorizontally() { this.layout = "h"; }
  layoutVertically() { this.layout = "v"; }
  centerAlignContent() { this.align = "center"; }
  centerAlignText() { this.textAlign = "center"; }
  leftAlignText() { this.textAlign = "left"; }
  applyTimerStyle() { this.style = "timer"; }
  applyTimeStyle() { this.style = "time"; }
  applyFittingContentMode() { this.fitting = true; }
}
class ListWidget extends Element {
  constructor() { super("widget"); this.presented = null; }
  async presentSmall() { this.presented = "small"; }
  async presentMedium() { this.presented = "medium"; }
  async presentLarge() { this.presented = "large"; }
  async presentExtraLarge() { this.presented = "extraLarge"; }
  async presentAccessoryInline() { this.presented = "accessoryInline"; }
  async presentAccessoryCircular() { this.presented = "accessoryCircular"; }
  async presentAccessoryRectangular() { this.presented = "accessoryRectangular"; }
}

function walk(el, fn) { fn(el); el.children.forEach((child) => walk(child, fn)); }
function all(el, pred) { const out = []; walk(el, (e) => pred(e) && out.push(e)); return out; }
function texts(el) { return all(el, (e) => e.kind === "text").map((e) => e.text); }

function run({ family = "large", now = new Date(2026, 9, 23, 14, 5, 30), device = {}, runsInWidget = true, noSymbols = false } = {}) {
  const state = { widget: null, completed: false, widgetObj: null };
  const dev = {
    batteryLevel: () => 0.75, isCharging: () => false, isFullyCharged: () => false,
    systemName: () => "iOS", systemVersion: () => "27.0.1", screenBrightness: () => 0.4,
    ...device,
  };
  const globals = {
    Color, Font, Size, ListWidget,
    SFSymbol: { named: (name) => (noSymbols ? null : { image: { symbol: name } }) },
    Device: dev,
    config: { widgetFamily: family === "app" ? null : family, runsInWidget },
    Script: { setWidget: (w) => { state.widget = w; }, complete: () => { state.completed = true; } },
    IWIDGET_NOW: now,
  };
  // 攔截 ListWidget，方便取返 widget 物件（in-app 模式用 present）
  globals.ListWidget = class extends ListWidget { constructor() { super(); state.widgetObj = this; } };
  const names = Object.keys(globals);
  const fn = new AsyncFunction(...names, SOURCE);
  return fn(...names.map((n) => globals[n])).then(() => state);
}

// ---- 測試框架 ----------------------------------------------------------

let pass = 0, fail = 0;
function check(name, cond, detail = "") {
  if (cond) { pass++; console.log(`  ✓  ${name}`); }
  else { fail++; console.log(`  ✗ FAIL  ${name}${detail ? "  → " + detail : ""}`); }
}

module.exports = { run, all, texts };

if (require.main === module) (async () => {
  console.log("\n【S】各尺寸都砌得出");
  for (const family of ["small", "medium", "large", "extraLarge", "accessoryInline", "accessoryCircular", "accessoryRectangular"]) {
    let state, error = null;
    try { state = await run({ family }); } catch (e) { error = e; }
    check(`S1 ${family} 冇 crash`, !error, error && error.stack);
    if (error) continue;
    check(`S2 ${family} setWidget + complete`, state.widget && state.completed);
    check(`S3 ${family} 有星期`, texts(state.widget).some((t) => t.includes("星期五")) || family === "accessoryCircular",
      JSON.stringify(texts(state.widget)));
  }

  console.log("\n【C】時鐘");
  let s = await run({ family: "large", now: new Date(2026, 9, 23, 14, 5, 30) });
  let clocks = all(s.widget, (e) => e.kind === "date");
  check("C1 日間用計時器樣式", clocks.length === 1 && clocks[0].style === "timer", JSON.stringify(clocks.map((c) => c.style)));
  check("C2 由今日 00:00 起數", clocks[0].date.getHours() === 0 && clocks[0].date.getMinutes() === 0 && clocks[0].date.getDate() === 23);
  check("C3 大尺寸字體 60", clocks[0].font.size === 60);
  s = await run({ family: "small", now: new Date(2026, 9, 23, 14, 5, 30) });
  check("C4 小尺寸字體 30", all(s.widget, (e) => e.kind === "date")[0].font.size === 30);
  s = await run({ family: "medium", now: new Date(2026, 9, 23, 14, 5, 30) });
  check("C5 中尺寸字體 50", all(s.widget, (e) => e.kind === "date")[0].font.size === 50);
  s = await run({ family: "large", now: new Date(2026, 9, 23, 0, 30, 0) });
  clocks = all(s.widget, (e) => e.kind === "date");
  check("C6 00:xx 唔用計時器（會顯示成分:秒）", clocks[0].style === "time");

  console.log("\n【R】reload 時間");
  const delay = async (now) => (await run({ family: "small", now })).widget.refreshAfterDate - now;
  check("R1 日間 30 分鐘", (await delay(new Date(2026, 9, 23, 14, 0, 0))) === 30 * 60000);
  check("R2 23:50 要趕 00:00:20", (await delay(new Date(2026, 9, 23, 23, 50, 0))) === 10 * 60000 + 20000);
  check("R3 00:40 要趕 01:00:20", (await delay(new Date(2026, 9, 23, 0, 40, 0))) === 20 * 60000 + 20000);
  check("R4 永遠喺未來", (await delay(new Date(2026, 9, 23, 0, 0, 20))) > 0);

  console.log("\n【L】大尺寸版面");
  s = await run({ family: "large" });
  const cards = s.widget.children.filter((e) => e.kind === "stack" && e.cornerRadius === 12);
  check("L1 4 張圓角資料卡", cards.length === 4, `${cards.length}`);
  check("L2 卡片有底色同邊距", cards.every((c) => c.backgroundColor && c.padding && c.padding[1] === 12));
  check("L3 每張卡有 Spacer（數值靠右）", cards.every((c) => c.children.some((k) => k.kind === "spacer")));
  const bars = all(s.widget, (e) => e.kind === "stack" && e.size && e.size.width === 70);
  check("L4 三條進度條（電量／亮度／今日）", bars.length === 3, `${bars.length}`);
  check("L5 電量 75%", texts(s.widget).includes("75%"));
  check("L6 有系統版本", texts(s.widget).includes("iOS 27.0.1"));
  check("L7 widget 背景同 padding", s.widget.backgroundColor && s.widget.padding.length === 4);
  const fills = all(s.widget, (e) => e.kind === "stack" && e.size && e.size.height === 6 && e.size.width !== 70);
  check("L8 進度條填充闊度跟比例", fills.some((f) => f.size.width === Math.round(70 * 0.75)), JSON.stringify(fills.map((f) => f.size.width)));

  console.log("\n【D】讀唔到資料／符號唔存在");
  s = await run({ family: "large", device: { batteryLevel: () => -1 } });
  check("D1 電量 -1 → 顯示 —，唔 crash", texts(s.widget).includes("—"));
  s = await run({ family: "large", device: { batteryLevel: () => { throw new Error("x"); }, systemVersion: () => { throw new Error("x"); } } });
  check("D2 Device 擲錯都出得到畫面", s.widget && texts(s.widget).includes("電量"));
  s = await run({ family: "large", noSymbols: true });
  check("D3 SF Symbol 唔存在都出得到", s.widget && texts(s.widget).includes("電量") && all(s.widget, (e) => e.kind === "image").length === 0);
  s = await run({ family: "large", device: { screenBrightness: () => { throw new Error("x"); } } });
  check("D4 讀唔到亮度 → 唔砌亮度卡", !texts(s.widget).includes("螢幕亮度"));
  s = await run({ family: "large", device: { isCharging: () => true } });
  check("D5 充電中顯示", texts(s.widget).some((t) => t.includes("充電中")));
  s = await run({ family: "large", device: { batteryLevel: () => 0.1 } });
  const lowText = all(s.widget, (e) => e.kind === "text" && e.text === "10%")[0];
  check("D6 低電紅色", Boolean(lowText && lowText.textColor.dynamic && lowText.textColor.light.hex === "#ff3b30"));

  console.log("\n【A】app 內預覽");
  s = await run({ family: "app", runsInWidget: false });
  check("A1 app 內行 → present，唔 setWidget", s.widget === null && s.widgetObj.presented === "large", `${s.widgetObj.presented}`);

  console.log("\n" + "=".repeat(60));
  console.log(`通過 ${pass}  失敗 ${fail}`);
  if (fail) process.exit(1);
  console.log("全部通過 ✓");
})().catch((error) => { console.error(error); process.exit(1); });
