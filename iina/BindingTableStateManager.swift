//
//  BindingTableStateManager.swift
//  iina
//
//  Created by Matt Svoboda on 11/15/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/**
 Responsible for changing the state of the Key Bindings table by building new versions of `BindingTableState`.
 */
class BindingTableStateManager: NSObject {
  let clearFilterWhenChangeMade = false
  let selectNextRowAfterDelete = false

  enum Key: String {
    case appInputConfig = "AppInputConfig"
    case tableUIChange = "BindingTableChange"
    case confFile = "InputConfFile"
  }

  private var undoHelper = PrefsWindowUndoHelper()
  private var observers: [NSObjectProtocol] = []

  func enableObservers() {
    guard observers.isEmpty else { return }
    observers.append(NotificationCenter.default.addObserver(forName: .iinaAppInputConfigDidChange, object: nil, queue: .main, using: self.appInputConfigDidChange))

    for key in [Preference.Key.showKeyBindingsFromAllSources] {
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }
  }

  func disableObservers() {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []

    // Remove observers for IINA preferences.
    ObjcUtils.silenced {
      for key in [Preference.Key.showKeyBindingsFromAllSources] {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

    DispatchQueue.main.async {
      switch keyPath {
      case Preference.Key.showKeyBindingsFromAllSources.rawValue:
        self.applyStateUpdate(AppInputConfig.current)
      default:
        return
      }
    }
  }

  func initialState() -> BindingTableState {
    let filterString = UIState.shared.isRestoreEnabled ? Preference.string(for: .uiPrefBindingsTableSearchString) ?? "" : ""
    let showAllBindings = Preference.bool(for: .showKeyBindingsFromAllSources)
    return BindingTableState(AppInputConfig.current, filterString: filterString, inputConfFile: ConfTableState.manager.loadConfFile(),
                             showAllBindings: showAllBindings)
  }

  /**
   Executes a single "action" to the current table state.
   This is either the "do" of an undoable action, or an undo of that action, or a redo of that undo.
   Don't use this for changes which aren't undoable, like filter string updates.

   Currently, all changes are to bindings in the current conf file. Must execute sequentially:
   1. Save conf file, get updated default section rows
   2. Send updated default section bindings to `InputBindingController`. It will recalculate all bindings and re-bind appropriately, then
   returns the updated set of all bindings to us.
   3. Update this class's unfiltered list of bindings, and recalculate filtered list
   4. Push update to the Key Bindings table in the UI so it can be animated.
   */
  func doAction(_ allRowsNew: [InputBinding], _ tableUIChange: TableUIChange) {
    // Currently don't care about any rows except for "default" section
    let userConfMappingsNew = extractUserConfMappings(from: allRowsNew)

    // If a filter is active for these ops, clear it. Otherwise the new row may be hidden by the filter, which might confuse the user.
    if clearFilterWhenChangeMade && !BindingTableState.current.filterString.isEmpty {
      switch tableUIChange.changeType {
      case .updateRows, .insertRows, .moveRows, .removeRows:
        // This will cause an asynchronous load of the table's UI. So we will end up with 2 table updates from our one action.
        // We will do the op as a separate step, because a "reload" is a sledgehammer which
        // doesn't support animation and also blows away selections and editors.
        clearFilter()
      default:
        break
      }
    }

    let tableStateOld = BindingTableState.current

    undoHelper.register(buildActionName(basedOn: tableUIChange), undo: { [self] in
      let tableStateNew = BindingTableState.current

      /**
       The undo of the original TableUIChange is just its inverse.
       HOWEVER: at present, the undo/redo logic in this class only cares about the "default section" bindings.
       This means that other bindings could have been added/removed by other sections above and below the default section
       since the last `TableUIChange` was calculated. Don't need to care about anything below the default section,
       but do need to adjust the indexes in each `TableUIChange` by the number of rows added/removed above them in order
       to stay current.
       */
      let userConfSectionStartIndexOld = tableStateOld.appInputConfig.userConfSectionStartIndex
      let userConfSectionStartIndexNew = tableStateNew.appInputConfig.userConfSectionStartIndex
      let userConfSectionOffsetChange = userConfSectionStartIndexOld - userConfSectionStartIndexNew
      let tableUIChangeUndo = TableUIChange.builder.inverted(from: tableUIChange, andAdjustAllIndexesBy: userConfSectionOffsetChange, selectNextRowAfterDelete: selectNextRowAfterDelete)
      tableUIChangeUndo.setUpFlashForChangedRows()

      let bindingRowsOld = tableStateOld.appInputConfig.bindingCandidateList
      self.doAction(bindingRowsOld, tableUIChangeUndo)  // Recursive call: implicitly registers redo
    })

    // Enqueue task to save user's changes to file:
    let updatedConfFile = overwrite(currentConfFile: tableStateOld.inputConfFile, with: userConfMappingsNew)

    /**
     Replace the shared static "default" section bindings with the given list, which will trigger a rebuild
     of AppInputConfig, which will result in `appInputConfigDidChange()` being called asynchronously.

     Note: we rely on the assumption that we know which rows will be added & removed, and that information is contained in `tableUIChange`.
     This is needed so that animations can work. But InputBindingController builds the actual row data,
     and the two must match or else visual bugs will result.
     */
    let associatedData: [AnyHashable : Any] = [BindingTableStateManager.Key.confFile: updatedConfFile,
                                               BindingTableStateManager.Key.tableUIChange: tableUIChange]
    AppInputConfig.replaceUserConfSectionMappings(with: userConfMappingsNew, attaching: associatedData)
  }

  private func extractUserConfMappings(from bindingRows: [InputBinding]) -> [KeyMapping] {
    bindingRows.filter({ $0.origin == .confFile }).map({ $0.keyMapping })
  }

  // Format the action name for Edit menu display (Undo/Redo)
  private func buildActionName(basedOn tableUIChange: TableUIChange? = nil) -> String? {

    guard let tableUIChange = tableUIChange else {
      return nil
    }

    switch tableUIChange.changeType {
    case .insertRows:
      return Utility.format(.keyBinding, tableUIChange.toInsert?.count ?? 0, .add)
    case .removeRows:
      return Utility.format(.keyBinding, tableUIChange.toRemove?.count ?? 0, .delete)
    case .moveRows:
      return Utility.format(.keyBinding, tableUIChange.toMove?.count ?? 0, .move)
    case .updateRows:
      return Utility.format(.keyBinding, tableUIChange.toUpdate?.count ?? 0, .update)
    default:
      return nil
    }
  }

  // Not an undoable action; just a UI change (but possibly saved in UI state prefs)
  func applyFilter(newFilterString: String) {
    UIState.shared.set(newFilterString, for: .uiPrefBindingsTableSearchString)
    applyStateUpdate(AppInputConfig.current, newFilterString: newFilterString)
    // Tell search field to update if needed:
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingSearchFieldShouldUpdate, object: newFilterString))
  }

