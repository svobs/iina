//
//  PlayerCore.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MediaPlayer

class PlayerCore: NSObject {
  // MARK: - Multiple instances
  static var manager = PlayerCoreManager()

  /// TODO: make `lastActive` and `active` Optional, so creating an uncessary player randomly at startup isn't needed

  /// - Important: Code referencing this property **must** be run on the main thread as getting the value of this property _may_
  ///              result in a reference the `active` property and that requires use of the main thread.
  static var lastActive: PlayerCore {
    get {
      return manager.lastActive ?? active
    }
    set {
      manager.lastActive = newValue
    }
  }

  /// - Important: Code referencing this property **must** be run on the main thread because it references
  ///              [NSApplication.windowController`](https://developer.apple.com/documentation/appkit/nsapplication/1428723-mainwindow)
  static var active: PlayerCore {
    return manager.getActive()
  }

  static var newPlayerCore: PlayerCore {
    return manager.getIdleOrCreateNew()
  }

  static var activeOrNew: PlayerCore {
    return manager.getActiveOrCreateNew()
  }

  static var playing: [PlayerCore] {
    return manager.getNonIdle()
  }

  static func activeOrNewForMenuAction(isAlternative: Bool) -> PlayerCore {
    let useNew = Preference.bool(for: .alwaysOpenInNewWindow) != isAlternative
    return useNew ? newPlayerCore : active
  }

  // MARK: - Fields

  let subsystem: Logger.Subsystem
  unowned var log: Logger.Subsystem { self.subsystem }
  var label: String

  @Atomic var saveTicketCounter: Int = 0
  @Atomic private var thumbnailReloadTicketCounter: Int = 0

  // Plugins
  var isManagedByPlugin = false
  var userLabel: String?
  var disableUI = false
  var disableWindowAnimation = false

  // Internal vars used to make sure init functions don't happen more than once
  private var didStart = false
  private var didInitVideo = false

  @available(macOS 10.12.2, *)
  var touchBarSupport: TouchBarSupport {
    get {
      return self._touchBarSupport as! TouchBarSupport
    }
  }
  private var _touchBarSupport: Any?

  /// `true` if this Mac is known to have a touch bar.
  ///
  /// - Note: This is set based on whether `AppKit` has called `MakeTouchBar`, therefore it can, for example, be `false` for
  ///         a MacBook that has a touch bar if the touch bar is asleep because the Mac is in closed clamshell mode.
  var needsTouchBar = false

  /// A dispatch queue for auto load feature.
  static let backgroundQueue = DispatchQueue(label: "IINAPlayerCoreTask", qos: .background)
  static let playlistQueue = DispatchQueue(label: "IINAPlaylistTask", qos: .utility)
  static let thumbnailQueue = DispatchQueue(label: "IINAPlayerCoreThumbnailTask", qos: .utility)

  /**
   This ticket will be increased each time before a new task being submitted to `backgroundQueue`.

   Each task holds a copy of ticket value at creation, so that a previous task will perceive and
   quit early if new tasks is awaiting.

   **See also**:

   `autoLoadFilesInCurrentFolder(ticket:)`
   */
  @Atomic var backgroundQueueTicket = 0

  // Ticket for sync UI update request
  @Atomic private var syncUITicketCounter: Int = 0

  // Windows

  var windowController: PlayerWindowController!

  var window: PlayerWindow {
    return (windowController.window as! PlayerWindow)
  }

  var mpv: MPVController!
  lazy var videoView: VideoView = VideoView(player: self)

  var bindingController: PlayerBindingController!

  var plugins: [JavascriptPluginInstance] = []
  private var pluginMap: [String: JavascriptPluginInstance] = [:]
  var events = EventController()

  var info: PlaybackInfo

  var syncUITimer: Timer?

  var isUsingMpvOSD = false
  /// Whether shutdown of this player has been initiated.
  var isShuttingDown = false

  /// Whether shutdown of this player has completed (mpv has shutdown).
  var isShutdown = false

  /// Whether stopping of this player has been initiated.
  /// Should always be updated in mpv DQ
  var isStopping = false

  /// Whether mpv playback has stopped and the media has been unloaded.
  /// Should always be updated in main DQ
  var isStopped = true

  var isInMiniPlayer: Bool {
    return windowController.isInMiniPlayer
  }

  var isFullScreen: Bool {
    return windowController.isFullScreen
  }

  var isInInteractiveMode: Bool {
    return windowController.isInInteractiveMode
  }

  /// Set this to `true` if user changes "music mode" status manually. This disables `autoSwitchToMusicMode`
  /// functionality for the duration of this player even if the preference is `true`. But if they manually change the
  /// "music mode" status again, change this to `false` so that the preference is honored again.
  var overrideAutoMusicMode = false

  var isSearchingOnlineSubtitle = false

  /// For supporting mpv `--shuffle` arg, to shuffle playlist when launching from command line
  @Atomic private var shufflePending = false

  var isMiniPlayerWaitingToShowVideo: Bool = false

  // test seeking
  var triedUsingExactSeekForCurrentFile: Bool = false
  var useExactSeekForCurrentFile: Bool = true

  var isPlaylistVisible: Bool {
    isInMiniPlayer ? windowController.miniPlayer.isPlaylistVisible : windowController.isShowing(sidebarTab: .playlist)
  }

