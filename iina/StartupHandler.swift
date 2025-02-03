//
//  swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-03.
//  Copyright © 2024 lhc. All rights reserved.
//


import Foundation

/// Encapsulates code for opening/restoring windows at application startup.
/// See also: `AppDelegate`
class StartupHandler {

  enum OpenWindowsState: Int {
    case stillEnqueuing = 1
    case doneEnqueuing
    case doneOpening

    var isDone: Bool {
      return self == .doneOpening
    }
  }

  // MARK: Properties

  let launchStartTime = CFAbsoluteTimeGetCurrent()

  var state: OpenWindowsState = .stillEnqueuing

  /**
   Mainly used to distinguish normal launches from others triggered by drag & drop or double-click from Finder.

   Becomes true once `application(_:openFile:)`, `handleURLEvent()` or `droppedText()` is called with file(s).
   See also `wcsForOpenFiles` which is expected be set to a non-nil (and non-empty) value after this variable
   becomes true. If needing to abort the new windows, `isOpeningNewWindows` should be set to false again.
   */
  var isOpeningNewWindows = false
  var wcsForOpenFiles: [PlayerWindowController]? = nil
  var wcsDoneWithFileOpen: [PlayerWindowController] = []

  // - Restore

  /// The enqueued list of windows to restore, when restoring at launch.
  /// Try to wait until all windows are ready so that we can show all of them at once (compare with `wcsDoneWithRestore`).
  /// Make sure order of `wcsToRestore` is from back to front to restore the order properly.
  var wcsToRestore: [NSWindowController] = []
  var wcsDoneWithRestore = Set<NSWindowController>()
  /// Special case for Open File window when restoring. Because it is a panel, not a window, it will not have
  /// an `NSWindowController`.
  var restoreOpenFileWindow = false

  /// Calls `self.restoreDidTimeOut` on timeout.
  let restoreTimer = TimeoutTimer(timeout: Constants.TimeInterval.restoreWindowsTimeout)
  var restoreTimeoutAlertPanel: NSAlert? = nil

  // Command Line

  private var commandLineStatus: CommandLineStatus? = nil

  var isCommandLine: Bool {
    commandLineStatus != nil
  }

  /// If launched from command line, should ignore `application(_, openFiles:)` during launch.
  var shouldIgnoreOpenFile: Bool {
    guard isCommandLine else { return false }
    return !state.isDone
  }

  // MARK: Init

  init() {
    restoreTimer.action = restoreDidTimeOut
  }

  func doStartup() {
    // Restore window state *before* hooking up the listener which saves state.
    restoreWindowsFromPreviousLaunch()

    commandLineStatus?.startFromCommandLine()

    state = .doneEnqueuing
    // Callbacks may have already fired before getting here. Check again to make sure we don't "drop the ball":
    showWindowsIfReady()
  }

