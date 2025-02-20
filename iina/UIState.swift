//
//  UIState.swift
//  iina
//
//  Created by Matt Svoboda on 8/6/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// Quick Start: find a pref editing tool like "Prefs Editor" or similar app. Filter all prefs by `Launch` & observe behavior.
///
/// Notes on performance:
/// Apple's `NSUserDefaults`, when getting & saving preference values, utilizes an in-memory cache which is very fast.
/// And although it periodically saves "dirty" values to disk, and the interval between writes is unclear, this doesn't appear to cause
/// a significant performance penalty, and certainly can't be much improved upon by IINA. Also, as playing video is by its nature very
/// data-intensive, writes to the .plist should be trivial by comparison.
class UIState {
  static let shared = UIState()

  enum LaunchLifecycleState: Int {
    case none = 0
    case stillRunning = 1
    case indeterminate1 = 2
    case indeterminate2 = 3
    case indeterminate3 = 4
    case indeterminate4 = 5
    case indeterminate5 = 6
    case indeterminate6 = 7
    case indeterminate7 = 8
    case indeterminate8 = 9
    case done = 10
  }

  class LaunchState: CustomStringConvertible {
    /// launch ID
    let id: Int
    /// `none` == pref entry missing
    var lifecycleState: LaunchLifecycleState = .none
    /// Will be `nil` if the pref entry is missing
    var savedWindows: [SavedWindow]? = nil
    // each entry in the set is a pref key
    var playerKeys = Set<String>()

    init(_ launchID: Int) {
      self.id = launchID
    }

    var hasAnyData: Bool {
      return lifecycleState != .none || !(savedWindows?.isEmpty ?? true) || !playerKeys.isEmpty
    }

    var windowCount: Int {
      return savedWindows?.count ?? 0
    }

    var playerWindowCount: Int {
      return savedWindows?.reduce(0, {count, wind in count + (wind.isPlayerWindow ? 1 : 0)}) ?? 0
    }

    var nonPlayerWindowCount: Int {
      return windowCount - playerWindowCount
    }

    var name: String {
      return UIState.launchName(forID: id)
    }

    var description: String {
      return "Launch(\(id) \(lifecycleStateDescription) w:\(savedWindowsDescription) p:\(playerKeys))"
    }

    var savedWindowsDescription: String {
      return savedWindows?.map{ $0.saveName.string }.description ?? "nil"
    }

    var lifecycleStateDescription: String {
      switch lifecycleState {
      case .none:
        return "none"
      case .done:
        return "done"
      default:
        return "running(\(lifecycleState.rawValue))"
      }
    }
  }  /// end `class LaunchState`


  let log = Logger.Subsystem.restore

  /// Each instance of IINA, when it starts, grabs the previous launch count from the prefs and increments it by 1,
  /// which becomes its launchID.
  let currentLaunchID: Int

  /// The unique name for this launch, used as a pref key
  let currentLaunchName: String

  var windowsOpen = Set<String>()
  var windowsMinimized = Set<String>()
  var openSheetsDict: [String: Set<String>] = [:]

  var cachedScreens: [UInt32: ScreenMeta] = [:]

  /// Animation configurations for opening & closing windows, by window type. Scope does not include application launch.
  ///
  /// - `.documentWindow` == zoom in effect.
  /// - `.utilityWindow` == fade effect.
  /// - `.default == .none` (?)
  ///
  /// Frequently opened windows should use `.utilityWindow` instead of `.documentWindow`, because the zoom can become dizzying.
  /// But `.utilityWindow` effect looks bad with VisualEffectViews in dark mode, so fall back to `.default` for windows with those.
  let windowOpenCloseAnimations: [WindowAutosaveName: NSWindow.AnimationBehavior] = [
    .anyPlayerWindow : .documentWindow,
    .inspector : .documentWindow,
    .videoFilter : .documentWindow,
    .audioFilter : .documentWindow,
    .openURL : .default,
    .openFile : .default,
    .playbackHistory : .utilityWindow,
    .welcome : .default,
    .guide : .documentWindow,
    .logViewer : .utilityWindow,
    .preferences : .default,
  ]

