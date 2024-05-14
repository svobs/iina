//
//  HistoryWindowController.swift
//  iina
//
//  Created by lhc on 28/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let MenuItemTagShowInFinder = 100
fileprivate let MenuItemTagDelete = 101
fileprivate let MenuItemTagSearchFilename = 200
fileprivate let MenuItemTagSearchFullPath = 201
fileprivate let MenuItemTagPlay = 300
fileprivate let MenuItemTagPlayInNewWindow = 301

fileprivate extension NSUserInterfaceItemIdentifier {
  static let time = NSUserInterfaceItemIdentifier("Time")
  static let filename = NSUserInterfaceItemIdentifier("Filename")
  static let progress = NSUserInterfaceItemIdentifier("Progress")
  static let group = NSUserInterfaceItemIdentifier("Group")
  static let contextMenu = NSUserInterfaceItemIdentifier("ContextMenu")
}

fileprivate let timeColMinWidths: [Preference.HistoryGroupBy: CGFloat] = [
  .lastPlayedDay: 60,
  .parentFolder: 145
]

class HistoryWindowController: IINAWindowController, NSOutlineViewDelegate, NSOutlineViewDataSource, NSMenuDelegate, NSMenuItemValidation {
  var log = HistoryController.shared.log

  private let getKey: [Preference.HistoryGroupBy: (PlaybackHistory) -> String] = [
    .lastPlayedDay: { DateFormatter.localizedString(from: $0.addedDate, dateStyle: .medium, timeStyle: .none) },
    .parentFolder: { $0.url.deletingLastPathComponent().path }
  ]

  override var windowNibName: NSNib.Name {
    return NSNib.Name("HistoryWindowController")
  }

  @Atomic var reloadTicketCounter: Int = 0

  private var backgroundQueue = DispatchQueue(label: "HistoryWindowBackground", qos: .background)

  @IBOutlet weak var outlineView: NSOutlineView!
  @IBOutlet weak var historySearchField: NSSearchField!

  var groupBy: Preference.HistoryGroupBy = HistoryWindowController.getGroupByFromPrefs() ?? Preference.HistoryGroupBy.defaultValue
  var searchType: Preference.HistorySearchType = HistoryWindowController.getHistorySearchTypeFromPrefs() ?? Preference.HistorySearchType.defaultValue
  var searchString: String = HistoryWindowController.getSearchStringFromPrefs() ?? ""

  private var historyData: [String: [PlaybackHistory]] = [:]
  private var historyDataKeys: [String] = []
  private var fileExistsMap: [URL: Bool] = [:]

  private var lastCompleteStatusReloadTime = Date(timeIntervalSince1970: 0)

  private var observedPrefKeys: [Preference.Key] = [
    .uiHistoryTableGroupBy,
    .uiHistoryTableSearchType,
    .uiHistoryTableSearchString
  ]

