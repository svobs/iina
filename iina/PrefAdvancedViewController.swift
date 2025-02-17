//
//  PrefAdvancedViewController.swift
//  iina
//
//  Created by lhc on 14/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let tableCellFontSize: CGFloat = 13
// Options are of type text, which can be dangerous if unrelated text is on the clipboard.
fileprivate let maxAllowedPastedOptions = 1000

@objcMembers
class PrefAdvancedViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefAdvancedViewController")
  }

  var viewIdentifier: String = "PrefAdvancedViewController"

  var preferenceTabTitle: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.advanced", comment: "Advanced")
  }

  var preferenceTabImage: NSImage {
    return makeSymbol("flask", fallbackImage: "pref_advanced")
  }

  var preferenceContentIsScrollable: Bool {
    return false
  }

  var hasResizableWidth: Bool = false

  /// Each entry should have a 2-element array:
  var optionsList: [[String]] = []

  override var sectionViews: [NSView] {
    return [headerView, loggingSettingsView, mpvSettingsView]
  }

  private var tableDragDelegate: TableDragDelegate<[String]>? = nil

  @IBOutlet var headerView: NSView!
  @IBOutlet var loggingSettingsView: NSView!
  @IBOutlet var mpvSettingsView: NSView!

  @IBOutlet weak var enableAdvancedSettingsLabel: NSTextField!
  @IBOutlet weak var optionsTableView: EditableTableView!
  @IBOutlet weak var useAnotherConfigDirBtn: NSButton!
  @IBOutlet weak var chooseConfigDirBtn: NSButton!
  @IBOutlet weak var removeButton: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()

    guard let userOptions = Preference.value(for: .userOptions) as? [[String]] else {
      Utility.showAlert("extra_option.cannot_read", sheetWindow: view.window)
      return
    }
    optionsList = userOptions

    optionsTableView.dataSource = self
    optionsTableView.delegate = self
    optionsTableView.editableDelegate = self
    optionsTableView.editableTextColumnIndexes = [0, 1]
    optionsTableView.selectNextRowAfterDelete = false
    refreshRemoveButton()

    tableDragDelegate = TableDragDelegate<[String]>("mpvOptions",
                                                    optionsTableView,
                                                    acceptableDraggedTypes: [.string],
                                                    tableChangeNotificationName: .pendingUIChangeForMpvOptionsTable,
                                                    getFromPasteboardFunc: readOptionsListFromPasteboard,
                                                    getAllCurentFunc: { self.optionsList },
                                                    moveFunc: moveOptionRows,
                                                    insertFunc: insertOptionRows,
                                                    removeFunc: removeOptionRows)

    optionsTableView.sizeLastColumnToFit()

    enableAdvancedSettingsLabel.stringValue = NSLocalizedString("preference.enable_adv_settings",
                                                                comment: "Enable advanced settings")
  }

  private func saveToUserDefaults() {
    let optionsList = optionsList
    let cmdLineFormatted = optionsList.map{"--\(optionToString($0))"}.joined(separator: " ")
    Logger.log.verbose("Saving mpv user options to prefs. CmdLine equivalent: \(cmdLineFormatted.pii.quoted)")
    Preference.set(optionsList, for: .userOptions)
  }

  // MARK: Options Table Drag & Drop

  @objc func tableView(_ tableView: NSTableView, pasteboardWriterForRow rowIndex: Int) -> NSPasteboardWriting? {
    let optionsList = optionsList
    guard rowIndex < optionsList.count else { return nil }

    let rowString = optionToString(optionsList[rowIndex])
    return rowString as NSString?
  }

  @objc func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    return tableDragDelegate!.draggingSession(session, sourceOperationMaskFor: context)
  }

  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
    tableDragDelegate!.tableView(tableView, draggingSession: session, willBeginAt: screenPoint, forRowIndexes: rowIndexes)
  }

  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    tableDragDelegate!.tableView(tableView, draggingSession: session, endedAt: screenPoint, operation: operation)
  }

  @objc func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow rowIndex: Int,
                       proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
    return tableDragDelegate!.tableView(tableView, validateDrop: info, proposedRow: rowIndex,
                                        proposedDropOperation: dropOperation)
  }

  @objc func tableView(_ tableView: NSTableView,
                       acceptDrop info: NSDraggingInfo, row targetRowIndex: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
    return tableDragDelegate!.tableView(tableView, acceptDrop: info, row: targetRowIndex, dropOperation: dropOperation)
  }

  // MARK: - Options Table CRUD

  func insertOptionRows(_ itemList: [[String]], at targetRowIndex: Int) {
    let (tableUIChange, allItemsNew) = optionsTableView.buildInsert(of: itemList, at: targetRowIndex, in: optionsList,
                                                                    completionHandler: { [self] tableUIChange in
      // Do not query table directly here. It seems to interfere with the row animations.
      // Easy enough to get the selection from the TableUIChange object.
      removeButton.isHidden = !tableUIChange.hasSelectionAfterChange
    })
    
    // Save model
    optionsList = allItemsNew
    saveToUserDefaults()

    // Notify Options table of update:
    optionsTableView.post(tableUIChange)
  }

  func insertNewOptionRows(_ newItems: [[String]], at targetRowIndex: Int, thenStartEdit: Bool = false) {
    let (tableUIChange, allItemsNew) = optionsTableView.buildInsert(of: newItems, at: targetRowIndex, in: optionsList,
                                                                    completionHandler: { [self] tableUIChange in
      // We don't know beforehand exactly which row it will end up at, but we can get this info from the TableUIChange object
      if thenStartEdit, let insertedRowIndex = tableUIChange.toInsert?.first {
        optionsTableView.editCell(row: insertedRowIndex, column: 0)
      }
      removeButton.isHidden = !tableUIChange.hasSelectionAfterChange
    })

    optionsList = allItemsNew
    saveToUserDefaults()

    optionsTableView.post(tableUIChange)
  }

  func moveOptionRows(from rowIndexes: IndexSet, to targetRowIndex: Int) {
    let (tableUIChange, allItemsNew) = optionsTableView.buildMove(rowIndexes, to: targetRowIndex, in: optionsList,
                                                                  completionHandler: { [self] tableUIChange in
      removeButton.isHidden = !tableUIChange.hasSelectionAfterChange
    })

    optionsList = allItemsNew
    saveToUserDefaults()

    optionsTableView.post(tableUIChange)
  }

  func removeOptionRows(_ rowIndexes: IndexSet) {
    guard !rowIndexes.isEmpty else { return }
    
    Logger.log.verbose("Removing rows from Options table: \(rowIndexes)")
    let (tableUIChange, allItemsNew) = optionsTableView.buildRemove(rowIndexes, in: optionsList,
                                                                    completionHandler: { [self] tableUIChange in
      removeButton.isHidden = !tableUIChange.hasSelectionAfterChange
    })

    optionsList = allItemsNew
    saveToUserDefaults()

    optionsTableView.post(tableUIChange)
  }

  // MARK: - IBAction

  @IBAction func openLogDir(_ sender: AnyObject) {
    NSWorkspace.shared.open(Logger.logDirectory)
  }
  
  @IBAction func showLogWindow(_ sender: AnyObject) {
    AppDelegate.shared.logWindow.showWindow(self)
  }

  @IBAction func addOptionBtnAction(_ sender: AnyObject) {
    let selectedRowIndexes = optionsTableView.selectedRowIndexes
    let insertIndex = selectedRowIndexes.isEmpty ? optionsTableView.numberOfRows : selectedRowIndexes.max()! + 1
    insertNewOptionRows([["", ""]], at: insertIndex, thenStartEdit: true)
  }

  @IBAction func removeOptionBtnAction(_ sender: AnyObject) {
    removeOptionRows(optionsTableView.selectedRowIndexes)
  }

  @IBAction func chooseDirBtnAction(_ sender: AnyObject) {
    let existingDir: URL?
    if let prefValue = Preference.string(for: .userDefinedConfDir) {
      existingDir = URL(fileURLWithPath: prefValue)
    } else {
      existingDir = nil
    }
    Utility.quickOpenPanel(title: "Choose config directory", chooseDir: true, dir: existingDir, sheetWindow: view.window) { url in
      Preference.set(url.path, for: .userDefinedConfDir)
    }
  }

  @IBAction func helpBtnAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink)!.appendingPathComponent("MPV-Options-and-Properties"))
  }
}

