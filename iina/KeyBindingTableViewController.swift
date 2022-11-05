//
//  KeyBindingTableViewController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.03.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

@available(macOS 10.14, *)
fileprivate let nonConfTextColor: NSColor = .controlAccentColor
@available(macOS 10.14, *)
fileprivate let pluginIconColor: NSColor = .controlAccentColor
@available(macOS 10.14, *)
fileprivate let libmpvIconColor: NSColor = .controlAccentColor
@available(macOS 10.14, *)
fileprivate let filterIconColor: NSColor = .controlAccentColor

fileprivate let COLUMN_INDEX_KEY = 0
fileprivate let COLUMN_INDEX_ACTION = 2
fileprivate let DRAGGING_FORMATION: NSDraggingFormation = .list
fileprivate let DEFAULT_DRAG_OPERATION = NSDragOperation.move

class KeyBindingTableViewController: NSObject {

  private unowned var tableView: EditableTableView!
  private var configStore: InputConfigStore {
    return AppInputConfig.inputConfigStore
  }

  private var bindingStore: InputBindingStore {
    return AppInputConfig.inputBindingStore
  }

  private var selectionDidChangeHandler: () -> Void
  private var observers: [NSObjectProtocol] = []

  init(_ kbTableView: EditableTableView, selectionDidChangeHandler: @escaping () -> Void) {
    self.tableView = kbTableView
    self.selectionDidChangeHandler = selectionDidChangeHandler

    super.init()
    tableView.dataSource = self
    tableView.delegate = self
    tableView.editableDelegate = self

    tableView.menu = NSMenu()
    tableView.menu?.delegate = self

    tableView.allowsMultipleSelection = true
    tableView.editableTextColumnIndexes = [COLUMN_INDEX_KEY, COLUMN_INDEX_ACTION]
    tableView.registerTableChangeObserver(forName: .iinaKeyBindingsTableShouldUpdate)
    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingErrorOccurred, object: nil, queue: .main, using: errorDidOccur))
    if #available(macOS 10.13, *) {
      var acceptableDraggedTypes: [NSPasteboard.PasteboardType] = [.iinaKeyMapping]
      if Preference.bool(for: .acceptRawTextAsKeyBindings) {
        acceptableDraggedTypes.append(.string)
      }
      tableView.registerForDraggedTypes(acceptableDraggedTypes)
      tableView.setDraggingSourceOperationMask([DEFAULT_DRAG_OPERATION], forLocal: false)
      tableView.draggingDestinationFeedbackStyle = .regular
    }

    tableView.scrollRowToVisible(0)
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  // Display error alert for errors:
  private func errorDidOccur(_ notification: Notification) {
    guard let alertInfo = notification.object as? Utility.AlertInfo else {
      Logger.log("Notification.iinaKeyBindingErrorOccurred: cannot display error: invalid object: \(type(of: notification.object))", level: .error)
      return
    }
    Utility.showAlert(alertInfo.key, arguments: alertInfo.args, sheetWindow: self.tableView.window)
  }
}

// MARK: NSTableViewDelegate

extension KeyBindingTableViewController: NSTableViewDelegate {

  @objc func tableViewSelectionDidChange(_ notification: Notification) {
    selectionDidChangeHandler()
  }

