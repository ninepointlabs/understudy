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

// What items are for; the helper gives every item one of these. The order
// is the order sections are shown in.
var GROUPS = [
  { name: "Gaming", icon: "󰊴" },
  { name: "Dev", icon: "󰅩" },
  { name: "CLI/TUI", icon: "󰆍" },
  { name: "Office", icon: "󰈙" },
  { name: "Media", icon: "󰝚" },
  { name: "Internet/Communication", icon: "󰖟" },
  { name: "System/Hardware", icon: "󰘚" },
  { name: "Themes/Look", icon: "󰏘" },
  { name: "Other", icon: "󰇘" }
]
var REMOVED_KEY = "removed"

function isGroup(name) {
  for (var i = 0; i < GROUPS.length; i++) if (GROUPS[i].name === name) return true
  return false
}

function groupIcon(name) {
  for (var i = 0; i < GROUPS.length; i++) if (GROUPS[i].name === name) return GROUPS[i].icon
  return "•"
}

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
    rows.push({ kind: r.kind, name: r.name, note: str(r.note), category: isGroup(r.category) ? r.category : "Other" })
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
      isPrivate: it["private"] === true,
      category: isGroup(it.category) ? it.category : "Other",
      skipped: it.skipped === true
    })
  }
  var removed = []
  var rawRemoved = Array.isArray(d.removed) ? d.removed : []
  for (var r = 0; r < rawRemoved.length; r++) {
    var x = rawRemoved[r]
    if (!isObject(x) || typeof x.key !== "string" || typeof x.command !== "string") continue
    removed.push({ key: x.key, kind: str(x.kind), name: str(x.name) || x.key, command: x.command,
                   category: isGroup(x.category) ? x.category : "Other" })
  }
  var list = isObject(d.list) ? d.list : {}
  return {
    items: items,
    removed: removed,
    skipCategories: Array.isArray(d.skip_categories) ? d.skip_categories.filter(isGroup) : [],
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
  if (!on && !item.hardware && !item.skipped && !item.ignored) action = "ignore"
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
  var skipped = (items || []).filter(function(x) { return x.skipped && x.installable }).length
  return picked + " ticked · " + missing + " missing · " + installed + " here" + (manual ? " · " + manual + " manual" : "")
    + (skipped ? " · " + skipped + " skipped" : "")
}

// Plain headers (the by-type view) are labels; sections, items, reminders
// and category rows can all take the cursor.
function selectable(row) {
  return !!row && row.rowType !== "header"
}

function indexOfKey(rows, key) {
  if (!key) return -1
  for (var i = 0; i < rows.length; i++) if (selectable(rows[i]) && rows[i].key === key) return i
  return -1
}

function firstItemIndex(rows, from, step) {
  if (rows.length === 0) return -1
  var i = from
  for (var n = 0; n < rows.length; n++) {
    i = (i + rows.length) % rows.length
    if (selectable(rows[i])) return i
    i += step
  }
  return -1
}