extension PrefAdvancedViewController: NSTableViewDelegate, NSTableViewDataSource, NSControlTextEditingDelegate {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return optionsList.count
  }

  /**
   Make cell view when asked
   */
  @objc func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier else { return nil }

    guard let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView else {
      return nil
    }
    let columnName = identifier.rawValue

    guard row < optionsList.count else { return nil }

    let colIndex: Int
    switch columnName {
    case "Key":
      colIndex = 0

    case "Value":
      colIndex = 1

    default:
      Logger.log("Unrecognized column: '\(columnName)'", level: .error)
      return nil
    }

    guard let textField = cell.textField else { return nil }

    var useItalic = false
    let textColor: NSColor
    if !tableView.isEnabled {
      textColor = .disabledControlTextColor
    } else {
      if isValidOptionName(optionsList[row][0]) {
        textColor = .controlTextColor
      } else {
        textColor = .systemRed
        useItalic = true
      }
    }
    textField.font = .monospacedSystemFont(ofSize: tableCellFontSize, weight: .regular)
    textField.setFormattedText(stringValue: optionsList[row][colIndex], textColor: textColor, italic: useItalic)
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    refreshRemoveButton()
  }

  private func refreshRemoveButton() {
    removeButton.isHidden = optionsTableView.selectedRowIndexes.isEmpty
  }

  private func isValidOptionName(_ name: String) -> Bool {
    return !name.isEmpty && !name.containsWhitespaceOrNewlines()
  }
}