  // Disalllow certain row indexes to be selected when user tries to perform a selection
  @objc func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
    var approvedSelectionIndexes = IndexSet()
    for index in proposedSelectionIndexes {
      if let row = bindingStore.getBindingRow(at: index), row.canBeModified {
        approvedSelectionIndexes.insert(index)
      }
    }
    return approvedSelectionIndexes
  }

  /**
   Make cell view when asked
   */
  @objc func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let bindingRow = bindingStore.getBindingRow(at: row) else {
      return nil
    }

    guard let identifier = tableColumn?.identifier else { return nil }

    guard let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView else {
      return nil
    }
    let columnName = identifier.rawValue

    switch columnName {
      case "keyColumn":
        let stringValue = bindingRow.getKeyColumnDisplay(raw: isRaw)
        setFormattedText(for: cell, to: stringValue, isEnabled: bindingRow.isEnabled, origin: bindingRow.origin)
        return cell

      case "actionColumn":
        let stringValue = bindingRow.getActionColumnDisplay(raw: isRaw)
        setFormattedText(for: cell, to: stringValue, isEnabled: bindingRow.isEnabled, origin: bindingRow.origin, italic: !bindingRow.canBeModified)
        return cell

      case "statusColumn":
        cell.toolTip = bindingRow.displayMessage

        if let imageView: NSImageView = cell.imageView {
          if #available(macOS 11.0, *) {
            imageView.isHidden = false

            if !bindingRow.isEnabled {
              imageView.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)!
              imageView.contentTintColor = NSColor.systemRed
              return cell
            }

            switch bindingRow.origin {
              case .iinaPlugin:
                imageView.image = NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: nil)!
                imageView.contentTintColor = pluginIconColor
              case .libmpv:
                imageView.image = NSImage(systemSymbolName: "applescript.fill", accessibilityDescription: nil)!
                imageView.contentTintColor = libmpvIconColor
              case .savedFilter:
                imageView.image = NSImage(systemSymbolName: "camera.filters", accessibilityDescription: nil)!
                imageView.contentTintColor = filterIconColor
              default:
                if bindingRow.menuItem != nil {
                  imageView.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil)!
                } else {
                  imageView.image = nil
                }
                imageView.contentTintColor = NSColor.controlTextColor
            }
          } else {
            // FIXME: find icons to use so that all versions are supported
            imageView.isHidden = true
          }
        }

        return cell

      default:
        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
        return nil
    }
  }

  private func setFormattedText(for cell: NSTableCellView, to stringValue: String, isEnabled: Bool, origin: InputBindingOrigin, italic: Bool = false) {
    guard let textField = cell.textField else { return }

    if isEnabled {
      var textColor: NSColor
      if #available(macOS 10.14, *) {
        textColor = nonConfTextColor
      } else {
        textColor = .linkColor
      }

      setText(of: textField, to: stringValue, textColor: origin == InputBindingOrigin.confFile ? nil : textColor, italic: italic)
    } else {
      setText(of: textField, to: stringValue, textColor: NSColor.systemRed, strikethrough: true, italic: italic)
    }
  }

  private func setText(of textField: NSTextField, to stringValue: String,
                       textColor: NSColor? = nil,
                       strikethrough: Bool = false,
                       italic: Bool = false) {
    let attrString = NSMutableAttributedString(string: stringValue)

    let fgColor: NSColor
    if let textColor = textColor {
      // If using custom text colors, need to make sure `EditableTextFieldCell` is specified
      // as the class of the child cell in Interface Builder.
      fgColor = textColor
    } else {
      fgColor = NSColor.controlTextColor
    }
    textField.textColor = fgColor

    if strikethrough {
      attrString.addAttrib(NSAttributedString.Key.strikethroughStyle, NSUnderlineStyle.single.rawValue)
    }

    if italic {
      attrString.addItalic(from: textField.font)
    }
    textField.attributedStringValue = attrString
  }

  private var isRaw: Bool {
    return Preference.bool(for: .displayKeyBindingRawValues)
  }

  private var selectedRows: [InputBinding] {
    Array(tableView.selectedRowIndexes.compactMap( { bindingStore.getBindingRow(at: $0) }))
  }

  private var selectedCopiableRows: [InputBinding] {
    self.selectedRows.filter({ $0.canBeCopied })
  }

  private var selectedModifiableRows: [InputBinding] {
    self.selectedRows.filter({ $0.canBeModified })
  }
}

// MARK: NSTableViewDataSource

extension KeyBindingTableViewController: NSTableViewDataSource {
  /*
   Tell AppKit the number of rows when it asks
   */
  @objc func numberOfRows(in tableView: NSTableView) -> Int {
    return bindingStore.bindingRowCount
  }

  // MARK: Drag & Drop

