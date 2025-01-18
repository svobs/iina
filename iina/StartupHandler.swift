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

  var state: OpenWindowsState = .stillEnqueuing

  /**
   Mainly used to distinguish normal launches from others triggered by drag & drop or double-click from Finder.
   Use only if opening single window. If multiple windows, don't wait; open each as soon as it loads.

   Becomes true once `application(_:openFile:)`, `handleURLEvent()` or `droppedText()` is called with single file.
   See also `wcForOpenFile` which may be set to non-nil value after this variable.
   */
  var openFileCalledForSingleFile = false
  var wcForOpenFile: PlayerWindowController? = nil

  // - Restore

  /// The enqueued list of windows to restore, when restoring at launch.
  /// Try to wait until all windows are ready so that we can show all of them at once (compare with `wcsReady`).
  /// Make sure order of `wcsToRestore` is from back to front to restore the order properly.
  var wcsToRestore: [NSWindowController] = []
  /// Special case for Open File window when restoring. Because it is a panel, not a window, it will not have
  /// an `NSWindowController`.
  var restoreOpenFileWindow = false

  var wcsReady = Set<NSWindowController>()

  /// Calls `self.restoreTimedOut` on timeout.
  let restoreTimer = TimeoutTimer(timeout: Constants.TimeInterval.restoreWindowsTimeout)
  var restoreTimeoutAlertPanel: NSAlert? = nil

  // Command Line

  private var commandLineStatus = CommandLineStatus()

  /// If launched from command line, should ignore `application(_, openFiles:)` during launch.
  var shouldIgnoreOpenFile: Bool {
    return commandLineStatus.isCommandLine && !state.isDone
  }

  // MARK: Init

  init() {
    restoreTimer.action = restoreTimedOut
  }

  func doStartup() {
    // Restore window state *before* hooking up the listener which saves state.
    restoreWindowsFromPreviousLaunch()

    if commandLineStatus.isCommandLine {
      startFromCommandLine()
    }

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

    if commandLineStatus.isCommandLine && !(Preference.bool(for: .enableAdvancedSettings) && Preference.bool(for: .enableRestoreUIStateForCmdLineLaunches)) {
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

      let wc: NSWindowController
      switch savedWindow.saveName {
      case .playbackHistory:
        app.showHistoryWindow(self)
        wc = app.historyWindow
      case .welcome:
        app.showWelcomeWindow()
        wc = app.initialWindow
      case .preferences:
        app.showPreferencesWindow(self)
        wc = app.preferenceWindowController
      case .about:
        app.showAboutWindow(self)
        wc = app.aboutWindow
      case .openFile:
        // No windowController for Open File window. Set flag instead
        restoreOpenFileWindow = true
        UIState.shared.windowsOpen.insert(savedWindow.saveName.string)
        continue
      case .openURL:
        // TODO: persist isAlternativeAction too
        app.showOpenURLWindow(isAlternativeAction: true)
        wc = app.openURLWindow
      case .inspector:
        // Do not show Inspector window. It doesn't support being drawn in the background, but it loads very quickly.
        // So just mark it as 'ready' and show with the rest when they are ready.
        wc = app.inspector
        wcsReady.insert(wc)
      case .videoFilter:
        app.showVideoFilterWindow(self)
        wc = app.vfWindow
      case .audioFilter:
        app.showAudioFilterWindow(self)
        wc = app.afWindow
      case .logViewer:
        app.showLogWindow(self)
        wc = app.logWindow
      case .playerWindow(let id):
        guard let player = PlayerManager.shared.restoreFromPriorLaunch(playerID: id) else { continue }
        wc = player.windowController
      case .newFilter, .editFilter, .saveFilter:
        log.debug("Restoring sheet window \(savedWindow.saveString) is not yet implemented; skipping")
        continue
      default:
        log.error("Cannot restore unrecognized autosave enum: \(savedWindow.saveName)")
        continue
      }

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

    return !wcsToRestore.isEmpty
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

  func restoreTimedOut() {
    assert(DispatchQueue.isExecutingIn(.main))
    let log = Logger.Subsystem.restore
    guard state == .doneEnqueuing else {
      log.error("Restore timed out but state is \(state)")
      return
    }

    let namesReady = wcsReady.compactMap{$0.window?.savedStateName}
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
        guard !wcsReady.contains(wcStalled) else {
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

  private func dismissTimeoutAlertPanel() {
    guard let restoreTimeoutAlertPanel else { return }

    /// Dismiss the prompt (if any). It seems we can't just call `close` on its `window` object, because the
    /// responder chain is left unusable. Instead, click its default button after setting `state`.
    let keepWaitingBtn = restoreTimeoutAlertPanel.buttons[0]
    keepWaitingBtn.performClick(self)
    self.restoreTimeoutAlertPanel = nil

    /// This may restart the timer if not in the correct state, so account for that.
  }

  func abortWaitForOpenFilePlayerStartup() {
    Logger.log.verbose("Aborting wait for Open File player startup")
    openFileCalledForSingleFile = false
    wcForOpenFile = nil
    showWindowsIfReady()
  }

  func showWindowsIfReady() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard state == .doneEnqueuing else { return }
    guard wcsReady.count == wcsToRestore.count else {
      dismissTimeoutAlertPanel()
      restoreTimer.restart()
      return
    }
    // TODO: change this to support multi-window open for multiple files
    guard !openFileCalledForSingleFile || wcForOpenFile != nil else { return }
    let log = Logger.Subsystem.restore

    log.verbose("All \(wcsToRestore.count) restored \(wcForOpenFile == nil ? "" : "& 1 new ")windows ready. Showing all")
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
    if let wcForOpenFile = wcForOpenFile, !(wcForOpenFile.window?.isMiniaturized ?? false) {
      wcForOpenFile.showWindow(self)  // open last, thus making frontmost
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

    let didOpenSomething = didRestoreSomething || wcForOpenFile != nil
    if !commandLineStatus.isCommandLine && !didOpenSomething {
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

    Logger.log.verbose("Done with startup")
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

    if Preference.bool(for: .isRestoreInProgress) {
      wcsReady.insert(wc)

      log.verbose("Restored window is ready: \(window.savedStateName.quoted). Progress: \(wcsReady.count)/\(state == .doneEnqueuing ? "\(wcsToRestore.count)" : "?")")

      // Show all windows if ready
      showWindowsIfReady()
    } else if window.isMiniaturized {
      log.verbose("OpenWindow: deminiaturizing window \(window.savedStateName.quoted)")
      // Need to call this instead of showWindow if minimized (otherwise there are visual glitches)
      window.deminiaturize(self)
    } else {
      log.verbose("OpenWindow: showing window \(window.savedStateName.quoted)")
      wc.showWindow(window)
    }
  }

  /// Window failed to load. Stop waiting for it
  func windowMustCancelShow(_ notification: Notification) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let window = notification.object as? NSWindow else { return }
    let log = Logger.Subsystem.restore

    guard Preference.bool(for: .isRestoreInProgress) else { return }
    log.verbose("Restored window cancelled: \(window.savedStateName.quoted). Progress: \(wcsReady.count)/\(state == .doneEnqueuing ? "\(wcsToRestore.count)" : "?")")

    // No longer waiting for this window
    wcsToRestore.removeAll(where: { wc in
      wc.window!.savedStateName == window.savedStateName
    })

    showWindowsIfReady()
  }

  // MARK: - Command Line

  // TODO: refactor to put this all in CommandLineStatus class
  func parseCommandLine(_ args: ArraySlice<String>) {
    var iinaArgs: [String] = []
    var iinaArgFilenames: [String] = []
    var dropNextArg = false

    Logger.log("Command-line arguments \("\(args)".pii)")
    for arg in args {
      if dropNextArg {
        dropNextArg = false
        continue
      }
      if arg.first == "-" {
        let indexAfterDash = arg.index(after: arg.startIndex)
        if indexAfterDash == arg.endIndex {
          // single '-'
          commandLineStatus.isStdin = true
        } else if arg[indexAfterDash] == "-" {
          // args starting with --
          iinaArgs.append(arg)
        } else {
          // args starting with -
          dropNextArg = true
        }
      } else {
        // assume args starting with nothing is a filename
        iinaArgFilenames.append(arg)
      }
    }

    commandLineStatus.parseArguments(iinaArgs)
    Logger.log("Filenames from args: \(iinaArgFilenames)")
    Logger.log("Derived mpv properties from args: \(commandLineStatus.mpvArguments)")

    guard !iinaArgFilenames.isEmpty || commandLineStatus.isStdin else {
      print("This binary is not intended for being used as a command line tool. Please use the bundled iina-cli.")
      print("Please ignore this message if you are running in a debug environment.")
      return
    }

    commandLineStatus.isCommandLine = true
    commandLineStatus.filenames = iinaArgFilenames
  }

  private func startFromCommandLine() {
    var lastPlayerCore: PlayerCore? = nil
    let getNewPlayerCore = { [self] () -> PlayerCore in
      let pc = PlayerManager.shared.getIdleOrCreateNew()
      commandLineStatus.applyMPVArguments(to: pc)
      lastPlayerCore = pc
      return pc
    }
    if commandLineStatus.isStdin {
      getNewPlayerCore().openURLString("-")
    } else {
      let validFileURLs: [URL] = commandLineStatus.filenames.compactMap { filename in
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

      if commandLineStatus.openSeparateWindows {
        validFileURLs.forEach { url in
          getNewPlayerCore().openURL(url)
        }
      } else {
        getNewPlayerCore().openURLs(validFileURLs)
      }
    }

    if let pc = lastPlayerCore {
      if commandLineStatus.enterMusicMode {
        Logger.log.verbose("Entering music mode as specified via command line")
        if commandLineStatus.enterPIP {
          // PiP is not supported in music mode. Combining these options is not permitted and is
          // rejected by iina-cli. The IINA executable must have been invoked directly with
          // arguments.
          Logger.log.error("Cannot specify both --music-mode and --pip")
          // Command line usage error.
          exit(EX_USAGE)
        }
        pc.enterMusicMode()
      } else if commandLineStatus.enterPIP {
        Logger.log.verbose("Entering PIP as specified via command line")
        pc.windowController.enterPIP()
      }
    }
  }
}


struct CommandLineStatus {
  var isCommandLine = false
  var isStdin = false
  var openSeparateWindows = false
  var enterMusicMode = false
  var enterPIP = false
  var mpvArguments: [(String, String)] = []
  var iinaArguments: [(String, String)] = []
  var filenames: [String] = []

  mutating func parseArguments(_ args: [String]) {
    mpvArguments.removeAll()
    iinaArguments.removeAll()
    for arg in args {
      let splitted = arg.dropFirst(2).split(separator: "=", maxSplits: 1)
      let name = String(splitted[0])
      if (name.hasPrefix("mpv-")) {
        // mpv args
        let strippedName = String(name.dropFirst(4))
        if strippedName == "-" {
          isStdin = true
        } else {
          let argPair: (String, String)
          if splitted.count <= 1 {
            argPair = (strippedName, "yes")
          } else {
            argPair = (strippedName, String(splitted[1]))
          }
          mpvArguments.append(argPair)
        }
      } else {
        // other args
        if splitted.count <= 1 {
          iinaArguments.append((name, "yes"))
        } else {
          iinaArguments.append((name, String(splitted[1])))
        }
        if name == "stdin" {
          isStdin = true
        }
        if name == "separate-windows" {
          openSeparateWindows = true
        }
        if name == "music-mode" {
          enterMusicMode = true
        }
        if name == "pip" {
          enterPIP = true
        }
      }
    }
  }

  func applyMPVArguments(to playerCore: PlayerCore) {
    Logger.log("Setting mpv properties from arguments: \(mpvArguments)")
    for argPair in mpvArguments {
      if argPair.0 == "shuffle" && argPair.1 == "yes" {
        // Special handling for this one
        Logger.log("Found \"shuffle\" request in command-line args. Adding mpv hook to shuffle playlist")
        playerCore.addShufflePlaylistHook()
        continue
      }
      playerCore.mpv.setString(argPair.0, argPair.1)
    }
  }

}
