// i-widget — Scriptable 單腳本 widget（時鐘／今日／資訊／法院／鎖屏）
// 安裝、parameter view、iCloud folder 授權同 JSON schema 見 scriptable/README.md。

// ---- 設定 -------------------------------------------------------------

const CONFIG = {
  showBrightness: true,
  showDayProgress: true,
  reloadMinutes: 30,
  previewFamily: "large",
  previewView: "clock",
  maxPayloadBytes: 512 * 1024,
  cacheName: "i-widget-last-good.json",
};

const WEEKDAYS = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"];
const VIEWS = ["today", "info", "court", "clock", "accessory"];
const SCHEMA_VERSION = 1;

// ---- 顏色 -------------------------------------------------------------

const dyn = (light, dark) => Color.dynamic(light, dark);
const rgba = (hex, alpha) => new Color(hex, alpha);
const BASE_COLORS = {
  bg: dyn(rgba("#ffffff", 1), rgba("#1c1c1e", 1)),
  label: dyn(rgba("#000000", 1), rgba("#ffffff", 1)),
  secondary: dyn(rgba("#3c3c43", 0.6), rgba("#ebebf5", 0.6)),
  card: dyn(rgba("#787880", 0.12), rgba("#787880", 0.24)),
  track: dyn(rgba("#787880", 0.2), rgba("#787880", 0.36)),
  accent: dyn(rgba("#ff3b30", 1), rgba("#ff453a", 1)),
  green: dyn(rgba("#34c759", 1), rgba("#30d158", 1)),
  orange: dyn(rgba("#ff9500", 1), rgba("#ff9f0a", 1)),
  red: dyn(rgba("#ff3b30", 1), rgba("#ff453a", 1)),
  blue: dyn(rgba("#007aff", 1), rgba("#0a84ff", 1)),
  indigo: dyn(rgba("#5856d6", 1), rgba("#5e5ce6", 1)),
  gray: dyn(rgba("#8e8e93", 1), rgba("#8e8e93", 1)),
};
const C = { ...BASE_COLORS };
const THEME_COLORS = {
  classic: {},
  ocean: { accent: dyn(rgba("#007aff", 1), rgba("#64d2ff", 1)), bg: dyn(rgba("#f2f8ff", 1), rgba("#102331", 1)) },
  sunset: { accent: dyn(rgba("#ff6b35", 1), rgba("#ff9f5a", 1)), bg: dyn(rgba("#fff7f0", 1), rgba("#301d18", 1)) },
  forest: { accent: dyn(rgba("#248a3d", 1), rgba("#66d17a", 1)), bg: dyn(rgba("#f3faf4", 1), rgba("#14291a", 1)) },
  violet: { accent: dyn(rgba("#7d3cff", 1), rgba("#bf8fff", 1)), bg: dyn(rgba("#f8f4ff", 1), rgba("#251b38", 1)) },
  mono: {
    accent: dyn(rgba("#5a5a5a", 1), rgba("#b0b0b0", 1)),
    bg: dyn(rgba("#f4f4f4", 1), rgba("#181818", 1)),
    green: dyn(rgba("#6e6e6e", 1), rgba("#a1a1a1", 1)),
    orange: dyn(rgba("#7c7c7c", 1), rgba("#b8b8b8", 1)),
    red: dyn(rgba("#4a4a4a", 1), rgba("#d1d1d1", 1)),
    blue: dyn(rgba("#636363", 1), rgba("#aeaeae", 1)),
    indigo: dyn(rgba("#686868", 1), rgba("#b5b5b5", 1)),
    gray: dyn(rgba("#8e8e8e", 1), rgba("#8e8e8e", 1)),
    secondary: dyn(rgba("#5a5a5a", 0.6), rgba("#d1d1d1", 0.6)),
    card: dyn(rgba("#787878", 0.12), rgba("#a1a1a1", 0.2)),
    track: dyn(rgba("#787878", 0.2), rgba("#a1a1a1", 0.32)),
  },
};

// 主題由 app 匯出；唔受 Scriptable 或 iOS extension 原生主題影響。
function applyTheme(theme) {
  Object.assign(C, BASE_COLORS, THEME_COLORS[theme] || {});
}

const NOW = typeof IWIDGET_NOW !== "undefined" ? IWIDGET_NOW : new Date();
const MISSING = "未有資料";

// ---- 安全呼叫 ---------------------------------------------------------

function safe(fn, fallback) {
  try {
    const value = fn();
    return value === undefined ? fallback : value;
  } catch (error) {
    return fallback;
  }
}

async function safeAsync(fn, fallback) {
  try {
    const value = await fn();
    return value === undefined ? fallback : value;
  } catch (error) {
    return fallback;
  }
}

function readDevice() {
  const level = safe(() => Device.batteryLevel(), null);
  return {
    level: typeof level === "number" && Number.isFinite(level) && level >= 0 ? Math.min(level, 1) : null,
    charging: safe(() => Device.isCharging(), false),
    full: safe(() => Device.isFullyCharged(), false),
    version: safe(() => `${Device.systemName()} ${Device.systemVersion()}`, "—"),
    brightness: safe(() => Device.screenBrightness(), null),
  };
}

// ---- schemaVersion 1 驗證 --------------------------------------------
// 只驗證 Scriptable 實際使用嘅欄位，但主要結構／日期／數值範圍全部檢查。
// 任何主要欄位無效都唔寫 cache，亦唔局部接受，避免半份資料冒充有效。

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function utf8Length(string) {
  let length = 0;
  for (const char of string) length += char.codePointAt(0) > 0xffff ? 4 : char.codePointAt(0) > 0x7ff ? 3 : char.codePointAt(0) > 0x7f ? 2 : 1;
  return length;
}