  /*
   Drag start: define which operations are allowed, and in which contexts
   */
  @objc func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    switch(context) {
      case .withinApplication:
        return .copy.union(.move)
      case .outsideApplication:
        return .copy
      default:
        return .copy
    }
  }

  /*
   Drag start: convert tableview rows to clipboard items
   */
  @objc func tableView(_ tableView: NSTableView, pasteboardWriterForRow rowIndex: Int) -> NSPasteboardWriting? {
    let row = bindingStore.getBindingRow(at: rowIndex)
    if let row = row, row.canBeModified {
      return row.keyMapping
    }
    return nil
  }

  /**
   This is implemented to support dropping items onto the Trash icon in the Dock.
   TODO: look for a way to animate this so that it's more obvious that something happened.
   */
  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    guard configStore.isEditEnabledForCurrentConfig, operation == NSDragOperation.delete else {
      return
    }

    let rmappingList = KeyMapping.deserializeList(from: session.draggingPasteboard)

    guard !rmappingList.isEmpty else {
      return
    }

    Logger.log("User dragged to the trash: \(rmappingList)", level: .verbose)

    bindingStore.removeBindings(withIDs: rmappingList.map{$0.bindingID!})
  }

  /*
   Validate drop while hovering.
   */
  @objc func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow rowIndex: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {

    guard configStore.isEditEnabledForCurrentConfig else {
      return []  // deny drop
    }

    let mappingList = KeyMapping.deserializeList(from: info.draggingPasteboard)

    guard !mappingList.isEmpty else {
      return []  // deny drop
    }

    // Update that little red number:
    info.numberOfValidItemsForDrop = mappingList.count

    info.draggingFormation = DRAGGING_FORMATION

    // Do not animate the drop; we have the row animations already
    info.animatesToDestination = false

    // Cannot drop on/into existing rows. Change to below it:
    let isAfterNotAt = dropOperation == .on
    // Can only make changes to the "default" section. If the drop cursor is not already inside it,
    // then we'll change it to the nearest valid index in the "default" section.
    let dropTargetRow = bindingStore.getClosestValidInsertIndex(from: rowIndex, isAfterNotAt: isAfterNotAt)

    tableView.setDropRow(dropTargetRow, dropOperation: .above)

    let dragMask = info.draggingSourceOperationMask
    switch dragMask {
      case .copy, .move:
        return dragMask
      default:
        return DEFAULT_DRAG_OPERATION
    }
  }

  /*
   Accept the drop and execute changes, or reject drop.
   */
  @objc func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row rowIndex: Int, dropOperation: NSTableView.DropOperation) -> Bool {

    let rowList = KeyMapping.deserializeList(from: info.draggingPasteboard)
    Logger.log("User dropped \(rowList.count) binding rows into KeyBinding table \(dropOperation == .on ? "on" : "above") rowIndex \(rowIndex)")
    guard !rowList.isEmpty else {
      return false
    }

    guard dropOperation == .above else {
      Logger.log("KeyBindingTableView: expected dropOperaion==.above but got: \(dropOperation); aborting drop")
      return false
    }

    info.numberOfValidItemsForDrop = rowList.count
    info.draggingFormation = DRAGGING_FORMATION
    info.animatesToDestination = true

    var dragMask = info.draggingSourceOperationMask
    if dragMask.contains(.every) || dragMask.contains(.generic) {
      dragMask = DEFAULT_DRAG_OPERATION
    }

    // Return immediately, and import (or fail to) asynchronously
    if dragMask.contains(.copy) {
      DispatchQueue.main.async {
        self.copyMappings(from: rowList, to: rowIndex, isAfterNotAt: false)
      }
      return true
    } else if dragMask.contains(.move) {
      DispatchQueue.main.async {
        self.moveMappings(from: rowList, to: rowIndex, isAfterNotAt: false)
      }
      return true
    } else {
      Logger.log("Rejecting drop: got unexpected drag mask: \(dragMask)")
      return false
    }
  }
}

// MARK: EditableTableViewDelegate

extension KeyBindingTableViewController: EditableTableViewDelegate {

  func userDidDoubleClickOnCell(row rowIndex: Int, column columnIndex: Int) -> Bool {
    guard requireCurrentConfigIsEditable(forAction: "edit cell") else { return false }

    guard bindingStore.isEditEnabledForBindingRow(rowIndex) else {
      Logger.log("Edit is not allowed for binding row \(rowIndex)", level: .verbose)
      return false
    }

    if isRaw {
      Logger.log("Double-click: opening in-line editor for row \(rowIndex)", level: .verbose)
      // Use in-line editor
      return true
    }

    editWithPopup(rowIndex: rowIndex)
    // Deny in-line editor from opening
    return false
  }

  func userDidPressEnterOnRow(_ rowIndex: Int) -> Bool {
    guard requireCurrentConfigIsEditable(forAction: "edit row") else { return false }

    guard bindingStore.isEditEnabledForBindingRow(rowIndex) else {
      Logger.log("Edit is not allowed for binding row \(rowIndex)", level: .verbose)
      return false
    }

    if isRaw {
      Logger.log("Opening inline editor for row \(rowIndex)", level: .verbose)
      // Use in-line editor
      return true
    }

    editWithPopup(rowIndex: rowIndex)
    // Deny in-line editor from opening
    return false
  }