  init() {
    let nextID = Preference.integer(for: .launchCount) + 1
    Preference.set(nextID, for: .launchCount)
    currentLaunchID = nextID
    currentLaunchName = UIState.launchName(forID: nextID)
    updateCachedScreens()
  }

  func updateCachedScreens() {
    let newScreenMap = NSScreen.screens.map{ScreenMeta.from($0)}.reduce(Dictionary<UInt32, ScreenMeta>(), {(dict, screenMeta) in
      var dict = dict
      dict[screenMeta.displayID] = screenMeta
      _ = Logger.getOrCreatePII(for: screenMeta.name)
      return dict
    })

    // Update the cached value
    cachedScreens = newScreenMap
  }

  /// See comments in `AppDelegqate.windowWillBeginSheet`
  func addOpenSheet(_ sheetName: String, toWindow windowName: String) {
    if var sheets = openSheetsDict[windowName] {
      sheets.insert(sheetName)
      openSheetsDict[windowName] = sheets
    } else {
      openSheetsDict[windowName] = Set<String>([sheetName])
    }
  }

  func flattenOpenSheets() -> [String] {
    return openSheetsDict.values.reduce(Array<String>(), { arr, valSet in
      var arr = arr
      arr.append(contentsOf: valSet)
      return arr
    })
  }

  func removeOpenSheets(fromWindow windowName: String) {
    openSheetsDict.removeValue(forKey: windowName)
  }

  func makeOpenWindowListKey(forLaunchID launchID: Int) -> String {
    return String(format: Constants.String.openWindowListFmt, launchID)
  }

  static func launchName(forID launchID: Int) -> String {
    return "\(Constants.String.iinaLaunchPrefix)\(launchID)"
  }

  /// Example input=`"PWin-1032c0"` → output=`"1032c0"`
  func playerID(fromPlayerWindowKey key: String) -> String? {
    if key.starts(with: WindowAutosaveName.playerWindowPrefix) {
      let splitted = key.split(separator: "-")
      if splitted.count == 2 {
        return String(splitted[1])
      }
    }
    return nil
  }

  /// Example input=`"PWin-1032c0"` → output=`"1032"`
  func launchID(fromPlayerWindowKey key: String) -> Int? {
    if let pid = playerID(fromPlayerWindowKey: key) {
      return WindowAutosaveName.playerWindowLaunchID(from: pid)
    }
    return nil
  }

  func launchID(fromOpenWindowListKey key: String) -> Int? {
    if key.starts(with: Constants.String.iinaLaunchPrefix) && key.hasSuffix("Windows") {
      let splitted = key.split(separator: "-")
      if splitted.count == 3 {
        return Int(splitted[1])
      }
    }
    return nil
  }

  func launchID(fromLegacyOpenWindowListKey key: String) -> Int? {
    if key.starts(with: "OpenWindows-") {
      let splitted = key.split(separator: "-", maxSplits: 1)
      if splitted.count == 2 {
        return Int(splitted[1])
      }
    }
    return nil
  }

  func launchID(fromLaunchName launchName: String) -> Int? {
    if launchName.starts(with: Constants.String.iinaLaunchPrefix) {
      let splitted = launchName.split(separator: "-")
      if splitted.count == 2 {
        return Int(splitted[1])
      }
    }
    return nil
  }

  /// This value, when set to true, disables state loading & saving for the remaining lifetime of this instance of IINA
  /// (overriding any user settings); calls to `set()` will not be saved for the next launch, and any new get() requests
  /// will return the default values.
  private var disableForThisInstance = false

  var isSaveEnabled: Bool {
    return isRestoreEnabled
  }

  var isRestoreEnabled: Bool {
    return !disableForThisInstance && Preference.bool(for: .enableRestoreUIState)
  }

  func disableSaveAndRestoreUntilNextLaunch() {
    disableForThisInstance = true
  }