function validatePayload(raw, now) {
  const errors = [];
  const fail = (path, message) => errors.push(`${path}: ${message}`);
  const object = (value, path) => {
    if (!isObject(value)) { fail(path, "必須是 object"); return {}; }
    return value;
  };
  const array = (value, path, max) => {
    if (!Array.isArray(value)) { fail(path, "必須是 array"); return []; }
    if (value.length > max) fail(path, `最多 ${max} 項`);
    return value;
  };
  const required = (value, path) => {
    if (value === undefined) fail(path, "缺少欄位");
    return value;
  };
  const string = (value, path, max = 2000, nonempty = false) => {
    value = required(value, path);
    if (typeof value !== "string") { fail(path, "必須是 string"); return ""; }
    if (utf8Length(value) > max) fail(path, `字串超過 ${max} bytes`);
    if (nonempty && value.trim() === "") fail(path, "不可空白");
    return value;
  };
  const boolean = (value, path) => {
    value = required(value, path);
    if (typeof value !== "boolean") fail(path, "必須是 boolean");
    return value;
  };
  const nullableBoolean = (value, path) => {
    if (value === null || value === undefined) return null;
    if (typeof value !== "boolean") fail(path, "必須是 boolean 或 null");
    return value;
  };
  const number = (value, path, min, max, integer = false) => {
    value = required(value, path);
    if (typeof value !== "number" || !Number.isFinite(value)) { fail(path, "必須是有限數值"); return null; }
    if (integer && !Number.isSafeInteger(value)) fail(path, "必須是安全整數");
    if (value < min || value > max) fail(path, `必須在 ${min}…${max}`);
    return value;
  };
  const nullableNumber = (value, path, min, max, integer = false) => value === null || value === undefined ? null : number(value, path, min, max, integer);
  const nullableString = (value, path, max = 2000) => value === null || value === undefined ? null : string(value, path, max);

  // ISO 8601：必須有時區，亦檢查真正日曆日期，唔只靠 Date.parse。
  const timestamp = (value, path, nullable = false) => {
    if (nullable && (value === null || value === undefined)) return null;
    value = required(value, path);
    const match = typeof value === "string" && value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/);
    if (!match) { fail(path, "必須是帶時區的 ISO 8601 日期"); return null; }
    const [, y, mo, d, h, mi, sec] = match.map((part) => Number(part));
    if (y < 2000 || y > 2100 || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || sec > 59) {
      fail(path, "日期或時間超出範圍");
      return null;
    }
    const probe = new Date(0);
    probe.setUTCFullYear(y, mo - 1, d);
    if (probe.getUTCFullYear() !== y || probe.getUTCMonth() !== mo - 1 || probe.getUTCDate() !== d) {
      fail(path, "不存在嘅日曆日期");
      return null;
    }
    const parsed = Date.parse(value);
    if (!Number.isFinite(parsed)) fail(path, "日期無效");
    return parsed;
  };
  const dateCode = (value, path) => {
    value = string(value, path, 8, true);
    const match = value.match(/^(\d{4})(\d{2})(\d{2})$/);
    if (!match) { fail(path, "必須是 YYYYMMDD"); return value; }
    const [, y, mo, d] = match.map(Number);
    const probe = new Date(0);
    probe.setUTCFullYear(y, mo - 1, d);
    if (y < 2000 || y > 2100 || probe.getUTCFullYear() !== y || probe.getUTCMonth() !== mo - 1 || probe.getUTCDate() !== d) {
      fail(path, "日期不存在或超出範圍");
    }
    return value;
  };
  const lines = (value, path, max = 40) => array(value, path, max).map((item, index) => {
    const line = object(item, `${path}[${index}]`);
    return { label: string(required(line.label, `${path}[${index}].label`), `${path}[${index}].label`, 120), value: string(required(line.value, `${path}[${index}].value`), `${path}[${index}].value`, 1000) };
  });

  if (typeof raw !== "string") return { error: "JSON 內容必須是字串" };
  if (utf8Length(raw) > CONFIG.maxPayloadBytes) return { error: "JSON 超過 512 KiB" };
  let root;
  try { root = JSON.parse(raw); } catch (error) { return { error: "JSON 損壞" }; }
  root = object(root, "$");
  if (required(root.schemaVersion, "$.schemaVersion") !== SCHEMA_VERSION) fail("$.schemaVersion", "唔支援嘅 schema");
  const generatedAt = timestamp(required(root.generatedAt, "$.generatedAt"), "$.generatedAt");
  const serviceDate = dateCode(required(root.serviceDate, "$.serviceDate"), "$.serviceDate");
  const theme = string(required(root.theme, "$.theme"), "$.theme", 40);
  if (!["classic", "ocean", "sunset", "forest", "violet", "mono"].includes(theme)) fail("$.theme", "未知主題");

  const freshness = object(required(root.freshness, "$.freshness"), "$.freshness");
  const parsedFreshness = {};
  for (const key of ["today", "info", "schedule", "weather", "warningsToday", "warningsInfo", "court"]) {
    parsedFreshness[key] = timestamp(freshness[key], `$.freshness.${key}`, true);
  }

  const system = object(required(root.system, "$.system"), "$.system");
  const capturedAt = timestamp(required(system.capturedAt, "$.system.capturedAt"), "$.system.capturedAt");
  const battery = object(required(system.battery, "$.system.battery"), "$.system.battery");
  const parsedBattery = {
    level: nullableNumber(battery.level, "$.system.battery.level", 0, 1),
    charging: boolean(required(battery.charging, "$.system.battery.charging"), "$.system.battery.charging"),
    fullyCharged: boolean(required(battery.fullyCharged, "$.system.battery.fullyCharged"), "$.system.battery.fullyCharged"),
    lowPowerMode: nullableBoolean(battery.lowPowerMode, "$.system.battery.lowPowerMode"),
    estimatedText: string(required(battery.estimatedText, "$.system.battery.estimatedText"), "$.system.battery.estimatedText", 200),
    rateText: string(required(battery.rateText, "$.system.battery.rateText"), "$.system.battery.rateText", 200),
  };
  const storage = object(required(system.storage, "$.system.storage"), "$.system.storage");
  const parsedStorage = {
    freeBytes: nullableNumber(storage.freeBytes, "$.system.storage.freeBytes", 0, Number.MAX_SAFE_INTEGER, true),
    totalBytes: nullableNumber(storage.totalBytes, "$.system.storage.totalBytes", 0, Number.MAX_SAFE_INTEGER, true),
  };
  if (parsedStorage.totalBytes === 0) fail("$.system.storage.totalBytes", "總容量不可為 0");
  if (parsedStorage.freeBytes !== null && parsedStorage.totalBytes !== null && parsedStorage.freeBytes > parsedStorage.totalBytes) fail("$.system.storage.freeBytes", "不可大於總容量");
  string(required(storage.freeText, "$.system.storage.freeText"), "$.system.storage.freeText", 100);
  string(required(storage.totalText, "$.system.storage.totalText"), "$.system.storage.totalText", 100);
  string(required(storage.usedText, "$.system.storage.usedText"), "$.system.storage.usedText", 100);
  const memory = object(required(system.memory, "$.system.memory"), "$.system.memory");
  const memoryTotal = nullableNumber(memory.totalBytes, "$.system.memory.totalBytes", 0, Number.MAX_SAFE_INTEGER, true);
  const memoryAvailable = nullableNumber(memory.availableBytes, "$.system.memory.availableBytes", 0, Number.MAX_SAFE_INTEGER, true);
  if (memoryTotal !== null && memoryAvailable !== null && memoryAvailable > memoryTotal) fail("$.system.memory.availableBytes", "不可大於總記憶體");
  lines(required(memory.lines, "$.system.memory.lines"), "$.system.memory.lines");
  const uptimeSeconds = nullableNumber(system.uptimeSeconds, "$.system.uptimeSeconds", 0, 315360000);
  string(required(system.uptimeText, "$.system.uptimeText"), "$.system.uptimeText", 200);
  const bootAt = timestamp(system.bootAt, "$.system.bootAt", true);
  string(required(system.systemName, "$.system.systemName"), "$.system.systemName", 80);
  string(required(system.systemVersion, "$.system.systemVersion"), "$.system.systemVersion", 80);
  string(required(system.versionText, "$.system.versionText"), "$.system.versionText", 160);
  nullableString(system.latestOS, "$.system.latestOS", 100);
  string(required(system.osStatus, "$.system.osStatus"), "$.system.osStatus", 200);

  const duty = object(required(root.duty, "$.duty"), "$.duty");
  boolean(required(duty.configured, "$.duty.configured"), "$.duty.configured");
  boolean(required(duty.failed, "$.duty.failed"), "$.duty.failed");
  const dutyDay = (value, path) => {
    if (value === null || value === undefined) return null;
    const day = object(value, path);
    return {
      date: dateCode(required(day.date, `${path}.date`), `${path}.date`),
      code: string(required(day.code, `${path}.code`), `${path}.code`, 40),
      title: string(required(day.title, `${path}.title`), `${path}.title`, 200),
      times: nullableString(day.times, `${path}.times`, 200),
      route: nullableString(day.route, `${path}.route`, 500),
      mealText: nullableString(day.mealText, `${path}.mealText`, 200),
      hoursText: nullableString(day.hoursText, `${path}.hoursText`, 100),
      hint: nullableString(day.hint, `${path}.hint`, 500),
      onAt: timestamp(day.onAt, `${path}.onAt`, true),
      offAt: timestamp(day.offAt, `${path}.offAt`, true),
    };
  };
  const parsedDuty = {
    today: dutyDay(duty.today, "$.duty.today"),
    tomorrow: dutyDay(duty.tomorrow, "$.duty.tomorrow"),
    events: array(required(duty.events, "$.duty.events"), "$.duty.events", 200).map((item, index) => {
      const event = object(item, `$.duty.events[${index}]`);
      const path = `$.duty.events[${index}]`;
      return {
        id: string(required(event.id, `${path}.id`), `${path}.id`, 120),
        action: string(required(event.action, `${path}.action`), `${path}.action`, 80),
        at: timestamp(required(event.at, `${path}.at`), `${path}.at`),
        displayAt: string(required(event.displayAt, `${path}.displayAt`), `${path}.displayAt`, 80),
        title: string(required(event.title, `${path}.title`), `${path}.title`, 200),
        detail: string(required(event.detail, `${path}.detail`), `${path}.detail`, 1000),
        place: string(required(event.place, `${path}.place`), `${path}.place`, 300),
        note: string(required(event.note, `${path}.note`), `${path}.note`, 1000),
      };
    }),
    weekText: nullableString(duty.weekText, "$.duty.weekText", 300),
    nextHoliday: duty.nextHoliday === null || duty.nextHoliday === undefined ? null : object(duty.nextHoliday, "$.duty.nextHoliday"),
    detailLines: lines(required(duty.detailLines, "$.duty.detailLines"), "$.duty.detailLines"),
  };
  if (parsedDuty.nextHoliday) {
    const path = "$.duty.nextHoliday";
    string(required(parsedDuty.nextHoliday.title, `${path}.title`), `${path}.title`, 200);
    string(required(parsedDuty.nextHoliday.rangeText, `${path}.rangeText`), `${path}.rangeText`, 200);
    number(required(parsedDuty.nextHoliday.daysAway, `${path}.daysAway`), `${path}.daysAway`, 0, 3660, true);
  }

  const school = object(required(root.school, "$.school"), "$.school");
  array(required(school.failed, "$.school.failed"), "$.school.failed", 20).forEach((name, index) => string(name, `$.school.failed[${index}]`, 200));
  const schoolDay = (value, path) => {
    const day = object(value, path);
    array(required(day.cycle, `${path}.cycle`), `${path}.cycle`, 20).forEach((title, index) => string(title, `${path}.cycle[${index}]`, 200));
    array(required(day.items, `${path}.items`), `${path}.items`, 100).forEach((item, index) => {
      const entry = object(item, `${path}.items[${index}]`);
      const itemPath = `${path}.items[${index}]`;
      string(required(entry.title, `${itemPath}.title`), `${itemPath}.title`, 300);
      const start = timestamp(required(entry.start, `${itemPath}.start`), `${itemPath}.start`);
      const end = timestamp(required(entry.end, `${itemPath}.end`), `${itemPath}.end`);
      if (start !== null && end !== null && end < start) fail(`${itemPath}.end`, "不可早於 start");
      boolean(required(entry.allDay, `${itemPath}.allDay`), `${itemPath}.allDay`);
    });
    return day;
  };
  schoolDay(required(school.today, "$.school.today"), "$.school.today");
  schoolDay(required(school.tomorrow, "$.school.tomorrow"), "$.school.tomorrow");

  const weather = object(required(root.weather, "$.weather"), "$.weather");
  boolean(required(weather.available, "$.weather.available"), "$.weather.available");
  timestamp(weather.fetchedAt, "$.weather.fetchedAt", true);
  nullableNumber(weather.currentTemp, "$.weather.currentTemp", -100, 100);
  const weatherDay = (value, path) => {
    if (value === null || value === undefined) return;
    const day = object(value, path);
    number(required(day.code, `${path}.code`), `${path}.code`, 0, 9999, true);
    string(required(day.codeText, `${path}.codeText`), `${path}.codeText`, 100);
    string(required(day.symbol, `${path}.symbol`), `${path}.symbol`, 100);
    const min = number(required(day.minTemp, `${path}.minTemp`), `${path}.minTemp`, -100, 100);
    const max = number(required(day.maxTemp, `${path}.maxTemp`), `${path}.maxTemp`, -100, 100);
    if (min !== null && max !== null && min > max) fail(`${path}.minTemp`, "不可大於 maxTemp");
    string(required(day.tempText, `${path}.tempText`), `${path}.tempText`, 100);
    nullableNumber(day.rainChance, `${path}.rainChance`, 0, 100, true);
    nullableNumber(day.uvIndex, `${path}.uvIndex`, 0, 20);
  };
  weatherDay(weather.today, "$.weather.today");
  weatherDay(weather.tomorrow, "$.weather.tomorrow");
  array(required(weather.daily, "$.weather.daily"), "$.weather.daily", 14).forEach((item, index) => {
    const day = object(item, `$.weather.daily[${index}]`);
    const path = `$.weather.daily[${index}]`;
    dateCode(required(day.date, `${path}.date`), `${path}.date`);
    weatherDay(required(day.day, `${path}.day`), `${path}.day`);
  });

  const warnings = object(required(root.warnings, "$.warnings"), "$.warnings");
  boolean(required(warnings.available, "$.warnings.available"), "$.warnings.available");
  array(required(warnings.items, "$.warnings.items"), "$.warnings.items", 30).forEach((item, index) => {
    const warning = object(item, `$.warnings.items[${index}]`);
    const path = `$.warnings.items[${index}]`;
    string(required(warning.text, `${path}.text`), `${path}.text`, 1000);
    boolean(required(warning.severe, `${path}.severe`), `${path}.severe`);
  });
  const train = object(required(root.train, "$.train"), "$.train");
  boolean(required(train.available, "$.train.available"), "$.train.available");
  string(required(train.stateText, "$.train.stateText"), "$.train.stateText", 200);
  string(required(train.message, "$.train.message"), "$.train.message", 1000);

  const environment = object(required(root.environment, "$.environment"), "$.environment");
  array(required(environment.sections, "$.environment.sections"), "$.environment.sections", 20).forEach((item, index) => {
    const section = object(item, `$.environment.sections[${index}]`);
    const path = `$.environment.sections[${index}]`;
    string(required(section.id, `${path}.id`), `${path}.id`, 80, true);
    string(required(section.title, `${path}.title`), `${path}.title`, 200);
    lines(required(section.lines, `${path}.lines`), `${path}.lines`);
  });
  const vps = object(required(root.vps, "$.vps"), "$.vps");
  boolean(required(vps.configured, "$.vps.configured"), "$.vps.configured");
  boolean(required(vps.available, "$.vps.available"), "$.vps.available");
  boolean(required(vps.failed, "$.vps.failed"), "$.vps.failed");
  lines(required(vps.lines, "$.vps.lines"), "$.vps.lines");

  const courts = object(required(root.courts, "$.courts"), "$.courts");
  timestamp(courts.listDate, "$.courts.listDate", true);
  timestamp(courts.updatedAt, "$.courts.updatedAt", true);
  const courtDays = array(required(courts.items, "$.courts.items"), "$.courts.items", 4);
  courtDays.forEach((item, index) => {
    const day = object(item, `$.courts.items[${index}]`);
    const path = `$.courts.items[${index}]`;
    string(required(day.code, `${path}.code`), `${path}.code`, 40, true);
    string(required(day.name, `${path}.name`), `${path}.name`, 200);
    dateCode(required(day.dateCode, `${path}.dateCode`), `${path}.dateCode`);
    timestamp(day.fetchedAt, `${path}.fetchedAt`, true);
    boolean(required(day.error, `${path}.error`), `${path}.error`);
    number(required(day.total, `${path}.total`), `${path}.total`, 0, 10000, true);
    boolean(required(day.truncated, `${path}.truncated`), `${path}.truncated`);
    array(required(day.categories, `${path}.categories`), `${path}.categories`, 40).forEach((category, categoryIndex) => {
      const entry = object(category, `${path}.categories[${categoryIndex}]`);
      const categoryPath = `${path}.categories[${categoryIndex}]`;
      string(required(entry.category, `${categoryPath}.category`), `${categoryPath}.category`, 80);
      string(required(entry.categoryTitle, `${categoryPath}.categoryTitle`), `${categoryPath}.categoryTitle`, 200);
      number(required(entry.count, `${categoryPath}.count`), `${categoryPath}.count`, 0, 10000, true);
    });
    string(required(day.deepLink, `${path}.deepLink`), `${path}.deepLink`, 2048);
    array(required(day.cases, `${path}.cases`), `${path}.cases`, 80).forEach((caseItem, caseIndex) => {
      const entry = object(caseItem, `${path}.cases[${caseIndex}]`);
      const casePath = `${path}.cases[${caseIndex}]`;
      string(required(entry.room, `${casePath}.room`), `${casePath}.room`, 120);
      string(required(entry.judge, `${casePath}.judge`), `${casePath}.judge`, 300);
      nullableNumber(entry.minutes, `${casePath}.minutes`, 0, 1439, true);
      string(required(entry.timeText, `${casePath}.timeText`), `${casePath}.timeText`, 20);
      string(required(entry.caseNo, `${casePath}.caseNo`), `${casePath}.caseNo`, 200);
      nullableString(entry.nature, `${casePath}.nature`, 500);
      nullableString(entry.offence, `${casePath}.offence`, 1000);
      string(required(entry.category, `${casePath}.category`), `${casePath}.category`, 80);
      string(required(entry.categoryTitle, `${casePath}.categoryTitle`), `${casePath}.categoryTitle`, 200);
      string(required(entry.detailText, `${casePath}.detailText`), `${casePath}.detailText`, 1000);
      string(required(entry.deepLink, `${casePath}.deepLink`), `${casePath}.deepLink`, 2048);
    });
  });

  if (errors.length) return { error: errors[0] };
  return {
    data: root,
    generatedAt,
    parsedFreshness,
    system: { capturedAt, battery: parsedBattery, storage: parsedStorage, uptimeSeconds, bootAt },
  };
}

