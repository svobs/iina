//
//  PlayerCore.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PlayerCore: NSObject {
  /// Should always be updated in mpv DQ
  enum LifecycleState: Int, StateEnum {
    case notYetStarted = 1

    case started

    // TODO: add states for playing, paused

    /// Whether stopping of this player has been initiated.
    case stopping

    /// Playback has stopped and the media has been unloaded.
    ///
    /// This is the initial state of a player. The player returns to this state when a
    /// [MPV_EVENT_PROPERTY_CHANGE](https://mpv.io/manual/stable/#command-interface-mpv-event-property-change)
    /// for the `idle-active` property is received with a value of `true`.
    case idle

    /// Whether shutdown of this player has been initiated.
    case shuttingDown

    /// Whether shutdown of this player has completed (mpv has shut down).
    case shutDown

    func isAtLeast(_ minState: LifecycleState) -> Bool {
      return rawValue >= minState.rawValue
    }

    func isNotYet(_ state: LifecycleState) -> Bool {
      return rawValue < state.rawValue
    }
  }

  // MARK: - Multiple instances

  /// - Important: Code referencing this property **must** be run on the main thread as getting the value of this property _may_
  ///              result in a reference the `active` property and that requires use of the main thread.
  static var lastActive: PlayerCore? {
    get {
      assert(DispatchQueue.isExecutingIn(.main))
      return PlayerManager.shared.lastActivePlayer
    }
    set {
      assert(DispatchQueue.isExecutingIn(.main))
      PlayerManager.shared.lastActivePlayer = newValue
    }
  }

  /// - Important: Code referencing this property **must** be run on the main thread because it references
  ///              [NSApplication.windowController`](https://developer.apple.com/documentation/appkit/nsapplication/1428723-mainwindow)
  static var active: PlayerCore? {
    assert(DispatchQueue.isExecutingIn(.main))
    return PlayerManager.shared.activePlayer
  }

  static var mouseLocationAtLastOpen: NSPoint? = nil

  // MARK: - Fields

  let subsystem: Logger.Subsystem
  unowned var log: Logger.Subsystem { self.subsystem }
  var label: String
  let isDemoPlayer: Bool
  var isAudioOnly: Bool { return isDemoPlayer }

  // At launch, wait until all windows are open before resuming video
  var pendingResumeWhenShowingWindow: Bool = false

  var isBufferUnderrun = false
  var cachedRanges: [(Double, Double)] = []

  @Atomic var saveTicketCounter: Int = 0
  @Atomic private var thumbnailReloadTicketCounter: Int = 0

  // Plugins
  var isManagedByPlugin = false
  var userLabel: String?
  var disableUI = false
  var disableWindowAnimation = false

  var touchBarSupport: TouchBarSupport!

  private var subFileMonitor: FileMonitor? = nil

  /// `true` if this Mac is _known to_ have a  [Touch Bar](https://support.apple.com/guide/mac-help/use-the-touch-bar-mchlbfd5b039/mac).
  ///
  /// In order to adhere to energy efficiency best practices IINA should stop the timer that synchronizes the UI when it is not needed.
  /// As one job of the timer is to update the Touch Bar on Macs that have one, IINA needs information such as:
  /// - Does this host have a Touch Bar?
  /// - Is the Touch Bar configured to show app controls?
  /// - Is the Touch Bar awake?
  /// - Is the host being operated in closed clamshell mode?
  ///
  /// This is the kind of information needed to avoid running the timer and updating controls that are not visible. Unfortunately in the
  /// documentation for [NSTouchBar](https://developer.apple.com/documentation/appkit/nstouchbar) Apple
  /// indicates "There’s no need, and no API, for your app to know whether or not there’s a Touch Bar available". So this property is
  /// set based off whether `AppKit` has requested that a `NSTouchBar` object be created by calling
  /// [MakeTouchBar](https://developer.apple.com/documentation/appkit/nsresponder/2544690-maketouchbar).
  /// This property is used to avoid running the timer on Macs that do not have a Touch Bar. It also may avoid running the timer when a
  /// MacBook with a Touch Bar is being operated in closed clamshell mode as `AppKit` will not call `MakeTouchBar` when the
  /// Touch Bar is asleep.
  var needsTouchBar = false

  /// A dispatch queue for auto load feature.
  static let backgroundQueue = DispatchQueue.newDQ(label: "IINAPlayerCoreTask", qos: .background)
  static let playlistQueue = DispatchQueue.newDQ(label: "IINAPlaylistTask", qos: .utility)
  static let thumbnailQueue = DispatchQueue.newDQ(label: "IINAPlayerCoreThumbnailTask", qos: .utility)

  /**
   This ticket will be increased each time before a new task being submitted to `backgroundQueue`.

   Each task holds a copy of ticket value at creation, so that a previous task will perceive and
   quit early if new tasks is awaiting.

   **See also**:

   `autoLoadFilesInCurrentFolder(ticket:)`
   */
  @Atomic var backgroundQueueTicket = 0
  @Atomic var thumbnailQueueTicket = 0

  // Ticket for sync UI update request
  @Atomic private var syncUITicketCounter: Int = 0

  // Windows

  var windowController: PlayerWindowController!

  var window: PlayerWindow {
    return windowController.window as! PlayerWindow
  }

  var mpv: MPVController!
  var videoView: VideoView!

  var keyBindingContext: PlayerInputContext!

  var plugins: [JavascriptPluginInstance] = []
  private var pluginMap: [String: JavascriptPluginInstance] = [:]
  var events = EventController()

  var info: PlaybackInfo

  /// Convenience accessor. Also exists to avoid refactoring legacy code
  var videoGeo: VideoGeometry {
    return windowController.geo.video
  }

  var syncUITimer: Timer?

  var isUsingMpvOSD = false

  var state: LifecycleState = .notYetStarted {
    didSet {
      log.verbose("Updated lifecycleState to \(state)")
    }
  }

  var isActive: Bool {
    return state.isAtLeast(.started) && state.isNotYet(.stopping)
  }

  var isShuttingDown: Bool {
    state.isAtLeast(.shuttingDown)
  }

  var isShutDown: Bool {
    state.isAtLeast(.shutDown)
  }

  var isStopping: Bool {
    state.isAtLeast(.stopping)
  }

  var isIdle: Bool {
    state == .idle
  }

  var isRestoring: Bool {
    return windowController.sessionState.isRestoring
  }

  var isInMiniPlayer: Bool {
    return windowController.isInMiniPlayer
  }

  var isFullScreen: Bool {
    return windowController.isFullScreen
  }

  var isInInteractiveMode: Bool {
    return windowController.isInInteractiveMode
  }

  var receivedEndFileWhileLoading: Bool = false

  /// Set this to `true` if user changes "music mode" status manually. This disables `autoSwitchToMusicMode`
  /// functionality for the duration of this player even if the preference is `true`. But if they manually change the
  /// "music mode" status again, change this to `false` so that the preference is honored again.
  var overrideAutoMusicMode = false

  /// Need this when reusing the window, so that we know that if in full screen, it was set by a previous window session,
  /// and not by a user cmd (although that would be a better way to detect it - should investigate tracking mpv args)
  var didEnterFullScreenViaUserToggle = false

  var isSearchingOnlineSubtitle = false

  /// For supporting mpv `--shuffle` arg, to shuffle playlist when launching from command line
  @Atomic private var shufflePending = false

  var isShowVideoPendingInMiniPlayer: Bool = false
  var miniPlayerShowVideoTimer: Timer? = nil

  // test seeking
  var triedUsingExactSeekForCurrentFile: Bool = false
  var useExactSeekForCurrentFile: Bool = true

  var isPlaylistVisible: Bool {
    isInMiniPlayer ? windowController.miniPlayer.isPlaylistVisible : windowController.isShowing(sidebarTab: .playlist)
  }

  var isOnlyOpenPlayer: Bool {
    for player in PlayerManager.shared.playerCores {
      if player != self && player.windowController.isOpen {
        return false
      }
    }
    return true
  }

  var canSkipBackward: Bool {
    isActive && (info.isPlaying || (info.playbackPositionSec ?? 0.0) > 0.0)
  }

  var canSkipForward: Bool {
    guard isActive else { return false }
    guard let pos = info.playbackPositionSec, let dur = info.playbackDurationSec else { return true }
    return !info.isPaused || pos < dur
  }

  var canPlayPrevTrack: Bool {
    guard isActive, let currentPlayback = info.currentPlayback else { return false }
    return (currentPlayback.playlistPos ?? 0) > 1
  }

  var canPlayNextTrack: Bool {
    guard isActive, let currentPlayback = info.currentPlayback, currentPlayback.state.isAtLeast(.loaded) else { return false }
    let playlistCount = info.playlist.count
    return (currentPlayback.playlistPos ?? 0) < playlistCount - 1
  }

  /// The A loop point established by the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  var abLoopA: Double {
    /// Returns the value of the A loop point, a timestamp in seconds if set, otherwise returns zero.
    /// - Note: The value of the A loop point is not required by mpv to be before the B loop point.
    /// - Returns:value of the mpv option `ab-loop-a`
    get { mpv.getDouble(MPVOption.PlaybackControl.abLoopA) }
    /// Sets the value of the A loop point as an absolute timestamp in seconds.
    ///
    /// The loop points of the mpv A-B loop command can be adjusted at runtime. This method updates the A loop point. Setting a
    /// loop point to zero disables looping, so this method will adjust the value so it is not equal to zero in order to require use of the
    /// A-B command to disable looping.
    /// - Precondition: The A loop point must have already been established using the A-B loop command otherwise the attempt
    ///     to change the loop point will be ignored.
    /// - Note: The value of the A loop point is not required by mpv to be before the B loop point.
    set {
      guard info.abLoopStatus == .aSet || info.abLoopStatus == .bSet else { return }
      mpv.setDouble(MPVOption.PlaybackControl.abLoopA, max(Constants.TimeInterval.minLoopPointTime, newValue))
    }
  }

  /// The B loop point established by the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  var abLoopB: Double {
    /// Returns the value of the B loop point, a timestamp in seconds if set, otherwise returns zero.
    /// - Note: The value of the B loop point is not required by mpv to be after the A loop point.
    /// - Returns:value of the mpv option `ab-loop-b`
    get { mpv.getDouble(MPVOption.PlaybackControl.abLoopB) }
    /// Sets the value of the B loop point as an absolute timestamp in seconds.
    ///
    /// The loop points of the mpv A-B loop command can be adjusted at runtime. This method updates the B loop point. Setting a
    /// loop point to zero disables looping, so this method will adjust the value so it is not equal to zero in order to require use of the
    /// A-B command to disable looping.
    /// - Precondition: The B loop point must have already been established using the A-B loop command otherwise the attempt
    ///     to change the loop point will be ignored.
    /// - Note: The value of the B loop point is not required by mpv to be after the A loop point.
    set {
      guard info.abLoopStatus == .bSet else { return }
      mpv.setDouble(MPVOption.PlaybackControl.abLoopB, max(Constants.TimeInterval.minLoopPointTime, newValue))
    }
  }

  var isABLoopActive: Bool {
    abLoopA != 0 && abLoopB != 0 && mpv.getString(MPVOption.PlaybackControl.abLoopCount) != "0"
  }

  init(_ label: String, isDemoPlayer: Bool = false) {
    let log = Logger.subsystem(forPlayerID: label)
    log.debug{"PlayerCore \(label) init"}
    self.label = label
    self.subsystem = log
    self.info = PlaybackInfo(log: log)
    self.isDemoPlayer = isDemoPlayer
    super.init()
    self.videoView = VideoView(player: self)
    self.mpv = MPVController(playerCore: self)
    self.keyBindingContext = PlayerInputContext(playerCore: self)
    self.windowController = PlayerWindowController(playerCore: self)
    self.touchBarSupport = TouchBarSupport(playerCore: self)
    TouchBarSettings.shared.addObserver(self, forKey: .PresentationModeFnModes)
    TouchBarSettings.shared.addObserver(self, forKey: .PresentationModeGlobal)
    TouchBarSettings.shared.addObserver(self, forKey: .PresentationModePerApp)
  }

  // MARK: - Plugins

  static func reloadPluginForAll(_ plugin: JavascriptPlugin) {
    PlayerManager.shared.playerCores.forEach { $0.reloadPlugin(plugin) }
    AppDelegate.shared.menuController?.updatePluginMenu()
  }

  private func loadPlugins() {
    pluginMap.removeAll()
    plugins = JavascriptPlugin.plugins.compactMap { plugin in
      guard plugin.enabled else { return nil }
      let instance = JavascriptPluginInstance(player: self, plugin: plugin)
      pluginMap[plugin.identifier] = instance
      return instance
    }
  }

  func reloadPlugin(_ plugin: JavascriptPlugin, forced: Bool = false) {
    let id = plugin.identifier
    if let _ = pluginMap[id] {
      if plugin.enabled {
        // no need to reload, unless forced
        guard forced else { return }
        pluginMap[id] = JavascriptPluginInstance(player: self, plugin: plugin)
      } else {
        pluginMap.removeValue(forKey: id)
      }
    } else {
      guard plugin.enabled else { return }
      pluginMap[id] = JavascriptPluginInstance(player: self, plugin: plugin)
    }

    plugins = JavascriptPlugin.plugins.compactMap { pluginMap[$0.identifier] }
    windowController.quickSettingView.updatePluginTabs()
  }

  // MARK: - Control

  /**
   Open a list of urls. If there are more than one urls, add the remaining ones to
   playlist and disable auto loading.

   - Returns: `nil` if no further action is needed, like opened a BD Folder; otherwise the count of playable files.
     `0` if no playable files were found & the player window was not opened.
   */
  @discardableResult
  func openURLs(_ urls: [URL], shouldAutoLoadPlaylist: Bool = true) -> Int? {
    assert(DispatchQueue.isExecutingIn(.main))

    guard !urls.isEmpty else { return 0 }
    log.debug{"OpenURLs (autoLoadPL=\(shouldAutoLoadPlaylist.yn)): \(urls.map{Playback.path(from: $0).pii})"}
    // Reset:
    info.shouldAutoLoadFiles = shouldAutoLoadPlaylist

    PlayerCore.mouseLocationAtLastOpen = NSEvent.mouseLocation

    let urls = Utility.resolveURLs(urls)

    // Handle folder URL (to support mpv shuffle, etc), BD folders and m3u / m3u8 files first.
    // For these cases, mpv will load/build the playlist and notify IINA when it can be retrieved.
    if urls.count == 1 {

      let loneURL = urls[0]
      if isBDFolder(loneURL)
          || Utility.playlistFileExt.contains(loneURL.absoluteString.lowercasedPathExtension) {

        info.shouldAutoLoadFiles = false
        openPlayerWindow(urls)
        return nil
      }
    }
    // Else open multiple URL args...

    // Filter URL args for playable files (video/audio), because mpv will "play" image files, text files (anything?)
    let playableFiles = getPlayableFiles(in: urls)
    let count = playableFiles.count

    log.verbose{"Found \(count) playable files for \(urls.count) requested URLs"}
    // check playable files count
    guard count > 0 else {
      return 0
    }

    if shouldAutoLoadPlaylist {
      info.shouldAutoLoadFiles = (count == 1)
    }

    // open the first file
    openPlayerWindow(playableFiles)
    return count
  }

  @discardableResult
  func openURL(_ url: URL) -> Int? {
    return openURLs([url])
  }

  /// Returns number of playable URLs opened. If `0`, no player window was opened.
  @discardableResult
  func openURLString(_ str: String) -> Int? {
    if str == "-" {
      info.shouldAutoLoadFiles = false  // reset
      openPlayerWindow([URL(string: "stdin")!])
      return 1
    }
    if str.first == "/" {
      return openURL(URL(fileURLWithPath: str))
    } else {
      // For apps built with Xcode 15 or later the behavior of the URL initializer has changed when
      // running under macOS Sonoma or later. The behavior now matches URLComponents and will
      // automatically percent encode characters. Must not apply percent encoding to the string
      // passed to the URL initializer if the new new behavior is active.
      var performPercentEncoding = true
#if compiler(>=5.9)
      if #available(macOS 14, *) {
        performPercentEncoding = false
      }
#endif
      var pstr = str
      if performPercentEncoding {
        guard let encoded = str.addingPercentEncoding(withAllowedCharacters: .urlAllowed) else {
          log.error("Cannot add percent encoding for \(str)")
          return 0
        }
        pstr = encoded
      }
      guard let url = URL(string: pstr) else {
        log.error("Cannot parse url for \(pstr)")
        return 0
      }
      return openURL(url)
    }
  }

  /// Loads the first URL into the player, and adds any remaining URLs to playlist.
  /// The caller must ensure that `urls` is *never* empty!
  private func openPlayerWindow(_ urls: [URL]) {
    assert(DispatchQueue.isExecutingIn(.main))

    guard urls.count > 0 else {
      log.fatalError("Cannot open player window: empty url list!")
    }

    let playback = Playback(url: urls[0])

    if playback.isNetworkResource {
      windowController.close()
      AppDelegate.shared.openURLWindow.showLoadingScreen(playerCore: self)
    }

    /// Need to use `sync` so that:
    /// 1. Prev use of mpv core can finish stopping / drain queue
    /// 2. `currentPlayback` is guaranteed to update before returning, so that `PlayerCore.activeOrNew` does not return same player
    mpv.queue.sync { [self] in
      let path = playback.path
      info.currentPlayback = playback
      log.debug{"Opening PlayerWindow for \(path.pii.quoted), playerState=\(state), sessionState=\(windowController.sessionState)"}

      info.hdrEnabled = Preference.bool(for: .enableHdrSupport)

      // Reset state flags
      if state == .stopping || state == .idle {
        state = .started
      }

      // Load into cache while in mpv queue first
      MediaMetaCache.shared.ensureVideoMetaIsCached(forURL: info.currentURL, log)

      DispatchQueue.main.async { [self] in
        if !windowController.sessionState.isRestoring {
          windowController.osd.clearQueuedOSDs()
          windowController.sessionState = windowController.sessionState.newSession()
        }

        /// This doesn't apply to restore. That is handled in `mpvRestoreWorkItem`.
        let pauseUntilWindowOpen = !windowController.isOpen

        windowController.openWindow(nil)

        mpv.queue.async { [self] in
          // Send load file command
          mpv.command(.loadfile, args: [path])

          if case .restoring(let priorState) = windowController.sessionState {
            priorState.restoreMpvProperties(to: self)
            return
          }

          if pauseUntilWindowOpen {
            // Pause until window opens, to avoid blips or other loading unpleasantness
            mpv.setFlag(MPVOption.PlaybackControl.pause, true)
            // ...or stay paused if configured
            pendingResumeWhenShowingWindow = !Preference.bool(for: .pauseWhenOpen)
          }

          // Not restoring

          if urls.count > 1 {
            log.verbose{"Adding \(urls.count - 1) files to playlist. Autoload=\(info.shouldAutoLoadFiles.yn)"}
            _addToPlaylist(urls: urls[1..<urls.count], silent: true)
            postNotification(.iinaPlaylistChanged)
          } else {
            // Only one entry in playlist, but still need to pull it from mpv
            _reloadPlaylist()
          }

          if Preference.bool(for: .enablePlaylistLoop) {
            mpv.setString(MPVOption.PlaybackControl.loopPlaylist, "inf")
          }
          if Preference.bool(for: .enableFileLoop) {
            mpv.setString(MPVOption.PlaybackControl.loopFile, "inf")
          }
          
          if Preference.bool(for: .autoRepeat) {
            let loopMode = Preference.DefaultRepeatMode(rawValue: Preference.integer(for: .defaultRepeatMode))
            setLoopMode(loopMode == .file ? .file : .playlist)
          }
        }
      }
    }
  }

  // Does nothing if already started
  func start() {
    guard state == .notYetStarted else { return }

    log.verbose("Player start")

    startMPV()
    /// This will create & add the `GLVideoLayer` if it was not already init:
    videoView.wantsLayer = true
    loadPlugins()
    if isAudioOnly {
      log.debug("Player is audio only. Will not init video")
    } else {
      initVideo()
    }
    state = .started
  }

  private func startMPV() {
    // set path for youtube-dl
    let oldPath = String(cString: getenv("PATH")!)
    var path = Utility.exeDirURL.path + ":" + oldPath
    if let customYtdlPath = Preference.string(for: .ytdlSearchPath), !customYtdlPath.isEmpty {
      path = customYtdlPath + ":" + path
    }
    setenv("PATH", path, 1)
    log.debug{"Set env path to \(path.pii)"}

    // set http proxy
    if let proxy = Preference.string(for: .httpProxy), !proxy.isEmpty {
      setenv("http_proxy", "http://" + proxy, 1)
      log.debug{"Set env http_proxy to \(proxy.pii)"}
    }

    mpv.mpvInit()
    events.emit(.mpvInitialized)

    if !getAudioDevices().contains(where: { $0["name"] == Preference.string(for: .audioDevice)! }) {
      log.verbose("Defaulting mpv audioDevice to 'auto'")
      setAudioDevice("auto")
    }
  }

  private func initVideo() {
    log.verbose("Init video")

    // init mpv render context.
    mpv.mpvInitRendering()
    videoView.startDisplayLink()
  }

  func saveState() {
    PlayerSaveState.save(self)
  }

  func clearSavedState() {
    UIState.shared.clearPlayerSaveState(forPlayerID: label)
  }

  /// Initiate shutdown of this player.
  ///
  /// This method is intended to only be used during application termination. Once shutdown has been initiated player methods
  /// **must not** be called.
  /// - Important: As a part of shutting down the player this method sends a quit command to mpv. Even though the command is
  ///     sent to mpv using the synchronous API mpv executes the quit command asynchronously. The player is not fully shutdown
  ///     until mpv finishes executing the quit command and shuts down.
  /// - Note: If the user clicks on `Quit` right after starting to play a video then the background task may still be running and
  ///     loading files into the playlist and adding subtitles. If that is the case then the background task **must be** stopped before
  ///     sending a `quit` command to mpv. If the background task is allowed to access mpv after a `quit` command has been
  ///     sent mpv could crash. The `stop` method takes care of instructing the background task to stop and will wait for it to stop
  ///     before sending a `stop` command to mpv. _However_ mpv will stop on its own if the end of the video is reached. When
  ///     that happens while IINA is quitting then this method may be called with the background task still running. If the background
  ///     task is still running this method only changes the player state. When the background task ends it will notice that shutting
  ///     down was in progress and will call this method again to continue the process of shutting down..
  func shutdown() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard state.isNotYet(.shuttingDown) else {
      log.verbose("Player is already shutting down")
      return
    }
    guard state.isAtLeast(.started) else {
      log.debug("Player was never started")
      mpvHasShutdown()
      return
    }
    log.debug("Shutting down player")
    state = .shuttingDown
    savePlaybackPosition() // Save state to mpv watch-later (if enabled)
    refreshSyncUITimer()   // Shut down timer
    mpv.mpvQuit()
  }

  /// Respond to the mpv core shutting down.
  /// - Important: Normally shutdown of the mpv core occurs after IINA has sent a `quit` command to the mpv core and that
  ///     asynchronous command completes. _However_ this can also occur when the user uses mpv's IPC interface to send a quit
  ///     command directly to mpv. Accessing a mpv core after it has shutdown is not permitted by mpv and can trigger a crash.
  ///     When IINA is in control of the termination sequence it is able to prevent access to the mpv core. For example, observers are
  ///     removed before sending the `quit` command. But when shutdown is initiated by mpv the actions IINA takes before
  ///     shutting down mpv are bypassed. This means a mpv initiated shutdown can't be made fully deterministic as there are inherit
  ///     windows of vulnerability that can not be fully closed. IINA has no choice but to support a mpv initiated shutdown as best it
  ///     can.
  func mpvHasShutdown() {
    assert(DispatchQueue.isExecutingIn(.main))
    let isMPVInitiated = state.isNotYet(.shuttingDown)
    let suffix = isMPVInitiated ? " (initiated by mpv)" : ""
    log.debug{"Player has shut down\(suffix)"}
    // If mpv shutdown was initiated by mpv then the player state has not been saved.
    if isMPVInitiated {
      state = .shuttingDown  // Make sure to indicate shutdown before calling `refreshSyncUITimer`
      savePlaybackPosition() // Save state to mpv watch-later (if enabled)
      refreshSyncUITimer()   // Shut down timer
      mpv.removeObservers()
    }
    videoView.uninit()       // Shut down DisplayLink. Has its own lock.

    mpv.queue.sync { [self] in  // run in queue to avoid race condition when handling events in queue, which checks mpv!=nil
      mpv.mpvDestroy()
    }
    state = .shutDown
    PlayerManager.shared.removePlayer(withLabel: label)
    postNotification(.iinaPlayerShutdown)
    if isMPVInitiated {
      // Initiate application termination. AppKit requires this be done from the main thread,
      // however the main dispatch queue must not be used to avoid blocking the queue as per
      // instructions from Apple.
      RunLoop.main.perform(inModes: [.common]) {
        guard !AppDelegate.shared.isTerminating else { return }
        NSApp.terminate(nil)
      }
    }
  }

  func enterMusicMode(automatically: Bool = false, withNewVidGeo newVidGeo: VideoGeometry? =  nil) {
    log.debug{"Switch to mini player, automatically=\(automatically)"}
    if !automatically {
      // Toggle manual override
      overrideAutoMusicMode = !overrideAutoMusicMode
      log.verbose{"Changed overrideAutoMusicMode to \(overrideAutoMusicMode)"}
    }
    windowController.enterMusicMode(withNewVidGeo: newVidGeo)
    events.emit(.musicModeChanged, data: true)
  }

  func exitMusicMode(automatically: Bool = false, withNewVidGeo newVidGeo: VideoGeometry? =  nil) {
    log.debug{"Switch to normal window from mini player, automatically=\(automatically)"}
    if !automatically {
      overrideAutoMusicMode = !overrideAutoMusicMode
      log.verbose{"Changed overrideAutoMusicMode to \(overrideAutoMusicMode)"}
    }
    windowController.exitMusicMode(withNewVidGeo: newVidGeo)
    windowController.updateTitle()

    events.emit(.musicModeChanged, data: false)
  }

  // MARK: - MPV commands

  func togglePause() {
    info.isPaused ? resume() : pause()
  }

  /// Pause playback.
  ///
  /// - Important: Setting the `pause` property will cause `mpv` to emit a `MPV_EVENT_PROPERTY_CHANGE` event. The
  ///     event will still be emitted even if the `mpv` core is idle. If the setting `Pause when machine goes to sleep` is
  ///     enabled then `PlayerWindowController` will call this method in response to a
  ///     `NSWorkspace.willSleepNotification`. That happens even if the window is closed and the player is idle. In
  ///     response the event handler in `MPVController` will call `VideoView.displayIdle`. The suspicion is that calling this
  ///     method results in a call to `CVDisplayLinkCreateWithActiveCGDisplays` which fails because the display is
  ///     asleep. Thus `setFlag` **must not** be called if the `mpv` core is idle or stopping. See issue
  ///     [#4520](https://github.com/iina/iina/issues/4520)
  func pause() {
    assert(DispatchQueue.isExecutingIn(.main))
    let isNormalSpeed = info.playSpeed == 1
    mpv.queue.async { [self] in
      guard isActive else { return }
      /// Set this so that callbacks will fire even though `info.isPaused` was already set
      info.pauseStateWasChangedLocally = true
      mpv.setFlag(MPVOption.PlaybackControl.pause, true)
    }
    if !isNormalSpeed && Preference.bool(for: .resetSpeedWhenPaused) {
      setSpeed(1, forceResume: false)
    }
    windowController.updatePlayButtonAndSpeedUI()
  }

  private func _resume() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    if shouldRestartFromEOF() {
      _seek(0, absolute: true, option: .exact)
    }
    mpv.setFlag(MPVOption.PlaybackControl.pause, false)
  }

  /// Restart playback if at EOF & feature is enabled.
  /// If auto-play next track in playlist is enabled, must be last track to restart.
  private func shouldRestartFromEOF() -> Bool {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    guard mpv.getFlag(MPVProperty.eofReached) && Preference.bool(for: .resumeFromEndRestartsPlayback) else {
      return false
    }
    if Preference.bool(for: .playlistAutoPlayNext) {
      let playlistPos = mpv.getInt(MPVProperty.playlistPos)
      let playlistCount = mpv.getInt(MPVProperty.playlistCount)
      return playlistPos == playlistCount - 1
    }
    return true
  }

  func resume() {
    mpv.queue.async { [self] in
      /// Set this so that callbacks will fire even though `info.isPaused` was already set
      info.pauseStateWasChangedLocally = true
      _resume()
    }
    windowController.updatePlayButtonAndSpeedUI()
  }

  /// Stop playback and unload the media.
  ///
  /// This method is called when a window closes. The player may be:
  /// - In one of the "active" states
  /// - In the `idle` state
  /// - In the `shutdown` state
  func stop() {
    assert(DispatchQueue.isExecutingIn(.main))

    mpv.queue.async { [self] in
      guard state.isNotYet(.stopping) else {
        log.debug("Stop called, but state is already \(state); aborting redundant stop call")
        return
      }

      log.verbose("Stop called")

      stopWatchingSubFile()

      /// call this BEFORE setting state to `.stopping`
      savePlaybackPosition() // Save state to mpv watch-later (if enabled)

      state = .stopping

      DispatchQueue.main.async { [self] in
        videoView.stopDisplayLink()
      }

      // If the user immediately closes the player window it is possible the background task may still
      // be working to load subtitles. Invalidate the ticket to get that task to abandon the work.
      $backgroundQueueTicket.withLock { $0 += 1 }
      $thumbnailQueueTicket.withLock { $0 += 1 }

      // Reset playback state
      info.playbackPositionSec = nil
      info.playbackDurationSec = nil
      info.playlist = []

      info.$matchedSubs.withLock { $0.removeAll() }

      // Do not send a stop command to mpv if it is already stopped. This happens when quitting is
      // initiated directly through mpv.
      guard state != .idle else { return }
      log.debug("Stopping playback")

      // Do not enqueue after window is closed (and info.currentPlayback is nil)
      sendOSD(.stop)
      DispatchQueue.main.async { [self] in
        refreshSyncUITimer()
      }
      mpv.command(.stop, level: .verbose)


    }
  }

  /// Playback has stopped and the media has been unloaded.
  ///
  /// This method is called by `MPVController` when mpv emits an event indicating the asynchronous mpv `stop` command
  /// has completed executing.
  func playbackStopped() {
    log.debug("Playback has stopped")
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    /// Do not set player's state = `stopped` here. This method seems to get called when it shouldn't
    /// (e.g., when changing current pos in playlist)

    DispatchQueue.main.async { [self] in
      postNotification(.iinaPlayerStopped)
    }
  }

  func toggleMute(_ set: Bool? = nil) {
    mpv.queue.async { [self] in
      let newState = set ?? !mpv.getFlag(MPVOption.Audio.mute)
      mpv.setFlag(MPVOption.Audio.mute, newState)
    }
  }

  // Seek %
  func seek(percent: Double, forceExact: Bool = false) {
    mpv.queue.async { [self] in
      var percent = percent
      // mpv will play next file automatically when seek to EOF.
      // We clamp to a Range to ensure that we don't try to seek to 100%.
      // however, it still won't work for videos with large keyframe interval.
      if let duration = info.playbackDurationSec,
         duration > 0 {
        percent = percent.clamped(to: 0..<100)
      }
      let useExact = forceExact ? true : Preference.bool(for: .useExactSeek)
      let seekMode = useExact ? "absolute-percent+exact" : "absolute-percent"
      mpv.command(.seek, args: ["\(percent)", seekMode], checkError: false)
    }
  }

  // Seek Relative
  func seek(relativeSecond: Double, option: Preference.SeekOption) {
    seek(relativeSecond, absolute: false, option: option)
  }

  private func seek(_ time: Double, absolute: Bool, option: Preference.SeekOption) {
    mpv.queue.async { [self] in
      _seek(time, absolute: absolute, option: option)
    }
  }

  private func _seek(_ time: Double, absolute: Bool, option: Preference.SeekOption) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard isActive else { return }
    let kind = absolute ? "absolute" : "relative"

    switch option {
    case .keyframes:
      mpv.command(.seek, args: ["\(time)", "\(kind)+keyframes"], checkError: false)

    case .exact:
      mpv.command(.seek, args: ["\(time)", "\(kind)+exact"], checkError: false)

    case .auto:
      // for each file , try use exact and record interval first
      if !triedUsingExactSeekForCurrentFile {
        mpv.recordedSeekTimeListener = { [unowned self] interval in
          // if seek time < 0.05, then can use exact
          self.useExactSeekForCurrentFile = interval < 0.05
        }
        mpv.needRecordSeekTime = true
        triedUsingExactSeekForCurrentFile = true
      }
      let seekMode = useExactSeekForCurrentFile ? "\(kind)+exact" : kind
      mpv.command(.seek, args: ["\(time)", seekMode], checkError: false)
    }
  }

  // Seek Absolute
  func seek(absoluteSecond: Double, forceExact: Bool = true) {
    let useExact = forceExact ? true : Preference.bool(for: .useExactSeek)
    seek(absoluteSecond, absolute: true, option: useExact ? .exact : .defaultValue)
  }

  func seek(absoluteSecond: Double, option: Preference.SeekOption) {
    seek(absoluteSecond, absolute: true, option: option)
  }

  func frameStep(backwards: Bool) {
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // It must be running when stepping to avoid slowdowns caused by mpv waiting for IINA to call
    // mpv_render_report_swap.
    videoView.displayActive()
    mpv.queue.async { [self] in
      if backwards {
        mpv.command(.frameBackStep)
      } else {
        mpv.command(.frameStep)
      }
    }
  }

  /// Takes a screenshot, attempting to augment mpv's `screenshot` command with additional functionality & control, for example
  /// the ability to save to clipboard instead of or in addition to file, and displaying the screenshot's thumbnail via the OSD.
  /// Returns `true` if a command was sent to mpv; `false` if no command was sent.
  ///
  /// If the prefs for `Preference.Key.screenshotSaveToFile` and `Preference.Key.screenshotCopyToClipboard` are both `false`,
  /// this function does nothing and returns `false`.
  ///
  /// ## Determining screenshot flags
  /// If `keyBinding` is present, it should contain an mpv `screenshot` command. If its action includes any flags, they will be
  /// used. If `keyBinding` is not present or its command has no flags, the value for `Preference.Key.screenshotIncludeSubtitle` will
  /// be used to determine the flags:
  /// - If `true`, the command `screenshot subtitles` will be sent to mpv.
  /// - If `false`, the command `screenshot video` will be sent to mpv.
  ///
  /// Note: IINA overrides mpv's behavior in some ways:
  /// 1. As noted above, if the stored values for `Preference.Key.screenshotSaveToFile` and `Preference.Key.screenshotCopyToClipboard` are
  /// set to false, all screenshot commands will be ignored.
  /// 2. When no flags are given with `screenshot`: instead of defaulting to `subtitles` as mpv does, IINA will use the value for
  /// `Preference.Key.screenshotIncludeSubtitle` to decide between `subtitles` or `video`.
  @discardableResult
  func screenshot(fromKeyBinding keyBinding: KeyMapping? = nil) -> Bool {
    assert(DispatchQueue.isExecutingIn(.main))

    /// `screenshot-raw`? (i.e. not `screenshot`)
    var isRaw: Bool = false
    let saveToFile = Preference.bool(for: .screenshotSaveToFile)
    let saveToClipboard = Preference.bool(for: .screenshotCopyToClipboard)
    guard saveToFile || saveToClipboard else {
      log.debug("Ignoring screenshot request: all forms of screenshots are disabled in prefs")
      return false
    }

    guard let vid = info.vid, vid > 0 else {
      log.debug("Ignoring screenshot request: no video stream is being played")
      return false
    }

    log.debug{"Screenshot requested by user\(keyBinding == nil ? "" : " (rawAction: \(keyBinding!.rawAction?.quoted ?? "nil"))")"}

    var commandFlags: [String] = []

    if let keyBinding {
      var canUseIINAScreenshot = true

      guard let rawAction = keyBinding.rawAction, let action = keyBinding.action,
            let commandName = keyBinding.action?.first,
              (commandName == MPVCommand.screenshotRaw.rawValue || commandName == MPVCommand.screenshot.rawValue) else {
        log.error{"Cannot take screenshot: unexpected first token in key binding action: \(keyBinding.rawAction?.quoted ?? "nil")"}
        return false
      }
      isRaw = commandName == MPVCommand.screenshotRaw.rawValue
      if isRaw {
        // Cannot yet support screenshot-raw
        canUseIINAScreenshot = false
      }
      if action.count > 1 {
        commandFlags = action[1].split(separator: "+").map{String($0)}

        for flag in commandFlags {
          switch flag {
          case "window", "subtitles", "video":
            // These are supported
            break
          case "each-frame":
            // Option is not currently supported by IINA's screenshot command
            canUseIINAScreenshot = false
          default:
            // Unexpected flag. Let mpv decide how to handle
            log.warn{"Taking screenshot: Unrecognized flag for mpv '\(commandName)' command: '\(flag)'"}
            canUseIINAScreenshot = false
          }
        }
      }

      if !canUseIINAScreenshot {
        let returnValue = mpv.command(rawString: rawAction)
        return returnValue == 0
      }
    }

    if commandFlags.isEmpty {
      let includeSubtitles = Preference.bool(for: .screenshotIncludeSubtitle)
      commandFlags.append(includeSubtitles ? "subtitles" : "video")
    }

    mpv.queue.async { [self] in
      guard isActive else { return }
      if isRaw {
        mpv.asyncCommand(.screenshotRaw, args: commandFlags, replyUserdata: MPVController.UserData.screenshotRaw)
      } else {
        mpv.asyncCommand(.screenshot, args: commandFlags, replyUserdata: MPVController.UserData.screenshot)
      }
    }
    return true
  }

  /// Initializes and returns an image object with the contents of the specified URL.
  ///
  /// At this time, the normal [NSImage](https://developer.apple.com/documentation/appkit/nsimage/1519907-init)
  /// initializer will fail to create an image object if the image file was encoded in [JPEG XL](https://jpeg.org/jpegxl/) format.
  /// In older versions of macOS this will also occur if the image file was encoded in [WebP](https://en.wikipedia.org/wiki/WebP/)
  /// format. As these are supported formats for screenshots this method will fall back to using FFmpeg to create the `NSImage` if
  /// the normal initializer fails to return an object.
  /// - Parameter url: The URL identifying the image.
  /// - Returns: An initialized `NSImage` object or `nil` if the method cannot create an image representation from the contents
  ///       of the specified URL.
  private func createImage(_ url: URL) -> NSImage? {
    if let image = NSImage(contentsOf: url) {
      return image
    }
    // The following internal property was added to provide a way to disable the FFmpeg image
    // decoder should a problem be discovered by users running old versions of macOS.
    guard Preference.bool(for: .enableFFmpegImageDecoder) else { return nil }
    log.debug{"Using FFmpeg to decode screenshot: \(url)"}
    return FFmpegController.createNSImage(withContentsOf: url)
  }

  func screenshotCallback() {
    let saveToFile = Preference.bool(for: .screenshotSaveToFile)
    let saveToClipboard = Preference.bool(for: .screenshotCopyToClipboard)
    guard saveToFile || saveToClipboard else { return }
    log.verbose{"Screenshot done: saveToFile=\(saveToFile), saveToClipboard=\(saveToClipboard)"}

    guard let imageFolder = mpv.getString(MPVOption.Screenshot.screenshotDir) else { return }
    guard let lastScreenshotURL = Utility.getLatestScreenshot(from: imageFolder) else { return }

    defer {
      if !saveToFile {
        try? FileManager.default.removeItem(at: lastScreenshotURL)
      }
    }

    guard let screenshotImage = createImage(lastScreenshotURL) else {
      self.sendOSD(.screenshot)
      return
    }

    if saveToClipboard {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([screenshotImage])
    }
    guard Preference.bool(for: .screenshotShowPreview) else {
      sendOSD(.screenshot)
      if !saveToFile {
        try? FileManager.default.removeItem(at: lastScreenshotURL)
      }
      return
    }

    DispatchQueue.main.async { [self] in
      let osdViewController = ScreenshootOSDView()
      // Shrink to some fraction of the currently displayed video
      let relativeSize = windowController.videoView.frame.size * 0.3
      let previewImageSize = screenshotImage.size.shrink(toSize: relativeSize)
      osdViewController.setImage(screenshotImage,
                       size: previewImageSize,
                       fileURL: saveToFile ? lastScreenshotURL : nil)

      sendOSD(.screenshot, forcedTimeout: 5, accessoryViewController: osdViewController)
    }
  }

  /// Invoke the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  ///
  /// The A-B loop command cycles mpv through these states:
  /// - Cleared (looping disabled)
  /// - A loop point set
  /// - B loop point set (looping enabled)
  ///
  /// When the command is first invoked it sets the A loop point to the timestamp of the current frame. When the command is invoked
  /// a second time it sets the B loop point to the timestamp of the current frame, activating looping and causing mpv to seek back to
  /// the A loop point. When the command is invoked again both loop points are cleared (set to zero) and looping stops.
  func abLoop() {
    mpv.queue.async { [self] in
      // may subject to change
      let returnValue = mpv.command(.abLoop)
      guard returnValue == 0 else { return }

      syncAbLoop()
      sendOSD(.abLoop(info.abLoopStatus))
    }
  }

  /// Synchronize IINA with the state of the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  func syncAbLoop() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard isActive else { return }

    // Obtain the values of the ab-loop-a and ab-loop-b options representing the A & B loop points.
    let a = abLoopA
    let b = abLoopB
    if a == 0 {
      if b == 0 {
        // Neither point is set, the feature is disabled.
        info.abLoopStatus = .cleared
      } else {
        // The B loop point is set without the A loop point having been set. This is allowed by mpv
        // but IINA is not supposed to allow mpv to get into this state, so something has gone
        // wrong. This is an internal error. Log it and pretend that just the A loop point is set.
        log.error{"Unexpected A-B loop state, ab-loop-a is \(a) ab-loop-b is \(b)"}
        info.abLoopStatus = .aSet
      }
    } else {
      // A loop point has been set. B loop point must be set as well to activate looping.
      info.abLoopStatus = b == 0 ? .aSet : .bSet
    }
    // The play slider has knobs representing the loop points, make insure the slider is in sync.
    windowController?.syncPlaySliderABLoop()
    log.verbose{"Synchronized info.abLoopStatus: \(info.abLoopStatus)"}
  }

  func togglePlaylistLoop() {
    mpv.queue.async { [self] in
      guard isActive else { return }
      let loopMode = getLoopMode()
      if loopMode == .playlist {
        setLoopMode(.off)
      } else {
        setLoopMode(.playlist)
      }
    }
  }

  func toggleFileLoop() {
    mpv.queue.async { [self] in
      guard isActive else { return }
      let loopMode = getLoopMode()
      if loopMode == .file {
        setLoopMode(.off)
      } else {
        setLoopMode(.file)
      }
    }
  }

  func getLoopMode() -> LoopMode {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    let loopFileStatus = mpv.getString(MPVOption.PlaybackControl.loopFile)
    guard loopFileStatus != "inf" else { return .file }
    if let loopFileStatus = loopFileStatus, let count = Int(loopFileStatus), count != 0 {
      return .file
    }
    let loopPlaylistStatus = mpv.getString(MPVOption.PlaybackControl.loopPlaylist)
    guard loopPlaylistStatus != "inf", loopPlaylistStatus != "force" else { return .playlist }
    guard let loopPlaylistStatus = loopPlaylistStatus, let count = Int(loopPlaylistStatus) else {
      return .off
    }
    return count == 0 ? .off : .playlist
  }

  private func setLoopMode(_ newMode: LoopMode) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard isActive else { return }
    switch newMode {
    case .playlist:
      mpv.setString(MPVOption.PlaybackControl.loopPlaylist, "inf")
      mpv.setString(MPVOption.PlaybackControl.loopFile, "no")
    case .file:
      mpv.setString(MPVOption.PlaybackControl.loopFile, "inf")
    case .off:
      mpv.setString(MPVOption.PlaybackControl.loopPlaylist, "no")
      mpv.setString(MPVOption.PlaybackControl.loopFile, "no")
    }
  }

  func nextLoopMode() {
    mpv.queue.async { [self] in
      guard isActive else { return }
      setLoopMode(getLoopMode().next())
    }
  }

  func toggleShuffle() {
    mpv.queue.async { [self] in
      guard isActive else { return }
      mpv.command(.playlistShuffle)
      _reloadPlaylist()
    }
  }

  func setVolume(_ volume: Double) {
    mpv.queue.async { [self] in
      let constrainedVolume = volume.clamped(to: 0...Preference.double(for: .maxVolume))
      info.volume = constrainedVolume
      // Always show OSD to acknowledge input, even if volume did not change:
      sendOSD(.volume(Int(constrainedVolume)))
      mpv.setDouble(MPVOption.Audio.volume, constrainedVolume)
      // Save default for future players:
      Preference.set(constrainedVolume, for: .softVolume)
    }
  }

  func _setTrack(_ index: Int, forType trackType: MPVTrack.TrackType, silent: Bool = false) {
    log.verbose{"Setting \(trackType) track to \(index)"}
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard isActive else { return }

    let name: String
    switch trackType {
    case .audio:
      name = MPVOption.TrackSelection.aid
    case .video:
      name = MPVOption.TrackSelection.vid
    case .sub:
      name = MPVOption.TrackSelection.sid
    case .secondSub:
      name = MPVOption.Subtitles.secondarySid
    }
    mpv.setInt(name, index)
    reloadSelectedTracks(silent: silent)
  }

  func setTrack(_ index: Int, forType: MPVTrack.TrackType, silent: Bool = false) {
    mpv.queue.async { [self] in
      _setTrack(index, forType: forType, silent: silent)
    }
  }

  /// Set playback speed.
  /// If `forceResume` is `true`, then always resume if paused; if `false`, never resume if paused;
  /// if `nil`, then resume if paused based on pref setting.
  func setSpeed(_ speed: Double, forceResume: Bool? = nil) {
    let speedTrunc = speed.truncatedTo6()
    info.playSpeed = speedTrunc  // set preemptively to keep UI in sync
    mpv.queue.async { [self] in
      guard isActive else { return }
      log.verbose("Setting speed to \(speedTrunc)")
      mpv.setDouble(MPVOption.PlaybackControl.speed, speedTrunc)

      /// If `resetSpeedWhenPaused` is enabled, then speed is reset to 1x when pausing.
      /// This will create a subconscious link in the user's mind between "pause" -> "unset speed".
      /// Try to stay consistent by linking the contrapositive together: "set speed" -> "play".
      /// The intuition should be most apparent when using the speed slider in Quick Settings.
      if info.isPaused {
        if forceResume == true {
          _resume()
        } else if forceResume == nil && Preference.bool(for: .resetSpeedWhenPaused) {
          _resume()
        }
      }
    }
  }

  /// Called with `MPVOption.PlaybackControl.pause` changed
  func pausedStateDidChange(to paused: Bool) {
    guard info.isPaused != paused || info.pauseStateWasChangedLocally else { return }
    
    info.isPaused = paused
    info.pauseStateWasChangedLocally = false

    DispatchQueue.main.async { [self] in
      if !paused {
        if state == .stopping || state == .idle {
          state = .started
        }
      }
      windowController.updatePlayButtonAndSpeedUI()
      refreshSyncUITimer() // needed to get latest playback position
      if let pos = info.playbackPositionSec, let dur = info.playbackDurationSec {
        let osdMsg: OSDMessage = paused ? .pause(playbackPositionSec: pos, playbackDurationSec: dur) :
          .resume(playbackPositionSec: pos, playbackDurationSec: dur)
        sendOSD(osdMsg)
      }
      saveState()  // record the pause state
      if paused {
        videoView.displayIdle()
      } else {  // resume
        videoView.displayActive()
      }
      if windowController.pip.status == .inPIP {
        windowController.pip.controller.playing = !paused
      }

      if windowController.loaded, !isFullScreen && Preference.bool(for: .alwaysFloatOnTop) {
        windowController.setWindowFloatingOnTop(!paused)
      }
    }
  }

  func speedDidChange(to speed: CGFloat) {
    info.playSpeed = speed
    sendOSD(.speed(speed))
    saveState()  // record the new speed
    DispatchQueue.main.async { [self] in
      windowController.updatePlayButtonAndSpeedUI()
    }
  }

  /// Called when `MPVOption.Video.videoRotate` changed
  func userRotationDidChange(to userRotation: Int) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    windowController.applyVideoGeoTransform("userRotation", { [self] cxt in
      guard userRotation != cxt.oldGeo.video.userRotation else { return nil }
      log.verbose{"[applyVideoGeo \(cxt.name)] Applying rotation: \(userRotation)"}
      // Update window geometry
      sendOSD(.rotation(userRotation))
      return videoGeo.clone(userRotation: userRotation)
    })
  }

  /// Set video's aspect ratio override. The `aspect` param is a string which may be one of the following formats:
  /// 1. Target aspect ratio. This came from user input, either from a button, menu, or text entry.
  /// This can be either in colon notation (e.g., "16:10") or decimal ("2.333333").
  /// 2. Actual aspect ratio as could be parsed as `Double` value.
  /// After the target aspect is applied to the raw video dimensions, the resulting dimensions must be rounded to their nearest
  /// integer values (because of reasons). So when the aspect is recalculated from the new dimensions, the result may be slightly
  /// different.
  ///
  /// This method ensures that the following components are synced to the given aspect ratio:
  /// 1. mpv `video-aspect-override` property
  /// 2. Player window geometry / displayed video size
  /// 3. Quick Settings controls & menu item checkmarks
  ///
  /// To hopefully avoid precision problems, `mpvAspectString` is used for comparisons across data sources.
  func setVideoAspectOverride(_ aspect: String) {
    mpv.queue.async { [self] in
      _setVideoAspectOverride(aspect)
    }
  }

  func _setVideoAspectOverride(_ aspectString: String) {
    log.verbose{"Got request to set videoAspectOverride to: \(aspectString.quoted)"}
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    let aspectLabel: String = Aspect.bestLabelFor(aspectString)

    windowController.applyVideoGeoTransform("AspectOverride", { [self] cxt in
      let oldVideoGeo = cxt.oldGeo.video
      guard oldVideoGeo.userAspectLabel != aspectLabel else { return nil }

      // Send update to mpv
      let mpvValue = Aspect.mpvVideoAspectOverride(fromAspectLabel: aspectLabel)
      log.verbose{"[applyVideoGeo \(cxt.name)] Setting mpv video-aspect-override to: \(mpvValue.quoted)"}
      mpv.setString(MPVOption.Video.videoAspectOverride, mpvValue)

      // FIXME: Default aspect needs i18n
      sendOSD(.aspect(aspectLabel))

      // Change video size:
      log.verbose{"[applyVideoGeo \(cxt.name)] changing userAspectLabel: \(oldVideoGeo.userAspectLabel.quoted) → \(aspectLabel.quoted)"}
      return oldVideoGeo.clone(userAspectLabel: aspectLabel)
    })
  }

  func updateMPVWindowScale(using windowGeo: PWinGeometry) {
    guard windowGeo.mode == .windowedNormal || (windowGeo.mode == .musicMode && windowGeo.videoSize.height > 0) else {
      return
    }
    mpv.queue.async { [self] in
      let desiredVideoScale = windowGeo.mpvVideoScale()
      guard desiredVideoScale > 0.0 else {
        log.verbose("UpdateMPVWindowScale: desiredVideoScale is 0; aborting")
        return
      }
      let currentVideoScale = mpv.getVideoScale()

      if desiredVideoScale != currentVideoScale {
        // Setting the window-scale property seems to result in a small hiccup during playback.
        // Not sure if this is an mpv limitation
        log.verbose{"Updating mpv window-scale from videoSize \(windowGeo.videoSize) (changing videoScale: \(currentVideoScale) → \(desiredVideoScale))"}

        let backingScaleFactor = NSScreen.getScreenOrDefault(screenID: windowGeo.screenID).backingScaleFactor
        let adjustedVideoScale = (desiredVideoScale * backingScaleFactor).truncatedTo6()
        log.verbose{"Adjusted videoScale from windowGeo (\(desiredVideoScale)) * BSF (\(backingScaleFactor)) → sending mpv \(adjustedVideoScale)"}
        mpv.setDouble(MPVProperty.windowScale, adjustedVideoScale)

      } else {
        log.verbose{"Skipping update to mpv window-scale: no change from existing (\(currentVideoScale))"}
      }
    }
  }

  func setVideoRotate(_ userRotation: Int) {
    mpv.queue.async { [self] in
      guard AppData.rotations.firstIndex(of: userRotation)! >= 0 else {
        log.error("Invalid value for videoRotate, ignoring: \(userRotation)")
        return
      }

      log.verbose("Setting videoRotate to: \(userRotation)°")
      mpv.setInt(MPVOption.Video.videoRotate, userRotation)
    }
  }

  func setFlip(_ enable: Bool) {
    mpv.queue.async { [self] in
      Logger.log("Setting flip to: \(enable)°", level: .verbose, subsystem: subsystem)
      if enable {
        guard info.flipFilter == nil else {
          Logger.log("Cannot enable flip: there is already a filter present", level: .error, subsystem: subsystem)
          return
        }
        let vf = MPVFilter.flip()
        vf.label = Constants.FilterLabel.flip
        let _ = addVideoFilter(vf)
      } else {
        guard let vf = info.flipFilter else {
          Logger.log("Cannot disable flip: no filter is present", level: .error, subsystem: subsystem)
          return
        }
        let _ = removeVideoFilter(vf)
      }
    }
  }

  func setMirror(_ enable: Bool) {
    mpv.queue.async { [self] in
      Logger.log("Setting mirror to: \(enable)°", level: .verbose, subsystem: subsystem)
      if enable {
        guard info.mirrorFilter == nil else {
          Logger.log("Cannot enable mirror: there is already a mirror filter present", level: .error, subsystem: subsystem)
          return
        }
        let vf = MPVFilter.mirror()
        vf.label = Constants.FilterLabel.mirror
        let _ = addVideoFilter(vf)
      } else {
        guard let vf = info.mirrorFilter else {
          Logger.log("Cannot disable mirror: no mirror filter is present", level: .error, subsystem: subsystem)
          return
        }
        let _ = removeVideoFilter(vf)
      }
    }
  }

  func toggleDeinterlace(_ enable: Bool) {
    mpv.queue.async { [self] in
      mpv.setFlag(MPVOption.Video.deinterlace, enable)
    }
  }

  func toggleHardwareDecoding(_ enable: Bool) {
    let value = Preference.HardwareDecoderOption(rawValue: Preference.integer(for: .hardwareDecoder))?.mpvString ?? "auto"
    mpv.queue.async { [self] in
      mpv.setString(MPVOption.Video.hwdec, enable ? value : "no")
    }
  }

  enum VideoEqualizerType {
    case brightness, contrast, saturation, gamma, hue
  }

  func setVideoEqualizer(forOption option: VideoEqualizerType, value: Int) {
    let optionName: String
    switch option {
    case .brightness:
      optionName = MPVOption.Equalizer.brightness
    case .contrast:
      optionName = MPVOption.Equalizer.contrast
    case .saturation:
      optionName = MPVOption.Equalizer.saturation
    case .gamma:
      optionName = MPVOption.Equalizer.gamma
    case .hue:
      optionName = MPVOption.Equalizer.hue
    }
    mpv.queue.async { [self] in
      mpv.command(.set, args: [optionName, value.description])
    }
  }

  func loadExternalVideoFile(_ url: URL) {
    mpv.queue.async { [self] in
      let urlPath = Playback.path(from: url)
      let code = mpv.command(.videoAdd, args: [urlPath], checkError: false)
      if code < 0 {
        log.error("Unsupported video: \(urlPath)")
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_audio")
        }
      }
    }
  }

  func loadExternalAudioFile(_ url: URL) {
    mpv.queue.async { [self] in
      let urlPath = Playback.path(from: url)
      let code = mpv.command(.audioAdd, args: [urlPath], checkError: false)
      if code < 0 {
        log.error("Unsupported audio: \(urlPath)")
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_audio")
        }
      }
    }
  }

  func toggleSubVisibility(_ set: Bool? = nil) {
    mpv.queue.async { [self] in
      let newState = set ?? !info.isSubVisible
      mpv.setFlag(MPVOption.Subtitles.subVisibility, newState)
    }
  }

  func toggleSecondSubVisibility(_ set: Bool? = nil) {
    mpv.queue.async { [self] in
      let newState = set ?? !info.isSecondSubVisible
      mpv.setFlag(MPVOption.Subtitles.secondarySubVisibility, newState)
    }
  }

  func loadExternalSubFile(_ url: URL, delay: Bool = false) {
    mpv.queue.async { [self] in
      guard isActive else { return }
      if let track = info.findExternalSubTrack(withURL: url) {
        mpv.command(.subReload, args: [String(track.id)], checkError: false)
        return
      }

      /// Use `auto` flag to override the default:
      /// ```<select>  Select the subtitle immediately (default).
      ///    <auto>    Don't select the subtitle. (Or in some special situations, let the default stream
      ///              selection mechanism decide.)```
      let urlPath = Playback.path(from: url)
      let code = mpv.command(.subAdd, args: [urlPath, "auto"], checkError: false)
      if code < 0 {
        let errorDesc = String(cString: mpv_error_string(code))
        log.error("Failed to load sub (error \(code): \(errorDesc)) \(urlPath.pii.quoted)")
        // if another modal panel is shown, popping up an alert now will cause some infinite loop.
        if delay {
          DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) {
            Utility.showAlert("unsupported_sub")
          }
        } else {
          DispatchQueue.main.async {
            Utility.showAlert("unsupported_sub")
          }
        }
      }
    }
  }

  func reloadAllSubs() {
    mpv.queue.async { [self] in
      guard isActive else { return }
      let currentSubName = info.currentTrack(.sub)?.externalFilename
      for subTrack in info.subTracks {
        let code = mpv.command(.subReload, args: ["\(subTrack.id)"], checkError: false)
        if code < 0 {
          log.error("Failed reloading subtitles: error code \(code)")
        }
      }
      guard reloadTrackInfo() else { return }
      if let currentSub = info.subTracks.first(where: {$0.externalFilename == currentSubName}) {
        setTrack(currentSub.id, forType: .sub)
      }

      DispatchQueue.main.async { [self] in
        windowController?.quickSettingView.reload()
      }
    }
  }

  func setAudioDelay(_ delay: Double) {
    mpv.queue.async { [self] in
      mpv.setDouble(MPVOption.Audio.audioDelay, delay)
    }
  }

  func setSubDelay(_ delay: Double, forPrimary: Bool = true) {
    mpv.queue.async { [self] in
      let option = forPrimary ? MPVOption.Subtitles.subDelay : MPVOption.Subtitles.secondarySubDelay
      mpv.setDouble(option, delay)
    }
  }

  func playlistMove(_ from: Int, to: Int) {
    mpv.queue.async { [self] in
      _playlistMove(from, to: to)
      _reloadPlaylist()
    }
  }

  func playlistMove(_ srcRows: IndexSet, to dstRow: Int) {
    mpv.queue.async { [self] in
      log.debug("Playlist Drag & Drop: \(srcRows) → \(dstRow)")
      // Drag & drop within playlistTableView
      var oldIndexOffset = 0, newIndexOffset = 0
      for oldIndex in srcRows {
        if oldIndex < dstRow {
          _playlistMove(oldIndex + oldIndexOffset, to: dstRow)
          oldIndexOffset -= 1
        } else {
          _playlistMove(oldIndex, to: dstRow + newIndexOffset)
          newIndexOffset += 1
        }
      }
      _reloadPlaylist()
    }
  }

  private func _playlistMove(_ from: Int, to: Int) {
    mpv.command(.playlistMove, args: ["\(from)", "\(to)"], level: .verbose)
  }

  func playNextInPlaylist(_ playlistItemIndexes: IndexSet) {
    mpv.queue.async { [self] in
      let current = mpv.getInt(MPVProperty.playlistPos)
      var ob = 0  // index offset before current playing item
      var mc = 1  // moved item count, +1 because move to next item of current played one
      for item in playlistItemIndexes {
        if item == current { continue }
        if item < current {
          _playlistMove(item + ob, to: current + mc + ob)
          ob -= 1
        } else {
          _playlistMove(item, to: current + mc + ob)
        }
        mc += 1
      }
      _reloadPlaylist(silent: false)
    }
  }

  /// Adds all the media in `pathList` to the current playlist.
  /// This checks whether the currently playing item is in the list, so that it may end up in the middle of the playlist.
  /// Also note that each item in `pathList` may be either a file path or a network URL.
  func _addToPlaylist(pathListIncludingCurrent pathList: [String]) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    _reloadPlaylist(silent: true)

    var addedCurrentItem = false

    for path in pathList {
      guard !isStopping else { return }
      if path == info.currentPlayback?.path {
        addedCurrentItem = true
      } else if addedCurrentItem {
        _addToPlaylist(path)
      } else {
        let count = mpv.getInt(MPVProperty.playlistCount)
        let current = mpv.getInt(MPVProperty.playlistPos)
        _addToPlaylist(path)
        let err = mpv.command(.playlistMove, args: ["\(count)", "\(current)"], checkError: false)
        if err != 0 {
          log.error("Error \(err) when auto-adding files into playlist")
          if err == MPV_ERROR_COMMAND.rawValue {
            return
          }
        }
      }
    }
    _reloadPlaylist()
  }

  func addToPlaylist(_ path: String, silent: Bool = false) {
    mpv.queue.async { [self] in
      _addToPlaylist(path)
      _reloadPlaylist(silent: silent)
    }
  }

  func addToPlaylist(urls: any Collection<URL>, silent: Bool = false) {
    guard !urls.isEmpty else { return }
    mpv.queue.async { [self] in
      _addToPlaylist(urls: urls, silent: silent)
    }
  }

  func _addToPlaylist(urls: any Collection<URL>, silent: Bool = false) {
    _reloadPlaylist(silent: true)  // get up-to-date list first
    for url in urls {
      let urlPath = Playback.path(from: url)
      _addToPlaylist(urlPath)
    }

    _reloadPlaylist(silent: silent)
    if !silent {
      sendOSD(.addToPlaylist(urls.count))
    }
  }

  func addToPlaylist(paths: [String], at index: Int = -1) {
    mpv.queue.async { [self] in
      _reloadPlaylist(silent: true)
      for path in paths {
        _addToPlaylist(path)
      }
      let playlist = info.playlist
      if index <= playlist.count && index >= 0 {
        let previousCount = playlist.count
        for i in 0..<paths.count {
          _playlistMove(previousCount + i, to: index + i)
        }
      }
      _reloadPlaylist()
      saveState()  // save playlist URLs to prefs
    }
  }

  func _addToPlaylist(_ urlPath: String) {
    log.verbose("Appending to mpv playlist: \(urlPath.pii.quoted)")
    mpv.command(.loadfile, args: [urlPath, "append"])
  }

  func playlistRemove(_ index: Int) {
    mpv.queue.async { [self] in
      log.verbose("Will remove row \(index) from playlist")
      _playlistRemove(index)
      _reloadPlaylist()
    }
  }

  func playlistRemove(_ indexSet: IndexSet) {
    mpv.queue.async { [self] in
      log.verbose("Will remove rows \(indexSet.map{$0}) from playlist")
      var count = 0
      for i in indexSet {
        _playlistRemove(i - count)
        count += 1
      }
      _reloadPlaylist()
    }
  }

  private func _playlistRemove(_ index: Int) {
    log.verbose("Removing row \(index) from playlist")
    mpv.command(.playlistRemove, args: [index.description])
  }

  func clearPlaylist() {
    mpv.queue.async { [self] in
      log.verbose("Sending 'playlist-clear' cmd to mpv")
      mpv.command(.playlistClear)
      _reloadPlaylist()
    }
  }

  func playFile(_ path: String) {
    mpv.queue.async { [self] in
      info.shouldAutoLoadFiles = true
      mpv.command(.loadfile, args: [path, "replace"])
      mpv.queue.async { [self] in
        _reloadPlaylist()
        saveState()
      }
    }
  }

  func playFileInPlaylist(_ pos: Int) {
    mpv.queue.async { [self] in
      log.verbose("Changing mpv playlist-pos to \(pos)")
      mpv.setInt(MPVProperty.playlistPos, pos)
      saveState()
    }
  }

  func navigateInPlaylist(nextMedia: Bool) {
    mpv.queue.async { [self] in
      mpv.command(nextMedia ? .playlistNext : .playlistPrev, checkError: false)
    }
  }

  @discardableResult
  func playChapter(_ pos: Int) -> MPVChapter? {
    log.verbose("Seeking to chapter \(pos)")
    let chapters = info.chapters
    guard pos < chapters.count else {
      return nil
    }
    let chapter = chapters[pos]
    mpv.queue.async { [self] in
      // Update playbackPositionSec preemptively, so UI doesn't flash
      // to prev chapter and back
      info.playbackPositionSec = chapter.startTime
      mpv.command(.seek, args: ["\(chapter.startTime)", "absolute"])
      _resume()
    }
    return chapter
  }

  func setAudioEq(fromGains gains: [Double]) {
    let freqList = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    let paramString = freqList.enumerated().map { (index, freq) in
      "equalizer=f=\(freq):t=h:width=\(Double(freq) / 1.224744871):g=\(gains[index])"
    }.joined(separator: ",")
    let filter = MPVFilter(name: "lavfi", label: Constants.FilterLabel.audioEq, paramString: "[\(paramString)]")
    addAudioFilter(filter)
    info.audioEqFilter = filter
  }

  func removeAudioEqFilter() {
    if let filter = info.audioEqFilter {
      removeAudioFilter(filter)
      info.audioEqFilter = nil
    }
  }

  /// Add a video filter given as a `MPVFilter` object.
  ///
  /// This method will prompt the user to change IINA's video preferences if hardware decoding is set to `auto`.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  /// Can run on either mpv or main DispatchQueue.
  // TODO: refactor to execute mpv commands only on mpv queue
  func addVideoFilter(_ filter: MPVFilter) -> Bool {
    let success = addVideoFilter(filter.stringFormat)
    if !success {
      log.verbose("Video filter \(filter.stringFormat) was not added")
    }
    return success
  }

  /// Add a video filter given as a string.
  ///
  /// This method will prompt the user to change IINA's video preferences if hardware decoding is set to `auto`.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  func addVideoFilter(_ filter: String) -> Bool {
    Logger.log("Adding video filter \(filter.quoted)...", subsystem: subsystem)

    // check hwdec
    let hwdec = mpv.getString(MPVProperty.hwdec)
    if hwdec == "auto" {
      let askHwdec: (() -> Bool) = { [self] in
        let panel = NSAlert()
        panel.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
        panel.informativeText = NSLocalizedString("alert.filter_hwdec.message", comment: "")
        panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.turn_off", comment: "Turn off hardware decoding"))
        panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.use_copy", comment: "Switch to Auto(Copy)"))
        panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.abort", comment: "Abort"))
        switch panel.runModal() {
        case .alertFirstButtonReturn:  // turn off
          mpv.setString(MPVProperty.hwdec, "no")
          Preference.set(Preference.HardwareDecoderOption.disabled.rawValue, for: .hardwareDecoder)
          return true
        case .alertSecondButtonReturn:
          mpv.setString(MPVProperty.hwdec, "auto-copy")
          Preference.set(Preference.HardwareDecoderOption.autoCopy.rawValue, for: .hardwareDecoder)
          return true
        default:
          return false
        }
      }

      // if not on main thread, post the alert in main thread
      if Thread.isMainThread {
        if !askHwdec() { return false }
      } else {
        var result = false
        DispatchQueue.main.sync {
          result = askHwdec()
        }
        if !result { return false }
      }
    }

    // try apply filter
    var didSucceed = true
    didSucceed = mpv.command(.vf, args: ["add", filter], checkError: false) >= 0
    log.debug("Add filter: \(didSucceed ? "Succeeded" : "Failed")")

    if didSucceed, let vf = MPVFilter(rawString: filter) {
      if Thread.isMainThread {
        mpv.queue.async { [self] in
          setPlaybackInfoFilter(vf)
        }
      } else {
        assert(DispatchQueue.isExecutingIn(mpv.queue))
        setPlaybackInfoFilter(vf)
      }
    }

    return didSucceed
  }

  private func logRemoveFilter(type: String, result: Bool, name: String) {
    if !result {
      log.warn("Failed to remove \(type) filter \(name)")
    } else {
      log.debug("Successfully removed \(type) filter \(name)")
    }
  }

  /// Remove a video filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeVideoFilter(_ filter: MPVFilter, _ index: Int) -> Bool {
    return removeVideoFilter(filter.stringFormat, index)
  }

  /// Remove a video filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeVideoFilter(_ filter: String, _ index: Int) -> Bool {
    Logger.log("Removing video filter \(filter)...", subsystem: subsystem)
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    let result = mpv.removeFilter(MPVProperty.vf, index)
    logRemoveFilter(type: "video", result: result, name: filter)
    return result
  }

  /// Remove a video filter given as a `MPVFilter` object.
  ///
  /// If the filter is not labeled then removing using a `MPVFilter` object can be problematic if the filter has multiple parameters.
  /// Filters that support multiple parameters have more than one valid string representation due to there being no requirement on the
  /// order in which those parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in
  /// the command sent to mpv does not match the order mpv expects the remove command will not find the filter to be removed. For
  /// this reason the remove methods that identify the filter to be removed based on its position in the filter list are the preferred way to
  /// remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  @discardableResult
  func removeVideoFilter(_ filter: MPVFilter, verify: Bool = true, notify: Bool = true) -> Bool {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    
    let filterString: String
    if let label = filter.label {
      // Has label: we care most about these
      // The vf remove command will return 0 even if the filter didn't exist in mpv. So need to do this check ourselves.
      let filterExists = mpv.getFilters(MPVProperty.vf).compactMap({$0.label}).contains(label)
      guard filterExists else {
        log.debug("Cannot remove video filter: could not find filter with label \(label.quoted) in mpv list")
        return false
      }
      
      log.debug("Removing video filter \(label.quoted) (\(filter.stringFormat.quoted))...")
      filterString = "@" + label
    } else {
      log.debug("Removing video filter (\(filter.stringFormat.quoted))...")
      filterString = filter.stringFormat
    }

    guard removeVideoFilter(filterString) else {
      return false
    }

    /// `getVideoFilters` will ensure various filter caches will stay up to date
    let didRemoveSuccessfully = !getVideoFilters().compactMap({$0.label}).contains(label)
    guard !verify || didRemoveSuccessfully else {
      log.error("Failed to remove video filter \(label.quoted): filter still present after vf remove!")
      return false
    }
    if notify {
      postNotification(.iinaVFChanged)
    }
    return true
  }

  /// Remove a video filter given as a string.
  ///
  /// If the filter is not labeled then removing using a string can be problematic if the filter has multiple parameters. Filters that support
  /// multiple parameters have more than one valid string representation due to there being no requirement on the order in which those
  /// parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in the command sent to
  /// mpv does not match the order mpv expects the remove command will not find the filter to be removed. For this reason the remove
  /// methods that identify the filter to be removed based on its position in the filter list are the preferred way to remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeVideoFilter(_ filterString: String) -> Bool {
    // Just pretend it succeeded if no error
    let didError = mpv.command(.vf, args: ["remove", filterString], checkError: false) != 0
    log.debug(didError ? "Error executing vf-remove" : "No error returned by vf-remove")
    return !didError
  }

  /// Add an audio filter given as a `MPVFilter` object.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  @discardableResult
  func addAudioFilter(_ filter: MPVFilter) -> Bool { addAudioFilter(filter.stringFormat) }

  /// Add an audio filter given as a string.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  @discardableResult
  func addAudioFilter(_ filter: String) -> Bool {
    log.debug("Adding audio filter \(filter)...")
    var result = true
    result = mpv.command(.af, args: ["add", filter], checkError: false) >= 0
    Logger.log(result ? "Succeeded" : "Failed", subsystem: self.subsystem)
    return result
  }

  /// Remove an audio filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeAudioFilter(_ filter: MPVFilter, _ index: Int) -> Bool {
    removeAudioFilter(filter.stringFormat, index)
  }

  /// Remove an audio filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeAudioFilter(_ filter: String, _ index: Int) -> Bool {
    log.debug("Removing audio filter \(filter)...")
    let result = mpv.removeFilter(MPVProperty.af, index)
    logRemoveFilter(type: "audio", result: result, name: filter)
    return result
  }

  /// Remove an audio filter given as a `MPVFilter` object.
  ///
  /// If the filter is not labeled then removing using a `MPVFilter` object can be problematic if the filter has multiple parameters.
  /// Filters that support multiple parameters have more than one valid string representation due to there being no requirement on the
  /// order in which those parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in
  /// the command sent to mpv does not match the order mpv expects the remove command will not find the filter to be removed. For
  /// this reason the remove methods that identify the filter to be removed based on its position in the filter list are the preferred way to
  /// remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  @discardableResult
  func removeAudioFilter(_ filter: MPVFilter) -> Bool { removeAudioFilter(filter.stringFormat) }

  /// Remove an audio filter given as a string.
  ///
  /// If the filter is not labeled then removing using a string can be problematic if the filter has multiple parameters. Filters that support
  /// multiple parameters have more than one valid string representation due to there being no requirement on the order in which those
  /// parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in the command sent to
  /// mpv does not match the order mpv expects the remove command will not find the filter to be removed. For this reason the remove
  /// methods that identify the filter to be removed based on its position in the filter list are the preferred way to remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  @discardableResult
  func removeAudioFilter(_ filter: String) -> Bool {
    Logger.log("Removing audio filter \(filter)...", subsystem: subsystem)
    let returnCode = mpv.command(.af, args: ["remove", filter], checkError: false) >= 0
    Logger.log(returnCode ? "Succeeded" : "Failed", subsystem: self.subsystem)
    return returnCode
  }

  func getAudioDevices() -> [[String: String]] {
    let raw = mpv.getNode(MPVProperty.audioDeviceList)
    if let list = raw as? [[String: String]] {
      return list
    } else {
      return []
    }
  }

  func setAudioDevice(_ name: String) {
    mpv.queue.async { [self] in
      log.verbose("Seting mpv audioDevice to \(name.pii.quoted)")
      mpv.setString(MPVProperty.audioDevice, name)
    }
  }

  /** Scale is a double value in (0, 100] */
  func setSubScale(_ scale: Double) {
    assert(scale > 0.0, "Invalid sub scale: \(scale)")
    mpv.queue.async { [self] in
      Preference.set(scale, for: .subScale)
      mpv.setDouble(MPVOption.Subtitles.subScale, scale)
    }
  }

  func setSubPos(_ pos: Int, forPrimary: Bool = true) {
    mpv.queue.async { [self] in
      if forPrimary {
        Preference.set(pos, for: .subPos)
      }
      let option = forPrimary ? MPVOption.Subtitles.subPos : MPVOption.Subtitles.secondarySubPos
      mpv.setInt(option, pos)
    }
  }

  func setSubTextColor(_ colorString: String) {
    mpv.queue.async { [self] in
      Preference.set(colorString, for: .subTextColorString)
      mpv.setString("options/" + MPVOption.Subtitles.subColor, colorString)
    }
  }

  func setSubFont(_ font: String) {
    mpv.queue.async { [self] in
      Preference.set(font, for: .subTextFont)
      mpv.setString(MPVOption.Subtitles.subFont, font)
    }
  }

  func setSubTextSize(_ fontSize: Double) {
    mpv.queue.async { [self] in
      Preference.set(fontSize, for: .subTextSize)
      mpv.setDouble("options/" + MPVOption.Subtitles.subFontSize, fontSize)
    }
  }

  func setSubTextBold(_ isBold: Bool) {
    mpv.queue.async { [self] in
      Preference.set(isBold, for: .subBold)
      mpv.setFlag("options/" + MPVOption.Subtitles.subBold, isBold)
    }
  }

  func setSubTextBorderColor(_ colorString: String) {
    mpv.queue.async { [self] in
      Preference.set(colorString, for: .subBorderColorString)
      mpv.setString("options/" + MPVOption.Subtitles.subBorderColor, colorString)
    }
  }

  func setSubTextBorderSize(_ size: Double) {
    mpv.queue.async { [self] in
      Preference.set(size, for: .subBorderSize)
      mpv.setDouble("options/" + MPVOption.Subtitles.subBorderSize, size)
    }
  }

  func setSubTextBgColor(_ colorString: String) {
    mpv.queue.async { [self] in
      Preference.set(colorString, for: .subBgColorString)
      mpv.setString("options/" + MPVOption.Subtitles.subBackColor, colorString)
    }
  }

  func setSubEncoding(_ encoding: String) {
    mpv.queue.async { [self] in
      mpv.setString(MPVOption.Subtitles.subCodepage, encoding)
      info.subEncoding = encoding
    }
  }

  private func saveToLastPlayedFile(_ url: URL?, duration: Double?, position: Double?) {
    guard Preference.bool(for: .resumeLastPosition) else { return }
    guard let url else {
      log.warn("Cannot save iinaLastPlayedFilePath or iinaLastPlayedFilePosition: url is nil!")
      return
    }
    // FIXME: remove `iinaLastPlayedFilePath` and `iinaLastPlayedFilePosition` - they are not compatible with welcome window list
    Preference.set(url, for: .iinaLastPlayedFilePath)
    // Write to cache directly (rather than calling `refreshCachedVideoProgress`).
    // If user only closed the window but didn't quit the app, this can make sure playlist displays the correct progress.
    MediaMetaCache.shared.setCachedMediaDurationAndProgress(url, duration: duration, progress: position)
    if let position = info.playbackPositionSec {
      Logger.log("Saving iinaLastPlayedFilePosition: \(position) sec", level: .verbose, subsystem: subsystem)
      Preference.set(position, for: .iinaLastPlayedFilePosition)
    } else {
      log.warn("Writing 0 to iinaLastPlayedFilePosition cuz no position found")
      Preference.set(0.0, for: .iinaLastPlayedFilePosition)
    }
  }

  /// mpv `watch-later` + `saveToLastPlayedFile()` (above)
  func savePlaybackPosition() {
    guard !isDemoPlayer else { return }
    guard Preference.bool(for: .resumeLastPosition) else { return }

    // The player must be active to be able to save the watch later configuration.
    if isActive {
      log.debug("Write watch later config")
      mpv.command(.writeWatchLaterConfig, level: .verbose)
    }
    saveToLastPlayedFile(info.currentURL, duration: info.playbackDurationSec, position: info.playbackPositionSec)

    // The rest of the stuff below relates to UI updates and should be cancelled if shutting down.
    guard !isShuttingDown else { return }

    // Ensure playlist is updated in real time
    postFileHistoryUpdateNotification()

    // Ensure Playback History window is updated in real time
    if Preference.bool(for: .recordPlaybackHistory) {
      HistoryController.shared.async { [self] in
        guard !isShuttingDown else { return }
        /// this will reload the `mpvProgress` field from the `watch-later` config files
        guard let historyItem = HistoryController.shared.history.first(where: {$0.url == info.currentURL}) else { return }
        historyItem.loadProgressFromWatchLater()
      }
    }
  }

  func getMPVGeometry() -> MPVGeometryDef? {
    /// Cannot rely on mpv instance to have `MPVOption.Window.geometry` set. If configured to only set when opening manually, it doesn't
    /// make sense to keep it set. Just load the pref value directly.
    let geometryString = Preference.string(for: .initialWindowSizePosition) ?? ""
    if let mpvGeometry = MPVGeometryDef.parse(geometryString) {
      log.verbose("Parsed mpv geometry from prefs: \(mpvGeometry)")
      return mpvGeometry
    } else {
      log.verbose("Got nil for mpv geometry from prefs!")
      return nil
    }
  }

  /// Uses an mpv `on_before_start_file` hook to honor mpv's `shuffle` command via IINA CLI.
  ///
  /// There is currently no way to remove an mpv hook once it has been added, so to minimize potential impact and/or side effects
  /// when not in use:
  /// 1. Only add the mpv hook if `--mpv-shuffle` (or equivalent) is specified. Because this decision only happens at launch,
  /// there is no risk of adding the hook more than once per player.
  /// 2. Use `shufflePending` to decide if it needs to run again. Set to `false` after use, and check its value as early as possible.
  func addShufflePlaylistHook() {
    $shufflePending.withLock{ $0 = true }

    func callback(next: @escaping () -> Void) {
      var mustShuffle = false
      $shufflePending.withLock{ shufflePending in
        if shufflePending {
          mustShuffle = true
          shufflePending = false
        }
      }

      guard mustShuffle else {
        log.verbose("Triggered on_before_start_file hook, but no shuffle needed")
        next()
        return
      }

      DispatchQueue.main.async { [self] in
        log.debug("Running on_before_start_file hook: shuffling playlist")
        mpv.command(.playlistShuffle)
        /// will cancel this file load sequence (so `fileLoaded` will not be called), then will start loading item at index 0
        mpv.command(.playlistPlayIndex, args: ["0"])
        next()
      }
    }

    mpv.addHook(MPVHook.onBeforeStartFile, hook: MPVHookValue(withBlock: callback))
  }

  // MARK: - Listeners

  /// A [MPV_EVENT_START_FILE](https://mpv.io/manual/stable/#command-interface-mpv-event-start-file) was received.
  func fileStarted(path: String, playlistPos: Int) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    if isIdle {
      state = .started
    }
    guard !isStopping else { return }

    guard let playbackFromPath = Playback(urlPath: path, playlistPos: playlistPos, state: .started) else {
      log.error("FileStarted: failed to create media from path \(path.pii.quoted)")
      return
    }
    let playback: Playback
    if let existingPlayback = info.currentPlayback, existingPlayback.url == playbackFromPath.url {
      guard existingPlayback.state.isNotYet(.started) else {
        log.warn("FileStarted: found existing playback for \(existingPlayback.url.absoluteString.pii.quoted), but state is unexpected; aborting (expected: 'started', found: \(existingPlayback.state.rawValue))")
        return
      }
      playback = existingPlayback
      // update existing entry
      existingPlayback.playlistPos = playbackFromPath.playlistPos
      existingPlayback.state = playbackFromPath.state
      log.verbose("FileStarted: existing playbackPath=\(path.pii.quoted), PL#=\(String(playbackFromPath.playlistPos))")
    } else {
      // New media, perhaps initiated by mpv
      log.verbose("FileStarted: new playbackPath=\(path.pii.quoted), PL#=\(String(playbackFromPath.playlistPos))")
      info.currentPlayback = playbackFromPath
      playback = playbackFromPath
    }
    if let parentPlaylist = mpv.getString(MPVProperty.playlistPath) {
      // TODO!
      playback.parentPlaylist = parentPlaylist
    }

    // Stop watchers from prev media (if any)
    stopWatchingSubFile()

    DispatchQueue.main.async { [self] in
      // Check this inside main DispatchQueue
      if isPlaylistVisible {
        // TableView whole table reload is very expensive. No need to reload entire playlist; just the two changed rows:
        windowController.playlistView.refreshNowPlayingIndex(setNewIndexTo: playlistPos)
      }

      MediaPlayerIntegration.shared.update()
    }

    // set "date last opened" attribute
    if let url = info.currentURL, url.isFileURL, !info.isMediaOnRemoteDrive {
      // the required data is a timespec struct
      var ts = timespec()
      let time = Date().timeIntervalSince1970
      ts.tv_sec = Int(time)
      ts.tv_nsec = Int(time.truncatingRemainder(dividingBy: 1) * 1_000_000_000)
      let data = Data(bytesOf: ts)
      // set the attribute; the key is undocumented
      let name = "com.apple.lastuseddate#PS"
      url.withUnsafeFileSystemRepresentation { fileSystemPath in
        let _ = data.withUnsafeBytes {
          setxattr(fileSystemPath, name, $0.baseAddress, data.count, 0, 0)
        }
      }
    }

    // Cannot restore playlist until after fileStarted event & mpv has a position for current item
    if let priorState = windowController.priorStateIfRestoring,
       let playlistPathList = priorState.properties[PlayerSaveState.PropName.playlistPaths.rawValue] as? [String] {
      log.debug("Restoring \(playlistPathList.count) items into playlist")
      _addToPlaylist(pathListIncludingCurrent: playlistPathList)

      /// Launches background task which scans video files and collects video size metadata using ffmpeg
      PlayerCore.backgroundQueue.async { [self] in
        MediaMetaCache.shared.fillInVideoSizes(info.currentVideosInfo, onBehalfOf: self)
      }
    }

    sendOSD(.fileStart(playback.displayName, ""))

    events.emit(.fileStarted)
  }

  /// Called via mpv hook `on_load`, right before file is loaded.
  func fileWillLoad() {
    /// Currently this method is only used to honor `--shuffle` arg via iina-cli
    guard shufflePending else { return }
    shufflePending = false

    Logger.log("Shuffling playlist", subsystem: subsystem)
    mpv.command(.playlistShuffle)
    /// will cancel this file load sequence (so `fileLoaded` will not be called), then will start loading item at index 0
    mpv.command(.playlistPlayIndex, args: ["0"])
  }


  /// A [MPV_EVENT_FILE_LOADED](https://mpv.io/manual/stable/#command-interface-mpv-event-file-loaded) was received.
  ///
  /// This function is called right after file loaded, triggered by mpv `fileLoaded` notification.
  /// We should now be able to get track info from mpv and can start rendering the video in the final size.
  func fileLoaded() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    // note: player may be "stopped" here
    guard !isStopping else { return }

    // If restoring, playback was already paused (and will not be unpaused until window is ready to show)
    if !isRestoring {
      let pause = Preference.bool(for: .pauseWhenOpen)
      mpv.setFlag(MPVOption.PlaybackControl.pause, pause)
    }
    log.verbose("FileLoaded path=\(info.currentPlayback?.path.pii.quoted ?? "nil")")

    let duration = mpv.getDouble(MPVProperty.duration)
    info.playbackDurationSec = duration
    if let path = mpv.getString(MPVProperty.path) {
      if let url = Playback.url(fromPath: path) {
        MediaMetaCache.shared.setCachedMediaDuration(url, duration)
      } else {
        log.error("Could not create URL for path, skipping: \(path)")
      }
    }
    let playbackPosition = mpv.getDouble(MPVProperty.timePos)
    info.playbackPositionSec = playbackPosition

    triedUsingExactSeekForCurrentFile = false
    // Playback will move directly from stopped to loading when transitioning to the next file in
    // the playlist.
    if state == .stopping || state == .idle {
      state = .started
    }

    guard let currentPlayback = info.currentPlayback else {
      log.debug("FileLoaded: aborting - currentPlayback was nil")
      return
    }

    guard !mpv.isStale() else {
      log.debug("FileLoaded: aborting - mpv is stale")
      return
    }

    guard currentPlayback.state.isNotYet(.loaded) else {
      log.warn("FileLoaded: aborting - state of \(currentPlayback.path.pii.quoted) is \(currentPlayback.state.description.quoted)")
      return
    }

    if currentPlayback.isNetworkResource {
      DispatchQueue.main.async {
        let openURLWindow = IINA.AppDelegate.shared.openURLWindow
        if openURLWindow.playerCore == self {
          openURLWindow.closeAfterSuccess()
        }
      }
    }

    // Kick off thumbnails load/gen - it can happen in background
    reloadThumbnails()

    checkUnsyncedWindowOptions()
    if !reloadTrackInfo() {
      // TODO: can this ever happen here?! May need to terminate player if so
      log.error("No tracks returned by mpv!")
    }

    // Cache these vars to keep them constant for background tasks
    let priorStateIfRestoring = windowController.priorStateIfRestoring

    // Sync tracks
    if let priorStateIfRestoring {
      if priorStateIfRestoring.string(for: .playPosition) != nil {
        /// Need to manually clear this, because mpv will try to seek to this time when any item in playlist
        /// is started. Run this on the mpv queue to ensure proper ordering.
        log.verbose("Clearing mpv 'start' option now that restore is complete")
        mpv.setString(MPVOption.PlaybackControl.start, AppData.mpvArgNone)
      }

      /// Will complete restore when `applyVideoGeoTransform` is done
    }
    // Set this *before* reloading track selections! They will check state
    currentPlayback.state = .loaded

    reloadSelectedTracks(silent: true)
    _reloadPlaylist()  // Need to do this when opening a playlist!
    _reloadChapters()
    syncAbLoop()
    // Done syncing tracks

    let stateChange: ((GeometryTransformContext) -> PWinSessionState?) = { [self] context in
      log.verbose("Calling applyVideoGeoForStateChange from fileLoaded; sessionState=\(context.sessionState)")
      switch context.sessionState {
      case .existingSession_continuing:
        return .existingSession_startingNewPlayback
      default:
        if context.sessionState.isOpeningFile {
          return context.sessionState
        } else {
          log.verbose("Not the right sessionState; will let another handler take this")
          return nil
        }
      }
    }
    windowController.applyVideoGeoForStateChange(stateChange: stateChange)

    // Launch auto-load tasks on background thread
    $backgroundQueueTicket.withLock { $0 += 1 }
    let shouldAutoLoadFiles = info.shouldAutoLoadFiles
    let currentTicket = backgroundQueueTicket
    PlayerCore.backgroundQueue.asyncAfter(deadline: DispatchTime.now() + Constants.TimeInterval.autoLoadDelay) { [self] in
      fileLoaded_backgroundQueueWork(for: currentPlayback, currentTicket: currentTicket,
                                     shouldAutoLoadFiles: shouldAutoLoadFiles,
                                     priorStateIfRestoring: priorStateIfRestoring)
    }

    // History thread: update history given new playback URL
    if let url = info.currentURL {
      HistoryController.shared.async { [self] in
        fileLoaded_historyQueueWork(for: url, durationSec: info.playbackDurationSec ?? 0.0)
      }
    }
  }

  // History task via history queue
  private func fileLoaded_historyQueueWork(for url: URL, durationSec: Double) {

    // 1. Update main history list
    HistoryController.shared.add(url, duration: durationSec)

    // 2. IINA's [ancient] "resume last playback" feature
    // Add this now, or else welcome window will fall out of sync with history list
    saveToLastPlayedFile(url, duration: durationSec, position: info.playbackPositionSec)

    if Preference.bool(for: .recordRecentFiles) {
      // 3. Workaround for File > Recent Documents getting cleared when it shouldn't
      if Preference.bool(for: .trackAllFilesInRecentOpenMenu) {
        HistoryController.shared.noteNewRecentDocumentURL(url)
      } else {
        /// This will get called by `noteNewRecentDocumentURL`. But if it's not called, need to call it
        /// so that welcome window is notified when `iinaLastPlayedFilePosition`, etc. are changed
        HistoryController.shared.postNotification(Notification(name: .recentDocumentsDidChange))
      }
    }
    HistoryController.shared.postNotification(Notification(name: .iinaHistoryUpdated))
    postFileHistoryUpdateNotification()
  }

  /// Auto load via background queue
  private func fileLoaded_backgroundQueueWork(for currentPlayback: Playback,
                                              currentTicket: Int,
                                              shouldAutoLoadFiles: Bool,
                                              priorStateIfRestoring: PlayerSaveState?) {
    assert(DispatchQueue.isExecutingIn(PlayerCore.backgroundQueue))
    let isRestoring = priorStateIfRestoring != nil

    // add files in same folder
    if shouldAutoLoadFiles {
      log.debug("Started auto load of files in current folder, isRestoring=\(isRestoring.yn)")
      self.autoLoadFilesInCurrentFolder(ticket: currentTicket)
    }
    // auto load matched subtitles
    if let matchedSubs = self.info.getMatchedSubs(currentPlayback.path) {
      log.debug("Found \(matchedSubs.count) external subs for current file")
      for sub in matchedSubs {
        guard currentTicket == self.backgroundQueueTicket else { return }
        self.loadExternalSubFile(sub)
      }
      if !isRestoring {
        // set sub to the first one
        // TODO: why?
        log.debug("Setting subtitle track to because an external sub was found")
        guard currentTicket == self.backgroundQueueTicket, self.mpv.mpv != nil else { return }
        self.setTrack(1, forType: .sub)
      }
    }

    self.autoSearchOnlineSub()

    // Set SID & S2ID now that all subs are available
    if let priorState = priorStateIfRestoring {
      if let priorSID = priorState.int(for: .sid) {
        setTrack(priorSID, forType: .sub, silent: true)
      }
      if let priorS2ID = priorState.int(for: .s2id) {
        setTrack(priorS2ID, forType: .secondSub, silent: true)
      }
    }
    log.debug("Auto load done")
  }

  func fileEnded(dueToStopCommand: Bool) {
    // if receive end-file when loading file, might be error
    // wait for idle
    if info.isFileLoaded {
      info.shouldAutoLoadFiles = false
    } else {
      if !dueToStopCommand {
        receivedEndFileWhileLoading = true
      }
    }
    if dueToStopCommand {
      playbackStopped()
    }
  }

  func afChanged() {
    guard !isStopping else { return }
    _ = getAudioFilters()
    saveState()
    reloadQuickSettingsView()
    postNotification(.iinaAFChanged)
  }

  func aidChanged(silent: Bool = false) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !isRestoring, !isStopping else { return }
    let aid = Int(mpv.getInt(MPVOption.TrackSelection.aid))
    guard aid != info.aid else { return }
    guard info.isFileLoaded else {
      log.verbose("Audio track changed to \(aid) but file is not loaded; ignoring")
      return
    }
    info.aid = aid

    log.verbose("Audio track changed to: \(aid)")
    syncUI(.volume)
    postNotification(.iinaAIDChanged)
    if !silent {
      if let audioTrack = info.currentTrack(.audio) {
        sendOSD(.audioTrack(audioTrack, info.volume))
      } else {
        // Do not show volume if no audio track:
        sendOSD(.track(.noneAudioTrack))
      }
    }
  }

  func chapterChanged() {
    guard isActive else { return }
    let chapter = Int(mpv.getInt(MPVProperty.chapter))
    info.chapter = chapter
    log.verbose("Δ mpv prop: 'chapter' = \(info.chapter)")
    syncUI(.chapterList)
    MediaPlayerIntegration.shared.updateNowPlayingInfo()
    postNotification(.iinaMediaTitleChanged)
  }

  func fullscreenChanged() {
    guard windowController.loaded, !isStopping else { return }
    let fs = mpv.getFlag(MPVOption.Window.fullscreen)
    if fs != isFullScreen {
      windowController.toggleWindowFullScreen()
    }
  }

  func idleActiveChanged() {
    let isFileLoaded = info.isFileLoaded
    let eofWhileLoading = receivedEndFileWhileLoading
    log.verbose("Got mpv 'idle-active' (isFileLoaded=\(isFileLoaded.yn) eofLoading=\(eofWhileLoading.yn) playerState=\(state))")
    /// Make sure to check that `info.currentPlayback != nil` before outputting error
    if eofWhileLoading, let playback = info.currentPlayback, playback.state.isNotYet(.loaded) {
      log.error("Received fileEnded + 'idle-active' from mpv while loading \(playback.path.pii.quoted). Will display alert to user and close window")
      DispatchQueue.main.async { [self] in
        Utility.showAlert("error_open_name", arguments: [playback.path.quoted])
        let openURLWindow = AppDelegate.shared.openURLWindow
        if openURLWindow.playerCore == self, openURLWindow.window?.isOpen == true {
          openURLWindow.failedToLoadURL()
        }
        _closeWindow()
      }
    } else if isFileLoaded || state.isAtLeast(.stopping) {
      // Check for stopping status also. Sometimes libmpv doesn't post stop message.
      closeWindow()
    }
    if state.isAtLeast(.started) {
      state = .idle
      receivedEndFileWhileLoading = false
    }
  }

  func mediaTitleChanged() {
    guard isActive else { return }
    DispatchQueue.main.async { [self] in
      guard windowController.isOpen else { return }
      postNotification(.iinaMediaTitleChanged)
    }
  }

  func reloadQuickSettingsView() {
    DispatchQueue.main.async { [self] in
      guard windowController.loaded else { return }
      guard !isStopping else { return }

      // Easiest place to put this - need to call it when setting equalizers
      videoView.displayActive(temporary: info.isPaused)
      windowController.quickSettingView.reload()
    }
  }

  func seeking() {
    log.trace("Seeking")
    DispatchQueue.main.async { [self] in
      // When playback is paused the display link may be shutdown in order to not waste energy.
      // It must be running when seeking to avoid slowdowns caused by mpv waiting for IINA to call
      // mpv_render_report_swap.
      videoView.displayActive()
    }

    if let pos = info.playbackPositionSec, let dur = info.playbackDurationSec {
      sendOSD(.seek(playbackPositionSec: pos, playbackDurationSec: dur))
    }
  }

  func ontopChanged() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard windowController.loaded else { return }
    let ontop = mpv.getFlag(MPVOption.Window.ontop)
    log.verbose("Δ mpv prop: 'ontop' = \(ontop.yesno)")
    if ontop != windowController.isOnTop {
      DispatchQueue.main.async { [self] in
        windowController.setWindowFloatingOnTop(ontop)
      }
    }
  }

  func playbackRestarted() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    log.debug("Playback restarted")

    DispatchQueue.main.async { [self] in
      windowController.updateUI()

      // When playback is paused the display link may be shutdown in order to not waste energy.
      // The display link will be restarted while seeking. If playback is paused shut it down
      // again.
      if info.isPaused {
        videoView.displayIdle()
      }

      // End of seeking? Set short timer to hide seek time & thumbnail
      windowController.resetSeekPreviewlTimer()
    }

    saveState()
  }

  func refreshEdrMode() {
    DispatchQueue.main.async { [self] in
      guard isActive else { return }
      guard windowController.loaded else { return }
      videoView.refreshEdrMode()
    }
  }

  func sidChanged(silent: Bool = false) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !windowController.sessionState.isRestoring, !isStopping else { return }
    let sid = Int(mpv.getInt(MPVOption.TrackSelection.sid))
    guard info.isFileLoaded else {
      log.verbose("SID changed to \(sid) but file is not loaded; ignoring")
      return
    }
    guard sid != info.sid else { return }
    info.sid = sid

    log.verbose("SID changed to \(sid)")
    if !silent {
      sendOSD(.track(info.currentTrack(.sub) ?? .noneSubTrack))
    }
    startWatchingSubFile()
    postNotification(.iinaSIDChanged)
    saveState()
  }

  func secondarySidChanged(silent: Bool = false) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !isRestoring, !isStopping else { return }
    let ssid = Int(mpv.getInt(MPVOption.Subtitles.secondarySid))
    guard info.isFileLoaded else {
      log.verbose("SSID changed to \(ssid) but file is not loaded; ignoring")
      return
    }
    guard ssid != info.secondSid else { return }
    info.secondSid = ssid

    log.verbose("SSID changed to \(ssid)")
    if !silent {
      sendOSD(.track(info.currentTrack(.secondSub) ?? .noneSecondSubTrack))
    }
    postNotification(.iinaSIDChanged)
    saveState()
    reloadQuickSettingsView()
  }

  func subScaleChanged(_ subScale: Double) {
    let displayValue = subScale >= 1 ? subScale : -1/subScale
    let subScale = displayValue.clamped(to: 0.1...10).roundedTo2()
    info.subScale = subScale
    sendOSD(.subScale(subScale))
    saveState()
    reloadQuickSettingsView()
  }

  func subVisibilityChanged(_ visible: Bool) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard info.isSubVisible != visible else { return }
    info.isSubVisible = visible
    sendOSD(visible ? .subVisible : .subHidden)
    saveState()
    postNotification(.iinaSubVisibilityChanged)
  }

  func secondSubVisibilityChanged(_ visible: Bool) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard info.isSecondSubVisible != visible else { return }
    info.isSecondSubVisible = visible
    sendOSD(visible ? .secondSubVisible : .secondSubHidden)
    saveState()
    postNotification(.iinaSecondSubVisibilityChanged)
  }

  func subDelayChanged(_ delay: Double) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    info.subDelay = delay
    sendOSD(.subDelay(delay))
    saveState()
    reloadQuickSettingsView()
  }

  func secondarySubDelayChanged(_ delay: Double) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    info.sub2Delay = delay
    sendOSD(.secondSubDelay(delay))
    saveState()
    reloadQuickSettingsView()
  }

  func subPosChanged(_ position: Double) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    info.subPos = position
    sendOSD(.subPos(position))
    saveState()
    reloadQuickSettingsView()
  }

  func secondarySubPosChanged(_ position: Double) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    info.sub2Pos = position
    sendOSD(.secondSubPos(position))
    saveState()
    reloadQuickSettingsView()
  }

  func trackListChanged() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    // No need to process track list changes if playback is being stopped. Must not process track
    // list changes if mpv is terminating as accessing mpv once shutdown has been initiated can
    // trigger a crash.
    guard !isStopping else { return }
    guard info.isFileLoaded else { return }
    log.debug("Track list changed")
    guard reloadTrackInfo() else { return }
    reloadSelectedTracks()
    log.verbose{"Posting iinaTracklistChanged vid=\(String(info.vid)) aid=\(String(info.aid)) sid=\(String(info.sid))"}
    postNotification(.iinaTracklistChanged)
  }

  func vfChanged() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !isStopping else { return }
    _ = getVideoFilters()
    postNotification(.iinaVFChanged)

    saveState()
    reloadQuickSettingsView()
  }

  func vidChanged(silent: Bool = false) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !isRestoring, !isStopping else { return }
    let vid = Int(mpv.getInt(MPVOption.TrackSelection.vid))
    guard let currentPlayback = info.currentPlayback else { return }
    let didChange = vid != info.vid
    // sometimes still need to show videoView when no actual vid change occurred (if use has vid=0 or no vid tracks exist)
    guard didChange || isShowVideoPendingInMiniPlayer else { return }
    guard info.isFileLoaded else {
      log.verbose{"Video track changed to \(vid) but file is not loaded; ignoring"}
      return
    }