  /// Returns `true` if any windows were restored; `false` otherwise.
  @discardableResult
  private func restoreWindowsFromPreviousLaunch() -> Bool {
    assert(DispatchQueue.isExecutingIn(.main))
    let log = Logger.Subsystem.restore

    guard UIState.shared.isRestoreEnabled else {
      log.debug("Restore is disabled. Wll not restore windows")
      return false
    }

    if isCommandLine && !(Preference.bool(for: .enableAdvancedSettings) && Preference.bool(for: .enableRestoreUIStateForCmdLineLaunches)) {
      log.debug("Restore is disabled for command-line launches. Wll not restore windows or save state for this launch")
      UIState.shared.disableSaveAndRestoreUntilNextLaunch()
      return false
    }

    let pastLaunches: [UIState.LaunchState] = UIState.shared.collectLaunchStateForRestore()
    log.verbose("Found \(pastLaunches.count) past launches to restore")
    if pastLaunches.isEmpty {
      return false
    }

    let stopwatch = Utility.Stopwatch()

    let isRestoreApproved = checkForRestoreApproval()
    if !isRestoreApproved {
      // Clear out old state. It may have been causing errors, or user wants to start new
      log.debug("User denied restore. Clearing all saved launch state.")
      UIState.shared.clearAllSavedLaunches()
      Preference.set(false, for: .isRestoreInProgress)
      return false
    }

    // If too much time has passed (in particular if user took a long time to respond to confirmation dialog), consider the data stale.
    // Due to 1s delay in chosen strategy for verifying whether other instances are running, try not to repeat it twice.
    // Users who are quick with their user interface device probably know what they are doing and will be impatient.
    let pastLaunchesCache = stopwatch.secElapsed > Constants.TimeInterval.pastLaunchResponseTimeout ? nil : pastLaunches
    let savedWindowsBackToFront = UIState.shared.consolidateSavedWindowsFromPastLaunches(pastLaunches: pastLaunchesCache)

    guard !savedWindowsBackToFront.isEmpty else {
      log.debug("Nothing to restore: stored window list empty")
      return false
    }

    if savedWindowsBackToFront.count == 1 {
      let onlyWindow = savedWindowsBackToFront[0].saveName

      if onlyWindow == WindowAutosaveName.inspector {
        // Do not restore this on its own
        log.verbose("Nothing to restore: only open window was Inspector")
        return false
      }

      let action: Preference.ActionAfterLaunch = Preference.enum(for: .actionAfterLaunch)
      if (onlyWindow == WindowAutosaveName.welcome && action == .welcomeWindow)
          || (onlyWindow == WindowAutosaveName.openURL && action == .openPanel)
          || (onlyWindow == WindowAutosaveName.playbackHistory && action == .historyWindow) {
        log.verbose("Nothing to restore: the only open window was identical to launch action (\(action))")
        // Skip the prompts below because they are just unnecessary nagging
        return false
      }
    }

    log.verbose("Starting restore of \(savedWindowsBackToFront.count) windows")
    Preference.set(true, for: .isRestoreInProgress)

    let app = AppDelegate.shared
    // Show windows one by one, starting at back and iterating to front:
    for savedWindow in savedWindowsBackToFront {
      log.verbose("Starting restore of window: \(savedWindow.saveName)\(savedWindow.isMinimized ? " (minimized)" : "")")

      switch savedWindow.saveName {
      case .playbackHistory:
        addWindowToRestore(savedWindow, app.historyWindow)
        app.showHistoryWindow(self)
      case .welcome:
        addWindowToRestore(savedWindow, app.initialWindow)
        app.showWelcomeWindow()
      case .preferences:
        addWindowToRestore(savedWindow, app.preferenceWindowController)
        app.showPreferencesWindow(self)
      case .about:
        addWindowToRestore(savedWindow, app.aboutWindow)
        app.showAboutWindow(self)
      case .openFile:
        // No windowController for Open File window. Set flag instead
        restoreOpenFileWindow = true
        UIState.shared.windowsOpen.insert(savedWindow.saveName.string)
      case .openURL:
        // TODO: persist isAlternativeAction too
        addWindowToRestore(savedWindow, app.openURLWindow)
        app.showOpenURLWindow(isAlternativeAction: true)
      case .inspector:
        // Do not show Inspector window. It doesn't support being drawn in the background, but it loads very quickly.
        // So just mark it as 'ready' and show with the rest when they are ready.
        wcsDoneWithRestore.insert(app.inspector)
        addWindowToRestore(savedWindow, app.inspector)
      case .videoFilter:
        addWindowToRestore(savedWindow, app.vfWindow)
        app.showVideoFilterWindow(self)
      case .audioFilter:
        addWindowToRestore(savedWindow, app.afWindow)
        app.showAudioFilterWindow(self)
      case .logViewer:
        addWindowToRestore(savedWindow, app.logWindow)
        app.showLogWindow(self)
      case .playerWindow(let id):
        restorePlayerWindowFromPriorLaunch(savedWindow, playerID: id)
      case .newFilter, .editFilter, .saveFilter:
        log.debug("Restoring sheet window \(savedWindow.saveString) is not yet implemented; skipping")
        continue
      default:
        log.error("Cannot restore unrecognized autosave enum: \(savedWindow.saveName)")
        continue
      }

    }

    return !wcsToRestore.isEmpty || restoreOpenFileWindow
  }