// ---- iCloud 輸入 + local last-good cache ------------------------------

async function loadSnapshot() {
  const cloud = safe(() => FileManager.iCloud(), null);
  const directory = safe(() => cloud && cloud.documentsDirectory(), null);
  let raw = null;
  if (cloud && directory) {
    const path = `${directory.replace(/\/$/, "")}/i-widget.json`;
    // 官方 FileManager API 多為同步；await 同時兼容回傳 Promise 嘅版本。
    await safeAsync(() => cloud.downloadFileFromiCloud(path), null);
    const exists = await safeAsync(() => cloud.fileExists(path), null);
    if (exists !== false) {
      const downloaded = await safeAsync(() => cloud.readString(path), null);
      if (typeof downloaded === "string") raw = downloaded;
    }
    const validated = raw === null ? null : validatePayload(raw, NOW);
    if (validated && !validated.error) {
      const local = safe(() => FileManager.local(), null);
      const localDirectory = safe(() => local && local.documentsDirectory(), null);
      if (local && localDirectory) {
        const localPath = `${localDirectory.replace(/\/$/, "")}/${CONFIG.cacheName}`;
        await safeAsync(() => local.writeString(raw, localPath), null);
      }
      return { ...validated, raw, source: "iCloud" };
    }
  }

  const local = safe(() => FileManager.local(), null);
  const localDirectory = safe(() => local && local.documentsDirectory(), null);
  const cached = local && localDirectory ? await safeAsync(() => local.readString(`${localDirectory.replace(/\/$/, "")}/${CONFIG.cacheName}`), null) : null;
  const validated = typeof cached === "string" ? validatePayload(cached, NOW) : null;
  return validated && !validated.error ? { ...validated, raw: cached, source: "cache" } : null;
}