  init() {
    super.init(window: nil)
    self.windowFrameAutosaveName = WindowAutosaveName.playbackHistory.string

    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    ObjcUtils.silenced {
      for key in self.observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, change != nil else { return }

    switch keyPath {
    case PK.uiHistoryTableGroupBy.rawValue:
      guard let groupByNew = HistoryWindowController.getGroupByFromPrefs(), groupByNew != groupBy else { return }
      groupBy = groupByNew
    case PK.uiHistoryTableSearchType.rawValue:
      guard let searchTypeNew = HistoryWindowController.getHistorySearchTypeFromPrefs(), searchTypeNew != searchType else { return }
      searchType = searchTypeNew
    case PK.uiHistoryTableSearchString.rawValue:
      guard let searchStringNew = HistoryWindowController.getSearchStringFromPrefs(), searchStringNew != searchString else { return }
      searchString = searchStringNew
      historySearchField.stringValue = searchString
      
    default:
      break
    }
    if isWindowLoaded {
      reloadData()
    }
  }
  
  override func windowDidLoad() {
    super.windowDidLoad()

    NotificationCenter.default.addObserver(forName: .iinaHistoryUpdated, object: nil, queue: .main) { [unowned self] _ in
      log.verbose("History window received iinaHistoryUpdated; will reload data")
      // Force full status reload:
      lastCompleteStatusReloadTime = Date(timeIntervalSince1970: 0)
      self.reloadData()
    }

    historySearchField.stringValue = searchString

    outlineView.delegate = self
    outlineView.dataSource = self
    outlineView.menu?.delegate = self
    outlineView.target = self
    outlineView.doubleAction = #selector(doubleAction)
    log.verbose("History windowDidLoad done")
  }

  override func openWindow(_ sender: Any?) {
    guard let window else { return }
    window.orderOut(self)  // Hide window. Should load window as a side effect, if not loaded already
    assert(isWindowLoaded, "Expected History window to be loaded!")

    let isInitialLoad = reloadTicketCounter == 0
    if isInitialLoad {
      /// Enquque in `HistoryController.shared.queue` to establish a happens-after relationship with history load.
      HistoryController.shared.queue.async { [self] in
        self.reloadData()
      }
    } else {
      // No need to reload data (it's an expensive operation)
      showWindow(sender)
    }
  }

  private static func getGroupByFromPrefs() -> Preference.HistoryGroupBy? {
    return Preference.UIState.isRestoreEnabled ? Preference.enum(for: .uiHistoryTableGroupBy) : nil
  }

  private static func getHistorySearchTypeFromPrefs() -> Preference.HistorySearchType? {
    return Preference.UIState.isRestoreEnabled ? Preference.enum(for: .uiHistoryTableSearchType) : nil
  }

  private static func getSearchStringFromPrefs() -> String? {
    return Preference.UIState.isRestoreEnabled ? Preference.string(for: .uiHistoryTableSearchString) : nil
  }

  // Change min width of "Played at" column
  private func adjustTimeColumnMinWidth() {
    guard let timeColumn = outlineView.tableColumn(withIdentifier: .time) else { return }
    let newMinWidth = timeColMinWidths[groupBy]!
    guard newMinWidth != timeColumn.minWidth else { return }
    if timeColumn.width < newMinWidth {
      if let filenameColumn = outlineView.tableColumn(withIdentifier: .filename) {
        donateColWidth(to: timeColumn, targetWidth: newMinWidth, from: filenameColumn)
      }
      if timeColumn.width < timeColumn.minWidth {
        if let progressColumn = outlineView.tableColumn(withIdentifier: .progress) {
          donateColWidth(to: timeColumn, targetWidth: newMinWidth, from: progressColumn)
        }
      }
    }
    // Do not set this until after width has been adjusted! Otherwise AppKit will change its width property
    // but will not actually resize it:
    timeColumn.minWidth = newMinWidth
    outlineView.layoutSubtreeIfNeeded()
    log.verbose("Updated \(timeColumn.identifier.rawValue.quoted) col width: \(timeColumn.width), minWidth: \(timeColumn.minWidth)")
  }

  private func donateColWidth(to targetColumn: NSTableColumn, targetWidth: CGFloat, from donorColumn: NSTableColumn) {
    let extraWidthNeeded = targetWidth - targetColumn.width
    // Don't take more than needed, or more than possible:
    let widthToDonate = min(extraWidthNeeded, max(donorColumn.width - donorColumn.minWidth, 0))
    if widthToDonate > 0 {
      log.verbose("Donating \(widthToDonate) pts width to col \(targetColumn.identifier.rawValue.quoted) from \(donorColumn.identifier.rawValue.quoted) width (\(donorColumn.width))")
      donorColumn.width -= widthToDonate
      targetColumn.width += widthToDonate
    }
  }

  private func reloadData() {
    // Reloads are expensive and many things can trigger them.
    // Use a counter + a delay to reduce duplicated work (except for initial load)
    reloadTicketCounter += 1
    let ticket = reloadTicketCounter
    let isInitialLoad = reloadTicketCounter == 1

    if isInitialLoad {
      backgroundQueue.async { [self] in
        _reloadData(ticket: ticket)
      }
    } else {
      backgroundQueue.asyncAfter(deadline: .now() + .seconds(1)) { [self] in
        guard ticket == reloadTicketCounter else { return }
        _reloadData(ticket: ticket)
      }
    }
  }

  private func _reloadData(ticket: Int) {
    let isInitialLoad = ticket == 1
    // reconstruct data
    let sw = Utility.Stopwatch()
    let unfilteredHistory = HistoryController.shared.history
    let historyList: [PlaybackHistory]
    if searchString.isEmpty {
      historyList = unfilteredHistory
    } else {
      historyList = unfilteredHistory.filter { entry in
        let string = searchType == .filename ? entry.name : entry.url.path
        // Do a locale-aware, case and diacritic insensitive search:
        return string.localizedStandardContains(searchString)
      }
    }
    var historyDataUpdated: [String: [PlaybackHistory]] = [:]
    var historyDataKeysUpdated: [String] = []

    for entry in historyList {
      let key = getKey[groupBy]!(entry)

      if historyDataUpdated[key] == nil {
        historyDataUpdated[key] = []
        historyDataKeysUpdated.append(key)
      }
      historyDataUpdated[key]!.append(entry)
    }

    // Update data and reload UI
    historyData = historyDataUpdated
    historyDataKeys = historyDataKeysUpdated

    DispatchQueue.main.async {
      self.adjustTimeColumnMinWidth()
      self.outlineView.reloadData()
      self.outlineView.expandItem(nil, expandChildren: true)

      self.log.verbose("Reloaded history table with \(historyList.count) entries, filtered=\((!self.searchString.isEmpty).yn) in \(sw.secElapsedString) (tkt \(self.reloadTicketCounter))")

      if isInitialLoad {
        super.openWindow(self)
      }
    }

    // optimization
//    guard !Preference.bool(for: .isRestoreInProgress) else { return }

    guard isInitialLoad || ticket == reloadTicketCounter else { return }  // check ticket

    // Put all FileManager stuff in background queue. It can hang for a long time if there are network problems.
    // Network or file system can change over time and cause our info to become out of date.
    // Do a full reload if too much time has gone by since the last full reload
    let forceFullStatusReload = Date().timeIntervalSince(lastCompleteStatusReloadTime) > Constants.TimeInterval.historyTableCompleteFileStatusReload
    let sw2 = Utility.Stopwatch()

    var fileExistsMap: [URL: Bool] = forceFullStatusReload ? [:] : self.fileExistsMap

    var count: Int = 0
    var watchLaterCount: Int = 0
    for entry in historyList {
      // Fill in fileExists
      if fileExistsMap[entry.url] == nil {
        fileExistsMap[entry.url] = !entry.url.isFileURL || FileManager.default.fileExists(atPath: entry.url.path)
        let wasWatchLaterFound = entry.loadProgressFromWatchLater()
        count += 1
        if wasWatchLaterFound {
          watchLaterCount += 1
        }
        if (count %% 100) == 0 {
          guard isInitialLoad || ticket == reloadTicketCounter else { return }  // check ticket
        }
      }
    }
    guard isInitialLoad || ticket == reloadTicketCounter else {return }  // check ticket

    self.fileExistsMap = fileExistsMap
    log.debug("Filled in fileExists for \(count) of \(historyList.count) history entries in \(sw2.secElapsedString) (wasFullReload=\(forceFullStatusReload.yn) watchLaterFilesLoaded=\(watchLaterCount)). FileExistsMap size is now \(fileExistsMap.count)")
    if forceFullStatusReload {
      lastCompleteStatusReloadTime = Date()
    }

    if count > 0 {
      DispatchQueue.main.async { [self] in
        // Reload table again to refresh statuses
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
        log.verbose("Reloaded History table with updated fileExists data")
      }
    }
  }

  private func removeAfterConfirmation(_ entries: [PlaybackHistory]) {
    Utility.quickAskPanel("delete_history", sheetWindow: window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      HistoryController.shared.remove(entries)
    }
  }

  // MARK: Key event

  override func keyDown(with event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags == .command  {
      switch event.charactersIgnoringModifiers! {
      case "f":
        window!.makeFirstResponder(historySearchField)
      case "a":
        outlineView.selectAll(nil)
      default:
        break
      }
    } else {
      let key = KeyCodeHelper.mpvKeyCode(from: event)
      if key == "DEL" || key == "BS" {
        let entries = outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? PlaybackHistory }
        removeAfterConfirmation(entries)
      }
    }
  }