extension PrefAdvancedViewController: EditableTableViewDelegate {
  func userDidDoubleClickOnCell(row rowIndex: Int, column columnIndex: Int) -> Bool {
    Logger.log.verbose("Double-click: Edit requested for row \(rowIndex), col \(columnIndex)")
    optionsTableView.editCell(row: rowIndex, column: columnIndex)
    return true
  }

  func userDidPressEnterOnRow(_ rowIndex: Int) -> Bool {
    Logger.log.verbose("Enter key: Edit requested for row \(rowIndex)")
    optionsTableView.editCell(row: rowIndex, column: 0)
    return true
  }

  func editDidEndWithNewText(newValue: String, row rowIndex: Int, column columnIndex: Int) -> Bool {
    Logger.log.verbose("User finished editing value for row \(rowIndex), col \(columnIndex): \(newValue.quoted)")
    guard rowIndex < optionsList.count else {
      return false
    }

    var optionPair: [String] = optionsList[rowIndex]

    var newValue = newValue
    if columnIndex == 0 {
      // Delete unnecessary prefix from confused users
      newValue = newValue.deletingPrefix("--")

      if newValue.contains("=") {
        Logger.log.verbose("User name entry has '=' in it")
        if optionPair[1].isEmpty {
          // Assume user entered whole line in Name column. Just fix it
          let split = newValue.split(separator: "=")
          newValue = String(split[0])
          optionPair[1] = String(split[1])
        } else {
          // not valid - will break our parsing!
          return false
        }
      }
    }

    optionPair[columnIndex] = newValue
    optionsList[rowIndex] = optionPair
    saveToUserDefaults()

    DispatchQueue.main.async { [self] in
      optionsTableView.reloadRow(rowIndex)
    }
    return true
  }

  var hasSelectedRows: Bool {
    return !optionsTableView.selectedRowIndexes.isEmpty
  }

  func isDeleteEnabled() -> Bool {
    return hasSelectedRows
  }

  func doEditMenuDelete() {
    removeOptionRows(optionsTableView.selectedRowIndexes)
  }

  func isCutEnabled() -> Bool {
    return hasSelectedRows
  }

  func isCopyEnabled() -> Bool {
    return hasSelectedRows
  }

  func isPasteEnabled() -> Bool {
    return !readOptionsFromClipboard().isEmpty
  }

  // Edit menu action handlers. Delegates should override these if they want to support the standard operations.

  func doEditMenuCut() {
    doEditMenuCopy()
    doEditMenuDelete()
  }

  func doEditMenuCopy() {
    copyOptionsToClipboard(selectedOptions)
  }

  func doEditMenuPaste() {
    let optionsToInsert = readOptionsFromClipboard()
    guard !optionsToInsert.isEmpty else { return }
    let insertIndex: Int
    if let lastSelectedRow = optionsTableView.selectedRowIndexes.last {
      insertIndex = lastSelectedRow + 1
    } else {
      insertIndex = optionsTableView.numberOfRows
    }

    insertNewOptionRows(optionsToInsert, at: insertIndex)
  }

  fileprivate var selectedOptions: [[String]] {
    return optionsTableView.selectedRowIndexes.map { optionsList[$0] }
  }

}

// MARK: - Ser/De functions for options lists

fileprivate func optionsToStrings(_ optionsList: [[String]]) -> [String] {
  return optionsList.map { optionToString($0) }
}

fileprivate func optionToString(_ option: [String]) -> String {
  return option.joined(separator: "=")
}

fileprivate func optionFromString(_ stringItem: String) -> [String] {
  let splitted = stringItem.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
  let key = String(splitted[0])
  let val = splitted.count > 1 ? String(splitted[1]) : ""
  return [key, val]
}

/// Input pasteboard item: "{key}={val}"
/// Ouput item: `[key, val]`
fileprivate func readOptionsListFromPasteboard(_ pasteboard: NSPasteboard) -> [[String]] {
  let stringItems = pasteboard.getStringItems()
  guard stringItems.count <= Constants.mpvOptionsTableMaxRowsPerOperation else { return [] }
  var optionPairs: [[String]] = []
  for stringItem in stringItems {
    let option: [String] = optionFromString(stringItem)
    optionPairs.append(option)
  }
  return optionPairs
}

fileprivate func readOptionsFromClipboard() -> [[String]] {
  let optionsList = readOptionsListFromPasteboard(NSPasteboard.general)
  guard optionsList.count < maxAllowedPastedOptions else {
    Logger.log.debug("Disabling paste: clipboard contains more than \(maxAllowedPastedOptions) options (counted: \(optionsList.count))")
    return []
  }
  return optionsList
}

// Convert conf file path to URL and put it in clipboard
fileprivate func copyOptionsToClipboard(_ optionsList: [[String]]) {
  guard !optionsList.isEmpty else {
    Logger.log.debug("Cannot copy options list to the clipboard: list is empty")
    return
  }
  let optionStrings = optionsToStrings(optionsList) as [NSString]
  NSPasteboard.general.clearContents()
  NSPasteboard.general.writeObjects(optionStrings)
  Logger.log.verbose("Copied to the clipboard: \(optionsList.count) options")
}
