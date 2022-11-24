//
//  BindingTableStateManager.swift
//  iina
//
//  Created by Matt Svoboda on 11/15/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Responsible for changing the state of the Key Bindings table by building new versions of `BindingTableState`.
 */
class BindingTableStateManager {
  enum Key: String {
    case appInputConfig = "AppInputConfig"
    case tableUIChange = "BindingTableChange"
    case confFile = "InputConfFile"
  }

  private var observers: [NSObjectProtocol] = []

  init() {
    Logger.log("BindingTableStateManager init", level: .verbose)
    observers.append(NotificationCenter.default.addObserver(forName: .iinaAppInputConfigDidChange, object: nil, queue: .main, using: self.appInputConfigDidChange))
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  /*
   Executes a single "action" to the current table state.
   This is either the "do" of an undoable action, or an undo of that action, or a redo of that undo.
   Don't use this for changes which aren't undoable, like filter string.

   Currently, all changes are to bindings in the current conf file. Must execute sequentially:
   1. Save conf file, get updated default section rows
   2. Send updated default section bindings to InputBindingController. It will recalculate all bindings and re-bind appropriately, then
   returns the updated set of all bindings to us.
   3. Update this class's unfiltered list of bindings, and recalculate filtered list
   4. Push update to the Key Bindings table in the UI so it can be animated.
   */
  func doAction(_ userConfMappingsNew: [KeyMapping], _ desiredTableChange: TableUIChange? = nil) {

    // If a filter is active for these ops, clear it. Otherwise the new row may be hidden by the filter, which might confuse the user.
    if !BindingTableState.current.filterString.isEmpty {
      if let ch = desiredTableChange, ch.changeType == .updateRows || ch.changeType == .addRows {
        // This will cause the UI to reload the table. We will do the op as a separate step, because a "reload" is a sledgehammer which
        // doesn't support animation and also blows away selections and editors.
        clearFilter()
      }
    }

    if let undoManager = PreferenceWindowController.undoManager {
      let userConfMappingsOld = AppInputConfig.userConfMappings

      undoManager.registerUndo(withTarget: self, handler: { bindingTableState in
        // TODO: instead of .undoRedo/diff, a better solution would be to calculate the inverse of original TableUIChange
        // FIXME: also need to use USER BINDINGS
        // FIXME: Filters!
        // If moving rows in the table which aren't unique, this solution often guesses the wrong rows to animate
        bindingTableState.doAction(userConfMappingsOld, TableUIChange(.undoRedo))
      })

      if let actionName = makeActionNameIfNeeded(basedOn: desiredTableChange, undoManager) {
        undoManager.setActionName(actionName)
      }
    }

    // Save user's changes to file before doing anything else:
    guard let updatedConfFile = overwriteCurrentConfFile(with: userConfMappingsNew) else {
      return
    }

    /*
     Replace the shared static "default" section bindings with the given list. Then rebuild the AppInputConfig.
     It will notify us asynchronously when it is done.

     Note: we rely on the assumption that we know which rows will be added & removed, and that information is contained in `tableUIChange`.
     This is needed so that animations can work. But InputBindingController builds the actual row data,
     and the two must match or else visual bugs will result.
     */
    var attachment: [AnyHashable : Any] = [BindingTableStateManager.Key.confFile: updatedConfFile]
    if let desiredTableChange = desiredTableChange {
      attachment[BindingTableStateManager.Key.tableUIChange] = desiredTableChange
    }

    AppInputConfig.replaceDefaultSectionMappings(with: userConfMappingsNew, attaching: attachment)
  }

  // Format the action name for Edit menu display (Undo/Redo)
  private func makeActionNameIfNeeded(basedOn tableUIChange: TableUIChange? = nil, _ undoManager: UndoManager) -> String? {

    guard let tableUIChange = tableUIChange, !undoManager.isUndoing && !undoManager.isRedoing else {
      return nil
    }

    switch tableUIChange.changeType {
      case .addRows:
        return Utility.format(.keyBinding, tableUIChange.toInsert?.count ?? 0, .add)
      case .removeRows:
        return Utility.format(.keyBinding, tableUIChange.toRemove?.count ?? 0, .delete)
      case .moveRows:
        return Utility.format(.keyBinding, tableUIChange.toMove?.count ?? 0, .move)
      default:
        return nil
    }
  }

  // Not an undoable action; just a UI change
  func applyFilter(newFilterString: String) {
    updateTableUI(AppInputConfig.current, newFilterString: newFilterString)
  }

  private func clearFilter() {
    Logger.log("Clearing Key Bindings filter", level: .verbose)
    applyFilter(newFilterString: "")
    // Tell search field to clear itself:
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingSearchFieldShouldUpdate, object: ""))
  }

  private func appInputConfigDidChange(_ notification: Notification) {
    Logger.log("Received \"\(notification.name.rawValue)\"", level: .verbose)
    guard let userData = notification.userInfo else {
      Logger.log("Notification \"\(notification.name.rawValue)\": contains no data!", level: .error)
      return
    }
    guard let appInputConfig = userData[BindingTableStateManager.Key.appInputConfig] as? AppInputConfig else {
      Logger.log("Notification \"\(notification.name.rawValue)\": no AppInputConfig!", level: .error)
      return
    }

    let tableUIChange = userData[BindingTableStateManager.Key.tableUIChange] as? TableUIChange
    let newInputConfFile = userData[BindingTableStateManager.Key.confFile] as? InputConfFile

    self.updateTableUI(appInputConfig, tableUIChange: tableUIChange, newInputConfFile: newInputConfFile)
  }

  /*
   Called asychronously from other parts of IINA when new data is available which affects the state of the
   table.

   Expected to be run on the main thread.
   */
  private func updateTableUI(_ appInputConfigNew: AppInputConfig, tableUIChange desiredTableChange: TableUIChange? = nil,
                             newFilterString: String? = nil, newInputConfFile: InputConfFile? = nil) {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

    let oldState = BindingTableState.current
    if oldState.appInputConfig.version == appInputConfigNew.version
        && desiredTableChange == nil && newFilterString == nil && newInputConfFile == nil {
      Logger.log("updateTableUI(): ignoring update because nothing new: (v\(appInputConfigNew.version))", level: .verbose)
      return
    }
    let newState = BindingTableState(appInputConfigNew,
                                     filterString: newFilterString ?? oldState.filterString,
                                     inputConfFile: newInputConfFile ?? oldState.inputConfFile)

    // A table change animation can be calculated if not provided, which should be sufficient in most cases
    let tableUIChange: TableUIChange
    if let desiredTableChange = desiredTableChange {
      if desiredTableChange.changeType == .undoRedo {
        tableUIChange = buildTableDiff(oldState: oldState, newState: newState, isUndoRedo: true)
      } else {
        tableUIChange = desiredTableChange
      }
    } else {
      tableUIChange = buildTableDiff(oldState: oldState, newState: newState)
    }

    // Any change made could conceivably change other rows in the table. It's inexpensive to just reload all of them:
    tableUIChange.reloadAllExistingRows = true

    // If the table change is the result of a new conf file being selected, don't try to retain the selection.
    if let newFile = newState.inputConfFile, let oldFile = oldState.inputConfFile,
        !newFile.canonicalFilePath.equalsIgnoreCase(oldFile.canonicalFilePath) {
      tableUIChange.newSelectedRows = IndexSet() // will clear any selection
    }

    BindingTableState.current = newState

    // Notify Key Bindings table of update:
    let notification = Notification(name: .iinaPendingUIChangeForBindingTable, object: tableUIChange)
    Logger.log("Posting \"\(notification.name.rawValue)\" notification with changeType \(tableUIChange.changeType)", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  private func buildTableDiff(oldState: BindingTableState, newState: BindingTableState, isUndoRedo: Bool = false) -> TableUIChange {
    // Remember, the displayed table contents must reflect the *filtered* state.
    let tableUIChange = TableUIChange.buildDiff(oldRows: oldState.bindingRowsFiltered, newRows: newState.bindingRowsFiltered, isUndoRedo: isUndoRedo)
    tableUIChange.rowInsertAnimation = .effectFade
    tableUIChange.rowRemoveAnimation = .effectFade
    return tableUIChange
  }

  // Input Config File: Save
  private func overwriteCurrentConfFile(with userConfMappings: [KeyMapping]) -> InputConfFile? {
    guard let confFilePath = ConfTableState.current.selectedConfFilePath else {
      let alertInfo = Utility.AlertInfo(key: "error_finding_file", args: ["config"])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      return nil
    }
    Logger.log("Saving \(userConfMappings.count) bindings to current conf file: \"\(confFilePath)\"", level: .verbose)
    guard let selectedConfFile = BindingTableState.current.inputConfFile else {
      Logger.log("Cannot save bindings updates to file: could not find file in memory!", level: .error)
      return nil
    }
    let canonicalPathCurrent = URL(fileURLWithPath: confFilePath).resolvingSymlinksInPath().path
    let canonicalPathLoaded = selectedConfFile.canonicalFilePath
    guard canonicalPathCurrent == canonicalPathLoaded else {
      Logger.log("Failed to save bindings updates to file \"\(canonicalPathCurrent)\": its path does not match currently loaded config's (\"\(canonicalPathLoaded)\")", level: .error)
      let alertInfo = Utility.AlertInfo(key: "config.cannot_write", args: [confFilePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      return nil
    }

    return selectedConfFile.overwriteFile(with: userConfMappings)
  }
}
