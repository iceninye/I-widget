// scriptable/i-widget.js 嘅測試：用假 Scriptable environment 執行。
// 執行：node scriptable/test-i-widget.js
"use strict";

// 固定時區，令 ISO freshness 顯示時間喺任何機器都一致。
process.env.TZ = "UTC";

const fs = require("fs");
const path = require("path");
const assert = require("assert");

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

class FakeVolume {
  constructor(directory, { offline = false, downloadError = false, missing = [], writeError = false } = {}) {
    this.directory = directory;
    this.files = new Map();
    this.calls = [];
    this.offline = offline;
    this.downloadError = downloadError;
    this.missing = new Set(missing);
    this.writeError = writeError;
  }
  documentsDirectory() { this.calls.push(["documentsDirectory"]); return this.directory; }
  downloadFileFromiCloud(file) {
    this.calls.push(["downloadFileFromiCloud", file]);
    if (this.downloadError) throw new Error("iCloud unavailable");
    if (this.offline) return Promise.reject(new Error("offline"));
    return true;
  }
  fileExists(file) { this.calls.push(["fileExists", file]); return this.files.has(file); }
  readString(file) {
    this.calls.push(["readString", file]);
    if (!this.files.has(file)) throw new Error("missing");
    return this.files.get(file);
  }
  writeString(value, file) {
    this.calls.push(["writeString", file]);
    if (this.writeError) throw new Error("read-only");
    this.files.set(file, value);
  }
}

function walk(el, fn) { fn(el); el.children.forEach((child) => walk(child, fn)); }
function all(el, pred) { const out = []; walk(el, (e) => pred(e) && out.push(e)); return out; }
function texts(el) { return all(el, (e) => e.kind === "text").map((e) => e.text); }
function clone(value) { return JSON.parse(JSON.stringify(value)); }

const DEFAULT_NOW = new Date(2026, 9, 23, 14, 5, 30);
const iso = (hours, minutes, day = 23) => new Date(2026, 9, day, hours, minutes, 0).toISOString();
function caseEntry(minutes, caseNo, deepLink = "iwidget://court?code=DC") {
  return {
    room: "3", judge: "陳法官", minutes, timeText: minutes === null ? "--:--" : `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`,
    caseNo, nature: "審訊", offence: null, category: "criminal", categoryTitle: "刑事", detailText: "3 · 陳法官", deepLink,
  };
}
function dutyEvent(at, overrides = {}) {
  return {
    id: `event-${at}`, action: "落更", at: new Date(at).toISOString(), displayAt: "15:30",
    title: "錦上路交接", detail: "帶交接文件", place: "錦上路站", note: "", ...overrides,
  };
}
function datedWeather(day, codeText, rainChance) {
  const date = new Date(2026, 9, day);
  const code = `${date.getFullYear()}${String(date.getMonth() + 1).padStart(2, "0")}${String(date.getDate()).padStart(2, "0")}`;
  return {
    date: code,
    day: { code: 3, codeText, symbol: "cloud.fill", minTemp: 23, maxTemp: 31, tempText: "23°–31°", rainChance, uvIndex: 5 },
  };
}
function planningFixture() {
  const data = fixture();
  data.duty.events = [dutyEvent(iso(13, 0), { title: "已發生事件" }), dutyEvent(iso(15, 30))];
  data.duty.weekText = "本週 5 更";
  data.duty.tomorrow = { ...data.duty.today, date: "20261024", code: "1101158", title: "00158 屯門", times: "06:00–14:00" };
  data.duty.nextHoliday = { title: "重陽節", rangeText: "10月26日", daysAway: 3 };
  data.school.tomorrow = { cycle: ["Day 5"], items: [{ title: "明日科學測驗", start: iso(9, 0, 24), end: iso(10, 0, 24), allDay: false }] };
  data.weather.tomorrow = { ...data.weather.today, codeText: "小雨", rainChance: 70 };
  data.weather.daily = Array.from({ length: 7 }, (_, index) => datedWeather(23 + index, `天氣${index + 1}`, index * 10));
  return data;
}
function dutyStripDay(offset, label, tone) {
  const date = new Date(2026, 9, 23 + offset);
  const weekdays = ["一", "二", "三", "四", "五", "六", "日"];
  const weekday = weekdays[(date.getDay() + 6) % 7];
  return { date: `202610${String(23 + offset).padStart(2, "0")}`, weekday, dayNumber: String(23 + offset), label, tone };
}

