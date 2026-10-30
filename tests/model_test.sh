#!/bin/bash

# tests/model_test.sh — UnderstudyModel.js, loaded in node.
#
#   tests/model_test.sh
#
# Reading the helper's output, which items start ticked, what ticking and
# unticking remember, grouping, and navigation. Reads the repo only.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v node >/dev/null; then
  echo "node is not on PATH; these tests load UnderstudyModel.js with it" >&2
  exit 1
fi

REPO="$REPO" node - <<'EOF'
const fs = require("fs")
const path = require("path")
const vm = require("vm")

let pass = 0, fail = 0
function check(desc, cond, detail) {
  if (cond) { console.log("  ok    " + desc); pass++ }
  else { console.log("  FAIL  " + desc + (detail !== undefined ? " (" + JSON.stringify(detail) + ")" : "")); fail++ }
}
function note(text) { console.log("\n" + text) }

// QML's `.pragma library` line is not JavaScript; everything after it is.
const Model = {}
vm.runInNewContext(fs.readFileSync(path.join(process.env.REPO, "UnderstudyModel.js"), "utf8").replace(/^\.pragma library/m, ""), Model)

const diffText = JSON.stringify({
  list: { path: "/x/understudy.toml", label: "tuf", generated_at: "2026-10-30T12:00:00Z" },
  errors: ["Themes #3: bad source; skipped", 7],
  items: [
    { key: "package:rclone", kind: "package", name: "rclone", status: "missing", note: "[extra]", installable: true, default: true, ignored: false, hardware: false, private: false },
    { key: "package:btop", kind: "package", name: "btop", status: "installed", note: "", installable: false, default: false, ignored: false, hardware: false, private: false },
    { key: "package:nvidia-dkms", kind: "package", name: "nvidia-dkms", status: "missing", note: "hardware-specific · [extra]", installable: true, default: false, ignored: false, hardware: true, private: false },
    { key: "package:restic", kind: "package", name: "restic", status: "missing", note: "[extra]", installable: true, default: false, ignored: true, hardware: false, private: false },
    { key: "installer:omarchy-install-gaming-steam", kind: "installer", name: "omarchy-install-gaming-steam", status: "missing", note: "sets it up", installable: true, default: true, ignored: false, hardware: false, private: false },
    { key: "theme:handmade", kind: "theme", name: "handmade", status: "manual", note: "manual: no source URL", installable: false, default: false, ignored: false, hardware: false, private: false },
    { key: "plugin:acme.weather", kind: "plugin", name: "acme.weather", label: "Weather", status: "missing", note: "github.com/acme/omarchy-weather.git", installable: true, default: true, ignored: false, hardware: false, private: false },
    { kind: "package" },
    "not an object"
  ]
})

note("reading the helper")
const d = Model.parseDiff(diffText)
check("parses the diff", d && d.items.length === 7, d && d.items.length)
check("drops malformed items", d.items.every((i) => typeof i.key === "string"))
check("keeps only string errors", d.errors.length === 1)
check("a plugin shows its name, not its id", d.items.find((i) => i.key === "plugin:acme.weather").name === "Weather")
check("label and date", d.label === "tuf" && d.generatedAt === "2026-10-30T12:00:00Z")
check("unreadable output is null", Model.parseDiff("nope") === null && Model.parseDiff('{"items": 1}') === null)
const st = Model.parseStatus('{"role":"boss","folder":"~/Sync/understudy","folderExists":true,"autoExport":true}')
check("status: an unknown role reads as unset", st.role === "" && st.folderExists && st.autoExport)
const sc = Model.parseScan(JSON.stringify({ counts: { package: 2, theme: 1 }, rows: [{ kind: "package", name: "btop", note: "[extra]" }, { kind: "theme" }], warnings: ["w", 3] }))
check("scan rows and warnings", sc.rows.length === 1 && sc.warnings.length === 1)
check("scan summary names the counts", Model.scanSummary(sc) === "2 repo packages · 1 themes", Model.scanSummary(sc))