  // Convenience method. If restoring UI state is enabled, returns the saved value; otherwise returns the saved value.
  // Note: doesn't work for enums.
  func getSavedValue<T>(for key: Preference.Key) -> T {
    if isRestoreEnabled {
      if let val = Preference.value(for: key) as? T {
        return val
      }
    }
    return Preference.typedDefault(for: key)
  }

  // Convenience method. If saving UI state is enabled, saves the given value. Otherwise does nothing.
  func set<T: Equatable>(_ value: T, for key: Preference.Key) {
    guard isSaveEnabled else { return }
    if let existing = Preference.object(for: key) as? T, existing == value {
      return
    }
    Preference.set(value, for: key)
  }

  /// Returns the autosave names of windows which have been saved in the set of open windows
  /// Value is a comma-separated string containing the list of open windows, back to front
  private func getSavedOpenWindowsBackToFront(forLaunchID launchID: Int) -> [SavedWindow] {
    let key = makeOpenWindowListKey(forLaunchID: launchID)
    let windowList = parseSavedOpenWindowsBackToFront(fromPrefValue: UserDefaults.standard.string(forKey: key))
    log.verbose("Loaded list of open windows for launchID \(launchID): \(windowList.map{$0.saveName.string})")
    return windowList
  }

  private func parseSavedOpenWindowsBackToFront(fromPrefValue prefValue: String?) -> [SavedWindow] {
    let csv = prefValue?.trimmingCharacters(in: .whitespaces) ?? ""
    if csv.isEmpty {
      return []
    }
    let tokens = csv.components(separatedBy: ",").map{ $0.trimmingCharacters(in: .whitespaces)}
    return tokens.compactMap{SavedWindow($0)}
  }

  private func getCurrentOpenWindowNames(excludingWindowName nameToExclude: String? = nil) -> [String] {
    var orderNamePairs: [(Int, String)] = []
    for window in NSApp.windows {
      let name = window.savedStateName
      /// `isVisible` here includes windows which are obscured or off-screen, but excludes ordered out or minimized
      if !name.isEmpty && window.isVisible {
        guard name != nameToExclude else {
          continue
        }
        orderNamePairs.append((window.orderedIndex, name))
      }
    }
    /// Sort windows in increasing `orderedIndex` (from back to front):
    return orderNamePairs.sorted(by: { (left, right) in left.0 > right.0}).map{ $0.1 }
  }

  func saveCurrentOpenWindowList(excludingWindowName nameToExclude: String? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard !AppDelegate.shared.isTerminating else { return }
    guard !Preference.bool(for: .isRestoreInProgress) else { return }
    var openWindowsSet = windowsOpen
    var openWindowNames = getCurrentOpenWindowNames(excludingWindowName: nameToExclude)
    // Don't care about ordering of these:
    let minimizedWindowNames = Array(windowsMinimized)

    if openWindowsSet.count != openWindowNames.count {
      for windName in openWindowNames {
        openWindowsSet.remove(windName)
      }
      // Add missing windows to end of list (front):
      log.verbose{"Assuming windows are still opening; appending \(openWindowsSet) to saved windows list: \(openWindowNames)"}
      for windName in openWindowsSet {
        openWindowNames.append(windName)
      }
    }
    log.trace{"Saving window list: open=\(openWindowNames), minimized=\(minimizedWindowNames)"}
    let minimizedStrings = minimizedWindowNames.map({ "\(SavedWindow.minimizedPrefix)\($0)" })
    saveOpenWindowList(windowNamesBackToFront: minimizedStrings + openWindowNames)

    if UserDefaults.standard.integer(forKey: currentLaunchName) != LaunchLifecycleState.stillRunning.rawValue {
      // The entry will be missing if the user cleared saved state but then re-enabled save in the same launch.
      // We can easily add the missing lifecycleState again.
      log.debug{"Pref entry for \(currentLaunchName.quoted) was missing or incorrect. Setting it to \(LaunchLifecycleState.stillRunning.rawValue)"}
      UserDefaults.standard.setValue(LaunchLifecycleState.stillRunning.rawValue, forKey: currentLaunchName)
    }
  }