  // Attempt to exactly restore play state & UI from last run of IINA (for given player)
  private func restorePlayerWindowFromPriorLaunch(_ savedWindow: SavedWindow, playerID id: String) {
    let log = UIState.shared.log
    log.debug("Creating new PlayerCore & restoring saved state for \(WindowAutosaveName.playerWindow(id: id).string.quoted)")

    guard let savedState = UIState.shared.getPlayerSaveState(forPlayerID: id) else {
      log.error("Cannot restore window: could not find saved state for \(WindowAutosaveName.playerWindow(id: id).string.quoted)")
      return
    }

    let player = PlayerManager.shared.createNewPlayerCore(withLabel: id)
    let wc = player.windowController!
    assert(wc.sessionState.isNone, "Invalid sessionState for restore: \(wc.sessionState)")
    wc.sessionState = .restoring(playerState: savedState)

    addWindowToRestore(savedWindow, wc)

    savedState.restoreTo(player)
  }


  private func addWindowToRestore(_ savedWindow: SavedWindow, _ wc: NSWindowController) {
    // Rebuild UIState window sets as we go:
    if savedWindow.isMinimized {
      // No need to worry about partial show, so skip wcsToRestore
      wc.window?.miniaturize(self)
      UIState.shared.windowsMinimized.insert(savedWindow.saveName.string)
    } else {
      // Add to list of windows to wait for, so we can show them all nicely
      wcsToRestore.append(wc)
      UIState.shared.windowsOpen.insert(savedWindow.saveName.string)
    }
  }

  /// If this returns true, restore should be attempted using the saved launch state.
  /// If false is returned, then the saved launch state should be deleted and app should launch fresh.
  private func checkForRestoreApproval() -> Bool {
#if DEBUG
    if DebugConfig.alwaysApproveRestore {
      // skip approval to make testing easier
      return true
    }
#endif

    if Preference.bool(for: .isRestoreInProgress) {
      // If this flag is still set, the last restore probably failed. If it keeps failing, launch will be impossible.
      // Let user decide whether to try again or delete saved state.
      Logger.Subsystem.restore.debug("Looks like there was a previous restore which didn't complete (pref \(Preference.Key.isRestoreInProgress.rawValue)=Y). Asking user whether to retry or skip")
      return Utility.quickAskPanel("restore_prev_error", useCustomButtons: true)
    }

    if Preference.bool(for: .alwaysAskBeforeRestoreAtLaunch) {
      Logger.Subsystem.restore.verbose("Prompting user whether to restore app state, per pref")
      return Utility.quickAskPanel("restore_confirm", useCustomButtons: true)
    }
    return true
  }

  /// Called by a `TimeoutTimer` if the restore process is taking too long.  Displays a dialog prompting
  /// the user to discard the stored state, or keep waiting.
  private func restoreDidTimeOut() {
    assert(DispatchQueue.isExecutingIn(.main))
    let log = Logger.Subsystem.restore
    guard state == .doneEnqueuing else {
      log.error("Restore timed out but state is \(state)")
      return
    }

    let namesReady = wcsDoneWithRestore.compactMap{$0.window?.savedStateName}
    let wcsStalled: [NSWindowController] = wcsToRestore.filter{ !namesReady.contains($0.window!.savedStateName) }
    var namesStalled: [String] = []
    for (index, wc) in wcsStalled.enumerated() {
      let winID = wc.window!.savedStateName
      let str: String
      if index > Constants.maxWindowNamesInRestoreTimeoutAlert {
        break
      } else if index == Constants.maxWindowNamesInRestoreTimeoutAlert {
        str = "…"
      } else if let path = (wc as? PlayerWindowController)?.player.info.currentPlayback?.path {
        str = "\(index+1). \(path.quoted)  [\(winID)]"
      } else {
        str = "\(index+1). \(winID)"
      }
      namesStalled.append(str)
    }

    log.debug("Restore timed out. Progress: \(namesReady.count)/\(wcsToRestore.count). Stalled: \(namesStalled)")
    log.debug("Prompting user whether to discard them & continue, or quit")

    let countFailed = "\(wcsStalled.count)"
    let countTotal = "\(wcsToRestore.count)"
    let namesStalledString = namesStalled.joined(separator: "\n")
    let msgArgs = [countFailed, countTotal, namesStalledString]
    let askPanel = Utility.buildThreeButtonAskPanel("restore_timeout", msgArgs: msgArgs, alertStyle: .critical)
    restoreTimeoutAlertPanel = askPanel
    let userResponse = askPanel.runModal()  // this will block for an indeterminate time

    switch userResponse {
    case .alertFirstButtonReturn:
      log.debug("User chose button 1: keep waiting")
      guard state != .doneOpening else {
        log.debug("Looks like windows finished opening - no need to restart restore timer")
        return
      }
      dismissTimeoutAlertPanel()
      restoreTimer.restart()

    case .alertSecondButtonReturn:
      log.debug("User chose button 2: discard stalled windows & continue with partial restore")
      restoreTimeoutAlertPanel = nil  // Clear this (no longer needed)
      guard state != .doneOpening else {
        log.debug("Looks like windows finished opening - no need to close anything")
        return
      }
      for wcStalled in wcsStalled {
        guard !wcsDoneWithRestore.contains(wcStalled) else {
          log.verbose("Window has become ready; skipping close: \(wcStalled.window!.savedStateName)")
          continue
        }
        log.verbose("Telling stalled window to close: \(wcStalled.window!.savedStateName)")
        if let pWin = wcStalled as? PlayerWindowController {
          /// This will guarantee `windowMustCancelShow` notification is sent
          pWin.player.closeWindow()
        } else {
          wcStalled.close()
          // explicitly call this, as the line above may fail
          wcStalled.window?.postWindowMustCancelShow()
        }
      }

    case .alertThirdButtonReturn:
      log.debug("User chose button 3: quit")
      NSApp.terminate(nil)

    default:
      log.fatalError("User responded to Restore Timeout alert with unrecognized choice!")
    }
  }

