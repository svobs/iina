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
      InputConfigDataStore.defaultConfigs
    }
  }

  private var observers: [NSObjectProtocol] = []

  private var ds = InputConfigDataStore()

  private var configTableController: InputConfigTableViewController? = nil
  private var kbTableController: KeyBindingsTableViewController? = nil

  // MARK: - Outlets

  @IBOutlet weak var inputConfigTableView: DoubleClickEditTableView!
  @IBOutlet weak var kbTableView: DoubleClickEditTableView!
  @IBOutlet weak var configHintLabel: NSTextField!
  @IBOutlet weak var addKmBtn: NSButton!
  @IBOutlet weak var removeKmBtn: NSButton!
  @IBOutlet weak var revealConfigFileBtn: NSButton!
  @IBOutlet weak var deleteConfigFileBtn: NSButton!
  @IBOutlet weak var newConfigBtn: NSButton!
  @IBOutlet weak var duplicateConfigBtn: NSButton!
  @IBOutlet weak var useMediaKeysButton: NSButton!
  @IBOutlet weak var keyMappingSearchField: NSSearchField!

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    kbTableController = KeyBindingsTableViewController(kbTableView, ds, selectionDidChangeHandler: updateRemoveButtonEnablement)
    kbTableView.dataSource = kbTableController
    kbTableView.delegate = kbTableController

    configTableController = InputConfigTableViewController(inputConfigTableView, ds)
    inputConfigTableView.dataSource = configTableController
    inputConfigTableView.delegate = configTableController

    if #available(macOS 10.13, *) {
      useMediaKeysButton.title = NSLocalizedString("preference.system_media_control", comment: "Use system media control")
    }

    observers.append(NotificationCenter.default.addObserver(forName: .iinaInputConfigListDidChange, object: nil, queue: .main) { _ in
      self.updateEditEnabledStatus()
    })

    observers.append(NotificationCenter.default.addObserver(forName: .iinaUpdateKeyBindingSearchField, object: nil, queue: .main) { notification in
      guard let newStringValue = notification.object as? String else {
        Logger.log("iinaUpdateKeyBindingSearchField: invalid object: \(type(of: notification.object))", level: .error)
        return
      }
      self.keyMappingSearchField.stringValue = newStringValue
    })

    configTableController?.selectCurrentConfigRow()
    self.updateEditEnabledStatus()
  }

  // MARK: - IBActions

  @IBAction func addKeyMappingBtnAction(_ sender: AnyObject) {
    kbTableController?.addNewBinding()
  }

  @IBAction func removeKeyMappingBtnAction(_ sender: AnyObject) {
    kbTableController?.removeSelectedBindings()
  }

  @IBAction func newConfigFileAction(_ sender: AnyObject) {
    // prompt
    Utility.quickPromptPanel("config.new", sheetWindow: view.window) { newName in
      guard !newName.isEmpty else {
        Utility.showAlert("config.empty_name", sheetWindow: self.view.window)
        return
      }

      self.configTableController!.makeNewConfFile(newName, doAction: { (newFilePath: String) in
        // - new file
        if !FileManager.default.createFile(atPath: newFilePath, contents: nil, attributes: nil) {
          Utility.showAlert("config.cannot_create", sheetWindow: self.view.window)
          return false
        }
        return true
      })
    }
  }

  @IBAction func duplicateConfigFileAction(_ sender: AnyObject) {
    configTableController?.duplicateConfig(ds.currentConfigName)
  }

  @IBAction func revealConfigFileAction(_ sender: AnyObject) {
    configTableController?.revealConfig(ds.currentConfigName)
  }

  @IBAction func deleteConfigFileAction(_ sender: AnyObject) {
    configTableController?.deleteConfig(ds.currentConfigName)
  }

  @IBAction func importConfigBtnAction(_ sender: Any) {
    Utility.quickOpenPanel(title: "Select Config File to Import", chooseDir: false, sheetWindow: view.window, allowedFileTypes: [InputConfigDataStore.CONFIG_FILE_EXTENSION]) { url in
      guard url.isFileURL, url.lastPathComponent.hasSuffix(InputConfigDataStore.CONFIG_FILE_EXTENSION) else { return }
      self.configTableController?.importConfigFiles([url.lastPathComponent])
    }
  }

  @IBAction func displayRawValueAction(_ sender: NSButton) {
    kbTableView.reloadExistingRows()
  }

  @IBAction func openKeyBindingsHelpAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink.appending("/Manage-Key-Bindings"))!)
  }

  @IBAction func searchAction(_ sender: NSSearchField) {
    ds.filterBindings(sender.stringValue)
  }

  // MARK: - UI

  private func updateEditEnabledStatus() {
    let isEditEnabledForCurrentConfig = ds.isEditEnabledForCurrentConfig()
    [revealConfigFileBtn, deleteConfigFileBtn, addKmBtn].forEach { btn in
      btn.isEnabled = isEditEnabledForCurrentConfig
    }
    configHintLabel.stringValue = NSLocalizedString("preference.key_binding_hint_\(isEditEnabledForCurrentConfig ? "2" : "1")", comment: "preference.key_binding_hint")

    self.updateRemoveButtonEnablement()
  }

  private func updateRemoveButtonEnablement() {
    // re-evaluate this each time either table changed selection:
    removeKmBtn.isEnabled = ds.isEditEnabledForCurrentConfig() && kbTableView.selectedRow != -1
  }
}