  func editDidEndWithNewText(newValue: String, row rowIndex: Int, column columnIndex: Int) -> Bool {
    guard bindingStore.isEditEnabledForBindingRow(rowIndex) else {
      // An error here would be really bad
      Logger.log("Cannot save binding row \(rowIndex): edit is not allowed for this row type! If you see this message please report it.", level: .error)
      return false
    }

    guard let editedRow = bindingStore.getBindingRow(at: rowIndex) else {
      Logger.log("userDidEndEditing(): failed to get row \(rowIndex) (newValue='\(newValue)')")
      return false
    }

    Logger.log("User finished editing value for row \(rowIndex), col \(columnIndex): \"\(newValue)\"", level: .verbose)

    let key, action: String?
    switch columnIndex {
      case COLUMN_INDEX_KEY:
        key = KeyCodeHelper.escapeReservedMpvKeys(newValue)
        action = nil
      case COLUMN_INDEX_ACTION:
        key = nil
        action = newValue
      default:
        Logger.log("userDidEndEditing(): bad column index: \(columnIndex)")
        return false
    }

    let newVersion = editedRow.keyMapping.clone(rawKey: key, rawAction: action)
    bindingStore.updateBinding(at: rowIndex, to: newVersion)
    return true
  }

  // MARK: Reusable actions

  // Edit either inline or with popup, depending on current mode
  private func edit(rowIndex: Int, columnIndex: Int = 0) {
    guard requireCurrentConfigIsEditable(forAction: "edit") else { return }

    Logger.log("Edit requested for row \(rowIndex), col \(columnIndex)")

    guard bindingStore.isEditEnabledForBindingRow(rowIndex) else {
      // Should never see this message
      Logger.log("Cannot edit binding row \(rowIndex): edit is not allowed for this row! Aborting", level: .error)
      return
    }

    if isRaw {
      // Use in-line editor
      self.tableView.editCell(row: rowIndex, column: columnIndex)
    } else {
      editWithPopup(rowIndex: rowIndex)
    }
  }

  // Use this if isRaw==false (i.e., not inline editing)
  private func editWithPopup(rowIndex: Int) {
    Logger.log("Opening key binding pop-up for row #\(rowIndex)", level: .verbose)

    guard let row = bindingStore.getBindingRow(at: rowIndex) else {
      return
    }

    showEditBindingPopup(key: row.keyMapping.rawKey, action: row.keyMapping.readableAction) { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      let newVersion = row.keyMapping.clone(rawKey: key, rawAction: action)
      self.bindingStore.updateBinding(at: rowIndex, to: newVersion)
    }
  }

  // Adds a new binding after the current selection and then opens an editor for it. The editor with either be inline or using the popup,
  // depending on whether isRaw is true or false, respectively.
  func addNewBinding() {
    var rowIndex: Int
    // If there are selected rows, add the new row right below the last selection. Otherwise add to end of table.
    if let lastSelectionIndex = tableView.selectedRowIndexes.max() {
      rowIndex = lastSelectionIndex
    } else {
      rowIndex = self.tableView.numberOfRows - 1
    }
    editNewEmptyBinding(relativeTo: rowIndex, isAfterNotAt: true)
  }

  // Adds a new binding at the given location then opens an editor for it. The editor with either be inline or using the popup,
  // depending on whether isRaw is true or false, respectively.
  // If isAfterNotAt==true, inserts after the row with given rowIndex. If isAfterNotAt==false, inserts before the row with given rowIndex.
  private func editNewEmptyBinding(relativeTo rowIndex: Int, isAfterNotAt: Bool = false) {
    guard requireCurrentConfigIsEditable(forAction: "insert binding") else { return }

    Logger.log("Inserting new binding \(isAfterNotAt ? "after" : "at") current row index: \(rowIndex)", level: .verbose)

    if isRaw {
      // The table will execute asynchronously, but we need to wait for it to complete in order to guarantee we have something to edit
      let afterComplete: TableChange.CompletionHandler = { tableChange in
        // We don't know beforehand exactly which row it will end up at, but we can get this info from the TableChange object
        if let insertedRowIndex = tableChange.toInsert?.first {
          self.tableView.editCell(row: insertedRowIndex, column: 0)
        }
      }
      let newMapping = KeyMapping(rawKey: "", rawAction: "")
      let _ = bindingStore.insertNewBinding(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, newMapping, afterComplete: afterComplete)

    } else {
      showEditBindingPopup { key, action in
        guard !key.isEmpty && !action.isEmpty else { return }

        let newMapping = KeyMapping(rawKey: key, rawAction: action)
        self.bindingStore.insertNewBinding(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, newMapping,
                                                afterComplete: self.scrollToFirstInserted)
      }
    }
  }

