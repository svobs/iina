//
//  AppInputConfig.swift
//  iina
//
//  Created by Matt Svoboda on 9/29/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/// Application-scoped input config (key bindings)
/// The currently active bindings for the IINA app. Includes key lookup table, list of binding candidates, & other data
struct AppInputConfig {
  /// Return true to send notifications; false otherwise
  typealias NotificationData = [AnyHashable : Any]

  static unowned var log = Logger.Subsystem.input

  // MARK: Shared input sections

  /// Contains static sections which occupy the bottom of every stack.
  /// Sort of like a prototype, but a change to any of these sections will immediately affects all players.
  static private let sharedSectionStack = InputSectionStack(initialEnabledSections: [
    SharedInputSection(name: SharedInputSection.USER_CONF_SECTION_NAME, isForce: true, origin: .confFile),
    SharedInputSection(name: SharedInputSection.AUDIO_FILTERS_SECTION_NAME, isForce: true, origin: .savedFilter),
    SharedInputSection(name: SharedInputSection.VIDEO_FILTERS_SECTION_NAME, isForce: true, origin: .savedFilter),
    SharedInputSection(name: SharedInputSection.PLUGINS_SECTION_NAME, isForce: false, origin: .iinaPlugin),
    SharedInputSection(name: SharedInputSection.BUILTIN_MENU_ITEMS_SECTION_NAME, isForce: true, origin: .builtInMenuItem)
  ])

  static var sharedSections: [InputSection] {
    sharedSectionStack.sectionsEnabled.map( { sharedSectionStack.sectionsDefined[$0.name]! })
  }

  static var userConfMappings: [KeyMapping] {
    return sharedSectionStack.sectionsDefined[SharedInputSection.USER_CONF_SECTION_NAME]!.keyMappingList
  }

  static func replaceUserConfSectionMappings(with userConfMappings: [KeyMapping], attaching userData: NotificationData? = nil) {
    replaceMappings(forSharedSectionName: SharedInputSection.USER_CONF_SECTION_NAME, with: userConfMappings, attaching: userData)
  }


  /// This can get called a lot for menu item bindings [by MacOS], so setting onlyIfDifferent=true can possibly cut down on redundant work.
  static func replaceMappings(forSharedSectionName: String, with mappings: [KeyMapping],
                              onlyIfDifferent: Bool = false, attaching userData: NotificationData? = nil) {
    InputSectionStack.lock.withLock {
      guard let sharedSection = sharedSectionStack.sectionsDefined[forSharedSectionName] as? SharedInputSection else { return }

      let doReplace = true

//      if onlyIfDifferent {
        // TODO: get more sophisticated than this simple check
//        let existingCount = sharedSection.keyMappingList.count
//        let newCount = mappings.count
//        let didChange = !(existingCount == 0 && newCount == 0)
//        doReplace = didChange
//        doReplace = true
//      }

      if doReplace {
        sharedSection.setKeyMappingList(mappings)
      }
      if doReplace || userData != nil {
        AppInputConfig.rebuildCurrent(attaching: userData)
      }
    }
  }

  // MARK: Other Static

  static private var lastStartedVersion: Int = 0

  /// The current instance. The app can only ever support one set of active key bindings at a time, so each time a change is made,
  /// the active bindings are rebuilt and the old set is discarded.
  static private(set) var current = AppInputConfig(version: 0, bindingCandidateList: [], resolverDict: [:], duplicateKeys: [],
                                                   userConfSectionStartIndex: 0, userConfSectionEndIndex: 0)

