//
//  HistoryWindowController.swift
//  iina
//
//  Created by lhc on 28/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate extension NSUserInterfaceItemIdentifier {
  static let time = NSUserInterfaceItemIdentifier("Time")
  static let filename = NSUserInterfaceItemIdentifier("Filename")
  static let progress = NSUserInterfaceItemIdentifier("Progress")
  static let group = NSUserInterfaceItemIdentifier("Group")
  static let contextMenu = NSUserInterfaceItemIdentifier("ContextMenu")
}

fileprivate class LoadingPlaceholder: PlaybackHistory {
  init() {
    super.init(url: URL(fileURLWithPath: "/dev/null"), duration: 0, name: "")
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: Constants

fileprivate let loadingKey = "Loading..."
fileprivate let loadingPlaceholderLabel = ""  // displayed next to the loading spinner

fileprivate let MenuItemTagShowInFinder = 100
fileprivate let MenuItemTagDelete = 101
fileprivate let MenuItemTagSearchFilename = 200
fileprivate let MenuItemTagSearchFullPath = 201
fileprivate let MenuItemTagPlay = 300
fileprivate let MenuItemTagPlayInNewWindow = 301

fileprivate let timeColMinWidths: [Preference.HistoryGroupBy: CGFloat] = [
  .lastPlayedDay: 60,
  .parentFolder: 145
]

class HistoryWindowController: IINAWindowController, NSOutlineViewDelegate, NSOutlineViewDataSource,
                               NSMenuDelegate, NSMenuItemValidation {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("HistoryWindowController")
  }

  @IBOutlet weak var outlineView: NSOutlineView!
  @IBOutlet weak var historySearchField: NSSearchField!

  private let log: Logger.Subsystem
  private var co: CocoaObserver!

  @Atomic private var reloadTicketCounter: Int = 0
  private var isInitialLoadDone = false

  private var backgroundQueue = DispatchQueue.newDQ(label: "HistoryWindow-BG", qos: .background)
  private var lastCompleteStatusReloadTime = Date(timeIntervalSince1970: 0)

  var groupBy: Preference.HistoryGroupBy = HistoryWindowController.getGroupByFromPrefs() ?? Preference.HistoryGroupBy.defaultValue
  var searchType: Preference.HistorySearchType = HistoryWindowController.getHistorySearchTypeFromPrefs() ?? Preference.HistorySearchType.defaultValue
  var searchString: String = HistoryWindowController.getSearchStringFromPrefs() ?? ""

  private static let loadingData = [loadingKey: [LoadingPlaceholder()]]
  private var historyData: [String: [PlaybackHistory]] = HistoryWindowController.loadingData
  private var historyDataKeys: [String] = [loadingKey]
  private var fileExistsMap: [URL: Bool] = [:]

  private var selectedEntries: [PlaybackHistory] = []

  init() {
    log = HistoryController.shared.log

    super.init(window: nil)
    windowFrameAutosaveName = WindowAutosaveName.playbackHistory.string

    co = CocoaObserver(log, prefDidChange: prefDidChange, [
      .uiHistoryTableGroupBy,
      .uiHistoryTableSearchType,
      .uiHistoryTableSearchString
    ], [
      .default: [

        .init(.iinaHistoryUpdated) { [self] _ in
          log.verbose("History window received iinaHistoryUpdated; will reload data")
          // Force full status reload:
          lastCompleteStatusReloadTime = Date(timeIntervalSince1970: 0)
          reloadData(silent: true)
        },

        .init(.iinaFileHistoryDidUpdate) { [self] note in
          guard !AppDelegate.shared.isTerminating else { return }
          guard let url = note.userInfo?["url"] as? URL else {
            log.error("Cannot update file history: no url found in userInfo!")
            return
          }
          log.verbose("History window got iinaFileHistoryDidUpdate; will reload watch-later for URL & possibly reload table")

          backgroundQueue.async { [self] in
            guard fileExistsMap.removeValue(forKey: url) != nil else { return }
            reloadData(silent: true)
          }
        }
      ]
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Called each time a pref `key`'s value is set
  private func prefDidChange(_ key: Preference.Key, _ newValue: Any?) {
    switch key {
    case .uiHistoryTableGroupBy:
      guard let groupByNew = HistoryWindowController.getGroupByFromPrefs(), groupByNew != groupBy else { return }
      groupBy = groupByNew
    case .uiHistoryTableSearchType:
      guard let searchTypeNew = HistoryWindowController.getHistorySearchTypeFromPrefs(), searchTypeNew != searchType else { return }
      searchType = searchTypeNew
    case .uiHistoryTableSearchString:
      guard let searchStringNew = HistoryWindowController.getSearchStringFromPrefs(), searchStringNew != searchString else { return }
      searchString = searchStringNew
      historySearchField.stringValue = searchString

    default:
      break
    }
    guard isWindowLoaded else { return }
    reloadData()
  }

  override func windowDidLoad() {
    super.windowDidLoad()
    historySearchField.stringValue = searchString
    outlineView.delegate = self
    outlineView.dataSource = self
    outlineView.menu?.delegate = self
    outlineView.target = self
    outlineView.doubleAction = #selector(doubleAction)
    log.verbose("History windowDidLoad done")
  }

  override func openWindow(_ sender: Any?) {
    guard let _ = window else { return }  // load window
    assert(isWindowLoaded, "Expected History window to be loaded!")

    if !isInitialLoadDone {
      // Expand to show loading placeholder
      outlineView.expandItem(nil, expandChildren: true)

      /// Enquque in `HistoryController.shared.queue` to establish a happens-after relationship with initial history load.
      HistoryController.shared.async { [self] in
#if DEBUG
        if DebugConfig.addHistoryWindowLoadingDelay {
          log.debug("Sleeping for 5 sec to test History window async loading...")
          Thread.sleep(forTimeInterval: 5)
        }
      #endif
        self.reloadData()
      }
    }

    co.addAllObservers()

    // Reload may take a long time. Send signal to open right away, and refresh when load is done.
    super.openWindow(sender)
  }

  func windowWillClose(_ notification: Notification) {
    log.verbose("History window will close")
    // Invalidate ticket
    $reloadTicketCounter.withLock { $0 += 1 }
    co.removeAllObservers()
  }

  private func isTicketStillValid(_ ticket: Int) -> Bool {
    ticket == reloadTicketCounter
  }

  /// Can be called from any DispatchQueue
  private func reloadData(silent: Bool = false) {
    // Reloads are expensive and many things can trigger them.
    // Use a counter + a delay to reduce duplicated work (except for initial load)
    let ticket: Int = $reloadTicketCounter.withLock {
      $0 += 1
      return $0
    }


    if isInitialLoadDone {
      DispatchQueue.main.async { [self] in
        if !silent {
          showLoadingUI()
        }

        // Expand to show loading placeholder
        outlineView.expandItem(nil, expandChildren: true)

        backgroundQueue.asyncAfter(deadline: .now() + .seconds(1)) { [self] in
          guard isTicketStillValid(ticket) else { return }
          _reloadData(ticket: ticket)
        }
      }
    } else {
      backgroundQueue.async { [self] in
        _reloadData(ticket: ticket)
      }
    }
  }

  /// Resets table to loading msg
  private func showLoadingUI() {
    historyData = HistoryWindowController.loadingData
    historyDataKeys = [loadingKey]
    outlineView.reloadData()
  }

  private func _reloadData(ticket: Int) {
    assert(DispatchQueue.isExecutingIn(backgroundQueue))

    let isInitialLoad = !isInitialLoadDone
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
      let key = getKey(entry)

      if historyDataUpdated[key] == nil {
        historyDataUpdated[key] = []
        historyDataKeysUpdated.append(key)
      }
      historyDataUpdated[key]!.append(entry)
    }

    DispatchQueue.main.async { [self] in
      guard isInitialLoad || isTicketStillValid(ticket) else { return }  // check ticket

      // Update data and reload UI
      historyData = historyDataUpdated
      historyDataKeys = historyDataKeysUpdated

      adjustTimeColumnMinWidth()
      outlineView.reloadData()
      outlineView.expandItem(nil, expandChildren: true)

      log.verbose("Reloaded history table: \(historyList.count) entries, filter=\(searchString.quoted) in \(sw.secElapsedString) (tkt \(reloadTicketCounter))")

      if isInitialLoad {
        isInitialLoadDone = true
      }
    }

    guard isInitialLoad || isTicketStillValid(ticket) else { return }  // check ticket

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
          guard isInitialLoad || isTicketStillValid(ticket) else { return }  // check ticket
        }
      }
    }
    guard isInitialLoad || isTicketStillValid(ticket) else {return }  // check ticket

    self.fileExistsMap = fileExistsMap
    log.debug("Filled in fileExists for \(count) of \(historyList.count) histories in \(sw2.secElapsedString), wasFullReload=\(forceFullStatusReload.yn) watchLaterFilesLoaded=\(watchLaterCount) fileExistsMapSize=\(fileExistsMap.count)")
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
      HistoryController.shared.async {
        HistoryController.shared.remove(entries)
      }
    }
  }

  @objc func doubleAction() {
    if let selected = outlineView.item(atRow: outlineView.clickedRow) as? PlaybackHistory {
      let player = PlayerManager.shared.getActiveOrCreateNew()
      player.openURL(selected.url)
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

  func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
    return isInitialLoadDone
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
      if item as? LoadingPlaceholder != nil {
        return ""
      } else if tableColumn?.identifier == .time {
        return getTimeString(from: entry)
      } else if tableColumn?.identifier == .progress {
        return VideoTime.string(from: entry.duration)
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

        if item as? LoadingPlaceholder != nil {
          // Loading placeholder for initial load
          let font = filenameView.textField!.font!
          let italicDescriptor: NSFontDescriptor = font.fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits.italic)
          let italicFont = NSFont(descriptor: italicDescriptor, size: font.pointSize)
          let attrString =  NSMutableAttributedString(string: loadingPlaceholderLabel, attributes: [.font: italicFont!])
          filenameView.textField?.attributedStringValue = attrString
          filenameView.textField?.textColor = .controlTextColor
          if #available(macOS 15.0, *) {
            let spinImage = NSImage(systemSymbolName: "progress.indicator", accessibilityDescription: "Loading...")!
            filenameView.docImage.setSymbolImage(spinImage, contentTransition: .automatic)
            let effect = VariableColorSymbolEffect.variableColor.iterative.dimInactiveLayers.nonReversing
            filenameView.docImage.addSymbolEffect(effect, options: .repeat(.continuous))
          } else {
            // Just show loading text
            filenameView.docImage.image = nil
          }

        } else {
          filenameView.textField?.stringValue = entry.url.isFileURL ? entry.name : entry.url.absoluteString
          let fileExists = fileExistsMap[entry.url] ?? true
          filenameView.textField?.textColor = fileExists ? .controlTextColor : .disabledControlTextColor
          filenameView.docImage.image = Utility.icon(for: entry.url)
        }

      } else if identifier == .progress {
        // Progress cell
        let progressView = cell as! HistoryProgressCellView
        // Do not animate! Causes unneeded slowdown
        progressView.indicator.usesThreadedAnimation = false

        if let progress = entry.mpvProgress {
          progressView.textField?.stringValue = VideoTime.string(from: progress)
          progressView.indicator.isHidden = false
          progressView.indicator.doubleValue = progress / entry.duration
        } else {
          progressView.textField?.stringValue = ""
          progressView.indicator.isHidden = true
        }
      }
      return cell
    } else {
      // group header
      guard let groupCell: NSTableCellView = outlineView.makeView(withIdentifier: .group, owner: nil) as? NSTableCellView else { return nil }
      return groupCell
    }
  }

  private func getTimeString(from entry: PlaybackHistory) -> String {
    if groupBy == .lastPlayedDay {
      return DateFormatter.localizedString(from: entry.addedDate, dateStyle: .none, timeStyle: .short)
    } else {
      return DateFormatter.localizedString(from: entry.addedDate, dateStyle: .short, timeStyle: .short)
    }
  }

  // MARK: - Menu

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
    PlayerManager.shared.getActiveOrCreateNew().openURL(firstEntry.url)
  }

  @IBAction func playInNewWindowAction(_ sender: AnyObject) {
    guard let firstEntry = selectedEntries.first else { return }
    PlayerManager.shared.getIdleOrCreateNew().openURL(firstEntry.url)
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
    UIState.shared.set(newValue.rawValue, for: .uiHistoryTableSearchType)
    reloadData()
  }

  @IBAction func searchFieldAction(_ sender: NSSearchField) {
    // avoid reload if no change:
    guard searchString != sender.stringValue else { return }
    self.searchString = sender.stringValue
    UIState.shared.set(sender.stringValue, for: .uiHistoryTableSearchString)
    reloadData()
  }

  // MARK: Misc support functions

  private static func getGroupByFromPrefs() -> Preference.HistoryGroupBy? {
    return UIState.shared.isRestoreEnabled ? Preference.enum(for: .uiHistoryTableGroupBy) : nil
  }

  private static func getHistorySearchTypeFromPrefs() -> Preference.HistorySearchType? {
    return UIState.shared.isRestoreEnabled ? Preference.enum(for: .uiHistoryTableSearchType) : nil
  }

  private static func getSearchStringFromPrefs() -> String? {
    return UIState.shared.isRestoreEnabled ? Preference.string(for: .uiHistoryTableSearchString) : nil
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

  private func getKey(_ entry: PlaybackHistory) -> String {
    switch groupBy {
    case .lastPlayedDay:
      return DateFormatter.localizedString(from: entry.addedDate, dateStyle: .medium, timeStyle: .none)
    case .parentFolder:
      return entry.url.deletingLastPathComponent().path
    }
  }

}


// MARK: - Other classes

class HistoryFilenameCellView: NSTableCellView {

  @IBOutlet var docImage: NSImageView!

}

class HistoryProgressCellView: NSTableCellView {

  @IBOutlet var indicator: NSProgressIndicator!

  /// Prepares the receiver for service after it has been loaded from an Interface Builder archive, or nib file.
  /// - Important: As per Apple's [Internationalization and Localization Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/SupportingRight-To-LeftLanguages/SupportingRight-To-LeftLanguages.html)
  ///     timeline indicators should not flip in a right-to-left language. This can not be set in the XIB.
  override func awakeFromNib() {
    indicator.userInterfaceLayoutDirection = .leftToRight
  }
}