  /// Called if all the windows become ready while still displaying the timeout dialog, Dismisses the dialog
  /// automatically, so the user does not have to do it themselves.
  private func dismissTimeoutAlertPanel() {
    guard let restoreTimeoutAlertPanel else { return }

    /// Dismiss the prompt (if any). It seems we can't just call `close` on its `window` object, because the
    /// responder chain is left unusable. Instead, click its default button after setting `state`.
    let keepWaitingBtn = restoreTimeoutAlertPanel.buttons[0]
    keepWaitingBtn.performClick(self)
    self.restoreTimeoutAlertPanel = nil

    /// This may restart the timer if not in the correct state, so account for that.
  }

  /// Call this if the user opened a new file at startup but we want to discard the state for it
  /// (for example if it couldn't be opened).
  func abortWaitForOpenFilePlayerStartup() {
    Logger.log.verbose("Aborting wait for open files")
    isOpeningNewWindows = false
    wcsForOpenFiles = nil
    wcsDoneWithFileOpen.removeAll()
    showWindowsIfReady()
  }

  func showWindowsIfReady() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard state == .doneEnqueuing else { return }
    guard wcsDoneWithRestore.count == wcsToRestore.count else {
      dismissTimeoutAlertPanel()
      restoreTimer.restart()
      return
    }
    // If an new player window was opened at startup (i.e. not a restored window), wait for this also.
    if isOpeningNewWindows {
      // If isOpeningNewWindows is true, the check below will only pass once wcsForOpenFiles becomes non-nil.
      guard let wcsForOpenFiles else { return }

      // If opening more than 1 file, proceed immediately. Otherwise wait for it to be ready.
      guard wcsForOpenFiles.count > 1 || (wcsForOpenFiles.count == wcsDoneWithFileOpen.count) else { return }
    }
    let log = Logger.Subsystem.restore

    let newWindCount = wcsForOpenFiles?.count ?? 0
    log.verbose("All \(wcsToRestore.count) restored \(newWindCount > 0 ? " & \(newWindCount) new windows ready. Showing all" : "")")
    restoreTimer.cancel()

    var prevWindowNumber: Int? = nil
    for wc in wcsToRestore {
      let windowIsMinimized = (wc.window?.isMiniaturized ?? false)
      guard !windowIsMinimized else { continue }

      if let prevWindowNumber {
        wc.window?.order(.above, relativeTo: prevWindowNumber)
      }
      prevWindowNumber = wc.window?.windowNumber
      wc.showWindow(self)
    }

    // Windows for opened files (if any).
    // Don't wait for these to be ready. But at least ensure that their ordering is correct.
    if let wcsForOpenFiles {
      for wc in wcsForOpenFiles {
        let windowIsMinimized = (wc.window?.isMiniaturized ?? false)
        guard !windowIsMinimized else { continue }

        // Make this topmost
        if let prevWindowNumber {
          wc.window?.order(.above, relativeTo: prevWindowNumber)
        }
        prevWindowNumber = wc.window?.windowNumber
        wc.showWindow(self)
      }
    }