  // Displays popup for editing a binding
  private func showEditBindingPopup(key: String = "", action: String = "", ok: @escaping (String, String) -> Void) {
    let panel = NSAlert()
    let keyRecordViewController = KeyRecordViewController()
    keyRecordViewController.keyCode = key
    keyRecordViewController.action = action
    panel.messageText = NSLocalizedString("keymapping.title", comment: "Key Mapping")
    panel.informativeText = NSLocalizedString("keymapping.message", comment: "Press any key to record.")
    panel.accessoryView = keyRecordViewController.view
    panel.window.initialFirstResponder = keyRecordViewController.keyRecordView
    let okButton = panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    okButton.cell!.bind(.enabled, to: keyRecordViewController, withKeyPath: "ready", options: nil)
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.beginSheetModal(for: tableView.window!) { respond in
      if respond == .alertFirstButtonReturn {
        ok(keyRecordViewController.keyCode, keyRecordViewController.action)
      }
    }
  }

  // e.g., drag & drop "copy" operation
  private func copyMappings(from mappingList: [KeyMapping], to rowIndex: Int, isAfterNotAt: Bool = false) {
    guard requireCurrentConfigIsEditable(forAction: "move binding(s)") else { return }
    guard !mappingList.isEmpty else { return }

    // Make sure to use copy() to clone the object here
    let newMappings: [KeyMapping] = mappingList.map { $0.clone() }

    bindingStore.insertNewBindings(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, newMappings,
                                                                    afterComplete: scrollToFirstInserted)
  }

  // e.g., drag & drop "move" operation
  private func moveMappings(from mappingList: [KeyMapping], to rowIndex: Int, isAfterNotAt: Bool = false) {
    guard requireCurrentConfigIsEditable(forAction: "move binding(s)") else { return }
    guard !mappingList.isEmpty else { return }

    let firstInsertedRowIndex = bindingStore.moveBindings(mappingList, to: rowIndex, isAfterNotAt: isAfterNotAt,
                                                               afterComplete: self.scrollToFirstInserted)
    self.tableView.scrollRowToVisible(firstInsertedRowIndex)
  }

  // Each TableUpdate executes asynchronously, but we need to wait for it to complete in order to do any further work on
  // inserted rows.
  private func scrollToFirstInserted(_ tableChange: TableChange) {
    if let firstInsertedRowIndex = tableChange.toInsert?.first {
      self.tableView.scrollRowToVisible(firstInsertedRowIndex)
    }
  }

  func removeSelectedBindings() {
    Logger.log("Removing selected bindings", level: .verbose)
    bindingStore.removeBindings(at: tableView.selectedRowIndexes)
  }

  private func requireCurrentConfigIsEditable(forAction action: String) -> Bool {
    if configStore.isEditEnabledForCurrentConfig {
      return true
    }

    // Should never see this ideally. If we do, something went wrong with UI enablement.
    Logger.log("Cannot \(action): cannot modify a default config. Telling user to duplicate the config instead", level: .verbose)
    Utility.showAlert("duplicate_config", sheetWindow: tableView.window)
    return false
  }

  // MARK: Cut, copy, paste, delete support.

  // Only selected table items which have `canBeModified==true` can be included.
  // Each menu item should be disabled if it cannot operate on at least one item.

  func isCopyEnabled() -> Bool {
    return !selectedCopiableRows.isEmpty
  }

  func isCutEnabled() -> Bool {
    return isDeleteEnabled()
  }

  func isDeleteEnabled() -> Bool {
    return configStore.isEditEnabledForCurrentConfig && !selectedModifiableRows.isEmpty
  }

  func isPasteEnabled() -> Bool {
    return configStore.isEditEnabledForCurrentConfig && !readBindingsFromClipboard().isEmpty
  }

  func doEditMenuCut() {
    if copyToClipboard() {
      removeSelectedBindings()
    }
  }

  func doEditMenuCopy() {
    _ = copyToClipboard()
  }

  func doEditMenuPaste() {
    // default to *after* current selection
    if let desiredInsertIndex = self.tableView.selectedRowIndexes.last {
      pasteFromClipboard(relativeTo: desiredInsertIndex, isAfterNotAt: true)
    } else {
      pasteFromClipboard(relativeTo: self.tableView.numberOfRows, isAfterNotAt: true)
    }
  }

  func doEditMenuDelete() {
    removeSelectedBindings()
  }