function fixture(now = DEFAULT_NOW) {
  return {
    schemaVersion: 1,
    generatedAt: now.toISOString(),
    serviceDate: "20261023",
    theme: "classic",
    freshness: { today: iso(11, 47), info: iso(9, 12), schedule: iso(8, 1), weather: iso(11, 40), warningsToday: iso(11, 45), warningsInfo: iso(9, 10), court: iso(12, 36) },
    system: {
      capturedAt: iso(13, 55),
      battery: { level: 0.75, charging: false, fullyCharged: false, lowPowerMode: true, estimatedText: "約 5 小時", rateText: "正常" },
      storage: { freeBytes: 32600000000, totalBytes: 255400000000, freeText: "32.6 GB", totalText: "255.4 GB", usedText: "222.8 GB" },
      memory: { totalBytes: 8000000000, availableBytes: 3100000000, lines: [{ label: "記憶體", value: "3.1 / 8 GB" }] },
      uptimeSeconds: 23 * 86400 + 18 * 3600,
      uptimeText: "23 天 18 小時",
      bootAt: new Date(now.getTime() - (23 * 86400 + 18 * 3600) * 1000).toISOString(),
      systemName: "iOS", systemVersion: "27.0.1", versionText: "iOS 27.0.1", latestOS: "27.1", osStatus: "可更新",
    },
    duty: {
      configured: true, failed: false,
      today: { date: "20261023", code: "1101157", title: "00157 錦上路", group: "KSR", datedSheet: null, isOverride: true, tone: "dawn", times: "15:05–23:15", route: "屯馬綫", mealText: "18:00", hoursText: "7.5 小時", hint: "帶八達通", onAt: iso(15, 5), offAt: iso(23, 15) },
      tomorrow: null,
      events: [],
      week: ["死早", "死早", "死早", "休", "死早", "死夜", "死夜"].map((label, index) => dutyStripDay(index, label, label === "休" ? "rest" : label === "死夜" ? "night" : "dawn")),
      weekText: "本週 5 更", nextHoliday: null, detailLines: [],
    },
    school: {
      failed: [], today: { cycle: ["Day 4"], items: [{ title: "中三家長會", start: iso(18, 0), end: iso(19, 0), allDay: false }] },
      tomorrow: { cycle: [], items: [] },
    },
    weather: {
      available: true, fetchedAt: iso(11, 40), currentTemp: 28.4,
      today: { code: 3, codeText: "多雲", symbol: "cloud.fill", minTemp: 24, maxTemp: 31, tempText: "24°–31°", rainChance: 30, uvIndex: 6 },
      tomorrow: null, daily: [],
    },
    warnings: { available: false, items: [] },
    train: { available: true, stateText: "正常", message: "行車大致正常" },
    environment: { sections: [{ id: "gold", title: "黃金", lines: [{ label: "999.9 金", value: "HK$62,800" }] }] },
    vps: { configured: true, available: true, failed: false, lines: [{ label: "狀態", value: "正常" }] },
    courts: {
      listDate: iso(12, 30), updatedAt: iso(12, 35),
      items: [{
        code: "DC", name: "區域法院", dateCode: "20261023", fetchedAt: iso(12, 36), error: false, total: 6, truncated: false, categories: [], deepLink: "iwidget://court?code=DC",
        cases: [caseEntry(830, "已過20分鐘"), caseEntry(829, "已篩走"), caseEntry(845, "DCCJ 1/2026"), caseEntry(849, "DCCJ 2/2026"), caseEntry(null, "沒有時間"), caseEntry(850, "DCCJ 3/2026")],
      }],
    },
  };
}

async function run({
  family = "large", view = "clock", now = DEFAULT_NOW, device = {}, runsInWidget = true,
  noSymbols = false, iCloud, cache, iCloudOptions = {}, localOptions = {},
  parameterValues = { view }, fileManager = true, args, alerts,
} = {}) {
  const state = { widget: null, completed: false, widgetObj: null, iCloud: null, local: null, alerts: [] };
  const dev = {
    batteryLevel: () => 0.75, isCharging: () => false, isFullyCharged: () => false,
    systemName: () => "iOS", systemVersion: () => "27.0.1", screenBrightness: () => 0.4,
    ...device,
  };
  const globals = {
    Color, Font, Size, ListWidget,
    SFSymbol: { named: (name) => (noSymbols ? null : { image: { symbol: name } }) },
    Device: dev,
    config: { widgetFamily: family === "app" ? null : family, runsInWidget, parameterValues },
    Script: { setWidget: (w) => { state.widget = w; }, complete: () => { state.completed = true; } },
    IWIDGET_NOW: now,
  };
  if (args !== undefined) globals.args = args;
  if (alerts !== undefined) {
    globals.Alert = class {
      async presentAlert() { state.alerts.push({ title: this.title, message: this.message }); }
    };
  }
  if (fileManager) {
    state.iCloud = new FakeVolume("/iCloud/Scriptable/", iCloudOptions);
    state.local = new FakeVolume("/local/Scriptable/", localOptions);
    if (iCloud !== undefined) state.iCloud.files.set(`${state.iCloud.directory}i-widget.json`, iCloud);
    if (cache !== undefined) state.local.files.set(`${state.local.directory}i-widget-last-good.json`, cache);
    const iCloudVolume = state.iCloud;
    const localVolume = state.local;
    globals.FileManager = {
      iCloud: () => {
        for (const method of iCloudVolume.missing) if (["documentsDirectory", "downloadFileFromiCloud", "fileExists", "readString"].includes(method)) iCloudVolume[method] = undefined;
        return iCloudVolume;
      },
      local: () => {
        for (const method of localVolume.missing) if (["documentsDirectory", "readString", "writeString"].includes(method)) localVolume[method] = undefined;
        return localVolume;
      },
    };
  }
  globals.ListWidget = class extends ListWidget { constructor() { super(); state.widgetObj = this; } };
  const names = Object.keys(globals);
  const fn = new AsyncFunction(...names, SOURCE);
  await fn(...names.map((name) => globals[name]));
  return state;
}

// ---- 測試框架 ----------------------------------------------------------