  private func saveOpenWindowList(windowNamesBackToFront: [String]) {
    guard isSaveEnabled else { return }
    //      log.verbose("Saving open windows: \(windowNamesBackToFront)")
    let csv = windowNamesBackToFront.map{ $0 }.joined(separator: ",")
    let key = makeOpenWindowListKey(forLaunchID: currentLaunchID)

    let csvOld = UserDefaults.standard.string(forKey: key)
    guard csvOld != csv else { return }

    UserDefaults.standard.setValue(csv, forKey: key)
    postSavedWindowStateDidChange()
  }

  private func postSavedWindowStateDidChange() {
    DispatchQueue.main.async { [self] in
      guard !AppDelegate.shared.isTerminating else { return }
      NotificationCenter.default.post(Notification(name: .savedWindowStateDidChange, object: self))
    }
  }

  func clearSavedLaunchForThisLaunch(silent: Bool = false) {
    clearSavedLaunch(launchID: currentLaunchID, silent: silent)
  }

  func clearSavedLaunch(withName launchName: String, silent: Bool = false) {
    guard let launchID = launchID(fromLaunchName: launchName) else {
      log.error("Failed to parse launchID from launchName: \(launchName.quoted)")
      return
    }
    clearSavedLaunch(launchID: launchID, silent: silent)
  }

  func clearSavedLaunch(launchID: Int, force: Bool = false, silent: Bool = false) {
    guard isSaveEnabled || force else { return }
    let launchName = UIState.launchName(forID: launchID)

    // Clear state for saved players:
    for savedWindow in getSavedOpenWindowsBackToFront(forLaunchID: launchID) {
      if let playerID = savedWindow.saveName.playerWindowID {
        clearPlayerSaveState(forPlayerID: playerID, force: force)
      }
    }

    let windowListKey = makeOpenWindowListKey(forLaunchID: launchID)
    log.debug("Clearing saved list of open windows (pref key: \(windowListKey.quoted))")
    UserDefaults.standard.removeObject(forKey: windowListKey)

    log.debug("Clearing saved launch (pref key: \(launchName.quoted))")
    UserDefaults.standard.removeObject(forKey: launchName)

    if !silent {
      postSavedWindowStateDidChange()
    }
  }

  func clearAllSavedLaunches(force: Bool = false) {
    guard !AppDelegate.shared.isTerminating else { return }
    guard isSaveEnabled || force else {
      log.debug("Will not clear saved UI state; UI save is disabled")
      return
    }
    let launchCount = currentLaunchID - 1
    log.debug("Clearing all saved window states from prefs (launchCount: \(launchCount), isSavedEnabled=\(isSaveEnabled.yn) force=\(force))")

    /// `collectLaunchState()` will give lingering launches a chance to deny being removed
    let launchIDs: [Int] = collectLaunchState(cleanUpAlongTheWay: true).compactMap{$0.id}

    for launchID in launchIDs {
      clearSavedLaunch(launchID: launchID, force: force, silent: true)
    }

    postSavedWindowStateDidChange()
  }

  private func getPlayerIDs(from windowAutosaveNames: [WindowAutosaveName]) -> [String] {
    var ids: [String] = []
    for windowName in windowAutosaveNames {
      switch windowName {
      case WindowAutosaveName.playerWindow(let id):
        ids.append(id)
      default:
        break
      }
    }
    return ids
  }

  func getPlayerSaveState(forPlayerID playerID: String) -> PlayerSaveState? {
    let key = WindowAutosaveName.playerWindow(id: playerID).string
    return getPlayerSaveState(forPlayerKey: key)
  }