  private func clearFilter() {
    Logger.log("Clearing Key Bindings filter", level: .verbose)
    applyFilter(newFilterString: "")
  }

  private func appInputConfigDidChange(_ notification: Notification) {
    Logger.log("BindingTableStateManager received \(notification.name.rawValue.quoted)", level: .verbose)
    guard let userData = notification.userInfo else {
      Logger.log("Notification \(notification.name.rawValue.quoted): contains no data!", level: .error)
      return
    }
    guard let appInputConfig = userData[BindingTableStateManager.Key.appInputConfig] as? AppInputConfig else {
      Logger.log("Notification \(notification.name.rawValue.quoted): no AppInputConfig!", level: .error)
      return
    }

    let tableUIChange = userData[BindingTableStateManager.Key.tableUIChange] as? TableUIChange
    let newInputConfFile = userData[BindingTableStateManager.Key.confFile] as? InputConfFile

    self.applyStateUpdate(appInputConfig, desiredTableUIChange: tableUIChange, newInputConfFile: newInputConfFile)
  }

  /**
   Builds a new `BindingTableState` and sets `BindingTableState.current` to it, using the given params if provided.
   Then notifies the table to update its UI. More notes:
   • If an update to `AppInputConfig` was needed, that will be done first and this method will be called asychronously
   from other parts of IINA.
   • The `TableUIChange` can be generated via diff to update the UI if not provided, but it is better to provide it in
   order to get more accurate animations.
   • Expected to be run on the main thread.
   */
  func applyStateUpdate(_ appInputConfigNew: AppInputConfig, desiredTableUIChange: TableUIChange? = nil,
                        newFilterString: String? = nil, newInputConfFile: InputConfFile? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))

    let showAllBindings = Preference.bool(for: .showKeyBindingsFromAllSources)

    Logger.log("Updating Binding table state: hasUIChange=\(desiredTableUIChange != nil) filterUpdate=\(newFilterString?.quoted ?? "nil") showAllBindings=\(showAllBindings)", level: .verbose)
    let oldState = BindingTableState.current
    if oldState.appInputConfig.version == appInputConfigNew.version
        && desiredTableUIChange == nil && newFilterString == nil && newInputConfFile == nil && showAllBindings == oldState.showAllBindings {
      Logger.log("BindingTableStateManager.applyStateUpdate(): ignoring update because nothing new: (v\(appInputConfigNew.version))", level: .verbose)
      return
    }

    let newState = BindingTableState(appInputConfigNew,
                                     filterString: newFilterString ?? oldState.filterString,
                                     inputConfFile: newInputConfFile ?? oldState.inputConfFile,
                                     showAllBindings: showAllBindings)

    BindingTableState.current = newState

    let tableUIChange: TableUIChange
    if let unfilteredTableChange = desiredTableUIChange {
      // If there is an active filter, must convert the unfiltered indexes in TableUIChange to filtered indexes.
      // This can't be done until after the new `AppInputConfig` is received due to the possibility of rows being added/removed
      // which are outside the user conf section.
      if !newState.filterString.isEmpty {
        // Attempting to update table rows while a filter is active.
        // TODO: The animation functionality here needs improvement. Need to retain selection on update!
        tableUIChange = buildTableDiff(oldState: oldState, newState: newState)
      } else {
        tableUIChange = unfilteredTableChange
      }
    } else {
      // A table change animation can be calculated if not provided, which should be sufficient for "reload".
      tableUIChange = buildTableDiff(oldState: oldState, newState: newState)
    }
    updateTableUI(oldState: oldState, newState: newState, desiredTableUIChange: tableUIChange)
  }

  private func translateToFiltered(_ unfilteredSet: IndexSet?, _ oldState: BindingTableState) -> IndexSet? {
    guard let unfilteredSet = unfilteredSet else {
      return nil
    }
    var filteredSet = IndexSet()
    for unfilteredIndex in unfilteredSet {
      if let filteredIndex = oldState.getFilteredIndex(fromUniltered: unfilteredIndex) {
        filteredSet.insert(filteredIndex)
      } else {
        Logger.log("Failed to find filtered index from unfiltered index \(unfilteredIndex); skipping", level: .error)
      }
    }
    return filteredSet
  }

  private func updateTableUI(oldState: BindingTableState, newState: BindingTableState, desiredTableUIChange: TableUIChange) {
    let tableUIChange = desiredTableUIChange

    // Any change made could conceivably change other rows in the table. It's inexpensive to just reload all of them:
    tableUIChange.reloadAllExistingRows = true

    // If the table change is the result of a new conf file being selected, don't try to retain the selection.
    if !newState.inputConfFile.canonicalFilePath.equalsIgnoreCase(oldState.inputConfFile.canonicalFilePath) {
      tableUIChange.newSelectedRowIndexes = IndexSet() // will clear any selection
      // The default slide animations look good when applying filters, but they are too chaotic when changing files.
      // A fade effect still looks nicer than nothing. Moved rows will still animate, but that actually works well
      // for sliding VF/AF bindings up and down as the list above them changes length.
      tableUIChange.rowInsertAnimation = .effectFade
      tableUIChange.rowRemoveAnimation = .effectFade
    }

    // Notify Key Bindings table of update:
    let notification = Notification(name: .iinaPendingUIChangeForBindingTable, object: tableUIChange)
    Logger.log("BindingTableStateManager: posting \(notification.name.rawValue.quoted) notification with changeType \(tableUIChange.changeType)", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  private func buildTableDiff(oldState: BindingTableState, newState: BindingTableState) -> TableUIChange {
    // Remember, the displayed table contents must reflect the *filtered* state (displayed rows).
    return TableUIChange.builder.buildDiff(oldRows: oldState.displayedRows, newRows: newState.displayedRows)
  }

  // Save change to input conf file
  private func overwrite(currentConfFile: InputConfFile, with userConfMappings: [KeyMapping]) -> InputConfFile {
    // Sanity check. Probably being paranoid.
    let filePathFromBindingState = currentConfFile.canonicalFilePath
    let filePathFromConfState = URL(fileURLWithPath: ConfTableState.current.selectedConfFilePath).resolvingSymlinksInPath().path
    guard filePathFromBindingState == filePathFromConfState else {
      Logger.log("While saving bindings updates to file \(filePathFromBindingState.quoted): its path does not match value from preferences (\(filePathFromConfState.quoted))", level: .error)
      let alertInfo = Utility.AlertInfo(key: "config.cannot_write", args: [filePathFromBindingState])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      return currentConfFile
    }

    return currentConfFile.overwriteFile(with: userConfMappings)
  }
}