  /// This attempts to mimick the logic in mpv's `get_cmd_from_keys()` function in input/input.c.
  /// Rebuilds `appBindingsList` and `currentResolverDict`, updating menu item key equivalents along the way.
  /// When done, notifies the Preferences > Key Bindings table of the update so it can refresh itself, as well
  /// as notifies the other callbacks supplied here as needed.
  static func rebuildCurrent(attaching userData: NotificationData? = nil) {
    let requestedVersion = AppInputConfig.lastStartedVersion + 1
    if DebugConfig.logBindingsRebuild {
      log.verbose("Requesting AppInputConfig build v\(requestedVersion)")
    }

    DispatchQueue.main.async {
      guard !AppDelegate.shared.isTerminating else { return }

      // Optimization: drop all but the most recent request (but not if there is an attachment to deliver)
      let hasAttachedData = (userData?.count ?? 0) > 0
      if requestedVersion <= AppInputConfig.lastStartedVersion && !hasAttachedData {
        return
      }

      AppInputConfig.lastStartedVersion = requestedVersion

      let player = PlayerManager.shared.activePlayer ?? PlayerManager.shared.getOrCreateDemo()
      guard let activePlayerInputContext = player.keyBindingContext else {
        Logger.fatal("AppInputConfig.rebuildCurrent(): player has no keyBindingContext!")  // should never happen
      }

      let builder = activePlayerInputContext.makeAppInputConfigBuilder()
      let appInputConfigNew = builder.build(version: requestedVersion)

      AppInputConfig.current = appInputConfigNew

      var data = userData ?? [:]
      data[BindingTableStateManager.Key.appInputConfig] = appInputConfigNew

      let notification = Notification(name: .iinaAppInputConfigDidChange,
                                      object: nil, userInfo: data)
      if DebugConfig.logBindingsRebuild {
        log.verbose("Completed AppInputConfig v\(appInputConfigNew.version); posting notification: \(notification.name.rawValue.quoted)")
      }
      NotificationCenter.default.post(notification)
    }
  }

  // MARK: Single instance

  let version: Int

  /// The list of all bindings including those with duplicate keys. The list `allRows` of `BindingTableState` should be kept
  /// consistent with this one as much as possible, but some brief inconsistencies may be acceptable due to the asynchronous nature of UI.
  let bindingCandidateList: [InputBinding]

  /// This structure results from merging the layers of enabled input sections for the currently active player using precedence rules.
  /// Contains only the bindings which are currently enabled for this player, plus extra dummy "ignored" bindings for partial key sequences.
  /// For lookup use `resolveMpvKey()` or `matchActiveKeyBinding()` from the active player's input config.
  let resolverDict: [String: InputBinding]

  /// (Note: These two fields are used for optimizing the Key Bindings UI  but are otherwise not important.)
  /// The index into `bindingCandidateList` of the first binding in the "default" (user conf) section.
  /// • If the "default" section has no bindings, then this will be the index of the next binding after it in the list,
  /// and also equal to `userConfSectionEndIndex` (thus, userConfSectionSize = userConfSectionEndIndex - userConfSectionStartIndex = 0).
  /// • If the "default" section has no bindings *and* there are no other "strong" sections in the table, then this will be equal to the
  /// size of the list (and not a valid index for lookup)
  /// [Remember that larger index in `bindingCandidateList` signifies higher priority; all "weak" sections' bindings are placed at lower
  /// indexes than "default"; and all "strong" sections' bindings (other than default) are placed at higher indexes than "default"].
  let userConfSectionStartIndex: Int
  /// The index into `bindingCandidateList` of the last binding in the "default" section.
  /// If the "default" section has no bindings, then this will be the index of the first binding belonging to the next "strong" section,
  /// or simply `bindingCandidateList.count` if there are no sections after it.
  let userConfSectionEndIndex: Int

  var userConfSectionLength: Int {
    userConfSectionEndIndex - userConfSectionStartIndex
  }

  init(version: Int, bindingCandidateList: [InputBinding], resolverDict: [String: InputBinding], duplicateKeys: Set<String>,
       userConfSectionStartIndex: Int, userConfSectionEndIndex: Int) {
    self.version = version
    self.bindingCandidateList = bindingCandidateList
    self.resolverDict = resolverDict
    self.duplicateKeys = duplicateKeys
    self.userConfSectionStartIndex = userConfSectionStartIndex
    self.userConfSectionEndIndex = userConfSectionEndIndex
  }

  let duplicateKeys: Set<String>

  func logEnabledBindings() {
    if DebugConfig.logBindingsRebuild, Logger.enabled && Logger.Level.preferred >= .verbose {
      let bindingList = bindingCandidateList.filter({ $0.isEnabled })
      AppInputConfig.log.verbose("Currently enabled bindings (\(bindingList.count)):\n\(bindingList.map { "\t\($0)" }.joined(separator: "\n"))")
    }
  }
}
