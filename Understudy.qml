pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "UnderstudyModel.js" as Model

// Understudy — make a second Omarchy laptop match the main one.
//
// On the main laptop the overlay shows what was added after the first
// Omarchy install and exports that list to a shared folder. On the second
// laptop it reads the list, shows what is missing there with a checkbox each,
// shows the exact commands, and opens a terminal to install the ticked ones.
//
// All the work is done by `bin/understudy`; the overlay only ever runs it
// with an argument array. Item keys, folder and paths typed here are passed
// as single arguments and checked by the helper, never joined into a command.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string selfId: manifest && manifest.id ? String(manifest.id) : "ninepointlabs.understudy"
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : Quickshell.env("HOME") + "/.config/omarchy/plugins/ninepointlabs.understudy"
  readonly property string helperPath: sourceDir + "/bin/understudy"
  readonly property var helper: ["/usr/bin/python3", "-I", "-S", root.helperPath]

  property bool opened: false
  property var status: null
  property string role: status ? status.role : ""
  property var scan: null
  property var diff: null
  property var ticks: ({})
  // Items unticked during this visit stay in view until the next open.
  property var keepShown: ({})
  property bool showAll: false
  // "category" (sections by what items are for, the default) or "kind"
  // (by how they install, as in v0.1). G switches.
  property string groupBy: "category"
  // Category name (or "removed") -> folded.
  property var collapsed: ({})
  property string categoryFilter: ""
  property bool panelOpen: false
  property var rows: []
  property int selectedIndex: -1
  property var current: null
  property bool busy: false
  property string busyText: ""
  property string statusText: ""
  property bool statusUrgent: false
  property bool planOpen: false
  property string planText: ""
  property bool confirmOpen: false
  property string promptKind: ""
  property string promptText: ""
  property bool autoExported: false

  // Menu surface tokens so themes that style the menu style this too.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property color dim: Util.alpha(foreground, 0.55)
  readonly property color faint: Util.alpha(foreground, 0.22)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.heading + Style.spacing.controlPaddingY * 2)
  property int rowHeight: Math.max(Style.space(48), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX + Style.spacing.xxs * 2)
  property int groupHeight: Style.space(28)
  property int cardWidth: Math.min(Style.space(900), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(680), panel.height - Style.gapsOut * 2)

  // ------------------------------------------------------------ lifecycle

  function isOpen() {
    return root.opened ? "true" : "false"
  }

  function open(payloadJson) {
    root.opened = true
    root.planOpen = false
    root.confirmOpen = false
    root.promptKind = ""
    root.panelOpen = false
    root.keepShown = ({})
    root.autoExported = false
    root.say("", false)
    root.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.confirmOpen = false
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.selfId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  onShellChanged: {
    if (!root.shell) return
    Qt.callLater(function() {
      if (root.opened || !root.shell) return
      if (typeof root.shell.isPluginOpen === "function" && root.shell.isPluginOpen(root.selfId) === true)
        root.open("{}")
    })
  }

  // ---------------------------------------------------------------- model

  function say(text, isUrgent) {
    root.statusText = text || ""
    root.statusUrgent = isUrgent === true
  }

  function reload() {
    statusProcess.running = true
  }

  function applyStatus(text) {
    var s = Model.parseStatus(text)
    if (!s) { root.say("Could not read Understudy's settings (understudy status).", true); return }
    root.status = s
    if (s.role === "main") {
      if (s.autoExport && !root.autoExported) {
        root.autoExported = true
        root.run(["export", "--json"], "Exporting…", function(out) { root.afterExport(out) })
      }
      root.loadScan()
    } else if (s.role === "secondary") {
      root.loadDiff()
    } else {
      root.rebuild()
    }
  }

  function loadScan() {
    if (scanProcess.running) return
    root.busyText = "Scanning…"
    scanProcess.running = true
  }

  function applyScan(text) {
    var s = Model.parseScan(text)
    if (!s) return
    root.scan = s
    if (s.warnings.length > 0) root.say(s.warnings[0], true)
    root.rebuild()
  }

  function loadDiff() {
    if (diffProcess.running) return
    root.busyText = "Reading the list…"
    diffProcess.running = true
  }

  function applyDiff(text) {
    var d = Model.parseDiff(text)
    if (!d) return
    var first = !root.diff
    root.diff = d
    if (first) root.collapsed = Model.initialCollapsed(d.skipCategories)
    if (first || Object.keys(root.ticks).length === 0) root.ticks = Model.initialTicks(d.items)
    else {
      // Keep this visit's choices; new items start at their default.
      var t = Model.initialTicks(d.items)
      for (var k in t) if (root.ticks[k] !== undefined) t[k] = root.ticks[k]
      root.ticks = t
    }
    if (d.errors.length > 0) root.say(d.errors.length + " entr" + (d.errors.length === 1 ? "y" : "ies") + " in the list were not usable: " + d.errors[0], true)
    root.rebuild()
  }

  function rebuild() {
    var keep = root.current ? root.current.key : ""
    var byCategory = root.groupBy === "category"
    if (root.panelOpen) {
      var entries = root.role === "main" ? (root.scan ? root.scan.rows : []) : (root.diff ? root.diff.items : [])
      root.rows = Model.buildCategoryPanelRows(entries, root.diff ? root.diff.skipCategories : [], root.categoryFilter,
                                               root.role === "secondary")
    } else if (root.role === "main") {
      root.rows = byCategory ? Model.buildMainCategoryRows(root.scan, root.collapsed, root.categoryFilter) : Model.buildMainRows(root.scan)
    } else if (root.role === "secondary" && root.diff) {
      root.rows = byCategory
        ? Model.buildCategoryRows(root.diff.items, root.ticks, { showAll: root.showAll, keep: root.keepShown, collapsed: root.collapsed,
                                  filter: root.categoryFilter, skip: root.diff.skipCategories, removed: root.diff.removed })
        : Model.buildSecondaryRows(root.diff.items, root.ticks, root.showAll, root.keepShown)
    } else {
      root.rows = []
    }

    displayModel.clear()
    for (var i = 0; i < root.rows.length; i++) {
      var row = root.rows[i]
      displayModel.append({
        rowType: row.rowType,
        rowKey: row.key,
        name: row.name,
        note: row.note || "",
        icon: row.icon || "",
        checkable: row.checkable === true,
        checked: row.checked === true,
        installed: row.status === "installed",
        collapsed: row.collapsed === true
      })
    }
    var idx = Model.indexOfKey(root.rows, keep)
    if (idx === -1) idx = Model.firstItemIndex(root.rows, Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1)), 1)
    root.selectedIndex = idx
    root.syncCurrent()
    Qt.callLater(function() {
      if (root.selectedIndex >= 0 && root.selectedIndex < displayModel.count)
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function syncCurrent() {
    var row = root.selectedIndex >= 0 && root.selectedIndex < root.rows.length ? root.rows[root.selectedIndex] : null
    root.current = Model.selectable(row) ? row : null
  }

  function select(delta) {
    if (root.rows.length === 0) return
    root.selectedIndex = root.selectedIndex < 0
      ? Model.firstItemIndex(root.rows, delta < 0 ? root.rows.length - 1 : 0, delta < 0 ? -1 : 1)
      : Model.nextItemIndex(root.rows, root.selectedIndex, delta)
    root.syncCurrent()
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectEdge(end) {
    if (root.rows.length === 0) return
    root.selectedIndex = end ? Model.firstItemIndex(root.rows, root.rows.length - 1, -1) : Model.firstItemIndex(root.rows, 0, 1)
    root.syncCurrent()
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectIndex(index) {
    if (index < 0 || index >= root.rows.length || !Model.selectable(root.rows[index])) return
    root.selectedIndex = index
    root.syncCurrent()
  }

  function itemFor(key) {
    if (!root.diff) return null
    for (var i = 0; i < root.diff.items.length; i++) if (root.diff.items[i].key === key) return root.diff.items[i]
    return null
  }

  // ------------------------------------------------------------- actions

  // Runs the helper with `args` (an array) and hands stdout to `done` when it
  // exits 0; otherwise shows the helper's last line of stderr.
  function run(args, label, done) {
    if (actionProcess.running) { root.say("Still busy with the last step.", false); return }
    actionProcess.done = done || null
    actionProcess.command = root.helper.concat(args)
    root.busy = true
    root.busyText = label || ""
    actionProcess.running = true
  }

  function setRole(role) {
    root.run(["role", role], "", function() {
      root.scan = null
      root.diff = null
      root.ticks = ({})
      root.planOpen = false
      root.say(role === "main" ? "This laptop is the main one." : "This laptop is the second one.", false)
      root.reload()
    })
  }

  function switchRole() {
    root.setRole(root.role === "main" ? "secondary" : "main")
  }

  function exportList(path) {
    var args = path ? ["export", path, "--json"] : ["export", "--json"]
    root.run(args, "Exporting…", function(out) { root.afterExport(out) })
  }

  function afterExport(out) {
    var r = Model.parseJson(out)
    var n = 0
    if (r && r.counts) for (var k in r.counts) n += r.counts[k]
    root.say("Exported " + n + " items to " + (r && r.path ? r.path : "the list") + ".", false)
    root.reload()
  }

  function toggleCurrent() {
    if (!root.current) return
    if (root.current.rowType === "section") { root.fold(!root.current.collapsed); return }
    if (root.current.rowType === "cat") { root.toggleSkipCurrent(); return }
    if (root.current.rowType === "removed") { root.say("Y copies the command to remove it yourself; X stops reminding you.", false); return }
    if (root.role !== "secondary") return
    var item = root.itemFor(root.current.key)
    if (!item || !item.installable) {
      root.say(item && item.status === "installed" ? "Already installed here." : "This one can't be installed from here: " + (item ? item.note : ""), false)
      return
    }
    var r = Model.toggle(root.ticks, item)
    root.ticks = r.ticks
    if (r.action === "ignore") {
      var keep = root.keepShown; keep[item.key] = true; root.keepShown = keep
      ignoreProcess.command = root.helper.concat(["ignore", item.key])
      ignoreProcess.running = true
      item.ignored = true
    } else if (r.action === "unignore") {
      ignoreProcess.command = root.helper.concat(["unignore", item.key])
      ignoreProcess.running = true
      item.ignored = false
    }
    root.rebuild()
  }

  // Folds (or unfolds) the section the cursor is in, leaving the cursor on
  // its header.
  function fold(shut) {
    if (root.groupBy !== "category" || root.panelOpen || root.planOpen) return
    var at = Model.sectionIndexOf(root.rows, root.selectedIndex)
    if (at < 0) return
    var name = Model.sectionName(root.rows[at])
    if ((root.collapsed[name] === true) === shut) { root.selectIndex(at); return }
    root.collapsed = Model.toggleCollapsed(root.collapsed, name)
    root.current = root.rows[at]
    root.rebuild()
  }

  function togglePanel() {
    root.panelOpen = !root.panelOpen
    root.current = null
    root.selectedIndex = 0
    root.rebuild()
  }

  // Enter in the category panel: show only that category ("All" shows all).
  function pickFilter() {
    if (!root.current || root.current.rowType !== "cat") return
    root.categoryFilter = root.current.key.replace(/^panel:/, "")
    root.panelOpen = false
    root.current = null
    root.selectedIndex = 0
    root.say(root.categoryFilter ? "Showing only " + root.categoryFilter + ". C, then Enter on All, shows everything." : "", false)
    root.rebuild()
  }

  function toggleSkipCurrent() {
    if (root.role !== "secondary" || !root.diff || !root.current || !root.current.checkable) return
    var name = root.current.name
    var r = Model.toggleSkip(root.diff.skipCategories, name)
    if (!r.action) return
    root.run([r.action, name], "", function() {
      // Fold a category as it is skipped, so it leaves the list the way it
      // would on the next open; its items are unticked by the helper.
      if (r.action === "skip" && root.collapsed[name] !== true) root.collapsed = Model.toggleCollapsed(root.collapsed, name)
      // Untick what is now skipped; what is offered again goes back to its
      // default when the list is read again.
      var t = {}
      for (var k in root.ticks) t[k] = root.ticks[k]
      for (var i = 0; i < root.diff.items.length; i++) {
        var it = root.diff.items[i]
        if (it.category !== name) continue
        if (r.action === "skip") t[it.key] = false
        else delete t[it.key]
      }
      root.ticks = t
      root.say(r.action === "skip" ? name + " is skipped on this laptop: folded and never ticked unless you tick an item by hand."
                                   : name + " is offered again.", false)
      root.loadDiff()
    })
  }

  function copyRemoveCommand() {
    if (!root.current || root.current.rowType !== "removed") return
    copyProcess.command = ["wl-copy", "--", root.current.command]
    copyProcess.running = true
    root.say("Copied: " + root.current.command, false)
  }

  function dismissRemoved() {
    if (!root.current || root.current.rowType !== "removed") return
    var key = root.current.key
    root.run(["dismiss", key], "", function() {
      root.say("No longer reminding you about " + key + ". `understudy undismiss " + key + "` brings it back.", false)
      root.loadDiff()
    })
  }

  function showPlan() {
    if (root.role !== "secondary" || !root.diff) return
    var keys = Model.selectedKeys(root.diff.items, root.ticks)
    root.run(["plan", "--json", "--only"].concat(keys), "Working out the commands…", function(out) {
      var r = Model.parseJson(out)
      root.planText = r && typeof r.text === "string" ? r.text : String(out)
      root.planOpen = true
    })
  }

  function requestInstall() {
    if (root.role !== "secondary" || !root.diff) return
    var n = Model.selectedKeys(root.diff.items, root.ticks).length
    if (n === 0) { root.say("Nothing is ticked.", false); return }
    confirmDialog.selectedIndex = 1
    root.confirmOpen = true
  }

  function acceptInstall() {
    root.confirmOpen = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    var keys = Model.selectedKeys(root.diff.items, root.ticks)
    root.run(["terminal", "--only"].concat(keys), "Opening a terminal…", function(out) {
      root.say(Model.lastLine(out) + " Reopen Understudy when it is done to see what is left.", false)
    })
  }

  function cancelConfirm() {
    root.confirmOpen = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openPrompt(kind) {
    root.promptKind = kind
    root.promptText = kind === "folder" && root.status ? root.status.folder : "~/"
  }

  function acceptPrompt() {
    var kind = root.promptKind, text = root.promptText.trim()
    root.promptKind = ""
    if (!text) return
    if (kind === "folder") root.run(["config", "folder", text], "", function() { root.say("Shared folder set.", false); root.reload() })
    else if (kind === "export") root.exportList(text)
    else if (kind === "import") root.run(["import", text], "Importing…", function(out) { root.say(Model.lastLine(out.split("\n")[0]), false); root.reload() })
  }

  function promptTitle() {
    if (root.promptKind === "folder") return "Shared folder"
    if (root.promptKind === "export") return "Export the list to"
    if (root.promptKind === "import") return "Import a list from"
    return ""
  }

  // ------------------------------------------------------------ processes

  ListModel { id: displayModel }

  Process {
    id: statusProcess
    command: root.helper.concat(["status", "--json"])
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.say("understudy status: " + Model.lastLine(statusErr.text), true)
    }
  }

  Process {
    id: scanProcess
    command: root.helper.concat(["scan", "--json", "--offline"])
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyScan(text) }
    stderr: StdioCollector { id: scanErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.busyText = ""
      if (exitCode !== 0) root.say("Scan failed: " + Model.lastLine(scanErr.text), true)
    }
  }

  Process {
    id: diffProcess
    command: root.helper.concat(["diff", "--json"])
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyDiff(text) }
    stderr: StdioCollector { id: diffErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.busyText = ""
      if (exitCode !== 0) {
        root.diff = null
        root.rebuild()
        root.say(Model.lastLine(diffErr.text), true)
      }
    }
  }

  Process {
    id: actionProcess
    property var done: null
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      root.busyText = ""
      var cb = actionProcess.done
      actionProcess.done = null
      if (exitCode === 0) { if (cb) cb(actionOut.text) }
      else root.say(Model.lastLine(actionErr.text) || ("understudy exited " + exitCode), true)
    }
  }

  Process {
    id: copyProcess
    stderr: StdioCollector { id: copyErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.say("Could not copy (is wl-copy installed?) " + Model.lastLine(copyErr.text), true)
    }
  }

  Process {
    id: ignoreProcess
    stderr: StdioCollector { id: ignoreErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.say("Could not remember that: " + Model.lastLine(ignoreErr.text), true)
    }
  }

  // ------------------------------------------------------------------ keys

  function handleKey(event) {
    if (root.confirmOpen) {
      if (confirmDialog.handleKey(event)) event.accepted = true
      return
    }
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var key = event.key

    if (root.promptKind !== "") {
      if (key === Qt.Key_Escape) root.promptKind = ""
      else if (key === Qt.Key_Return || key === Qt.Key_Enter) root.acceptPrompt()
      else if (Util.editsFilter(event, root.promptText)) root.promptText = Util.editedFilter(event, root.promptText)
      else if (!ctrl && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127)
        root.promptText += event.text
      event.accepted = true
      return
    }

    if (root.panelOpen) {
      if (key === Qt.Key_Escape || key === Qt.Key_C) root.togglePanel()
      else if (key === Qt.Key_Down) root.select(1)
      else if (key === Qt.Key_Up) root.select(-1)
      else if (key === Qt.Key_Home) root.selectEdge(false)
      else if (key === Qt.Key_End) root.selectEdge(true)
      else if (key === Qt.Key_Space) root.toggleSkipCurrent()
      else if (key === Qt.Key_Return || key === Qt.Key_Enter) root.pickFilter()
      else return
      event.accepted = true
      return
    }

    if (key === Qt.Key_Escape) {
      if (root.planOpen) root.planOpen = false
      else root.dismiss()
    } else if (root.planOpen && (key === Qt.Key_Down || key === Qt.Key_Up || key === Qt.Key_PageDown || key === Qt.Key_PageUp)) {
      var stepY = key === Qt.Key_Down ? 40 : key === Qt.Key_Up ? -40 : key === Qt.Key_PageDown ? planView.height * 0.8 : -planView.height * 0.8
      planView.contentY = Math.max(0, Math.min(planView.contentHeight - planView.height, planView.contentY + stepY))
    } else if (key === Qt.Key_Down) {
      root.select(1)
    } else if (key === Qt.Key_Up) {
      root.select(-1)
    } else if (key === Qt.Key_PageDown) {
      root.select(5)
    } else if (key === Qt.Key_PageUp) {
      root.select(-5)
    } else if (key === Qt.Key_Home) {
      root.selectEdge(false)
    } else if (key === Qt.Key_End) {
      root.selectEdge(true)
    } else if (ctrl && key === Qt.Key_R) {
      root.reload()
    } else if (ctrl) {
      return
    } else if (key === Qt.Key_Tab && root.role !== "") {
      root.switchRole()
    } else if (key === Qt.Key_F) {
      root.openPrompt("folder")
    } else if (root.role !== "" && key === Qt.Key_C) {
      root.togglePanel()
    } else if (root.role !== "" && key === Qt.Key_G) {
      root.groupBy = root.groupBy === "category" ? "kind" : "category"
      root.say(root.groupBy === "category" ? "Grouped by category." : "Grouped by type, as Understudy installs them.", false)
      root.rebuild()
    } else if (root.role !== "" && key === Qt.Key_Left) {
      root.fold(true)
    } else if (root.role !== "" && key === Qt.Key_Right) {
      root.fold(false)
    } else if (root.role !== "" && key === Qt.Key_Space && root.current && root.current.rowType === "section") {
      root.toggleCurrent()
    } else if (root.role === "secondary" && key === Qt.Key_Y) {
      root.copyRemoveCommand()
    } else if (root.role === "secondary" && key === Qt.Key_X) {
      root.dismissRemoved()
    } else if (root.role === "" && key === Qt.Key_M) {
      root.setRole("main")
    } else if (root.role === "" && key === Qt.Key_S) {
      root.setRole("secondary")
    } else if (root.role === "main" && key === Qt.Key_S) {
      root.loadScan()
    } else if (root.role === "main" && (key === Qt.Key_E || key === Qt.Key_Return || key === Qt.Key_Enter)) {
      root.exportList("")
    } else if (root.role === "main" && key === Qt.Key_P) {
      root.openPrompt("export")
    } else if (root.role === "main" && key === Qt.Key_A) {
      root.run(["config", "auto-export", root.status && root.status.autoExport ? "off" : "on"], "", function() { root.reload() })
    } else if (root.role === "secondary" && key === Qt.Key_Space) {
      root.toggleCurrent()
    } else if (root.role === "secondary" && key === Qt.Key_D) {
      root.showPlan()
    } else if (root.role === "secondary" && (key === Qt.Key_Return || key === Qt.Key_Enter)) {
      root.requestInstall()
    } else if (root.role === "secondary" && key === Qt.Key_I) {
      root.openPrompt("import")
    } else if (root.role === "secondary" && key === Qt.Key_H) {
      root.showAll = !root.showAll
      root.rebuild()
    } else {
      return
    }
    event.accepted = true
  }

  function hintsText() {
    if (root.promptKind !== "") return "⏎ ok   esc cancel"
    if (root.planOpen) return "↑↓ scroll   esc back"
    if (root.panelOpen) return root.role === "secondary" ? "space skip on this laptop   ⏎ show only this   esc back" : "⏎ show only this   esc back"
    if (root.role === "main") return "S scan   ⏎/E export   P export to…   A auto-export   C categories   G group   ←→ fold   F folder   tab role"
    if (root.role === "secondary" && root.current && root.current.rowType === "removed") return "Y copy the command   X stop reminding   ↑↓ move   esc close"
    if (root.role === "secondary") return "space tick   ←→ fold   C categories   G group   D commands   ⏎ install   I import   H " + (root.showAll ? "hide" : "all") + "   tab role"
    return "M main   S secondary   esc close"
  }

  function emptyText() {
    if (root.role === "") return "Is this the main laptop, or the second one?"
    if (root.busyText) return root.busyText
    if (root.role === "main" && root.categoryFilter && root.scan) return "Nothing in " + root.categoryFilter + ". Press C, then Enter on All categories."
    if (root.role === "main") return root.scan ? "Nothing was added since the first Omarchy install." : "Press S to scan."
    if (!root.diff) {
      if (root.status && !root.status.folderExists)
        return "The shared folder " + root.status.folder + " does not exist yet. Set it up in Syncthing (see the README), press F to pick another folder, or I to import a list from any path."
      return "No list yet. Export it on the main laptop, or press I to import one from any path."
    }
    if (root.categoryFilter) return "Nothing to show in " + root.categoryFilter + ". Press C, then Enter on All categories."
    return root.showAll ? "The list is empty." : "Everything on the list is here. H shows it all."
  }

  // ---------------------------------------------------------------- window

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-understudy"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.confirmOpen ? 20 : 0
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKey(event) }

        ConfirmDialog {
          id: confirmDialog
          anchors.fill: parent
          opened: root.confirmOpen
          z: 10
          message: root.diff ? Model.installConfirm(Model.selectedKeys(root.diff.items, root.ticks).length) : ""
          confirmText: "Open terminal"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelConfirm()
          onConfirmed: root.acceptInstall()
        }
      }

      Column {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // ------------------------------------------------------- header
        Item {
          width: parent.width
          height: root.headerHeight

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            Text {
              textFormat: Text.PlainText
              text: "󰑓"
              color: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "Understudy"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              visible: root.role !== ""
              anchors.verticalCenter: parent.verticalCenter
              radius: root.cornerRadius
              color: root.selectedBackground
              width: roleText.implicitWidth + Style.spacing.md * 2
              height: roleText.implicitHeight + Style.spacing.xs * 2

              Text {
                id: roleText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.role === "main" ? "Main" : "Secondary"
                color: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.5
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            textFormat: Text.PlainText
            text: root.busyText ? root.busyText
              : root.role === "main" ? Model.scanSummary(root.scan)
              : root.role === "secondary" && root.diff ? Model.diffSummary(root.diff.items, root.ticks)
                + (root.categoryFilter ? " · only " + root.categoryFilter : "")
              : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Where the list lives, and when it was written.
        Text {
          width: parent.width
          visible: root.role !== "" && root.status !== null
          textFormat: Text.PlainText
          elide: Text.ElideMiddle
          text: !root.status ? ""
            : "Folder " + root.status.folder + (root.status.folderExists ? "" : " (missing)")
              + (root.role === "main"
                  ? (root.status.listExists ? " · exported " + root.status.listGeneratedAt : " · not exported yet")
                    + (root.status.autoExport ? " · exports when opened" : "")
                  : root.diff ? " · list “" + (root.diff.label || "?") + "” from " + (root.diff.generatedAt || "?") : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Rectangle { width: parent.width; height: Style.normalBorderWidth; color: root.faint }

        // ---------------------------------------------------------- body
        Item {
          id: body
          width: parent.width
          height: parent.height - root.headerHeight - footer.height - Style.normalBorderWidth - Style.font.caption - root.contentSpacing * 4
            - (promptBar.visible ? promptBar.height + root.contentSpacing : 0)
          clip: true

          ListView {
            id: resultList
            anchors.fill: parent
            visible: !root.planOpen
            model: displayModel
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              id: row
              required property int index
              required property string rowType
              required property string rowKey
              required property string name
              required property string note
              required property string icon
              required property bool checkable
              required property bool checked
              required property bool installed
              required property bool collapsed

              readonly property bool isHeader: rowType === "header"
              readonly property bool isSection: rowType === "section"
              readonly property bool hasCursor: !isHeader && index === root.selectedIndex
              readonly property color ink: hasCursor ? root.selectedText : root.foreground

              width: ListView.view.width
              height: isHeader ? root.groupHeight : root.rowHeight

              PanelSectionHeader {
                visible: row.isHeader
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.spacing.xs
                text: row.name
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Rectangle {
                visible: !row.isHeader
                anchors.fill: parent
                radius: root.cornerRadius
                color: row.hasCursor ? root.selectedBackground : "transparent"

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    var again = row.index === root.selectedIndex
                    root.selectIndex(row.index)
                    if (again || mouse.x < Style.space(40)) root.toggleCurrent()
                  }
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  spacing: Style.spacing.lg

                  Text {
                    id: box
                    textFormat: Text.PlainText
                    width: Style.space(18)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.role === "secondary" || row.isSection
                    text: row.isSection ? (row.collapsed ? "󰅂" : "󰅀")
                      : row.rowType === "removed" ? "󰆴"
                      : row.rowType === "cat" && !row.checkable ? ""
                      : row.installed ? "󰄬" : !row.checkable ? "󰅖" : row.checked ? "󰄲" : "󰄱"
                    color: row.checkable || row.isSection ? row.ink : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Text {
                    id: kindIcon
                    textFormat: Text.PlainText
                    width: Style.space(18)
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.icon
                    color: row.ink
                    opacity: 0.8
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Column {
                    width: parent.width - kindIcon.width - (box.visible ? box.width + parent.spacing : 0) - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xxs

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: row.name
                      color: row.ink
                      opacity: root.role === "secondary" && row.rowType === "item" && !row.checkable ? 0.6 : 1
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: row.hasCursor || row.isSection
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      visible: row.note !== ""
                      text: row.note
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }
          }

          Flickable {
            id: planView
            anchors.fill: parent
            visible: root.planOpen
            clip: true
            contentWidth: width
            contentHeight: planTextItem.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Text {
              id: planTextItem
              width: planView.width
              textFormat: Text.PlainText
              text: root.planText
              color: root.foreground
              font.family: "monospace"
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
            }
          }

          Column {
            anchors.centerIn: parent
            width: parent.width - root.contentMargin * 2
            spacing: Style.spacing.lg
            visible: !root.planOpen && displayModel.count === 0

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "󰑓"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.emptyText()
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Row {
              visible: root.role === ""
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.spacing.lg

              Button {
                text: "Main  M"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.setRole("main")
              }

              Button {
                text: "Secondary  S"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.setRole("secondary")
              }
            }
          }
        }

        // A one-line text prompt for a path or folder.
        Rectangle {
          id: promptBar
          visible: root.promptKind !== ""
          width: parent.width
          height: Math.max(Style.space(30), Style.font.body + Style.spacing.controlPaddingY * 2)
          radius: root.cornerRadius
          color: root.selectedBackground

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.spacing.rowPaddingX
            anchors.rightMargin: Style.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            elide: Text.ElideLeft
            text: root.promptTitle() + ":  " + root.promptText + "▏"
            color: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        // -------------------------------------------------------- footer
        Item {
          id: footer
          width: parent.width
          height: Math.max(Style.space(20), Style.font.caption + Style.spacing.sm)

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: hints.left
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText
            color: root.statusUrgent ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            id: hints
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.hintsText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