function nextItemIndex(rows, current, step) {
  if (rows.length === 0) return -1
  var i = current
  for (var n = 0; n < rows.length; n++) {
    i = (i + step + rows.length) % rows.length
    if (selectable(rows[i])) return i
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

// ------------------------------------------------------------ categories

// Sections for skipped categories start folded, so the second laptop's list
// opens without them; what is in them still starts unticked when unfolded.
function initialCollapsed(skipCategories) {
  var out = {}
  for (var i = 0; i < (skipCategories || []).length; i++) out[skipCategories[i]] = true
  return out
}

function toggleCollapsed(collapsed, name) {
  var next = {}
  for (var k in collapsed) next[k] = collapsed[k]
  next[name] = !(collapsed && collapsed[name] === true)
  return next
}

function plural(n, word) {
  return n + " " + word + (n === 1 ? "" : "s")
}

function sectionRow(key, name, icon, note, collapsed, skipped) {
  return { rowType: "section", key: key, kind: "", name: name, note: note, icon: icon, checkable: false,
           checked: false, status: "", collapsed: collapsed === true, skipped: skipped === true }
}

// Rows for the second laptop, by category: a section per category (with how
// many there are to install and how many are ticked), folded or not, then
// "Removed on main" last. `opts`: showAll, keep (items ignored this visit),
// collapsed (name -> true), filter (one category, or ""), skip (names),
// removed (from parseDiff).
function buildCategoryRows(items, ticks, opts) {
  opts = opts || {}
  var collapsed = opts.collapsed || {}
  var skip = opts.skip || []
  var out = []
  for (var g = 0; g < GROUPS.length; g++) {
    var group = GROUPS[g]
    if (opts.filter && opts.filter !== group.name) continue
    var list = []
    for (var i = 0; i < (items || []).length; i++) {
      var it = items[i]
      if (it.category !== group.name) continue
      if (!opts.showAll && it.status === "installed") continue
      if (!opts.showAll && it.ignored && !(opts.keep && opts.keep[it.key])) continue
      list.push(it)
    }
    if (list.length === 0) continue
    var missing = 0, ticked = 0
    for (var m = 0; m < list.length; m++) {
      if (list[m].installable) missing++
      if (isTicked(ticks, list[m])) ticked++
    }
    var skipped = skip.indexOf(group.name) !== -1
    var note = missing + " to install · " + ticked + " ticked" + (skipped ? " · skipped on this laptop" : "")
    var folded = collapsed[group.name] === true
    out.push(sectionRow("cat:" + group.name, group.name + " · " + list.length, group.icon, note, folded, skipped))
    if (folded) continue
    for (var j = 0; j < list.length; j++) {
      var item = list[j]
      out.push({
        rowType: "item",
        key: item.key,
        kind: item.kind,
        name: item.name,
        note: noteFor(item),
        icon: iconFor(item.kind),
        checkable: item.installable,
        checked: isTicked(ticks, item),
        status: item.status,
        collapsed: false,
        skipped: item.skipped === true
      })
    }
  }
  var removed = (opts.removed || []).filter(function(r) { return !opts.filter || r.category === opts.filter })
  if (removed.length > 0) {
    var foldedRemoved = collapsed[REMOVED_KEY] === true
    out.push(sectionRow(REMOVED_KEY, "Removed on main · " + removed.length, "󰋚",
                        "still on this laptop · a reminder only, nothing is removed", foldedRemoved, false))
    if (!foldedRemoved) {
      for (var r = 0; r < removed.length; r++) {
        out.push({ rowType: "removed", key: removed[r].key, kind: removed[r].kind, name: removed[r].name,
                   note: removed[r].category + " · to remove it: " + removed[r].command, icon: iconFor(removed[r].kind),
                   checkable: false, checked: false, status: "", collapsed: false, skipped: false,
                   command: removed[r].command })
      }
    }
  }
  return out
}

// The main laptop's scan, by category.
function buildMainCategoryRows(scan, collapsed, filter) {
  var out = []
  if (!scan) return out
  collapsed = collapsed || {}
  for (var g = 0; g < GROUPS.length; g++) {
    var group = GROUPS[g]
    if (filter && filter !== group.name) continue
    var list = scan.rows.filter(function(r) { return r.category === group.name })
    if (list.length === 0) continue
    var folded = collapsed[group.name] === true
    out.push(sectionRow("cat:" + group.name, group.name + " · " + list.length, group.icon, "", folded, false))
    if (folded) continue
    for (var j = 0; j < list.length; j++)
      out.push({ rowType: "item", key: list[j].kind + ":" + list[j].name, kind: list[j].kind, name: list[j].name,
                 note: list[j].note, icon: iconFor(list[j].kind), checkable: false, checked: false, status: "",
                 collapsed: false, skipped: false })
  }
  return out
}

// The category panel: one row per category with how many items it has, a
// "skip on this laptop" checkbox (the second laptop only), and a first row
// that shows everything again. Enter on a row shows only that category.
function buildCategoryPanelRows(entries, skip, filter, withSkip) {
  var out = [{ rowType: "cat", key: "panel:", name: "All categories", note: filter ? "" : "showing", icon: "󰒺",
               checkable: false, checked: false, status: "", collapsed: false, skipped: false }]
  for (var g = 0; g < GROUPS.length; g++) {
    var group = GROUPS[g]
    var n = 0, missing = 0
    for (var i = 0; i < (entries || []).length; i++) {
      if (entries[i].category !== group.name) continue
      n++
      if (entries[i].installable) missing++
    }
    var skipped = (skip || []).indexOf(group.name) !== -1
    var parts = [plural(n, "item")]
    if (withSkip) parts.push(missing + " to install")
    if (filter === group.name) parts.unshift("showing only this")
    if (withSkip && skipped) parts.push("skipped on this laptop")
    out.push({ rowType: "cat", key: "panel:" + group.name, name: group.name, note: parts.join(" · "), icon: group.icon,
               checkable: withSkip === true, checked: skipped, status: "", collapsed: false, skipped: skipped })
  }
  return out
}

// Flips one category's skip. Returns the new list (in GROUPS order) and the
// helper command that remembers it.
function toggleSkip(skip, name) {
  if (!isGroup(name)) return { skip: (skip || []).slice(), action: "" }
  var on = (skip || []).indexOf(name) === -1
  var next = GROUPS.map(function(g) { return g.name }).filter(function(n) {
    return n === name ? on : (skip || []).indexOf(n) !== -1
  })
  return { skip: next, action: on ? "skip" : "unskip" }
}

// The section a row is in: its own index for a section, else the nearest
// section above it, else -1.
function sectionIndexOf(rows, index) {
  for (var i = Math.min(index, rows.length - 1); i >= 0; i--) if (rows[i].rowType === "section") return i
  return -1
}

function sectionName(row) {
  if (!row || row.rowType !== "section") return ""
  return row.key === REMOVED_KEY ? REMOVED_KEY : row.key.replace(/^cat:/, "")
}
