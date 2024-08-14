//
//  PrefKeyBindingViewController.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let fm = FileManager.default
fileprivate typealias KC = PrefKeyBindingViewController

@objcMembers
class PrefKeyBindingViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefKeyBindingViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.keybindings", comment: "Keybindings")
  }

  var preferenceTabImage: NSImage {
    return makeSymbol("keyboard.badge.ellipsis", fallbackImage: "pref_kb")
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

  private var confTableController: ConfTableViewController? = nil
  private var bindingTableController: BindingTableViewController? = nil

  private var observers: [NSObjectProtocol] = []

  // MARK: - Outlets

  @IBOutlet weak var confTableView: EditableTableView!
  @IBOutlet weak var bindingTableView: EditableTableView!
  @IBOutlet weak var confHintLabel: NSTextField!
  @IBOutlet weak var addBindingBtn: NSButton!
  @IBOutlet weak var removeBindingBtn: NSButton!
  @IBOutlet weak var showConfFileBtn: NSButton!
  @IBOutlet weak var deleteConfFileBtn: NSButton!
  @IBOutlet weak var newConfBtn: NSButton!
  @IBOutlet weak var duplicateConfBtn: NSButton!
  @IBOutlet weak var useMediaKeysButton: NSButton!
  @IBOutlet weak var bindingSearchField: NSSearchField!
  @IBOutlet weak var showFromAllSourcesBtn: NSButton!

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []

    UserDefaults.standard.removeObserver(self, forKeyPath: #keyPath(view.effectiveAppearance))
  }

  override func viewWillAppear() {
    Logger.log("Key Bindings pref pane will appear", level: .verbose)
    super.viewWillAppear()
    BindingTableState.manager.applyStateUpdate(AppInputConfig.current)  // bring up to date
    BindingTableState.manager.enableObservers()
  }

  override func viewWillDisappear() {
    // Disable observers when not in use to save CPU
    Logger.log("Key Bindings pref pane will disappear", level: .verbose)
    super.viewWillDisappear()
    BindingTableState.manager.disableObservers()
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let bindingTableController = BindingTableViewController(bindingTableView, selectionDidChangeHandler: updateTableButtonVisibilities)
    self.bindingTableController = bindingTableController
    confTableController = ConfTableViewController(confTableView, bindingTableController, selectionDidChangeHandler: updateTableButtonVisibilities)
    setCustomTableColors()

    bindingSearchField.stringValue = bindingTableState.filterString

    useMediaKeysButton.title = NSLocalizedString("preference.system_media_control", comment: "Use system media control")

    observers.append(NotificationCenter.default.addObserver(forName: .iinaPendingUIChangeForConfTable, object: nil, queue: .main) { _ in
      self.updateTableButtonVisibilities()
    })

    addObserver(self, forKeyPath: #keyPath(view.effectiveAppearance), options: [], context: nil)

    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingSearchFieldShouldUpdate, object: nil, queue: .main) { notification in
      guard let newStringValue = notification.object as? String else {
        Logger.log("Received \(notification.name.rawValue.quoted) with invalid object: \(type(of: notification.object))", level: .error)
        return
      }
      guard self.bindingSearchField.stringValue != newStringValue else {
        return
      }
      self.bindingSearchField.stringValue = newStringValue
    })

    confTableController?.selectCurrentConfRow()
    self.updateTableButtonVisibilities()

    // FIXME: need to change this to *after* first data load
    // Set initial scroll, and set up to save scroll value across launches
    if let scrollView = bindingTableView.enclosingScrollView {
      let observer = scrollView.restoreAndObserveVerticalScroll(key: .uiPrefBindingsTableScrollOffsetY, defaultScrollAction: {
        bindingTableView.scrollRowToVisible(0)
      })
      // Change vertical scroll elastisticity of tables in Key Bindings prefs from "yes" to "allowed"
      observers.append(observer)
    }
  }

  fileprivate let blendFraction: CGFloat = 0.2
  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath else { return }

    switch keyPath {
    case #keyPath(view.effectiveAppearance):
      // Need to use this closure for dark/light mode toggling to get picked up while running (not sure why...)
      view.effectiveAppearance.applyAppearanceFor {
        setCustomTableColors()
      }
    default:
      return
    }
  }

  // MARK: - IBActions

  @IBAction func addBindingBtnAction(_ sender: AnyObject) {
    bindingTableController?.addNewBinding()
  }

  @IBAction func removeBindingBtnAction(_ sender: AnyObject) {
    bindingTableController?.removeSelectedBindings()
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
    bindingTableView.reloadExistingRows(reselectRowsAfter: true)
  }

  @IBAction func openKeyBindingsHelpAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink.appending("/Manage-Key-Bindings"))!)
  }

  @IBAction func searchAction(_ sender: NSSearchField) {
    bindingTableState.applyFilter(sender.stringValue)
  }

  // MARK: - UI
  private func updateTableButtonVisibilities() {
    let isSelectedConfReadOnly = confTableState.isSelectedConfReadOnly
    Logger.log("Updating editEnabledStatus to \(!isSelectedConfReadOnly)", level: .verbose)
    [deleteConfFileBtn, addBindingBtn].forEach { btn in
      btn?.isHidden = isSelectedConfReadOnly
    }
    showConfFileBtn.isEnabled = !isSelectedConfReadOnly
    confHintLabel.stringValue = NSLocalizedString("preference.key_binding_hint_\(isSelectedConfReadOnly ? "1" : "2")", comment: "preference.key_binding_hint")

    // re-evaluate this each time either table changed selection:
    removeBindingBtn.isHidden = confTableState.isSelectedConfReadOnly || bindingTableView.selectedRowIndexes.isEmpty
  }

  private func setCustomTableColors() {
    let builtInItemTextColor: NSColor = .controlAccentColor.blended(withFraction: blendFraction, of: .textColor)!
    confTableController?.setCustomColors(builtInItemTextColor: builtInItemTextColor)
    confTableView.reloadExistingRows(reselectRowsAfter: true)

    bindingTableController?.setCustomColors(builtInItemTextColor: builtInItemTextColor)
    bindingTableView.reloadExistingRows(reselectRowsAfter: true)

    let lastPlayerStr = NSLocalizedString("preference.show_all_bindings.last_player", comment: "last player window")
    let allSourcesStr = NSLocalizedString("preference.show_all_bindings.other_sources", comment: "other bindings")
    let btnTitle = String(format: NSLocalizedString("preference.show_all_bindings", comment: "Include %@ which are present in %@"), allSourcesStr, lastPlayerStr)
    let attrString = NSMutableAttributedString(string: btnTitle, attributes: [:])

    // Add special formatting for "from all sources" substring
    if let nsRange = btnTitle.range(of: allSourcesStr)?.nsRange(in: btnTitle) {
      attrString.addAttributes([.foregroundColor: builtInItemTextColor], range: nsRange)

      // Add italic
      if let buttonFont = showFromAllSourcesBtn.font {
        let italicDescriptor: NSFontDescriptor = buttonFont.fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits.italic)
        if let italicFont = NSFont(descriptor: italicDescriptor, size: 0) {
          attrString.addAttributes([.font: italicFont], range: nsRange)
        }
      }
    }

    // TODO: add link to last player window, and update it as it changes

    showFromAllSourcesBtn.attributedTitle = attrString
    showFromAllSourcesBtn.layout() // Re-layout in case width changed due to formatting changes
  }
}
