//
//  KeyBindingTableViewController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.03.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class KeyBindingTableViewController: NSObject {
  private let COLUMN_INDEX_KEY = 0
  private let COLUMN_INDEX_ACTION = 2
  private let DEFAULT_DRAG_OPERATION = NSDragOperation.move

  private unowned var tableView: EditableTableView!
  private var inputConfigTableStore: InputConfigTableStore {
    return (NSApp.delegate as! AppDelegate).inputConfigTableStore
  }

  private var bindingTableStore: ActiveBindingTableStore {
    return (NSApp.delegate as! AppDelegate).bindingTableStore
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
      // Enable drag & drop for MacOS 10.13+. Default to "move"
      tableView.registerForDraggedTypes([.string, .iinaActiveBinding])
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
    guard let alertInfo = notification.object as? AlertInfo else {
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

  /**
   Make cell view when asked
   */
  @objc func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let bindingRow = bindingTableStore.getBindingRow(at: row) else {
      return nil
    }

    guard let identifier = tableColumn?.identifier else { return nil }

    guard let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView else {
      return nil
    }
    let columnName = identifier.rawValue
    let binding = bindingRow.keyMapping

    switch columnName {
      case "keyColumn":
        let stringValue = isRaw ? binding.rawKey : binding.prettyKey
        setFormattedText(for: cell, to: stringValue, isEnabled: bindingRow.isEnabled)
        return cell

      case "actionColumn":
        let stringValue: String
        if bindingRow.origin == .iinaPlugin {
          // IINA plugins do not map directly to mpv commands
          stringValue = bindingRow.keyMapping.comment ?? ""
        } else {
          stringValue = isRaw ? binding.rawAction : binding.readableCommand
        }

        setFormattedText(for: cell, to: stringValue, isEnabled: bindingRow.isEnabled)

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
              case .libmpv:
                imageView.image = NSImage(systemSymbolName: "applescript.fill", accessibilityDescription: nil)!
              default:
                if bindingRow.isMenuItem {
                  imageView.image = NSImage(systemSymbolName: "filemenu.and.selection", accessibilityDescription: nil)!
                } else {
                  imageView.image = nil
                }
            }
            imageView.contentTintColor = NSColor.controlTextColor
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

  private func setFormattedText(for cell: NSTableCellView, to stringValue: String, isEnabled: Bool) {
    guard let textField = cell.textField else { return }

    let attrString = NSMutableAttributedString(string: stringValue)

    if isEnabled {
      textField.textColor = NSColor.controlTextColor
    } else {
      textField.textColor = NSColor.systemRed

      let strikethroughAttr = [NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.single.rawValue]
      attrString.addAttributes(strikethroughAttr, range: NSRange(location: 0, length: attrString.length))
    }
    textField.attributedStringValue = attrString
  }

  private var isRaw: Bool {
    return Preference.bool(for: .displayKeyBindingRawValues)
  }

  private var selectedRows: [ActiveBinding] {
    Array(tableView.selectedRowIndexes.compactMap( { bindingTableStore.getBindingRow(at: $0) }))
  }

  private var selectedEditableRows: [ActiveBinding] {
    self.selectedRows.filter({ $0.isEditableByUser })
  }
}

// MARK: NSTableViewDataSource

extension KeyBindingTableViewController: NSTableViewDataSource {
  /*
   Tell AppKit the number of rows when it asks
   */
  @objc func numberOfRows(in tableView: NSTableView) -> Int {
    return bindingTableStore.bindingRowCount
  }

  // MARK: Drag & Drop

  /*
   Drag start: convert tableview rows to clipboard items
   */
  @objc func tableView(_ tableView: NSTableView, pasteboardWriterForRow rowIndex: Int) -> NSPasteboardWriting? {
    return bindingTableStore.getBindingRow(at: rowIndex)
  }

  /*
   Applies when this table the drop target
   */
  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
    session.draggingFormation = .list
  }

  /**
   This is implemented to support dropping items onto the Trash icon in the Dock.
   TODO: look for a way to animate this so that it's more obvious that something happened.
   */
  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    guard inputConfigTableStore.isEditEnabledForCurrentConfig, operation == NSDragOperation.delete else {
      return
    }

    let rowList = ActiveBinding.deserializeList(from: session.draggingPasteboard)

    guard !rowList.isEmpty else {
      return
    }

    Logger.log("User dragged to the trash: \(rowList)", level: .verbose)

    rowList.forEach {
      if !$0.isEditableByUser {
        Logger.log("Ignoring drop: dragged list contains at least one row which is read-only: \(rowList)", level: .verbose)
        return
      }
    }

    bindingTableStore.removeBindings(withIDs: rowList.map{$0.keyMapping.bindingID!})
  }

  /*
   Validate drop while hovering.
   */
  @objc func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow rowIndex: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {

    guard inputConfigTableStore.isEditEnabledForCurrentConfig else {
      return []  // deny drop
    }

    let rowList = ActiveBinding.deserializeList(from: info.draggingPasteboard)

    guard !rowList.isEmpty else {
      return []  // deny drop
    }

    // Update that little red number:
    info.numberOfValidItemsForDrop = rowList.count
    info.draggingFormation = .list
    info.animatesToDestination = true

    // Cannot drop on/into existing rows. Change to below it:
    let isAfterNotAt = dropOperation == .on
    // Can only make changes to the "default" section. If the drop cursor is not already inside it,
    // then we'll change it to the nearest valid index in the "default" section.
    let dropTargetRow = bindingTableStore.getClosestValidInsertIndex(from: rowIndex, isAfterNotAt: isAfterNotAt)

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

    let rowList = ActiveBinding.deserializeList(from: info.draggingPasteboard)
    Logger.log("User dropped \(rowList.count) binding rows into table \(dropOperation == .on ? "on" : "above") rowIndex \(rowIndex)")
    guard !rowList.isEmpty else {
      return false
    }

    guard dropOperation == .above else {
      Logger.log("Expected dropOperaion==.above but got: \(dropOperation); aborting drop")
      return false
    }

    info.numberOfValidItemsForDrop = rowList.count
    info.draggingFormation = .list
    info.animatesToDestination = true

    var dragMask = info.draggingSourceOperationMask
    if dragMask == NSDragOperation.every {
      dragMask = DEFAULT_DRAG_OPERATION
    }

    // Return immediately, and import (or fail to) asynchronously
    DispatchQueue.main.async {
      switch dragMask {
        case .copy:
          self.copyBindingRows(from: rowList, to: rowIndex, isAfterNotAt: false)
        case .move:
          self.moveBindingRows(from: rowList, to: rowIndex, isAfterNotAt: false)
        default:
          Logger.log("Unexpected drag operatiom: \(dragMask)")
      }
    }
    return true
  }
}

