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

  private var confTableState: ConfTableState {
    return ConfTableState.current
  }

  private var bindingTableState: BindingTableState {
    return BindingTableState.current
  }

  private var confTableController: InputConfTableViewController? = nil
  private var kbTableController: BindingTableViewController? = nil

  // Need to store these somewhere which isn't only inside a struct.
  // Swift will see them as zero refs!
  private let bindingTableStateManger = BindingTableState.manager
  private let confTableStateManager = ConfTableState.manager

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
  @IBOutlet weak var duplicateConfBtn: NSButton!
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

    // Apparently, Swift is feeling very lazy about loading `BindingTableViewController`.
    // The reference above is not enough to call its constructor.
    // But we need it to start now. Need to be proactive.
    self.bindingTableStateManger.wakeUp()

    let kbTableController = BindingTableViewController(kbTableView, selectionDidChangeHandler: updateRemoveButtonEnablement)
    self.kbTableController = kbTableController
    confTableController = InputConfTableViewController(inputConfigTableView, kbTableController)

    if #available(macOS 10.13, *) {
      useMediaKeysButton.title = NSLocalizedString("preference.system_media_control", comment: "Use system media control")
    }

    observers.append(NotificationCenter.default.addObserver(forName: .iinaConfTableShouldChange, object: nil, queue: .main) { _ in
      self.updateEditEnabledStatus()
    })

    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingSearchFieldShouldUpdate, object: nil, queue: .main) { notification in
      guard let newStringValue = notification.object as? String else {
        Logger.log("\(notification.name): invalid object: \(type(of: notification.object))", level: .error)
        return
      }
      self.keyMappingSearchField.stringValue = newStringValue
    })

    confTableController?.selectCurrentConfRow()
    self.updateEditEnabledStatus()
  }

  // MARK: - IBActions

  @IBAction func addKeyMappingBtnAction(_ sender: AnyObject) {
    kbTableController?.addNewBinding()
  }

  @IBAction func removeKeyMappingBtnAction(_ sender: AnyObject) {
    kbTableController?.removeSelectedBindings()
  }

  @IBAction func newConfFileAction(_ sender: AnyObject) {
    confTableController?.createNewConf()
  }

  @IBAction func duplicateConfFileAction(_ sender: AnyObject) {
    confTableController?.duplicateConf(confTableState.selectedConfName)
  }

  @IBAction func showConfFileAction(_ sender: AnyObject) {
    confTableController?.showInFinder(confTableState.selectedConfName)
  }

  @IBAction func deleteConfFileAction(_ sender: AnyObject) {
    confTableController?.deleteConf(confTableState.selectedConfName)
  }

  @IBAction func importConfBtnAction(_ sender: Any) {
    Utility.quickOpenPanel(title: "Select Config File to Import", chooseDir: false, sheetWindow: view.window, allowedFileTypes: [AppData.confFileExtension]) { url in
      guard url.isFileURL, url.lastPathComponent.hasSuffix(AppData.confFileExtension) else { return }
      self.confTableController?.importConfFiles([url.lastPathComponent])
    }
  }

  @IBAction func displayRawValueAction(_ sender: NSButton) {
    kbTableView.reloadExistingRows()
  }

  @IBAction func openKeyBindingsHelpAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink.appending("/Manage-Key-Bindings"))!)
  }

  @IBAction func searchAction(_ sender: NSSearchField) {
    bindingTableState.filterBindings(sender.stringValue)
  }

  // MARK: - UI

  private func updateEditEnabledStatus() {
    let isSelectedConfReadOnly = confTableState.isSelectedConfReadOnly
    [showConfFileBtn, deleteConfFileBtn, addKmBtn].forEach { btn in
      btn.isEnabled = !isSelectedConfReadOnly
    }
    configHintLabel.stringValue = NSLocalizedString("preference.key_binding_hint_\(isSelectedConfReadOnly ? "1" : "2")", comment: "preference.key_binding_hint")

    self.updateRemoveButtonEnablement()
  }

  private func updateRemoveButtonEnablement() {
    // re-evaluate this each time either table changed selection:
    removeKmBtn.isEnabled = !confTableState.isSelectedConfReadOnly && kbTableView.selectedRow != -1
  }
}
