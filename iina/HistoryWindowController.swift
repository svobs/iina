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

class HistoryWindowController: NSWindowController, NSOutlineViewDelegate, NSOutlineViewDataSource, NSMenuDelegate, NSMenuItemValidation {

  private let getKey: [Preference.HistoryGroupBy: (PlaybackHistory) -> String] = [
    .lastPlayedDay: { DateFormatter.localizedString(from: $0.addedDate, dateStyle: .medium, timeStyle: .none) },
    .parentFolder: { $0.url.deletingLastPathComponent().path }
  ]

  override var windowNibName: NSNib.Name {
    return NSNib.Name("HistoryWindowController")
  }

  @IBOutlet weak var outlineView: NSOutlineView!
  @IBOutlet weak var historySearchField: NSSearchField!

  var groupBy: Preference.HistoryGroupBy = HistoryWindowController.getGroupByFromPrefs() ?? Preference.HistoryGroupBy.defaultValue
  var searchType: Preference.HistorySearchType = HistoryWindowController.getHistorySearchTypeFromPrefs() ?? Preference.HistorySearchType.defaultValue
  var searchString: String = HistoryWindowController.getSearchStringFromPrefs() ?? ""

  private var historyData: [String: [PlaybackHistory]] = [:]
  private var historyDataKeys: [String] = []

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
      self.reloadData()
    }

    historySearchField.stringValue = searchString

    outlineView.delegate = self
    outlineView.dataSource = self
    outlineView.menu?.delegate = self
    outlineView.target = self
    outlineView.doubleAction = #selector(doubleAction)
    reloadData()
  }

  override func showWindow(_ sender: Any?) {
    Logger.log("Showing History window", level: .verbose)
    super.showWindow(sender)
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
    Logger.log("Updated \(timeColumn.identifier.rawValue.quoted) col width: \(timeColumn.width), minWidth: \(timeColumn.minWidth)", level: .verbose)
  }

  private func donateColWidth(to targetColumn: NSTableColumn, targetWidth: CGFloat, from donorColumn: NSTableColumn) {
    let extraWidthNeeded = targetWidth - targetColumn.width
    // Don't take more than needed, or more than possible:
    let widthToDonate = min(extraWidthNeeded, max(donorColumn.width - donorColumn.minWidth, 0))
    if widthToDonate > 0 {
      Logger.log("Donating \(widthToDonate) pts width to col \(targetColumn.identifier.rawValue.quoted) from \(donorColumn.identifier.rawValue.quoted) width (\(donorColumn.width))")
      donorColumn.width -= widthToDonate
      targetColumn.width += widthToDonate
    }
  }

  private func reloadData() {
    // reconstruct data
    historyData.removeAll()
    historyDataKeys.removeAll()

    adjustTimeColumnMinWidth()

    let historyList: [PlaybackHistory]
    if searchString.isEmpty {
      historyList = HistoryController.shared.history
    } else {
      historyList = HistoryController.shared.history.filter { entry in
        let string = searchType == .filename ? entry.name : entry.url.path
        // Do a locale-aware, case and diacritic insensitive search:
        return string.localizedStandardContains(searchString)
      }
    }
    Logger.log("Reloading history table with \(historyList.count) entries, filtered=\((!searchString.isEmpty).yn)", level: .verbose)

    for entry in historyList {
      let key = getKey[groupBy]!(entry)

      if historyData[key] == nil {
        historyData[key] = []
        historyDataKeys.append(key)
      }
      historyData[key]!.append(entry)
    }

    outlineView.reloadData()
    outlineView.expandItem(nil, expandChildren: true)
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
        // FIXME: this will hang if there are network problems! Put all FileManager stuff in background queue
        let fileExists = !entry.url.isFileURL || FileManager.default.fileExists(atPath: entry.url.path)
        filenameView.textField?.stringValue = entry.url.isFileURL ? entry.name : entry.url.absoluteString
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
    reloadData()
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
      return selectedEntries.contains { FileManager.default.fileExists(atPath: $0.url.path) }
    case MenuItemTagDelete:
      // "Delete" in this case only removes from history
      return !selectedEntries.isEmpty
    case MenuItemTagPlay, MenuItemTagPlayInNewWindow:
      if selectedEntries.isEmpty { return false }
      return selectedEntries.contains { !$0.url.isFileURL || FileManager.default.fileExists(atPath: $0.url.path) }
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
    reloadData()
  }
}


// MARK: - Other classes

class HistoryFilenameCellView: NSTableCellView {

  @IBOutlet var docImage: NSImageView!

}

class HistoryProgressCellView: NSTableCellView {

  @IBOutlet var indicator: NSProgressIndicator!

}