  var isOnlyOpenPlayer: Bool {
    for player in PlayerCore.manager.getPlayerCores() {
      if player != self && player.windowController.isOpen {
        return false
      }
    }
    return true
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
      mpv.setDouble(MPVOption.PlaybackControl.abLoopA, max(AppData.minLoopPointTime, newValue))
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
      mpv.setDouble(MPVOption.PlaybackControl.abLoopB, max(AppData.minLoopPointTime, newValue))
    }
  }

  var isABLoopActive: Bool {
    abLoopA != 0 && abLoopB != 0 && mpv.getString(MPVOption.PlaybackControl.abLoopCount) != "0"
  }

  init(_ label: String) {
    let log = Logger.Subsystem(rawValue: "PLR-\(label)")
    log.debug("PlayerCore \(label) init")
    self.label = label
    self.subsystem = log
    self.info = PlaybackInfo(log: log)
    super.init()
    self.mpv = MPVController(playerCore: self)
    self.bindingController = PlayerBindingController(playerCore: self)
    self.windowController = PlayerWindowController(playerCore: self)
    if #available(macOS 10.12.2, *) {
      self._touchBarSupport = TouchBarSupport(playerCore: self)
    }
  }

  // MARK: - Plugins

  static func reloadPluginForAll(_ plugin: JavascriptPlugin) {
    manager.getPlayerCores().forEach { $0.reloadPlugin(plugin) }
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

  private func open(_ url: URL?, shouldAutoLoad: Bool = false) {
    guard let url = url else {
      Logger.log("empty file path or url", level: .error, subsystem: subsystem)
      return
    }
    Logger.log("Open URL: \(url.absoluteString.pii.quoted), autoload=\(shouldAutoLoad.yn)", subsystem: subsystem)
    if shouldAutoLoad {
      info.shouldAutoLoadFiles = true
    }
    openPlayerWindow(url: url)
  }

  /**
   Open a list of urls. If there are more than one urls, add the remaining ones to
   playlist and disable auto loading.

   - Returns: `nil` if no further action is needed, like opened a BD Folder; otherwise the
   count of playable files.
   */
  @discardableResult
  func openURLs(_ urls: [URL], shouldAutoLoad autoLoad: Bool = true) -> Int? {
    guard !urls.isEmpty else { return 0 }
    log.debug("OpenURLs (autoLoad=\(autoLoad.yn)): \(urls.map{$0.absoluteString.pii})")
    let urls = Utility.resolveURLs(urls)

    // Handle folder URL (to support mpv shuffle, etc), BD folders and m3u / m3u8 files first.
    // For these cases, mpv will load/build the playlist and notify IINA when it can be retrieved.
    if urls.count == 1 {
      let url = urls[0]

      if isBDFolder(url)
          || Utility.playlistFileExt.contains(url.absoluteString.lowercasedPathExtension) {
        info.shouldAutoLoadFiles = false
        open(url)
        return nil
      }
    }

    let playableFiles = getPlayableFiles(in: urls)
    let count = playableFiles.count

    log.verbose("Found \(count) playable files for \(urls.count) requested URLs")
    // check playable files count
    if count == 0 {
      return 0
    }

    if !autoLoad {
      info.shouldAutoLoadFiles = false
    } else {
      info.shouldAutoLoadFiles = (count == 1)
    }

    // open the first file
    open(playableFiles[0])

    log.verbose("Adding \(count - 1) files to playlist. Autoload=\(info.shouldAutoLoadFiles)")
    addToPlaylist(urls: playableFiles[1..<count])
    return count
  }

  func openURL(_ url: URL, shouldAutoLoad: Bool = true) {
    info.hdrEnabled = Preference.bool(for: .enableHdrSupport)
    openURLs([url], shouldAutoLoad: shouldAutoLoad)
  }

  func openURLString(_ str: String) {
    if str == "-" {
      openPlayerWindow()
      return
    }
    if str.first == "/" {
      openURL(URL(fileURLWithPath: str))
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
          print("Cannot add percent encoding for \(str)")
          return
        }
        pstr = encoded
      }
      guard let url = URL(string: pstr) else {
        Logger.log("Cannot parse url for \(pstr)", level: .error, subsystem: subsystem)
        return
      }
      openURL(url)
    }
  }

  /// if `url` is `nil`, assumed to be `stdin`
  private func openPlayerWindow(url: URL? = nil) {
    let path: String
    if let url = url, url.absoluteString != "stdin" {
      path = url.isFileURL ? url.path : url.absoluteString
      info.currentMedia = MediaItem(url: url)
      log.debug("Opening Player window for URL: \(url.absoluteString.pii.quoted), path: \(path.pii.quoted)")
    } else {
      path = "-"
      let url = URL(string: "stdin")!
      info.currentMedia = MediaItem(url: url)
      log.debug("Opening Player window for stdin")
    }

    if !info.isRestoring {
      AppDelegate.shared.initialWindow.closePriorToOpeningPlayerWindow()
    }
    windowController.openWindow()

    mpv.queue.async { [self] in
      log.debug("OpenPlayerWindow: setting isFileLoaded=false")

      // Reset state flags
      info.isFileLoaded = false
      isStopping = false

      // Send load file command
      mpv.command(.loadfile, args: [path])

      if !info.isRestoring {  // restore state has higher precedence
        if Preference.bool(for: .enablePlaylistLoop) {
          mpv.setString(MPVOption.PlaybackControl.loopPlaylist, "inf")
        }
        if Preference.bool(for: .enableFileLoop) {
          mpv.setString(MPVOption.PlaybackControl.loopFile, "inf")
        }
      }
    }
  }

  // Does nothing if already started
  func start(restore: Bool = false) {
    guard !didStart else { return }
    didStart = true

    log.verbose("Player start, restoring=\(restore.yn)")

    startMPV()
    loadPlugins()

    if restore, let savedState = Preference.UIState.getPlayerSaveState(forPlayerID: label) {
      savedState.restoreTo(self)
    }
  }

  private func startMPV() {
    // set path for youtube-dl
    let oldPath = String(cString: getenv("PATH")!)
    var path = Utility.exeDirURL.path + ":" + oldPath
    if let customYtdlPath = Preference.string(for: .ytdlSearchPath), !customYtdlPath.isEmpty {
      path = customYtdlPath + ":" + path
    }
    setenv("PATH", path, 1)
    log.debug("Set env path to \(path.pii)")

    // set http proxy
    if let proxy = Preference.string(for: .httpProxy), !proxy.isEmpty {
      setenv("http_proxy", "http://" + proxy, 1)
      log.debug("Set env http_proxy to \(proxy.pii)")
    }

    mpv.mpvInit()
    events.emit(.mpvInitialized)

    if !getAudioDevices().contains(where: { $0["name"] == Preference.string(for: .audioDevice)! }) {
      log.verbose("Defaulting mpv audioDevice to 'auto'")
      setAudioDevice("auto")
    }
  }

  func initVideo() {
    guard !didInitVideo else { return }
    didInitVideo = true

    // init mpv render context.
    // The video layer must be displayed once to get the OpenGL context initialized.
    videoView.videoLayer.display()
    mpv.mpvInitRendering()
    videoView.startDisplayLink()
  }

  /// Launches background task which scans video files and collects video size metadata using ffmpeg
  func loadVideoSizes() {
    log.verbose("Filling in video sizes...")
    PlayerCore.backgroundQueue.async { [self] in
      AutoFileMatcher.fillInVideoSizes(info.currentVideosInfo)
    }
  }

  func saveState() {
    PlayerSaveState.save(self)  // record the pause state
  }


  // unload main window video view
  private func uninitVideo() {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    guard didInitVideo else { return }
    log.debug("Uninit video")
    videoView.stopDisplayLink()
    videoView.uninit()
    didInitVideo = false
  }

  /// Initiate shutdown of this player.
  ///
  /// This method is intended to only be used during application termination. Once shutdown has been initiated player methods
  /// **must not** be called.
  /// - Important: As a part of shutting down the player this method sends a quit command to mpv. Even though the command is
  ///     sent to mpv using the synchronous API mpv executes the quit command asynchronously. The player is not fully shutdown
  ///     until mpv finishes executing the quit command and shuts down.
  func shutdown() {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    guard !isShuttingDown else {
      log.verbose("Player is already shutting down")
      return
    }
    log.debug("Shutting down player")
    isShuttingDown = true
    savePlaybackPosition() // Save state to mpv watch-later (if enabled)
    refreshSyncUITimer()   // Shut down timer
    uninitVideo()          // Shut down DisplayLink

    mpv.mpvQuit()
  }

  func mpvHasShutdown(isMPVInitiated: Bool = false) {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    let suffix = isMPVInitiated ? " (initiated by mpv)" : ""
    log.debug("Player has shut down\(suffix)")
    isStopped = true
    isShutdown = true
    // If mpv shutdown was initiated by mpv then the player state has not been saved.
    if isMPVInitiated {
      isShuttingDown = true
      savePlaybackPosition() // Save state to mpv watch-later (if enabled)
      refreshSyncUITimer()   // Shut down timer
      uninitVideo()          // Shut down DisplayLink
    }
    log.debug("Removing player \(label)")
    PlayerCore.manager.removePlayer(withLabel: label)

    postNotification(.iinaPlayerShutdown)
  }

  func enterMusicMode(automatically: Bool = false) {
    log.debug("Switch to mini player, automatically=\(automatically)")
    if !automatically {
      // Toggle manual override
      overrideAutoMusicMode = !overrideAutoMusicMode
      log.verbose("Changed overrideAutoMusicMode to \(overrideAutoMusicMode)")
    }
    windowController.enterMusicMode()
    events.emit(.musicModeChanged, data: true)
  }

  func exitMusicMode(automatically: Bool = false) {
    Logger.log("Switch to normal window from mini player, automatically=\(automatically)", subsystem: subsystem)
    if !automatically {
      overrideAutoMusicMode = !overrideAutoMusicMode
      Logger.log("Changed overrideAutoMusicMode to \(overrideAutoMusicMode)",
                 level: .verbose, subsystem: subsystem)
    }
    windowController.exitMusicMode()
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
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    let isNormalSpeed = info.playSpeed == 1
    info.isPaused = true  // set preemptively to prevent inconsistencies in UI
    mpv.queue.async { [self] in
      guard !info.isIdle, !isStopping, !isStopped, !isShuttingDown, !isShutdown else { return }
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
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    // Restart playback when reached EOF
    if mpv.getFlag(MPVProperty.eofReached) && Preference.bool(for: .resumeFromEndRestartsPlayback) {
      _seek(absoluteSecond: 0)
    }
    mpv.setFlag(MPVOption.PlaybackControl.pause, false)
  }

  func resume() {
    info.isPaused = false  // set preemptively to prevent inconsistencies in UI
    mpv.queue.async { [self] in
      /// Set this so that callbacks will fire even though `info.isPaused` was already set
      info.pauseStateWasChangedLocally = true
      _resume()
    }
    windowController.updatePlayButtonAndSpeedUI()
  }

  /// Stop playback and unload the media.
  func stop() {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

    // If the user immediately closes the player window it is possible the background task may still
    // be working to load subtitles. Invalidate the ticket to get that task to abandon the work.
    $backgroundQueueTicket.withLock { $0 += 1 }

    videoView.stopDisplayLink()

    mpv.queue.async { [self] in
      saveState()            // Save state to IINA prefs (if enabled)
      savePlaybackPosition() // Save state to mpv watch-later (if enabled)

      // Reset playback state
      log.verbose("Stop called: resetting playback state")
      info.videoGeo = VideoGeometry.nullGeometry
      info.currentMedia = nil
      info.videoPosition = nil
      info.videoDuration = nil
      info.playlist = []

      info.$matchedSubs.withLock { $0.removeAll() }

      // Do not send a stop command to mpv if it is already stopped. This happens when quitting is
      // initiated directly through mpv.
      guard !isStopped else { return }
      log.debug("Stopping playback")

      sendOSD(.stop)
      isStopping = true
      DispatchQueue.main.async { [self] in
        refreshSyncUITimer()
      }
      mpv.command(.stop)
    }
  }

  /// Playback has stopped and the media has been unloaded.
  ///
  /// This method is called by `MPVController` when mpv emits an event indicating the asynchronous mpv `stop` command
  /// has completed executing.
  func playbackStopped() {
    log.debug("Playback has stopped")
    dispatchPrecondition(condition: .onQueue(mpv.queue))

    DispatchQueue.main.async { [self] in
      isStopped = true

      windowController.clearOSDQueue()

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
      if let duration = info.videoDuration?.second,
         duration > 0 {
        percent = percent.clamped(to: 0..<100)
      }
      let useExact = forceExact ? true : Preference.bool(for: .useExactSeek)
      let seekMode = useExact ? "absolute-percent+exact" : "absolute-percent"
      Logger.log("Seek \(percent) % (forceExact: \(forceExact), useExact: \(useExact) -> \(seekMode))", level: .verbose, subsystem: subsystem)
      mpv.command(.seek, args: ["\(percent)", seekMode], checkError: false)
    }
  }

  // Seek Relative
  func seek(relativeSecond: Double, option: Preference.SeekOption) {
    mpv.queue.async { [self] in
      log.verbose("Seek \(relativeSecond)s (\(option.rawValue))")
      switch option {

      case .relative:
        mpv.command(.seek, args: ["\(relativeSecond)", "relative"], checkError: false)

      case .exact:
        mpv.command(.seek, args: ["\(relativeSecond)", "relative+exact"], checkError: false)

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
        let seekMode = useExactSeekForCurrentFile ? "relative+exact" : "relative"
        mpv.command(.seek, args: ["\(relativeSecond)", seekMode], checkError: false)

      }
    }
  }

  // Seek Absolute
  func seek(absoluteSecond: Double) {
    mpv.queue.async { [self] in
      _seek(absoluteSecond: absoluteSecond)
    }
  }

  func _seek(absoluteSecond: Double) {
    Logger.log("Seek \(absoluteSecond) absolute+exact", level: .verbose, subsystem: subsystem)
    mpv.command(.seek, args: ["\(absoluteSecond)", "absolute+exact"])
  }

  func frameStep(backwards: Bool) {
    Logger.log("FrameStep (\(backwards ? "-" : "+"))", level: .verbose, subsystem: subsystem)
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

  func isScreenshotEnabled() -> Bool {
    let saveToFile = Preference.bool(for: .screenshotSaveToFile)
    let saveToClipboard = Preference.bool(for: .screenshotCopyToClipboard)
    return saveToFile || saveToClipboard
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
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    guard isScreenshotEnabled() else {
      Logger.log("Ignoring screenshot request\(keyBinding == nil ? "" : " from key binding") because all forms of screenshots are disabled in prefs")
      return false
    }

    var commandFlags: [String] = []

    if let keyBinding {
      var canUseIINAScreenshot = true

      guard let commandName = keyBinding.action.first, commandName == MPVCommand.screenshot.rawValue else {
        Logger.log("Cannot take screenshot: first token in key binding action is unexpected: \(keyBinding.action)")
        return false
      }
      if keyBinding.action.count > 1 {
        commandFlags = keyBinding.action[1].split(separator: "+").map{String($0)}

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
            Logger.log("Unrecognized flag for mpv 'screenshot' command: '\(flag)'", level: .warning)
            canUseIINAScreenshot = false
          }
        }
      }

      if !canUseIINAScreenshot {
        let returnValue = mpv.command(rawString: keyBinding.rawAction)
        return returnValue == 0
      }
    }

    guard let vid = info.vid, vid > 0 else { return false }  // TODO: why this is needed?

    if commandFlags.isEmpty {
      let includeSubtitles = Preference.bool(for: .screenshotIncludeSubtitle)
      commandFlags.append(includeSubtitles ? "subtitles" : "video")
    }

    mpv.queue.async { [self] in
      mpv.asyncCommand(.screenshot, args: commandFlags, replyUserdata: MPVController.UserData.screenshot)
    }
    return true
  }

  func screenshotCallback() {
    let saveToFile = Preference.bool(for: .screenshotSaveToFile)
    let saveToClipboard = Preference.bool(for: .screenshotCopyToClipboard)
    guard saveToFile || saveToClipboard else { return }

    guard let imageFolder = mpv.getString(MPVOption.Screenshot.screenshotDirectory) else { return }
    guard let lastScreenshotURL = Utility.getLatestScreenshot(from: imageFolder) else { return }
    guard let screenshotImage = NSImage(contentsOf: lastScreenshotURL) else {
      self.sendOSD(.screenshot)
      return
    }
    if saveToClipboard {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([screenshotImage])
    }
    guard Preference.bool(for: .screenshotShowPreview) else {
      self.sendOSD(.screenshot)
      return
    }

    DispatchQueue.main.async { [self] in
      let osdViewController = ScreenshootOSDView()
      // Shrink to some fraction of the currently displayed video
      let relativeSize = windowController.videoView.frame.size.multiply(0.3)
      let previewImageSize = screenshotImage.size.shrink(toSize: relativeSize)
      osdViewController.setImage(screenshotImage,
                       size: previewImageSize,
                       fileURL: saveToFile ? lastScreenshotURL : nil)

      self.sendOSD(.screenshot, forcedTimeout: 5, accessoryViewController: osdViewController)
      if !saveToFile {
        try? FileManager.default.removeItem(at: lastScreenshotURL)
      }
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
  func abLoop() -> Int32 {
    dispatchPrecondition(condition: .onQueue(mpv.queue))

    // may subject to change
    let returnValue = mpv.command(.abLoop)
    if returnValue == 0 {
      syncAbLoop()
      sendOSD(.abLoop(info.abLoopStatus))
    }
    return returnValue
  }

  /// Synchronize IINA with the state of the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  func syncAbLoop() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))

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
        log.error("Unexpected A-B loop state, ab-loop-a is \(a) ab-loop-b is \(b)")
        info.abLoopStatus = .aSet
      }
    } else {
      // A loop point has been set. B loop point must be set as well to activate looping.
      info.abLoopStatus = b == 0 ? .aSet : .bSet
    }
    // The play slider has knobs representing the loop points, make insure the slider is in sync.
    windowController?.syncPlaySliderABLoop()
    log.verbose("Synchronized info.abLoopStatus \(info.abLoopStatus)")
  }

  func togglePlaylistLoop() {
    mpv.queue.async { [self] in
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
      let loopMode = getLoopMode()
      if loopMode == .file {
        setLoopMode(.off)
      } else {
        setLoopMode(.file)
      }
    }
  }

  func getLoopMode() -> LoopMode {
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
    switch newMode {
    case .playlist:
      mpv.setString(MPVOption.PlaybackControl.loopPlaylist, "inf")
      mpv.setString(MPVOption.PlaybackControl.loopFile, "no")
      sendOSD(.playlistLoop)
    case .file:
      mpv.setString(MPVOption.PlaybackControl.loopFile, "inf")
      sendOSD(.fileLoop)
    case .off:
      mpv.setString(MPVOption.PlaybackControl.loopPlaylist, "no")
      mpv.setString(MPVOption.PlaybackControl.loopFile, "no")
      sendOSD(.noLoop)
    }
  }

  func nextLoopMode() {
    mpv.queue.async { [self] in
      setLoopMode(getLoopMode().next())
    }
  }

  func toggleShuffle() {
    mpv.queue.async { [self] in
      mpv.command(.playlistShuffle)
      _reloadPlaylist()
    }
  }

  func setVolume(_ volume: Double, constrain: Bool = true) {
    mpv.queue.async { [self] in
      let maxVolume = Preference.integer(for: .maxVolume)
      let constrainedVolume = volume.clamped(to: 0...Double(maxVolume))
      let appliedVolume = constrain ? constrainedVolume : volume
      info.volume = appliedVolume
      mpv.setDouble(MPVOption.Audio.volume, appliedVolume)
      // Save default for future players:
      Preference.set(constrainedVolume, for: .softVolume)
    }
  }

  func _setTrack(_ index: Int, forType trackType: MPVTrack.TrackType) {
    log.verbose("Setting \(trackType) track to \(index)")
    dispatchPrecondition(condition: .onQueue(mpv.queue))

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
    reloadSelectedTracks()
  }

  func setTrack(_ index: Int, forType: MPVTrack.TrackType) {
    mpv.queue.async { [self] in
      _setTrack(index, forType: forType)
    }
  }

  /// Set playbackk speed.
  /// If `forceResume` is `true`, then always resume if paused; if `false`, never resume if paused;
  /// if `nil`, then resume if paused based on pref setting.
  func setSpeed(_ speed: Double, forceResume: Bool? = nil) {
    let speedTrunc = speed.truncatedTo3()
    info.playSpeed = speedTrunc  // set preemptively to keep UI in sync
    mpv.queue.async { [self] in
      log.verbose("Setting speed to \(speedTrunc)")
      mpv.setDouble(MPVOption.PlaybackControl.speed, speedTrunc)

      /// If `resetSpeedWhenPaused` is enabled, then speed is reset to 1x when pausing.
      /// This will create a subconscious link in the user's mind between "pause" -> "unset speed".
      /// Try to stay consistent by linking the contrapositive together: "set speed" -> "play".
      /// The intuition should be most apparent when using the speed slider in Quick Settings.
      if info.isPaused {
        if let forceResume, forceResume {
          _resume()
        } else if forceResume == nil && Preference.bool(for: .resetSpeedWhenPaused) {
          _resume()
        }
      }
    }
  }

  /// Set video's aspect ratio. The param may be one of:
  /// 1. Target aspect ratio. This came from user input, either from a button, menu, or text entry.
  /// This can be either in colon notation (e.g., "16:10") or decimal ("2.333333").
  /// 2. Actual aspect ratio (like `info.videoAspect`, but that is applied *after* video rotation). After the target aspect
  /// is applied to the raw video dimensions, the resulting dimensions must be rounded to their nearest integer values
  /// (because of reasons). So when the aspect is recalculated from the new dimensions, the result may be slightly different.
  ///
  /// This method ensures that the following components are synced to the given aspect ratio:
  /// 1. mpv `video-aspect-override` property
  /// 2. Player window geometry / displayed video size
  /// 3. Quick Settings controls & menu item checkmarks
  ///
  /// To hopefully avoid precision problems, `aspectNormalDecimalString` is used for comparisons across data sources.
  func setVideoAspectOverride(_ aspect: String) {
    mpv.queue.async { [self] in
      _setVideoAspectOverride(aspect)
    }
  }

  func _setVideoAspectOverride(_ aspectString: String) {
    log.verbose("Got request to set videoAspectOverride to: \(aspectString.quoted)")
    dispatchPrecondition(condition: .onQueue(mpv.queue))

    let aspectLabel: String
    if aspectString.contains(":"), Aspect(string: aspectString) != nil {
      // Aspect is in colon notation (X:Y)
      aspectLabel = aspectString
    } else if let aspectDouble = Double(aspectString), aspectDouble > 0 {
      /// Aspect is a decimal number, but is not default (`-1` or video default)
      /// Try to match to known aspect by comparing their decimal values to the new aspect.
      /// Note that mpv seems to do its calculations to only 2 decimal places of precision, so use that for comparison.
      if let knownAspectRatio = findLabelForAspectRatio(aspectDouble) {
        aspectLabel = knownAspectRatio
      } else {
        aspectLabel = aspectDouble.aspectNormalDecimalString
      }
    } else {
      aspectLabel = AppData.defaultAspectIdentifier
      // -1, default, or unrecognized
      log.verbose("Setting selectedAspect to: \(AppData.defaultAspectIdentifier.quoted) for aspect \(aspectString.quoted)")
    }

    if info.videoGeo.selectedAspectLabel != aspectLabel {
      let newVideoGeo = info.videoGeo.clone(selectedAspectLabel: aspectLabel)

      // Send update to mpv
      let mpvValue = aspectLabel == AppData.defaultAspectIdentifier ? "no" : aspectLabel
      log.verbose("Setting mpv video-aspect-override to: \(mpvValue.quoted)")
      mpv.setString(MPVOption.Video.videoAspectOverride, mpvValue)

      // FIXME: Default aspect needs i18n
      sendOSD(.aspect(aspectLabel))

      if newVideoGeo.hasValidSize {
        // Change video size:
        log.verbose("Calling applyVidGeo from video-aspect-override")
        windowController.applyVidGeo(newVideoGeo)
      }
    }

    // Update controls in UI. Need to always execute this, so that clicking on the video default aspect
    // immediately changes the selection to "Default".
    reloadQuickSettingsView()
  }

  private func findLabelForAspectRatio(_ aspectRatioNumber: Double) -> String? {
    let mpvAspect = Aspect.mpvPrecision(of: aspectRatioNumber)
    for knownAspectRatio in AppData.aspectsInMenu {
      if let parsedAspect = Aspect(string: knownAspectRatio), parsedAspect.value == mpvAspect {
        // Matches a known aspect. Use its colon notation (X:Y) instead of decimal value
        return knownAspectRatio
      }
    }
    // Not found
    return nil
  }

  func updateMPVWindowScale(using windowGeo: PWGeometry) {
    mpv.queue.async { [self] in
      guard let actualVideoScale = deriveVideoScale(from: windowGeo) else {
        log.verbose("Skipping update to mpv window-scale: could not get size info")
        return
      }
      let prevVideoScale: CGFloat = info.videoGeo.scale

      if actualVideoScale != prevVideoScale {
        // Setting the window-scale property seems to result in a small hiccup during playback.
        // Not sure if this is an mpv limitation
        log.verbose("Updating mpv window-scale from videoSize \(windowGeo.videoSize), changing scale: \(prevVideoScale) → \(actualVideoScale)")

        let newVidGeo = info.videoGeo.clone(scale: actualVideoScale)
        windowController.applyVidGeo(newVidGeo)
        /// Allow `applyVidGeo` to call `mpv.setDouble(MPVProperty.windowScale, actualVideoScale)`
      } else {
        log.verbose("Skipping update to mpv window-scale: no change from prev (\(prevVideoScale))")
      }
    }
  }

  private func deriveVideoScale(from windowGeometry: PWGeometry) -> CGFloat? {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    
    let videoWidthScaled = windowGeometry.videoSize.width

    // This should take into account aspect override and/or crop already
    guard let videoWidthUnscaled = mpv.queryForVideoGeometry()?.videoSizeACR?.width else {
      return nil
    }

    let videoScale = (videoWidthScaled / videoWidthUnscaled).truncatedTo6()
    log.verbose("Derived video scale from vidGeo: \(videoScale)")
    return videoScale
  }

  func setVideoRotate(_ degree: Int) {
    mpv.queue.async { [self] in
      guard AppData.rotations.firstIndex(of: degree)! >= 0 else {
        Logger.log("Invalid value for videoRotate, ignoring: \(degree)", level: .error, subsystem: subsystem)
        return
      }

      Logger.log("Setting videoRotate to: \(degree)°", level: .verbose, subsystem: subsystem)
      mpv.setInt(MPVOption.Video.videoRotate, degree)
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
      let code = mpv.command(.videoAdd, args: [url.path], checkError: false)
      if code < 0 {
        Logger.log("Unsupported video: \(url.path)", level: .error, subsystem: self.subsystem)
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_audio")
        }
      }
    }
  }

  func loadExternalAudioFile(_ url: URL) {
    mpv.queue.async { [self] in
      let code = mpv.command(.audioAdd, args: [url.path], checkError: false)
      if code < 0 {
        Logger.log("Unsupported audio: \(url.path)", level: .error, subsystem: self.subsystem)
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_audio")
        }
      }
    }
  }

  func toggleSubVisibility() {
    mpv.queue.async { [self] in
      mpv.setFlag(MPVOption.Subtitles.subVisibility, !info.isSubVisible)
    }
  }

  func toggleSecondSubVisibility() {
    mpv.queue.async { [self] in
      mpv.setFlag(MPVOption.Subtitles.secondarySubVisibility, !info.isSecondSubVisible)
    }
  }

  func loadExternalSubFile(_ url: URL, delay: Bool = false) {
    mpv.queue.async { [self] in
      if let track = info.subTracks.first(where: { $0.externalFilename == url.path }) {
        mpv.command(.subReload, args: [String(track.id)], checkError: false)
        return
      }

      let code = mpv.command(.subAdd, args: [url.path], checkError: false)
      if code < 0 {
        Logger.log("Unsupported sub: \(url.path)", level: .error, subsystem: self.subsystem)
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
      let currentSubName = info.currentTrack(.sub)?.externalFilename
      for subTrack in info.subTracks {
        let code = mpv.command(.subReload, args: ["\(subTrack.id)"], checkError: false)
        if code < 0 {
          Logger.log("Failed reloading subtitles: error code \(code)", level: .error, subsystem: self.subsystem)
        }
      }
      reloadTrackInfo()
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

  func setSubDelay(_ delay: Double) {
    mpv.queue.async { [self] in
      mpv.setDouble(MPVOption.Subtitles.subDelay, delay)
    }
  }

  /// Adds all the media in `pathList` to the current playlist.
  /// This checks whether the currently playing item is in the list, so that it may end up in the middle of the playlist.
  /// Also note that each item in `pathList` may be either a file path or a
  /// network URl.
  func addFilesToPlaylist(pathList: [String]) {
    mpv.queue.async { [self] in
      var addedCurrentItem = false

      log.debug("Adding \(pathList.count) files to playlist")
      for path in pathList {
        if path == info.currentURL?.path {
          addedCurrentItem = true
        } else if addedCurrentItem {
          _addToPlaylist(path)
        } else {
          let count = mpv.getInt(MPVProperty.playlistCount)
          let current = mpv.getInt(MPVProperty.playlistPos)
          _addToPlaylist(path)
          let err = mpv.command(.playlistMove, args: ["\(count)", "\(current)"], checkError: false)
          if err != 0 {
            log.error("Error \(err) when adding files to playlist")
            if err == MPV_ERROR_COMMAND.rawValue {
              return
            }
          }
        }
      }
      _reloadPlaylist()
    }
  }

  func _addToPlaylist(_ path: String) {
    mpv.command(.loadfile, args: [path, "append"])
  }

  func addToPlaylist(_ path: String, silent: Bool = false) {
    mpv.queue.async { [self] in
      _addToPlaylist(path)
      _reloadPlaylist(silent: silent)
    }
  }

  private func _playlistMove(_ from: Int, to: Int) {
    mpv.command(.playlistMove, args: ["\(from)", "\(to)"])
  }

  func playlistMove(_ from: Int, to: Int) {
    mpv.queue.async { [self] in
      _playlistMove(from, to: to)
    }
    _reloadPlaylist()
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

  func addToPlaylist(urls: any Collection<URL>) {
    guard !urls.isEmpty else { return }
    mpv.queue.async { [self] in
      for url in urls {
        let path = url.isFileURL ? url.path : url.absoluteString
        _addToPlaylist(path)
      }

      // refresh playlist UI
      _reloadPlaylist()
      sendOSD(.addToPlaylist(urls.count))
    }
  }

  func addToPlaylist(paths: [String], at index: Int = -1) {
    mpv.queue.async { [self] in
      _reloadPlaylist(silent: true)
      for path in paths {
        _addToPlaylist(path)
      }
      if index <= info.playlist.count && index >= 0 {
        let previousCount = info.playlist.count
        for i in 0..<paths.count {
          _playlistMove(previousCount + i, to: index + i)
        }
      }
      _reloadPlaylist()
      saveState()  // save playlist URLs to prefs
    }
  }

  private func _playlistRemove(_ index: Int) {
    subsystem.verbose("Removing row \(index) from playlist")
    mpv.command(.playlistRemove, args: [index.description])
  }

  func playlistRemove(_ index: Int) {
    mpv.queue.async { [self] in
      subsystem.verbose("Will remove row \(index) from playlist")
      _playlistRemove(index)
      _reloadPlaylist()
    }
  }

  func playlistRemove(_ indexSet: IndexSet) {
    mpv.queue.async { [self] in
      subsystem.verbose("Will remove rows \(indexSet.map{$0}) from playlist")
      var count = 0
      for i in indexSet {
        _playlistRemove(i - count)
        count += 1
      }
      _reloadPlaylist()
    }
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
    Logger.log("Seeking to chapter \(pos)", level: .verbose, subsystem: subsystem)
    let chapters = info.chapters
    guard pos < chapters.count else {
      return nil
    }
    let chapter = chapters[pos]
    mpv.queue.async { [self] in
      mpv.command(.seek, args: ["\(chapter.time.second)", "absolute"])
      _resume()
    }
    return chapter
  }

  func setAudioEq(fromGains gains: [Double]) {
    let channelCount = mpv.getInt(MPVProperty.audioParamsChannelCount)
    let freqList = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    let filters = freqList.enumerated().map { (index, freq) -> MPVFilter in
      let string = [Int](0..<channelCount).map { "c\($0) f=\(freq) w=\(freq / 1.224744871) g=\(gains[index])" }.joined(separator: "|")
      return MPVFilter(name: "lavfi", label: "\(Constants.FilterLabel.audioEq)\(index)", paramString: "[anequalizer=\(string)]")
    }
    filters.forEach { _ = addAudioFilter($0) }
    info.audioEqFilters = filters
  }

  func removeAudioEqFilter() {
    info.audioEqFilters?.compactMap { $0 }.forEach { _ = removeAudioFilter($0) }
    info.audioEqFilters = nil
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
        dispatchPrecondition(condition: .onQueue(mpv.queue))
        setPlaybackInfoFilter(vf)
      }
    }

    return didSucceed
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
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    let result = mpv.removeFilter(MPVProperty.vf, index)
    Logger.log(result ? "Succeeded" : "Failed", subsystem: self.subsystem)
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
  func removeVideoFilter(_ filter: MPVFilter, verify: Bool = true) -> Bool {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    
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
    postNotification(.iinaVFChanged)
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
  func addAudioFilter(_ filter: MPVFilter) -> Bool { addAudioFilter(filter.stringFormat) }

  /// Add an audio filter given as a string.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  func addAudioFilter(_ filter: String) -> Bool {
    Logger.log("Adding audio filter \(filter)...", subsystem: subsystem)
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
    Logger.log("Removing audio filter \(filter)...", subsystem: subsystem)
    let result = mpv.removeFilter(MPVProperty.af, index)
    Logger.log(result ? "Succeeded" : "Failed", subsystem: self.subsystem)
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

  func setSubPos(_ pos: Int) {
    mpv.queue.async { [self] in
      Preference.set(pos, for: .subPos)
      mpv.setInt(MPVOption.Subtitles.subPos, pos)
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

  func savePlaybackPosition() {
    guard Preference.bool(for: .resumeLastPosition) else { return }

    // If the player is stopped then the file has been unloaded and it is too late to save the
    // watch later configuration.
    if isStopped {
      Logger.log("Player is stopped; too late to write water later config. This is ok if shutdown was initiated by mpv", level: .verbose, subsystem: subsystem)
    } else {
      Logger.log("Write watch later config", subsystem: subsystem)
      mpv.command(.writeWatchLaterConfig)
    }
    if let url = info.currentURL {
      Preference.set(url, for: .iinaLastPlayedFilePath)
      // Write to cache directly (rather than calling `refreshCachedVideoProgress`).
      // If user only closed the window but didn't quit the app, this can make sure playlist displays the correct progress.
      info.setCachedVideoDurationAndProgress(url.path, (duration: info.videoDuration?.second, progress: info.videoPosition?.second))
    }
    if let position = info.videoPosition?.second {
      Logger.log("Saving iinaLastPlayedFilePosition: \(position) sec", level: .verbose, subsystem: subsystem)
      Preference.set(position, for: .iinaLastPlayedFilePosition)
    } else {
      log.debug("Cannot save iinaLastPlayedFilePosition; no position found")
    }
  }

  func getMPVGeometry() -> MPVGeometryDef? {
    let geometry = mpv.getString(MPVOption.Window.geometry) ?? ""
    let parsed = MPVGeometryDef.parse(geometry)
    if let parsed = parsed {
      Logger.log("Got geometry from mpv: \(parsed)", level: .verbose, subsystem: subsystem)
    } else {
      Logger.log("Got nil for mpv geometry!", level: .verbose, subsystem: subsystem)
    }
    return parsed
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
        Logger.log("Triggered on_before_start_file hook, but no shuffle needed", level: .verbose, subsystem: subsystem)
        next()
        return
      }

      DispatchQueue.main.async { [self] in
        Logger.log("Running on_before_start_file hook: shuffling playlist", subsystem: subsystem)
        mpv.command(.playlistShuffle)
        /// will cancel this file load sequence (so `fileLoaded` will not be called), then will start loading item at index 0
        mpv.command(.playlistPlayIndex, args: ["0"])
        next()
      }
    }

    mpv.addHook(MPVHook.onBeforeStartFile, hook: MPVHookValue(withBlock: callback))
  }

  // MARK: - Listeners

  // Use cached video info (if it is available) to set the correct video geometry right away and without waiting for mpv.
  // This is optional but provides a better viewer experience
  private func preResizeVideo(forURL url: URL?) {
    if let videoInfo = info.currentVideosInfo.first(where: { $0.url == url }),
       let videoSize = videoInfo.videoSize {

      let newParams = info.videoGeo.clone(rawWidth: videoSize.0, rawHeight: videoSize.1)
      log.verbose("Calling applyVidGeo from preResizeVideo with \(newParams)")
      windowController.applyVidGeo(newParams)
    } else {
      // Either not a video file, or info not loaded. Null out video raw size for now (but keep prior settings)
      log.verbose("Nothing for preResizeVideo to do")
    }
  }

  func fileStarted(path: String, playlistPos: Int) {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    guard !isStopping, !isShuttingDown else { return }

    guard let mediaFromPath = MediaItem(path: path, playlistPos: playlistPos, loadStatus: .started) else {
      log.error("FileStarted: failed to create media from path \(path.pii.quoted)")
      return
    }
    if let existingMedia = info.currentMedia, existingMedia.url == mediaFromPath.url {
      guard existingMedia.loadStatus.rawValue < MediaItem.LoadStatus.started.rawValue else {
        log.warn("FileStarted: loadStatus is \(info.currentMedia?.loadStatus.description.quoted ?? "nil") (\(existingMedia.loadStatus.rawValue)), which is less than \(MediaItem.LoadStatus.started.rawValue)")
        return
      }
      // update existing entry
      existingMedia.playlistPos = mediaFromPath.playlistPos
      existingMedia.loadStatus = mediaFromPath.loadStatus
    } else {
      // New media, perhaps initiated by mpv
      log.verbose("FileStarted: media is new. PlaylistPos: \(mediaFromPath.playlistPos)")
      info.currentMedia = mediaFromPath
    }

    DispatchQueue.main.async { [self] in
      // Check this inside main DispatchQueue
      if isPlaylistVisible {
        // TableView whole table reload is very expensive. No need to reload entire playlist; just the two changed rows:
        windowController.playlistView.refreshNowPlayingIndex(setNewIndexTo: playlistPos)
      }
    }

    preResizeVideo(forURL: info.currentMedia?.url)

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

    if #available(macOS 10.13, *), RemoteCommandController.useSystemMediaControl {
      DispatchQueue.main.async {
        NowPlayingInfoManager.updateInfo(state: .playing, withTitle: true)
      }
    }

    // Auto load
    $backgroundQueueTicket.withLock { $0 += 1 }
    let shouldAutoLoadFiles = info.shouldAutoLoadFiles
    let currentTicket = backgroundQueueTicket
    PlayerCore.backgroundQueue.asyncAfter(deadline: DispatchTime.now() + AppData.autoLoadDelay) { [self] in
      // add files in same folder
      if shouldAutoLoadFiles {
        log.debug("Started auto load of files in current folder")
        self.autoLoadFilesInCurrentFolder(ticket: currentTicket)
      }
      // auto load matched subtitles
      if let matchedSubs = self.info.getMatchedSubs(path) {
        log.debug("Found \(matchedSubs.count) subs for current file")
        for sub in matchedSubs {
          guard currentTicket == self.backgroundQueueTicket else { return }
          self.loadExternalSubFile(sub)
        }
        // set sub to the first one
        guard currentTicket == self.backgroundQueueTicket, self.mpv.mpv != nil else { return }
        self.setTrack(1, forType: .sub)
      }
      self.autoSearchOnlineSub()
      log.debug("Done with auto load")
    }

    let url = info.currentURL
    let message = info.isNetworkResource ? url?.absoluteString : url?.lastPathComponent
    sendOSD(.fileStart(message ?? "-"))

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

  /** This function is called right after file loaded. Should load all meta info here. */
  func fileLoaded() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))

    // note: player may be "stopped" here
    guard !isStopping, !isShuttingDown else { return }

    let pause: Bool
    if let priorState = info.priorState {
      if Preference.bool(for: .alwaysPauseMediaWhenRestoringAtLaunch) {
        pause = true
      } else if let wasPaused = priorState.bool(for: .paused) {
        pause = wasPaused
      } else {
        pause = Preference.bool(for: .pauseWhenOpen)
      }
    } else {
      pause = Preference.bool(for: .pauseWhenOpen)
    }
    log.verbose("FileLoaded action=\(pause ? "PAUSE" : "PLAY") url=\(info.currentURL?.absoluteString.pii.quoted ?? "nil")")
    mpv.setFlag(MPVOption.PlaybackControl.pause, pause)

    let duration = mpv.getDouble(MPVProperty.duration)
    info.videoDuration = VideoTime(duration)
    if let filename = mpv.getString(MPVProperty.path) {
      info.setCachedVideoDuration(filename, duration)
    }
    let position = mpv.getDouble(MPVProperty.timePos)
    info.videoPosition = VideoTime(position)

    triedUsingExactSeekForCurrentFile = false
    info.isFileLoaded = true
    // Playback will move directly from stopped to loading when transitioning to the next file in
    // the playlist.
    isStopping = false
    info.haveDownloadedSub = false

    guard let currentMedia = info.currentMedia else {
      log.verbose("FileLoaded: currentMedia was nil")
      return
    }

    if !mpv.isStale() {
      if let loadStatus = info.currentMedia?.loadStatus, loadStatus.rawValue < MediaItem.LoadStatus.loaded.rawValue {
        info.currentMedia?.loadStatus = .loaded
      } else {
        log.warn("FileLoaded: loadStatus is \(info.currentMedia?.loadStatus.description.quoted ?? "nil")")
      }
    }

    // Kick off thumbnails load/gen - it can happen in background
    reloadThumbnails(forMedia: currentMedia)

    checkUnsyncedWindowOptions()
    // Call `trackListChanged` to load tracks
    trackListChanged()
    _reloadChapters()
    syncAbLoop()
    saveState()

    // main thread stuff
    DispatchQueue.main.async { [self] in
      isStopped = false
      refreshSyncUITimer()

      if #available(macOS 10.12.2, *) {
        touchBarSupport.setupTouchBarUI()
      }

      let appDelegate = AppDelegate.shared  // must dereference this only from main thread
      // add to history
      if let url = info.currentURL {
        let duration = info.videoDuration ?? .zero
        HistoryController.shared.queue.async {
          HistoryController.shared.add(url, duration: duration.second)

          if Preference.bool(for: .recordRecentFiles) && Preference.bool(for: .trackAllFilesInRecentOpenMenu) {
            appDelegate.noteNewRecentDocumentURL(url)
          }
        }
      }
    }

    postNotification(.iinaFileLoaded)
    events.emit(.fileLoaded, data: info.currentURL?.absoluteString ?? "")
  }

  func afChanged() {
    guard !isStopping, !isStopped, !isShuttingDown, !isShutdown else { return }
    _ = getAudioFilters()
    saveState()
    postNotification(.iinaAFChanged)
  }
  
  /// The mpv `file-loaded` event is emitted before everything associated with the file (such as filters) is completely done loading.
  /// This event should be called when everything is truly done.
  func fileIsCompletelyDoneLoading() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    guard !mpv.isStale() else { return }

    reloadTrackInfo()
    reloadSelectedTracks()

    // Make sure to call this because mpv does not always trigger it.
    guard let newVidGeo = mpv.queryForVideoGeometry() else { return }

    // Always send this to window controller. It should be smart enough to resize only when needed:
    log.verbose("Calling applyVidGeo from fileIsCompletelyDoneLoading")
    windowController.applyVidGeo(newVidGeo)

    log.verbose("File is completely done loading; setting justOpenedFile=N")
    /// Make sure to set this *after* calling `applyVidGeo` but *before* calling `refreshAlbumArtDisplay`
    if let loadStatus = info.currentMedia?.loadStatus, loadStatus.rawValue < MediaItem.LoadStatus.completelyLoaded.rawValue {
      info.currentMedia?.loadStatus = .completelyLoaded
      info.timeLastFileOpenFinished = Date().timeIntervalSince1970
    } else {
      log.warn("FileCompletelyLoaded: loadStatus is \(info.currentMedia?.loadStatus.description.quoted ?? "nil")")
    }

    // Update art & aspect *before* switching to/from music mode for more pleasant animation (but after updating state booleans)
    windowController.refreshAlbumArtDisplay()

    if let priorState = info.priorState {
      if priorState.string(for: .playPosition) != nil {
        /// Need to manually clear this, because mpv will try to seek to this time when any item in playlist is started
        log.verbose("Clearing mpv 'start' option now that restore is complete")
        mpv.setString(MPVOption.PlaybackControl.start, AppData.mpvArgNone)
      }
      info.priorState = nil
      info.isRestoring = false
      log.debug("Done with restore")
      return
    }

    let currentMediaAudioStatus = info.currentMediaAudioStatus

    DispatchQueue.main.async { [self] in

      // if need to switch to music mode
      if Preference.bool(for: .autoSwitchToMusicMode) {
        if overrideAutoMusicMode {
          log.verbose("Skipping music mode auto-switch because overrideAutoMusicMode is true")
        } else if currentMediaAudioStatus == .isAudio && !isInMiniPlayer && !windowController.isFullScreen {
          log.debug("Current media is audio: auto-switching to music mode")
          enterMusicMode(automatically: true)
        } else if currentMediaAudioStatus == .notAudio && isInMiniPlayer {
          log.debug("Current media is not audio: auto-switching to normal window")
          exitMusicMode(automatically: true)
        }
      }
    }
  }

  func reloadAID() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    guard !isStopping, !isStopped, !isShuttingDown, !isShutdown else { return }
    let aid = Int(mpv.getInt(MPVOption.TrackSelection.aid))
    guard aid != info.aid else { return }
    info.aid = aid

    log.verbose("Audio track changed to: \(aid)")
    syncUI(.volume)
    postNotification(.iinaAIDChanged)
    sendOSD(.track(info.currentTrack(.audio) ?? .noneAudioTrack))
  }

  func mediaTitleChanged() {
    guard !isStopping, !isStopped, !isShuttingDown, !isShutdown else { return }
    postNotification(.iinaMediaTitleChanged)
  }

  func reloadQuickSettingsView() {
    DispatchQueue.main.async { [self] in
      guard !isShuttingDown, !isShutdown else { return }

      // Easiest place to put this - need to call it when setting equalizers
      videoView.displayActive(temporary: info.isPaused)
      windowController.quickSettingView.reload()
    }
  }

  func seeking() {
    log.trace("Seeking")
    DispatchQueue.main.async { [self] in
      info.isSeeking = true
      // When playback is paused the display link may be shutdown in order to not waste energy.
      // It must be running when seeking to avoid slowdowns caused by mpv waiting for IINA to call
      // mpv_render_report_swap.
      videoView.displayActive()
    }

    sendOSD(.seek(videoPosition: info.videoPosition, videoDuration: info.videoDuration))
  }

  func playbackRestarted() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    log.debug("Playback restarted")

    info.isIdle = false
    info.isSeeking = false

    DispatchQueue.main.async { [self] in
      windowController.updateUI()

      // When playback is paused the display link may be shutdown in order to not waste energy.
      // The display link will be restarted while seeking. If playback is paused shut it down
      // again.
      if info.isPaused {
        videoView.displayIdle()
      }

      if #available(macOS 10.13, *), RemoteCommandController.useSystemMediaControl {
        NowPlayingInfoManager.updateInfo()
      }
    }

    saveState()
  }

  @available(macOS 10.15, *)
  func refreshEdrMode() {
    guard windowController.loaded else { return }
    DispatchQueue.main.async { [self] in
      // No need to refresh if playback is being stopped. Must not attempt to refresh if mpv is
      // terminating as accessing mpv once shutdown has been initiated can trigger a crash.
      guard !isStopping, !isStopped, !isShuttingDown, !isShutdown else { return }
      videoView.refreshEdrMode()
    }
  }

  func reloadSID() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    guard !isStopping, !isStopped, !isShuttingDown, !isShutdown else { return }
    let sid = Int(mpv.getInt(MPVOption.TrackSelection.sid))
    guard sid != info.sid else { return }
    info.sid = sid

    log.verbose("SID changed to \(sid)")
    postNotification(.iinaSIDChanged)
    sendOSD(.track(info.currentTrack(.sub) ?? .noneSubTrack))
  }

  func reloadSecondSID() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    guard !isStopping, !isStopped, !isShuttingDown, !isShutdown else { return }
    let ssid = Int(mpv.getInt(MPVOption.Subtitles.secondarySid))
    guard ssid != info.secondSid else { return }
    info.secondSid = ssid

    log.verbose("SSID changed to \(ssid)")
    postNotification(.iinaSIDChanged)
  }

  func trackListChanged() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    // No need to process track list changes if playback is being stopped. Must not process track
    // list changes if mpv is terminating as accessing mpv once shutdown has been initiated can
    // trigger a crash.
    guard !isStopping, !isStopped, !isShuttingDown, !isShutdown else { return }
    log.debug("Track list changed")
    reloadTrackInfo()
    reloadSelectedTracks()
    saveState()
    log.verbose("Posting iinaTracklistChanged, vid=\(optString(info.vid)), aid=\(optString(info.aid)), sid=\(optString(info.sid))")
    postNotification(.iinaTracklistChanged)
  }

  private func optString(_ num: Int?) -> String {
    if let num = num {
      return String(num)
    }
    return "nil"
  }

  func vfChanged() {
    guard !isStopping, !isStopped, !isShuttingDown, !isShutdown else { return }
    _ = getVideoFilters()
    saveState()
    postNotification(.iinaVFChanged)

    /// The first filter msg after starting a file means that the file is officially done loading.
    /// (Put this here instead of at `playback-restart` because it occurs later & will avoid triggering display of OSDs)
    fileIsCompletelyDoneLoading()
  }

  func reloadVID() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    guard !isStopping, !isStopped, !isShuttingDown, !isShutdown else { return }
    let vid = Int(mpv.getInt(MPVOption.TrackSelection.vid))
    guard vid != info.vid else { return }
    info.vid = vid

    /// Do this first, before `applyVideoVisibility`, for a nicer animation`
    windowController.refreshAlbumArtDisplay()

    DispatchQueue.main.async{ [self] in
      guard info.isFileLoaded else {
        log.verbose("After video track changed to: \(vid): file is not loaded!")
        return
      }
      windowController.forceDraw()

      if isMiniPlayerWaitingToShowVideo {
        isMiniPlayerWaitingToShowVideo = false
        windowController.miniPlayer.showVideo()
      }
    }
    postNotification(.iinaVIDChanged)
    if isInMiniPlayer && (isMiniPlayerWaitingToShowVideo || !windowController.miniPlayer.isVideoVisible) {
      return
    }
    sendOSD(.track(info.currentTrack(.video) ?? .noneVideoTrack))
  }

  ///  `showMiniPlayerVideo` is only used if `enable` is true
  func setVideoTrackEnabled(_ enable: Bool, showMiniPlayerVideo: Bool = false) {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

    if enable {
      // Go to first video track found (unless one is already selected):
      if !info.isVideoTrackSelected {
        if showMiniPlayerVideo {
          isMiniPlayerWaitingToShowVideo = true
        }
        mpv.queue.async { [self] in
          log.verbose("Sending mpv request to cycle video track")
          mpv.command(.cycle, args: ["video"])
        }
      } else {
        if showMiniPlayerVideo {
          // Don't wait; execute now
          windowController.miniPlayer.showVideo()
        }
      }
    } else {
      // Change video track to None
      log.verbose("Sending request to mpv: set video track to 0")
      setTrack(0, forType: .video)
    }
  }

  private func autoSearchOnlineSub() {
    if Preference.bool(for: .autoSearchOnlineSub) &&
      !info.isNetworkResource && info.subTracks.isEmpty &&
      (info.videoDuration?.second ?? 0.0) >= Preference.double(for: .autoSearchThreshold) * 60 {
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

  /**
   Checks unsynchronized window options, such as those set via mpv before window loaded.

   These options currently include fullscreen and ontop.
   */
  private func checkUnsyncedWindowOptions() {
    guard windowController.loaded else { return }

    let mpvFS = mpv.getFlag(MPVOption.Window.fullscreen)
    let iinaFS = windowController.isFullScreen
    log.verbose("IINA FullScreen state: \(iinaFS.yn), mpv: \(mpvFS.yn)")
    if mpvFS != iinaFS {
      DispatchQueue.main.async { [self] in
        if mpvFS {
          windowController.enterFullScreen()
        } else {
          windowController.exitFullScreen(legacy: windowController.currentLayout.isLegacyFullScreen)
        }
      }
    }

    let ontop = mpv.getFlag(MPVOption.Window.ontop)
    if ontop != windowController.isOnTop {
      log.verbose("IINA OnTop state (\(windowController.isOnTop.yn)) does not match mpv (\(ontop.yn)). Will change to match mpv state")
      DispatchQueue.main.async {
        self.windowController.setWindowFloatingOnTop(ontop, updateOnTopStatus: false)
      }
    }
  }

  // MARK: - Sync with UI in PlayerWindow

  var lastTimerSummary = ""  // for reducing log volume
  /// Call this when `syncUITimer` may need to be started, stopped, or needs its interval changed. It will figure out the correct action.
  /// Just need to make sure that any state variables (e.g., `info.isPaused`, `isInMiniPlayer`, the vars checked by `windowController.isUITimerNeeded()`,
  /// etc.) are set *before* calling this method, not after, so that it makes the correct decisions.
  func refreshSyncUITimer(logMsg: String = "") {
    // Check if timer should start/restart
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

    let useTimer: Bool
    if isStopping || isStopped || isShuttingDown || isShutdown {
      useTimer = false
    } else if info.isPaused {
      // Follow energy efficiency best practices and ensure IINA is absolutely idle when the
      // video is paused to avoid wasting energy with needless processing. If paused shutdown
      // the timer that synchronizes the UI and the high priority display link thread.
      useTimer = false
    } else if needsTouchBar || isInMiniPlayer {
      // Follow energy efficiency best practices and stop the timer that updates the OSC while it is
      // hidden. However the timer can't be stopped if the mini player is being used as it always
      // displays the the OSC or the timer is also updating the information being displayed in the
      // touch bar. Does this host have a touch bar? Is the touch bar configured to show app controls?
      // Is the touch bar awake? Is the host being operated in closed clamshell mode? This is the kind
      // of information needed to avoid running the timer and updating controls that are not visible.
      // Unfortunately in the documentation for NSTouchBar Apple indicates "There’s no need, and no
      // API, for your app to know whether or not there’s a Touch Bar available". So this code keys
      // off whether AppKit has requested that a NSTouchBar object be created. This avoids running the
      // timer on Macs that do not have a touch bar. It also may avoid running the timer when a
      // MacBook with a touch bar is being operated in closed clameshell mode.
      useTimer = true
    } else if info.isNetworkResource {
      // May need to show, hide, or update buffering indicator at any time
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
        let logMsg = logMsg.isEmpty ? logMsg : "\(logMsg)- "
        log.verbose("\(logMsg)SyncUITimer \(summary), paused:\(info.isPaused.yn) net:\(info.isNetworkResource.yn) mini:\(isInMiniPlayer.yn) touchBar:\(needsTouchBar.yn) stop:\(isStopping.yn)\(isStopped.yn) quit:\(isShuttingDown.yn)\(isShutdown.yn)")
      }
    }

    guard useTimer && (timerRestartNeeded || !wasTimerRunning) else {
      return
    }

    // Timer will start

    if !wasTimerRunning {
      // Do not wait for first redraw
      windowController.updateUI()
    }

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

    DispatchQueue.main.async { [self] in
      windowController.animationPipeline.submitZeroDuration { [self] in
        guard syncUITicket == syncUITicketCounter else {
          return
        }
        windowController.updateUI()
      }
    }
  }

  private var lastSaveTime = Date().timeIntervalSince1970

  func updatePlaybackTimeInfo() {
    guard didInitVideo, !isStopping, !isShuttingDown else {
      log.verbose("syncUITime: not syncing")
      return
    }

    let isNetworkStream = info.isNetworkResource
    if isNetworkStream {
      info.videoDuration = VideoTime(mpv.getDouble(MPVProperty.duration))
    }
    // When the end of a video file is reached mpv does not update the value of the property
    // time-pos, leaving it reflecting the position of the last frame of the video. This is
    // especially noticeable if the onscreen controller time labels are configured to show
    // milliseconds. Adjust the position if the end of the file has been reached.
    let eofReached = mpv.getFlag(MPVProperty.eofReached)
    if eofReached, let duration = info.videoDuration {
      info.videoPosition = duration
    } else {
      info.videoPosition = VideoTime(mpv.getDouble(MPVProperty.timePos))
    }
    info.constrainVideoPosition()
    if isNetworkStream {
      // Update cache info
      info.pausedForCache = mpv.getFlag(MPVProperty.pausedForCache)
      info.cacheUsed = ((mpv.getNode(MPVProperty.demuxerCacheState) as? [String: Any])?["fw-bytes"] as? Int) ?? 0
      info.cacheSpeed = mpv.getInt(MPVProperty.cacheSpeed)
      info.cacheTime = mpv.getInt(MPVProperty.demuxerCacheTime)
      info.bufferingState = mpv.getInt(MPVProperty.cacheBufferingState)
    }

    // Ensure user can resume playback by periodically saving
    let now = Date().timeIntervalSince1970
    let secSinceLastSave = now - lastSaveTime
    if secSinceLastSave >= AppData.playTimeSaveStateIntervalSec {
      if log.isTraceEnabled {
        log.trace("Another \(AppData.playTimeSaveStateIntervalSec)s has passed: saving player state")
      }
      saveState()
      lastSaveTime = now
    }
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
    log.verbose("Syncing UI \(option)")

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
    if !windowController.loaded || !Preference.bool(for: .enableOSD) || isUsingMpvOSD || info.isRestoring || isInInteractiveMode {
      return false
    }
    if isInMiniPlayer && !Preference.bool(for: .enableOSDInMusicMode) {
      return false
    }

    return true
  }

  func sendOSD(_ msg: OSDMessage, autoHide: Bool = true, forcedTimeout: Double? = nil,
               accessoryViewController: NSViewController? = nil, external: Bool = false) {
    windowController.displayOSD(msg, autoHide: autoHide, forcedTimeout: forcedTimeout, accessoryViewController: accessoryViewController, isExternal: external)
  }

  func hideOSD() {
    DispatchQueue.main.async {
      self.windowController.hideOSD()
    }
  }

  func errorOpeningFileAndClosePlayerWindow(url: URL? = nil) {
    DispatchQueue.main.async { [self] in
      if let path = url?.path {
        Utility.showAlert("error_open_name", arguments: [path.quoted])
      } else {
        Utility.showAlert("error_open")
      }

      self.isStopped = true
      self.windowController.close()
    }
  }

  func closeWindow() {
    DispatchQueue.main.async { [self] in
      isStopped = true
      windowController.close()
    }
  }

  func reloadThumbnails(forMedia currentMedia: MediaItem?) {
    guard let currentMedia else {
      log.debug("Cannot generate thumbnails: no file active")
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + AppData.thumbnailRegenerationDelay) { [self] in
      guard !info.isNetworkResource, let url = info.currentURL, let mpvMD5 = info.mpvMd5 else {
        log.debug("Thumbnails reload stopped because cannot get file path")
        clearExistingThumbnails(for: currentMedia)
        return
      }
      guard Preference.bool(for: .enableThumbnailPreview) else {
        log.verbose("Thumbnails reload stopped because thumbnails are disabled by user")
        clearExistingThumbnails(for: currentMedia)
        return
      }
      if !Preference.bool(for: .enableThumbnailForRemoteFiles) && info.isMediaOnRemoteDrive {
        log.debug("Thumbnails reload stopped because file is on a mounted remote drive")
        clearExistingThumbnails(for: currentMedia)
        return
      }
      if isInMiniPlayer && !Preference.bool(for: .enableThumbnailForMusicMode) {
        log.verbose("Thumbnails reload stopped because user has not enabled for music mode")
        clearExistingThumbnails(for: currentMedia)
        return
      }

      var ticket: Int = 0
      $thumbnailReloadTicketCounter.withLock {
        $0 += 1
        ticket = $0
      }

      // Run the following in the background at lower priority, so the UI is not slowed down
      PlayerCore.thumbnailQueue.asyncAfter(deadline: .now() + 0.5) { [self] in
        guard ticket == thumbnailReloadTicketCounter else { return }
        guard !isStopping, !isStopped, !isShuttingDown else { return }
        log.debug("Reloading thumbnails (tkt \(ticket))")

        // Generate thumbnails using video's original dimensions, before aspect ratio correction.
        // We will adjust aspect ratio & rotation when we display the thumbnail, similar to how mpv works.
        var videoGeo = info.videoGeo
        if !videoGeo.hasValidSize {
          // Fall back to querying mpv:
          guard let videoGeoNew = mpv.queryForVideoGeometry() else {
            log.debug("Cannot generate thumbnails: could not get video params from mpv")
            return
          }
          videoGeo = videoGeoNew
        }

        guard let videoSizeRaw = videoGeo.videoSizeRaw else {
          log.debug("Cannot generate thumbnails: video height and/or width is zero")
          clearExistingThumbnails(for: currentMedia)
          return
        }

        let thumbnailWidth = SingleMediaThumbnailsLoader.determineWidthOfThumbnail(from: videoSizeRaw, log: log)

        if let oldThumbs = currentMedia.thumbnails {
          if !oldThumbs.isCancelled, oldThumbs.mediaFilePath == url.path,
             thumbnailWidth == oldThumbs.thumbnailWidth,
             videoGeo.totalRotation == oldThumbs.rotationDegrees {
            log.debug("Already loaded \(oldThumbs.thumbnails.count) thumbnails (\(oldThumbs.thumbnailsProgress * 100.0)%) for file (\(thumbnailWidth)px, \(videoGeo.totalRotation)°). Nothing to do")
            return
          } else {
            clearExistingThumbnails(for: currentMedia)
          }
        }

        let newMediaThumbnailLoader = SingleMediaThumbnailsLoader(self, mediaFilePath: url.path, mediaFilePathMD5: mpvMD5,
                                                                  thumbnailWidth: thumbnailWidth, rotationDegrees: videoGeo.totalRotation)
        currentMedia.thumbnails = newMediaThumbnailLoader
        newMediaThumbnailLoader.loadThumbnails()
      }
    }
  }

  private func clearExistingThumbnails(for currentMedia: MediaItem) {
    if let oldThumbnailSet = currentMedia.thumbnails {
      oldThumbnailSet.isCancelled = true
      currentMedia.thumbnails = nil
    }
    if #available(macOS 10.12.2, *) {
      self.touchBarSupport.touchBarPlaySlider?.resetCachedThumbnails()
    }
  }

  @available(macOS 10.12.2, *)
  func makeTouchBar() -> NSTouchBar {
    Logger.log("Activating Touch Bar", subsystem: subsystem)
    needsTouchBar = true
    // The timer that synchronizes the UI is shutdown to conserve energy when the OSC is hidden.
    // However the timer can't be stopped if it is needed to update the information being displayed
    // in the touch bar. If currently playing make sure the timer is running.
    refreshSyncUITimer()
    return touchBarSupport.touchBar
  }

  func refreshTouchBarSlider() {
    if #available(macOS 10.12.2, *) {
      DispatchQueue.main.async {
        self.touchBarSupport.touchBarPlaySlider?.needsDisplay = true
      }
    }
  }

  // MARK: - Getting info

  func reloadTrackInfo() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    log.trace("Reloading tracklist from mpv")
    var audioTracks: [MPVTrack] = []
    var videoTracks: [MPVTrack] = []
    var subTracks: [MPVTrack] = []

    let trackCount = mpv.getInt(MPVProperty.trackListCount)
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
    log.debug("Reloaded tracklist from mpv (\(trackCount) tracks)")
  }

  private func reloadSelectedTracks() {
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    log.verbose("Reloading selected tracks")
    reloadAID()
    reloadVID()
    reloadSID()
    reloadSecondSID()

    saveState()
  }

  private func _reloadPlaylist(silent: Bool = false) {
    log.verbose("Removing all items from playlist")
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    var newPlaylist: [MPVPlaylistItem] = []
    let playlistCount = mpv.getInt(MPVProperty.playlistCount)
    log.verbose("Adding \(playlistCount) items to playlist")
    for index in 0..<playlistCount {
      let playlistItem = MPVPlaylistItem(filename: mpv.getString(MPVProperty.playlistNFilename(index))!,
                                         title: mpv.getString(MPVProperty.playlistNTitle(index)))
      newPlaylist.append(playlistItem)
    }
    info.playlist = newPlaylist
    let mpvPlaylistPos = mpv.getInt(MPVProperty.playlistPos)
    info.currentMedia?.playlistPos = mpvPlaylistPos
    if isPlaylistVisible {
      DispatchQueue.main.async { [self] in
        windowController.playlistView.refreshNowPlayingIndex(setNewIndexTo: mpvPlaylistPos)
      }
    }
    log.verbose("After reloading playlist: playlistPos is: \(mpvPlaylistPos)")
    saveState()  // save playlist URLs to prefs
    if !silent {
      postNotification(.iinaPlaylistChanged)
    }
  }

  func reloadPlaylist() {
    mpv.queue.async { [self] in
      _reloadPlaylist()
      saveState()  // save playlist URLs to prefs
    }
  }

  func _reloadChapters() {
    Logger.log("Reloading chapter list", level: .verbose, subsystem: subsystem)
    dispatchPrecondition(condition: .onQueue(mpv.queue))
    var chapters: [MPVChapter] = []
    let chapterCount = mpv.getInt(MPVProperty.chapterListCount)
    for index in 0..<chapterCount {
      let chapter = MPVChapter(title:     mpv.getString(MPVProperty.chapterListNTitle(index)),
                               startTime: mpv.getDouble(MPVProperty.chapterListNTime(index)),
                               index:     index)
      chapters.append(chapter)
    }
    // Instead of modifying existing list, overwrite reference to prev list.
    // This will avoid concurrent modification crashes
    info.chapters = chapters

    syncUI(.chapterList)
  }

  func reloadChapters() {
    mpv.queue.async { [self] in
      _reloadChapters()
    }
    syncUI(.chapterList)
  }

  // MARK: - Notifications

  func postNotification(_ name: Notification.Name) {
    log.debug("Posting notification: \(name.rawValue)")
    NotificationCenter.default.post(Notification(name: name, object: self))
  }

  // MARK: - Utils

  func getMediaTitle(withExtension: Bool = true) -> String {
    let mediaTitle = mpv.getString(MPVProperty.mediaTitle)
    let mediaPath = withExtension ? info.currentURL?.path : info.currentURL?.deletingPathExtension().path
    return mediaTitle ?? mediaPath ?? ""
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

  func setPlaybackInfoFilter(_ filter: MPVFilter) {
    dispatchPrecondition(condition: .onQueue(mpv.queue))

    switch filter.label {
    case Constants.FilterLabel.crop:
      // CROP
      if let cropLabel = deriveCropLabel(from: filter) {
        updateSelectedCrop(to: cropLabel)  // Known aspect-based crop
      } else {
        // Cannot parse IINA crop filter? Remove crop
        log.error("Could not determine crop from filter \(filter.label?.debugDescription.quoted ?? "nil"). Removing filter")
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
    dispatchPrecondition(condition: .onQueue(mpv.queue))

    let videoFilters = getVideoFilters()
    postNotification(.iinaVFChanged)
    let audioFilters = getAudioFilters()
    postNotification(.iinaAFChanged)
    Logger.log("Total filters from mpv: \(videoFilters.count) vf, \(audioFilters.count) af", level: .verbose, subsystem: subsystem)
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
      Logger.log("Got mpv vf, name: \(filter.name.quoted), label: \(filter.label?.quoted ?? "nil"), params: \(filter.params ?? [:])",
                 level: .verbose, subsystem: subsystem)
      if filter.label == Constants.FilterLabel.crop {
        foundCropFilter = true
      }
      setPlaybackInfoFilter(filter)
    }
    if !foundCropFilter, info.videoGeo.hasCrop {
      log.debug("No crop filter found in mpv video filters. Removing crop")
      updateSelectedCrop(to: AppData.noneCropIdentifier)
    }
    return videoFilters
  }

  /// `af`: gets up-to-date list of audio filters AND updates associated state in the process
  func getAudioFilters() -> [MPVFilter] {
    // Clear cached filters first:
    info.audioEqFilters = nil
    let audioFilters = mpv.getFilters(MPVProperty.af)
    for filter in audioFilters {
      Logger.log("Got mpv af, name: \(filter.name.quoted), label: \(filter.label?.quoted ?? "nil"), params: \(filter.params ?? [:])",
                 level: .verbose, subsystem: subsystem)
      guard let label = filter.label else { continue }
      if label.hasPrefix(Constants.FilterLabel.audioEq) {
        if info.audioEqFilters == nil {
          info.audioEqFilters = Array(repeating: nil, count: 10)
        }
        if let index = Int(String(label.last!)) {
          info.audioEqFilters![index] = filter
        }
      }
    }
    return audioFilters
  }

  /**
   Get video duration, playback progress, and metadata, then save it to info.
   It may take some time to run this method, so it should be used in background.
   */
  func refreshCachedVideoInfo(forVideoPath path: String) {
    guard let dict = FFmpegController.probeVideoInfo(forFile: path) else { return }
    let progress = Utility.playbackProgressFromWatchLater(path.md5)
    self.info.setCachedVideoDurationAndProgress(path, (
      duration: dict["@iina_duration"] as? Double,
      progress: progress?.second
    ))
    var result: (title: String?, album: String?, artist: String?)
    dict.forEach { (k, v) in
      guard let key = k as? String else { return }
      switch key.lowercased() {
      case "title":
        result.title = v as? String
      case "album":
        result.album = v as? String
      case "artist":
        result.artist = v as? String
      default:
        break
      }
    }
    self.info.setCachedMetadata(path, result)
  }

  static func checkStatusForSleep() {
    for player in playing {
      if player.info.isPlaying {
        SleepPreventer.preventSleep()
        return
      }
    }
    SleepPreventer.allowSleep()
  }
}

@available (macOS 10.13, *)
class NowPlayingInfoManager {

  /// Update the information shown by macOS in `Now Playing`.
  ///
  /// The macOS [Control Center](https://support.apple.com/guide/mac-help/quickly-change-settings-mchl50f94f8f/mac)
  /// contains a `Now Playing` module. This module can also be configured to be directly accessible from the menu bar.
  /// `Now Playing` displays the title of the media currently  playing and other information about the state of playback. It also can be
  /// used to control playback. IINA is fully integrated with the macOS `Now Playing` module.
  ///
  /// - Note: See [Becoming a Now Playable App](https://developer.apple.com/documentation/mediaplayer/becoming_a_now_playable_app)
  ///         and [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
  ///         for more information.
  ///
  /// - Important: This method **must** be run on the main thread because it references `PlayerCore.lastActive`.
  static func updateInfo(state: MPNowPlayingPlaybackState? = nil, withTitle: Bool = false) {
    let center = MPNowPlayingInfoCenter.default()
    var info = center.nowPlayingInfo ?? [String: Any]()

    let activePlayer = PlayerCore.lastActive
    guard !activePlayer.isStopping, !activePlayer.isStopped, !activePlayer.isShuttingDown, !activePlayer.isShutdown else { return }

    if withTitle {
      if activePlayer.info.currentMediaAudioStatus == .isAudio {
        info[MPMediaItemPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        let (title, album, artist) = activePlayer.getMusicMetadata()
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyAlbumTitle] = album
        info[MPMediaItemPropertyArtist] = artist
      } else {
        info[MPMediaItemPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        info[MPMediaItemPropertyTitle] = activePlayer.getMediaTitle(withExtension: false)
      }
    }

    let duration = activePlayer.info.videoDuration?.second ?? 0
    let time = activePlayer.info.videoPosition?.second ?? 0
    let speed = activePlayer.info.playSpeed

    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
    info[MPNowPlayingInfoPropertyPlaybackRate] = speed
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1

    center.nowPlayingInfo = info

    if state != nil {
      center.playbackState = state!
    }
  }
}