note("ticks")
let ticks = Model.initialTicks(d.items)
check("defaults start ticked", ticks["package:rclone"] === true && ticks["installer:omarchy-install-gaming-steam"] === true)
check("hardware starts unticked", ticks["package:nvidia-dkms"] === false)
check("ignored starts unticked", ticks["package:restic"] === false)
check("selected keys are the ticked installable ones",
  JSON.stringify(Model.selectedKeys(d.items, ticks)) === JSON.stringify(["package:rclone", "installer:omarchy-install-gaming-steam", "plugin:acme.weather"]))

const rclone = d.items.find((i) => i.key === "package:rclone")
let r = Model.toggle(ticks, rclone)
check("unticking a normal item ignores it from now on", r.ticks["package:rclone"] === false && r.action === "ignore")
check("toggle does not change the ticks it was given", ticks["package:rclone"] === true)
const restic = d.items.find((i) => i.key === "package:restic")
r = Model.toggle(ticks, restic)
check("ticking an ignored item stops ignoring it", r.ticks["package:restic"] === true && r.action === "unignore")
const hw = d.items.find((i) => i.key === "package:nvidia-dkms")
r = Model.toggle(ticks, hw)
check("ticking hardware is for this visit only", r.ticks["package:nvidia-dkms"] === true && r.action === "")
r = Model.toggle(r.ticks, hw)
check("unticking hardware is not remembered either", r.ticks["package:nvidia-dkms"] === false && r.action === "")
const manual = d.items.find((i) => i.key === "theme:handmade")
r = Model.toggle(ticks, manual)
check("a manual item cannot be ticked", r.ticks["theme:handmade"] === false && r.action === "")
check("an installed item never counts as ticked", !Model.isTicked({ "package:btop": true }, d.items.find((i) => i.key === "package:btop")))

note("rows")
const rows = Model.buildSecondaryRows(d.items, ticks, false, {})
const names = rows.map((x) => x.rowType === "header" ? "#" + x.name : x.name)
check("grouped in install order; installed and ignored hidden",
  JSON.stringify(names) === JSON.stringify(["#Omarchy installers · 1 to install", "omarchy-install-gaming-steam",
    "#Repo packages · 2 to install", "rclone", "nvidia-dkms", "#Themes · 0 to install", "handmade",
    "#Plugins · 1 to install", "Weather"]), names)
const all = Model.buildSecondaryRows(d.items, ticks, true, {})
check("show all brings back installed and ignored", all.some((x) => x.key === "package:btop") && all.some((x) => x.key === "package:restic"))
check("installed rows say so", all.find((x) => x.key === "package:btop").note.indexOf("installed here") === 0)
const kept = Model.buildSecondaryRows(d.items, ticks, false, { "package:restic": true })
check("an item ignored this visit stays in view", kept.some((x) => x.key === "package:restic"))
check("rows carry their checkbox state", rows.find((x) => x.key === "package:rclone").checked && !rows.find((x) => x.key === "theme:handmade").checkable)
check("summary counts ticked, missing, here and manual",
  Model.diffSummary(d.items, ticks) === "3 ticked · 5 missing · 1 here · 1 manual", Model.diffSummary(d.items, ticks))
const mainRows = Model.buildMainRows(sc)
check("main rows group the scan", mainRows.length === 2 && mainRows[0].rowType === "header" && mainRows[0].name === "Repo packages · 1")

note("navigation and text")
check("first item skips the header", Model.firstItemIndex(rows, 0, 1) === 1)
check("next skips headers", Model.nextItemIndex(rows, 1, 1) === 3)
check("wraps around", Model.nextItemIndex(rows, rows.length - 1, 1) === 1)
check("finds a key", Model.indexOfKey(rows, "package:rclone") === 3)
check("the confirmation says a terminal asks again", /asks\s+again/.test(Model.installConfirm(3)) && /3 items/.test(Model.installConfirm(3)))
check("one item is singular", /Install 1 item\?/.test(Model.installConfirm(1)))
check("last line drops the helper's prefix", Model.lastLine("a\nunderstudy: No list yet.\n\n") === "No list yet.")

