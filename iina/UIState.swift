//
//  UIState.swift
//  iina
//
//  Created by Matt Svoboda on 8/6/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// Notes on performance:
/// Apple's `NSUserDefaults`, when getting & saving preference values, utilizes an in-memory cache which is very fast.
/// And although it periodically saves "dirty" values to disk, and the interval between writes is unclear, this doesn't appear to cause
/// a significant performance penalty, and certainly can't be much improved upon by IINA. Also, as playing video is by its nature very
/// data-intensive, writes to the .plist should be trivial by comparison.
extension Preference {
  class UIState {
    class LaunchStatus {
      static let none: Int = 0
      static let stillRunning: Int = 1
      static let indeterminate1: Int = 2
      static let indeterminate2: Int = 3
      static let done: Int = 10
    }

    class LaunchState: CustomStringConvertible {
      /// launch ID
      let id: Int
      /// `none` == pref entry missing
      var status: Int = LaunchStatus.none
      /// Will be `nil` if the pref entry is missing
      var savedWindows: [SavedWindow]? = nil
      // each entry in the set is a pref key
      var playerKeys = Set<String>()

      init(_ launchID: Int) {
        self.id = launchID
      }

      var description: String {
        return "Launch(\(id) \(statusDescription) w:\(savedWindowsDescription) p:\(playerKeys))"
      }

      var savedWindowsDescription: String {
        return savedWindows?.map{ $0.saveName.string }.description ?? "nil"
      }

      var statusDescription: String {
        switch status {
        case 0:
          return "noStatus"
        case 10:
          return "done"
        case 1...9:
          return "notDone(\(status))"
        default:
          return "INVALID(\(status))"
        }
      }
    }

    static private let iinaLaunchPrefix = "Launch-"
    // Comma-separated list of open windows, back to front
    static private let openWindowListPrefix = "OpenWindows-"

    static func makeOpenWindowListKey(forLaunchID launchID: Int) -> String {
      return "\(Preference.UIState.openWindowListPrefix)\(launchID)"
    }

    static func launchName(forID launchID: Int) -> String {
      return "\(Preference.UIState.iinaLaunchPrefix)\(launchID)"
    }

    static func launchID(fromPlayerWindowKey key: String) -> Int? {
      if key.starts(with: WindowAutosaveName.playerWindowPrefix) {
        let splitted = key.split(separator: "-", maxSplits: 1)
        if splitted.count == 2 {
          let playerWindowID = String(splitted[1])
          return WindowAutosaveName.playerWindowLaunchID(from: playerWindowID)
        }
      }
      return nil
    }

    static func launchID(fromOpenWindowListKey key: String) -> Int? {
      if key.starts(with: openWindowListPrefix) {
        let splitted = key.split(separator: "-", maxSplits: 1)
        if splitted.count == 2 {
          return Int(splitted[1])
        }
      }
      return nil
    }

    static func launchID(fromLaunchName launchName: String) -> Int? {
      if launchName.starts(with: iinaLaunchPrefix) {
        let splitted = launchName.split(separator: "-", maxSplits: 1)
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

    // Returns the autosave names of windows which have been saved in the set of open windows
    static private func getSavedOpenWindowsBackToFront(forLaunchID launchID: Int) -> [SavedWindow] {
      guard isRestoreEnabled else {
        Logger.log("UI restore disabled. Returning empty open window list")
        return []
      }

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
          if let nameToExclude = nameToExclude, nameToExclude == name {
            continue
          }
          orderNamePairs.append((window.orderedIndex, name))
        }
      }
      /// Sort windows in increasing `orderedIndex` (from back to front):
      return orderNamePairs.sorted(by: { (left, right) in left.0 > right.0}).map{ $0.1 }
    }

