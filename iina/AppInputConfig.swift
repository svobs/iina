//
//  AppInputConfig.swift
//  iina
//
//  Created by Matt Svoboda on 9/29/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// The currently active bindings for the IINA app. Includes key lookup table, list of binding candidates, & other data
class AppInputConfig {
  
  // MARK: Static

  static let LOG_BINDINGS_REBUILD = false
  static private var lastBuildVersion: Int = 0

  // The current instance. The app can only ever support one set of active key bindings at a time, so each time a change is made,
  // the active bindings are rebuilt and the old set is discarded.
  static var current = AppInputConfig()

  /*
   This attempts to mimick the logic in mpv's `get_cmd_from_keys()` function in input/input.c.
   Rebuilds `appBindingsList` and `currentResolverDict`, updating menu item key equivalents along the way.
   When done, notifies the Preferences > Key Bindings table of the update so it can refresh itself, as well
   as notifies the other callbacks supplied here as needed.

   Should be run on the main thread. For other threads, see `rebuildCurrentAsync()`.

   Generally speaking, if the return value of this method is not used, then `thenNotifyPrefsUI` shold be set to true.
   It should only be false if called synchronously by the Key Bindings UI.
   */
  @discardableResult
  static func rebuildCurrent(thenNotifyPrefsUI: Bool = true) -> AppInputConfig {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

    guard let activePlayerInputConfig = PlayerCore.active.inputConfig else {
      Logger.fatal("rebuildCurrent(): no active player!")
    }

    let builder = activePlayerInputConfig.makeAppInputConfigBuilder()
    let newAppBindings = builder.build()

    // This will update all standard menu item bindings, and also update the isMenuItem status of each:
    (NSApp.delegate as! AppDelegate).menuController.updateKeyEquivalentsFrom(newAppBindings.bindingCandidateList)

    AppInputConfig.current = newAppBindings

    if thenNotifyPrefsUI {
      // Notify Key Bindings table in prefs UI
      (NSApp.delegate as! AppDelegate).bindingTableStore.appActiveBindingsDidChange(newAppBindings.bindingCandidateList)
    }

    return newAppBindings
  }

  // Same as `rebuildCurrent()`, but kicks off an async task and notifies Key Bindings table
  static func rebuildCurrentAsync() {
    dispatchPrecondition(condition: .notOnQueue(DispatchQueue.main))

    let rebuildVersion = AppInputConfig.lastBuildVersion + 1
    Logger.log("Requesting app active bindings rebuild (v\(rebuildVersion))", level: .verbose)

    DispatchQueue.main.async {
      // Optimization: drop all but the most recent request
      if AppInputConfig.lastBuildVersion >= rebuildVersion {
        return
      }
      AppInputConfig.lastBuildVersion = rebuildVersion
      Logger.log("Rebuilding app active bindings (v\(rebuildVersion))", level: .verbose)

      rebuildCurrent(thenNotifyPrefsUI: true)
    }
  }

  // MARK: Single instance

  // The list of all bindings including those with duplicate keys. The list `bindingRowsAll` of `ActiveBindingTableStore` should be kept
  // consistent with this one as much as possible, but some brief inconsistencies may be acceptable due to the asynchronous nature of UI.
  let bindingCandidateList: [ActiveBinding]

  // This structure results from merging the layers of enabled input sections for the currently active player using precedence rules.
  // Contains only the bindings which are currently enabled for this player, plus extra dummy "ignored" bindings for partial key sequences.
  // For lookup use `resolveMpvKey()` or `resolveKeyEvent()` from the active player's input config.
  let resolverDict: [String: ActiveBinding]

  init(bindingCandidateList: [ActiveBinding] = [], resolverDict: [String: ActiveBinding] = [:]) {
    self.bindingCandidateList = bindingCandidateList
    self.resolverDict = resolverDict
  }

  func logEnabledBindings() {
    if AppInputConfig.LOG_BINDINGS_REBUILD, Logger.enabled && Logger.Level.preferred >= .verbose {
      let bindingList = bindingCandidateList.filter({ $0.isEnabled })
      Logger.log("Currently enabled bindings (\(bindingList.count)):\n\(bindingList.map { "\t\($0)" }.joined(separator: "\n"))", level: .verbose, subsystem: PlayerInputConfig.inputBindingsSubsystem)
    }
  }
}