  func getPlayerSaveState(forPlayerKey key: String) -> PlayerSaveState? {
    guard isRestoreEnabled else { return nil }
    guard let propDict = UserDefaults.standard.dictionary(forKey: key) else {
      log.error("Could not find stored UI state for \(key.quoted)")
      return nil
    }
    guard let pid = playerID(fromPlayerWindowKey: key) else {
      log.error("Bad player key: \(key.quoted)")
      return nil
    }
    return PlayerSaveState(propDict, playerID: pid)
  }

  func saveState(forPlayerID playerID: String, properties: [String: Any]) {
    guard isSaveEnabled else { return }
    guard properties[PlayerSaveState.PropName.url.rawValue] != nil else {
      // This can happen if trying to save while changing tracks, or at certain brief periods during shutdown.
      // Do not save without a URL! The window cannot be restored.
      // Just assume there was already a good save made not too far back.
      log.debug("Skipping save for player \(playerID): it has no URL")
      return
    }
    let key = WindowAutosaveName.playerWindow(id: playerID).string
    UserDefaults.standard.setValue(properties, forKey: key)
  }

  func clearPlayerSaveState(forPlayerID playerID: String, force: Bool = false) {
    guard isSaveEnabled || force else { return }
    let key = WindowAutosaveName.playerWindow(id: playerID).string
    UserDefaults.standard.removeObject(forKey: key)
    log.verbose("Removed stored UI state for player \(key.quoted)")
  }

  private func launchStatus(fromAny value: Any, launchName: String) -> LaunchLifecycleState {
    guard let lifecycleStateInt = value as? Int else {
      log.error("Failed to parse lifecycleState int from pref entry! (entry: \(launchName.quoted), value: \(value))")
      return .none
    }
    let lifecycleState = LaunchLifecycleState(rawValue: lifecycleStateInt)
    guard let lifecycleState else {
      log.error("Status int from pref entry is invalid! (entry: \(launchName.quoted), value: \(value))")
      return .none
    }
    return lifecycleState
  }

  private func buildLaunchDict(cleanUpAlongTheWay isCleanUpEnabled: Bool = false) -> [Int: LaunchState] {
    var countOfLaunchesToWaitOn = 0
    var launchDict: [Int: LaunchState] = [:]

    let thisLaunchID = UIState.shared.currentLaunchID
    // It is easier & less bug-prone to just to iterate over all entries in the plist than to try to guess key names
    for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
      if let launchID = launchID(fromLaunchName: key) {
        // Entry is type: Launch Status
        let launch = launchDict[launchID] ?? LaunchState(launchID)

        launch.lifecycleState = launchStatus(fromAny: value, launchName: key)
        launchDict[launchID] = launch

        if isCleanUpEnabled, launch.lifecycleState != LaunchLifecycleState.done, launchID != thisLaunchID {
          /// Launch was not marked `done`?
          /// Maybe it is done but did not exit cleanly. Send ping to see if it is still alive
          var newValue = LaunchLifecycleState.indeterminate1
          if launch.lifecycleState.rawValue < LaunchLifecycleState.done.rawValue - 1 {
            newValue = LaunchLifecycleState(rawValue: launch.lifecycleState.rawValue + 1) ?? LaunchLifecycleState.indeterminate2
          }
          UserDefaults.standard.setValue(newValue.rawValue, forKey: key)
          countOfLaunchesToWaitOn += 1
        }

      } else if let launchID = launchID(fromPlayerWindowKey: key) {
        // Entry is type: PlayerWindow
        let launch = launchDict[launchID] ?? LaunchState(launchID)

        launch.playerKeys.insert(key)
        launchDict[launchID] = launch

      } else if let launchID = launchID(fromLegacyOpenWindowListKey: key) {
        // Entry is type: Open Windows List (legacy)
        let launch = launchDict[launchID] ?? LaunchState(launchID)

        // Do same logic as for modern entry:
        if let csv = value as? String {
          launch.savedWindows = parseSavedOpenWindowsBackToFront(fromPrefValue: csv)
        }
        launchDict[launchID] = launch

        if isCleanUpEnabled {
          // Now migrate legacy key
          let newKey = makeOpenWindowListKey(forLaunchID: launch.id)
          UserDefaults.standard.setValue(value, forKey: newKey)
          log.warn("Copied legacy pref entry: \(key.quoted) → \(newKey)")
          UserDefaults.standard.removeObject(forKey: key)
          log.warn("Deleted legacy pref entry: \(key.quoted)")
        }

      } else if let launchID = launchID(fromOpenWindowListKey: key) {
        // Entry is type: Open Windows List
        let launch = launchDict[launchID] ?? LaunchState(launchID)

        if let csv = value as? String {
          launch.savedWindows = parseSavedOpenWindowsBackToFront(fromPrefValue: csv)
        }
        launchDict[launchID] = launch
      }
    }