    static func saveCurrentOpenWindowList(excludingWindowName nameToExclude: String? = nil) {
      guard !AppDelegate.shared.isTerminating else { return }
      let openWindowNames = getCurrentOpenWindowNames(excludingWindowName: nameToExclude)
      let minimizedWindowNames = Array(AppDelegate.windowsMinimized)
      let hiddenWindowNames = Array(AppDelegate.windowsHidden)
      if Logger.isTraceEnabled {
        Logger.log("Saving window list: open=\(openWindowNames), hidden=\(hiddenWindowNames), minimized=\(minimizedWindowNames)", level: .verbose)
      }
      let minimizedStrings = minimizedWindowNames.map({ "\(SavedWindow.minimizedPrefix)\($0)" })
      saveOpenWindowList(windowNamesBackToFront: minimizedStrings + hiddenWindowNames + openWindowNames, forLaunchID: AppDelegate.launchID)
    }

    static private func saveOpenWindowList(windowNamesBackToFront: [String], forLaunchID launchID: Int) {
      guard isSaveEnabled else { return }
      //      Logger.log("Saving open windows: \(windowNamesBackToFront)", level: .verbose)
      let csv = windowNamesBackToFront.map{ $0 }.joined(separator: ",")
      let key = Preference.UIState.makeOpenWindowListKey(forLaunchID: launchID)

      UserDefaults.standard.setValue(csv, forKey: key)
    }

    static func clearSavedStateForThisLaunch() {
      clearSavedState(forLaunchID: AppDelegate.launchID)
    }

    static func clearSavedState(forLaunchName launchName: String) {
      guard let launchID = Preference.UIState.launchID(fromLaunchName: launchName) else {
        Logger.log("Failed to parse launchID from launchName: \(launchName.quoted)", level: .error)
        return
      }
      clearSavedState(forLaunchID: launchID)
    }

    static func clearSavedState(forLaunchID launchID: Int) {
      let launchName = Preference.UIState.launchName(forID: launchID)

      // Clear state for saved players:
      for savedWindow in getSavedOpenWindowsBackToFront(forLaunchID: launchID) {
        if let playerID = savedWindow.saveName.playerWindowID {
          Preference.UIState.clearPlayerSaveState(forPlayerID: playerID)
        }
      }

      let windowListKey = Preference.UIState.makeOpenWindowListKey(forLaunchID: launchID)
      Logger.log("Clearing saved list of open windows (pref key: \(windowListKey.quoted))")
      UserDefaults.standard.removeObject(forKey: windowListKey)

      Logger.log("Clearing saved launch (pref key: \(launchName.quoted))")
      UserDefaults.standard.removeObject(forKey: launchName)
    }

