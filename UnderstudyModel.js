.pragma library

// Pure model code for the Understudy overlay: helper output in, rows out, no
// QML. Loaded in node by tests/model_test.sh.

var CATEGORIES = [
  { kind: "installer", title: "Omarchy installers", icon: "󰏗" },
  { kind: "package", title: "Repo packages", icon: "󰏖" },
  { kind: "aur", title: "AUR packages", icon: "󰣇" },
  { kind: "flatpak", title: "Flatpaks", icon: "󰏓" },
  { kind: "theme", title: "Themes", icon: "󰏘" },
  { kind: "plugin", title: "Plugins", icon: "󰐱" },
  { kind: "webapp", title: "Web apps", icon: "󰖟" },
  { kind: "tui", title: "TUI launchers", icon: "" },
  { kind: "appimage", title: "AppImages", icon: "󰀻" }
]

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function str(value) {
  return typeof value === "string" ? value : ""
}

function parseJson(text) {
  try { return JSON.parse(String(text || "")) } catch (e) { return null }
}

function iconFor(kind) {
  for (var i = 0; i < CATEGORIES.length; i++) if (CATEGORIES[i].kind === kind) return CATEGORIES[i].icon
  return "•"
}

// `understudy status --json`
function parseStatus(text) {
  var s = parseJson(text)
  if (!isObject(s)) return null
  return {
    role: s.role === "main" || s.role === "secondary" ? s.role : "",
    folder: str(s.folder),
    folderExists: s.folderExists === true,
    listExists: s.listExists === true,
    importedExists: s.importedExists === true,
    listGeneratedAt: str(s.listGeneratedAt),
    importedGeneratedAt: str(s.importedGeneratedAt),
    label: str(s.label),
    autoExport: s.autoExport === true
  }
}

// `understudy scan --json`
function parseScan(text) {
  var s = parseJson(text)
  if (!isObject(s) || !Array.isArray(s.rows)) return null
  var rows = []
  for (var i = 0; i < s.rows.length; i++) {
    var r = s.rows[i]
    if (!isObject(r) || typeof r.kind !== "string" || typeof r.name !== "string") continue
    rows.push({ kind: r.kind, name: r.name, note: str(r.note) })
  }
  return {
    rows: rows,
    counts: isObject(s.counts) ? s.counts : {},
    packages: isObject(s.packages) ? s.packages : {},
    firstInstall: str(s.first_install),
    omarchyVersion: str(s.omarchy_version),
    warnings: Array.isArray(s.warnings) ? s.warnings.filter(function(w) { return typeof w === "string" }) : []
  }
}

// `understudy diff --json`
function parseDiff(text) {
  var d = parseJson(text)
  if (!isObject(d) || !Array.isArray(d.items)) return null
  var items = []
  for (var i = 0; i < d.items.length; i++) {
    var it = d.items[i]
    if (!isObject(it) || typeof it.key !== "string" || typeof it.kind !== "string") continue
    items.push({
      key: it.key,
      kind: it.kind,
      name: str(it.label) || str(it.name),
      id: str(it.name),
      status: str(it.status),
      note: str(it.note),
      installable: it.installable === true,
      isDefault: it["default"] === true,
      ignored: it.ignored === true,
      hardware: it.hardware === true,
      isPrivate: it["private"] === true
    })
  }
  var list = isObject(d.list) ? d.list : {}
  return {
    items: items,
    errors: Array.isArray(d.errors) ? d.errors.filter(function(e) { return typeof e === "string" }) : [],
    label: str(list.label),
    generatedAt: str(list.generated_at)
  }
}

// What starts ticked: whatever the helper says is the default.
function initialTicks(items) {
  var ticks = {}
  for (var i = 0; i < (items || []).length; i++) ticks[items[i].key] = items[i].isDefault
  return ticks
}

function isTicked(ticks, item) {
  return item.installable && ticks[item.key] === true
}

// Flips one item. Returns the new ticks and what to remember: unticking a
// normal item ignores it from now on, ticking an ignored one stops ignoring
// it. Hardware items start unticked and are not remembered either way.
function toggle(ticks, item) {
  var next = {}
  for (var k in ticks) next[k] = ticks[k]
  if (!item || !item.installable) return { ticks: next, action: "" }
  var on = !(ticks[item.key] === true)
  next[item.key] = on
  var action = ""
  if (!on && !item.hardware && !item.ignored) action = "ignore"
  else if (on && item.ignored) action = "unignore"
  return { ticks: next, action: action }
}

