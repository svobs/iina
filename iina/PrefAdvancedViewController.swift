//
//  PrefAdvancedViewController.swift
//  iina
//
//  Created by lhc on 14/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

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
    return makeSymbol("flask", fallbackName: "pref_advanced")
  }

  var preferenceContentIsScrollable: Bool {
    return false
  }

  var hasResizableWidth: Bool = false

  var options: [[String]] = []

  override var sectionViews: [NSView] {
    return [headerView, loggingSettingsView, mpvSettingsView]
  }

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

    guard let op = Preference.value(for: .userOptions) as? [[String]] else {
      Utility.showAlert("extra_option.cannot_read", sheetWindow: view.window)
      return
    }
    options = op

    optionsTableView.dataSource = self
    optionsTableView.delegate = self
    optionsTableView.editableDelegate = self
    optionsTableView.sizeLastColumnToFit()
    optionsTableView.editableTextColumnIndexes = [0, 1]
    refreshRemoveButton()
    
    enableAdvancedSettingsLabel.stringValue = NSLocalizedString("preference.enable_adv_settings", comment: "Enable advanced settings")
  }

  func saveToUserDefaults() {
    Preference.set(options, for: .userOptions)
    UserDefaults.standard.synchronize()
  }

  // MARK: - IBAction

  @IBAction func openLogDir(_ sender: AnyObject) {
    NSWorkspace.shared.open(Logger.logDirectory)
  }
  
  @IBAction func showLogWindow(_ sender: AnyObject) {
    AppDelegate.shared.logWindow.showWindow(self)
  }

  @IBAction func addOptionBtnAction(_ sender: AnyObject) {
    options.append(["name", "value"])
    optionsTableView.reloadData()
    optionsTableView.selectRowIndexes(IndexSet(integer: options.count - 1), byExtendingSelection: false)
    saveToUserDefaults()
  }

  @IBAction func removeOptionBtnAction(_ sender: AnyObject) {
    if optionsTableView.selectedRow >= 0 {
      options.remove(at: optionsTableView.selectedRow)
      optionsTableView.reloadData()
      refreshRemoveButton()
      saveToUserDefaults()
    }
  }

  @IBAction func chooseDirBtnAction(_ sender: AnyObject) {
    Utility.quickOpenPanel(title: "Choose config directory", chooseDir: true, sheetWindow: view.window) { url in
      Preference.set(url.path, for: .userDefinedConfDir)
      UserDefaults.standard.synchronize()
    }
  }

  @IBAction func helpBtnAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink)!.appendingPathComponent("MPV-Options-and-Properties"))
  }
}

extension PrefAdvancedViewController: NSTableViewDelegate, NSTableViewDataSource, NSControlTextEditingDelegate {

  func controlTextDidEndEditing(_ obj: Notification) {
    saveToUserDefaults()
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return options.count
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

    guard row < options.count else {
      return nil
    }

    switch columnName {
    case "Key":
      setFormattedText(for: cell, to: options[row][0], isEnabled: tableView.isEnabled)
      return cell

    case "Value":
      setFormattedText(for: cell, to: options[row][1], isEnabled: tableView.isEnabled)
      return cell

    default:
      Logger.log("Unrecognized column: '\(columnName)'", level: .error)
      return nil
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    if optionsTableView.selectedRowIndexes.count == 0 {
      optionsTableView.reloadData()
    }
    refreshRemoveButton()
  }

  private func refreshRemoveButton() {
    removeButton.isHidden = optionsTableView.selectedRowIndexes.isEmpty
  }

  private func setFormattedText(for cell: NSTableCellView, to stringValue: String, isEnabled: Bool) {
    guard let textField = cell.textField else { return }
    textField.setFormattedText(stringValue: stringValue, textColor: isEnabled ? .controlTextColor : .disabledControlTextColor)
  }
}

extension PrefAdvancedViewController: EditableTableViewDelegate {
  func userDidDoubleClickOnCell(row rowIndex: Int, column columnIndex: Int) -> Bool {
    Logger.log("Double-click: Edit requested for row \(rowIndex), col \(columnIndex)")
    optionsTableView.editCell(row: rowIndex, column: columnIndex)
    return true
  }

  func userDidPressEnterOnRow(_ rowIndex: Int) -> Bool {
    Logger.log("Enter key: Edit requested for row \(rowIndex)")
    optionsTableView.editCell(row: rowIndex, column: 0)
    return true
  }

  func editDidEndWithNewText(newValue: String, row rowIndex: Int, column columnIndex: Int) -> Bool {
    Logger.log("User finished editing value for row \(rowIndex), col \(columnIndex): \(newValue.quoted)", level: .verbose)
    guard rowIndex < options.count else {
      return false
    }

    var rowValues = options[rowIndex]

    guard columnIndex < rowValues.count else {
      Logger.log("userDidEndEditing(): bad column index: \(columnIndex)")
      return false
    }

    rowValues[columnIndex] = newValue
    options[rowIndex] = rowValues
    saveToUserDefaults()
    return true
  }
}