    static func clearAllSavedLaunchState(extraClean: Bool = false) {
      guard !AppDelegate.shared.isTerminating else { return }
      guard isSaveEnabled else {
        Logger.log("Will not clear saved UI state; UI save is disabled")
        return
      }
      let launchCount = AppDelegate.launchID - 1
      Logger.log("Clearing all saved window states from prefs (launchCount: \(launchCount), extraClean: \(extraClean.yn))", level: .debug)

      let launchIDs: [Int]
      if extraClean {
        // ExtraClean: May take a while, but should clean up any ophans
        launchIDs = [Int](0..<launchCount)
      } else {
        /// `collectPastLaunches()` will give lingering launches a chance to deny being removed
        launchIDs = Preference.UIState.collectPastLaunches().compactMap({Preference.UIState.launchID(fromLaunchName: $0)})
      }

      for launchID in launchIDs {
        clearSavedState(forLaunchID: launchID)
      }

      clearSavedStateForThisLaunch()
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
      guard isRestoreEnabled else { return nil }
      let key = WindowAutosaveName.playerWindow(id: playerID).string
      guard let propDict = UserDefaults.standard.dictionary(forKey: key) else {
        Logger.log("Could not find stored UI state for \(key.quoted)", level: .error)
        return nil
      }
      return PlayerSaveState(propDict)
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

    static func clearPlayerSaveState(forPlayerID playerID: String) {
      let key = WindowAutosaveName.playerWindow(id: playerID).string
      UserDefaults.standard.removeObject(forKey: key)
      Logger.log("Removed stored UI state for player \(key.quoted)", level: .verbose)
    }

    private static func buildPastLaunchDict() -> [Int: LaunchState] {
      var countOfLaunchesToWaitOn = 0
      var launchDict: [Int: LaunchState] = [:]

      // It is easier & less bug-prone to just to iterate over all entries in the plist than to try to guess key names
      for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
        if let launchID = launchID(fromLaunchName: key) {
          // Entry is type: Launch Status
          guard launchID != AppDelegate.launchID else { continue }
          let launch = launchDict[launchID] ?? LaunchState(launchID)

          guard let statusInt = value as? Int else {
            Logger.log("Failed to parse status int from pref entry! (entry: \(key.quoted), value: \(value))", level: .error)
            continue
          }
          launch.status = statusInt
          launchDict[launchID] = launch

          if launch.status != LaunchStatus.done {
            /// Launch was not marked `done`?
            /// Maybe it is done but did not exit cleanly. Send ping to see if it is still alive
            var newValue = LaunchStatus.indeterminate1
            if launch.status == LaunchStatus.indeterminate1 {
              newValue = LaunchStatus.indeterminate2
            }
            UserDefaults.standard.setValue(newValue, forKey: key)
            countOfLaunchesToWaitOn += 1
          }
        } else if let launchID = launchID(fromPlayerWindowKey: key) {
          // Entry is type: PlayerWindow
          guard launchID != AppDelegate.launchID else { continue }
          let launch = launchDict[launchID] ?? LaunchState(launchID)

          launch.playerKeys.insert(key)
          launchDict[launchID] = launch
        } else if let launchID = launchID(fromOpenWindowListKey: key) {
          // Entry is type: Open Windows List
          guard launchID != AppDelegate.launchID else { continue }
          let launch = launchDict[launchID] ?? LaunchState(launchID)

          if let csv = value as? String {
            launch.savedWindows = parseSavedOpenWindowsBackToFront(fromPrefValue: csv)
          }
          launchDict[launchID] = launch
        }
      }

      if countOfLaunchesToWaitOn > 0 {
        let iffyKeys = launchDict.filter{
          $0.value.status != Preference.UIState.LaunchStatus.done}.keys.map{$0}
        Logger.log("Looks like these launches may not be done: \(iffyKeys)", level: .verbose)
        Logger.log("Waiting 1s to see if \(countOfLaunchesToWaitOn) past instances are still running...", level: .verbose)

        Thread.sleep(forTimeInterval: 1)
      }

      return launchDict
    }

    /// Returns list of "launch name" identifiers for past launches of IINA which have saved state to restore.
    /// This omits launches which are detected as still running.
    static func collectPastLaunches() -> [String] {
      let launchDict = buildPastLaunchDict()

      var countEntriesDeleted: Int = 0
      var pastLaunchesToRestore: [String] = []

      // Iterate backwards through past launches, from most recent to least recent.
      let launchesNewestToOldest = launchDict.values.sorted(by: { $0.id > $1.id })
      if Logger.isVerboseEnabled {
        Logger.log("PastLaunchData: \(launchesNewestToOldest)", level: .verbose)
      }

      for launch in launchesNewestToOldest {
        guard launch.status != LaunchStatus.none else {
          // Anything found here is orphaned. Clean it up.
          // Remember that we are iterating backwards, so all data should be accounted for.

          if launch.savedWindows != nil {
            let key = makeOpenWindowListKey(forLaunchID: launch.id)
            Logger.log("Deleting orphaned pref entry: \(key.quoted)", level: .warning)
            UserDefaults.standard.removeObject(forKey: key)
            countEntriesDeleted += 1
          }

          for playerKey in launch.playerKeys {
            Logger.log("Deleting orphaned pref entry: \(playerKey.quoted)", level: .warning)
            UserDefaults.standard.removeObject(forKey: playerKey)
            countEntriesDeleted += 1
          }

          continue
        }

        // Old player windows may have been associated with newer launches. Update our data structure to match
        if let savedWindows = launch.savedWindows {
          Logger.log("LaunchID \(launch.id) has saved windows: \(launch.savedWindowsDescription)", level: .verbose)
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
                Logger.log("Player window \(savedWindow.saveName.string) is from prior launch \(playerLaunchID)", level: .verbose)
                launch.playerKeys.insert(playerKeyFromPrev)
              }
            }
          }
        }

