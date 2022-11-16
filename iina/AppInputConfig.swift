//
//  AppInputConfig.swift
//  iina
//
//  Created by Matt Svoboda on 9/29/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Application-scoped input config (key bindings)
// The currently active bindings for the IINA app. Includes key lookup table, list of binding candidates, & other data
struct AppInputConfig {
  // return true to send notifications; false otherwise
  typealias CompletionHandler = (AppInputConfig) -> Bool

  // MARK: Shared input sections

  // Contains static sections which occupy the bottom of every stack.
  // Sort of like a prototype, but a change to any of these sections will immediately affects all players.
  static private let sharedSectionStack = InputSectionStack(PlayerInputConfig.inputBindingsSubsystem,
                                                            initialEnabledSections: [
                                                              SharedInputSection(name: SharedInputSection.DEFAULT_SECTION_NAME, isForce: true, origin: .confFile),
                                                              SharedInputSection(name: SharedInputSection.AUDIO_FILTERS_SECTION_NAME, isForce: true, origin: .savedFilter),
                                                              SharedInputSection(name: SharedInputSection.VIDEO_FILTERS_SECTION_NAME, isForce: true, origin: .savedFilter),
                                                              SharedInputSection(name: SharedInputSection.PLUGINS_SECTION_NAME, isForce: false, origin: .iinaPlugin)
                                                            ])

  static var sharedSections: [InputSection] {
    sharedSectionStack.sectionsEnabled.map( { sharedSectionStack.sectionsDefined[$0.name]! })
  }

  static var userConfMappings: [KeyMapping] {
    return sharedSectionStack.sectionsDefined[SharedInputSection.DEFAULT_SECTION_NAME]!.keyMappingList
  }

  static func replaceDefaultSectionMappings(with userConfMappings: [KeyMapping], completionHandler: CompletionHandler? = nil) {
    replaceMappings(forSharedSectionName: SharedInputSection.DEFAULT_SECTION_NAME, with: userConfMappings, doRebuildAfter: false)
    AppInputConfig.rebuildCurrent(completionHandler: completionHandler)
  }


  // This can get called a lot for menu item bindings [by MacOS], so setting onlyIfDifferent=true can possibly cut down on redundant work.
  static func replaceMappings(forSharedSectionName: String, with mappings: [KeyMapping],
                              onlyIfDifferent: Bool = false, doRebuildAfter: Bool = true) {
    var doReplace = true
    InputSectionStack.dq.sync {
      if let sharedSection = sharedSectionStack.sectionsDefined[forSharedSectionName] as? SharedInputSection {

        if onlyIfDifferent {
          let existingCount = sharedSection.keyMappingList.count
          let newCount = mappings.count
          // TODO: get more sophisticated than this simple check
          let didChange = !(existingCount == 0 && newCount == 0)
          doReplace = didChange
        }

        if doReplace {
          sharedSection.setKeyMappingList(mappings)
          if doRebuildAfter {
            AppInputConfig.rebuildCurrent()
          }
        }
      }
    }
  }

  // MARK: Other Static

  static let inputConfigStore: InputConfigStore = InputConfigStore()

  static let bindingTableStateManager: BindingTableStateManager = BindingTableStateManager()

  static private var lastStartedVersion: Int = 0

  static var logBindingsRebuild: Bool {
    Preference.bool(for: .logKeyBindingsRebuild)
  }

  // The current instance. The app can only ever support one set of active key bindings at a time, so each time a change is made,
  // the active bindings are rebuilt and the old set is discarded.
  static var current = AppInputConfig(version: 0, bindingCandidateList: [], resolverDict: [:], defaultSectionStartIndex: 0, defaultSectionEndIndex: 0)