  // MARK: NSOutlineViewDelegate

  @objc func doubleAction() {
    if let selected = outlineView.item(atRow: outlineView.clickedRow) as? PlaybackHistory {
      PlayerCore.activeOrNew.openURL(selected.url)
    }
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    return item is String
  }

  func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
    return item is String
  }

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    if let item = item {
      return historyData[item as! String]!.count
    } else {
      return historyData.count
    }
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if let item = item {
      return historyData[item as! String]![index]
    } else {
      return historyDataKeys[index]
    }
  }

  func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
    if let entry = item as? PlaybackHistory {
      if tableColumn?.identifier == .time {
        return getTimeString(from: entry)
      } else if tableColumn?.identifier == .progress {
        return entry.duration.stringRepresentation
      }
    }
    return item
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    if let identifier = tableColumn?.identifier {
      guard let cell: NSTableCellView = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView else { return nil }
      guard let entry = item as? PlaybackHistory else { return cell }
      if identifier == .filename {
        // Filename cell
        let filenameView = cell as! HistoryFilenameCellView
        filenameView.textField?.stringValue = entry.url.isFileURL ? entry.name : entry.url.absoluteString
        let fileExists = fileExistsMap[entry.url] ?? true
        filenameView.textField?.textColor = fileExists ? .controlTextColor : .disabledControlTextColor
        filenameView.docImage.image = NSWorkspace.shared.icon(forFileType: entry.url.pathExtension)
      } else if identifier == .progress {
        // Progress cell
        let progressView = cell as! HistoryProgressCellView
        // Do not animate! Causes unneeded slowdown
        progressView.indicator.usesThreadedAnimation = false
        if let progress = entry.mpvProgress {
          progressView.textField?.stringValue = progress.stringRepresentation
          progressView.indicator.isHidden = false
          progressView.indicator.doubleValue = (progress / entry.duration) ?? 0
        } else {
          progressView.textField?.stringValue = ""
          progressView.indicator.isHidden = true
        }
      }
      return cell
    } else {
      // group columns
      return outlineView.makeView(withIdentifier: .group, owner: nil)
    }
  }

  private func getTimeString(from entry: PlaybackHistory) -> String {
    if groupBy == .lastPlayedDay {
      return DateFormatter.localizedString(from: entry.addedDate, dateStyle: .none, timeStyle: .short)
    } else {
      return DateFormatter.localizedString(from: entry.addedDate, dateStyle: .short, timeStyle: .short)
    }
  }

  // MARK: - Searching

  @IBAction func searchFieldAction(_ sender: NSSearchField) {
    // avoid reload if no change:
    guard searchString != sender.stringValue else { return }
    self.searchString = sender.stringValue
    Preference.UIState.set(sender.stringValue, for: .uiHistoryTableSearchString)
    backgroundQueue.async { [self] in
      reloadData()
    }
  }

  // MARK: - Menu

  private var selectedEntries: [PlaybackHistory] = []

  func menuNeedsUpdate(_ menu: NSMenu) {
    var indexSet = IndexSet()
    let selectedRowIndexes = outlineView.selectedRowIndexes
    let clickedRow = outlineView.clickedRow
    if clickedRow != -1 {
      if selectedRowIndexes.contains(clickedRow) {
        indexSet = selectedRowIndexes
      } else {
        indexSet.insert(clickedRow)
      }
    }
    selectedEntries = indexSet.compactMap { outlineView.item(atRow: $0) as? PlaybackHistory }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.tag {
    case MenuItemTagShowInFinder:
      if selectedEntries.isEmpty { return false }
      return selectedEntries.contains { $0.url.isFileURL && (fileExistsMap[$0.url] ?? false) }
    case MenuItemTagDelete:
      // "Delete" in this case only removes from history
      return !selectedEntries.isEmpty
    case MenuItemTagPlay, MenuItemTagPlayInNewWindow:
      if selectedEntries.isEmpty { return false }
      return selectedEntries.contains { !$0.url.isFileURL || (fileExistsMap[$0.url] ?? false) }
    case MenuItemTagSearchFilename:
      menuItem.state = searchType == .filename ? .on : .off
    case MenuItemTagSearchFullPath:
      menuItem.state = searchType == .fullPath ? .on : .off
    default:
      break
    }
    return menuItem.isEnabled
  }

  // MARK: - IBActions

  @IBAction func playAction(_ sender: AnyObject) {
    guard let firstEntry = selectedEntries.first else { return }
    PlayerCore.active.openURL(firstEntry.url)
  }

  @IBAction func playInNewWindowAction(_ sender: AnyObject) {
    guard let firstEntry = selectedEntries.first else { return }
    PlayerCore.newPlayerCore.openURL(firstEntry.url)
  }

  @IBAction func showInFinderAction(_ sender: AnyObject) {
    let urls = selectedEntries.compactMap { FileManager.default.fileExists(atPath: $0.url.path) ? $0.url: nil }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  @IBAction func deleteAction(_ sender: AnyObject) {
    removeAfterConfirmation(self.selectedEntries)
  }

  @IBAction func searchTypeFilenameAction(_ sender: AnyObject) {
    setSearchType(.filename)
  }

  @IBAction func searchTypeFullPathAction(_ sender: AnyObject) {
    setSearchType(.fullPath)
  }

  private func setSearchType(_ newValue: Preference.HistorySearchType) {
    // avoid reload if no change:
    guard searchType != newValue else { return }
    searchType = newValue
    Preference.UIState.set(newValue.rawValue, for: .uiHistoryTableSearchType)
    backgroundQueue.async { [self] in
      reloadData()
    }
  }
}


// MARK: - Other classes

class HistoryFilenameCellView: NSTableCellView {

  @IBOutlet var docImage: NSImageView!

}

class HistoryProgressCellView: NSTableCellView {

  @IBOutlet var indicator: NSProgressIndicator!

}