// MARK: EditableTableViewDelegate

extension KeyBindingTableViewController: EditableTableViewDelegate {

  func userDidDoubleClickOnCell(row rowIndex: Int, column columnIndex: Int) -> Bool {
    guard requireCurrentConfigIsEditable(forAction: "edit cell") else { return false }

    guard bindingTableStore.isEditEnabledForBindingRow(rowIndex) else {
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

    guard bindingTableStore.isEditEnabledForBindingRow(rowIndex) else {
      Logger.log("Edit is not allowed for binding row \(rowIndex)", level: .verbose)
      return false
    }

    if isRaw {
      Logger.log("Opening in-line editor for row \(rowIndex)", level: .verbose)
      // Use in-line editor
      return true
    }

    editWithPopup(rowIndex: rowIndex)
    // Deny in-line editor from opening
    return false
  }

  func editDidEndWithNewText(newValue: String, row rowIndex: Int, column columnIndex: Int) -> Bool {
    guard bindingTableStore.isEditEnabledForBindingRow(rowIndex) else {
      // An error here would be really bad
      Logger.log("Cannot save binding row \(rowIndex): edit is not allowed for this row type! If you see this message please report it.", level: .error)
      return false
    }

    guard let editedRow = bindingTableStore.getBindingRow(at: rowIndex) else {
      Logger.log("userDidEndEditing(): failed to get row \(rowIndex) (newValue='\(newValue)')")
      return false
    }

    Logger.log("User finished editing value for row \(rowIndex), col \(columnIndex): \"\(newValue)\"", level: .verbose)

    let key, action: String?
    switch columnIndex {
      case COLUMN_INDEX_KEY:
        key = newValue
        action = nil
      case COLUMN_INDEX_ACTION:
        key = nil
        action = newValue
      default:
        Logger.log("userDidEndEditing(): bad column index: \(columnIndex)")
        return false
    }

    let newVersion = editedRow.keyMapping.clone(rawKey: key, rawAction: action)
    bindingTableStore.updateBinding(at: rowIndex, to: newVersion)
    return true
  }

  // MARK: Reusable actions

  // Edit either inline or with popup, depending on current mode
  private func edit(rowIndex: Int, columnIndex: Int = 0) {
    guard requireCurrentConfigIsEditable(forAction: "edit") else { return }

    Logger.log("Edit requested for row \(rowIndex), col \(columnIndex)")

    guard bindingTableStore.isEditEnabledForBindingRow(rowIndex) else {
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

    guard let row = bindingTableStore.getBindingRow(at: rowIndex) else {
      return
    }

    showEditBindingPopup(key: row.keyMapping.rawKey, action: row.keyMapping.readableAction) { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      let newVersion = row.keyMapping.clone(rawKey: key, rawAction: action)
      self.bindingTableStore.updateBinding(at: rowIndex, to: newVersion)
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
        if let tc = tableChange as? TableChangeByRowIndex {
          // We don't know beforehand exactly which row it will end up at, but we can get this info from the TableChange object
          if let insertedRowIndex = tc.toInsert?.first {
            self.tableView.editCell(row: insertedRowIndex, column: 0)
          }
        }
      }
      let newMapping = KeyMapping(rawKey: "", rawAction: "")
      let _ = bindingTableStore.insertNewBinding(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, newMapping, afterComplete: afterComplete)

    } else {
      showEditBindingPopup { key, action in
        guard !key.isEmpty && !action.isEmpty else { return }

        let newMapping = KeyMapping(rawKey: key, rawAction: action)
        self.bindingTableStore.insertNewBinding(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, newMapping,
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
  private func copyBindingRows(from rowList: [ActiveBinding], to rowIndex: Int, isAfterNotAt: Bool = false) {
    // Make sure to use copy() to clone the object here
    let newMappings: [KeyMapping] = rowList.map { $0.keyMapping.clone() }

    bindingTableStore.insertNewBindings(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, newMappings,
                                                                    afterComplete: scrollToFirstInserted)
  }

  // e.g., drag & drop "move" operation
  private func moveBindingRows(from rowList: [ActiveBinding], to rowIndex: Int, isAfterNotAt: Bool = false) {
    guard requireCurrentConfigIsEditable(forAction: "move binding(s)") else { return }

    let editableBindings: [KeyMapping] = rowList.filter { $0.isEditableByUser }.map { $0.keyMapping }
    guard !editableBindings.isEmpty else {
      Logger.log("Aborting move: none of the \(rowList.count) dragged bindings is editable")
      return
    }

    let firstInsertedRowIndex = bindingTableStore.moveBindings(editableBindings, to: rowIndex, isAfterNotAt: isAfterNotAt,
                                                               afterComplete: self.scrollToFirstInserted)
    self.tableView.scrollRowToVisible(firstInsertedRowIndex)
  }

  // Each TableUpdate executes asynchronously, but we need to wait for it to complete in order to do any further work on
  // inserted rows.
  private func scrollToFirstInserted(_ tableChange: TableChange) {
    if let tc = tableChange as? TableChangeByRowIndex {
      if let firstInsertedRowIndex = tc.toInsert?.first {
        self.tableView.scrollRowToVisible(firstInsertedRowIndex)
      }
    }
  }

  func removeSelectedBindings() {
    bindingTableStore.removeBindings(at: tableView.selectedRowIndexes)
  }

  private func requireCurrentConfigIsEditable(forAction action: String) -> Bool {
    if inputConfigTableStore.isEditEnabledForCurrentConfig {
      return true
    }

    // Should never see this ideally. If we do, something went wrong with UI enablement.
    Logger.log("Cannot \(action): cannot modify a default config. Telling user to duplicate the config instead", level: .verbose)
    Utility.showAlert("duplicate_config", sheetWindow: tableView.window)
    return false
  }

  // MARK: Cut, copy, paste, delete support.

  // Only selected table items which have `isEditableByUser==true` can be included.
  // Each menu item should be disabled if it cannot operate on at least one item.

  func isCopyEnabled() -> Bool {
    return inputConfigTableStore.isEditEnabledForCurrentConfig && !selectedEditableRows.isEmpty
  }

  func isCutEnabled() -> Bool {
    return isCopyEnabled()
  }

  func isDeleteEnabled() -> Bool {
    return isCopyEnabled()
  }

  func isPasteEnabled() -> Bool {
    return !readBindingsFromClipboard().isEmpty
  }

  func doEditMenuCut() {
    copyToClipboard()
    removeSelectedBindings()
  }

  func doEditMenuCopy() {
    copyToClipboard()
  }

  func doEditMenuPaste() {
    pasteFromClipboard()
  }

  func doEditMenuDelete() {
    removeSelectedBindings()
  }

  // If `rowsToCopy` is specified, copies it to the Clipboard.
  // If it is not specified, uses the currently selected rows
  private func copyToClipboard(rowsToCopy: [ActiveBinding]? = nil) {
    guard inputConfigTableStore.isEditEnabledForCurrentConfig else {
      return
    }
    let rows: [ActiveBinding]
    if let rowsToCopy = rowsToCopy {
      rows = rowsToCopy.filter({ $0.isEditableByUser })
    } else {
      rows = self.selectedEditableRows
    }

    if rows.isEmpty {
      Logger.log("No bindings to copy: not touching clipboard", level: .verbose)
      return
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(rows)
    Logger.log("Copied \(rows.count) bindings to the clipboard", level: .verbose)
  }

  // If desiredInsertIndex != nil, try to insert after it.
  // Else if there are selected rows, try to insert after them.
  // Else just use the end of the table.
  // `bindingTableStore` will then do a bunch of its own logic and probably end up putting it somewhere else.
  private func pasteFromClipboard(after desiredInsertIndex: Int? = nil) {
    let rowsToPaste = readBindingsFromClipboard()
    guard !rowsToPaste.isEmpty else {
      Logger.log("Aborting Paste action because there is nothing to paste", level: .warning)
      return
    }
    var insertAfterIndex: Int
    if let desiredInsertIndex = desiredInsertIndex {
      insertAfterIndex = desiredInsertIndex
    } else if let lastSelectedIndex = tableView.selectedRowIndexes.last {
      insertAfterIndex = lastSelectedIndex
    } else {
      insertAfterIndex = bindingTableStore.bindingRowCount
    }
    let mappingsToInsert = rowsToPaste.map { $0.keyMapping }
    Logger.log("Pasting \(mappingsToInsert.count) bindings after index \(insertAfterIndex)")
    bindingTableStore.insertNewBindings(relativeTo: insertAfterIndex, isAfterNotAt: true, mappingsToInsert,
                                        afterComplete: self.scrollToFirstInserted)
  }

  private func readBindingsFromClipboard() -> [ActiveBinding] {
    return ActiveBinding.deserializeList(from: NSPasteboard.general)
  }
}

// MARK: NSMenuDelegate

extension KeyBindingTableViewController: NSMenuDelegate {

  fileprivate class BindingMenuItem: NSMenuItem {
    let row: ActiveBinding
    let rowIndex: Int

    public init(_ row: ActiveBinding, rowIndex: Int, title: String, action selector: Selector?, target: AnyObject?, enabled: Bool = true) {
      self.row = row
      self.rowIndex = rowIndex
      super.init(title: title, action: selector, keyEquivalent: "")
      self.target = target
      self.isEnabled = enabled
    }

    required init(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  private func addItem(to menu: NSMenu, for row: ActiveBinding, withIndex rowIndex: Int, title: String, action: Selector?, target: AnyObject? = nil, enabled: Bool = true) {
    let finalTarget: AnyObject
    if let target = target {
      finalTarget = target
    } else {
      finalTarget = self
    }
    menu.addItem(BindingMenuItem(row, rowIndex: rowIndex, title: title, action: action, target: finalTarget, enabled: enabled))
  }

  private func addItalicDisabledItem(to menu: NSMenu, for row: ActiveBinding, withIndex rowIndex: Int, title: String) {
    let attrTitle = NSMutableAttributedString(string: title)
    // FIXME: make italic
//        let font = NSFont.systemFont(ofSize: 12)
//        attrTitle.addAttribute(NSAttributedString.Key.font, value: font, range: NSRange(location: 0, length: attrTitle.length))
    let item = BindingMenuItem(row, rowIndex: rowIndex, title: title, action: nil, target: self)
    item.attributedTitle = attrTitle
    item.isEnabled = false
    menu.addItem(item)
  }

  func menuNeedsUpdate(_ contextMenu: NSMenu) {
    // This will prevent menu from showing if no items are added
    contextMenu.removeAllItems()

    let clickedIndex = tableView.clickedRow
    guard let clickedRow = bindingTableStore.getBindingRow(at: tableView.clickedRow) else { return }

    guard inputConfigTableStore.isEditEnabledForCurrentConfig else {
      let title = "Cannot make changes: \"\(inputConfigTableStore.currentConfigName)\" is a default config"
      addItalicDisabledItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: title)
      return
    }

    if tableView.selectedRowIndexes.count > 1 && tableView.selectedRowIndexes.contains(clickedIndex) {
      populate(contextMenu: contextMenu, for: tableView.selectedRowIndexes, clickedIndex: clickedIndex, clickedRow: clickedRow)
    } else {
      populate(contextMenu: contextMenu, for: clickedRow, clickedIndex: clickedIndex)
    }
  }

  // For right-click on a single row which is not currently selected.
  private func populate(contextMenu: NSMenu, for clickedRow: ActiveBinding, clickedIndex: Int) {
    let isRowEditable = clickedRow.isEditableByUser
    if isRowEditable {
      // Edit
      if isRaw {
        addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Edit Key", action: #selector(self.editKeyColumn(_:)))
        addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Edit Action", action: #selector(self.editActionColumn(_:)))
      } else {
        addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Edit Row...", action: #selector(self.editRow(_:)))
      }
    } else {
      let culprit: String
      switch clickedRow.origin {
        case .iinaPlugin:
          culprit = "the IINA plugin \"\(clickedRow.srcSectionName)\""
        case .libmpv:
          culprit = "a Lua script or other mpv interface"
        default:
          Logger.log("Unrecognized binding origin for rowIndex \(clickedIndex): \(clickedRow.origin)", level: .error)
          culprit = "<unknown>"
      }
      let title = "Cannot modify row: \"\(inputConfigTableStore.currentConfigName)\" it was set by \(culprit)"
      addItalicDisabledItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: title)
    }

    // ---
    contextMenu.addItem(NSMenuItem.separator())

    // Cut, Copy, Paste, Delete
    addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Cut", action: #selector(self.cutRow(_:)), enabled: isRowEditable)
    addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Copy", action: #selector(self.copyRow(_:)), enabled: isRowEditable)
    let pastableBindings = readBindingsFromClipboard()
    let pasteTitle = makePasteMenuItemTitle(itemCount: pastableBindings.count)
    addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: pasteTitle, action: #selector(self.pasteAfterIndex(_:)), enabled: !pastableBindings.isEmpty)
    addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Delete", action: #selector(self.removeRow(_:)), enabled: isRowEditable)

    // ---
    contextMenu.addItem(NSMenuItem.separator())

    // Add
    addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Add New \(Constants.String.keyBinding) Above", action: #selector(self.addNewRowAbove(_:)))
    addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Add New \(Constants.String.keyBinding) Below", action: #selector(self.addNewRowBelow(_:)))

  }

  // For right-click on selected row(s)
  private func populate(contextMenu: NSMenu, for selectedRowIndexes: IndexSet, clickedIndex: Int, clickedRow: ActiveBinding) {
    let selectedRowsCount = tableView.selectedRowIndexes.count

    let readOnlyCount = tableView.selectedRowIndexes.reduce(0) { readOnlyCount, rowIndex in
      return !bindingTableStore.isEditEnabledForBindingRow(rowIndex) ? readOnlyCount + 1 : readOnlyCount
    }
    let modifiableCount = selectedRowsCount - readOnlyCount

    if readOnlyCount > 0 {
      let readOnlyDisclaimer: String

      if readOnlyCount == selectedRowsCount {
        readOnlyDisclaimer = "\(readOnlyCount) items are read-only"
      } else {
        readOnlyDisclaimer = "\(readOnlyCount) of \(selectedRowsCount) items are read-only"
      }
      addItalicDisabledItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: readOnlyDisclaimer)
    }

    // Cut, Copy, Paste, Delete
    if modifiableCount > 0 {
      // By setting the target to `tableView`, AppKit will know to call its `validateUserInterfaceItem()`
      // and will enable/disable each action appropriately
      addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Cut \(modifiableCount) \(Constants.String.keyBinding)s", action: #selector(self.tableView.cut(_:)), target: self.tableView)
      addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Copy \(modifiableCount) \(Constants.String.keyBinding)s", action: #selector(self.tableView.copy(_:)), target: self.tableView)
      let pastableBindings = readBindingsFromClipboard()
      let pasteTitle = makePasteMenuItemTitle(itemCount: pastableBindings.count)
      addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: pasteTitle, action: #selector(self.tableView.paste(_:)), target: self.tableView)
      addItem(to: contextMenu, for: clickedRow, withIndex: clickedIndex, title: "Delete \(modifiableCount) \(Constants.String.keyBinding)s", action: #selector(self.tableView.delete(_:)), target: self.tableView)
    }
  }

  private func makePasteMenuItemTitle(itemCount: Int) -> String {
    itemCount == 0 ? "Paste" : "Paste \(itemCount) \(Constants.String.keyBinding)s"
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
    copyToClipboard(rowsToCopy: [sender.row])
    bindingTableStore.removeBindings(at: IndexSet(integer: sender.rowIndex))
  }

  @objc fileprivate func copyRow(_ sender: BindingMenuItem) {
    copyToClipboard(rowsToCopy: [sender.row])
  }

  @objc fileprivate func pasteAfterIndex(_ sender: BindingMenuItem) {
    pasteFromClipboard(after: sender.rowIndex)
  }

  @objc fileprivate func removeRow(_ sender: BindingMenuItem) {
    bindingTableStore.removeBindings(at: IndexSet(integer: sender.rowIndex))
  }
}