  // If `rowsToCopy` is specified, copies it to the Clipboard.
  // If it is not specified, uses the currently selected rows
  // Returns `true` if it copied at least 1 row; `false` if not
  private func copyToClipboard(rowsToCopy: [InputBinding]? = nil) -> Bool {
    let rows: [InputBinding]
    if let rowsToCopy = rowsToCopy {
      rows = rowsToCopy.filter({ $0.canBeCopied })
    } else {
      rows = self.selectedCopiableRows
    }

    if rows.isEmpty {
      Logger.log("No bindings to copy: not touching clipboard", level: .verbose)
      return false
    }

    let mappings = rows.map { $0.keyMapping }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(mappings)
    Logger.log("Copied \(rows.count) bindings to the clipboard", level: .verbose)
    return true
  }

  private func pasteFromClipboard(relativeTo rowIndex: Int, isAfterNotAt: Bool = false) {
    let mappingsToInsert = readBindingsFromClipboard()
    guard !mappingsToInsert.isEmpty else {
      Logger.log("Aborting Paste action because there is nothing to paste", level: .warning)
      return
    }
    Logger.log("Pasting \(mappingsToInsert.count) bindings \(isAfterNotAt ? "after" : "at") index \(rowIndex)")
    bindingStore.insertNewBindings(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, mappingsToInsert,
                                        afterComplete: self.scrollToFirstInserted)
  }

  private func readBindingsFromClipboard() -> [KeyMapping] {
    return KeyMapping.deserializeList(from: NSPasteboard.general)
  }
}

// MARK: NSMenuDelegate

extension KeyBindingTableViewController: NSMenuDelegate {