    if restoreOpenFileWindow {
      // TODO: persist isAlternativeAction too
      AppDelegate.shared.showOpenFileWindow(isAlternativeAction: false)
    }

    let didRestoreSomething = !wcsToRestore.isEmpty

    if Preference.bool(for: .isRestoreInProgress) {
      log.verbose("Done restoring windows (\(wcsToRestore.count))")
      Preference.set(false, for: .isRestoreInProgress)
    }

    state = .doneOpening

    let didOpenSomething = didRestoreSomething || wcsForOpenFiles != nil
    if !isCommandLine && !didOpenSomething {
      // Fall back to default action:
      AppDelegate.shared.doLaunchOrReopenAction()
    }

    /// Make sure to do this *after* `state = .doneOpening`:
    dismissTimeoutAlertPanel()

    // Init MediaPlayer integration
    MediaPlayerIntegration.shared.update()

    Logger.log("Activating app")
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    NSApplication.shared.servicesProvider = self

    let timeElapsed: Double = CFAbsoluteTimeGetCurrent() - launchStartTime
    Logger.log.verbose("Done with startup (\(timeElapsed.stringMaxFrac2)s)")
  }


  // MARK: - Notification Listeners

  /// Window is done loading and is ready to show.
  /// If the application has already finished launching, this simply calls `showWindow` for the calling window.
  func windowIsReadyToShow(_ notification: Notification) {
    assert(DispatchQueue.isExecutingIn(.main))
    let log = Logger.Subsystem.restore

    guard let window = notification.object as? NSWindow else { return }
    guard let wc = window.windowController else {
      log.error("Restored window is ready, but no windowController for window: \(window.savedStateName.quoted)!")
      return
    }
    let savedStateName = window.savedStateName

    if state.isDone {
      if window.isMiniaturized {
        log.verbose("OpenWindow: deminiaturizing window \(window.savedStateName.quoted)")
        // Need to call this instead of showWindow if minimized (otherwise there are visual glitches)
        window.deminiaturize(self)
      } else {
        log.verbose("OpenWindow: showing window \(window.savedStateName.quoted)")
        wc.showWindow(window)
      }

    } else { // Not done launching
      if Preference.bool(for: .isRestoreInProgress), wcsToRestore.contains(wc) {
        wcsDoneWithRestore.insert(wc)
        log.verbose("Restored window is ready: \(savedStateName.quoted). Progress: \(wcsDoneWithRestore.count)/\(state == .doneEnqueuing ? "\(wcsToRestore.count)" : "?")")
      } else if let wcsForOpenFiles, wcsForOpenFiles.contains(where: {$0.window!.savedStateName == savedStateName}) {
        wcsDoneWithFileOpen.append(wc as! PlayerWindowController)
        log.verbose("OpenedFile window is ready: \(savedStateName.quoted)")
      }
      // Else may be multiple files opened at launch

      // Show all windows if ready
      showWindowsIfReady()
    }
  }

  /// Window failed to load. Stop waiting for it
  func windowMustCancelShow(_ notification: Notification) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let window = notification.object as? NSWindow else { return }
    let log = Logger.Subsystem.restore

    guard Preference.bool(for: .isRestoreInProgress) else { return }
    log.verbose("Restored window cancelled: \(window.savedStateName.quoted). Progress: \(wcsDoneWithRestore.count)/\(state == .doneEnqueuing ? "\(wcsToRestore.count)" : "?")")

    // No longer waiting for this window
    wcsToRestore.removeAll(where: { wc in
      wc.window!.savedStateName == window.savedStateName
    })

    showWindowsIfReady()
  }

  // MARK: - Command Line

  func parseCommandLine(_ cmdLineArgs: ArraySlice<String>) {
    commandLineStatus = CommandLineStatus(cmdLineArgs)
  }
}

