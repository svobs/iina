//
//  PrefKeyBindingViewController.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefKeyBindingViewController: NSViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefKeyBindingViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.keybindings", comment: "Keybindings")
  }

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_kb"))!
  }

  var preferenceContentIsScrollable: Bool {
    return false
  }

  // This is referenced outside of keybindings code:
  static var defaultConfigs: [String: String] {
    get {
      InputConfDataStore.defaultConfigs
    }
  }

  private var configDS = InputConfDataStore()

  private var confTableViewController: InputConfTableViewController? = nil
  private var keyBindingsTableController: KeyBindingsTableViewController? = nil

  var shouldEnableEdit: Bool = true

  // MARK: - Outlets

  @IBOutlet weak var confTableView: DoubleClickEditTableView!
  @IBOutlet weak var kbTableView: DoubleClickEditTableView!
  @IBOutlet weak var configHintLabel: NSTextField!
  @IBOutlet weak var addKmBtn: NSButton!
  @IBOutlet weak var removeKmBtn: NSButton!
  @IBOutlet weak var revealConfFileBtn: NSButton!
  @IBOutlet weak var deleteConfFileBtn: NSButton!
  @IBOutlet weak var newConfigBtn: NSButton!
  @IBOutlet weak var duplicateConfigBtn: NSButton!
  @IBOutlet weak var useMediaKeysButton: NSButton!
  @IBOutlet weak var keyMappingSearchField: NSSearchField!
  @IBOutlet var mappingController: NSArrayController!

  override func viewDidLoad() {
    super.viewDidLoad()

    keyBindingsTableController = KeyBindingsTableViewController(self)
    kbTableView.delegate = keyBindingsTableController
    confTableView.delegate = keyBindingsTableController

    confTableViewController = InputConfTableViewController(confTableView, self.configDS)
    confTableView.dataSource = confTableViewController
    confTableView.delegate = confTableViewController

    removeKmBtn.isEnabled = false

    if #available(macOS 10.13, *) {
      useMediaKeysButton.title = NSLocalizedString("preference.system_media_control", comment: "Use system media control")
    }

    NotificationCenter.default.addObserver(forName: .iinaKeyBindingChanged, object: nil, queue: .main, using: saveToCurrentConfFile)
    NotificationCenter.default.addObserver(forName: .iinaCurrentInputConfChanged, object: nil, queue: .main) { _ in
      self.loadConfigFile()
    }

    confTableViewController?.selectCurrentInputRow()
    self.loadConfigFile()
  }

  // MARK: - IBActions

  func showKeyBindingPanel(key: String = "", action: String = "", ok: @escaping (String, String) -> Void) {
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
    panel.beginSheetModal(for: view.window!) { respond in
      if respond == .alertFirstButtonReturn {
        ok(keyRecordViewController.keyCode, keyRecordViewController.action)
      }
    }
  }

  @IBAction func addKeyMappingBtnAction(_ sender: AnyObject) {
    showKeyBindingPanel { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      if action.hasPrefix("@iina") {
        let trimmedAction = action[action.index(action.startIndex, offsetBy: "@iina".count)...].trimmingCharacters(in: .whitespaces)
        self.mappingController.addObject(KeyMapping(rawKey: key,
                                        rawAction: trimmedAction,
                                        isIINACommand: true))
      } else {
        self.mappingController.addObject(KeyMapping(rawKey: key, rawAction: action))
      }

      self.kbTableView.scrollRowToVisible((self.mappingController.arrangedObjects as! [AnyObject]).count - 1)
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
    }
  }

  @IBAction func removeKeyMappingBtnAction(_ sender: AnyObject) {
    mappingController.remove(sender)
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
  }

  @IBAction func newConfFileAction(_ sender: AnyObject) {
    // prompt
    Utility.quickPromptPanel("config.new", sheetWindow: view.window) { newName in
      guard !newName.isEmpty else {
        Utility.showAlert("config.empty_name", sheetWindow: self.view.window)
        return
      }

      self.confTableViewController!.makeNewConfFile(newName, doAction: { (newFilePath: String) in
        // - new file
        if !FileManager.default.createFile(atPath: newFilePath, contents: nil, attributes: nil) {
          Utility.showAlert("config.cannot_create", sheetWindow: self.view.window)
          return false
        }
        return true
      })
    }
  }

  @IBAction func duplicateConfFileAction(_ sender: AnyObject) {
    confTableViewController?.duplicateConfig(configDS.currentConfName)
  }

  @IBAction func revealConfFileAction(_ sender: AnyObject) {
    confTableViewController?.revealConfig(configDS.currentConfName)
  }

  @IBAction func deleteConfFileAction(_ sender: AnyObject) {
    confTableViewController?.deleteConfig(configDS.currentConfName)
  }

  @IBAction func importConfigBtnAction(_ sender: Any) {
    Utility.quickOpenPanel(title: "Select Config File to Import", chooseDir: false, sheetWindow: view.window, allowedFileTypes: ["conf"]) { url in
      guard url.isFileURL, url.lastPathComponent.hasSuffix(".conf") else { return }
      let newFilePath = Utility.userInputConfDirURL.appendingPathComponent(url.lastPathComponent).path
      let newName = url.deletingPathExtension().lastPathComponent
      // copy file
      do {
        try FileManager.default.copyItem(atPath: url.path, toPath: newFilePath)
      } catch let error {
        Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.view.window)
        return
      }
      // update prefs & refresh UI
      self.configDS.addUserConfig(name: newName, filePath: newFilePath)
    }
  }

  @IBAction func displayRawValueAction(_ sender: NSButton) {
    kbTableView.reloadData()
  }

  @IBAction func openKeyBindingsHelpAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink.appending("/Manage-Key-Bindings"))!)
  }

  // MARK: - UI

  private func saveToCurrentConfFile(_ sender: Notification) {
    guard let confFilePath = requireCurrentFilePath() else {
      return
    }
    let predicate = mappingController.filterPredicate
    mappingController.filterPredicate = nil
    guard let keyBindingList = mappingController.arrangedObjects as? [KeyMapping] else {
      return
    }
    setKeybindingsForPlayerCore(keyBindingList)
    mappingController.filterPredicate = predicate
    do {
      try KeyMapping.generateInputConf(from: keyBindingList).write(toFile: confFilePath, atomically: true, encoding: .utf8)
    } catch {
      Utility.showAlert("config.cannot_write", sheetWindow: view.window)
    }
  }

  private func loadConfigFile() {
    guard let confFilePath = configDS.currentConfFilePath else {
      return
    }
    Logger.log("Loading key bindings config from \"\(confFilePath)\"")
    guard let keyBindingList = KeyMapping.parseInputConf(at: confFilePath) else {
      // on error
      Logger.log("Error loading key bindings config from \"\(confFilePath)\"", level: .error)
      let fileName = URL(fileURLWithPath: confFilePath).lastPathComponent
      Utility.showAlert("keybinding_config.error", arguments: [fileName], sheetWindow: view.window)
      configDS.changeCurrentConfig(0)
      return
    }

    mappingController.content = nil
    mappingController.add(contentsOf: keyBindingList)
    mappingController.setSelectionIndexes(IndexSet())

    setKeybindingsForPlayerCore(keyBindingList)
    updateEditEnabledStatus()
  }

  private func updateEditEnabledStatus() {
    shouldEnableEdit = !self.configDS.isDefaultConfig(configDS.currentConfName)
    [revealConfFileBtn, deleteConfFileBtn, addKmBtn].forEach { btn in
      btn.isEnabled = shouldEnableEdit
    }
    kbTableView.tableColumns.forEach { $0.isEditable = shouldEnableEdit }
    configHintLabel.stringValue = NSLocalizedString("preference.key_binding_hint_\(shouldEnableEdit ? "2" : "1")", comment: "preference.key_binding_hint")
  }

  // TODO: change this to a notification
  func updateRemoveButtonEnablement() {
    // re-evaluate this each time either table changed selection:
    removeKmBtn.isEnabled = shouldEnableEdit && kbTableView.selectedRow != -1
  }

  private func setKeybindingsForPlayerCore(_ keyBindingList: [KeyMapping]) {
    PlayerCore.setKeyBindings(keyBindingList)
  }

  private func tellUserToDuplicateConfig() {
    Utility.showAlert("duplicate_config", sheetWindow: view.window)
  }

  private func requireCurrentFilePath() -> String? {
    if let confFilePath = configDS.currentConfFilePath {
      return confFilePath
    }

    Utility.showAlert("error_finding_file", arguments: ["config"], sheetWindow: view.window)
    return nil
  }

  @objc func doubleClickedKBTable() {
    // Disabled for "raw values"
    guard !Preference.bool(for: .displayKeyBindingRawValues) else {
      return
    }

    guard shouldEnableEdit else {
      tellUserToDuplicateConfig()
      return
    }
    guard kbTableView.selectedRow != -1 else { return }
    let selectedData = mappingController.selectedObjects[0] as! KeyMapping
    showKeyBindingPanel(key: selectedData.rawKey, action: selectedData.readableAction) { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      selectedData.rawKey = key
      selectedData.rawAction = action
      self.kbTableView.reloadData()
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
    }
  }

}