  fileprivate class BindingMenuItem: NSMenuItem {
    let row: InputBinding
    let rowIndex: Int

    public init(_ row: InputBinding, rowIndex: Int, title: String, action selector: Selector?, keyEquivalent: String = "") {
      self.row = row
      self.rowIndex = rowIndex
      super.init(title: title, action: selector, keyEquivalent: keyEquivalent)
    }

    required init(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  fileprivate class BindingsMenuBuilder: ContextMenuBuilder<InputBinding> {
    override func buildItem(for row: InputBinding, withIndex rowIndex: Int, title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
      return BindingMenuItem(row, rowIndex: rowIndex, title: title, action: action, keyEquivalent: keyEquivalent)
    }
  }

  private func addReadOnlyConfigMenuItem(_ bdr: BindingsMenuBuilder) {
    bdr.addItalicDisabledItem("Cannot make changes: \"\(configStore.currentConfigName)\" is a built-in config")
  }

  func menuNeedsUpdate(_ contextMenu: NSMenu) {
    // This will prevent menu from showing if no items are added
    contextMenu.removeAllItems()

    let clickedIndex = tableView.clickedRow
    guard let clickedRow = bindingStore.getBindingRow(at: tableView.clickedRow) else { return }
    let bdr = BindingsMenuBuilder(contextMenu, clickedRow: clickedRow, clickedRowIndex: tableView.clickedRow, target: self)

    if tableView.selectedRowIndexes.count > 1 && tableView.selectedRowIndexes.contains(clickedIndex) {
      populate(bdr, for: tableView.selectedRowIndexes)
    } else {
      populateForSingleRow(bdr)
    }
  }

  // SINGLE: For right-click on a single row. This may be selected, if it is the only row in the selection.
  private func populateForSingleRow(_ bdr: BindingsMenuBuilder) {
    let isRowEditable = configStore.isEditEnabledForCurrentConfig && bdr.clickedRow.canBeModified

    if !configStore.isEditEnabledForCurrentConfig {
      addReadOnlyConfigMenuItem(bdr)
    } else if !isRowEditable {
      let culprit: String
      switch bdr.clickedRow.origin {
        case .iinaPlugin:
          let sourceName = (bdr.clickedRow.keyMapping as? MenuItemMapping)?.sourceName ?? "<ERROR>"
          culprit = "the IINA plugin \"\(sourceName)\""
        case .savedFilter:
          let sourceName = (bdr.clickedRow.keyMapping as? MenuItemMapping)?.sourceName ?? "<ERROR>"
          culprit = "the saved filter \"\(sourceName)\""
        case .libmpv:
          culprit = "a Lua script or other mpv interface"
        default:
          Logger.log("Unrecognized binding origin for rowIndex \(bdr.clickedRowIndex): \(bdr.clickedRow.origin)", level: .error)
          culprit = "<unknown>"
      }
      bdr.addItalicDisabledItem("Cannot modify binding: it is owned by \(culprit)")
    } else {
      // Edit options
      if isRaw {
        bdr.addItem("Edit Key", #selector(self.editKeyColumn(_:)), key: KeyCodeHelper.KeyEquivalents.RETURN, keyMods: [])
        bdr.addItem("Edit Action", #selector(self.editActionColumn(_:)))
      } else {
        bdr.addItem("Edit Row...", #selector(self.editRow(_:)), key: KeyCodeHelper.KeyEquivalents.RETURN, keyMods: [])
      }
    }

    // ---
    bdr.addSeparator()

    // Cut, Copy, Paste, Delete
    bdr.addItem("Cut", #selector(self.cutRow(_:)), enabled: isRowEditable, key: "x")
    bdr.addItem("Copy", #selector(self.copyRow(_:)), enabled: bdr.clickedRow.canBeCopied, key: "c")
    let pastableBindings = readBindingsFromClipboard()
    let pasteTitle = makePasteMenuItemTitle(itemCount: pastableBindings.count)
    if !configStore.isEditEnabledForCurrentConfig || pastableBindings.isEmpty {
      bdr.addItem("Paste", nil, enabled: false, key: "v")
    } else if isRowEditable {
      bdr.addItem("\(pasteTitle) Above", #selector(self.pasteAbove(_:)))
      bdr.addItem("\(pasteTitle) Below", #selector(self.pasteBelow(_:)), key: "v")
    } else {
      // If current row is not editable, a new row can only be added in the direction of the editable rows ("default" section).
      let isAfterNotAt = bindingStore.getClosestValidInsertIndex(from: bdr.clickedRowIndex) > bdr.clickedRowIndex
      let directionLabel = isAfterNotAt ? "Below" : "Above"
      let selector = isAfterNotAt ? #selector(self.pasteBelow(_:)) : #selector(self.pasteAbove(_:))
      bdr.addItem("\(pasteTitle) \(directionLabel)", selector, key: "v")
    }

    // ---
    bdr.addSeparator()

    bdr.addItem(isRowEditable ? "Delete Binding" : "Delete", #selector(self.removeRow(_:)), enabled: isRowEditable, key: KeyCodeHelper.KeyEquivalents.BACKSPACE, keyMods: [])

    // ---
    bdr.addSeparator()

    // Add New: follow same logic as Paste
    if configStore.isEditEnabledForCurrentConfig {
      if isRowEditable {
        bdr.addItem("Insert New \(Constants.String.keyBinding) Above", #selector(self.addNewRowAbove(_:)))
        bdr.addItem("Insert New \(Constants.String.keyBinding) Below", #selector(self.addNewRowBelow(_:)))
      } else {
        // If current row is not editable, a new row can only be added in the direction of the editable rows ("default" section).
        let isAfterNotAt = bindingStore.getClosestValidInsertIndex(from: bdr.clickedRowIndex) > bdr.clickedRowIndex
        let directionLabel = isAfterNotAt ? "Below" : "Above"
        let selector = isAfterNotAt ? #selector(self.addNewRowBelow(_:)) : #selector(self.addNewRowAbove(_:))
        bdr.addItem("Insert New \(Constants.String.keyBinding) \(directionLabel)", selector)
      }
    }
  }

  // MULTIPLE: For right-click on selected rows
  private func populate(_ bdr: BindingsMenuBuilder, for selectedRowIndexes: IndexSet) {
    let selectedRowsCount = tableView.selectedRowIndexes.count

    var modifiableCount = 0
    var copyableCount = 0
    for rowIndex in tableView.selectedRowIndexes {
      if let bindingRow = bindingStore.getBindingRow(at: rowIndex) {
        if bindingRow.canBeCopied {
          copyableCount += 1
        }
        if bindingRow.canBeModified {
          modifiableCount += 1
        }
      }
    }

    // Add disabled italicized message if not all can be operated on
    if !configStore.isEditEnabledForCurrentConfig {
      modifiableCount = 0
      addReadOnlyConfigMenuItem(bdr)
    } else {
      let readOnlyCount = tableView.selectedRowIndexes.count - modifiableCount
      if readOnlyCount > 0 {
        let readOnlyDisclaimer: String
        if readOnlyCount == selectedRowsCount {
          readOnlyDisclaimer = "\(readOnlyCount) bindings are read-only"
        } else {
          readOnlyDisclaimer = "\(readOnlyCount) of \(selectedRowsCount) bindings are read-only"
        }
        bdr.addItalicDisabledItem(readOnlyDisclaimer)
      }
    }

    // ---
    bdr.addSeparator()

    // Cut, Copy, Paste, Delete

    var title = "Cut"
    if modifiableCount > 0 {
      title += " \(modifiableCount) \(Constants.String.keyBinding)s"
    }
    // By setting target:`tableView`, AppKit, will call `tableView.validateUserInterfaceItem()` to enable/disable each action appropriately
    bdr.addItem(title, #selector(self.tableView.cut(_:)), target: self.tableView, key: "x")

    title = "Copy"
    if copyableCount > 0 {
      title += " \(copyableCount) \(Constants.String.keyBinding)s"
    }
    bdr.addItem(title, #selector(self.tableView.copy(_:)), target: self.tableView, key: "c")

    if !isPasteEnabled() {
      bdr.addItem("Paste", #selector(self.tableView.paste(_:)), target: self.tableView, key: "v")
    } else {
      // Paste is enabled if there are bindings in the clipboard, and doesn't matter if selected rows are editable
      var addedOne = false
      let pasteTitle = makePasteMenuItemTitle(itemCount: readBindingsFromClipboard().count)

      let firstSelectedIndex = (tableView.selectedRowIndexes.first ?? 0)
      if bindingStore.getClosestValidInsertIndex(from: firstSelectedIndex) <= firstSelectedIndex {
        bdr.addItem("\(pasteTitle) Above", #selector(self.pasteAbove(_:)), rowIndex: firstSelectedIndex)
        addedOne = true
      }

      let lastSelectedIndex = tableView.selectedRowIndexes.last ?? tableView.numberOfRows
      if !addedOne || bindingStore.getClosestValidInsertIndex(from: lastSelectedIndex, isAfterNotAt: true) >= lastSelectedIndex {
        bdr.addItem("\(pasteTitle) Below", #selector(self.pasteBelow(_:)), rowIndex: lastSelectedIndex, key: "v")
      }
    }

    // ---
    bdr.addSeparator()

    title = "Delete"
    if modifiableCount > 0 {
      title += " \(modifiableCount) \(Constants.String.keyBinding)s"
    }
    let item = bdr.addItem(title, #selector(self.tableView.delete(_:)), target: self.tableView, key: KeyCodeHelper.KeyEquivalents.BACKSPACE, keyMods: [])
  }

  private func makePasteMenuItemTitle(itemCount: Int, preferredInsertIndex: Int, referenceIndex: Int) -> String {
    let closestInsertIndexAfterSelection = bindingStore.getClosestValidInsertIndex(from: preferredInsertIndex)
    let direction = closestInsertIndexAfterSelection <= referenceIndex ? "Above" : "Below"
    return "\(makePasteMenuItemTitle(itemCount: itemCount)) \(direction)"
  }

  private func makePasteMenuItemTitle(itemCount: Int) -> String {
    return itemCount == 0 ? "Paste" : "Paste \(itemCount) \(Constants.String.keyBinding)\(itemCount == 1 ? "" : "s")"
  }

  @objc fileprivate func editKeyColumn(_ sender: BindingMenuItem) {
    edit(rowIndex: sender.rowIndex, columnIndex: COLUMN_INDEX_KEY)
  }

  @objc fileprivate func editActionColumn(_ sender: BindingMenuItem) {
    edit(rowIndex: sender.rowIndex, columnIndex: COLUMN_INDEX_ACTION)
  }

  @objc fileprivate func editRow(_ sender: BindingMenuItem) {
    edit(rowIndex: sender.rowIndex)
  }

  @objc fileprivate func addNewRowAbove(_ sender: BindingMenuItem) {
    editNewEmptyBinding(relativeTo: sender.rowIndex, isAfterNotAt: false)
  }

  @objc fileprivate func addNewRowBelow(_ sender: BindingMenuItem) {
    editNewEmptyBinding(relativeTo: sender.rowIndex, isAfterNotAt: true)
  }

  // Similar to Edit menu operations, but operating on a single non-selected row:
  @objc fileprivate func cutRow(_ sender: BindingMenuItem) {
    if copyToClipboard(rowsToCopy: [sender.row]) {
      bindingStore.removeBindings(at: IndexSet(integer: sender.rowIndex))
    }
  }

  @objc fileprivate func copyRow(_ sender: BindingMenuItem) {
    _ = copyToClipboard(rowsToCopy: [sender.row])
  }

  @objc fileprivate func pasteAbove(_ sender: BindingMenuItem) {
    pasteFromClipboard(relativeTo: sender.rowIndex, isAfterNotAt: false)
  }

  @objc fileprivate func pasteBelow(_ sender: BindingMenuItem) {
    pasteFromClipboard(relativeTo: sender.rowIndex, isAfterNotAt: true)
  }

  @objc fileprivate func removeRow(_ sender: BindingMenuItem) {
    bindingStore.removeBindings(at: IndexSet(integer: sender.rowIndex))
  }
}