        let pastLaunchName = launchName(forID: launch.id)
        let launchStatus: Int = UserDefaults.standard.integer(forKey: pastLaunchName)
        launch.status = launchStatus
        if launchStatus == Preference.UIState.LaunchStatus.stillRunning {
          Logger.log("Still running, will ignore: \(pastLaunchName.quoted)", level: .verbose)
        } else {
          if launchStatus != Preference.UIState.LaunchStatus.done {
            Logger.log("Looks defunct, will merge into current (\(AppDelegate.launchName)): \(launch)", level: .verbose)
          }
          pastLaunchesToRestore.append(pastLaunchName)
        }
      }

      if countEntriesDeleted > 0 {
        Logger.log("Deleted \(countEntriesDeleted) pref entries")
      }

      return pastLaunchesToRestore
    }

    /// Consolidates all player windows (& others) from any past launches which are no longer running into the windows for this instance.
    /// Updates prefs to reflect new conslidated state.
    /// Returns all window names for this launch instance, back to front.
    static func consolidateOpenWindowsFromPastLaunches(pastLaunches cachedLaunches: [String]? = nil) -> [SavedWindow] {
      // Could have been a long time since data was last collected. Get a fresh set of data:
      let pastLaunchNames = cachedLaunches ?? Preference.UIState.collectPastLaunches()

      var allWindowsSortedOldestToNewest: [SavedWindow] = []
      var nameSet = Set<String>()
      for pastLaunchName in pastLaunchNames {
        guard let launchID = Preference.UIState.launchID(fromLaunchName: pastLaunchName) else {
          Logger.log("Failed to parse launchID from launchName: \(pastLaunchName.quoted)", level: .error)
          continue
        }
        for savedWindow in getSavedOpenWindowsBackToFront(forLaunchID: launchID) {
          allWindowsSortedOldestToNewest.append(savedWindow)
          nameSet.insert(savedWindow.saveName.string)
        }
      }

      // Remove duplicates, favoring front-most copies
      var deduplicatedReverseWindowList: [SavedWindow] = []
      for savedWindow in allWindowsSortedOldestToNewest.reversed() {
        if nameSet.remove(savedWindow.saveName.string) != nil {
          deduplicatedReverseWindowList.append(savedWindow)
        } else {
          Logger.log("Skipping duplicate open window: \(savedWindow.saveName.string.quoted)", level: .verbose)
        }
      }

      // First save under new window list:
      let finalWindowList = Array(deduplicatedReverseWindowList.reversed())
      let finalWindowStringList = finalWindowList.map({$0.saveString})
      Logger.log("Consolidated windows from past launches, will save under launchID \(AppDelegate.launchID): \(finalWindowList.map({$0.saveName.string}))", level: .verbose)
      saveOpenWindowList(windowNamesBackToFront: finalWindowStringList, forLaunchID: AppDelegate.launchID)

      // Now remove entries for old launches (keeping player state entries)
      for pastLaunchName in pastLaunchNames {
        Logger.log("Removing past launch from prefs: \(pastLaunchName.quoted)", level: .verbose)
        guard let launchID = Preference.UIState.launchID(fromLaunchName: pastLaunchName) else {
          Logger.log("Failed to parse launchID from launchName: \(pastLaunchName.quoted)", level: .error)
          continue
        }
        let windowListKey = Preference.UIState.makeOpenWindowListKey(forLaunchID: launchID)
        Logger.log("Clearing saved list of open windows (pref key: \(windowListKey.quoted))")
        UserDefaults.standard.removeObject(forKey: windowListKey)

        Logger.log("Clearing saved launch (pref key: \(pastLaunchName.quoted))")
        UserDefaults.standard.removeObject(forKey: pastLaunchName)
      }

      return finalWindowList
    }
  }
}