let pass = 0, fail = 0;
async function test(name, fn) {
  try { await fn(); pass++; console.log(`  ✓  ${name}`); }
  catch (error) { fail++; console.log(`  ✗ FAIL  ${name}  → ${error.message}`); }
}
function equal(actual, expected, message = "") { assert.deepStrictEqual(actual, expected, message); }
function ok(value, message = "") { assert.ok(value, message); }
function has(widget, value) { return texts(widget).includes(value); }
function cachePath(state) { return `${state.local.directory}i-widget-last-good.json`; }
function cloudPath(state) { return `${state.iCloud.directory}i-widget.json`; }

module.exports = { run, all, texts, fixture, FakeVolume };

if (require.main === module) (async () => {
  console.log("\n【S】view × family");
  for (const view of ["today", "info", "court", "clock", "accessory"]) {
    for (const family of ["small", "medium", "large", "extraLarge", "accessoryInline", "accessoryCircular", "accessoryRectangular"]) {
      await test(`${view}/${family} 有畫面、setWidget + complete`, async () => {
        const state = await run({ view, family, iCloud: JSON.stringify(fixture()) });
        ok(state.widget && state.completed);
        ok(texts(state.widget).length > 0);
      });
    }
  }
  await test("parameter view 分流；未知值安全 fallback today", async () => {
    equal(has((await run({ view: "today", parameterValues: { view: "court" }, iCloud: JSON.stringify(fixture()) })).widget, "法院案件"), true);
    const fallback = await run({ parameterValues: { view: "unknown" }, iCloud: JSON.stringify(fixture()) });
    equal(has(fallback.widget, "00157 錦上路"), true);
    equal(all(fallback.widget, (e) => e.kind === "date").length, 0);
  });
  await test("舊 config 無 parameterValues 時預設 today", async () => {
    const state = await run({ parameterValues: null, iCloud: JSON.stringify(fixture()) });
    equal(has(state.widget, "00157 錦上路"), true);
    equal(all(state.widget, (e) => e.kind === "date").length, 0);
  });

  console.log("\n【F】iCloud、cache、schema 驗證");
  await test("有效 JSON 先寫 local last-good cache", async () => {
    const raw = JSON.stringify(fixture());
    const state = await run({ iCloud: raw });
    equal(state.local.files.get(cachePath(state)), raw);
    ok(state.iCloud.calls.some((call) => call[0] === "downloadFileFromiCloud" && call[1] === cloudPath(state)));
    ok(state.iCloud.calls.some((call) => call[0] === "fileExists"));
    ok(state.iCloud.calls.some((call) => call[0] === "readString"));
    ok(state.local.calls.some((call) => call[0] === "writeString" && call[1] === cachePath(state)));
  });
  await test("Swift 省略 optional key 視為 null，仍可用", async () => {
    const data = fixture();
    for (const key of Object.keys(data.freshness)) if (data.freshness[key] === null) delete data.freshness[key];
    delete data.system.battery.level;
    delete data.system.battery.lowPowerMode;
    delete data.system.storage.freeBytes;
    delete data.system.storage.totalBytes;
    delete data.system.uptimeSeconds;
    delete data.system.bootAt;
    delete data.system.latestOS;
    delete data.duty.tomorrow;
    delete data.duty.weekText;
    delete data.duty.nextHoliday;
    delete data.weather.tomorrow;
    delete data.courts.listDate;
    delete data.courts.updatedAt;
    delete data.courts.items[0].fetchedAt;
    delete data.courts.items[0].cases[0].nature;
    delete data.courts.items[0].cases[0].offence;
    const raw = JSON.stringify(data);
    const state = await run({ view: "info", iCloud: raw });
    equal(state.local.files.get(cachePath(state)), raw);
    ok(has(state.widget, "未有資料"));
    ok(has(state.widget, "iOS 27.0.1"));
  });
  for (const [name, iCloud] of [
    ["corrupt", "{not json"],
    ["unsupported schema", JSON.stringify({ ...fixture(), schemaVersion: 2 })],
    ["缺少主要欄位", JSON.stringify({ schemaVersion: 1 })],
    ["損壞日期", JSON.stringify({ ...fixture(), generatedAt: "2026-02-30T14:05:30Z" })],
    ["日期沒有時區", JSON.stringify({ ...fixture(), generatedAt: "2026-10-23T14:05:30" })],
    ["電量越界", JSON.stringify({ ...fixture(), system: { ...fixture().system, battery: { ...fixture().system.battery, level: 1.1 } } })],
    ["儲存越界", JSON.stringify({ ...fixture(), system: { ...fixture().system, storage: { ...fixture().system.storage, freeBytes: -1 } } })],
    ["案件 minutes 越界", JSON.stringify({ ...fixture(), courts: { ...fixture().courts, items: [{ ...fixture().courts.items[0], cases: [caseEntry(1440, "bad")] }] } })],
    ["過大 payload", " ".repeat(513 * 1024)],
  ]) {
    await test(`${name} 用 cache，唔覆蓋 cache`, async () => {
      const cached = JSON.stringify(fixture());
      const state = await run({ view: "info", iCloud, cache: cached });
      equal(state.local.files.get(cachePath(state)), cached);
      ok(has(state.widget, "更新於 09:12 · 快取"));
    });
  }
  await test("cache fallback 顯示舊 freshness 與快取標記", async () => {
    const state = await run({ view: "info", iCloud: "broken", cache: JSON.stringify(fixture()) });
    ok(has(state.widget, "更新於 09:12 · 快取"));
    equal(has(state.widget, "32.6 GB / 255.4 GB 可用"), true);
  });
  await test("iCloud 缺失／download 失敗／read 失敗都用 cache", async () => {
    for (const options of [{}, { downloadError: true }, { missing: ["readString"] }]) {
      const state = await run({ view: "court", cache: JSON.stringify(fixture()), iCloudOptions: options });
      ok(texts(state.widget).some((t) => t.includes("DCCJ 2/2026")));
    }
  });
  await test("離線 fallback", async () => {
    const state = await run({ view: "today", cache: JSON.stringify(fixture()), iCloudOptions: { offline: true } });
    ok(has(state.widget, "00157 錦上路"));
  });
  await test("FileManager 缺失／API 缺失／cache 寫入失敗都唔 crash", async () => {
    ok((await run({ view: "info", fileManager: false })).widget);
    ok((await run({ view: "info", iCloud: JSON.stringify(fixture()), iCloudOptions: { missing: ["documentsDirectory"] } })).widget);
    ok((await run({ view: "info", iCloud: JSON.stringify(fixture()), localOptions: { writeError: true } })).widget);
    ok((await run({ view: "info", iCloud: JSON.stringify(fixture()), iCloudOptions: { missing: ["fileExists", "downloadFileFromiCloud"] } })).widget);
  });
  await test("cache 損壞兼 iCloud 缺失 → 顯示具體診斷", async () => {
    const state = await run({ view: "today", cache: "broken" });
    const output = texts(state.widget).join("\n");
    ok(output.includes("未有資料") && output.includes("i-widget.json") && output.includes("local cache"));
  });
  await test("schema 驗證失敗顯示欄位原因，唔只顯示未有資料", async () => {
    const raw = JSON.stringify({ ...fixture(), schemaVersion: 2 });
    const state = await run({ view: "info", iCloud: raw });
    ok(texts(state.widget).some((t) => t.includes("JSON 驗證失敗") && t.includes("schemaVersion")));
  });
  await test("Scriptable app 預覽缺少 JSON 時顯示安全診斷 Alert", async () => {
    const state = await run({ view: "today", runsInWidget: false, alerts: true });
    equal(state.alerts.length, 1);
    ok(state.alerts[0].message.includes("i-widget.json"));
    ok(!state.alerts[0].message.includes(JSON.stringify(fixture())));
  });

  console.log("\n【T】freshness 語意");
  await test("generatedAt 唔當資料更新時間", async () => {
    const data = fixture();
    data.freshness.today = iso(1, 2);
    data.freshness.info = iso(3, 4);
    data.freshness.court = iso(5, 6);
    const state = await run({ view: "today", iCloud: JSON.stringify(data) });
    ok(has(state.widget, "更新於 01:02"));
    ok(!texts(state.widget).includes("更新於 14:05"));
  });
  await test("freshness null 顯示未有資料", async () => {
    const data = fixture();
    data.freshness.today = null;
    const state = await run({ view: "today", iCloud: JSON.stringify(data) });
    ok(has(state.widget, "未有資料"));
  });
  await test("court freshness 優先；null 先 courts.updatedAt", async () => {
    let data = fixture();
    data.courts.updatedAt = iso(1, 1);
    ok(has((await run({ view: "court", iCloud: JSON.stringify(data) })).widget, "更新於 12:36"));
    data.freshness.court = null;
    ok(has((await run({ view: "court", iCloud: JSON.stringify(data) })).widget, "更新於 01:01"));
  });

  console.log("\n【V】today / info / court / accessory 內容");
  await test("today 顯示更份、學校、天氣、屯馬綫", async () => {
    const state = await run({ view: "today", iCloud: JSON.stringify(fixture()) });
    for (const value of ["00157 錦上路", "15:05–23:15", "Day 4", "中三家長會", "多雲", "KSR", "改"]) ok(texts(state.widget).some((t) => t.includes(value)), value);
    ok(!texts(state.widget).includes("行車大致正常"));
  });
  await test("info 系統儲存／uptime／低耗電只由 JSON 顯示", async () => {
    const state = await run({ view: "info", iCloud: JSON.stringify(fixture()) });
    ok(has(state.widget, "32.6 GB / 255.4 GB 可用"));
    ok(texts(state.widget).some((t) => t.includes("23 天 18 小時")));
    ok(has(state.widget, "開啟"));
    ok(has(state.widget, "HK$62,800"));
    ok(has(state.widget, "正常"));
  });
  await test("系統數值缺失顯示未有資料，唔 fallback Device", async () => {
    const data = fixture();
    data.system.storage.freeBytes = null;
    data.system.storage.totalBytes = null;
    data.system.uptimeSeconds = null;
    data.system.bootAt = null;
    data.system.battery.lowPowerMode = null;
    const state = await run({ view: "info", iCloud: JSON.stringify(data), device: { screenBrightness: () => 1 } });
    ok(has(state.widget, "未有資料"));
    ok(!texts(state.widget).some((t) => t.includes("32.6 GB")));
    ok(!texts(state.widget).some((t) => t.includes("23 天")));
    ok(!texts(state.widget).includes("開啟"));
  });
  await test("court 以分鐘篩 20 分鐘 ongoing window、排序、顯示狀熊", async () => {
    const state = await run({ view: "court", now: new Date(2026, 9, 23, 14, 10, 0), iCloud: JSON.stringify(fixture()) });
    // 13:50 喺 14:10 嘅 20 分鐘邊界內；13:49 同無時間項目被篩走。
    const courtText = texts(state.widget).join("\n");
    ok(courtText.includes("DCCJ 1/2026"));
    ok(courtText.includes("DCCJ 2/2026"));
    ok(courtText.includes("DCCJ 3/2026"));
    ok(courtText.includes("已過20分鐘"));
    ok(!courtText.includes("已篩走"));
    ok(!courtText.includes("沒有時間"));
    ok(courtText.includes("已過時間"));
    ok(courtText.indexOf("13:50") < courtText.indexOf("14:09"));
  });
  await test("court 14:05 顯示進行中", async () => {
    const state = await run({ view: "court", iCloud: JSON.stringify(fixture()) });
    ok(texts(state.widget).some((t) => t.includes("DCCJ 1/2026") && t.includes("進行中")));
  });
  await test("court 非今日日期唔顯示舊案件", async () => {
    const data = fixture();
    data.courts.items[0].dateCode = "20261022";
    const state = await run({ view: "court", iCloud: JSON.stringify(data) });
    ok(has(state.widget, "JSON 未有今日案件表"));
    ok(!has(state.widget, "DCCJ 1/2026"));
  });
  await test("accessory view 任何 family 都有電量", async () => {
    for (const family of ["small", "medium", "large", "extraLarge", "accessoryInline", "accessoryCircular", "accessoryRectangular"]) {
      const state = await run({ view: "accessory", family, iCloud: JSON.stringify(fixture()) });
      ok(texts(state.widget).some((t) => t.includes("75%")), family);
    }
  });
  await test("accessory 缺 JSON 仍有電量與設定提示", async () => {
    for (const family of ["small", "medium", "large", "extraLarge", "accessoryInline", "accessoryCircular", "accessoryRectangular"]) {
      const state = await run({ view: "accessory", family });
      const output = texts(state.widget);
      ok(output.some((t) => t.includes("75%")), family);
      ok(output.some((t) => t.includes("未有資料") || t.includes("設定")), family);
    }
  });

  console.log("\n【R】失敗／快取／空資料狀態");
  await test("warnings unavailable + 空 items 顯示未有資料，唔顯示沒有警告", async () => {
    for (const view of ["today", "info"]) {
      const state = await run({ view, iCloud: JSON.stringify(fixture()) });
      ok(texts(state.widget).some((value) => value.includes("未有資料")), view);
      ok(!has(state.widget, "沒有警告"), view);
    }
  });
  await test("warnings available + 空 items 時 info 先顯示沒有警告；today 收起", async () => {
    const data = fixture();
    data.warnings.available = true;
    ok(has((await run({ view: "info", iCloud: JSON.stringify(data) })).widget, "沒有警告"));
    ok(!has((await run({ view: "today", iCloud: JSON.stringify(data) })).widget, "沒有警告"));
  });
  await test("today 屯馬綫未有資料唔會被當成正常而收起", async () => {
    const data = fixture();
    data.warnings.available = true;
    data.train.available = false;
    const output = texts((await run({ view: "today", iCloud: JSON.stringify(data) })).widget).join("\n");
    ok(output.includes("屯馬綫：未有資料"));
  });
  await test("warnings available 顯示警告內容", async () => {
    const data = fixture();
    data.warnings = { available: true, items: [{ text: "黑色暴雨警告", severe: true }] };
    for (const view of ["today", "info"]) ok(has((await run({ view, iCloud: JSON.stringify(data) })).widget, "黑色暴雨警告"));
  });
  await test("duty configured + failed + today=nil 顯示讀取失敗", async () => {
    const data = fixture();
    data.duty.configured = true;
    data.duty.failed = true;
    data.duty.today = null;
    for (const family of ["small", "medium", "large", "extraLarge"]) {
      const output = texts((await run({ view: "today", family, iCloud: JSON.stringify(data) })).widget).join("\n");
      ok(output.includes("更份讀取失敗"), family);
      ok(!output.includes("今日唔使返工"), family);
    }
  });
  await test("duty failed + cached today 顯示快取更份與失敗提示", async () => {
    const data = fixture();
    data.duty.failed = true;
    for (const family of ["small", "large", "extraLarge"]) {
      const output = texts((await run({ view: "today", family, iCloud: JSON.stringify(data) })).widget).join("\n");
      ok(output.includes("更份讀取失敗 · 沿用快取"), family);
      ok(output.includes("00157 錦上路"), family);
    }
  });
  await test("duty configured + valid today=nil 仍顯示今日唔使返工", async () => {
    const data = fixture();
    data.duty.today = null;
    ok(has((await run({ view: "today", iCloud: JSON.stringify(data) })).widget, "今日唔使返工"));
  });
  await test("鎖屏 today summary 亦保留 duty 失敗／快取提示", async () => {
    const data = fixture();
    data.duty.failed = true;
    for (const family of ["accessoryInline", "accessoryCircular", "accessoryRectangular"]) {
      const output = texts((await run({ view: "today", family, iCloud: JSON.stringify(data) })).widget).join("\n");
      ok(output.includes("更份讀取失敗 · 沿用快取"), family);
    }
    data.duty.today = null;
    const output = texts((await run({ view: "today", family: "accessoryRectangular", iCloud: JSON.stringify(data) })).widget).join("\n");
    ok(output.includes("更份讀取失敗"));
    ok(!output.includes("今日唔使返工"));
  });
  await test("school failed 即使 items 空仍顯示失敗，valid empty 先顯示沒有日程", async () => {
    const data = fixture();
    data.school.failed = ["中三", "小六"];
    data.school.today = { cycle: [], items: [] };
    let output = texts((await run({ view: "today", iCloud: JSON.stringify(data) })).widget).join("\n");
    ok(output.includes("中三、小六") && output.includes("讀唔到"));
    ok(!output.includes("今明兩日冇學校活動"));
    data.school.failed = [];
    output = texts((await run({ view: "today", iCloud: JSON.stringify(data) })).widget).join("\n");
    ok(output.includes("今明兩日冇學校活動"));
  });
  await test("school failed 有部分 items 時同時顯示失敗與日程", async () => {
    const data = fixture();
    data.school.failed = ["小六"];
    const output = texts((await run({ view: "today", iCloud: JSON.stringify(data) })).widget).join("\n");
    ok(output.includes("小六") && output.includes("讀唔到"));
    ok(output.includes("中三家長會"));
  });
  await test("VPS 未設定、讀取失敗、沿用快取三態清楚", async () => {
    const cases = [
      [{ configured: false, available: true, failed: false }, "VPS 未設定", false],
      [{ configured: true, available: false, failed: true }, "VPS 讀取失敗", false],
      [{ configured: true, available: true, failed: true }, "VPS 讀取失敗 · 沿用快取", true],
    ];
    for (const [vps, expected, cached] of cases) {
      const data = fixture();
      data.vps = { ...vps, lines: [{ label: "狀態", value: "VPS 快取正常" }] };
      const widget = (await run({ view: "info", iCloud: JSON.stringify(data) })).widget;
      const output = texts(widget).join("\n");
      ok(output.includes(expected), expected);
      equal(texts(widget).includes("VPS 快取正常"), cached, expected);
    }
  });
  await test("VPS configured + available=false + failed=false 顯示未有資料", async () => {
    const data = fixture();
    data.vps = { configured: true, available: false, failed: false, lines: [] };
    ok(has((await run({ view: "info", iCloud: JSON.stringify(data) })).widget, "VPS 未有資料"));
  });

  console.log("\n【M】app 主題與 deep links");
  await test("六個主題實際改變畫面 accent／背景，mono 所有畫面色為灰階", async () => {
    const accents = new Set();
    const backgrounds = new Set();
    for (const theme of ["classic", "ocean", "sunset", "forest", "violet", "mono"]) {
      const data = planningFixture();
      data.theme = theme;
      const widget = (await run({ view: "today", iCloud: JSON.stringify(data) })).widget;
      const accentIcon = all(widget, (e) => e.kind === "image" && e.image && e.image.symbol === "clock")[0];
      ok(accentIcon && accentIcon.tintColor.dynamic, theme);
      accents.add(accentIcon.tintColor.light.hex);
      backgrounds.add(widget.backgroundColor.light.hex);
      if (theme === "mono") {
        const colors = all(widget, (e) => e.textColor || e.backgroundColor).map((e) => e.textColor || e.backgroundColor);
        for (const color of colors) {
          for (const variant of [color.light, color.dark]) {
            ok(variant && /^#[0-9a-f]{6}$/i.test(variant.hex), JSON.stringify(variant));
            equal(variant.hex.slice(1, 3), variant.hex.slice(3, 5));
            equal(variant.hex.slice(3, 5), variant.hex.slice(5, 7));
          }
        }
      }
    }
    equal(accents.size, 6);
    equal(backgrounds.size, 6);
  });
  await test("snapshot theme 套用於 clock，而非只用 today", async () => {
    const data = fixture();
    data.theme = "ocean";
    const widget = (await run({ view: "clock", iCloud: JSON.stringify(data) })).widget;
    equal(widget.backgroundColor.light.hex, "#f2f8ff");
    const heading = all(widget, (e) => e.kind === "text" && e.text === "星期五")[0];
    equal(heading.textColor.light.hex, "#007aff");
  });
  await test("五 views whole-widget URL 正確", async () => {
    const data = fixture();
    data.courts.items[0].deepLink = "iwidget://court?code=DC&date=20261023";
    const expected = { today: "iwidget://duty", info: "iwidget://info", court: data.courts.items[0].deepLink, clock: "iwidget://duty", accessory: "iwidget://duty" };
    for (const [view, url] of Object.entries(expected)) {
      equal((await run({ view, iCloud: JSON.stringify(data) })).widget.url, url, view);
      equal((await run({ view })).widget.url, view === "court" ? "iwidget://court" : url, `${view} no JSON`);
    }
  });
  await test("court 每宗案件 stack/text 有 deepLink", async () => {
    const data = fixture();
    data.courts.items[0].cases[2].deepLink = "iwidget://court?code=DC&case=1";
    const widget = (await run({ view: "court", iCloud: JSON.stringify(data) })).widget;
    const row = all(widget, (e) => e.kind === "stack" && e.children.some((child) => child.text === "14:05 · DCCJ 1/2026 · 進行中"))[0];
    ok(row);
    equal(row.url, "iwidget://court?code=DC&case=1");
    ok(row.children.filter((e) => e.kind === "text").every((e) => e.url === "iwidget://court?code=DC&case=1"));
  });
  await test("court 18:30 後下一工作日顯示全部有時間案件與日期", async () => {
    const data = fixture();
    data.courts.listDate = iso(12, 30, 26);
    data.courts.items[0].dateCode = "20261026";
    data.courts.items[0].fetchedAt = iso(18, 35);
    data.courts.items[0].cases = [caseEntry(540, "下周一第一宗"), caseEntry(600, "下周一第二宗"), caseEntry(null, "沒有時間"), caseEntry(780, "下周一第三宗")];
    const state = await run({ view: "court", now: new Date(2026, 9, 23, 19, 0), iCloud: JSON.stringify(data) });
    const output = texts(state.widget).join("\n");
    ok(output.includes("區域法院 · 10月26日"));
    ok(output.includes("下周一第一宗") && output.includes("下周一第二宗") && output.includes("下周一第三宗"));
    ok(!output.includes("沒有時間"));
    ok(!output.includes("今日沒有案件"));
    const accessory = texts((await run({ view: "court", family: "accessoryCircular", now: new Date(2026, 9, 23, 19, 0), iCloud: JSON.stringify(data) })).widget).join("\n");
    ok(accessory.includes("3 宗"));
  });
  await test("court listDate 過去日期顯示沒有相關案件", async () => {
    const data = fixture();
    data.courts.listDate = iso(12, 30, 22);
    data.courts.items[0].dateCode = "20261022";
    const state = await run({ view: "court", iCloud: JSON.stringify(data) });
    ok(has(state.widget, "沒有相關案件"));
    ok(!has(state.widget, "DCCJ 1/2026"));
  });
  await test("court 同日較早 listDate 仍保留今日 ongoing window", async () => {
    const data = fixture();
    data.courts.listDate = iso(9, 0);
    const output = texts((await run({ view: "court", now: new Date(2026, 9, 23, 14, 10), iCloud: JSON.stringify(data) })).widget).join("\n");
    ok(output.includes("DCCJ 1/2026"));
    ok(!output.includes("已篩走"));
  });
  await test("court 省略 optional listDate 仍顯示今日案件", async () => {
    const data = fixture();
    delete data.courts.listDate;
    const widget = (await run({ view: "court", iCloud: JSON.stringify(data) })).widget;
    ok(texts(widget).some((value) => value.includes("DCCJ 1/2026")));
    ok(!has(widget, "JSON 未有今日案件表"));
  });

  console.log("\n【P】today 規劃與 info 內容");
  await test("today events 只顯示未發生，並有 action/title/time/place/detail", async () => {
    const output = texts((await run({ view: "today", family: "large", iCloud: JSON.stringify(planningFixture()) })).widget).join("\n");
    for (const value of ["15:30", "落更", "錦上路交接", "錦上路站", "帶交接文件"]) ok(output.includes(value), value);
    ok(!output.includes("已發生事件"));
  });
  await test("today 大尺寸補回 7 日更份、明日、假期、學校；medium 保持精簡", async () => {
    for (const family of ["large", "extraLarge"]) {
      const output = texts((await run({ view: "today", family, iCloud: JSON.stringify(planningFixture()) })).widget).join("\n");
      for (const value of ["00158 屯門", "06:00–14:00", "重陽節", "10月26日", "3 日後", "明日科學測驗"]) ok(output.includes(value), `${family}: ${value}`);
      for (const label of ["五23", "六24", "日25", "一26", "二27", "三28", "四29"]) ok(output.includes(label), `${family}: ${label}`);
      equal(output.includes("本週 5 更"), family === "extraLarge", `${family}: week summary`);
    }
    const medium = texts((await run({ view: "today", family: "medium", iCloud: JSON.stringify(planningFixture()) })).widget).join("\n");
    ok(!medium.includes("明日科學測驗"));
    ok(!medium.includes("三23"));
  });
  await test("today small 維持精簡，仍有 cached duty 失敗提示", async () => {
    const data = planningFixture();
    data.duty.failed = true;
    const output = texts((await run({ view: "today", family: "small", iCloud: JSON.stringify(data) })).widget).join("\n");
    ok(output.includes("更份讀取失敗 · 沿用快取"));
    ok(output.includes("00157 錦上路"));
    ok(!output.includes("本週 5 更"));
    ok(!output.includes("天氣7"));
  });
  await test("today 原生式版面限制事件、7 日色條同學校行數", async () => {
    const data = planningFixture();
    data.duty.events = Array.from({ length: 200 }, (_, index) => dutyEvent(iso(15, index), { title: `事件${index}` }));
    data.weather.daily = Array.from({ length: 14 }, (_, index) => datedWeather(23 + index, `天氣${index + 1}`, 10));
    data.school.today.items = Array.from({ length: 10 }, (_, index) => ({ title: `活動${index}`, start: iso(9, index), end: iso(10, index), allDay: false }));
    for (const family of ["medium", "large", "extraLarge"]) {
      const widget = (await run({ view: "today", family, iCloud: JSON.stringify(data) })).widget;
      const output = texts(widget).join("\n");
      equal(output.includes("事件199"), false, family);
      equal(all(widget, (e) => e.kind === "stack" && e.cornerRadius === 18).length, 1, `${family}: one duty card`);
      if (family !== "medium") {
        for (const label of ["五23", "六24", "日25", "一26", "二27", "三28", "四29"]) ok(output.includes(label), `${family}: ${label}`);
        equal(output.includes("活動2"), true, `${family}: school visible`);
        equal(output.includes("活動5"), family === "extraLarge", `${family}: school budget`);
        equal(output.includes("活動9"), false, `${family}: school cap`);
      }
    }
  });
  await test("info 補回 warning、battery estimate/rate、memory、今日／明日 rain", async () => {
    const data = planningFixture();
    data.warnings = { available: true, items: [{ text: "雷暴警告", severe: true }] };
    data.system.battery.estimatedText = "約 5 小時";
    data.system.battery.rateText = "12.5% / 小時";
    data.system.memory.lines = [{ label: "記憶體", value: "3.1 / 8 GB" }, { label: "可用", value: "38%" }];
    for (const family of ["medium", "large", "extraLarge"]) {
      const output = texts((await run({ view: "info", family, iCloud: JSON.stringify(data) })).widget).join("\n");
      for (const value of ["雷暴警告", "約 5 小時", "12.5% / 小時", "3.1 / 8 GB", "今日降雨", "30%", "明日降雨", "70%", "HK$62,800", "正常", "行車大致正常"]) ok(output.includes(value), `${family}: ${value}`);
    }
  });

  console.log("\n【C】時鐘與 reload 邊界");
  let state = await run({ family: "large", now: new Date(2026, 9, 23, 14, 5, 30) });
  let clocks = all(state.widget, (e) => e.kind === "date");
  equal(clocks.length, 1);
  equal(clocks[0].style, "timer");
  equal([clocks[0].date.getHours(), clocks[0].date.getMinutes(), clocks[0].date.getDate()], [0, 0, 23]);
  equal(clocks[0].font.size, 60);
  equal(all((await run({ family: "small" })).widget, (e) => e.kind === "date")[0].font.size, 30);
  equal(all((await run({ family: "medium" })).widget, (e) => e.kind === "date")[0].font.size, 50);
  state = await run({ family: "large", now: new Date(2026, 9, 23, 0, 30, 0) });
  equal(all(state.widget, (e) => e.kind === "date")[0].style, "time");
  state = await run({ family: "accessoryRectangular", now: new Date(2026, 9, 23, 14, 5, 30) });
  equal(all(state.widget, (e) => e.kind === "date").length, 1);
  equal(all(state.widget, (e) => e.kind === "date")[0].style, "timer");

  const delay = async (now) => (await run({ family: "small", now })).widget.refreshAfterDate - now;
  equal(await delay(new Date(2026, 9, 23, 14, 0, 0)), 30 * 60000);
  equal(await delay(new Date(2026, 9, 23, 23, 50, 0)), 10 * 60000 + 20000);
  equal(await delay(new Date(2026, 9, 23, 0, 40, 0)), 20 * 60000 + 20000);
  ok(await delay(new Date(2026, 9, 23, 0, 0, 20)) > 0);

  console.log("\n【L】clock 大尺寸舊版面");
  state = await run({ family: "large" });
  const cards = state.widget.children.filter((e) => e.kind === "stack" && e.cornerRadius === 12);
  equal(cards.length, 4);
  ok(cards.every((c) => c.backgroundColor && c.padding && c.padding[1] === 12));
  ok(cards.every((c) => c.children.some((k) => k.kind === "spacer")));
  equal(all(state.widget, (e) => e.kind === "stack" && e.size && e.size.width === 70).length, 3);
  ok(has(state.widget, "75%"));
  ok(has(state.widget, "iOS 27.0.1"));
  const fills = all(state.widget, (e) => e.kind === "stack" && e.size && e.size.height === 6 && e.size.width !== 70);
  ok(fills.some((f) => f.size.width === Math.round(70 * 0.75)));

  console.log("\n【D】缺資料／Device 錯誤／符號缺失");
  state = await run({ family: "large", device: { batteryLevel: () => -1 } });
  ok(has(state.widget, "—"));
  state = await run({ family: "large", device: { batteryLevel: () => { throw new Error("x"); }, systemVersion: () => { throw new Error("x"); } } });
  ok(state.widget && has(state.widget, "電量"));
  state = await run({ family: "large", noSymbols: true });
  ok(has(state.widget, "電量") && all(state.widget, (e) => e.kind === "image").length === 0);
  state = await run({ family: "large", device: { screenBrightness: () => { throw new Error("x"); } } });
  ok(!has(state.widget, "螢幕亮度"));
  state = await run({ family: "large", device: { isCharging: () => true } });
  ok(texts(state.widget).some((t) => t.includes("充電中")));
  state = await run({ family: "large", device: { batteryLevel: () => 0.1 } });
  const lowText = all(state.widget, (e) => e.kind === "text" && e.text === "10%")[0];
  ok(lowText && lowText.textColor.dynamic && lowText.textColor.light.hex === "#ff3b30");
  for (const view of ["today", "info", "court"]) {
    state = await run({ view });
    ok(texts(state.widget).some((t) => t.includes("未有資料")));
  }

  console.log("\n【A】app 內預覽");
  state = await run({ family: "app", runsInWidget: false, iCloud: JSON.stringify(fixture()) });
  equal(state.widget, null);
  equal(state.widgetObj.presented, "large");

  console.log("\n" + "=".repeat(60));
  console.log(`通過 ${pass}  失敗 ${fail}`);
  if (fail) process.exit(1);
  console.log("全部通過 ✓");
})().catch((error) => { console.error(error); process.exit(1); });