// ---- 格式／新鮮度 -----------------------------------------------------

function dayProgress(now) {
  return (now - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000;
}

function pct(fraction) {
  return fraction === null || fraction === undefined ? "—" : `${Math.round(fraction * 100)}%`;
}

function pad(value) { return String(value).padStart(2, "0"); }
function hhmm(date) { return `${pad(date.getHours())}:${pad(date.getMinutes())}`; }
function dateCode(now) { return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`; }

function formatBytes(value) {
  if (value === null || value === undefined) return MISSING;
  let size = value;
  for (const unit of ["B", "KB", "MB"]) {
    if (size < 1000) return `${size.toFixed(0)} ${unit}`;
    size /= 1000;
  }
  return size < 1000 ? `${size.toFixed(1)} GB` : `${(size / 1000).toFixed(2)} TB`;
}

function formatUptime(seconds) {
  if (seconds === null || seconds === undefined || !Number.isFinite(seconds)) return MISSING;
  const total = Math.max(0, Math.floor(seconds));
  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (days) return `${days} 天 ${hours} 小時`;
  if (hours) return `${hours} 小時 ${minutes} 分`;
  return `${minutes} 分`;
}

function freshnessFor(view, snapshot) {
  if (!snapshot) return null;
  if (view === "today") return snapshot.parsedFreshness.today;
  if (view === "info") return snapshot.parsedFreshness.info;
  if (view === "court") return snapshot.parsedFreshness.court ?? Date.parse(snapshot.data.courts.updatedAt);
  return null;
}

function freshnessText(view, snapshot) {
  const stamp = freshnessFor(view, snapshot);
  if (stamp === null || !Number.isFinite(stamp)) return MISSING;
  const date = new Date(stamp);
  const sameDay = date.toDateString() === NOW.toDateString();
  return `更新於 ${sameDay ? hhmm(date) : `${date.getMonth() + 1}月${date.getDate()}日 ${hhmm(date)}`}${snapshot.source === "cache" ? " · 快取" : ""}`;
}

// ---- 時鐘（保留原有行為）--------------------------------------------

function midnightOf(now) { return new Date(now.getFullYear(), now.getMonth(), now.getDate()); }

function addClock(parent, size, align) {
  const live = NOW.getHours() !== 0;
  const date = parent.addDate(live ? midnightOf(NOW) : NOW);
  if (live) date.applyTimerStyle();
  else date.applyTimeStyle();
  date.font = Font.boldSystemFont(size);
  date.textColor = C.label;
  date.lineLimit = 1;
  date.minimumScaleFactor = 0.5;
  if (align === "center") date.centerAlignText();
  else date.leftAlignText();
  return date;
}

function nextReload(now) {
  // 00:xx 靜態時鐘要喺 01:00 前 reload；跨日亦要喺 00:00 前 reload。
  const limit = CONFIG.reloadMinutes * 60000;
  const edges = [0, 1].map((hour) => {
    const edge = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, 0, 20);
    return edge <= now ? new Date(edge.getTime() + 86400000) : edge;
  });
  const untilEdge = Math.min(...edges.map((edge) => edge - now));
  return new Date(now.getTime() + Math.min(limit, untilEdge));
}

// ---- 共用元件 ---------------------------------------------------------

function text(parent, string, size, color, bold) {
  const t = parent.addText(String(string));
  t.font = bold ? Font.boldSystemFont(size) : Font.systemFont(size);
  t.textColor = color;
  t.lineLimit = 1;
  t.minimumScaleFactor = 0.7;
  return t;
}

function multilineText(parent, string, size, color, bold, lines = 2) {
  const t = text(parent, string, size, color, bold);
  t.lineLimit = lines;
  return t;
}

function symbol(parent, name, color, size) {
  const sym = safe(() => SFSymbol.named(name), null);
  if (!sym) return null;
  const image = parent.addImage(sym.image);
  image.tintColor = color;
  image.imageSize = new Size(size, size);
  image.applyFittingContentMode();
  return image;
}

function bar(parent, fraction, color, width, height) {
  const track = parent.addStack();
  track.layoutHorizontally();
  track.size = new Size(width, height);
  track.cornerRadius = height / 2;
  track.backgroundColor = C.track;
  const clamped = Math.max(0, Math.min(1, fraction || 0));
  if (clamped > 0) {
    const fill = track.addStack();
    fill.size = new Size(Math.max(height, Math.round(width * clamped)), height);
    fill.cornerRadius = height / 2;
    fill.backgroundColor = color;
  }
  track.addSpacer();
  return track;
}

function card(parent, { icon, tint, title, value, valueColor, fraction, barColor }) {
  const row = parent.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  row.setPadding(9, 12, 9, 12);
  row.cornerRadius = 12;
  row.backgroundColor = C.card;
  if (symbol(row, icon, tint, 16)) row.addSpacer(8);
  text(row, title, 14, C.secondary, false);
  row.addSpacer();
  if (fraction !== null && fraction !== undefined) {
    bar(row, fraction, barColor || tint, 70, 6);
    row.addSpacer(8);
  }
  text(row, value, 14, valueColor || C.label, true);
  return row;
}

function batteryColor(level, charging) {
  if (charging) return C.green;
  if (level === null) return C.secondary;
  if (level <= 0.2) return C.red;
  return level <= 0.4 ? C.orange : C.green;
}

function batterySymbol(level, charging) {
  if (charging) return "battery.100percent.bolt";
  if (level === null) return "battery.0percent";
  for (const [threshold, name] of [[0.88, "100"], [0.63, "75"], [0.38, "50"], [0.13, "25"]]) if (level >= threshold) return `battery.${name}percent`;
  return "battery.0percent";
}

function batteryChip(parent, device, size) {
  const color = batteryColor(device.level, device.charging);
  if (symbol(parent, batterySymbol(device.level, device.charging), color, size)) parent.addSpacer(4);
  text(parent, pct(device.level), size, color, true);
}

function header(parent, size, trailing) {
  const row = parent.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  text(row, WEEKDAYS[NOW.getDay()], size, C.accent, true);
  row.addSpacer(6);
  text(row, `${NOW.getMonth() + 1}月${NOW.getDate()}日`, size, C.secondary, false);
  row.addSpacer();
  if (trailing) trailing(row);
  return row;
}

function viewHeading(parent, view, snapshot, family) {
  const names = { today: "今日", info: "各項資訊", court: "法院案件" };
  const row = parent.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  text(row, names[view], family === "small" ? 15 : 18, C.label, true);
  row.addSpacer();
  text(row, freshnessText(view, snapshot), family === "small" ? 10 : 11, C.secondary, false);
  return row;
}

function setupNotice(parent, message = "請喺 iWidget app 匯出 JSON，並授權 iCloud／Scriptable folder") {
  const row = parent.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  row.setPadding(9, 10, 9, 10);
  row.cornerRadius = 10;
  row.backgroundColor = C.card;
  if (symbol(row, "folder.badge.questionmark", C.orange, 14)) row.addSpacer(6);
  multilineText(row, `${MISSING} · ${message}`, 11, C.secondary, false, 2);
}

function lineRow(parent, label, value, color = C.label, valueSize = 13) {
  const row = parent.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  text(row, label, valueSize, C.secondary, false);
  row.addSpacer(6);
  text(row, value || MISSING, valueSize, value ? color : C.secondary, Boolean(value));
  return row;
}

function sectionLabel(parent, title) {
  const row = parent.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  text(row, title, 12, C.accent, true);
  row.addSpacer();
}

function rowBudget(family) {
  return family === "small" ? 4 : family === "medium" ? 6 : family === "extraLarge" ? 11 : 8;
}

// ---- clock view：原有小／中／大／鎖屏版面 -----------------------------

function buildSmall(w, device) {
  w.setPadding(12, 14, 12, 14);
  header(w, 13, null);
  w.addSpacer();
  addClock(w, 30, "left");
  w.addSpacer();
  const row = w.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  batteryChip(row, device, 14);
  row.addSpacer();
}

function buildMedium(w, device) {
  w.setPadding(14, 16, 14, 16);
  header(w, 14, (row) => batteryChip(row, device, 14));
  w.addSpacer();
  addClock(w, 50, "left");
  w.addSpacer();
  const row = w.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  if (symbol(row, "iphone.gen3", C.gray, 14)) row.addSpacer(6);
  text(row, device.version, 14, C.label, false);
  row.addSpacer();
  if (CONFIG.showDayProgress) {
    const progress = dayProgress(NOW);
    bar(row, progress, C.blue, 70, 6);
    row.addSpacer(8);
    text(row, pct(progress), 14, C.secondary, true);
  }
}

function buildLarge(w, device) {
  w.setPadding(14, 14, 14, 14);
  header(w, 15, null);
  w.addSpacer();
  const clockRow = w.addStack();
  clockRow.layoutHorizontally();
  clockRow.addSpacer();
  addClock(clockRow, 60, "center");
  clockRow.addSpacer();
  w.addSpacer();
  const batteryTint = batteryColor(device.level, device.charging);
  let batteryValue = pct(device.level);
  if (device.charging) batteryValue += device.full ? " · 已充滿" : " · 充電中";
  card(w, { icon: batterySymbol(device.level, device.charging), tint: batteryTint, title: "電量", value: batteryValue, valueColor: batteryTint, fraction: device.level });
  w.addSpacer(5);
  card(w, { icon: "iphone.gen3", tint: C.gray, title: "系統版本", value: device.version });
  if (CONFIG.showBrightness && device.brightness !== null) {
    w.addSpacer(5);
    card(w, { icon: "sun.max.fill", tint: C.orange, title: "螢幕亮度", value: pct(device.brightness), fraction: device.brightness });
  }
  if (CONFIG.showDayProgress) {
    const progress = dayProgress(NOW);
    w.addSpacer(5);
    card(w, { icon: "sun.horizon.fill", tint: C.indigo, title: "今日進度", value: pct(progress), fraction: progress });
  }
}

function buildAccessory(w, family, device) {
  if (family === "accessoryInline") {
    w.addText(`${WEEKDAYS[NOW.getDay()]} ${NOW.getMonth() + 1}月${NOW.getDate()}日 · ${pct(device.level)}`);
  } else if (family === "accessoryCircular") {
    const stack = w.addStack();
    stack.layoutVertically();
    stack.centerAlignContent();
    symbol(stack, batterySymbol(device.level, device.charging), C.label, 14);
    const t = stack.addText(pct(device.level));
    t.font = Font.boldSystemFont(13);
    t.centerAlignText();
  } else {
    w.addAccessoryWidgetBackground = true;
    const day = w.addText(`${WEEKDAYS[NOW.getDay()]} ${NOW.getMonth() + 1}月${NOW.getDate()}日`);
    day.font = Font.semiboldSystemFont(12);
    addClock(w, 24, "left");
    const row = w.addStack();
    row.layoutHorizontally();
    row.centerAlignContent();
    symbol(row, batterySymbol(device.level, device.charging), C.label, 11);
    row.addSpacer(4);
    const t = row.addText(pct(device.level));
    t.font = Font.systemFont(11);
  }
}

// ---- today view -------------------------------------------------------

function dutyStatus(duty) {
  if (duty.failed) return duty.today ? "更份讀取失敗 · 沿用快取" : "更份讀取失敗";
  if (duty.today) return null;
  return duty.configured ? "今日唔使返工" : "更份未設定";
}

function warningStatus(warnings) {
  if (!warnings.available) return MISSING;
  if (!warnings.items.length) return "沒有警告";
  return warnings.items.map((item) => item.text).join(" · ");
}

function schoolFailureText(failed) {
  return failed && failed.length ? `學校讀取失敗／部分失敗：${failed.join("、")}` : null;
}

function schoolSummary(parent, school, label, failed = [], size = 12) {
  const failure = schoolFailureText(failed);
  const cycle = school.cycle.join(" · ");
  const item = school.items[0];
  if (failure) text(parent, `${label} · ${failure}`, size, C.red, true);
  if (cycle) text(parent, `${label} · ${cycle}`, size, C.indigo, true);
  if (item) {
    const time = item.allDay ? "全日" : `${hhmm(new Date(item.start))}–${hhmm(new Date(item.end))}`;
    lineRow(parent, `${label} ${time}`, item.title, C.label, size);
  } else if (!failure) {
    text(parent, `${label} · ${cycle ? "沒有其他日程" : "沒有日程"}`, size, C.secondary, false);
  }
}

function shortDate(code) {
  if (!/^\d{8}$/.test(code || "")) return code || MISSING;
  return `${Number(code.slice(4, 6))}月${Number(code.slice(6, 8))}日`;
}

function dutyDayText(day) {
  if (!day) return "沒有更份";
  return `${day.title || "更份"}${day.times ? ` · ${day.times}` : ""}`;
}

function buildToday(w, family, snapshot) {
  const data = snapshot && snapshot.data;
  if (!data) { setupNotice(w); return; }
  viewHeading(w, "today", snapshot, family);
  w.addSpacer(6);
  const budget = rowBudget(family);
  let rows = 0;
  const add = (fn) => {
    if (rows >= budget) return;
    if (fn() !== false) rows++;
  };
  const status = dutyStatus(data.duty);

  if (family === "small") {
    // small 只保留四行內；有事件時用第一宗即將發生嘅事件取代靜態更份。
    const event = data.duty.events.filter((item) => Date.parse(item.at) >= NOW).sort((a, b) => Date.parse(a.at) - Date.parse(b.at))[0];
    if (status) {
      text(w, status, 11, status.includes("失敗") ? C.red : C.secondary, true);
      if (data.duty.today) text(w, `${data.duty.today.title || "今日更份"}${data.duty.today.times ? ` · ${data.duty.today.times}` : ""}`, 10, C.label, false);
    } else if (event) text(w, `${event.displayAt} · ${event.action} ${event.title}`, 11, C.label, true);
    else {
      text(w, data.duty.today.title || "今日更份", 12, C.label, true);
      text(w, data.duty.today.times || MISSING, 11, C.secondary, false);
    }
    const school = data.school.today;
    const failure = schoolFailureText(data.school.failed);
    const schoolText = failure || school.items[0]?.title || school.cycle.join("／") || "沒有日程";
    text(w, `學校 · ${schoolText}`, 10, failure ? C.red : C.indigo, false);
    const weather = data.weather.available && data.weather.today;
    const weatherText = weather ? `${weather.codeText} ${weather.tempText}` : "天氣未有資料";
    const trainText = data.train.available ? data.train.stateText : "屯馬綫未有資料";
    text(w, `${weatherText} · ${trainText}`, 10, C.secondary, false);
    return;
  }

  add(() => {
    sectionLabel(w, "更份");
    if (status) text(w, status, 12, status.includes("失敗") ? C.red : C.secondary, true);
    const duty = data.duty.today;
    if (duty) {
      text(w, duty.title || "今日更份", family === "medium" ? 18 : 20, C.label, true);
      lineRow(w, "時間", duty.times);
      if (duty.route) lineRow(w, "路線", duty.route);
      if (family === "extraLarge") {
        if (duty.mealText) lineRow(w, "用膳", duty.mealText);
        if (duty.hoursText) lineRow(w, "時數", duty.hoursText);
        if (duty.hint) lineRow(w, "提示", duty.hint);
        for (const line of data.duty.detailLines.slice(0, 3)) lineRow(w, line.label, line.value);
      }
    }
  });
  add(() => {
    const events = data.duty.events
      .filter((item) => Date.parse(item.at) >= NOW)
      .sort((a, b) => Date.parse(a.at) - Date.parse(b.at))
      .slice(0, family === "extraLarge" ? 4 : 2);
    if (!events.length) return false;
    sectionLabel(w, "即將發生");
    for (const event of events) {
      text(w, `${event.displayAt} · ${event.action} · ${event.title}`, 12, C.label, true);
      const detail = [event.place, event.detail].filter(Boolean).join(" · ");
      if (detail) multilineText(w, detail, 10, C.secondary, false, 2);
    }
  });
  add(() => {
    if (!data.duty.weekText && !data.duty.tomorrow && !data.duty.nextHoliday) return false;
    sectionLabel(w, "方案規劃");
    if (data.duty.weekText) lineRow(w, "本週", data.duty.weekText);
    if (data.duty.tomorrow) lineRow(w, "明日更份", dutyDayText(data.duty.tomorrow));
    if (data.duty.nextHoliday) {
      const holiday = data.duty.nextHoliday;
      lineRow(w, "下個假期", `${holiday.title} · ${holiday.rangeText} · ${holiday.daysAway} 天後`);
    }
  });
  add(() => {
    sectionLabel(w, "學校");
    schoolSummary(w, data.school.today, "今日", data.school.failed);
    schoolSummary(w, data.school.tomorrow, "明日");
  });
  add(() => {
    sectionLabel(w, "天氣");
    if (data.weather.available && data.weather.today) {
      const weather = data.weather.today;
      const temp = weather.tempText || `${weather.minTemp}–${weather.maxTemp}°`;
      lineRow(w, weather.codeText, `${data.weather.currentTemp === null ? "" : `${Math.round(data.weather.currentTemp)}° · `}${temp}`, C.blue, 13);
    } else text(w, MISSING, 12, C.secondary, false);
    if (data.weather.available && data.weather.daily.length) {
      const daily = data.weather.daily.slice(0, 7).map((item) => {
        const rain = item.day.rainChance === null ? "" : ` · 雨 ${item.day.rainChance}%`;
        return `${shortDate(item.date)} ${item.day.codeText} ${item.day.tempText}${rain}`;
      }).join(" · ");
      multilineText(w, daily, 10, C.secondary, false, family === "extraLarge" ? 3 : 2);
    }
  });
  add(() => {
    sectionLabel(w, "屯馬綫");
    text(w, data.train.available ? [data.train.stateText, data.train.message].filter(Boolean).join(" · ") || "正常" : MISSING, 12, data.train.available ? C.green : C.secondary, false);
  });
  add(() => {
    sectionLabel(w, "天氣警告");
    const warnings = warningStatus(data.warnings);
    multilineText(w, warnings, 11, data.warnings.items.some((item) => item.severe) ? C.red : C.secondary, false, 2);
  });
}

// ---- info view --------------------------------------------------------

function infoUptime(snapshot) {
  if (!snapshot) return MISSING;
  if (snapshot.system.bootAt !== null) return formatUptime((NOW - snapshot.system.bootAt) / 1000);
  return formatUptime(snapshot.system.uptimeSeconds);
}

function vpsStatus(vps) {
  if (!vps.configured) return { text: "VPS 未設定", color: C.secondary, cached: false };
  if (vps.failed) return { text: vps.available ? "VPS 讀取失敗 · 沿用快取" : "VPS 讀取失敗", color: C.red, cached: vps.available };
  if (!vps.available) return { text: "VPS 未有資料", color: C.secondary, cached: false };
  return null;
}

function rainChance(weather) {
  return weather && weather.rainChance !== null && weather.rainChance !== undefined ? `${weather.rainChance}%` : MISSING;
}

function buildInfo(w, family, snapshot) {
  const data = snapshot && snapshot.data;
  if (!data) { setupNotice(w); return; }
  viewHeading(w, "info", snapshot, family);
  w.addSpacer(6);
  if (family === "small") {
    const free = snapshot.system.storage.freeBytes;
    const total = snapshot.system.storage.totalBytes;
    lineRow(w, "儲存", free === null ? MISSING : `${formatBytes(free)}${total === null ? " 可用" : ` / ${formatBytes(total)}`}`, C.label, 11);
    lineRow(w, "開機", infoUptime(snapshot), C.label, 11);
    const lowPower = snapshot.system.battery.lowPowerMode;
    lineRow(w, "低耗電", lowPower === null ? MISSING : lowPower ? "開啟" : "關閉", lowPower === null ? C.secondary : lowPower ? C.orange : C.green, 11);
    text(w, data.system.versionText, 10, C.secondary, false);
    return;
  }
  const budget = rowBudget(family);
  let rows = 0;
  const add = (fn) => { if (rows < budget) { fn(); rows++; } };
  const free = snapshot.system.storage.freeBytes;
  const total = snapshot.system.storage.totalBytes;
  const lowPower = snapshot.system.battery.lowPowerMode;

  add(() => {
    sectionLabel(w, "系統");
    const storageText = free === null ? MISSING : `${formatBytes(free)}${total === null ? " 可用" : ` / ${formatBytes(total)} 可用`}`;
    lineRow(w, "儲存空間", storageText, free !== null && total !== null && free / total < 0.1 ? C.orange : C.label);
    lineRow(w, "開機時間", infoUptime(snapshot));
    lineRow(w, "低耗電", lowPower === null ? MISSING : lowPower ? "開啟" : "關閉", lowPower === null ? C.secondary : lowPower ? C.orange : C.green);
    lineRow(w, data.system.versionText, data.system.latestOS ? `${data.system.osStatus} · 最新 ${data.system.latestOS}` : data.system.osStatus);
  });
  add(() => {
    sectionLabel(w, "電池／記憶體");
    lineRow(w, "續航估算", snapshot.system.battery.estimatedText || MISSING);
    lineRow(w, "耗電速率", snapshot.system.battery.rateText || MISSING);
    if (!data.system.memory.lines.length) text(w, MISSING, 12, C.secondary, false);
    for (const line of data.system.memory.lines.slice(0, family === "extraLarge" ? 6 : 3)) lineRow(w, line.label, line.value);
  });
  add(() => {
    sectionLabel(w, "天氣警告");
    multilineText(w, warningStatus(data.warnings), 11, data.warnings.items.some((item) => item.severe) ? C.red : C.secondary, false, 2);
  });
  add(() => {
    sectionLabel(w, "環境");
    let shown = 0;
    const maxSections = family === "extraLarge" ? 20 : 5;
    const maxLines = family === "medium" ? 4 : family === "extraLarge" ? 18 : 8;
    for (const section of data.environment.sections.slice(0, maxSections)) {
      if (shown >= maxLines) break;
      text(w, section.title, 11, C.accent, true);
      for (const line of section.lines.slice(0, maxLines - shown)) {
        lineRow(w, line.label, line.value);
        shown++;
      }
    }
    if (!shown) text(w, MISSING, 12, C.secondary, false);
  });
  add(() => {
    sectionLabel(w, "VPS");
    const status = vpsStatus(data.vps);
    if (status) text(w, status.text, 12, status.color, true);
    if (!status || status.cached) {
      if (!data.vps.lines.length) text(w, MISSING, 12, C.secondary, false);
      for (const line of data.vps.lines.slice(0, family === "extraLarge" ? 8 : 2)) lineRow(w, line.label, line.value);
    }
  });
  add(() => {
    sectionLabel(w, "天氣");
    if (!data.weather.available) text(w, MISSING, 12, C.secondary, false);
    else {
      if (data.weather.today) {
        const weather = data.weather.today;
        lineRow(w, weather.codeText, `${data.weather.currentTemp === null ? MISSING : `${Math.round(data.weather.currentTemp)}°`} · ${weather.tempText}`, C.blue);
      }
      lineRow(w, "今日降雨", rainChance(data.weather.today));
      lineRow(w, "明日降雨", rainChance(data.weather.tomorrow));
    }
    sectionLabel(w, "屯馬綫");
    text(w, data.train.available ? [data.train.stateText, data.train.message].filter(Boolean).join(" · ") || "正常" : MISSING, 12, data.train.available ? C.green : C.secondary, false);
  });
}

// ---- court view -------------------------------------------------------

function relevantCases(day, now, includeAll = false) {
  if (!day) return [];
  const minute = now.getHours() * 60 + now.getMinutes();
  return day.cases
    .filter((entry) => entry.minutes !== null && entry.minutes !== undefined && (includeAll || entry.minutes >= minute - 20))
    .map((entry, index) => ({ entry, index }))
    .sort((a, b) => a.entry.minutes - b.entry.minutes || a.index - b.index)
    .map(({ entry }) => entry);
}

function selectedCourtDays(data, now) {
  const stamp = data.courts.listDate === null || data.courts.listDate === undefined ? null : Date.parse(data.courts.listDate);
  const listDate = stamp === null ? null : new Date(stamp);
  const today = dateCode(now);
  const listCode = listDate ? dateCode(listDate) : null;
  // 過去日期匯出不可當成今日／未來案件；同日匯出仍保留今日 20 分鐘視窗。
  if (listCode && listCode < today) return [];
  const futureCode = listCode && listCode > today ? listCode : null;
  return data.courts.items
    .filter((day) => day.dateCode === today || (futureCode && day.dateCode === futureCode))
    .map((day) => ({ day, future: day.dateCode !== today }));
}

function buildCourt(w, family, snapshot) {
  const data = snapshot && snapshot.data;
  if (!data) { setupNotice(w); return; }
  viewHeading(w, "court", snapshot, family);
  w.addSpacer(8);
  const selected = selectedCourtDays(data, NOW);
  if (!selected.length) {
    const stamp = data.courts.listDate === null || data.courts.listDate === undefined ? null : Date.parse(data.courts.listDate);
    const listCode = stamp === null ? null : dateCode(new Date(stamp));
    const message = !data.courts.items.length ? MISSING : listCode && listCode < dateCode(NOW) ? "沒有相關案件" : listCode && listCode > dateCode(NOW) ? "JSON 未有相關案件表" : "JSON 未有今日案件表";
    text(w, message, 14, C.secondary, false);
    if (!data.courts.items.length) setupNotice(w, "請由 iWidget app 匯出法院案件");
    return;
  }
  const minute = NOW.getHours() * 60 + NOW.getMinutes();
  const maxCases = family === "small" ? 2 : family === "medium" ? 3 : family === "extraLarge" ? 8 : 5;
  let shown = 0;
  for (const { day, future } of selected) {
    if (shown >= maxCases) break;
    sectionLabel(w, future ? `${day.name} · ${shortDate(day.dateCode)}` : day.name);
    const cases = relevantCases(day, NOW, future);
    if (day.error) text(w, "案件表讀取失敗", 12, C.red, false);
    else if (!cases.length) text(w, future ? "該日沒有有時間嘅案件" : day.cases.length ? "未有進行中或之後嘅案件" : "今日沒有案件", 12, C.secondary, false);
    for (const entry of cases.slice(0, maxCases - shown)) {
      const ongoing = !future && entry.minutes <= minute && minute - entry.minutes < 20;
      const time = entry.timeText || `${pad(Math.floor(entry.minutes / 60))}:${pad(entry.minutes % 60)}`;
      const status = ongoing ? "進行中" : entry.minutes > minute || future ? "未開始" : "已過時間";
      const row = w.addStack();
      row.layoutVertically();
      safe(() => { row.url = entry.deepLink; }, null);
      const heading = text(row, `${time} · ${entry.caseNo} · ${status}`, family === "small" ? 11 : 13, ongoing ? C.green : C.label, true);
      safe(() => { heading.url = entry.deepLink; }, null);
      const detail = [entry.room, entry.judge, entry.nature || entry.offence].filter(Boolean).join(" · ");
      if (detail && family !== "small") {
        const detailText = text(row, detail, 10, C.secondary, false);
        safe(() => { detailText.url = entry.deepLink; }, null);
      }
      shown++;
    }
    if (day.truncated) text(w, "案件表只顯示部分", 10, C.orange, false);
  }
}

// ---- accessory view（任何 family 都用鎖屏式內容）----------------------

function accessorySummary(view, snapshot) {
  if (!snapshot) return MISSING;
  const data = snapshot.data;
  if (view === "court") {
    const count = selectedCourtDays(data, NOW).reduce((sum, { day, future }) => sum + relevantCases(day, NOW, future).length, 0);
    return count ? `${count} 宗` : "沒有案件";
  }
  if (view === "info") {
    const free = snapshot.system.storage.freeBytes;
    return free === null ? MISSING : `${formatBytes(free)} 可用`;
  }
  if (view === "today") {
    if (data.duty.failed) return data.duty.today ? "更份讀取失敗 · 沿用快取" : "更份讀取失敗";
    if (data.duty.today) return data.duty.today.times || data.duty.today.title;
    if (data.school.today.items.length) return data.school.today.items[0].title;
    if (data.weather.available && data.weather.today) return data.weather.today.tempText;
    return MISSING;
  }
  return pct(safe(() => Device.batteryLevel(), -1));
}

function buildAccessoryView(w, family, view, snapshot, device) {
  if (view === "accessory" && family.startsWith("accessory")) {
    if (snapshot) { buildAccessory(w, family, device); return; }
    if (family === "accessoryInline") {
      text(w, `未有資料 · 設定 JSON · ${pct(device.level)}`, 10, C.secondary, false);
    } else if (family === "accessoryCircular") {
      const stack = w.addStack();
      stack.layoutVertically();
      stack.centerAlignContent();
      symbol(stack, batterySymbol(device.level, device.charging), C.label, 12);
      text(stack, pct(device.level), 11, C.label, true).centerAlignText();
      text(stack, "未有資料", 8, C.secondary, false).centerAlignText();
    } else {
      w.addAccessoryWidgetBackground = true;
      text(w, `${WEEKDAYS[NOW.getDay()]} ${NOW.getMonth() + 1}月${NOW.getDate()}日`, 11, C.secondary, false);
      addClock(w, 22, "left");
      text(w, `${pct(device.level)} · 未有資料`, 10, C.label, false);
      text(w, "請設定 iCloud JSON", 9, C.secondary, false);
    }
    return;
  }
  if (family === "accessoryInline" || family === "accessoryCircular" || family === "accessoryRectangular") {
    const title = { today: "今日", info: "資訊", court: "法院" }[view];
    const value = accessorySummary(view, snapshot);
    if (family === "accessoryInline") {
      text(w, `${title} · ${value}${snapshot ? snapshot.source === "cache" ? " · 快取" : "" : " · 設定 JSON"}`, 10, C.label, false);
    } else if (family === "accessoryCircular") {
      const stack = w.addStack();
      stack.layoutVertically();
      stack.centerAlignContent();
      symbol(stack, !snapshot ? "folder.badge.questionmark" : view === "court" ? "building.columns.fill" : view === "today" ? "calendar" : "internaldrive.fill", C.label, 13);
      const t = multilineText(stack, value, 10, C.label, true, 2);
      t.centerAlignText();
    } else {
      w.addAccessoryWidgetBackground = true;
      text(w, title, 11, C.accent, true);
      multilineText(w, value, 15, C.label, true, 2);
      text(w, snapshot ? freshnessText(view, snapshot) : "請設定 iCloud JSON", 9, C.secondary, false);
    }
    return;
  }
  // 非鎖屏 family 揀 accessory view 時，顯示同樣嘅紧凑電量卡。
  w.setPadding(12, 14, 12, 14);
  const row = w.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  row.setPadding(12, 14, 12, 14);
  row.cornerRadius = 12;
  row.backgroundColor = C.card;
  symbol(row, batterySymbol(device.level, device.charging), batteryColor(device.level, device.charging), 22);
  row.addSpacer(10);
  text(row, "電量", 14, C.secondary, false);
  row.addSpacer();
  text(row, pct(device.level), 24, batteryColor(device.level, device.charging), true);
  w.addSpacer();
  text(w, `${WEEKDAYS[NOW.getDay()]} ${NOW.getMonth() + 1}月${NOW.getDate()}日`, 12, C.secondary, false);
  if (!snapshot) text(w, "未有資料 · 請設定 iCloud JSON", 10, C.secondary, false);
  w.addSpacer();
  addClock(w, family === "small" ? 30 : 48, "left");
}

// ---- 入口 -------------------------------------------------------------

function widgetURL(view, snapshot) {
  if (view === "today") return "iwidget://duty";
  if (view === "info") return "iwidget://info";
  if (view === "court") {
    const day = snapshot && snapshot.data.courts.items[0];
    return day && day.deepLink ? day.deepLink : "iwidget://court";
  }
  // clock／accessory 冇獨立 JSON 頁；開 app 今日更份，冇資料時亦適用。
  return "iwidget://duty";
}

function build(family, view, snapshot) {
  const device = readDevice();
  const w = new ListWidget();
  w.backgroundColor = C.bg;
  w.url = widgetURL(view, snapshot);
  w.spacing = 0;
  // 只代表 iOS 最早可 reload；實際時間由系統預算／低耗電決定。
  w.refreshAfterDate = nextReload(NOW);
  if (view === "clock" && !family.startsWith("accessory")) {
    if (family === "small") buildSmall(w, device);
    else if (family === "medium") buildMedium(w, device);
    else buildLarge(w, device);
  } else if (view === "clock") {
    buildAccessory(w, family, device);
  } else if (view === "accessory") {
    buildAccessoryView(w, family, view, snapshot, device);
  } else if (family.startsWith("accessory")) {
    buildAccessoryView(w, family, view, snapshot, device);
  } else {
    w.setPadding(14, 14, 14, 14);
    if (view === "today") buildToday(w, family, snapshot);
    else if (view === "info") buildInfo(w, family, snapshot);
    else buildCourt(w, family, snapshot);
  }
  return w;
}

function selectedView() {
  const parameters = safe(() => config.parameterValues, null) || safe(() => args && args.parameterValues, null);
  const requested = safe(() => parameters.view, CONFIG.previewView);
  return VIEWS.includes(requested) ? requested : CONFIG.previewView;
}

const family = config.widgetFamily || CONFIG.previewFamily;
const view = selectedView();
const snapshot = await loadSnapshot();
applyTheme(snapshot && snapshot.data.theme);
const widget = build(family, view, snapshot);

if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  const present = {
    small: "presentSmall", medium: "presentMedium", large: "presentLarge", extraLarge: "presentExtraLarge",
    accessoryInline: "presentAccessoryInline", accessoryCircular: "presentAccessoryCircular", accessoryRectangular: "presentAccessoryRectangular",
  }[family] || "presentLarge";
  await widget[present]();
}
Script.complete();
