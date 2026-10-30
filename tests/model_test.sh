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

console.log("\n" + pass + " passed, " + fail + " failed")
process.exit(fail === 0 ? 0 : 1)
EOF
