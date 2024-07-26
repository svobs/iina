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
extension Preference {
  class UIState {
    enum LaunchStatus: Int {
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
      var status: LaunchStatus = .none
      /// Will be `nil` if the pref entry is missing
      var savedWindows: [SavedWindow]? = nil
      // each entry in the set is a pref key
      var playerKeys = Set<String>()

      init(_ launchID: Int) {
        self.id = launchID
      }

      var hasAnyData: Bool {
        return status != .none || !(savedWindows?.isEmpty ?? true) || !playerKeys.isEmpty
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
        return Preference.UIState.launchName(forID: id)
      }

      var description: String {
        return "Launch(\(id) \(statusDescription) w:\(savedWindowsDescription) p:\(playerKeys))"
      }

      var savedWindowsDescription: String {
        return savedWindows?.map{ $0.saveName.string }.description ?? "nil"
      }

      var statusDescription: String {
        switch status {
        case .none:
          return "noStatus"
        case .done:
          return "done"
        default:
          return "running(\(status.rawValue))"
        }
      }
    }


    /// Each instance of IINA, when it starts, grabs the previous launch count from the prefs and increments it by 1, which becomes its launchID.
    static let launchID: Int = {
      let nextID = Preference.integer(for: .launchCount) + 1
      Preference.set(nextID, for: .launchCount)
      return nextID
    }()

    /// The unique name for this launch, used as a pref key
    static let launchName: String = Preference.UIState.launchName(forID: launchID)

    static var windowsOpen = Set<String>()
    static var windowsHidden = Set<String>()
    static var windowsMinimized = Set<String>()

    static var openSheetsDict: [String: Set<String>] = [:]

    static func addOpenSheet(_ sheetName: String, toWindow windowName: String) {
      if var sheets = openSheetsDict[windowName] {
        sheets.insert(sheetName)
        openSheetsDict[windowName] = sheets
      } else {
        openSheetsDict[windowName] = Set<String>([sheetName])
      }
    }

    static func flattenOpenSheets() -> [String] {
      return openSheetsDict.values.reduce(Array<String>(), { arr, valSet in
        var arr = arr
        arr.append(contentsOf: valSet)
        return arr
      })
    }

    static func removeOpenSheets(fromWindow windowName: String) {
      openSheetsDict.removeValue(forKey: windowName)
    }

    static func makeOpenWindowListKey(forLaunchID launchID: Int) -> String {
      return String(format: Constants.String.openWindowListFmt, launchID)
    }

    static func launchName(forID launchID: Int) -> String {
      return "\(Constants.String.iinaLaunchPrefix)\(launchID)"
    }

    /// Example input=`"PWin-1032m0"` → output=`"1032m0"`
    static func playerID(fromPlayerWindowKey key: String) -> String? {
      if key.starts(with: WindowAutosaveName.playerWindowPrefix) {
        let splitted = key.split(separator: "-")
        if splitted.count == 2 {
          return String(splitted[1])
        }
      }
      return nil
    }

    /// Example input=`"PWin-1032m0"` → output=`"1032"`
    static func launchID(fromPlayerWindowKey key: String) -> Int? {
      if let pid = playerID(fromPlayerWindowKey: key) {
        return WindowAutosaveName.playerWindowLaunchID(from: pid)
      }
      return nil
    }

    static func launchID(fromOpenWindowListKey key: String) -> Int? {
      if key.starts(with: Constants.String.iinaLaunchPrefix) && key.hasSuffix("Windows") {
        let splitted = key.split(separator: "-")
        if splitted.count == 3 {
          return Int(splitted[1])
        }
      }
      return nil
    }

    static func launchID(fromLegacyOpenWindowListKey key: String) -> Int? {
      if key.starts(with: "OpenWindows-") {
        let splitted = key.split(separator: "-", maxSplits: 1)
        if splitted.count == 2 {
          return Int(splitted[1])
        }
      }
      return nil
    }

