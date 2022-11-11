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

  private var configStore: InputConfigStore {
    return AppInputConfig.inputConfigStore
  }

  private var bindingStore: InputBindingStore {
    return AppInputConfig.inputBindingStore
  }

  private var configTableController: InputConfigTableViewController? = nil
  private var kbTableController: KeyBindingTableViewController? = nil

  private var observers: [NSObjectProtocol] = []

  // MARK: - Outlets

  @IBOutlet weak var inputConfigTableView: EditableTableView!
  @IBOutlet weak var kbTableView: EditableTableView!
  @IBOutlet weak var configHintLabel: NSTextField!
  @IBOutlet weak var addKmBtn: NSButton!
  @IBOutlet weak var removeKmBtn: NSButton!
  @IBOutlet weak var showConfFileBtn: NSButton!
  @IBOutlet weak var deleteConfFileBtn: NSButton!
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

    let kbTableController = KeyBindingTableViewController(kbTableView, selectionDidChangeHandler: updateRemoveButtonEnablement)
    self.kbTableController = kbTableController
    configTableController = InputConfigTableViewController(inputConfigTableView, configStore, kbTableController)

    if #available(macOS 10.13, *) {
      useMediaKeysButton.title = NSLocalizedString("preference.system_media_control", comment: "Use system media control")
    }

    observers.append(NotificationCenter.default.addObserver(forName: .iinaInputConfigTableShouldUpdate, object: nil, queue: .main) { _ in
      self.updateEditEnabledStatus()
    })

    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingSearchFieldShouldUpdate, object: nil, queue: .main) { notification in
      guard let newStringValue = notification.object as? String else {
        Logger.log("iinaKeyBindingSearchFieldShouldUpdate: invalid object: \(type(of: notification.object))", level: .error)
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
    configTableController?.createNewConfig()
  }

  @IBAction func duplicateConfigFileAction(_ sender: AnyObject) {
    configTableController?.duplicateConfig(configStore.currentConfigName)
  }

  @IBAction func showConfFileAction(_ sender: AnyObject) {
    configTableController?.showInFinder(configStore.currentConfigName)
  }

  @IBAction func deleteConfFileAction(_ sender: AnyObject) {
    configTableController?.deleteConfig(configStore.currentConfigName)
  }

  @IBAction func importConfigBtnAction(_ sender: Any) {
    Utility.quickOpenPanel(title: "Select Config File to Import", chooseDir: false, sheetWindow: view.window, allowedFileTypes: [AppData.configFileExtension]) { url in
      guard url.isFileURL, url.lastPathComponent.hasSuffix(AppData.configFileExtension) else { return }
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
    bindingStore.filterBindings(sender.stringValue)
  }

  // MARK: - UI

  private func updateEditEnabledStatus() {
    let isEditEnabledForCurrentConfig = configStore.isEditEnabledForCurrentConfig
    [showConfFileBtn, deleteConfFileBtn, addKmBtn].forEach { btn in
      btn.isEnabled = isEditEnabledForCurrentConfig
    }
    configHintLabel.stringValue = NSLocalizedString("preference.key_binding_hint_\(isEditEnabledForCurrentConfig ? "2" : "1")", comment: "preference.key_binding_hint")

    self.updateRemoveButtonEnablement()
  }

  private func updateRemoveButtonEnablement() {
    // re-evaluate this each time either table changed selection:
    removeKmBtn.isEnabled = configStore.isEditEnabledForCurrentConfig && kbTableView.selectedRow != -1
  }
}