fileprivate class CommandLineStatus {
  var isStdin = false
  var openSeparateWindows = false
  var enterMusicMode = false
  var enterPIP = false
  var mpvArguments: [(String, String)] = []
  var filenames: [String] = []

  init?(_ arguments: ArraySlice<String>) {
    guard !arguments.isEmpty else { return nil }

    for arg in arguments {
      if arg.hasPrefix("--") {
        parseDoubleDashedArg(arg)
      } else if arg.hasPrefix("-") {
        parseSingleDashedArg(arg)
      } else {
        // assume arg with no starting dashes is a filename
        filenames.append(arg)
      }
    }

    Logger.log("Parsed command-line args: isStdin=\(isStdin) separateWindows=\(openSeparateWindows), enterMusicMode=\(enterMusicMode), enterPIP=\(enterPIP))")
    Logger.log("Filenames from arguments: \(filenames)")
    Logger.log("Derived mpv properties from args: \(mpvArguments)")

    guard !filenames.isEmpty || isStdin else {
      print("This binary is not intended for being used as a command line tool. Please use the bundled iina-cli.")
      print("Please ignore this message if you are running in a debug environment.")
      return nil
    }
  }

  private func parseDoubleDashedArg(_ arg: String) {
    if arg == "--" {
      // ignore
      return
    }
    let splitted = arg.dropFirst(2).split(separator: "=", maxSplits: 1)
    let name = String(splitted[0])
    if name.hasPrefix("mpv-") {
      // mpv args
      let strippedName = String(name.dropFirst(4))
      if strippedName == "-" {
        isStdin = true
      } else if splitted.count <= 1 {
        mpvArguments.append((strippedName, "yes"))
      } else {
        mpvArguments.append((strippedName, String(splitted[1])))
      }
    } else {
      // Check for IINA args. If an arg is not recognized, assume it is an mpv arg.
      // (The names here should match the "Usage" message in main.swift)
      switch name {
      case "stdin":
        isStdin = true
      case "separate-windows":
        openSeparateWindows = true
      case "music-mode":
        enterMusicMode = true
      case "pip":
        enterPIP = true
      default:
        if splitted.count <= 1 {
          mpvArguments.append((name, "yes"))
        } else {
          mpvArguments.append((name, String(splitted[1])))
        }
      }
    }
  }

  private func parseSingleDashedArg(_ arg: String) {
    if arg == "-" {
      // single '-'
      isStdin = true
    }
    // else ignore all single-dashed args
  }

  fileprivate func startFromCommandLine() {
    var lastPlayerCore: PlayerCore? = nil
    if isStdin {
      lastPlayerCore = getOrCreatePlayerWithCmdLineArgs()
      lastPlayerCore?.openURLString("-")
    } else {
      let validFileURLs: [URL] = filenames.compactMap { filename in
        if Regex.url.matches(filename) {
          return URL(string: filename.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? filename)
        } else {
          return FileManager.default.fileExists(atPath: filename) ? URL(fileURLWithPath: filename) : nil
        }
      }
      guard !validFileURLs.isEmpty else {
        Logger.log.error("No valid file URLs provided via command line! Nothing to do")
        return
      }

      if openSeparateWindows {
        for url in validFileURLs {
          lastPlayerCore = getOrCreatePlayerWithCmdLineArgs()
          lastPlayerCore?.openURL(url)
        }
      } else {
        lastPlayerCore = getOrCreatePlayerWithCmdLineArgs()
        lastPlayerCore?.openURLs(validFileURLs)
      }
    }

    if let pc = lastPlayerCore {
      if enterMusicMode {
        Logger.log.verbose("Entering music mode as specified via command line")
        if enterPIP {
          // PiP is not supported in music mode. Combining these options is not permitted and is
          // rejected by iina-cli. The IINA executable must have been invoked directly with
          // arguments.
          Logger.log.error("Cannot specify both --music-mode and --pip")
          // Command line usage error.
          exit(EX_USAGE)
        }
        pc.enterMusicMode()
      } else if enterPIP {
        Logger.log.verbose("Entering PIP as specified via command line")
        pc.windowController.enterPIP()
      }
    }
  }

  func getOrCreatePlayerWithCmdLineArgs() -> PlayerCore {
    let playerCore = PlayerManager.shared.getIdleOrCreateNew()
    Logger.log("Setting mpv properties from arguments: \(mpvArguments)")
    for argPair in mpvArguments {
      if argPair.0 == "shuffle" && argPair.1 == "yes" {
        // Special handling for this one
        Logger.log("Found \"shuffle\" request in command-line args. Adding mpv hook to shuffle playlist")
        playerCore.addShufflePlaylistHook()
      } else {
        playerCore.mpv.setString(argPair.0, argPair.1)
      }
    }
    return playerCore
  }

}
