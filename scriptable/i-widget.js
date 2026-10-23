// i-widget — iPhone「時間／系統狀態」widget（Scriptable 版，JavaScript）
//
// 安裝：App Store 裝 Scriptable → 新增 script，貼入呢個檔案 →
// 長按 Home Screen 加 Scriptable widget → 編輯 Widget → Script 揀呢隻。
//
// 同 Pyto 版嘅分別：Scriptable 嘅 Device API 讀唔到剩餘儲存空間、開機時間、低耗電模式，
// 所以呢個版本冇呢三項；另外加咗螢幕亮度同今日進度，並支援鎖屏 widget。
// 詳見 scriptable/README.md。

// ---- 設定 -------------------------------------------------------------

const CONFIG = {
  showBrightness: true, // 大尺寸：螢幕亮度卡
  showDayProgress: true, // 大尺寸／中尺寸：今日進度
  reloadMinutes: 30, // WidgetKit 每日預算 40–70 次，30 分鐘 = 48 次
  previewFamily: "large", // 喺 Scriptable app 入面行時預覽邊個尺寸
};

const WEEKDAYS = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"];

// ---- 顏色（淺色／深色自動適應，全部用系統色盤）--------------------------

const dyn = (light, dark) => Color.dynamic(light, dark);
const rgba = (hex, alpha) => new Color(hex, alpha);

const C = {
  bg: dyn(rgba("#ffffff", 1), rgba("#1c1c1e", 1)),
  label: dyn(rgba("#000000", 1), rgba("#ffffff", 1)),
  secondary: dyn(rgba("#3c3c43", 0.6), rgba("#ebebf5", 0.6)),
  card: dyn(rgba("#787880", 0.12), rgba("#787880", 0.24)), // 系統 tertiary fill
  track: dyn(rgba("#787880", 0.2), rgba("#787880", 0.36)),
  accent: dyn(rgba("#ff3b30", 1), rgba("#ff453a", 1)),
  green: dyn(rgba("#34c759", 1), rgba("#30d158", 1)),
  orange: dyn(rgba("#ff9500", 1), rgba("#ff9f0a", 1)),
  red: dyn(rgba("#ff3b30", 1), rgba("#ff453a", 1)),
  blue: dyn(rgba("#007aff", 1), rgba("#0a84ff", 1)),
  indigo: dyn(rgba("#5856d6", 1), rgba("#5e5ce6", 1)),
  gray: dyn(rgba("#8e8e93", 1), rgba("#8e8e93", 1)),
};

// ---- 資料 -------------------------------------------------------------

const NOW = typeof IWIDGET_NOW !== "undefined" ? IWIDGET_NOW : new Date();

function safe(fn, fallback) {
  try {
    const value = fn();
    return value === undefined ? fallback : value;
  } catch (error) {
    return fallback;
  }
}

function readDevice() {
  const level = safe(() => Device.batteryLevel(), null);
  return {
    level: typeof level === "number" && level >= 0 ? Math.min(level, 1) : null, // -1 = 讀唔到
    charging: safe(() => Device.isCharging(), false),
    full: safe(() => Device.isFullyCharged(), false),
    version: safe(() => `${Device.systemName()} ${Device.systemVersion()}`, "—"),
    brightness: safe(() => Device.screenBrightness(), null),
  };
}

function dayProgress(now) {
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return (now - start) / 86400000;
}

function pct(fraction) {
  return fraction === null || fraction === undefined ? "—" : `${Math.round(fraction * 100)}%`;
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
  const steps = [[0.88, "100"], [0.63, "75"], [0.38, "50"], [0.13, "25"]];
  for (const [threshold, name] of steps) if (level >= threshold) return `battery.${name}percent`;
  return "battery.0percent";
}

// ---- 時鐘 -------------------------------------------------------------
// 計時器樣式由今日 00:00 起數，由 iOS 即時跳動（顯示 h:mm:ss），唔使靠 reload。
// 計時器喺 1 小時內只顯示「分:秒」，所以 00:00–00:59 用 applyTimeStyle（靜態 HH:MM）。

function midnightOf(now) {
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
}

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
  // 要趕得及 00:00 同 01:00（計時器喺 00:xx 唔啱用；跨日會變 24:xx）
  const limit = CONFIG.reloadMinutes * 60000;
  const edges = [0, 1].map((hour) => {
    const edge = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, 0, 20);
    return edge <= now ? new Date(edge.getTime() + 86400000) : edge;
  });
  const untilEdge = Math.min(...edges.map((edge) => edge - now));
  return new Date(now.getTime() + Math.min(limit, untilEdge));
}

// ---- 元件 -------------------------------------------------------------

function text(parent, string, size, color, bold) {
  const t = parent.addText(string);
  t.font = bold ? Font.boldSystemFont(size) : Font.systemFont(size);
  t.textColor = color;
  t.lineLimit = 1;
  t.minimumScaleFactor = 0.7;
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

function batteryChip(parent, device, size) {
  const color = batteryColor(device.level, device.charging);
  if (symbol(parent, batterySymbol(device.level, device.charging), color, size)) parent.addSpacer(4);
  text(parent, pct(device.level), size, color, true);
}

// ---- 版面 -------------------------------------------------------------

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
  card(w, {
    icon: batterySymbol(device.level, device.charging),
    tint: batteryTint,
    title: "電量",
    value: batteryValue,
    valueColor: batteryTint,
    fraction: device.level,
  });
  w.addSpacer(5);
  card(w, { icon: "iphone.gen3", tint: C.gray, title: "系統版本", value: device.version });
  if (CONFIG.showBrightness && device.brightness !== null) {
    w.addSpacer(5);
    card(w, {
      icon: "sun.max.fill",
      tint: C.orange,
      title: "螢幕亮度",
      value: pct(device.brightness),
      fraction: device.brightness,
    });
  }
  if (CONFIG.showDayProgress) {
    const progress = dayProgress(NOW);
    w.addSpacer(5);
    card(w, {
      icon: "sun.horizon.fill",
      tint: C.indigo,
      title: "今日進度",
      value: pct(progress),
      fraction: progress,
    });
  }
}

// 鎖屏 widget（accessory*）：iOS 16+ 嘅 widget family，Pyto 做唔到。
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

function build(family) {
  const device = readDevice();
  const w = new ListWidget();
  w.backgroundColor = C.bg;
  w.spacing = 0;
  w.refreshAfterDate = nextReload(NOW);
  if (family.startsWith("accessory")) buildAccessory(w, family, device);
  else if (family === "small") buildSmall(w, device);
  else if (family === "medium") buildMedium(w, device);
  else buildLarge(w, device); // large／extraLarge
  return w;
}

// ---- 入口 -------------------------------------------------------------

const family = config.widgetFamily || CONFIG.previewFamily;
const widget = build(family);

if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  const present = {
    small: "presentSmall",
    medium: "presentMedium",
    large: "presentLarge",
    extraLarge: "presentExtraLarge",
    accessoryInline: "presentAccessoryInline",
    accessoryCircular: "presentAccessoryCircular",
    accessoryRectangular: "presentAccessoryRectangular",
  }[family] || "presentLarge";
  await widget[present]();
}
Script.complete();