    if countOfLaunchesToWaitOn > 0 {
      let iffyKeys = launchDict.filter{ $0.value.id != currentLaunchID &&
        $0.value.lifecycleState != UIState.LaunchLifecycleState.done}.keys.map{$0}
      log.verbose("Looks like these launches may still be running: \(iffyKeys)")
      log.debug("Waiting 1s to see if \(countOfLaunchesToWaitOn) past launches are still running...")

      Thread.sleep(forTimeInterval: 1)
    }

    return launchDict
  }

  /// Returns list of "launch name" identifiers for past launches of IINA which have saved state to restore.
  /// This omits launches which are detected as still running.
  func collectLaunchState(cleanUpAlongTheWay isCleanUpEnabled: Bool = false) -> [LaunchState] {
    let launchDict = buildLaunchDict(cleanUpAlongTheWay: isCleanUpEnabled)

    var countEntriesDeleted: Int = 0

    // Iterate backwards through past launches, from most recent to least recent.
    let launchesNewestToOldest = launchDict.values.sorted(by: { $0.id > $1.id })

    let currentBuildNumber = Int(InfoDictionary.shared.version.1)!

    for launch in launchesNewestToOldest {
      guard launch.lifecycleState != LaunchLifecycleState.none else {
        if isCleanUpEnabled {
          // Anything found here is orphaned. Clean it up.
          // Remember that we are iterating backwards, so all data should be accounted for.

          if launch.savedWindows != nil {
            let key = makeOpenWindowListKey(forLaunchID: launch.id)
            log.warn("Deleting orphaned pref entry \(key.quoted) (value=\(launch.savedWindowsDescription))")
            UserDefaults.standard.removeObject(forKey: key)
            countEntriesDeleted += 1
          }

          for playerKey in launch.playerKeys {
            guard let savedState = getPlayerSaveState(forPlayerKey: playerKey) else {
              log.error("Skipping delete of pref key \(playerKey.quoted): could not parse as PlayerSavedState!")
              continue
            }
            /// May want to reuse this data for different purposes in future versions. Do not blindly delete!
            /// Only delete data which is tagged with the current build or previous builds. The `buildNumber` field
            ///  was not present until the 1.2 release (buildNum 3), so assume previous release if not present.
            let buildNumber = savedState.int(for: .buildNumber) ?? 0
            guard buildNumber <= currentBuildNumber else {
              log.verbose("Skipping delete of pref key \(playerKey.quoted): its buildNumber (\(buildNumber)) > currentBuildNumber (\(currentBuildNumber))")
              continue
            }

            if Logger.isEnabled(.warning) {
              let path = Playback.path(from: savedState.url(for: .url))
              log.warn("Deleting orphaned pref entry: \(playerKey.quoted) with path \(path.quoted)")
            }
            UserDefaults.standard.removeObject(forKey: playerKey)
            countEntriesDeleted += 1
          }
        }

        continue
      }

      // Old player windows may have been associated with newer launches. Update our data structure to match
      if let savedWindows = launch.savedWindows {
        log.verbose("\(launch.name) has saved windows: \(launch.savedWindowsDescription)")
        for savedWindow in savedWindows {
          let playerLaunchID = savedWindow.saveName.playerWindowLaunchID
          if let playerLaunchID, playerLaunchID != launch.id {
            if playerLaunchID > launch.id {
              // Should only happen if someone messed up the .plist file
              log.error("Suspicious data found! Saved launch (\(launch.id)) contains a player window from a newer launch (\(playerLaunchID))!")
            }

            // If player window is from a past launch, need to remove it from that launch's list so that it is not seen as orphan
            if let prevLaunch = launchDict[playerLaunchID],
               let playerKeyFromPrev = prevLaunch.playerKeys.remove(savedWindow.saveName.string) {
              log.trace{"Player window \(savedWindow.saveName.string) is from prior launch \(playerLaunchID) but is now part of launch \(launch.id)"}
              launch.playerKeys.insert(playerKeyFromPrev)
            }
          }
        }
      }

      if isCleanUpEnabled {
        // May have been waiting for past launches to report back their lifecycleState so that we
        // can clean up improperly terminated launches. Refresh lifecycleState now.
        let pastLaunchName = UIState.launchName(forID: launch.id)
        let lifecycleStateInt: Int = UserDefaults.standard.integer(forKey: pastLaunchName)
        launch.lifecycleState = launchStatus(fromAny: lifecycleStateInt, launchName: pastLaunchName)
      }
    }

    if countEntriesDeleted > 0 {
      log.debug("Deleted \(countEntriesDeleted) pref entries")
      postSavedWindowStateDidChange()
    }

    let culledLaunches = launchesNewestToOldest.filter{ $0.hasAnyData }
    log.verbose{"Found saved launches (current=\(currentLaunchID)): \(culledLaunches)"}
    return culledLaunches
  }

  func collectLaunchStateForRestore() -> [LaunchState] {
    return collectLaunchState(cleanUpAlongTheWay: true).filter{ $0.lifecycleState != .stillRunning }
  }

  /// Consolidates all player windows (& others) from any past launches which are no longer running into the windows for this instance.
  /// Updates prefs to reflect new conslidated state.
  /// Returns all window names for this launch instance, back to front.
  func consolidateSavedWindowsFromPastLaunches(pastLaunches cachedLaunches: [LaunchState]? = nil) -> [SavedWindow] {
    // Could have been a long time since data was last collected. Get a fresh set of data:
    let launchesNewestToOldest = cachedLaunches ?? collectLaunchStateForRestore()

    // Remove duplicates, favoring front-most copies
    var deduplicatedWindowList: [SavedWindow] = []
    var nameSet = Set<String>()
    for launch in launchesNewestToOldest {
      if let savedWindows = launch.savedWindows {
        for savedWindow in savedWindows {
          if !nameSet.contains(savedWindow.saveName.string) {
            deduplicatedWindowList.append(savedWindow)
            nameSet.insert(savedWindow.saveName.string)
          } else {
            log.verbose("Skipping duplicate open window: \(savedWindow.saveName.string.quoted)")
          }
        }
      }
    }

    // First save under new window list:
    let finalWindowStringList = deduplicatedWindowList.map({$0.saveString})
    log.verbose("Consolidating windows from \(launchesNewestToOldest.count) past launches to current launch (\(currentLaunchID)): \(deduplicatedWindowList.map({$0.saveName.string}))")
    saveOpenWindowList(windowNamesBackToFront: finalWindowStringList)

    // Now remove entries for old launches (keeping player state entries)
    for launch in launchesNewestToOldest {
      let launchName = UIState.launchName(forID: launch.id)

      if launch.savedWindows != nil {
        let windowListKey = makeOpenWindowListKey(forLaunchID: launch.id)
        log.debug("Clearing saved list of open windows (pref key: \(windowListKey.quoted))")
        UserDefaults.standard.removeObject(forKey: windowListKey)
      }

      if launch.lifecycleState != .none {
        log.debug("Clearing saved launch lifecycleState (pref key: \(launchName.quoted))")
        UserDefaults.standard.removeObject(forKey: launchName)
      }
    }

    postSavedWindowStateDidChange()
    return deduplicatedWindowList
  }
}