note("categories")
const catText = JSON.stringify({
  list: { label: "tuf", generated_at: "2026-10-30T12:00:00Z" },
  skip_categories: ["Gaming", "Snacks"],
  items: [
    { key: "installer:omarchy-install-gaming-steam", kind: "installer", name: "omarchy-install-gaming-steam", status: "missing", installable: true, default: false, category: "Gaming", skipped: true },
    { key: "aur:protonup-qt-bin", kind: "aur", name: "protonup-qt-bin", status: "missing", installable: true, default: false, category: "Gaming", skipped: true },
    { key: "package:rclone", kind: "package", name: "rclone", status: "missing", installable: true, default: true, category: "Internet/Communication", skipped: false },
    { key: "package:btop", kind: "package", name: "btop", status: "installed", installable: false, default: false, category: "CLI/TUI", skipped: false },
    { key: "package:fd", kind: "package", name: "fd", status: "missing", installable: true, default: true, category: "CLI/TUI", skipped: false },
    { key: "theme:sunset", kind: "theme", name: "sunset", status: "missing", installable: true, default: true, category: "Snacks", skipped: false }
  ],
  removed: [
    { key: "package:restic", kind: "package", name: "restic", category: "System/Hardware", command: "omarchy pkg drop restic" },
    { key: "theme:grok", kind: "theme", name: "grok", category: "Themes/Look", command: "omarchy theme remove grok" },
    { key: 5, command: "x" }, { key: "package:x" }
  ]
})
const c = Model.parseDiff(catText)
check("items carry their category and skipped flag", c.items[0].category === "Gaming" && c.items[0].skipped === true)
check("an unknown category reads as Other", c.items.find((i) => i.key === "theme:sunset").category === "Other")
check("only known skip categories are kept", JSON.stringify(c.skipCategories) === '["Gaming"]', c.skipCategories)
check("removed items need a key and a command", c.removed.length === 2 && c.removed[0].command === "omarchy pkg drop restic")
check("a v0.1 diff (no categories) still reads, as Other", Model.parseDiff(diffText).items.every((i) => i.category === "Other" && !i.skipped))
const scanCat = Model.parseScan(JSON.stringify({ rows: [{ kind: "package", name: "steam", category: "Gaming" }, { kind: "theme", name: "x", category: 3 }] }))
check("scan rows carry their category", scanCat.rows[0].category === "Gaming" && scanCat.rows[1].category === "Other")

let ct = Model.initialTicks(c.items)
let collapsed = Model.initialCollapsed(c.skipCategories)
check("skipped categories start folded", collapsed.Gaming === true && collapsed["CLI/TUI"] !== true)
check("and their items start unticked", ct["installer:omarchy-install-gaming-steam"] === false && ct["package:rclone"] === true)
let crow = Model.buildCategoryRows(c.items, ct, { collapsed: collapsed, skip: c.skipCategories, removed: c.removed })
const label = (x) => (x.rowType === "section" ? "#" : x.rowType === "removed" ? "-" : "") + x.name
check("sections in category order; a folded one shows only its header; Removed on main last",
  JSON.stringify(crow.map(label)) === JSON.stringify(["#Gaming · 2", "#CLI/TUI · 1", "fd", "#Internet/Communication · 1", "rclone",
    "#Other · 1", "sunset", "#Removed on main · 2", "-restic", "-grok"]), crow.map(label))