#if DEBUG
    if vid == 0 {
      log.verbose("Video track is 0!")
    }
#endif

    info.vid = vid
    // Show OSD in music mode (if configured) when actually changing tracks, but not while toggling videoView visibility
    if !silent && (!isInMiniPlayer || (windowController.miniPlayer.isVideoVisible && !isShowVideoPendingInMiniPlayer)) {
      sendOSD(.track(info.currentTrack(.video) ?? .noneVideoTrack))
    }
    postNotification(.iinaVIDChanged)

    windowController.applyVideoGeoForStateChange(stateChange: { [self] cxt in
      log.verbose{"Calling applyVideoGeoForStateChange from vidChanged (to: \(vid)), vidLastSized=\(String(currentPlayback.vidTrackLastSized)), sessionState=\(cxt.sessionState))"}
      if case .existingSession_continuing = cxt.sessionState {
        if currentPlayback.state.isAtLeast(.loadedAndSized) && currentPlayback.vidTrackLastSized != vid {
          return .existingSession_videoTrackChangedForSamePlayback
        } else {
          return cxt.sessionState
        }
      }
      if isShowVideoPendingInMiniPlayer {
        return cxt.sessionState
      }
      return nil  // abort
    }, { [self] ctx in
      let oldMusicModeGeo = ctx.oldGeo.musicMode
      // Vid changed, but not from toggling music mode? Then no extra changes needed to musicMode geo.
      guard isShowVideoPendingInMiniPlayer else { return oldMusicModeGeo }
      /// Must change `isShowVideoPendingInMiniPlayer` in main queue only to avoid race!
      isShowVideoPendingInMiniPlayer = false
      miniPlayerShowVideoTimer?.invalidate()
      guard isInMiniPlayer && !windowController.miniPlayer.isVideoVisible else { return oldMusicModeGeo }
      /// `showDefaultArt` should already have been handled by `applyVideoGeoForStateChange` so do not change here
      let newGeo = oldMusicModeGeo.withVideoViewVisible(true)
      log.verbose{"MusicMode: changing videoView visibility: \(oldMusicModeGeo.isVideoVisible.yesno) → YES, H=\(newGeo.videoHeight)"}
      return newGeo
    })

  }

  /// In music mode, when toggling album art on, we wait for `vidChanged` to get called before showing the art.
  /// But it will not be called if there is no change (i.e. there are no video tracks at all).
  /// We can bridge the gap by setting a timer which will call `vidChanged`.
  @objc private func showVideoViewAfterVidChange() {
    guard isShowVideoPendingInMiniPlayer else { return }
    mpv.queue.async { [self] in
      log.verbose("Forcing vidChanged() to show videoView")
      vidChanged(silent: true)
    }
  }

  ///  Sets `vid=1` via mpv (if track exists), then if `showMiniPlayerVideo==true` and in music mode, shows `videoView`.
  ///  Does nothing if already in the target state (idempotent).
  ///
  ///  See also: `setVideoTrackDisabled`
  func setVideoTrackEnabled(thenShowMiniPlayerVideo showMiniPlayerVideo: Bool = false) {
    assert(DispatchQueue.isExecutingIn(.main))

    if showMiniPlayerVideo {
      isShowVideoPendingInMiniPlayer = true
      // In most cases, mpv will async'ly notify when the video track is done changing. But it is not guaranteed in all cases.
      // Give it a chance to load but use a timer as fallback to guarantee the videoView will open.
      let timeout = Constants.TimeInterval.musicModeChangeTrackTimeout
      log.verbose{"Will show music mode video after enabling video track, timeout=\(timeout)s"}
      miniPlayerShowVideoTimer = Timer.scheduledTimer(timeInterval: timeout,
                                                      target: self, selector: #selector(showVideoViewAfterVidChange),
                                                      userInfo: nil, repeats: false)
    }

    mpv.queue.async { [self] in
      guard isActive else {
        log.verbose("Skipping enable video track: player is not active")
        return
      }

      _ = reloadTrackInfo()
      let vidTrackCount = info.videoTracks.count
      let hasVidTrack = vidTrackCount > 0
      let vidNow = Int(mpv.getInt(MPVOption.TrackSelection.vid))
      let vidToSet: Int
      if let vidOld = info.vidDisabled {
        info.vidDisabled = nil
        if vidOld < vidTrackCount {
          vidToSet = vidOld
        } else {
          // vidDisabled is invalid. Can happen if media changed while disabled.
          // Just fall back to 1:
          vidToSet = 1
        }
      } else {
        vidToSet = 1
      }
      log.verbose{"Enabling video track: vidTrackCount=\(vidTrackCount) vidNow=\(vidNow) vidToSet=\(vidToSet) showMiniPlayerVideo=\(showMiniPlayerVideo.yn)"}
      guard (hasVidTrack && vidNow != vidToSet) else {
        info.vidDisabled = nil  // clear saved track
        if showMiniPlayerVideo {
          // If no vid track selected, don't need to change tracks if a track is already selected. But may still need to show videoView.
          // If no tracks, will not get a response from mpv if requesting to chamging tracks. But change geometry to set default album art.
          miniPlayerShowVideoTimer?.invalidate()
          log.verbose("Enabling video track: skipping, but forcing vidChanged() to show videoView")
          vidChanged(silent: true)
        }
        return
      }

      _setTrack(vidToSet, forType: .video, silent: true)
    }
  }

  ///  Sets `vid=0` via mpv. Does nothing if already in the target state (idempotent).
  ///
  ///  See also: `setVideoTrackEnabled`
  func setVideoTrackDisabled() {
    assert(DispatchQueue.isExecutingIn(.main))

    mpv.queue.async { [self] in
      _setVideoTrackDisabled()
    }
  }

  func _setVideoTrackDisabled() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    // Change video track to None
    let vidNow = Int(mpv.getInt(MPVOption.TrackSelection.vid))

    if info.vidDisabled == nil {
      log.verbose("Disabling video track: setting vidDisabled to \(vidNow) before setting vid=0")
      info.vidDisabled = vidNow
    }
    guard vidNow != 0 else {
      log.verbose("Disabling video track: vid=0 already, skipping")
      return
    }
    log.verbose("Setting vid=0")
    _setTrack(0, forType: .video, silent: true)
  }

  func windowScaleChanged() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard windowController.loaded else { return }
    // Ignore if magnifying - will mess up our animation. Will submit window-scale anyway at end of magnify
    guard !windowController.isMagnifying else { return }
    let isAlreadySized = info.currentPlayback?.state.isAtLeast(.loaded) ?? false
    guard isAlreadySized else { return }

    let cachedVideoScale: CGFloat
    if windowController.currentLayout.mode == .musicMode {
      cachedVideoScale = windowController.musicModeGeo.toPWinGeometry().mpvVideoScale()
    } else {
      cachedVideoScale = windowController.windowedModeGeo.mpvVideoScale()
    }
    let newVideoScale = mpv.getVideoScale()
    let needsUpdate = abs(newVideoScale - cachedVideoScale) > 10e-10
    guard needsUpdate else {
      log.verbose{"Δ mpv prop: 'window-scale'; videoScale \(newVideoScale) not changed"}
      return
    }

    log.verbose{"Δ mpv prop: 'window-scale', \(cachedVideoScale) → \(newVideoScale)"}
    DispatchQueue.main.async { [self] in
      log.verbose{"Calling setVideoScale → \(newVideoScale)x"}
      windowController.changeVideoScale(to: newVideoScale)
    }
  }

  private func autoSearchOnlineSub() {
    if Preference.bool(for: .autoSearchOnlineSub) &&
      !info.isNetworkResource && info.subTracks.isEmpty &&
      (info.playbackDurationSec ?? 0.0) >= Preference.double(for: .autoSearchThreshold) * 60 {
      windowController.menuFindOnlineSub(.dummy)
    }
  }

  /**
   Add files in the same folder to playlist.
   It basically follows the following steps:
   - Get all files in current folder. Group and sort videos and audios, and add them to playlist.
   - Scan subtitles from search paths, combined with subs got in previous step.
   - Try match videos and subs by series and filename.
   - For unmatched videos and subs, perform fuzzy (but slow, O(n^2)) match for them.

   **Remark**:

   This method is expected to be executed in `backgroundQueue` (see `backgroundQueueTicket`).
   Therefore accesses to `self.info` and mpv playlist must be guarded.
   */
  private func autoLoadFilesInCurrentFolder(ticket: Int) {
    AutoFileMatcher(player: self, ticket: ticket).startMatching()
  }

  private func startWatchingSubFile() {
    guard let currentSubTrack = info.currentTrack(.sub) else { return }
    guard let externalFilename = currentSubTrack.externalFilename else {
      log.verbose{"Sub \(currentSubTrack.id) is not an external file"}
      return
    }

    // Stop previous watch (if any)
    stopWatchingSubFile()

    let subURL = URL(fileURLWithPath: externalFilename)
    let fileMonitor = FileMonitor(url: subURL)
    fileMonitor.fileDidChange = { [self] in
      let code = mpv.command(.subReload, args: ["\(currentSubTrack.id)"], checkError: false)
      if code < 0 {
        log.error{"Failed reloading sub track \(currentSubTrack.id): error code \(code)"}
      }
    }
    subFileMonitor = fileMonitor
    log.verbose{"Starting FS watch of sub file \(subURL.path.pii.quoted)"}
    fileMonitor.startMonitoring()
  }

  private func stopWatchingSubFile() {
    guard let subFileMonitor else { return }

    log.verbose{"Stopping FS watch of sub file \(Playback.path(from: subFileMonitor.url).pii.quoted)"}
    subFileMonitor.stopMonitoring()
    self.subFileMonitor = nil
  }

  /**
   Checks unsynchronized window options, such as those set via mpv before window loaded.

   These options currently include fullscreen and ontop.
   */
  private func checkUnsyncedWindowOptions() {
    guard windowController.loaded else { return }

    syncFullScreenState()
    let ontop = mpv.getFlag(MPVOption.Window.ontop)
    if ontop != windowController.isOnTop {
      log.verbose{"IINA OnTop state (\(windowController.isOnTop.yn)) does not match mpv (\(ontop.yn)). Will change to match mpv state"}
      DispatchQueue.main.async {
        self.windowController.setWindowFloatingOnTop(ontop, updateOnTopStatus: false)
      }
    }
  }

  func syncFullScreenState() {
    guard windowController.loaded else { return }
    let mpvFS = mpv.getFlag(MPVOption.Window.fullscreen)
    let iinaFS = windowController.isFullScreen
    log.verbose{"IINA FullScreen state: \(iinaFS.yn), mpv: \(mpvFS.yn)"}
    if mpvFS != iinaFS {
      if mpvFS && didEnterFullScreenViaUserToggle {
        didEnterFullScreenViaUserToggle = false
        mpv.setFlag(MPVOption.Window.fullscreen, false)
      } else {
        DispatchQueue.main.async { [self] in
          if mpvFS {
            windowController.enterFullScreen()
          } else {
            windowController.exitFullScreen()
          }
        }
      }
    }
  }

  // MARK: - Sync with UI in PlayerWindow

  var lastTimerSummary = ""  // for reducing log volume

  /// Assess the need for the timer that synchronizes the UI and start or stop it as needed.
  ///
  /// Call this when `syncUITimer` may need to be started, stopped, or needs its interval changed. It will figure out the correct action.
  ///
  /// This method is required to adhere to the best practices in the [Energy Efficiency Guide for Mac Apps](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/UsingEfficientGraphics.html#//apple_ref/doc/uid/TP40013929-CH27-SW1)
  /// that call for an app to avoid needless energy use. [Minimizing Timer Usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html#//apple_ref/doc/uid/TP40013929-CH5-SW1) is one of the recommended best practices.
  /// - Important: Make sure that any state variables (e.g., `info.isPaused`, `isInMiniPlayer`,  etc.) are set *before*
  ///     calling this method, not after, so that it makes the correct decisions.
  func refreshSyncUITimer(logMsg: String = "") {
    // Check if timer should start/restart
    assert(DispatchQueue.isExecutingIn(.main))

    let useTimer: Bool
    if state.isAtLeast(.stopping) {
      useTimer = false
    } else if info.isPaused {
      // Follow energy efficiency best practices and ensure IINA is absolutely idle when the
      // video is paused to avoid wasting energy with needless processing. If paused shutdown
      // the timer that synchronizes the UI and the high priority display link thread.

      // If showing OSC for streaming media, even while paused the cache may still be filling,
      // which will change the duration continuously.
      useTimer = info.isNetworkResource && windowController.isUITimerNeeded()
    } else if needsTouchBar && TouchBarSettings.shared.showAppControls || isInMiniPlayer {
      // The timer can't be stopped if the mini player is being used as it always displays the OSC
      // or if the timer is updating the information being displayed in the Touch Bar.
      useTimer = true
    } else if info.isNetworkResource {
      // May need to show, hide, or update buffering indicator at any time.
      useTimer = true
    } else {
      useTimer = windowController.isUITimerNeeded()
    }

    let timerConfig = AppData.syncTimerConfig

    /// Invalidate existing timer:
    /// - if no longer needed
    /// - if still needed but need to change the `timeInterval`
    var wasTimerRunning = false
    var timerRestartNeeded = false
    if let existingTimer = self.syncUITimer, existingTimer.isValid {
      wasTimerRunning = true
      if useTimer {
        if timerConfig.interval == existingTimer.timeInterval {
          /// Don't restart the existing timer if not needed, because restarting will ignore any time it has
          /// already spent waiting, and could in theory result in a small visual jump (more so for long intervals).
        } else {
          timerRestartNeeded = true
        }
      }

      if !useTimer || timerRestartNeeded {
        log.verbose("Invalidating SyncUITimer")
        existingTimer.invalidate()
        self.syncUITimer = nil
      }
    }

    if Logger.isEnabled(.verbose) {
      var summary: String = ""
      if wasTimerRunning {
        if useTimer {
          summary = timerRestartNeeded ? "restarting" : "running"
        } else {
          summary = "didStop"
        }
      } else {  // timer was not running
        summary = useTimer ? "starting" : "notNeeded"
      }
      if summary != lastTimerSummary {
        lastTimerSummary = summary
        if useTimer {
          summary += ", every \(timerConfig.interval)s"
        }
        log.verbose {
          let logMsg = logMsg.isEmpty ? logMsg : "\(logMsg)- "
          return "\(logMsg)SyncUITimer \(summary), paused:\(info.isPaused.yn) net:\(info.isNetworkResource.yn) mini:\(isInMiniPlayer.yn) touchBar:\(needsTouchBar.yn) state:\(state)"
        }
      }
    }

    // When fadeable views are hidden the time can get out of sync. This method will be called when
    // the view becomes visible to sync the time. If the timer was not running the view must be
    // updated now. Playback may be paused. If that is the case then the timer will not be started.
    if !wasTimerRunning {
      // Do not wait for first redraw
      windowController.updateUI()
    }

    guard useTimer && (timerRestartNeeded || !wasTimerRunning) else {
      return
    }

    // Timer will start

    log.verbose("Scheduling SyncUITimer")
    syncUITimer = Timer.scheduledTimer(
      timeInterval: timerConfig.interval,
      target: self,
      selector: #selector(fireSyncUITimer),
      userInfo: nil,
      repeats: true
    )
    /// This defaults to 0 ("no tolerance"). But after profiling, it was found that granting a tolerance of `timeInterval * 0.1` (10%)
    /// resulted in an ~8% redunction in CPU time used by UI sync.
    syncUITimer?.tolerance = timerConfig.tolerance
  }

  @objc func fireSyncUITimer() {
    syncUITicketCounter += 1
    let syncUITicket = syncUITicketCounter

    windowController.animationPipeline.submitInstantTask { [self] in
      guard syncUITicket == syncUITicketCounter else {
        return
      }
      windowController.updateUI()
    }
  }

  private var lastSaveTime = Date().timeIntervalSince1970

  func updatePlaybackTimeInfo() {
    guard state.isAtLeast(.started), state.isNotYet(.stopping) else {
      log.verbose("syncUITime: not syncing")
      return
    }

    let isNetworkStream = info.isNetworkResource
    if isNetworkStream {
      info.playbackDurationSec = mpv.getDouble(MPVProperty.duration)
    }
    // When the end of a video file is reached mpv does not update the value of the property
    // time-pos, leaving it reflecting the position of the last frame of the video. This is
    // especially noticeable if the onscreen controller time labels are configured to show
    // milliseconds. Adjust the position if the end of the file has been reached.
    let eofReached = mpv.getFlag(MPVProperty.eofReached)
    let playbackPositionSec: Double
    if eofReached, let duration = info.playbackDurationSec {
      playbackPositionSec = duration
    } else {
      playbackPositionSec = mpv.getDouble(MPVProperty.timePos)
    }
    info.playbackPositionSec = playbackPositionSec

    info.constrainVideoPosition()
    if isNetworkStream || Preference.bool(for: .showCachedRangesInSlider) {
      updateCacheInfo()
    } else {
      info.cacheTime = 0
    }

    // Ensure user can resume playback by periodically saving
    let now = Date().timeIntervalSince1970
    let secSinceLastSave = now - lastSaveTime
    if secSinceLastSave >= Constants.TimeInterval.playTimeSaveStateFrequency {
      log.trace{"Another \(Constants.TimeInterval.playTimeSaveStateFrequency)s has passed: saving player state"}
      saveState()
      lastSaveTime = now
    }
  }

  func updateCacheInfo() {
    var cachedRanges: [(Double, Double)] = []
    info.pausedForCache = mpv.getFlag(MPVProperty.pausedForCache)
    if let demuxerCacheState = mpv.getNode(MPVProperty.demuxerCacheState) as? [String: Any] {
      if let underrun = demuxerCacheState["underrun"] as? Bool, underrun {
        if !isBufferUnderrun {
          log.verbose("Buffer underrun")
          isBufferUnderrun = true
        }
      } else if isBufferUnderrun {
        log.verbose("Buffer OK")
        isBufferUnderrun = false
      }
      if let seekableRanges = demuxerCacheState["seekable-ranges"] as? [[String: Any]] {
        for seekableRange in seekableRanges {
          if let rangeStart = seekableRange["start"] as? Double, let rangeEnd = seekableRange["end"] as? Double {
            cachedRanges.append((rangeStart, rangeEnd))
          }
        }
      }
      if let cacheUsed = demuxerCacheState["fw-bytes"] as? Int {
        info.cacheUsed = cacheUsed
      }
      self.cachedRanges = cachedRanges
    }
//    NSLog("   *** CACHED RANGES: \(cachedRanges.count): \(cachedRanges)")
    info.cacheSpeed = mpv.getInt(MPVProperty.cacheSpeed)
    info.cacheTime = mpv.getDouble(MPVProperty.demuxerCacheTime)
    info.bufferingState = mpv.getInt(MPVProperty.cacheBufferingState)
  }

  // difficult to use option set
  enum SyncUIOption {
    case volume
    case muteButton
    case chapterList
    case playlist
    case loop
  }

  func syncUI(_ option: SyncUIOption) {
    // if window not loaded, ignore
    guard windowController.loaded else { return }
    log.verbose{"Syncing UI \(option)"}

    switch option {

    case .volume, .muteButton:
      DispatchQueue.main.async { [self] in
        windowController.updateVolumeUI()
      }

    case .chapterList:
      DispatchQueue.main.async { [self] in
        // this should avoid sending reload when table view is not ready
        if isInMiniPlayer ? windowController.miniPlayer.isPlaylistVisible : windowController.isShowing(sidebarTab: .chapters) {
          windowController.playlistView.chapterTableView.reloadData()
        }
      }

    case .playlist:
      DispatchQueue.main.async {
        if self.isPlaylistVisible {
          self.windowController.playlistView.playlistTableView.reloadData()
        }
      }

    case .loop:
      DispatchQueue.main.async {
        self.windowController.playlistView.updateLoopBtnStatus()
      }
    }

    // All of the above reflect a state change. Save it:
    saveState()
  }

  func canShowOSD() -> Bool {
    /// Note: use `loaded` (querying `isWindowLoaded` will initialize windowController unexpectedly)
    if !windowController.loaded || !Preference.bool(for: .enableOSD) || isUsingMpvOSD || isRestoring || isInInteractiveMode {
      return false
    }
    if isInMiniPlayer && !Preference.bool(for: .enableOSDInMusicMode) {
      return false
    }

    return true
  }

  func sendOSD(_ msg: OSDMessage, autoHide: Bool = true, forcedTimeout: Double? = nil,
               accessoryViewController: NSViewController? = nil, external: Bool = false) {
    if case .debug = msg {
      log.verbose{"DebugOSD: \(msg)"}
    }

    /// Check `isFileLoadedAndSized` early to prevent race condition
    let disableOSDForFileLoading: Bool = !info.isFileLoadedAndSized
    if disableOSDForFileLoading && !external {
      switch msg {
      case .fileStart,
          .resumeFromWatchLater,
          .debug:
        break
      default:
        return
      }
    }

    windowController.displayOSD(msg, autoHide: autoHide, forcedTimeout: forcedTimeout, accessoryViewController: accessoryViewController, isExternal: external)
  }

  func hideOSD() {
    DispatchQueue.main.async {
      self.windowController.hideOSD()
    }
  }

  func closeWindow() {
    DispatchQueue.main.async { [self] in
      _closeWindow()
    }
  }

  /// Closes the window & ensures its state is properly updated.
  ///
  /// After closing the window, calls `AppDelegate.shared.windowWillClose` explicitly (AppKit should always call
  /// it via` NotificationCenter`, but this will dispel all doubt).
  /// This function can safely be called more than once without danger of side effects.
  private func _closeWindow() {
    assert(DispatchQueue.isExecutingIn(.main))
    stop()
    window.postWindowMustCancelShow()
    log.verbose("Closing window")
    windowController.close()
    /// `windowController.close()` doesn't always fire notification (e.g., if the window is ordered out).
    /// Call manually to ensure things execute:
    AppDelegate.shared.windowWillClose(window)
  }

  func reloadThumbnails() {
    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.TimeInterval.thumbnailRegenerationDelay) { [self] in
      guard let currentPlayback = info.currentPlayback else {
        log.debug("Thumbnails reload stopped because no current playback")
        touchBarSupport.touchBarPlaySlider?.resetCachedThumbnails()
        return
      }
      let videoTrackID = info.vid
      guard let videoTrackID, videoTrackID > 0 else {
        log.debug("Thumbnails reload stopped: invalid/missing video track \(String(videoTrackID))")
        clearExistingThumbnails(for: currentPlayback)
        return
      }
      guard !currentPlayback.isNetworkResource else {
        log.verbose("Thumbnails reload stopped current media is network")
        clearExistingThumbnails(for: currentPlayback)
        return
      }
      guard Preference.bool(for: .enableThumbnailPreview) else {
        log.verbose("Thumbnails reload stopped because thumbnails are disabled by user")
        clearExistingThumbnails(for: currentPlayback)
        return
      }
      if !Preference.bool(for: .enableThumbnailForRemoteFiles) && info.isMediaOnRemoteDrive {
        log.debug("Thumbnails reload stopped because file is on a mounted remote drive")
        clearExistingThumbnails(for: currentPlayback)
        return
      }
      if isInMiniPlayer && !Preference.bool(for: .enableThumbnailForMusicMode) {
        log.verbose("Thumbnails reload stopped because user has not enabled for music mode")
        clearExistingThumbnails(for: currentPlayback)
        return
      }

      let reloadTicket: Int = $thumbnailReloadTicketCounter.withLock {
        $0 += 1
        return $0
      }

      // Run the following in the background at lower priority, so the UI is not slowed down
      PlayerCore.thumbnailQueue.asyncAfter(deadline: .now() + 0.5) { [self] in
        guard reloadTicket == thumbnailReloadTicketCounter else { return }
        guard !isStopping else { return }
        log.debug{"Reloading thumbnails (tkt \(reloadTicket))"}

        var queueTicket: Int = 0
        $thumbnailQueueTicket.withLock {
          $0 += 1  // this will cancel any previous thumbnail loads for this player
          queueTicket = $0
        }

        // Generate thumbnails using video's original dimensions, before aspect ratio correction.
        // We will adjust aspect ratio & rotation when we display the thumbnail, similar to how mpv works.
        let videoGeo = videoGeo
        let videoSizeRaw = videoGeo.videoSizeRaw

        let thumbnailWidth = SingleMediaThumbnailsLoader.determineWidthOfThumbnail(from: videoSizeRaw, log: log)

        if let oldThumbs = currentPlayback.thumbnails {
          if !oldThumbs.isCancelled, oldThumbs.mediaFilePath == currentPlayback.url.path,
             oldThumbs.videoTrackID == videoTrackID,
             thumbnailWidth == oldThumbs.thumbnailWidth,
             videoGeo.totalRotation == oldThumbs.rotationDegrees {
            log.debug{"Already loaded \(oldThumbs.thumbnails.count) thumbnails (\(oldThumbs.thumbnailsProgress * 100.0)%) for vid\(videoTrackID) (\(thumbnailWidth)px, \(videoGeo.totalRotation)°). Nothing to do"}
            return
          } else {
            clearExistingThumbnails(for: currentPlayback)
          }
        }

        let newMediaThumbnailLoader = SingleMediaThumbnailsLoader(self, queueTicket: queueTicket, mediaFilePath: currentPlayback.url.path, mediaFilePathMD5: currentPlayback.mpvMD5,
                                                                  videoTrackID: videoTrackID, thumbnailWidth: thumbnailWidth, rotationDegrees: videoGeo.totalRotation)
        currentPlayback.thumbnails = newMediaThumbnailLoader
        guard queueTicket == thumbnailQueueTicket else { return }
        newMediaThumbnailLoader.loadThumbnails()
      }
    }
  }

  private func clearExistingThumbnails(for currentPlayback: Playback) {
    if currentPlayback.thumbnails != nil {
      currentPlayback.thumbnails = nil
    }
    touchBarSupport.touchBarPlaySlider?.resetCachedThumbnails()
  }

  func makeTouchBar() -> NSTouchBar {
    log.debug("Activating Touch Bar")
    needsTouchBar = true
    // The timer that synchronizes the UI is shutdown to conserve energy when the OSC is hidden.
    // However the timer can't be stopped if it is needed to update the information being displayed
    // in the touch bar. If currently playing make sure the timer is running.
    refreshSyncUITimer()
    return touchBarSupport.touchBar
  }

  func refreshTouchBarSlider() {
    DispatchQueue.main.async {
      self.touchBarSupport.touchBarPlaySlider?.needsDisplay = true
    }
  }

  // MARK: - Getting info

  func reloadTrackInfo() -> Bool {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    log.trace("Reloading tracklist from mpv")

    let trackCount = mpv.getInt(MPVProperty.trackListCount)
    guard trackCount > 0 else {
      log.verbose("No tracks returned by mpv's trackListCount; ignoring")
      return false
    }

    var audioTracks: [MPVTrack] = []
    var videoTracks: [MPVTrack] = []
    var subTracks: [MPVTrack] = []

    for index in 0..<trackCount {
      // get info for each track
      guard let trackType = mpv.getString(MPVProperty.trackListNType(index)) else { continue }
      let track = MPVTrack(id: mpv.getInt(MPVProperty.trackListNId(index)),
                           type: MPVTrack.TrackType(rawValue: trackType)!,
                           isDefault: mpv.getFlag(MPVProperty.trackListNDefault(index)),
                           isForced: mpv.getFlag(MPVProperty.trackListNForced(index)),
                           isSelected: mpv.getFlag(MPVProperty.trackListNSelected(index)),
                           isExternal: mpv.getFlag(MPVProperty.trackListNExternal(index)))
      track.srcId = mpv.getInt(MPVProperty.trackListNSrcId(index))
      track.title = mpv.getString(MPVProperty.trackListNTitle(index))
      track.lang = mpv.getString(MPVProperty.trackListNLang(index))
      track.codec = mpv.getString(MPVProperty.trackListNCodec(index))
      track.externalFilename = mpv.getString(MPVProperty.trackListNExternalFilename(index))
      track.isAlbumart = mpv.getString(MPVProperty.trackListNAlbumart(index)) == "yes"
      track.decoderDesc = mpv.getString(MPVProperty.trackListNDecoderDesc(index))
      track.demuxW = mpv.getInt(MPVProperty.trackListNDemuxW(index))
      track.demuxH = mpv.getInt(MPVProperty.trackListNDemuxH(index))
      track.demuxFps = mpv.getDouble(MPVProperty.trackListNDemuxFps(index))
      track.demuxChannelCount = mpv.getInt(MPVProperty.trackListNDemuxChannelCount(index))
      track.demuxChannels = mpv.getString(MPVProperty.trackListNDemuxChannels(index))
      track.demuxSamplerate = mpv.getInt(MPVProperty.trackListNDemuxSamplerate(index))

      // add to lists
      switch track.type {
      case .audio:
        audioTracks.append(track)
      case .video:
        videoTracks.append(track)
      case .sub:
        subTracks.append(track)
      default:
        break
      }
    }

    info.replaceTracks(audio: audioTracks, video: videoTracks, sub: subTracks)
    log.debug{"Reloaded tracklist from mpv (\(trackCount) tracks)"}
    return true
  }

  private func reloadSelectedTracks(silent: Bool = false) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    log.verbose("Reloading selected tracks")
    aidChanged(silent: silent)
    vidChanged(silent: silent)
    sidChanged(silent: silent)
    secondarySidChanged(silent: silent)

    saveState()
  }

  /// Reloads playlist from mpv, then enqueues state save & sends `iinaPlaylistChanged` notification.
  func reloadPlaylist() {
    mpv.queue.async { [self] in
      _reloadPlaylist()
    }
  }

  private func _reloadPlaylist(silent: Bool = false) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !isStopping else { return }
    log.verbose("Reloading playlist")
    var newPlaylist: [MPVPlaylistItem] = []
    let playlistCount = mpv.getInt(MPVProperty.playlistCount)
    log.verbose{"Reloaded playlist will have \(playlistCount) items"}
    for index in 0..<playlistCount {
      let urlPath = mpv.getString(MPVProperty.playlistNFilename(index))!
      let url = Playback.url(fromPath: urlPath)!
      let playlistItem = MPVPlaylistItem(url: url)
      newPlaylist.append(playlistItem)
    }
    info.playlist = newPlaylist
    let mpvPlaylistPos = mpv.getInt(MPVProperty.playlistPos)
    info.currentPlayback?.playlistPos = mpvPlaylistPos
    if isPlaylistVisible {
      DispatchQueue.main.async { [self] in
        windowController.playlistView.refreshNowPlayingIndex(setNewIndexTo: mpvPlaylistPos)
      }
    }
    log.verbose{"After reloading playlist: playlistPos is: \(mpvPlaylistPos)"}
    saveState()  // save playlist URLs to prefs
    if !silent {
      postNotification(.iinaPlaylistChanged)
    }
  }

  func reloadChapters() {
    mpv.queue.async { [self] in
      _reloadChapters()
    }
    syncUI(.chapterList)
  }

  func _reloadChapters() {
    log.verbose("Reloading chapter list")
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    var chapters: [MPVChapter] = []
    let chapterCount = mpv.getInt(MPVProperty.chapterListCount)
    for index in 0..<chapterCount {
      let chapter = MPVChapter(title:     mpv.getString(MPVProperty.chapterListNTitle(index)),
                               startTime: mpv.getDouble(MPVProperty.chapterListNTime(index)),
                               index:     index)
      chapters.append(chapter)
    }
    log.trace{"Chapters: \(chapters)"}
    // Instead of modifying existing list, overwrite reference to prev list.
    // This will avoid concurrent modification crashes
    info.chapters = chapters

    syncUI(.chapterList)
  }

  // MARK: - Notifications

  func postNotification(_ name: Notification.Name) {
    log.debug{"Posting notification: \(name.rawValue)"}
    NotificationCenter.default.post(Notification(name: name, object: self))
  }

  func postFileHistoryUpdateNotification() {
    guard let url = info.currentURL else { return }
    let note = Notification(name: .iinaFileHistoryDidUpdate, object: nil, userInfo: ["url": url])
    HistoryController.shared.postNotification(note)
  }

  /// Observer for changes to the macOS Touch Bar settings.
  /// - Parameters:
  ///   - keyPath: The key path, relative to `object`, to the value that has changed.
  ///   - object: The source object of the key path `keyPath`.
  ///   - change: A dictionary that describes the changes that have been made to the value of the property at the key path
  ///             `keyPath` relative to object. Entries are described in `Change Dictionary Keys`.
  ///   - context: The value that was provided when the observer was registered to receive key-value observation notifications.
  override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                             change: [NSKeyValueChangeKey: Any]?,
                             context: UnsafeMutableRawPointer?) {
    // The following guards are sanity checks and should never report an error.
    guard let keyPath = keyPath else {
      log.error("Observed key path is missing")
      return
    }
    guard let key = TouchBarSettings.Key(rawValue: keyPath) else {
      log.error("Observed key path is not a touch bar setting: \(keyPath)")
      return
    }
    guard key == .PresentationModeFnModes || key == .PresentationModeGlobal ||
          key == .PresentationModePerApp else {
      log.error("Observed key path is unrecognized: \(keyPath)")
      return
    }
    log.debug("Touch Bar \(key) setting has changed")
    // The macOS settings that control what the Touch Bar displays has changed. May need to start or
    // stop the timer that refreshes the UI.
    refreshSyncUITimer()
  }

  // MARK: - Utils

  func getMediaTitle(withExtension: Bool = true) -> String {
    if let mediaTitle = mpv.getString(MPVProperty.mediaTitle) {
      return mediaTitle
    }
    if let url = info.currentURL {
      return withExtension ? url.path : url.deletingPathExtension().path
    }
    return ""
  }

  func getMusicMetadata() -> (title: String, album: String, artist: String) {
    if mpv.getInt(MPVProperty.chapters) > 0 {
      let chapter = mpv.getInt(MPVProperty.chapter)
      let chapterTitle = mpv.getString(MPVProperty.chapterListNTitle(chapter))
      return (
        chapterTitle ?? mpv.getString(MPVProperty.mediaTitle) ?? "",
        mpv.getString("metadata/by-key/album") ?? "",
        mpv.getString("chapter-metadata/by-key/performer") ?? mpv.getString("metadata/by-key/artist") ?? ""
      )
    } else {
      return (
        mpv.getString(MPVProperty.mediaTitle) ?? "",
        mpv.getString("metadata/by-key/album") ?? "",
        mpv.getString("metadata/by-key/artist") ?? ""
      )
    }
  }

  private func setPlaybackInfoFilter(_ filter: MPVFilter) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    switch filter.label {
    case Constants.FilterLabel.crop:
      // CROP
      if let cropLabel = deriveCropLabel(from: filter) {
        updateSelectedCrop(to: cropLabel)  // Known aspect-based crop
      } else {
        // Cannot parse IINA crop filter? Remove crop
        log.error{"Could not determine crop from filter \(filter.label?.debugDescription.quoted ?? "nil"). Removing filter"}
        updateSelectedCrop(to: AppData.noneCropIdentifier)
      }
    case Constants.FilterLabel.flip:
      info.flipFilter = filter
    case Constants.FilterLabel.mirror:
      info.mirrorFilter = filter
    case Constants.FilterLabel.delogo:
      info.delogoFilter = filter
    default:
      return
    }
  }

  /** Check if there are IINA filters saved in watch_later file. */
  func reloadSavedIINAfilters() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    let videoFilters = getVideoFilters()
    postNotification(.iinaVFChanged)
    let audioFilters = getAudioFilters()
    postNotification(.iinaAFChanged)
    log.verbose{"Total filters from mpv: \(videoFilters.count) vf, \(audioFilters.count) af"}
  }

  /// `vf`: gets up-to-date list of video filters AND updates associated state in the process
  func getVideoFilters() -> [MPVFilter] {
    // Clear cached filters first:
    info.flipFilter = nil
    info.mirrorFilter = nil
    info.delogoFilter = nil
    let videoFilters = mpv.getFilters(MPVProperty.vf)
    var foundCropFilter = false
    for filter in videoFilters {
      log.verbose{"Got mpv vf, name: \(filter.name.quoted), label: \(filter.label?.quoted ?? "nil"), params: \(filter.params ?? [:])"}
      if filter.label == Constants.FilterLabel.crop {
        foundCropFilter = true
      }
      setPlaybackInfoFilter(filter)
    }
    if !foundCropFilter, videoGeo.hasCrop {
      log.debug("No crop filter found in mpv video filters. Removing crop")
      updateSelectedCrop(to: AppData.noneCropIdentifier)
    }
    return videoFilters
  }

  /// `af`: gets up-to-date list of audio filters AND updates associated state in the process
  func getAudioFilters() -> [MPVFilter] {
    let audioFilters = mpv.getFilters(MPVProperty.af)
    for filter in audioFilters {
      log.verbose{"Got mpv af, name: \(filter.name.quoted), label: \(filter.label?.quoted ?? "nil"), params: \(filter.params ?? [:])"}
      guard let label = filter.label else { continue }
      if label.hasPrefix(Constants.FilterLabel.audioEq) {
        info.audioEqFilter = filter
      }
    }
    return audioFilters
  }

  static func checkStatusForSleep() {
    guard Preference.bool(for: .preventScreenSaver) else {
      SleepPreventer.allowSleep()
      return
    }
    let playing = PlayerManager.shared.getNonIdle()
    // Look for players actively playing that are not in music mode and are not just playing audio.
    for player in playing {
      guard player.info.isPlaying,
            !player.info.currentMediaAudioStatus.isAudio && !player.isInMiniPlayer else { continue }
      SleepPreventer.preventSleep()
      return
    }
    // Now look for players in music mode or playing audio.
    for player in playing {
      guard player.info.isPlaying,
            player.info.currentMediaAudioStatus.isAudio || player.isInMiniPlayer else { continue }
      // Either prevent the screen saver from activating or prevent system from sleeping depending
      // upon user setting.
      SleepPreventer.preventSleep(allowScreenSaver: Preference.bool(for: .allowScreenSaverForAudio))
      return
    }
    // No players are actively playing.
    SleepPreventer.allowSleep()
  }
}
