//
//  BindingTableStateManager.swift
//  iina
//
//  Created by Matt Svoboda on 11/15/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class BindingTableStateManager {
  static var currentState = BindingTableState(AppInputConfig.current, filterString: "", inputConfigFile: nil)

  unowned var undoManager: UndoManager? = nil

  // MARK: TableChange push & receive with other components

  /*
   Must execute sequentially:
   1. Save conf file, get updated default section rows
   2. Send updated default section bindings to InputBindingController. It will recalculate all bindings and re-bind appropriately, then
   returns the updated set of all bindings to us.
   3. Update this class's unfiltered list of bindings, and recalculate filtered list
   4. Push update to the Key Bindings table in the UI so it can be animated.
   */
  func applyChange(_ userConfMappingsNew: [KeyMapping], _ desiredTableChange: TableChange? = nil) {

    // If a filter is active for these ops, clear it. Otherwise the new row may be hidden by the filter, which might confuse the user.
    // This will cause the UI to reload the table. We will do the op as a separate step, because a "reload" is a sledgehammer which
    // doesn't support animation and also blows away selections and editors.
    if !BindingTableStateManager.currentState.filterString.isEmpty {
      if let ch = desiredTableChange, ch.changeType == .updateRows || ch.changeType == .addRows {
        clearFilter()
      }
    }

    if let undoManager = self.undoManager {
      let userConfMappingsOld = AppInputConfig.userConfMappings

      undoManager.registerUndo(withTarget: self, handler: { bindingTableStore in
        // TODO: instead of .undoRedo/diff, a better solution would be to calculate the inverse of original TableChange
        // FIXME: also need to use USER BINDINGS
        // If moving rows in the table which aren't unique, this solution often guesses the wrong rows to animate
        bindingTableStore.applyChange(userConfMappingsOld, TableChange(.undoRedo))
      })

      // Format the action name for Edit menu display
      if let desiredTableChange = desiredTableChange, !undoManager.isUndoing && !undoManager.isRedoing {
        var actionName: String? =  nil
        switch desiredTableChange.changeType {
          case .addRows:
            actionName = Utility.format(.keyBinding, desiredTableChange.toInsert?.count ?? 0, .add)
          case .removeRows:
            actionName = Utility.format(.keyBinding, desiredTableChange.toRemove?.count ?? 0, .delete)
          case .moveRows:
            actionName = Utility.format(.keyBinding, desiredTableChange.toMove?.count ?? 0, .move)
          default:
            break
        }
        if let actionName = actionName {
          undoManager.setActionName(actionName)
        }
      }
    }

    // Save to file. Note that all non-"default" rows in this list will be ignored, so there is no chance of corrupting a different section,
    // or of writing another section's bindings to the "default" section.
     guard let userConfMappingsNew = saveBindingsToCurrentConfigFile(userConfMappingsNew) else {
      return
     }

     /*
      Replace the shared static "default" section bindings with the given list. Then rebuild the AppInputConfig.
      It will notify us asynchronously when it is done.

      Note: we rely on the assumption that we know which rows will be added & removed, and that information is contained in `tableChange`.
      This is needed so that animations can work. But InputBindingController builds the actual row data,
      and the two must match or else visual bugs will result.
      */
     AppInputConfig.replaceDefaultSectionMappings(with: userConfMappingsNew, completionHandler: { appInputConfigNew in
       self.appInputConfigDidChange(appInputConfigNew, tableChange: desiredTableChange)
     })
   }

  private func clearFilter() {
    Logger.log("Clearing Key Bindings filter", level: .verbose)
    filterBindings(newFilterString: "")
    // Tell search field to clear itself:
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingSearchFieldShouldUpdate, object: ""))
  }

  // No an undoable action; just a UI change
  func filterBindings(newFilterString: String) {
    appInputConfigDidChange(AppInputConfig.current, newFilterString: newFilterString)
  }

  /*
   Does the following sequentially:
   - Update this class's unfiltered list of bindings, and recalculate filtered list
   - Push update to the Key Bindings table in the UI so it can be animated.
   Expected to be run on the main thread.
   */
  func appInputConfigDidChange(_ appInputConfigNew: AppInputConfig, tableChange desiredTableChange: TableChange? = nil,
                               newFilterString: String? = nil, newInputConfigFile: InputConfigFile? = nil) {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    let lastState = BindingTableStateManager.currentState
    let currentState = BindingTableState(appInputConfigNew,
                                         filterString: newFilterString ?? lastState.filterString,
                                         inputConfigFile: newInputConfigFile ?? lastState.inputConfigFile)

    // A table change animation can be calculated if not provided, which should be sufficient in most cases:
    let tableChange: TableChange
    if let desiredTableChange = desiredTableChange {
      if desiredTableChange.changeType == .undoRedo {
        tableChange = buildTableDiff(oldState: lastState, newState: currentState, isUndoRedo: true)
      } else {
        tableChange = desiredTableChange
      }
    } else {
      tableChange = buildTableDiff(oldState: lastState, newState: currentState)
    }

    // Any change made could conceivably change other rows in the table. It's inexpensive to just reload all of them:
    tableChange.reloadAllExistingRows = true

    BindingTableStateManager.currentState = currentState

    // Notify Key Bindings table of update:
    let notification = Notification(name: .iinaKeyBindingsTableShouldUpdate, object: tableChange)
    Logger.log("Posting '\(notification.name.rawValue)' notification with changeType \(tableChange.changeType)", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  private func buildTableDiff(oldState: BindingTableState, newState: BindingTableState, isUndoRedo: Bool = false) -> TableChange {
    // Remember, the displayed table contents must reflect the *filtered* state.
    return TableChange.buildDiff(oldRows: oldState.bindingRowsFiltered, newRows: newState.bindingRowsFiltered, isUndoRedo: isUndoRedo)
  }

  // Input Config File: Save
  private func saveBindingsToCurrentConfigFile(_ userConfMappings: [KeyMapping]) -> [KeyMapping]? {
    guard let configFilePath = AppInputConfig.inputConfigStore.currentConfigFilePath else {
      let alertInfo = Utility.AlertInfo(key: "error_finding_file", args: ["config"])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      return nil
    }
    Logger.log("Saving \(userConfMappings.count) bindings to current config file: \"\(configFilePath)\"", level: .verbose)
    do {
      guard let currentConfigFile = BindingTableStateManager.currentState.inputConfigFile else {
        Logger.log("Cannot save bindings updates to file: could not find file in memory!", level: .error)
        return nil
      }
      let canonicalPathCurrent = URL(fileURLWithPath: configFilePath).resolvingSymlinksInPath().path
      let canonicalPathLoaded = URL(fileURLWithPath: currentConfigFile.filePath).resolvingSymlinksInPath().path
      guard canonicalPathCurrent == canonicalPathLoaded else {
        Logger.log("Failed to save bindings updates to file \"\(canonicalPathCurrent)\": its path does not match currently loaded config's (\"\(canonicalPathLoaded)\")", level: .error)
        let alertInfo = Utility.AlertInfo(key: "config.cannot_write", args: [configFilePath])
        NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
        return nil
      }

      currentConfigFile.replaceAllMappings(with: userConfMappings)
      try currentConfigFile.saveToDisk()
      return currentConfigFile.parseMappings() // gets updated line numbers
    } catch {
      Logger.log("Failed to save bindings updates to file: \(error)", level: .error)
      let alertInfo = Utility.AlertInfo(key: "config.cannot_write", args: [configFilePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    }
    return nil
  }
}