function selectedKeys(items, ticks) {
  var out = []
  for (var i = 0; i < (items || []).length; i++) if (isTicked(ticks, items[i])) out.push(items[i].key)
  return out
}

// Rows for the secondary view: a header per category, then what is missing
// here. Installed items and ignored ones show only with `showAll`, except
// items ignored during this visit (`keep`), which stay where they were.
function buildSecondaryRows(items, ticks, showAll, keep) {
  var out = []
  for (var c = 0; c < CATEGORIES.length; c++) {
    var cat = CATEGORIES[c]
    var list = []
    for (var i = 0; i < (items || []).length; i++) {
      var it = items[i]
      if (it.kind !== cat.kind) continue
      if (!showAll && it.status === "installed") continue
      if (!showAll && it.ignored && !(keep && keep[it.key])) continue
      list.push(it)
    }
    if (list.length === 0) continue
    var missing = list.filter(function(x) { return x.installable }).length
    out.push({ rowType: "header", key: "", name: cat.title + " · " + missing + " to install" })
    for (var j = 0; j < list.length; j++) {
      var item = list[j]
      out.push({
        rowType: "item",
        key: item.key,
        kind: item.kind,
        name: item.name,
        note: noteFor(item),
        icon: cat.icon,
        checkable: item.installable,
        checked: isTicked(ticks, item),
        status: item.status
      })
    }
  }
  return out
}

function noteFor(item) {
  var parts = []
  if (item.status === "installed") parts.push("installed here")
  if (item.ignored) parts.push("ignored")
  if (item.note) parts.push(item.note)
  return parts.join(" · ")
}

// Rows for the main view: what the scan found, grouped.
function buildMainRows(scan) {
  var out = []
  if (!scan) return out
  for (var c = 0; c < CATEGORIES.length; c++) {
    var cat = CATEGORIES[c]
    var list = scan.rows.filter(function(r) { return r.kind === cat.kind })
    if (list.length === 0) continue
    out.push({ rowType: "header", key: "", name: cat.title + " · " + list.length })
    for (var j = 0; j < list.length; j++)
      out.push({ rowType: "item", key: cat.kind + ":" + list[j].name, kind: cat.kind, name: list[j].name,
                 note: list[j].note, icon: cat.icon, checkable: false, checked: false, status: "" })
  }
  return out
}

function scanSummary(scan) {
  if (!scan) return ""
  var parts = []
  for (var c = 0; c < CATEGORIES.length; c++) {
    var n = scan.counts[CATEGORIES[c].kind] || 0
    if (n > 0) parts.push(n + " " + CATEGORIES[c].title.toLowerCase())
  }
  return parts.length ? parts.join(" · ") : "nothing added since the first install"
}

function diffSummary(items, ticks) {
  var missing = 0, installed = 0, manual = 0
  for (var i = 0; i < (items || []).length; i++) {
    if (items[i].installable) missing++
    else if (items[i].status === "installed") installed++
    else manual++
  }
  var picked = selectedKeys(items, ticks).length
  return picked + " ticked · " + missing + " missing · " + installed + " here" + (manual ? " · " + manual + " manual" : "")
}

function indexOfKey(rows, key) {
  for (var i = 0; i < rows.length; i++) if (rows[i].rowType === "item" && rows[i].key === key) return i
  return -1
}

function firstItemIndex(rows, from, step) {
  if (rows.length === 0) return -1
  var i = from
  for (var n = 0; n < rows.length; n++) {
    i = (i + rows.length) % rows.length
    if (rows[i].rowType === "item") return i
    i += step
  }
  return -1
}

function nextItemIndex(rows, current, step) {
  if (rows.length === 0) return -1
  var i = current
  for (var n = 0; n < rows.length; n++) {
    i = (i + step + rows.length) % rows.length
    if (rows[i].rowType === "item") return i
  }
  return current
}

function installConfirm(count) {
  return "Install " + count + " item" + (count === 1 ? "" : "s") + "? A terminal opens, prints every command, and asks "
    + "again before anything runs. pacman and yay ask for your password there. Nothing is removed."
}

function lastLine(text) {
  var parts = String(text || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
  return parts.length ? parts[parts.length - 1].replace(/^understudy: /, "") : ""
}