  /*
   This attempts to mimick the logic in mpv's `get_cmd_from_keys()` function in input/input.c.
   Rebuilds `appBindingsList` and `currentResolverDict`, updating menu item key equivalents along the way.
   When done, notifies the Preferences > Key Bindings table of the update so it can refresh itself, as well
   as notifies the other callbacks supplied here as needed.
   */
  static func rebuildCurrent(completionHandler: CompletionHandler? = nil) {
    let requestedVersion = AppInputConfig.lastStartedVersion + 1
    Logger.log("Requesting app input bindings rebuild (v\(requestedVersion))", level: .verbose)

    DispatchQueue.main.async {
      var notifyTable = true
      defer {
        // Always execute this before returning, if supplied
        if let completionHandler = completionHandler, !completionHandler(AppInputConfig.current) {
          notifyTable = false
        }
        if notifyTable {
          // Notify Key Bindings table in prefs UI
          bindingTableStateManager.updateTableState(AppInputConfig.current)
        }
      }

      // Optimization: drop all but the most recent request
      if requestedVersion <= AppInputConfig.lastStartedVersion {
        notifyTable = false
        return
      }
      AppInputConfig.lastStartedVersion = requestedVersion
      if AppInputConfig.current.version == 0 {
        // Initial load
        inputConfigStore.loadBindingsFromCurrentConfigFile()
      }

      guard let activePlayerInputConfig = PlayerCore.active.inputConfig else {
        Logger.fatal("AppInputConfig.rebuildCurrent(): no active player!")
      }

      let builder = activePlayerInputConfig.makeAppInputConfigBuilder()
      let appInputConfigNew = builder.build(version: requestedVersion)

      // This will update all standard menu item bindings, and also update the isMenuItem status of each:
      (NSApp.delegate as! AppDelegate).menuController.updateKeyEquivalents(from: appInputConfigNew.bindingCandidateList)

      AppInputConfig.current = appInputConfigNew
    }
  }

  // MARK: Single instance

  let version: Int

  // The list of all bindings including those with duplicate keys. The list `bindingRowsAll` of `BindingTableState` should be kept
  // consistent with this one as much as possible, but some brief inconsistencies may be acceptable due to the asynchronous nature of UI.
  let bindingCandidateList: [InputBinding]

  // This structure results from merging the layers of enabled input sections for the currently active player using precedence rules.
  // Contains only the bindings which are currently enabled for this player, plus extra dummy "ignored" bindings for partial key sequences.
  // For lookup use `resolveMpvKey()` or `resolveKeyEvent()` from the active player's input config.
  let resolverDict: [String: InputBinding]

  // (Note: These two fields are used for optimizing the Key Bindings UI  but are otherwise not important.)
  // The index into `bindingCandidateList` of the first binding in the "default" section.
  // If the "default" section has no bindings, then this will be the last index of the section preceding it in precendence, or simply 0
  // if there are no sections preceding it.
  let defaultSectionStartIndex: Int
  // The index into `bindingCandidateList` of the last binding in the "default" section.
  // If the "default" section has no bindings, then this will be the index of the first binding belonging to  the next "strong" section,
  // or simply `bindingCandidateList.count` if there are no sections after it.
  let defaultSectionEndIndex: Int

  init(version: Int, bindingCandidateList: [InputBinding], resolverDict: [String: InputBinding], defaultSectionStartIndex: Int, defaultSectionEndIndex: Int) {
    self.version = version
    self.bindingCandidateList = bindingCandidateList
    self.resolverDict = resolverDict
    self.defaultSectionStartIndex = defaultSectionStartIndex
    self.defaultSectionEndIndex = defaultSectionEndIndex
  }

  func logEnabledBindings() {
    if AppInputConfig.logBindingsRebuild, Logger.enabled && Logger.Level.preferred >= .verbose {
      let bindingList = bindingCandidateList.filter({ $0.isEnabled })
      Logger.log("Currently enabled bindings (\(bindingList.count)):\n\(bindingList.map { "\t\($0)" }.joined(separator: "\n"))", level: .verbose, subsystem: PlayerInputConfig.inputBindingsSubsystem)
    }
  }
}
