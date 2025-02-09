//
//  AppDelegate.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import Sparkle

/** Tags for "Open File/URL" menu item when "Always open file in new windows" is off. Vice versa. */
fileprivate let NormalMenuItemTag = 0
/** Tags for "Open File/URL in New Window" when "Always open URL" when "Open file in new windows" is off. Vice versa. */
fileprivate let AlternativeMenuItemTag = 1

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {

  /// The `AppDelegate` singleton object.
  static var shared: AppDelegate { NSApp.delegate as! AppDelegate }

  // MARK: Properties

  @IBOutlet var menuController: MenuController!

  @IBOutlet weak var dockMenu: NSMenu!

  // TODO: finish adding support for tabbing windows
  var tabService: TabService? = nil

  func addTabForPlayer(_ pwc: PlayerWindowController) {
    if let tabService, let mainWindow = tabService.mainWindow {
      Logger.log.debug{"Adding tab for PlayerWindow \(pwc.player.label.quoted)"}
      tabService.createTab(newWindowController: pwc, inWindow: mainWindow, ordered: .above)
    } else {
      // If either tabService or mainWindow is nil, there are no prev tabbed windows
      Logger.log.debug{"Creating new TabService with initial PlayerWindow \(pwc.player.label.quoted)"}
      tabService = TabService(initialWindowController: pwc)
    }
  }

  // Need to store these somewhere which isn't only inside a struct.
  // Swift doesn't seem to count them as strong references
  private let bindingTableStateManger: BindingTableStateManager = BindingTableState.manager
  private let confTableStateManager: ConfTableStateManager = ConfTableState.manager

  // MARK: Window controllers

  lazy var initialWindow = InitialWindowController()
  lazy var openURLWindow = OpenURLWindowController()
  lazy var aboutWindow = AboutWindowController()
  lazy var fontPicker = FontPickerWindowController()
  lazy var inspector = InspectorWindowController()
  lazy var historyWindow = HistoryWindowController()
  lazy var guideWindow = GuideWindowController()
  lazy var logWindow = LogWindowController()

  lazy var vfWindow = FilterWindowController(filterType: MPVProperty.vf, .videoFilter)
  lazy var afWindow = FilterWindowController(filterType: MPVProperty.af, .audioFilter)

  lazy var preferenceWindowController = PreferenceWindowController()

  // MARK: State

  var startupHandler = StartupHandler()
  private var shutdownHandler = ShutdownHandler()
  private var co: CocoaObserver!

  private var lastClosedWindowName: String = ""
  var isShowingOpenFileWindow = false

  var isTerminating: Bool {
    return shutdownHandler.isTerminating
  }

  /// Called each time a pref `key`'s value is set
  func prefDidChange(_ key: Preference.Key, _ newValue: Any?) {
    switch key {
    case PK.enableAdvancedSettings, PK.enableLogging, PK.logLevel:
      Logger.updateEnablement()
      // depends on advanced being enabled:
      menuController.refreshCmdNStatus()
      menuController.refreshBuiltInMenuItemBindings()

    case PK.enableCmdN:
      menuController.refreshCmdNStatus()
      menuController.refreshBuiltInMenuItemBindings()

    case PK.resumeLastPosition:
      HistoryController.shared.async {
        HistoryController.shared.log.verbose("Reloading playback history in response to change for 'resumeLastPosition'.")
        HistoryController.shared.reloadAll()
      }

    case PK.useMediaKeys:
      MediaPlayerIntegration.shared.update()

    // TODO: #1, see above
//    case PK.hideWindowsWhenInactive:
//      if let newValue = newValue as? Bool {
//        for window in NSApp.windows {
//          guard window as? PlayerWindow == nil else { continue }
//          window.hidesOnDeactivate = newValue
//        }
//      }

    default:
      break
    }
  }

  /// Only implemented for special case of `UIState.shared.currentLaunchName`. All other prefs should be checked in `prefDidChange`.
  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath, let change, keyPath == UIState.shared.currentLaunchName, let newLaunchLifecycleState = change[.newKey] as? Int else { return }
    guard !isTerminating else { return }
    guard newLaunchLifecycleState != 0 else { return }
    Logger.log("Detected change to this instance's lifecycle state pref (\(keyPath.quoted)). Probably a newer instance of IINA has started and is attempting to restore")
    Logger.log("Changing our lifecycle state back to 'stillRunning' so the other launch will skip this instance.")
    UserDefaults.standard.setValue(UIState.LaunchLifecycleState.stillRunning.rawValue, forKey: keyPath)
    DispatchQueue.main.async { [self] in
      NotificationCenter.default.post(Notification(name: .savedWindowStateDidChange, object: self))
    }
  }

  // MARK: - Auto update

  @IBOutlet var updaterController: SPUStandardUpdaterController!

  func feedURLString(for updater: SPUUpdater) -> String? {
    return Preference.bool(for: .receiveBetaUpdate) ? AppData.appcastBetaLink : AppData.appcastLink
  }

  // MARK: - Startup

  var isDoneLaunching: Bool {
    startupHandler.isDoneLaunching
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    // Must setup preferences before logging so log level is set correctly.
    registerUserDefaultValues()

    Logger.initLogging()
    AppDetailsLogging.shared.logAllAppDetails()

    Logger.log.debug{"App will launch. LaunchID: \(UIState.shared.currentLaunchID)"}

    // Start asynchronously gathering and caching information about the hardware decoding
    // capabilities of this Mac.
    HardwareDecodeCapabilities.shared.checkCapabilities()


    var ncDefaultObservers: [CocoaObserver.NCObserver] = [ .init(.windowIsReadyToShow, startupHandler.windowIsReadyToShow),
                                                           .init(.windowMustCancelShow, startupHandler.windowMustCancelShow)]
    // The "action on last window closed" action will vary slightly depending on which type of window was closed.
    // Here we add a listener which fires when *any* window is closed, in order to handle that logic all in one place.
    ncDefaultObservers.append(.init(NSWindow.willCloseNotification, windowWillClose))

    if UIState.shared.isSaveEnabled {
      // Save ordered list of open windows each time the order of windows changed.
      ncDefaultObservers.append(.init(NSWindow.didBecomeMainNotification, windowDidBecomeMain))
      ncDefaultObservers.append(.init(NSWindow.willBeginSheetNotification, windowWillBeginSheet))
      ncDefaultObservers.append(.init(NSWindow.didEndSheetNotification, windowDidEndSheet))
      ncDefaultObservers.append(.init(NSWindow.didMiniaturizeNotification, windowDidMiniaturize))
      ncDefaultObservers.append(.init(NSWindow.didDeminiaturizeNotification, windowDidDeminiaturize))
#if DEBUG
      if DebugConfig.logAllScreenChangeEvents {
        ncDefaultObservers.append(.init(NSWindow.didChangeScreenNotification, { noti in
          let window = noti.object as! NSWindow
          let screenID = window.screen?.screenID.quoted ?? "nil"
          Logger.log.verbose{"WindowDidChangeScreen \(window.windowNumber): \(screenID)"}
        }))
      }
#endif
    } else {
      // TODO: remove existing state...somewhere
      Logger.log("Note: UI state saving is disabled")
    }

    /// Attach this in `applicationWillFinishLaunching`, because `application(openFiles:)` will be called after this but
    /// before `applicationDidFinishLaunching`.
    co = CocoaObserver(Logger.log,
                       prefDidChange: prefDidChange,
                       legacyPrefKeyObserver: self, [
      .logLevel,
      .enableLogging,
      .enableAdvancedSettings,
      .enableCmdN,
      .resumeLastPosition,
      .useMediaKeys,
      //    .hideWindowsWhenInactive, // TODO: #1, see below
    ],[
      .default: ncDefaultObservers
    ])

    co.addAllObservers()

    // Check for legacy pref entries and migrate them to their modern equivalents.
    // Must do this before setting defaults so that checking for existing entries doesn't result in false positives
    LegacyMigration.migrateLegacyPreferences()

#if DEBUG
    /// Set the NSUserDefault NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints to YES to have
    /// `-[NSWindow visualizeConstraints:]` automatically called when [conflicting constraints] happens.
    ///  And/or, set a symbolic breakpoint on `LAYOUT_CONSTRAINTS_NOT_SATISFIABLE` to catch this in the debugger.
    UserDefaults.standard.set(true, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
#endif

    // Call this *before* registering for url events, to guarantee that menu is init'd
    confTableStateManager.startUp()

    HistoryController.shared.start()

    // register for url event
    NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(self.handleURLEvent(event:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

    // Hide Window > "Enter Full Screen" menu item, because this is already present in the Video menu
    UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")

    // handle command line arguments
    let cmdLineArgs = ProcessInfo.processInfo.arguments.dropFirst()
    Logger.log.debug{"All app arguments: \(cmdLineArgs)"}
    startupHandler.parseCommandLine(cmdLineArgs)
  }

  private func registerUserDefaultValues() {
    UserDefaults.standard.register(defaults: [String: Any](uniqueKeysWithValues: Preference.defaultPreference.map { ($0.0.rawValue, $0.1) }))
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    Logger.log("App launched")

    menuController.bindMenuItems()
    // FIXME: this actually causes a window to open in the background. Should wait until intending to show it
    // show alpha in color panels
    NSColorPanel.shared.showsAlpha = true

    // other initializations at App level
    NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = false

    // TODO: try to get tabbing working
    NSWindow.allowsAutomaticWindowTabbing = false
    // NSWindow.userTabbingPreference

    JavascriptPlugin.loadGlobalInstances()

    menuController.updatePluginMenu()
    menuController.refreshBuiltInMenuItemBindings()

    // Register to restore for successive launches. Set status to currently running so that it isn't restored immediately by the next launch
    UserDefaults.standard.setValue(UIState.LaunchLifecycleState.stillRunning.rawValue, forKey: UIState.shared.currentLaunchName)
    UserDefaults.standard.addObserver(self, forKeyPath: UIState.shared.currentLaunchName, options: .new, context: nil)

    startupHandler.doStartup()
  }

  // MARK: - Window Notifications

  /// Sheet window is opening. Track it like a regular window.
  ///
  /// The notification provides no way to actually know which sheet is being added.
  /// So prior to opening the sheet, the caller must manually add it using `UIState.shared.addOpenSheet`.
  private func windowWillBeginSheet(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    let activeWindowName = window.savedStateName
    guard !activeWindowName.isEmpty else { return }

    DispatchQueue.main.async { [self] in
      guard !isTerminating else {
        return
      }
      guard let sheetNames = UIState.shared.openSheetsDict[activeWindowName] else { return }

      for sheetName in sheetNames {
        Logger.log("Sheet opened: \(sheetName.quoted)", level: .verbose)
        UIState.shared.windowsOpen.insert(sheetName)
      }
      UIState.shared.saveCurrentOpenWindowList()
    }
  }

  /// Sheet window did close
  private func windowDidEndSheet(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    let activeWindowName = window.savedStateName
    guard !activeWindowName.isEmpty else { return }

    DispatchQueue.main.async { [self] in
      guard !isTerminating else {
        return
      }
      // NOTE: not sure how to identify which sheet will end. In the future this could cause problems
      // if we use a window with multiple sheets. But for now we can assume that there is only one sheet,
      // so that is the one being closed.
      guard let sheetNames = UIState.shared.openSheetsDict[activeWindowName] else { return }
      UIState.shared.removeOpenSheets(fromWindow: activeWindowName)

      for sheetName in sheetNames {
        Logger.log("Sheet closed: \(sheetName.quoted)", level: .verbose)
        UIState.shared.windowsOpen.remove(sheetName)
      }

      UIState.shared.saveCurrentOpenWindowList()
    }
  }

  /// Saves an ordered list of current open windows (if configured) each time *any* window becomes the main window.
  private func windowDidBecomeMain(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    // Assume new main window is the active window. AppKit does not provide an API to notify when a window is opened,
    // so this notification will serve as a proxy, since a window which becomes active is by definition an open window.
    let activeWindowName = window.savedStateName
    guard !activeWindowName.isEmpty else { return }

    // Query for the list of open windows and save it.
    // Don't do this too soon, or their orderIndexes may not yet be up to date.
    DispatchQueue.main.async { [self] in
      // This notification can sometimes happen if the app had multiple windows at shutdown.
      // We will ignore it in this case, because this is exactly the case that we want to save!
      guard !isTerminating else { return }

      // This notification can also happen after windowDidClose notification,
      // so make sure this a window which is recognized.
      if UIState.shared.windowsMinimized.remove(activeWindowName) != nil {
        Logger.log.verbose{"Minimized window become main; adding to open windows list: \(activeWindowName.quoted)"}
        UIState.shared.windowsOpen.insert(activeWindowName)
      } else {
        // Do not process. Another listener will handle it
        Logger.log.trace{"Window became main: \(activeWindowName.quoted)"}
        return
      }

      UIState.shared.saveCurrentOpenWindowList()
    }
  }

  /// A window was minimized. Need to update lists of tracked windows.
  func windowDidMiniaturize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    let savedStateName = window.savedStateName
    guard !savedStateName.isEmpty else { return }

    DispatchQueue.main.async { [self] in
      guard !isTerminating else {
        return
      }
      Logger.log.verbose{"Window did minimize; adding to minimized windows list: \(savedStateName.quoted)"}
      UIState.shared.windowsOpen.remove(savedStateName)
      UIState.shared.windowsMinimized.insert(savedStateName)
      UIState.shared.saveCurrentOpenWindowList()
    }
  }

  /// A window was un-minimized. Update state of tracked windows.
  private func windowDidDeminiaturize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    let savedStateName = window.savedStateName
    guard !savedStateName.isEmpty else { return }

    DispatchQueue.main.async { [self] in
      guard !isTerminating else {
        return
      }
      Logger.log.verbose{"App window did deminiaturize; removing from minimized windows list: \(savedStateName.quoted)"}
      UIState.shared.windowsOpen.insert(savedStateName)
      UIState.shared.windowsMinimized.remove(savedStateName)
      UIState.shared.saveCurrentOpenWindowList()
    }
  }

  // MARK: - Window Close

  private func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    windowWillClose(window)
  }

  /// This method can be called multiple times safely because it always runs on the main thread and does not
  /// continue unless the window is found to be in an existing list
  func windowWillClose(_ window: NSWindow) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard !isTerminating else { return }

    let windowName = window.savedStateName
    guard !windowName.isEmpty else { return }

    let wasOpen = UIState.shared.windowsOpen.remove(windowName) != nil
    let wasMinimized = UIState.shared.windowsMinimized.remove(windowName) != nil

    guard wasOpen || wasMinimized else {
      Logger.log.verbose{"Window already closed, ignoring: \(windowName.quoted)"}
      return
    }

    Logger.log.verbose{"Window will close: \(windowName)"}
    lastClosedWindowName = windowName

    /// Query for the list of open windows and save it (excluding the window which is about to close).
    /// Most cases are covered by saving when `windowDidBecomeMain` is called, but this covers the case where
    /// the user closes a window which is not in the foreground.
    UIState.shared.saveCurrentOpenWindowList(excludingWindowName: window.savedStateName)

    window.refreshWindowOpenCloseAnimation()

    if let player = (window.windowController as? PlayerWindowController)?.player {
      player.windowController.windowWillClose()
      // Player window was closed; need to remove some additional state
      player.clearSavedState()

      MediaPlayerIntegration.shared.update()
    }

    if window.isOnlyOpenWindow {
      doActionWhenLastWindowWillClose()
    }
  }

  /// Question mark
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    assert(DispatchQueue.isExecutingIn(.main))
    guard !isTerminating else { return false }
    guard startupHandler.state == .doneOpening else { return false }

    /// Certain events (like when PIP is enabled) can result in this being called when it shouldn't.
    /// Another case is when the welcome window is closed prior to a new player window opening.
    /// For these reasons we must keep a list of windows which meet our definition of "open", which
    /// may not match Apple's definition which is more closely tied to `window.isVisible`.
    guard UIState.shared.windowsOpen.isEmpty else {
      Logger.log.verbose{"App will not terminate: \(UIState.shared.windowsOpen.count) windows are still in open list: \(UIState.shared.windowsOpen)"}
      return false
    }

    if let activePlayer = PlayerManager.shared.activePlayer, activePlayer.windowController.isWindowHidden {
      return false
    }

    if Preference.ActionWhenNoOpenWindow(key: .actionWhenNoOpenWindow) == .quit {
      UIState.shared.clearSavedLaunchForThisLaunch()
      Logger.log.verbose{"Last window was closed. App will quit due to configured pref"}
      return true
    }

    Logger.log.verbose{"Last window was closed. Will do configured action"}
    doActionWhenLastWindowWillClose()
    return false
  }

  private func doActionWhenLastWindowWillClose() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard !isTerminating else { return }
    guard let noOpenWindowAction = Preference.ActionWhenNoOpenWindow(key: .actionWhenNoOpenWindow) else { return }
    Logger.log.verbose{"ActionWhenNoOpenWindow: \(noOpenWindowAction). LastClosedWindowName: \(lastClosedWindowName.quoted)"}
    var shouldTerminate: Bool = false

    switch noOpenWindowAction {
    case .none:
      break
    case .quit:
      shouldTerminate = true
    case .sameActionAsLaunch:
      let launchAction: Preference.ActionAfterLaunch = Preference.enum(for: .actionAfterLaunch)
      var quitForAction: Preference.ActionAfterLaunch? = nil

      // Check if user just closed the window we are configured to open. If so, exit app instead of doing nothing
      if let closedWindowName = WindowAutosaveName(lastClosedWindowName) {
        switch closedWindowName {
        case .playbackHistory:
          quitForAction = .historyWindow
        case .openFile:
          quitForAction = .openPanel
        case .welcome:
          guard !UIState.shared.windowsOpen.isEmpty else {
            return
          }
          quitForAction = .welcomeWindow
        default:
          quitForAction = nil
        }
      }

      if launchAction == quitForAction {
        Logger.log.debug{"Last window closed was the configured ActionWhenNoOpenWindow. Will quit instead of re-opening it."}
        shouldTerminate = true
      } else {
        switch launchAction {
        case .welcomeWindow:
          showWelcomeWindow()
        case .openPanel:
          showOpenFileWindow(isAlternativeAction: true)
        case .historyWindow:
          showHistoryWindow(self)
        case .none:
          break
        }
      }
    }

    if shouldTerminate {
      Logger.log.debug{"Clearing all state for this launch because all windows have closed!"}
      UIState.shared.clearSavedLaunchForThisLaunch()
      NSApp.terminate(nil)
    }
  }

  // MARK: - Application termination

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Logger.log("App should terminate")
    if shutdownHandler.beginShutdown() {
      return .terminateNow
    }

    // Tell AppKit that it is ok to proceed with termination, but wait for our reply.
    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    Logger.log("App will terminate")
    Logger.closeLogFiles()
  }

  // MARK: - Open file(s)

  func application(_ sender: NSApplication, openFiles filePaths: [String]) {
    let shouldIgnoreOpenFile = startupHandler.shouldIgnoreOpenFile
    Logger.log.debug{"application(openFiles:) called with: \(filePaths.map{$0.pii}), willIgnore=\(shouldIgnoreOpenFile)"}
    // if launched from command line, should ignore openFile during launch
    guard !shouldIgnoreOpenFile else { return }
    let urls = filePaths.map { URL(fileURLWithPath: $0) }

    // if installing a plugin package
    if let pluginPackageURL = urls.first(where: { $0.pathExtension == "iinaplgz" }) {
      Logger.log.debug{"Opening plugin URL: \(pluginPackageURL.absoluteString.pii.quoted)"}
      showPreferencesWindow(self)
      preferenceWindowController.performAction(.installPlugin(url: pluginPackageURL))
      return
    }

    let openingMultipleWindows = Preference.bool(for: .alwaysOpenInNewWindow) && urls.count > 1
    if !openingMultipleWindows {
      // Use only if opening single window.
      // If multiple windows, don't wait; open each as soon as it loads
      startupHandler.isOpeningNewWindowsForOpenedFiles = true
    }

    DispatchQueue.main.async { [self] in
      Logger.log.debug{"Opening URLs (count: \(urls.count))"}
      var totalFilesOpened = 0

      var wcsForOpenFiles: [PlayerWindowController] = []
      if openingMultipleWindows {
        if urls.count > 10 {
          // TODO: put up a confirmation prompt
          Logger.log.warn{"User requested to open a lot of windows (count: \(urls.count))"}
        }
        for url in urls {
          // open one window per file
          let newPlayer = PlayerManager.shared.getIdleOrCreateNew()
          let playerFilesOpened = newPlayer.openURLs([url])

          guard playerFilesOpened > 0 else { continue }
          newPlayer.openedWindowsSetIndex = wcsForOpenFiles.count
          wcsForOpenFiles.append(newPlayer.windowController)
          totalFilesOpened += playerFilesOpened
        }
      } else {
        // open pending files in single window
        let player = PlayerManager.shared.getActiveOrCreateNew()
        let playerFilesOpened = player.openURLs(urls)
        if playerFilesOpened > 0 {
          wcsForOpenFiles.append(player.windowController)
          totalFilesOpened += playerFilesOpened
        }
      }

      if totalFilesOpened == 0 {
        startupHandler.abortWaitForOpenFilePlayerStartup()

        Logger.log.verbose("Notifying user nothing was opened")
        Utility.showAlert("nothing_to_open")
      } else {
        Logger.log.verbose{"Total new windows opening: \(wcsForOpenFiles.count), with \(totalFilesOpened) files"}
        // Now set wcsForOpenFiles in StartupHandler:
        startupHandler.wcsForOpenFiles = wcsForOpenFiles
      }
      startupHandler.showWindowsIfReady()
    }
  }

  // MARK: - Accept dropped string and URL on Dock icon

  @objc
  func droppedText(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
    Logger.log.verbose{"Text dropped on app's Dock icon"}
    guard let url = pboard.string(forType: .string) else { return }

    guard let player = PlayerCore.active else { return }
    startupHandler.isOpeningNewWindowsForOpenedFiles = true
    if player.openURLString(url) == 0 {
      startupHandler.abortWaitForOpenFilePlayerStartup()
    } else {
      startupHandler.wcsForOpenFiles = [player.windowController]
    }
    startupHandler.showWindowsIfReady()
  }

  // MARK: - URL Scheme

  @objc func handleURLEvent(event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
    guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
    Logger.log.debug{"Handling URL event: \(url)"}
    parsePendingURL(url)
  }

  /**
   Parses the pending iina:// url.
   - Parameter url: the pending URL.
   - Note:
   The iina:// URL scheme currently supports the following actions:

   __/open__
   - `url`: a url or string to open.
   - `new_window`: 0 or 1 (default) to indicate whether open the media in a new window.
   - `enqueue`: 0 (default) or 1 to indicate whether to add the media to the current playlist.
   - `full_screen`: 0 (default) or 1 to indicate whether open the media and enter fullscreen.
   - `pip`: 0 (default) or 1 to indicate whether open the media and enter pip.
   - `mpv_*`: additional mpv options to be passed. e.g. `mpv_volume=20`.
   Options starting with `no-` are not supported.
   */
  private func parsePendingURL(_ url: String) {
    Logger.log("Parsing URL \(url.pii)")
    guard let parsed = URLComponents(string: url) else {
      Logger.log.warn("Cannot parse URL using URLComponents")
      return
    }

    if parsed.scheme != "iina" {
      // try to open the URL directly
      let player = PlayerManager.shared.getActiveOrNewForMenuAction(isAlternative: false)
      startupHandler.isOpeningNewWindowsForOpenedFiles = true
      if player.openURLString(url) == 0 {
        startupHandler.abortWaitForOpenFilePlayerStartup()
      } else {
        startupHandler.wcsForOpenFiles = [player.windowController]
      }
      startupHandler.showWindowsIfReady()
      return
    }

    // handle url scheme
    guard let host = parsed.host else { return }

    if host == "open" || host == "weblink" {
      // open a file or link
      guard let queries = parsed.queryItems else { return }
      let queryDict = [String: String](uniqueKeysWithValues: queries.map { ($0.name, $0.value ?? "") })

      // url
      guard let urlValue = queryDict["url"], !urlValue.isEmpty else {
        Logger.log("Cannot find parameter \"url\", stopped")
        return
      }

      // new_window
      let player: PlayerCore
      if let newWindowValue = queryDict["new_window"], newWindowValue == "1" {
        player = PlayerManager.shared.getIdleOrCreateNew()
      } else {
        player = PlayerManager.shared.getActiveOrNewForMenuAction(isAlternative: false)
      }

      // enqueue
      if let enqueueValue = queryDict["enqueue"], enqueueValue == "1",
         let lastActivePlayer = PlayerManager.shared.lastActivePlayer,
         !lastActivePlayer.info.playlist.isEmpty {
        lastActivePlayer.addToPlaylist(urlValue)
        lastActivePlayer.sendOSD(.addToPlaylist(1))
      } else {
        startupHandler.isOpeningNewWindowsForOpenedFiles = true
        if player.openURLString(urlValue) == 0 {
          startupHandler.abortWaitForOpenFilePlayerStartup()
        } else {
          startupHandler.wcsForOpenFiles = [player.windowController]
        }
      }

      // presentation options
      if let fsValue = queryDict["full_screen"], fsValue == "1" {
        // full_screen
        player.mpv.setFlag(MPVOption.Window.fullscreen, true)
      } else if let pipValue = queryDict["pip"], pipValue == "1" {
        // pip
        player.windowController.enterPIP()
      }

      // mpv options
      for query in queries {
        if query.name.hasPrefix("mpv_") {
          let mpvOptionName = String(query.name.dropFirst(4))
          guard let mpvOptionValue = query.value else { continue }
          Logger.log("Setting \(mpvOptionName) to \(mpvOptionValue)")
          player.mpv.setString(mpvOptionName, mpvOptionValue)
        }
      }

      Logger.log("Finished URL scheme handling")
      startupHandler.showWindowsIfReady()
    }
  }

  // MARK: - App Reopen

  /// Called when user clicks the dock icon of the already-running application.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    // Once termination starts subsystems such as mpv are being shutdown. Accessing mpv
    // once it has been instructed to shutdown can trigger a crash. MUST NOT permit
    // reopening once termination has started.
    guard !isTerminating else { return false }
    guard startupHandler.state == .doneOpening else { return false }
    // OpenFile is an NSPanel, which AppKit considers not to be a window. Need to account for this ourselves.
    guard !hasVisibleWindows && !isShowingOpenFileWindow else { return true }

    Logger.log("Handle reopen")
    doLaunchOrReopenAction()
    return true
  }

  func doLaunchOrReopenAction() {
    guard startupHandler.isDoneLaunching else {
      Logger.log.verbose("Still starting up; skipping actionAfterLaunch")
      return
    }

    let action: Preference.ActionAfterLaunch = Preference.enum(for: .actionAfterLaunch)
    Logger.log.verbose{"Doing actionAfterLaunch: \(action)"}

    switch action {
    case .welcomeWindow:
      showWelcomeWindow()
    case .openPanel:
      showOpenFileWindow(isAlternativeAction: true)
    case .historyWindow:
      showHistoryWindow(self)
    case .none:
      break
    }
  }

  // MARK: - NSApplicationDelegate (other APIs)

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    return dockMenu
  }

  func applicationShouldAutomaticallyLocalizeKeyEquivalents(_ application: NSApplication) -> Bool {
    // Do not re-map keyboard shortcuts based on keyboard position in different locales
    return false
  }

  /// Method to opt-in to secure restorable state.
  ///
  /// From the `Restorable State` section of the [AppKit Release Notes for macOS 14](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14#Restorable-State):
  ///
  /// Secure coding is automatically enabled for restorable state for applications linked on the macOS 14.0 SDK. Applications that
  /// target prior versions of macOS should implement `NSApplicationDelegate.applicationSupportsSecureRestorableState()`
  /// to return`true` so it’s enabled on all supported OS versions.
  ///
  /// This is about conformance to [NSSecureCoding](https://developer.apple.com/documentation/foundation/nssecurecoding)
  /// which protects against object substitution attacks. If an application does not implement this method then a warning will be emitted
  /// reporting secure coding is not enabled for restorable state.
  @available(macOS 12.0, *)
  @MainActor func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Called when this application becomes the frontmost app (as indicated by its name appearing as a menu next to the Apple menu).
  ///
  /// Cases include: at app launch; whenever Dock icon is clicked; when an app window is ordered to front.
  func applicationDidBecomeActive(_ notfication: Notification) {
    // When using custom window style, sometimes AppKit will remove their entries from the Window menu (e.g. when hiding the app).
    // Make sure to add them again if they are missing:
    for player in PlayerManager.shared.playerCores {
      if player.windowController.loaded && !player.isShutDown {
        player.windowController.updateTitle()
      }
    }
  }

  // MARK: - Menu IBActions

  @IBAction func openFile(_ sender: AnyObject) {
    Logger.log("Menu - Open File")
    showOpenFileWindow(isAlternativeAction: sender.tag == AlternativeMenuItemTag)
  }

  @IBAction func openURL(_ sender: AnyObject) {
    Logger.log("Menu - Open URL")
    showOpenURLWindow(isAlternativeAction: sender.tag == AlternativeMenuItemTag)
  }

  /// Only used if `Preference.Key.enableCmdN` is set to `true`
  @IBAction func menuNewWindow(_ sender: Any) {
    showWelcomeWindow()
  }

  @IBAction func menuOpenScreenshotFolder(_ sender: NSMenuItem) {
    let screenshotPath = Preference.string(for: .screenshotFolder)!
    let absoluteScreenshotPath = NSString(string: screenshotPath).expandingTildeInPath
    let url = URL(fileURLWithPath: absoluteScreenshotPath, isDirectory: true)
    NSWorkspace.shared.open(url)
  }

  @IBAction func menuSelectAudioDevice(_ sender: NSMenuItem) {
    if let name = sender.representedObject as? String {
      PlayerCore.active?.setAudioDevice(name)
    }
  }

  @IBAction func showPreferencesWindow(_ sender: AnyObject) {
    Logger.log("Opening Preferences window", level: .verbose)
    preferenceWindowController.openWindow(self)
  }

  @objc func showPluginPreferences(_ sender: NSMenuItem) {
    preferenceWindowController.openPreferenceView(withNibName: "PrefPluginViewController")
  }

  @IBAction func showVideoFilterWindow(_ sender: AnyObject) {
    Logger.log("Opening Video Filter window", level: .verbose)
    vfWindow.openWindow(self)
  }

  @IBAction func showAudioFilterWindow(_ sender: AnyObject) {
    Logger.log("Opening Audio Filter window", level: .verbose)
    afWindow.openWindow(self)
  }

  @IBAction func showAboutWindow(_ sender: AnyObject) {
    Logger.log("Opening About window", level: .verbose)
    aboutWindow.openWindow(self)
  }

  @IBAction func showHistoryWindow(_ sender: AnyObject) {
    Logger.log("Opening History window", level: .verbose)
    historyWindow.openWindow(self)
  }

  @IBAction func showLogWindow(_ sender: AnyObject) {
    Logger.log("Opening Log window", level: .verbose)
    logWindow.openWindow(self)
  }

  @IBAction func showHighlights(_ sender: AnyObject) {
    guideWindow.show(pages: [.highlights])
  }

  @IBAction func helpAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink)!)
  }

  @IBAction func githubAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.githubLink)!)
  }

  @IBAction func websiteAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.websiteLink)!)
  }

  // MARK: - Other window open methods

  func showWelcomeWindow() {
    Logger.log("Showing WelcomeWindow", level: .verbose)
    initialWindow.openWindow(self)
  }

  func showOpenFileWindow(isAlternativeAction: Bool) {
    Logger.log.verbose{"Showing OpenFileWindow: isAlternativeAction=\(isAlternativeAction.yesno)"}
    guard !isShowingOpenFileWindow else {
      // Do not allow more than one open file window at a time
      Logger.log.debug("Ignoring request to show OpenFileWindow: already showing one")
      return
    }
    isShowingOpenFileWindow = true
    let panel = NSOpenPanel()
    panel.setFrameAutosaveName(WindowAutosaveName.openFile.string)
    panel.title = NSLocalizedString("alert.choose_media_file.title", comment: "Choose Media File")
    panel.canCreateDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true

    panel.begin(completionHandler: { [self] result in
      if result == .OK {  /// OK
        Logger.log.verbose{"OpenFile: user chose \(panel.urls.count) files"}
        if Preference.bool(for: .recordRecentFiles) {
          let urls = panel.urls  // must call this on the main thread
          HistoryController.shared.async {
            HistoryController.shared.noteNewRecentDocumentURLs(urls)
          }
        }
        let playerCore = PlayerManager.shared.getActiveOrNewForMenuAction(isAlternative: isAlternativeAction)
        if playerCore.openURLs(panel.urls) == 0 {
          Logger.log("OpenFile: notifying user there is nothing to open", level: .verbose)
          Utility.showAlert("nothing_to_open")
        }
      } else {  /// Cancel
        Logger.log("OpenFile: user cancelled", level: .verbose)
      }
      // AppKit does not consider a panel to be a window, so it won't fire this. Must call ourselves:
      windowWillClose(panel)
      isShowingOpenFileWindow = false
    })
  }

  func showOpenURLWindow(isAlternativeAction: Bool) {
    Logger.log.verbose{"Showing OpenURLWindow: isAltAction=\(isAlternativeAction.yn)"}
    openURLWindow.isAlternativeAction = isAlternativeAction
    openURLWindow.openWindow(self)
  }

  func showInspectorWindow() {
    Logger.log("Showing Inspector window", level: .verbose)
    inspector.openWindow(self)
  }

  // MARK: - Recent Documents

  /// Empties the recent documents list for the application.
  ///
  /// This is part of a workaround for macOS Sonoma clearing the list of recent documents. See the method
  /// `restoreRecentDocuments` and the issue [#4688](https://github.com/iina/iina/issues/4688) for more
  /// information..
  /// - Parameter sender: The object that initiated the clearing of the recent documents.
  @IBAction
  func clearRecentDocuments(_ sender: Any?) {
    HistoryController.shared.clearRecentDocuments(sender)
  }
}