    static func launchID(fromLaunchName launchName: String) -> Int? {
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
    private static var disableForThisInstance = false

    static var isSaveEnabled: Bool {
      return isRestoreEnabled
    }

    static var isRestoreEnabled: Bool {
      return !disableForThisInstance && Preference.bool(for: .enableRestoreUIState)
    }

    static func disableSaveAndRestoreUntilNextLaunch() {
      disableForThisInstance = true
    }

    // Convenience method. If restoring UI state is enabled, returns the saved value; otherwise returns the saved value.
    // Note: doesn't work for enums.
    static func get<T>(_ key: Key) -> T {
      if isRestoreEnabled {
        if let val = Preference.value(for: key) as? T {
          return val
        }
      }
      return Preference.typedDefault(for: key)
    }

    // Convenience method. If saving UI state is enabled, saves the given value. Otherwise does nothing.
    static func set<T: Equatable>(_ value: T, for key: Key) {
      guard isSaveEnabled else { return }
      if let existing = Preference.object(for: key) as? T, existing == value {
        return
      }
      Preference.set(value, for: key)
    }

    /// Returns the autosave names of windows which have been saved in the set of open windows
    /// Value is a comma-separated string containing the list of open windows, back to front
    static private func getSavedOpenWindowsBackToFront(forLaunchID launchID: Int) -> [SavedWindow] {
      let key = Preference.UIState.makeOpenWindowListKey(forLaunchID: launchID)
      let windowList = parseSavedOpenWindowsBackToFront(fromPrefValue: UserDefaults.standard.string(forKey: key))
      Logger.log("Loaded list of open windows for launchID \(launchID): \(windowList.map{$0.saveName.string})", level: .verbose)
      return windowList
    }

    static private func parseSavedOpenWindowsBackToFront(fromPrefValue prefValue: String?) -> [SavedWindow] {
      let csv = prefValue?.trimmingCharacters(in: .whitespaces) ?? ""
      if csv.isEmpty {
        return []
      }
      let tokens = csv.components(separatedBy: ",").map{ $0.trimmingCharacters(in: .whitespaces)}
      return tokens.compactMap{SavedWindow($0)}
    }

    static private func getCurrentOpenWindowNames(excludingWindowName nameToExclude: String? = nil) -> [String] {
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

    static func saveCurrentOpenWindowList(excludingWindowName nameToExclude: String? = nil) {
      assert(DispatchQueue.isExecutingIn(.main))
      guard !AppDelegate.shared.isTerminating else { return }
      guard !Preference.bool(for: .isRestoreInProgress) else { return }
      let openWindowsSet = windowsOpen
      let openWindowNames = getCurrentOpenWindowNames(excludingWindowName: nameToExclude)
      // Don't care about ordering of these:
      let minimizedWindowNames = Array(windowsMinimized)
      let hiddenWindowNames = Array(windowsHidden)
      if openWindowsSet.count != openWindowNames.count {
        let errorMsg = "While saving window list: openWindowSet (\(openWindowsSet)) does not match open window list: \(openWindowNames) + Hidden=\(hiddenWindowNames) + Minimized=\(minimizedWindowNames); excluded=\(nameToExclude?.quoted ?? "nil")"
        #if DEBUG
        Utility.showAlert(errorMsg, logAlert: true)
        #else
        Logger.log(errorMsg, level: .error)
        #endif
      }
      if Logger.isTraceEnabled {
        Logger.log("Saving window list: open=\(openWindowNames), hidden=\(hiddenWindowNames), minimized=\(minimizedWindowNames)", 
                   level: .verbose)
      }
      let minimizedStrings = minimizedWindowNames.map({ "\(SavedWindow.minimizedPrefix)\($0)" })
      saveOpenWindowList(windowNamesBackToFront: minimizedStrings + hiddenWindowNames + openWindowNames,
                         forLaunchID: launchID)
      
      if UserDefaults.standard.integer(forKey: launchName) != LaunchStatus.stillRunning.rawValue {
        // The entry will be missing if the user cleared saved state but then re-enabled save in the same launch.
        // We can easily add the missing status again.
        Logger.log("Pref entry for \(launchName.quoted) was missing or incorrect. Setting it to \(LaunchStatus.stillRunning.rawValue)")
        UserDefaults.standard.setValue(LaunchStatus.stillRunning.rawValue, forKey: launchName)
      }
    }

    static private func saveOpenWindowList(windowNamesBackToFront: [String], forLaunchID launchID: Int) {
      guard isSaveEnabled else { return }
      //      Logger.log("Saving open windows: \(windowNamesBackToFront)", level: .verbose)
      let csv = windowNamesBackToFront.map{ $0 }.joined(separator: ",")
      let key = Preference.UIState.makeOpenWindowListKey(forLaunchID: launchID)

      let csvOld = UserDefaults.standard.string(forKey: key)
      guard csvOld != csv else { return }

      UserDefaults.standard.setValue(csv, forKey: key)

      NotificationCenter.default.post(Notification(name: .savedWindowStateDidChange, object: self))
    }

    static func clearSavedStateForThisLaunch(silent: Bool = false) {
      clearSavedState(forLaunchID: launchID, silent: silent)
    }

    static func clearSavedState(forLaunchName launchName: String, silent: Bool = false) {
      guard let launchID = Preference.UIState.launchID(fromLaunchName: launchName) else {
        Logger.log("Failed to parse launchID from launchName: \(launchName.quoted)", level: .error)
        return
      }
      clearSavedState(forLaunchID: launchID, silent: silent)
    }

    static func clearSavedState(forLaunchID launchID: Int, force: Bool = false, silent: Bool = false) {
      guard isSaveEnabled || force else { return }
      let launchName = Preference.UIState.launchName(forID: launchID)

      // Clear state for saved players:
      for savedWindow in getSavedOpenWindowsBackToFront(forLaunchID: launchID) {
        if let playerID = savedWindow.saveName.playerWindowID {
          Preference.UIState.clearPlayerSaveState(forPlayerID: playerID, force: force)
        }
      }

      let windowListKey = Preference.UIState.makeOpenWindowListKey(forLaunchID: launchID)
      Logger.log("Clearing saved list of open windows (pref key: \(windowListKey.quoted))")
      UserDefaults.standard.removeObject(forKey: windowListKey)

      Logger.log("Clearing saved launch (pref key: \(launchName.quoted))")
      UserDefaults.standard.removeObject(forKey: launchName)

      if !silent {
        NotificationCenter.default.post(Notification(name: .savedWindowStateDidChange, object: self))
      }
    }

    static func clearAllSavedLaunchState(force: Bool = false) {
      guard !AppDelegate.shared.isTerminating else { return }
      guard isSaveEnabled || force else {
        Logger.log("Will not clear saved UI state; UI save is disabled")
        return
      }
      let launchCount = launchID - 1
      Logger.log("Clearing all saved window states from prefs (launchCount: \(launchCount), isSavedEnabled=\(isSaveEnabled.yn) force=\(force))", level: .debug)

      /// `collectLaunchState()` will give lingering launches a chance to deny being removed
      let launchIDs: [Int] = Preference.UIState.collectLaunchState(cleanUpAlongTheWay: true).compactMap{$0.id}

      for launchID in launchIDs {
        clearSavedState(forLaunchID: launchID, force: force, silent: true)
      }

      NotificationCenter.default.post(Notification(name: .savedWindowStateDidChange, object: self))
    }

    static private func getPlayerIDs(from windowAutosaveNames: [WindowAutosaveName]) -> [String] {
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

    static func getPlayerSaveState(forPlayerID playerID: String) -> PlayerSaveState? {
      let key = WindowAutosaveName.playerWindow(id: playerID).string
      return getPlayerSaveState(forPlayerKey: key)
    }

    static func getPlayerSaveState(forPlayerKey key: String) -> PlayerSaveState? {
      guard isRestoreEnabled else { return nil }
      guard let propDict = UserDefaults.standard.dictionary(forKey: key) else {
        Logger.log("Could not find stored UI state for \(key.quoted)", level: .error)
        return nil
      }
      guard let pid = playerID(fromPlayerWindowKey: key) else {
        Logger.log("Bad player key: \(key.quoted)", level: .error)
        return nil
      }
      return PlayerSaveState(propDict, playerID: pid)
    }

    static func savePlayerState(forPlayerID playerID: String, properties: [String: Any]) {
      guard isSaveEnabled else { return }
      guard properties[PlayerSaveState.PropName.url.rawValue] != nil else {
        // This can happen if trying to save while changing tracks, or at certain brief periods during shutdown.
        // Do not save without a URL! The window cannot be restored.
        // Just assume there was already a good save made not too far back.
        Logger.log("Skipping save for player \(playerID): it has no URL", level: .debug)
        return
      }
      let key = WindowAutosaveName.playerWindow(id: playerID).string
      UserDefaults.standard.setValue(properties, forKey: key)
    }

    static func clearPlayerSaveState(forPlayerID playerID: String, force: Bool = false) {
      guard isSaveEnabled || force else { return }
      let key = WindowAutosaveName.playerWindow(id: playerID).string
      UserDefaults.standard.removeObject(forKey: key)
      Logger.log("Removed stored UI state for player \(key.quoted)", level: .verbose)
    }

    private static func launchStatus(fromAny value: Any, launchName: String) -> LaunchStatus {
      guard let statusInt = value as? Int else {
        Logger.log("Failed to parse status int from pref entry! (entry: \(launchName.quoted), value: \(value))", level: .error)
        return .none
      }
      let status = LaunchStatus(rawValue: statusInt)
      guard let status else {
        Logger.log("Status int from pref entry is invalid! (entry: \(launchName.quoted), value: \(value))", level: .error)
        return .none
      }
      return status
    }

    private static func buildLaunchDict(cleanUpAlongTheWay isCleanUpEnabled: Bool = false) -> [Int: LaunchState] {
      var countOfLaunchesToWaitOn = 0
      var launchDict: [Int: LaunchState] = [:]

      // It is easier & less bug-prone to just to iterate over all entries in the plist than to try to guess key names
      for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
        if let launchID = launchID(fromLaunchName: key) {
          // Entry is type: Launch Status
          let launch = launchDict[launchID] ?? LaunchState(launchID)
          
          launch.status = launchStatus(fromAny: value, launchName: key)
          launchDict[launchID] = launch

          if isCleanUpEnabled, launch.status != LaunchStatus.done, launchID != Preference.UIState.launchID {
            /// Launch was not marked `done`?
            /// Maybe it is done but did not exit cleanly. Send ping to see if it is still alive
            var newValue = LaunchStatus.indeterminate1
            if launch.status.rawValue < LaunchStatus.done.rawValue - 1 {
              newValue = LaunchStatus(rawValue: launch.status.rawValue + 1) ?? LaunchStatus.indeterminate2
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
            Logger.log("Copied legacy pref entry: \(key.quoted) → \(newKey)", level: .warning)
            UserDefaults.standard.removeObject(forKey: key)
            Logger.log("Deleted legacy pref entry: \(key.quoted)", level: .warning)
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
        let iffyKeys = launchDict.filter{ $0.value.id != UIState.launchID &&
          $0.value.status != Preference.UIState.LaunchStatus.done}.keys.map{$0}
        Logger.log("Looks like these launches may still be running: \(iffyKeys)", level: .verbose)
        Logger.log("Waiting 1s to see if \(countOfLaunchesToWaitOn) past launches are still running...", level: .debug)

        Thread.sleep(forTimeInterval: 1)
      }

      return launchDict
    }

    /// Returns list of "launch name" identifiers for past launches of IINA which have saved state to restore.
    /// This omits launches which are detected as still running.
    static func collectLaunchState(cleanUpAlongTheWay isCleanUpEnabled: Bool = false) -> [LaunchState] {
      let launchDict = buildLaunchDict(cleanUpAlongTheWay: isCleanUpEnabled)

      var countEntriesDeleted: Int = 0

      // Iterate backwards through past launches, from most recent to least recent.
      let launchesNewestToOldest = launchDict.values.sorted(by: { $0.id > $1.id })

      let currentBuildNumber = Int(InfoDictionary.shared.version.1)!

      for launch in launchesNewestToOldest {
        guard launch.status != LaunchStatus.none else {
          if isCleanUpEnabled {
            // Anything found here is orphaned. Clean it up.
            // Remember that we are iterating backwards, so all data should be accounted for.

            if launch.savedWindows != nil {
              let key = makeOpenWindowListKey(forLaunchID: launch.id)
              Logger.log("Deleting orphaned pref entry \(key.quoted) (value=\(launch.savedWindowsDescription))", level: .warning)
              UserDefaults.standard.removeObject(forKey: key)
              countEntriesDeleted += 1
            }

            for playerKey in launch.playerKeys {
              guard let savedState = Preference.UIState.getPlayerSaveState(forPlayerKey: playerKey) else {
                Logger.log("Skipping delete of pref key \(playerKey.quoted): could not parse as PlayerSavedState!", level: .error)
                continue
              }
              /// May want to reuse this data for different purposes in future versions. Do not blindly delete!
              /// Only delete data which is tagged with the current build or previous builds. The `buildNumber` field
              ///  was not present until the 1.2 release (buildNum 3), so assume previous release if not present.
              let buildNumber = savedState.int(for: .buildNumber) ?? 0
              guard buildNumber <= currentBuildNumber else {
                Logger.log("Skipping delete of pref key \(playerKey.quoted): its buildNumber (\(buildNumber)) > currentBuildNumber (\(currentBuildNumber))", level: .verbose)
                continue
              }

              if Logger.isEnabled(.warning) {
                let path = Playback.path(for: savedState.url(for: .url))
                Logger.log("Deleting orphaned pref entry: \(playerKey.quoted) with path \(path.quoted)",
                           level: .warning)
              }
              UserDefaults.standard.removeObject(forKey: playerKey)
              countEntriesDeleted += 1
            }
          }

          continue
        }

        // Old player windows may have been associated with newer launches. Update our data structure to match
        if let savedWindows = launch.savedWindows {
          Logger.log("\(launch.name) has saved windows: \(launch.savedWindowsDescription)", level: .verbose)
          for savedWindow in savedWindows {
            let playerLaunchID = savedWindow.saveName.playerWindowLaunchID
            if let playerLaunchID, playerLaunchID != launch.id {
              if playerLaunchID > launch.id {
                // Should only happen if someone messed up the .plist file
                Logger.log("Suspicious data found! Saved launch (\(launch.id)) contains a player window from a newer launch (\(playerLaunchID))!", level: .error)
              }

              // If player window is from a past launch, need to remove it from that launch's list so that it is not seen as orphan
              if let prevLaunch = launchDict[playerLaunchID],
                 let playerKeyFromPrev = prevLaunch.playerKeys.remove(savedWindow.saveName.string) {
                if Logger.isTraceEnabled {
                  Logger.log("Player window \(savedWindow.saveName.string) is from prior launch \(playerLaunchID) but is now part of launch \(launch.id)", level: .trace)
                }
                launch.playerKeys.insert(playerKeyFromPrev)
              }
            }
          }
        }

        if isCleanUpEnabled {
          // May have been waiting for past launches to report back their status so that we
          // can clean up improperly terminated launches. Refresh status now.
          let pastLaunchName = launchName(forID: launch.id)
          let statusInt: Int = UserDefaults.standard.integer(forKey: pastLaunchName)
          launch.status = launchStatus(fromAny: statusInt, launchName: pastLaunchName)
        }
      }

      if countEntriesDeleted > 0 {
        Logger.log("Deleted \(countEntriesDeleted) pref entries")
        NotificationCenter.default.post(Notification(name: .savedWindowStateDidChange, object: self))
      }

      let culledLaunches = launchesNewestToOldest.filter{ $0.hasAnyData }
      if Logger.isVerboseEnabled {
        Logger.log("Found saved launches (current=\(launchID)): \(culledLaunches)", level: .verbose)
      }
      return culledLaunches
    }

    static func collectLaunchStateForRestore() -> [LaunchState] {
      return collectLaunchState(cleanUpAlongTheWay: true).filter{ $0.status != .stillRunning }
    }

    /// Consolidates all player windows (& others) from any past launches which are no longer running into the windows for this instance.
    /// Updates prefs to reflect new conslidated state.
    /// Returns all window names for this launch instance, back to front.
    static func consolidateSavedWindowsFromPastLaunches(pastLaunches cachedLaunches: [LaunchState]? = nil) -> [SavedWindow] {
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
              Logger.log("Skipping duplicate open window: \(savedWindow.saveName.string.quoted)", level: .verbose)
            }
          }
        }
      }

      // First save under new window list:
      let finalWindowStringList = deduplicatedWindowList.map({$0.saveString})
      Logger.log("Consolidating windows from \(launchesNewestToOldest.count) past launches to current launch (\(launchID)): \(deduplicatedWindowList.map({$0.saveName.string}))", level: .verbose)
      saveOpenWindowList(windowNamesBackToFront: finalWindowStringList, forLaunchID: launchID)

      // Now remove entries for old launches (keeping player state entries)
      for launch in launchesNewestToOldest {
        let launchName = Preference.UIState.launchName(forID: launch.id)

        if launch.savedWindows != nil {
          let windowListKey = Preference.UIState.makeOpenWindowListKey(forLaunchID: launch.id)
          Logger.log("Clearing saved list of open windows (pref key: \(windowListKey.quoted))")
          UserDefaults.standard.removeObject(forKey: windowListKey)
        }

        if launch.status != .none {
          Logger.log("Clearing saved launch status (pref key: \(launchName.quoted))")
          UserDefaults.standard.removeObject(forKey: launchName)
        }
      }

      NotificationCenter.default.post(Notification(name: .savedWindowStateDidChange, object: self))
      return deduplicatedWindowList
    }

  }
}