const gamingRow = crow[0]
check("a skipped section says so, with its counts", gamingRow.note === "2 to install · 0 ticked · skipped on this laptop" && gamingRow.collapsed && gamingRow.skipped, gamingRow.note)
check("a section counts what is ticked", crow.find((x) => x.key === "cat:CLI/TUI").note === "1 to install · 1 ticked")
check("a reminder row carries the command to copy", crow.find((x) => x.key === "theme:grok").command === "omarchy theme remove grok")
check("an item row shows its kind's icon", crow.find((x) => x.key === "package:fd").icon === Model.iconFor("package"))
collapsed = Model.toggleCollapsed(collapsed, "Gaming")
check("unfolding a section does not change the old map", Model.initialCollapsed(["Gaming"]).Gaming === true && collapsed.Gaming === false)
crow = Model.buildCategoryRows(c.items, ct, { collapsed: collapsed, skip: c.skipCategories, removed: c.removed })
check("unfolded, a skipped category's items show, unticked", crow[1].key === "installer:omarchy-install-gaming-steam" && crow[1].checkable && !crow[1].checked)
const steam = c.items[0]
r = Model.toggle(ct, steam)
check("ticking a skipped item by hand works and is not remembered", r.ticks[steam.key] === true && r.action === "")
r = Model.toggle(r.ticks, steam)
check("unticking it again does not ignore it either", r.ticks[steam.key] === false && r.action === "")
ct = Model.toggle(ct, steam).ticks
check("a hand-ticked skipped item is selected", Model.selectedKeys(c.items, ct).indexOf(steam.key) !== -1)
check("the summary counts skipped items", /· 2 skipped$/.test(Model.diffSummary(c.items, ct)), Model.diffSummary(c.items, ct))
const only = Model.buildCategoryRows(c.items, ct, { collapsed: {}, filter: "CLI/TUI", removed: c.removed })
check("a filter shows one category and its reminders only", JSON.stringify(only.map(label)) === JSON.stringify(["#CLI/TUI · 1", "fd"]), only.map(label))
const sys = Model.buildCategoryRows(c.items, ct, { collapsed: { removed: true }, filter: "System/Hardware", removed: c.removed })
check("a folded Removed on main shows its header only", JSON.stringify(sys.map(label)) === JSON.stringify(["#Removed on main · 1"]), sys.map(label))
check("showAll brings back installed items in their section", Model.buildCategoryRows(c.items, ct, { showAll: true }).some((x) => x.key === "package:btop"))

note("categories: navigation, panel, skip")
check("sections take the cursor; plain headers still do not", Model.firstItemIndex(crow, 0, 1) === 0 && Model.firstItemIndex(rows, 0, 1) === 1)
check("next goes through sections", Model.nextItemIndex(crow, 2, 1) === 3 && crow[3].rowType === "section")
check("a row's section is found", Model.sectionIndexOf(crow, 4) === 3 && Model.sectionIndexOf(crow, 3) === 3)
check("section names come back for folding", Model.sectionName(crow[3]) === "CLI/TUI" && Model.sectionName(crow[crow.length - 3]) === "removed")
check("a section is found by key", Model.indexOfKey(crow, "cat:CLI/TUI") === 3)
const panel = Model.buildCategoryPanelRows(c.items, c.skipCategories, "", true)
check("the panel has All, then every category", panel.length === Model.GROUPS.length + 1 && panel[0].key === "panel:" && panel[1].name === "Gaming")
check("a category row counts its items and has a skip checkbox", panel[1].note === "2 items · 2 to install · skipped on this laptop" && panel[1].checkable && panel[1].checked, panel[1].note)
const mainPanel = Model.buildCategoryPanelRows(scanCat.rows, [], "Gaming", false)
check("on main the panel has no checkboxes, and marks the filter", !mainPanel[1].checkable && mainPanel[1].note === "showing only this · 1 item", mainPanel[1].note)
let sk = Model.toggleSkip(["Media"], "Gaming")
check("skipping adds, in category order", JSON.stringify(sk.skip) === '["Gaming","Media"]' && sk.action === "skip")
sk = Model.toggleSkip(sk.skip, "Media")
check("unskipping removes", JSON.stringify(sk.skip) === '["Gaming"]' && sk.action === "unskip")
check("an unknown category does nothing", Model.toggleSkip(["Gaming"], "Snacks").action === "")
const mcat = Model.buildMainCategoryRows(scanCat, { Other: true }, "")
check("main rows by category, folding too", JSON.stringify(mcat.map(label)) === JSON.stringify(["#Gaming · 1", "steam", "#Other · 1"]), mcat.map(label))

console.log("\n" + pass + " passed, " + fail + " failed")
process.exit(fail === 0 ? 0 : 1)
EOF
