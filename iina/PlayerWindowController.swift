//
//  PlayerWindowController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PlaybackControlButtonsView: ClickThroughView {
  private var playerWindowController: PlayerWindowController? {
    return window?.windowController as? PlayerWindowController
  }

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    playerWindowController?.playButtonAction(self)
  }
}

// Use single instance of each for efficiency
fileprivate let playImage = NSImage(named: "play")!
fileprivate let pauseImage = NSImage(named: "pause")!
fileprivate let replayImage: NSImage = {
  if #available(macOS 11.0, *) {
    if let img = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Restart from beginning") {
      return img
    }
  }
  return NSImage(named: "arrow.counterclockwise")!
}()


class PlayerWindowController: IINAWindowController, NSWindowDelegate {
  unowned var player: PlayerCore
  unowned var log: Logger.Subsystem {
    return player.log
  }

  override var windowNibName: NSNib.Name {
    return NSNib.Name("PlayerWindowController")
  }

  @objc var videoView: VideoView {
    return player.videoView
  }

  @objc let monospacedFont: NSFont = {
    let fontSize = NSFont.systemFontSize(for: .small)
    return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
  }()

  /**
   `NSWindow` doesn't provide title bar height directly, but we can derive it by asking `NSWindow` for
   the dimensions of a prototypical window with titlebar, then subtracting the height of its `contentView`.
   Note that we can't use this trick to get it from our window instance directly, because our window has the
   `fullSizeContentView` style and so its `frameRect` does not include any extra space for its title bar.
   */
  static let standardTitleBarHeight: CGFloat = {
    // Probably doesn't matter what dimensions we pick for the dummy contentRect, but to be safe let's make them nonzero.
    let dummyContentRect = NSRect(x: 0, y: 0, width: 10, height: 10)
    let dummyFrameRect = NSWindow.frameRect(forContentRect: dummyContentRect, styleMask: .titled)
    let titleBarHeight = dummyFrameRect.height - dummyContentRect.height
    return titleBarHeight
  }()

  static let reducedTitleBarHeight: CGFloat = {
    if let heightOfCloseButton = NSWindow.standardWindowButton(.closeButton, for: .titled)?.frame.height {
      // add 2 because button's bounds seems to be a bit larger than its visible size
      return standardTitleBarHeight - ((standardTitleBarHeight - heightOfCloseButton) / 2 + 2)
    }
    Logger.log("reducedTitleBarHeight may be incorrect (could not get close button)", level: .error)
    return standardTitleBarHeight
  }()

  // MARK: - Objects, Views

  var bestScreen: NSScreen {
    window?.screen ?? NSScreen.main!
  }

  /** For blacking out other screens. */
  var cachedScreens: [UInt32: ScreenMeta] = PlayerWindowController.buildScreenMap()
  var blackWindows: [NSWindow] = []

  /** The quick setting sidebar (video, audio, subtitles). */
  let quickSettingView = QuickSettingViewController()

  /** The playlist and chapter sidebar. */
  let playlistView = PlaylistViewController()

  /// The music player panel.
  ///
  /// This is only shown while in music mode, and will be a subview of `bottomBarView`. It contains a "mini" OSC, and if configured, the
  /// playlist.
  var miniPlayer: MiniPlayerViewController!

  /** The control view for interactive mode. */
  var cropSettingsView: CropBoxViewController?

  // For legacy windowed mode
  var customTitleBar: CustomTitleBarViewController? = nil

  // For Rotate gesture:
  let rotationHandler = RotationGestureHandler()

  // For Pinch To Magnify gesture:
  let magnificationHandler = MagnificationGestureHandler()

  let animationPipeline = IINAAnimation.Pipeline()

  /// Need to store this for use by `showWindow` when it is called asynchronously
  var pendingVideoGeoUpdateTasks: [IINAAnimation.Task] = []

  // MARK: - Status variables

  var isAnimating: Bool {
    return animationPipeline.isRunning
  }

  // While true, disable window geometry listeners so they don't overwrite cache with intermediate data
  var isAnimatingLayoutTransition: Bool = false {
    didSet {
      log.verbose("Updated isAnimatingLayoutTransition ≔ \(isAnimatingLayoutTransition.yesno)")
    }
  }

  var isOnTop: Bool = false

  // TODO: replace these vars with window state var: .notYetLoaded, .loadedButClosed, .willOpen, .openVisible, .openDragging,
  // .openMagnifying, .openLiveResizingWidth, .openLiveResizingHeight, .openHidden, .openMiniturized, .openInFullScreen, .closing
  var loaded = false  // TODO: -> .isAtLeast(.loadedButClosed)
  var isInitialSizeDone = false // TODO: -> willOpen
  var isWindowMiniturized = false
  /// Set only for PiP
  var isWindowHidden = false
  var isDragging: Bool = false
  var isLiveResizingWidth: Bool? = nil
  var isMagnifying = false

  /// True if window is either visible, hidden, or minimized. False if window is closed.
  var isOpen: Bool {
    assert(DispatchQueue.isExecutingIn(.main))

    if !self.loaded {
      return false
    }
    guard let window = self.window else { return false }
    /// Also check if hidden due to PIP, or minimized.
    /// NOTE: `window.isVisible` returns `false` if the window is ordered out, which we do sometimes,
    /// as well as in the minimized or hidden states.
    /// Check against our internally tracked window state lists also:
    let savedStateName = window.savedStateName
    let isVisible = window.isVisible || Preference.UIState.windowsOpen.contains(savedStateName)
    let isMinimized = Preference.UIState.windowsMinimized.contains(savedStateName)
    return isVisible || isMinimized
  }

  var isClosing: Bool {
    return player.state.isAtLeast(.stopping)
  }

  var isWindowMiniaturizedDueToPip = false
  var isWindowPipDueToInactiveSpace = false

  var denyNextWindowResize = false
  var modeToSetAfterExitingFullScreen: PlayerWindowMode? = nil

  var isPausedDueToInactive: Bool = false
  var isPausedDueToMiniaturization: Bool = false
  var isPausedPriorToInteractiveMode: Bool = false

  var floatingOSCCenterRatioH = CGFloat(Preference.float(for: .controlBarPositionHorizontal))
  var floatingOSCOriginRatioV = CGFloat(Preference.float(for: .controlBarPositionVertical))

  // - Mouse

  var mousePosRelatedToWindow: CGPoint?

  // might use another obj to handle slider?
  var isMouseInWindow: Bool = false

  // - Left and right arrow buttons

  /** The maximum pressure recorded when clicking on the arrow buttons. */
  var maxPressure: Int = 0

  /** The value of speedValueIndex before Force Touch. */
  var oldSpeedValueIndex: Int = AppData.availableSpeedValues.count / 2

  /** When the arrow buttons were last clicked. */
  var lastClick = Date()

  /// Responder chain is a mess. Use this to prevent duplicate event processing
  var lastMouseDownEventID: Int = -1
  var lastMouseUpEventID: Int = -1
  var lastRightMouseDownEventID: Int = -1
  var lastRightMouseUpEventID: Int = -1

  /** For force touch action */
  var isCurrentPressInSecondStage = false

  /// - Sidebars: See file `Sidebars.swift`

  /// For resize of `playlist` tab group
  var leadingSidebarIsResizing = false
  var trailingSidebarIsResizing = false

  // Is non-nil if within the activation rect of one of the sidebars
  var sidebarResizeCursor: NSCursor? = nil

  var isDraggingPlaySlider = false

  // - Fadeable Views

  /// Views that will show/hide when cursor moving in/out of the window
  var fadeableViews = Set<NSView>()
  /// Similar to `fadeableViews`, but may fade in differently depending on configuration of top bar.
  var fadeableViewsInTopBar = Set<NSView>()
  var fadeableViewsAnimationState: UIAnimationState = .shown
  var fadeableTopBarAnimationState: UIAnimationState = .shown
  /// For auto hiding UI after a timeout.
  var hideFadeableViewsTimer: Timer?

  // Other visibility
  var hideCursorTimer: Timer?
  var seekTimeAndThumbnailAnimationState: UIAnimationState = .shown
  /// For auto hiding seek time & thumbnail after a timeout.
  var hideSeekTimeAndThumbnailTimer: Timer?

  // - OSD

  var osd: OSDState

  // - Window Layout State

  var pipStatus = PIPStatus.notInPIP {
    didSet {
      log.verbose("Updated pipStatus to: \(pipStatus)")
    }
  }

  var currentLayout: LayoutState = LayoutState(spec: LayoutSpec.defaultLayout()) {
    didSet {
      if currentLayout.mode == .windowed {
        lastWindowedLayoutSpec = currentLayout.spec
      }
    }
  }
  /// For restoring windowed mode layout from music mode or other mode which does not support sidebars.
  /// Also used to preserve layout if a new file is dragged & dropped into this window
  var lastWindowedLayoutSpec: LayoutSpec = LayoutSpec.defaultLayout()

  // Only used for debug logging:
  @Atomic var layoutTransitionCounter: Int = 0

  /// For throttling `windowDidChangeScreen` notifications. MacOS 14 often sends hundreds in short bursts
  @Atomic var screenChangedTicketCounter: Int = 0
  /// For throttling `windowDidChangeScreenParameters` notifications. MacOS 14 often sends hundreds in short bursts
  @Atomic var screenParamsChangedTicketCounter: Int = 0
  @Atomic var thumbDisplayTicketCounter: Int = 0

  // - Window Geometry

  var geo: GeometrySet

  var windowedModeGeo: PWinGeometry {
    get {
      return geo.windowed
    } set {
      geo = geo.clone(windowed: newValue)
      log.verbose("Updated windowedModeGeo ≔ \(newValue)")
      assert(newValue.mode.isWindowed, "windowedModeGeo has unexpected mode: \(newValue.mode)")
      assert(!newValue.fitOption.isFullScreen, "windowedModeGeo has invalid fitOption: \(newValue.fitOption)")
    }
  }

  var musicModeGeo: MusicModeGeometry {
    get {
      return geo.musicMode
    } set {
      geo = geo.clone(musicMode: newValue)
      log.verbose("Updated musicModeGeo ≔ \(newValue)")
    }
  }

  // Remembers the geometry of the "last closed" window in windowed, so future windows will default to its layout.
  // The first "get" of this will load from saved pref. Every "set" of this will update the pref.
  static var windowedModeGeoLastClosed: PWinGeometry = {
    let csv = Preference.string(for: .uiLastClosedWindowedModeGeometry)
    if csv?.isEmpty ?? true {
      Logger.log.debug("Pref entry for \(Preference.quoted(.uiLastClosedWindowedModeGeometry)) is empty or could not be parsed. Falling back to default geometry")
    } else if let savedGeo = PWinGeometry.fromCSV(csv, Logger.log) {
      if savedGeo.mode.isWindowed && !savedGeo.fitOption.isFullScreen {
        Logger.log.verbose("Loaded pref \(Preference.quoted(.uiLastClosedWindowedModeGeometry)): \(savedGeo)")
        return savedGeo
      } else {
        Logger.log.error("Saved pref \(Preference.quoted(.uiLastClosedWindowedModeGeometry)) is invalid. Falling back to default geometry (found: \(savedGeo))")
      }
    }
    // Compute default geometry for main screen
    let defaultScreen = NSScreen.screens[0]
    return LayoutState.buildFrom(LayoutSpec.defaultLayout()).buildDefaultInitialGeometry(screen: defaultScreen)
  }() {
    didSet {
      guard windowedModeGeoLastClosed.mode.isWindowed, !windowedModeGeoLastClosed.fitOption.isFullScreen else {
        Logger.log.error("Will skip save of windowedModeGeoLastClosed because it is invalid: not in windowed mode! Found: \(windowedModeGeoLastClosed)")
        return
      }
      Preference.set(windowedModeGeoLastClosed.toCSV(), for: .uiLastClosedWindowedModeGeometry)
      Logger.log.verbose("Updated pref \(Preference.quoted(.uiLastClosedWindowedModeGeometry)) ≔ \(windowedModeGeoLastClosed)")
    }
  }

  // Remembers the geometry of the "last closed" music mode window, so future music mode windows will default to its layout.
  // The first "get" of this will load from saved pref. Every "set" of this will update the pref.
  static var musicModeGeoLastClosed: MusicModeGeometry = {
    let csv = Preference.string(for: .uiLastClosedMusicModeGeometry)
    if let savedGeo = MusicModeGeometry.fromCSV(csv, Logger.log) {
      Logger.log.verbose("Loaded pref \(Preference.quoted(.uiLastClosedMusicModeGeometry)): \(savedGeo)")
      return savedGeo
    }
    Logger.log("Pref \(Preference.quoted(.uiLastClosedMusicModeGeometry)) is empty or could not be parsed. Falling back to default music mode geometry",
               level: .debug)
    let defaultScreen = NSScreen.screens[0]
    let defaultGeo = MiniPlayerViewController.buildMusicModeGeometryFromPrefs(screen: defaultScreen,
                                                                              video: VideoGeometry.defaultGeometry())
    return defaultGeo
  }() {
    didSet {
      Preference.set(musicModeGeoLastClosed.toCSV(), for: .uiLastClosedMusicModeGeometry)
      Logger.log.verbose("Updated musicModeGeoLastClosed ≔ \(musicModeGeoLastClosed)")
    }
  }

  // MARK: - Notification & user defaults observers

  private var co: CocoaObserver!

  private func addObservers() {
    guard let window else { return }

    co.initObservers()

    co.addObserver(to: NSWorkspace.shared.notificationCenter, forName: NSWorkspace.activeSpaceDidChangeNotification) { [self] _ in
      // FIXME: this is not ready for production yet! Need to fix issues with freezing video
      guard Preference.bool(for: .togglePipWhenSwitchingSpaces) else { return }
      if !window.isOnActiveSpace && pipStatus == .notInPIP {
        animationPipeline.submitInstantTask({ [self] in
          log.debug("Window is no longer in active space; entering PIP")
          enterPIP(then: { [self] in
            isWindowPipDueToInactiveSpace = true
          })
        })
      } else if window.isOnActiveSpace && isWindowPipDueToInactiveSpace && pipStatus == .inPIP {
        animationPipeline.submitInstantTask({ [self] in
          log.debug("Window is in active space again; exiting PIP")
          isWindowPipDueToInactiveSpace = false
          exitPIP()
        })
      }
    }

    co.addObserver(to: .default, forName: NSScreen.colorSpaceDidChangeNotification) { [self] noti in
      colorSpaceDidChange(noti)
    }

    co.addObserver(to: .default, forName: NSWindow.didChangeScreenNotification) { [self] noti in
      windowDidChangeScreen(noti)
    }

    co.addObserver(to: .default, forName: .iinaMediaTitleChanged, object: player) { [self] _ in
      updateTitle()
    }

    // This observer handles when the user connected a new screen or removed a screen, or shows/hides the Dock.
    // This is legacy code which will not run in newer versions of MacOS.
    co.addObserver(to: .default, forName: NSApplication.didChangeScreenParametersNotification) { [self] noti in
      windowDidChangeScreenParameters(noti)
    }

    // Observe the loop knobs on the progress bar and update mpv when the knobs move.
    co.addObserver(to: .default, forName: .iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopA) { [weak self] _ in
      guard let self = self else { return }
      let seconds = self.percentToSeconds(self.playSlider.abLoopA.doubleValue)
      self.player.abLoopA = seconds
      self.player.sendOSD(.abLoopUpdate(.aSet, VideoTime(seconds).stringRepresentation))
    }
    co.addObserver(to: .default, forName: .iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopB) { [weak self] _ in
      guard let self = self else { return }
      let seconds = self.percentToSeconds(self.playSlider.abLoopB.doubleValue)
      self.player.abLoopB = seconds
      self.player.sendOSD(.abLoopUpdate(.bSet, VideoTime(seconds).stringRepresentation))
    }

    co.addObserver(to: .default, forName: NSWorkspace.willSleepNotification) { [self] _ in
      if Preference.bool(for: .pauseWhenGoesToSleep) {
        self.player.pause()
      }
    }
  }

  // Cached user defaults values
  internal lazy var followGlobalSeekTypeWhenAdjustSlider: Bool = Preference.bool(for: .followGlobalSeekTypeWhenAdjustSlider)
  internal lazy var useExactSeek: Preference.SeekOption = Preference.enum(for: .useExactSeek)
  internal lazy var singleClickAction: Preference.MouseClickAction = Preference.enum(for: .singleClickAction)
  internal lazy var doubleClickAction: Preference.MouseClickAction = Preference.enum(for: .doubleClickAction)
  internal lazy var horizontalScrollAction: Preference.ScrollAction = Preference.enum(for: .horizontalScrollAction)
  internal lazy var verticalScrollAction: Preference.ScrollAction = Preference.enum(for: .verticalScrollAction)

  static private let observedPrefKeys: [Preference.Key] = [
    .enableAdvancedSettings,
    .enableToneMapping,
    .toneMappingTargetPeak,
    .loadIccProfile,
    .toneMappingAlgorithm,
    .keepOpenOnFileEnd,
    .playlistAutoPlayNext,
    .themeMaterial,
    .playerWindowOpacity,
    .showRemainingTime,
    .maxVolume,
    .useExactSeek,
    .relativeSeekAmount,
    .volumeScrollAmount,
    .singleClickAction,
    .doubleClickAction,
    .horizontalScrollAction,
    .verticalScrollAction,
    .playlistShowMetadata,
    .playlistShowMetadataInMusicMode,
    .shortenFileGroupsInPlaylist,
    .autoSwitchToMusicMode,
    .hideWindowsWhenInactive,
    .enableControlBarAutoHide,
    .osdAutoHideTimeout,
    .osdTextSize,
    .osdPosition,
    .enableOSC,
    .oscPosition,
    .topBarPlacement,
    .bottomBarPlacement,
    .oscBarHeight,
    .oscBarPlaybackIconSize,
    .oscBarPlaybackIconSpacing,
    .controlBarToolbarButtons,
    .oscBarToolbarIconSize,
    .oscBarToolbarIconSpacing,
    .enableThumbnailPreview,
    .enableThumbnailForRemoteFiles,
    .enableThumbnailForMusicMode,
    .thumbnailSizeOption,
    .thumbnailFixedLength,
    .thumbnailRawSizePercentage,
    .thumbnailDisplayedSizePercentage,
    .thumbnailBorderStyle,
    .showChapterPos,
    .arrowButtonAction,
    .playSliderBarLeftColor,
    .blackOutMonitor,
    .useLegacyFullScreen,
    .displayTimeAndBatteryInFullScreen,
    .alwaysShowOnTopIcon,
    .leadingSidebarPlacement,
    .trailingSidebarPlacement,
    .settingsTabGroupLocation,
    .playlistTabGroupLocation,
    .aspectRatioPanelPresets,
    .cropPanelPresets,
    .showLeadingSidebarToggleButton,
    .showTrailingSidebarToggleButton,
    .useLegacyWindowedMode,
    .lockViewportToVideoSize,
    .allowVideoToOverlapCameraHousing,
  ]

  func prefDidChange(_ key: Preference.Key, _ newValue: Any?) {
    guard isOpen else { return }  // do not want to respond to some things like blackOutOtherMonitors while closed!

    switch key {
    case .enableAdvancedSettings:
      animationPipeline.submitTask({ [self] in
        updateCustomBorderBoxAndWindowOpacity()
        // may need to hide cropbox label and other advanced stuff
        quickSettingView.reload()
      })
    case .enableToneMapping,
      .toneMappingTargetPeak,
      .loadIccProfile,
      .toneMappingAlgorithm:
      videoView.refreshEdrMode()
    case .themeMaterial:
      applyThemeMaterial()
    case .playerWindowOpacity:
      animationPipeline.submitTask({ [self] in
        updateCustomBorderBoxAndWindowOpacity()
      })
    case .showRemainingTime:
      if let newValue = newValue as? Bool {
        rightLabel.mode = newValue ? .remaining : .duration
      }
    case .maxVolume:
      if let newValue = newValue as? Int {
        if player.mpv.getDouble(MPVOption.Audio.volume) > Double(newValue) {
          player.mpv.setDouble(MPVOption.Audio.volume, Double(newValue))
        } else {
          updateVolumeUI()
        }
      }
    case .useExactSeek:
      if let newValue = newValue as? Int {
        useExactSeek = Preference.SeekOption(rawValue: newValue)!
      }
    case .relativeSeekAmount:
      playSlider.updateSensitivity()
    case .volumeScrollAmount:
      volumeSlider.updateSensitivity()
    case .singleClickAction:
      if let newValue = newValue as? Int {
        singleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }
    case .doubleClickAction:
      if let newValue = newValue as? Int {
        doubleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }
    case .playlistShowMetadata, .playlistShowMetadataInMusicMode, .shortenFileGroupsInPlaylist:
      // Reload now, even if not visible. Don't nitpick.
      player.windowController.playlistView.playlistTableView.reloadData()
    case .autoSwitchToMusicMode:
      player.overrideAutoMusicMode = false

    case .keepOpenOnFileEnd, .playlistAutoPlayNext:
      player.mpv.updateKeepOpenOptionFromPrefs()

    case .enableOSC,
      .oscPosition,
      .topBarPlacement,
      .bottomBarPlacement,
      .oscBarHeight,
      .oscBarPlaybackIconSize,
      .oscBarPlaybackIconSpacing,
      .oscBarToolbarIconSize,
      .oscBarToolbarIconSpacing,
      .showLeadingSidebarToggleButton,
      .showTrailingSidebarToggleButton,
      .controlBarToolbarButtons,
      .allowVideoToOverlapCameraHousing,
      .useLegacyWindowedMode,
      .arrowButtonAction,
      .playSliderBarLeftColor:

      log.verbose("Calling updateTitleBarAndOSC in response to pref change: \(key.rawValue.quoted)")
      updateTitleBarAndOSC()
    case .lockViewportToVideoSize:
      if let isLocked = newValue as? Bool, isLocked {
        log.debug("Pref \(key.rawValue.quoted) changed to \(isLocked): resizing viewport to remove any excess space")
        resizeViewport()
      }
    case .hideWindowsWhenInactive:
      animationPipeline.submitInstantTask({ [self] in
        refreshHidesOnDeactivateStatus()
      })

    case .thumbnailSizeOption,
      .thumbnailFixedLength,
      .thumbnailRawSizePercentage,
      .enableThumbnailPreview,
      .enableThumbnailForRemoteFiles,
      .enableThumbnailForMusicMode:

      log.verbose("Pref \(key.rawValue.quoted) changed: requesting thumbs regen")
      // May need to remove thumbs or generate new ones: let method below figure it out:
      player.reloadThumbnails(forMedia: player.info.currentPlayback)

    case .showChapterPos:
      if let newValue = newValue as? Bool {
        playSlider.customCell.drawChapters = newValue
      }
    case .verticalScrollAction:
      if let newValue = newValue as? Int {
        verticalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }
    case .horizontalScrollAction:
      if let newValue = newValue as? Int {
        horizontalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }
    case .blackOutMonitor:
      if let newValue = newValue as? Bool {
        if isFullScreen {
          newValue ? blackOutOtherMonitors() : removeBlackWindows()
        }
      }
    case .useLegacyFullScreen:
      updateUseLegacyFullScreen()
    case .displayTimeAndBatteryInFullScreen:
      if let newValue = newValue as? Bool {
        if !newValue {
          additionalInfoView.isHidden = true
        }
      }
    case .alwaysShowOnTopIcon:
      updateOnTopButton()
    case .leadingSidebarPlacement, .trailingSidebarPlacement:
      updateSidebarPlacements()
    case .settingsTabGroupLocation:
      if let newRawValue = newValue as? Int, let newLocationID = Preference.SidebarLocation(rawValue: newRawValue) {
        self.moveTabGroup(.settings, toSidebarLocation: newLocationID)
      }
    case .playlistTabGroupLocation:
      if let newRawValue = newValue as? Int, let newLocationID = Preference.SidebarLocation(rawValue: newRawValue) {
        self.moveTabGroup(.playlist, toSidebarLocation: newLocationID)
      }
    case .osdAutoHideTimeout, .enableControlBarAutoHide:
      if let newTimeout = newValue as? Double {
        if osd.animationState == .shown, let hideOSDTimer = osd.hideOSDTimer, hideOSDTimer.isValid {
          // Reschedule timer to prevent prev long timeout from lingering
          osd.hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(newTimeout), target: self,
                                                  selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
        }
      }
    case .osdPosition:
      // If OSD is showing, it will move over as a neat animation:
      animationPipeline.submitInstantTask {
        self.updateOSDPosition()
      }
    case .osdTextSize:
      animationPipeline.submitInstantTask { [self] in
        updateOSDTextSize()
        setOSDViews()
      }
    case .aspectRatioPanelPresets, .cropPanelPresets:
      quickSettingView.updateSegmentLabels()
    default:
      return
    }
  }

  // MARK: - Outlets

  // - Outlets: Constraints

  var viewportViewHeightContraint: NSLayoutConstraint? = nil

  // Spacers in left title bar accessory view:
  @IBOutlet weak var leadingTitleBarLeadingSpaceConstraint: NSLayoutConstraint!
  @IBOutlet weak var leadingTitleBarTrailingSpaceConstraint: NSLayoutConstraint!

  // Spacers in right title bar accessory view:
  @IBOutlet weak var trailingTitleBarLeadingSpaceConstraint: NSLayoutConstraint!
  @IBOutlet weak var trailingTitleBarTrailingSpaceConstraint: NSLayoutConstraint!

  // - Top bar (title bar and/or top OSC) constraints
  @IBOutlet weak var viewportTopOffsetFromTopBarBottomConstraint: NSLayoutConstraint!
  @IBOutlet weak var viewportTopOffsetFromTopBarTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var viewportTopOffsetFromContentViewTopConstraint: NSLayoutConstraint!
  // Needs to be changed to align with either sidepanel or leading edge of window:
  @IBOutlet weak var topBarLeadingSpaceConstraint: NSLayoutConstraint!
  // Needs to be changed to align with either sidepanel or trailing edge of window:
  @IBOutlet weak var topBarTrailingSpaceConstraint: NSLayoutConstraint!

  // - Bottom OSC constraints
  @IBOutlet weak var viewportBtmOffsetFromContentViewBtmConstraint: NSLayoutConstraint!
  var viewportBtmOffsetFromTopOfBottomBarConstraint: NSLayoutConstraint!
  var viewportBtmOffsetFromBtmOfBottomBarConstraint: NSLayoutConstraint!
  // Needs to be changed to align with either sidepanel or leading edge of window:
  var bottomBarLeadingSpaceConstraint: NSLayoutConstraint!
  // Needs to be changed to align with either sidepanel or trailing edge of window:
  var bottomBarTrailingSpaceConstraint: NSLayoutConstraint!

  // - Leading sidebar constraints
  @IBOutlet weak var viewportLeadingOffsetFromContentViewLeadingConstraint: NSLayoutConstraint!
  @IBOutlet weak var viewportLeadingOffsetFromLeadingSidebarLeadingConstraint: NSLayoutConstraint!
  @IBOutlet weak var viewportLeadingOffsetFromLeadingSidebarTrailingConstraint: NSLayoutConstraint!

  @IBOutlet weak var viewportLeadingToLeadingSidebarCropTrailingConstraint: NSLayoutConstraint!

  // - Trailing sidebar constraints
  @IBOutlet weak var viewportTrailingOffsetFromContentViewTrailingConstraint: NSLayoutConstraint!
  @IBOutlet weak var viewportTrailingOffsetFromTrailingSidebarLeadingConstraint: NSLayoutConstraint!
  @IBOutlet weak var viewportTrailingOffsetFromTrailingSidebarTrailingConstraint: NSLayoutConstraint!

  @IBOutlet weak var viewportTrailingToTrailingSidebarCropLeadingConstraint: NSLayoutConstraint!

  /**
   OSD: shown here in "upper-left" configuration.
   For "upper-right" config: swap OSD & AdditionalInfo anchors in A & B, and invert all the params of B.
   ┌───────────────────────┐
   │ A ┌────┐  ┌───────┐ B │  A: leadingSidebarToOSDSpaceConstraint
   │◄─►│ OSD│  │ AddNfo│◄─►│  B: trailingSidebarToOSDSpaceConstraint
   │   └────┘  └───────┘   │
   └───────────────────────┘
   */
  @IBOutlet weak var leadingSidebarToOSDSpaceConstraint: NSLayoutConstraint!
  @IBOutlet weak var trailingSidebarToOSDSpaceConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdTopToTopBarConstraint: NSLayoutConstraint!
  @IBOutlet var osdLeadingToMiniPlayerButtonsTrailingConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdIconWidthConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdIconHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdTopMarginConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdTrailingMarginConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdLeadingMarginConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdBottomMarginConstraint: NSLayoutConstraint!

  /// Sets the size of the spacer view in the top overlay which reserves space for a title bar.
  @IBOutlet weak var titleBarHeightConstraint: NSLayoutConstraint!


  var fragPlaybackBtnsWidthConstraint: NSLayoutConstraint!

  /// Size of each side of the (square) `playButton`
  var playBtnWidthConstraint: NSLayoutConstraint!
  /// Size of each side of square buttons `leftArrowButton` & `rightArrowButton`
  var arrowBtnWidthConstraint: NSLayoutConstraint!

  var leftArrowBtnHorizOffsetConstraint: NSLayoutConstraint!
  var rightArrowBtnHorizOffsetConstraint: NSLayoutConstraint!

  @IBOutlet weak var topOSCHeightConstraint: NSLayoutConstraint!

  @IBOutlet weak var timePositionHoverLabelHorizontalCenterConstraint: NSLayoutConstraint!
  @IBOutlet weak var timePositionHoverLabelVerticalSpaceConstraint: NSLayoutConstraint!
  @IBOutlet weak var playSliderHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var volumeIconSizeConstraint: NSLayoutConstraint!

  // - Outlets: Views

  @IBOutlet weak var customWindowBorderBox: NSBox!
  @IBOutlet weak var customWindowBorderTopHighlightBox: NSBox!

  // MiniPlayer buttons
  @IBOutlet weak var closeButtonView: NSView!
  // Mini island containing window buttons which hover over album art / video (when video is visible):
  @IBOutlet weak var closeButtonBackgroundViewVE: NSVisualEffectView!
  // Mini island containing window buttons which appear next to controls (when video not visible):
  @IBOutlet weak var closeButtonBackgroundViewBox: NSBox!
  @IBOutlet weak var closeButtonVE: NSButton!
  @IBOutlet weak var backButtonVE: NSButton!
  @IBOutlet weak var closeButtonBox: NSButton!
  @IBOutlet weak var backButtonBox: NSButton!

  @IBOutlet var leadingTitleBarAccessoryView: NSView!
  @IBOutlet var trailingTitleBarAccessoryView: NSView!
  /// "Pin to Top" icon in title bar, if configured to  be shown
  @IBOutlet weak var onTopButton: NSButton!
  @IBOutlet weak var leadingSidebarToggleButton: NSButton!
  @IBOutlet weak var trailingSidebarToggleButton: NSButton!

  /// Panel at top of window. May be `insideViewport` or `outsideViewport`. May contain `titleBarView` and/or `controlBarTop`
  /// depending on configuration.
  @IBOutlet weak var topBarView: NSVisualEffectView!
  /// Bottom border of `topBarView`.
  @IBOutlet weak var topBarBottomBorder: NSBox!
  /// Reserves space for the title bar components. Does not contain any child views.
  @IBOutlet weak var titleBarView: NSView!
  /// Control bar at top of window, if configured.
  @IBOutlet weak var controlBarTop: NSView!

  @IBOutlet weak var controlBarFloating: FloatingControlBarView!

  /// Control bar at bottom of window, if configured. May be `insideViewport` or `outsideViewport`.
  let bottomBarView: NSView = NSVisualEffectView()
  /// Top border of `bottomBarView`.
  let bottomBarTopBorder = NSBox()

  @IBOutlet weak var timePositionHoverLabel: NSTextField!
  var thumbnailPeekView = ThumbnailPeekView()
  var leftArrowButton: NSButton!
  var rightArrowButton: NSButton!

  @IBOutlet weak var leadingSidebarView: NSVisualEffectView!
  @IBOutlet weak var leadingSidebarTrailingBorder: NSBox!  // shown if leading sidebar is "outside"
  @IBOutlet weak var trailingSidebarView: NSVisualEffectView!
  @IBOutlet weak var trailingSidebarLeadingBorder: NSBox!  // shown if trailing sidebar is "outside"

  @IBOutlet weak var bufferIndicatorView: NSVisualEffectView!
  @IBOutlet weak var bufferProgressLabel: NSTextField!
  @IBOutlet weak var bufferSpin: NSProgressIndicator!
  @IBOutlet weak var bufferDetailLabel: NSTextField!

  @IBOutlet weak var additionalInfoView: NSVisualEffectView!
  @IBOutlet weak var additionalInfoLabel: NSTextField!
  @IBOutlet weak var additionalInfoStackView: NSStackView!
  @IBOutlet weak var additionalInfoTitle: NSTextField!
  @IBOutlet weak var additionalInfoBatteryView: NSView!
  @IBOutlet weak var additionalInfoBattery: NSTextField!

  @IBOutlet weak var oscFloatingPlayButtonsContainerView: NSStackView!
  @IBOutlet weak var oscFloatingUpperView: NSStackView!
  @IBOutlet weak var oscFloatingLowerView: NSStackView!
  let oscBottomMainView = NSStackView()
  @IBOutlet weak var oscTopMainView: NSStackView!

  var fragToolbarView: NSStackView? = nil
  @IBOutlet weak var fragVolumeView: NSView!
  @IBOutlet var fragPositionSliderView: NSView!
  let fragPlaybackBtnsView = PlaybackControlButtonsView()

  /// Speed indicator label, when playing at speeds other than 1x
  let speedLabel = NSTextField()

  // OSD
  @IBOutlet weak var osdVisualEffectView: NSVisualEffectView!
  @IBOutlet weak var osdHStackView: NSStackView!
  @IBOutlet weak var osdVStackView: NSStackView!
  @IBOutlet weak var osdIconImageView: NSImageView!
  @IBOutlet weak var osdLabel: NSTextField!
  @IBOutlet weak var osdAccessoryText: NSTextField!
  @IBOutlet weak var osdAccessoryProgress: NSProgressIndicator!

  @IBOutlet weak var pipOverlayView: NSVisualEffectView!
  @IBOutlet weak var viewportView: ViewportView!
  let defaultAlbumArtView = NSView()

  @IBOutlet weak var volumeSlider: VolumeSlider!
  @IBOutlet weak var muteButton: NSButton!
  var playButton: NSButton!
  @IBOutlet weak var playSlider: PlaySlider!
  @IBOutlet weak var rightLabel: DurationDisplayTextField!
  @IBOutlet weak var leftLabel: DurationDisplayTextField!

  /// Differentiate between single clicks and double clicks.
  var singleClickTimer: Timer?
  var mouseExitEnterCount = 0

  /// Scroll wheel (see `PWin_MouseInput.swift`)

  /// The virtual scroll wheel which may result in either volume or playback time seeking depending on direction
  let windowScrollWheel = VirtualScrollWheel()
  /// One of `playSlider`, `volumeSlider`, or `nil`
  var scrollActionSlider: ScrollableSlider? = nil

  var isInScrollWheelSeek: Bool {
    return windowScrollWheel.isScrolling() || playSlider.isScrolling() || volumeSlider.isScrolling()
  }

  // Other state

  var mouseActionDisabledViews: [NSView?] {[leadingSidebarView, trailingSidebarView, currentControlBar, titleBarView, oscTopMainView, subPopoverView]}

  var isFullScreen: Bool {
    return currentLayout.isFullScreen
  }

  var isInMiniPlayer: Bool {
    return currentLayout.isMusicMode
  }

  var isInInteractiveMode: Bool {
    return currentLayout.isInteractiveMode
  }

  var standardWindowButtons: [NSButton] {
    get {
      return ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindow.ButtonType]).compactMap {
        window?.standardWindowButton($0)
      }
    }
  }

  var documentIconButton: NSButton? {
    get {
      window?.standardWindowButton(.documentIconButton)
    }
  }

  var trafficLightButtons: [NSButton] {
    get {
      if let window, window.styleMask.contains(.titled) {
        return ([.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType]).compactMap {
          window.standardWindowButton($0)
        }
      }
      return customTitleBar?.trafficLightButtons ?? []
    }
  }

  // Width of the 3 traffic light buttons
  lazy var trafficLightButtonsWidth: CGFloat = {
    var maxX: CGFloat = 0
    for buttonType in [NSWindow.ButtonType.closeButton, NSWindow.ButtonType.miniaturizeButton, NSWindow.ButtonType.zoomButton] {
      if let button = window!.standardWindowButton(buttonType) {
        maxX = max(maxX, button.frame.origin.x + button.frame.width)
      }
    }
    return maxX
  }()

  /** Get the `NSTextField` of widow's title. */
  var titleTextField: NSTextField? {
    get {
      return window?.standardWindowButton(.closeButton)?.superview?.subviews.compactMap({ $0 as? NSTextField }).first
    }
  }

  var leadingTitlebarAccesoryViewController: NSTitlebarAccessoryViewController?
  var trailingTitlebarAccesoryViewController: NSTitlebarAccessoryViewController?

  /** Current OSC view. May be top, bottom, or floating depneding on user pref. */
  var currentControlBar: NSView?

  lazy var pluginOverlayViewContainer: NSView! = {
    guard let window = window, let cv = window.contentView else { return nil }
    let view = NSView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(view, positioned: .below, relativeTo: bufferIndicatorView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": view])
    return view
  }()

  lazy var subPopoverView = playlistView.subPopover?.contentViewController?.view

  // PIP

  lazy var _pip: PIPViewController = {
    let pip = VideoPIPViewController()
    pip.delegate = self
    return pip
  }()

  var pip: PIPViewController {
    _pip
  }

  var pipVideo: NSViewController!

  // MARK: - Initialization

  init(playerCore: PlayerCore) {
    self.player = playerCore
    self.osd = OSDState(log: playerCore.log)
    self.geo = GeometrySet(windowed: PlayerWindowController.windowedModeGeoLastClosed,
                           musicMode: PlayerWindowController.musicModeGeoLastClosed,
                           video: VideoGeometry.defaultGeometry(playerCore.log))
    super.init(window: nil)
    log.verbose("PlayerWindowController init")
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func windowDidLoad() {
    log.verbose("PlayerWindow windowDidLoad starting")
    super.windowDidLoad()

    miniPlayer = MiniPlayerViewController()
    miniPlayer.windowController = self

    viewportView.player = player

    co = CocoaObserver(observedPrefKeys: PlayerWindowController.observedPrefKeys,
                       player.log, prefDidChange: self.prefDidChange)

    guard let window = window else { return }
    guard let contentView = window.contentView else { return }

    /// Set base options for `collectionBehavior` here, and then insert/remove full screen options
    /// using `resetCollectionBehavior`. Do not mess with the base options again because doing so seems
    /// to cause flickering while animating.
    /// Always use option `.fullScreenDisallowsTiling`. As of MacOS 14.2.1, tiling is at best glitchy &
    /// at worst results in an infinite loop with our code.
    // FIXME: support tiling for at least native full screen
    window.collectionBehavior = [.managed, .fullScreenDisallowsTiling]

    window.initialFirstResponder = nil

    // size
    window.minSize = AppData.minVideoSize

    // need to deal with control bar, so we handle it manually
    window.isMovableByWindowBackground  = false

    // Registers this window for didChangeScreenProfileNotification
    window.displaysWhenScreenProfileChanges = true

    leftLabel.mode = .current
    rightLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

    // This is above the play slider and by default, will swallow clicks. Send events to play slider instead
    timePositionHoverLabel.nextResponder = playSlider

    // gesture recognizers
    rotationHandler.windowController = self
    magnificationHandler.windowController = self
    contentView.addGestureRecognizer(magnificationHandler.magnificationGestureRecognizer)
    contentView.addGestureRecognizer(rotationHandler.rotationGestureRecognizer)

    windowScrollWheel.scrollWheelDidStart = self.scrollWheelDidStart(_:)
    windowScrollWheel.scrollWheelDidEnd = self.scrollWheelDidEnd

    playlistView.windowController = self
    quickSettingView.windowController = self

    // other initialization
    osdAccessoryProgress.usesThreadedAnimation = false

    /// Note that this will add `videoView`, but at first run it will not yet have a video layer.
    /// Need to wait until after mpv is initialized before creating `videoView.layer`
    addVideoViewToWindow()
    player.start()

    /// Use an animation task to init views, to hopefully prevent partial/redundant draws.
    /// NOTE: this will likely execute *after* `_showWindow()`
    animationPipeline.submitInstantTask{ [self] in

      // FIXME: stick to individual side of screen
      // FIXME: parent playlist
      // FIXME: play bar drawing

      // Top bar: other init
      topBarView.clipsToBounds = true
      topBarBottomBorder.fillColor = NSColor(named: .titleBarBorder)!

      viewportView.clipsToBounds = true

      /// Set `window.contentView`'s background to black so that the windows behind this one don't bleed through
      /// when `lockViewportToVideoSize` is disabled, or when in legacy full screen on a Macbook screen  with a
      /// notch and the preference `allowVideoToOverlapCameraHousing` is false.
      contentView.wantsLayer = true
      // Need this to be black also, for sidebar animations
      viewportView.wantsLayer = true
      setEmptySpaceColor(to: Constants.Color.defaultWindowBackgroundColor)

      applyThemeMaterial()

      // Titlebar accessories

      // Update this here to reduce animation jitter on older versions of MacOS:
      viewportTopOffsetFromTopBarTopConstraint.constant = PlayerWindowController.standardTitleBarHeight

      addTitleBarAccessoryViews()

      // Work around a bug in macOS Ventura where HDR content becomes dimmed when playing in full
      // screen mode once overlaying views are fully hidden (issue #3844). After applying this
      // workaround another bug in Ventura where an external monitor goes black could not be
      // reproduced (issue #4015). The workaround adds a tiny subview with such a low alpha level it
      // is invisible to the human eye. This workaround may not be effective in all cases.
      if #available(macOS 13, *) {
        let view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 0.1, height: 0.1)))
        view.wantsLayer = true
        view.layer?.backgroundColor = Constants.Color.defaultWindowBackgroundColor
        view.layer?.opacity = 0.01
        contentView.addSubview(view)
      }

      contentView.addSubview(thumbnailPeekView, positioned: .below, relativeTo: osdVisualEffectView)
      thumbnailPeekView.identifier = .init("thumbnailPeekView")
      thumbnailPeekView.isHidden = true
      initBottomBarView(in: contentView)
      initSpeedLabel()
      initPlaybackBtnsView()
      initAlbumArtView()
      fragPositionSliderView.userInterfaceLayoutDirection = .leftToRight

      bufferIndicatorView.roundCorners()
      additionalInfoView.roundCorners()
      osdVisualEffectView.roundCorners()

      contentView.configureSubtreeForCoreAnimation()

      // Make sure to set this inside the animation task! See note above
      loaded = true

      // Update to corect values before displaying. Only useful when restoring at launch
      updateUI()

      if player.info.isRestoring {
        if let priorState = player.info.priorState, let layoutSpec = priorState.layoutSpec {
          // Preemptively set window frames to prevent windows from "jumping" during restore
          if layoutSpec.mode == .musicMode {
            let geo = priorState.geoSet.musicMode.toPWinGeometry()
            player.window.setFrameImmediately(geo, notify: false)
          } else {
            let geo = priorState.geoSet.windowed
            player.window.setFrameImmediately(geo, notify: false)
          }
        }

        defaultAlbumArtView.isHidden = player.info.isVideoTrackSelected
      }

      if player.disableUI { hideFadeableViews() }

      log.verbose("PlayerWindow windowDidLoad done")
      player.events.emit(.windowLoaded)
    }

  }

  private func initBottomBarView(in contentView: NSView) {
    contentView.addSubview(bottomBarView, positioned: .above, relativeTo: viewportView)
    bottomBarView.clipsToBounds = true
    if let bottomBarView = bottomBarView as? NSVisualEffectView {
      bottomBarView.blendingMode = .withinWindow
      bottomBarView.material = .sidebar
      bottomBarView.state = .active
    }
    bottomBarView.identifier = .init("bottomBarView")  // helps with debug logging
    bottomBarView.isHidden = true
    bottomBarView.translatesAutoresizingMaskIntoConstraints = false

    viewportBtmOffsetFromTopOfBottomBarConstraint = viewportView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 0)
    viewportBtmOffsetFromTopOfBottomBarConstraint.isActive = true
    viewportBtmOffsetFromTopOfBottomBarConstraint.identifier = .init("viewportBtmOffsetFromTopOfBottomBarConstraint")

    viewportBtmOffsetFromBtmOfBottomBarConstraint = viewportView.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor, constant: 0)
    viewportBtmOffsetFromBtmOfBottomBarConstraint.isActive = true
    viewportBtmOffsetFromBtmOfBottomBarConstraint.identifier = .init("viewportBtmOffsetFromBtmOfBottomBarConstraint")

    bottomBarLeadingSpaceConstraint = bottomBarView.leadingAnchor.constraint(equalTo: leadingSidebarView.trailingAnchor, constant: 0)
    bottomBarLeadingSpaceConstraint.isActive = true
    bottomBarLeadingSpaceConstraint.identifier = .init("bottomBarLeadingSpaceConstraint")

    bottomBarTrailingSpaceConstraint = bottomBarView.trailingAnchor.constraint(equalTo: trailingSidebarView.leadingAnchor, constant: 0)
    bottomBarTrailingSpaceConstraint.isActive = true
    bottomBarTrailingSpaceConstraint.identifier = .init("bottomBarTrailingSpaceConstraint")

    oscBottomMainView.identifier = .init("oscBottomMainView")  // helps with debug logging
    oscBottomMainView.spacing = 4
    oscBottomMainView.orientation = .horizontal
    oscBottomMainView.alignment = .centerY
    oscBottomMainView.distribution = .gravityAreas
    oscBottomMainView.translatesAutoresizingMaskIntoConstraints = false

    bottomBarTopBorder.identifier = .init("bottomBarTopBorder")  // helps with debug logging
    bottomBarTopBorder.boxType = .custom
    bottomBarTopBorder.titlePosition = .noTitle
    bottomBarTopBorder.borderWidth = 0
    bottomBarTopBorder.fillColor = NSColor(named: .titleBarBorder)!
    bottomBarTopBorder.translatesAutoresizingMaskIntoConstraints = false
    bottomBarView.addSubview(bottomBarTopBorder)
    bottomBarTopBorder.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)
    bottomBarTopBorder.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    bottomBarTopBorder.borderColor = NSColor.clear
  }

  private func initSpeedLabel() {
    speedLabel.identifier = .init("speedLabel")  // helps with debug logging
    speedLabel.translatesAutoresizingMaskIntoConstraints = false
    speedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
    speedLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    speedLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    speedLabel.setContentHuggingPriority(.required, for: .horizontal)
    speedLabel.setContentHuggingPriority(.required, for: .vertical)
    speedLabel.font = NSFont.messageFont(ofSize: 10)
    speedLabel.textColor = .textColor
    speedLabel.alphaValue = 0.75
    speedLabel.isBordered = false
    speedLabel.drawsBackground = false
    speedLabel.isBezeled = false
    speedLabel.isEditable = false
    speedLabel.isSelectable = false
    speedLabel.isEnabled = true
    speedLabel.refusesFirstResponder = true
    speedLabel.alignment = .center

    speedLabel.nextResponder = playButton
  }

  private func initPlaybackBtnsView() {
    let oscGeo = ControlBarGeometry.current

    // Play button
    playButton = NSButton(image: playImage, target: self,
                          action: #selector(playButtonAction(_:)))
    playButton.identifier = .init("playButton")  // helps with debug logging
    playButton.isBordered = false
    playButton.bezelStyle = .regularSquare
    playButton.imagePosition = .imageOnly
    playButton.refusesFirstResponder = true
    playButton.imageScaling = .scaleProportionallyUpOrDown
    if #available(macOS 11.0, *) {
      let config = NSImage.SymbolConfiguration(textStyle: .headline)
      playButton.symbolConfiguration = config
    }
    playButton.translatesAutoresizingMaskIntoConstraints = false
    playButton.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    playButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    let playIconSize = oscGeo.playIconSize
    playBtnWidthConstraint = playButton.widthAnchor.constraint(equalToConstant: playIconSize)
    playBtnWidthConstraint.priority = .init(850)  // allow to shrink for animations or speedLabel
    playBtnWidthConstraint.isActive = true
    let playAspectConstraint = playButton.widthAnchor.constraint(equalTo: playButton.heightAnchor)
    playAspectConstraint.isActive = true

    let playButtonVStackView = ClickThroughStackView()
    playButtonVStackView.identifier = .init("playButtonVStackView")
    playButtonVStackView.orientation = .vertical
    playButtonVStackView.alignment = .centerX
    playButtonVStackView.detachesHiddenViews = true
    playButtonVStackView.layer?.backgroundColor = .clear
    playButtonVStackView.spacing = 0
    playButtonVStackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    playButtonVStackView.addView(speedLabel, in: .center)
    playButtonVStackView.addView(playButton, in: .center)
    playButtonVStackView.setHuggingPriority(.init(250), for: .vertical)
    playButtonVStackView.setHuggingPriority(.init(250), for: .horizontal)
    playButtonVStackView.translatesAutoresizingMaskIntoConstraints = false

    // Left Arrow button
    leftArrowButton = NSButton(image: oscGeo.leftArrowImage, target: self,
                               action: #selector(leftArrowButtonAction(_:)))
    leftArrowButton.identifier = .init("leftArrowButton")
    leftArrowButton.setButtonType(.multiLevelAccelerator)
    leftArrowButton.isBordered = false
    leftArrowButton.maxAcceleratorLevel = 5
    leftArrowButton.bezelStyle = .regularSquare
    leftArrowButton.imagePosition = .imageOnly
    leftArrowButton.refusesFirstResponder = true
    leftArrowButton.imageScaling = .scaleProportionallyUpOrDown
    leftArrowButton.translatesAutoresizingMaskIntoConstraints = false

    // Right Arrow button
    rightArrowButton = NSButton(image: oscGeo.rightArrowImage, target: self,
                                action: #selector(rightArrowButtonAction(_:)))
    rightArrowButton.identifier = .init("rightArrowButton")
    rightArrowButton.setButtonType(.multiLevelAccelerator)
    rightArrowButton.isBordered = false
    rightArrowButton.maxAcceleratorLevel = 5
    rightArrowButton.bezelStyle = .regularSquare
    rightArrowButton.imagePosition = .imageOnly
    rightArrowButton.refusesFirstResponder = true
    rightArrowButton.imageScaling = .scaleProportionallyUpOrDown
    rightArrowButton.translatesAutoresizingMaskIntoConstraints = false

    fragPlaybackBtnsView.identifier = .init("fragPlaybackBtnsView")
    fragPlaybackBtnsView.addSubview(leftArrowButton)
    fragPlaybackBtnsView.addSubview(playButtonVStackView)
    fragPlaybackBtnsView.addSubview(rightArrowButton)

    playButtonVStackView.heightAnchor.constraint(lessThanOrEqualTo: fragPlaybackBtnsView.heightAnchor).isActive = true

    fragPlaybackBtnsView.translatesAutoresizingMaskIntoConstraints = false
    fragPlaybackBtnsView.setContentHuggingPriority(.init(rawValue: 249), for: .vertical)  // hug superview more than default

    // Try to make sure the buttons' bounding boxes reach the full height, for activation
    // (their images will be limited by the width constraint & will stop scaling before this)
    let leftArrowHeightConstraint = leftArrowButton.heightAnchor.constraint(equalTo: fragPlaybackBtnsView.heightAnchor)
    leftArrowHeightConstraint.identifier = .init("leftArrowHeightConstraint")
    leftArrowHeightConstraint.priority = .defaultHigh
    leftArrowHeightConstraint.isActive = true
    let rightArrowHeightConstraint = rightArrowButton.heightAnchor.constraint(equalTo: fragPlaybackBtnsView.heightAnchor)
    rightArrowHeightConstraint.identifier = .init("rightArrowHeightConstraint")
    rightArrowHeightConstraint.priority = .defaultHigh
    rightArrowHeightConstraint.isActive = true

    // Video controllers and timeline indicators should not flip in a right-to-left language.
    fragPlaybackBtnsView.userInterfaceLayoutDirection = .leftToRight

    let playBtnVertOffsetConstraint = playButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    playBtnVertOffsetConstraint.isActive = true

    let playBtnHorizOffsetConstraint = playButtonVStackView.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor)
    playBtnHorizOffsetConstraint.isActive = true

    speedLabel.topAnchor.constraint(equalTo: fragPlaybackBtnsView.topAnchor).isActive = true

    fragPlaybackBtnsWidthConstraint = fragPlaybackBtnsView.widthAnchor.constraint(equalToConstant: oscGeo.totalPlayControlsWidth)
    fragPlaybackBtnsWidthConstraint.identifier = .init("fragPlaybackBtnsWidthConstraint")
    fragPlaybackBtnsWidthConstraint.isActive = true

    leftArrowBtnHorizOffsetConstraint = leftArrowButton.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor,
                                                                                 constant: oscGeo.leftArrowOffsetX)
    leftArrowBtnHorizOffsetConstraint.identifier = .init("leftArrowBtnHorizOffsetConstraint")
    leftArrowBtnHorizOffsetConstraint.isActive = true

    arrowBtnWidthConstraint = leftArrowButton.widthAnchor.constraint(equalToConstant: oscGeo.arrowIconWidth)
    arrowBtnWidthConstraint.identifier = .init("arrowBtnWidthConstraint")
    arrowBtnWidthConstraint.isActive = true

    rightArrowBtnHorizOffsetConstraint = rightArrowButton.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor,
                                                                                   constant: oscGeo.rightArrowOffsetX)
    rightArrowBtnHorizOffsetConstraint.identifier = .init("rightArrowBtnHorizOffsetConstraint")
    rightArrowBtnHorizOffsetConstraint.isActive = true

    // Left & Right arrow buttons are always same size
    let arrowBtnsEqualWidthConstraint = leftArrowButton.widthAnchor.constraint(equalTo: rightArrowButton.widthAnchor, multiplier: 1)
    arrowBtnsEqualWidthConstraint.identifier = .init("arrowBtnsEqualWidthConstraint")
    arrowBtnsEqualWidthConstraint.isActive = true

    let leftArrowBtnVertOffsetConstraint = leftArrowButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    leftArrowBtnVertOffsetConstraint.isActive = true
    let rightArrowBtnVertOffsetConstraint = rightArrowButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    rightArrowBtnVertOffsetConstraint.isActive = true
  }

  private func initAlbumArtView() {
    defaultAlbumArtView.wantsLayer = true
    defaultAlbumArtView.isHidden = true
    defaultAlbumArtView.layer?.contents = #imageLiteral(resourceName: "default-album-art")
    viewportView.addSubview(defaultAlbumArtView)

    defaultAlbumArtView.translatesAutoresizingMaskIntoConstraints = false

    // Add 1:1 aspect ratio constraint
    let aspectConstraint = defaultAlbumArtView.widthAnchor.constraint(equalTo: defaultAlbumArtView.heightAnchor, multiplier: 1)
    aspectConstraint.priority = .defaultHigh
    aspectConstraint.isActive = true
    // Always fill superview
    let widthGE = defaultAlbumArtView.widthAnchor.constraint(greaterThanOrEqualTo: viewportView.widthAnchor)
    widthGE.priority = .defaultHigh
    widthGE.isActive = true
    let heightGE = defaultAlbumArtView.heightAnchor.constraint(greaterThanOrEqualTo: viewportView.heightAnchor)
    heightGE.priority = .defaultHigh
    heightGE.isActive = true
    let widthEq = defaultAlbumArtView.widthAnchor.constraint(equalTo: viewportView.widthAnchor)
    widthEq.priority = .defaultLow
    widthEq.isActive = true
    let heightEq = defaultAlbumArtView.heightAnchor.constraint(equalTo: viewportView.heightAnchor)
    heightEq.priority = .defaultLow
    heightEq.isActive = true
    // Center in superview
    defaultAlbumArtView.centerXAnchor.constraint(equalTo: viewportView.centerXAnchor).isActive = true
    defaultAlbumArtView.centerYAnchor.constraint(equalTo: viewportView.centerYAnchor).isActive = true
  }

  static func buildScreenMap() -> [UInt32 : ScreenMeta] {
    let newMap = NSScreen.screens.map{ScreenMeta.from($0)}.reduce(Dictionary<UInt32, ScreenMeta>(), {(dict, screenMeta) in
      var dict = dict
      dict[screenMeta.displayID] = screenMeta
      _ = Logger.getOrCreatePII(for: screenMeta.name)
      return dict
    })
    Logger.log("Built screen meta: \(newMap.values)", level: .verbose)
    return newMap
  }

  /// Returns the position in seconds for the given percent of the total duration of the video the percentage represents.
  ///
  /// The number of seconds returned must be considered an estimate that could change. The duration of the video is obtained from
  /// the [mpv](https://mpv.io/manual/stable/) `duration` property. The documentation for this property cautions that
  /// mpv is not always able to determine the duration and when it does return a duration it may be an estimate. If the duration is
  /// unknown this method will fallback to using the current playback position, if that is known. Otherwise this method will return zero.
  /// - Parameter percent: Position in the video as a percentage of the duration.
  /// - Returns: The position in the video the given percentage represents.
  private func percentToSeconds(_ percent: Double) -> Double {
    if let duration = player.info.playbackDurationSec {
      return duration * percent / 100
    } else if let position = player.info.playbackPositionSec {
      return position * percent / 100
    } else {
      return 0
    }
  }

  /// When entering "windowed" mode (either from initial load, PIP, or music mode), call this to add/return `videoView`
  /// to this window. Will do nothing if it's already there.
  func addVideoViewToWindow() {
    guard let window else { return }
    do {
      let hasOpenGL = player.mpv.lockAndSetOpenGLContext()
      defer {
        if hasOpenGL {
          player.mpv.unlockOpenGLContext()
        }
      }
      videoView.$isUninited.withLock() { isUninited in
        guard !viewportView.subviews.contains(videoView) else { return }
        player.log.verbose("Adding videoView to viewportView, screenScaleFactor: \(window.screenScaleFactor)")
        /// Make sure `defaultAlbumArtView` stays above `videoView`
        viewportView.addSubview(videoView, positioned: .below, relativeTo: defaultAlbumArtView)
      }
    }
    // Screen may have changed. Refresh:
    videoView.refreshAll()
    /// Add constraints. These get removed each time `videoView` changes superviews.
    videoView.translatesAutoresizingMaskIntoConstraints = false
    if !player.info.isRestoring {  // this can mess up music mode restore
      let geo = currentLayout.mode == .musicMode ? musicModeGeo.toPWinGeometry() : windowedModeGeo
      videoView.apply(geo)
    }
  }

  /** Set material for OSC and title bar */
  func applyThemeMaterial() {
    guard let window else { return }

    let theme: Preference.Theme = Preference.enum(for: .themeMaterial)
    let newAppearance = NSAppearance(iinaTheme: theme)
    window.appearance = newAppearance

    // Change to appearance above does not take effect until this task completes. Enqueue a new task to run after this one.
    DispatchQueue.main.async { [self] in
      (newAppearance ?? window.effectiveAppearance).applyAppearanceFor {
        thumbnailPeekView.refreshColors()
      }
    }
  }

  func updateUseLegacyFullScreen() {
    let oldLayout = currentLayout
    if !oldLayout.isFullScreen {
      DispatchQueue.main.async { [self] in
        resetCollectionBehavior()
      }
    }
    // Exit from legacy FS only. Native FS will fail if not the active space
    guard oldLayout.isLegacyFullScreen else { return }
    let outputLayoutSpec = LayoutSpec.fromPreferences(fillingInFrom: oldLayout.spec)
    if oldLayout.spec.isLegacyStyle != outputLayoutSpec.isLegacyStyle {
      DispatchQueue.main.async { [self] in
        log.verbose("User toggled legacy FS pref to \(outputLayoutSpec.isLegacyStyle.yesno) while in FS. Will try to exit FS")
        exitFullScreen()
      }
    }
  }

  func updateTitleBarAndOSC() {
    animationPipeline.submitInstantTask { [self] in
      let oldLayout = currentLayout
      let newLayoutSpec = LayoutSpec.fromPreferences(fillingInFrom: oldLayout.spec)
      buildLayoutTransition(named: "UpdateTitleBarAndOSC", from: oldLayout, to: newLayoutSpec,
                            totalStartingDuration: IINAAnimation.DefaultDuration * 0.5,
                            totalEndingDuration: IINAAnimation.DefaultDuration * 0.5,
                            thenRun: true)
    }
  }

  func restoreFromMiscWindowBools(_ priorState: PlayerSaveState) {
    let isOnTop = priorState.bool(for: .isOnTop) ?? false
    setWindowFloatingOnTop(isOnTop, updateOnTopStatus: true)

    guard let stateString = priorState.string(for: .miscWindowBools) else { return }

    let splitted: [String] = stateString.split(separator: ",").map{String($0)}
    guard splitted.count >= 5,
       let isMiniaturized = Bool.yn(splitted[0]),
       let isHidden = Bool.yn(splitted[1]),
       let isInPip = Bool.yn(splitted[2]),
       let isWindowMiniaturizedDueToPip = Bool.yn(splitted[3]),
          let isPausedPriorToInteractiveMode = Bool.yn(splitted[4]) else {
      log.error("Failed to restore property \(PlayerSaveState.PropName.miscWindowBools.rawValue.quoted): could not parse \(stateString.quoted)")
      return
    }

    if !isMiniaturized && !isWindowMiniaturizedDueToPip {
      // Hide window during init. When done, showWindow will be called
      log.verbose("Ordering out window while restoring")
      window!.orderOut(self)
    }

    // Process PIP options first, to make sure it's not miniturized due to PIP
    if isInPip {
      let pipOption: Preference.WindowBehaviorWhenPip
      if isHidden {  // currently this will only be true due to PIP
        pipOption = .hide
      } else if isWindowMiniaturizedDueToPip {
        pipOption = .minimize
      } else {
        pipOption = .doNothing
      }
      // Run in queue to avert race condition with window load
      animationPipeline.submitInstantTask({ [self] in
        enterPIP(usePipBehavior: pipOption)
      })
    } else if isMiniaturized {
      // Not in PIP, but miniturized
      // Run in queue to avert race condition with window load
      animationPipeline.submitInstantTask({ [self] in
        window?.miniaturize(nil)
      })
    }
    if isPausedPriorToInteractiveMode {
      self.isPausedPriorToInteractiveMode = isPausedPriorToInteractiveMode
    }
  }

  // MARK: - Key events

  override func keyDown(with event: NSEvent) {
    let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
    let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)
    log.verbose("KEYDOWN: \(normalizedKeyCode.quoted)")

    PluginInputManager.handle(
      input: normalizedKeyCode, event: .keyDown, player: player,
      arguments: keyEventArgs(event), handler: { [self] in
        if let keyBinding = player.bindingController.matchActiveKeyBinding(endingWith: event) {

          guard !keyBinding.isIgnored else {
            // if "ignore", just swallow the event. Do not forward; do not beep
            log.verbose("Binding is ignored for key: \(keyCode.quoted)")
            return true
          }

          return handleKeyBinding(keyBinding)
        }
        return false
      }, defaultHandler: {
        // invalid key: beep if cmd failed
        super.keyDown(with: event)
      })
  }

  // Note: If a KeyUp appears without a KeyDown, this indicates the keypress triggered a menu item!
  override func keyUp(with event: NSEvent) {
    let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
    let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)
    log.verbose("KEYUP: \(normalizedKeyCode.quoted)")

    PluginInputManager.handle(
      input: normalizedKeyCode, event: .keyUp, player: player,
      arguments: keyEventArgs(event), defaultHandler: {
        // invalid key
        super.keyUp(with: event)
      })
  }

  // Returns true if handled
  @discardableResult
  func handleKeyBinding(_ keyBinding: KeyMapping) -> Bool {
    if let menuItem = keyBinding.menuItem, let action = menuItem.action {
      log.verbose("Key binding is attached to menu item: \(menuItem.title.quoted) but was not handled by MenuController. Call it manually")
      NSApp.sendAction(action, to: self, from: menuItem)
      return true
    }

    // Some script bindings will draw to the video area. We don't know which will, but
    // if the DisplayLink is not active the updates will not be displayed.
    // So start the DisplayLink temporily if not already running:
    forceDraw()

    if keyBinding.isIINACommand {
      // - IINA command
      if let iinaCommand = IINACommand(rawValue: keyBinding.rawAction) {
        handleIINACommand(iinaCommand)
        return true
      } else {
        log.error("Unrecognized IINA command: \(keyBinding.rawAction.quoted)")
        return false
      }
    } else {
      // - mpv command
      let returnValue: Int32
      // execute the command
      switch keyBinding.action.first! {

      case MPVCommand.abLoop.rawValue:
        abLoop()
        returnValue = 0

      case MPVCommand.quit.rawValue:
        // Initiate application termination. AppKit requires this be done from the main thread,
        // however the main dispatch queue must not be used to avoid blocking the queue as per
        // instructions from Apple. IINA must support quitting being initiated by mpv as the user
        // could use mpv's IPC interface to send the quit command directly to mpv. However the
        // shutdown sequence is cleaner when initiated by IINA, so we do not send the quit command
        // to mpv and instead trigger the normal app termination sequence.
        RunLoop.main.perform(inModes: [.common]) {
          if !AppDelegate.shared.isTerminating {
            NSApp.terminate(nil)
          }
        }
        returnValue = 0

      case MPVCommand.screenshot.rawValue:
        return player.screenshot(fromKeyBinding: keyBinding)
        
      default:
        returnValue = player.mpv.command(rawString: keyBinding.rawAction)
      }
      if returnValue == 0 {
        return true
      } else {
        Logger.log("Return value \(returnValue) when executing key command \(keyBinding.rawAction)", level: .error)
        return false
      }
    }
  }

  private func handleIINACommand(_ cmd: IINACommand) {
    switch cmd {
    case .openFile:
      AppDelegate.shared.showOpenFileWindow(isAlternativeAction: false)
    case .openURL:
      AppDelegate.shared.openURL(self)
    case .flip:
      menuToggleFlip(.dummy)
    case .mirror:
      menuToggleMirror(.dummy)
    case .saveCurrentPlaylist:
      menuSavePlaylist(.dummy)
    case .deleteCurrentFile:
      menuDeleteCurrentFile(.dummy)
    case .findOnlineSubs:
      menuFindOnlineSub(.dummy)
    case .saveDownloadedSub:
      saveDownloadedSub(.dummy)
    default:
      break
    }
  }

  fileprivate func keyEventArgs(_ event: NSEvent) -> [[String: Any]] {
    return [[
      "x": event.locationInWindow.x,
      "y": event.locationInWindow.y,
      "isRepeat": event.isARepeat
    ] as [String : Any]]
  }

  // MARK: - Window delegate: Open / Close

  override func openWindow(_ sender: Any?) {
    animationPipeline.submitInstantTask({ [self] in
      _openWindow()
    })
  }

  func _openWindow() {
    guard let window = self.window, let cv = window.contentView else { return }

    log.verbose("PlayerWindow openWindow starting")

    // Must workaround an AppKit defect in some versions of macOS. This defect is known to exist in
    // Catalina and Big Sur. The problem was not reproducible in early versions of Monterey. It
    // reappeared in Ventura. The status of other versions of macOS is unknown, however the
    // workaround should be safe to apply in any version of macOS. The problem was reported in
    // issues #4229, #3159, #3097 and #3253. The titles of open windows shown in the "Window" menu
    // are automatically managed by the AppKit framework. To improve performance PlayerCore caches
    // and reuses player instances along with their windows. This technique is valid and recommended
    // by Apple. But in some versions of macOS, if a window is reused the framework will display the
    // title first used for the window in the "Window" menu even after IINA has updated the title of
    // the window. This problem can also be seen when right-clicking or control-clicking the IINA
    // icon in the dock. As a workaround reset the window's title to "Window" before it is reused.
    // This is the default title AppKit assigns to a window when it is first created. Surprising and
    // rather disturbing this works as a workaround, but it does.
    window.title = "Window"

    // start tracking mouse event
    if cv.trackingAreas.isEmpty {
      cv.addTrackingArea(NSTrackingArea(rect: cv.bounds,
                                        options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                        owner: self, userInfo: [TrackingArea.key: TrackingArea.playerWindow]))
    }
    if playSlider.trackingAreas.isEmpty {
      playSlider.addTrackingArea(NSTrackingArea(rect: playSlider.bounds,
                                                options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                                owner: self, userInfo: [TrackingArea.key: TrackingArea.playSlider]))
    }
    // Track the thumbs on the progress bar representing the A-B loop points and treat them as part
    // of the slider.
    if playSlider.abLoopA.trackingAreas.count <= 1 {
      playSlider.abLoopA.addTrackingArea(NSTrackingArea(rect: playSlider.abLoopA.bounds, options:  [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: [TrackingArea.key: TrackingArea.playSlider]))
    }
    if playSlider.abLoopB.trackingAreas.count <= 1 {
      playSlider.abLoopB.addTrackingArea(NSTrackingArea(rect: playSlider.abLoopB.bounds, options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: [TrackingArea.key: TrackingArea.playSlider]))
    }

    // truncate middle for title
    if let attrTitle = titleTextField?.attributedStringValue.mutableCopy() as? NSMutableAttributedString, attrTitle.length > 0 {
      let p = attrTitle.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSMutableParagraphStyle
      p.lineBreakMode = .byTruncatingMiddle
      attrTitle.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: attrTitle.length))
    }

    resetCollectionBehavior()
    updateBufferIndicatorView()
    updateOSDPosition()

    addObservers()

    if let priorState = player.info.priorState {
      restoreFromMiscWindowBools(priorState)
    }

    /// Do this *after* `restoreFromMiscWindowBools` call
    if window.isMiniaturized {
      Preference.UIState.windowsMinimized.insert(window.savedStateName)
    } else {
      Preference.UIState.windowsOpen.insert(window.savedStateName)
    }

    if !player.info.isRestoring {
      AppDelegate.shared.initialWindow.closePriorToOpeningPlayerWindow()
    }

    log.verbose("PlayerWindow openWindow done")
    if let currentPlayback = player.info.currentPlayback, currentPlayback.isNetworkResource {
      // Don't wait for load for network stream; open immediately & show loading msg
      player.mpv.queue.async { [self] in
        log.verbose("Current playback is network resource; applying VideoGeometry now")
        applyVideoGeoAtFileOpen(currentPlayback: currentPlayback, player.info.currentMediaAudioStatus)
      }
    }
  }

  override func showWindow(_ sender: Any?) {
    guard player.state.isNotYet(.stopping) else {
      log.verbose("Aborting showWindow - player is stopping")
      return
    }
    log.verbose("Showing PlayerWindow")
    super.showWindow(sender)

    /// Need this as a kludge to ensure it runs after tasks in `applyVideoGeoTransform`
    DispatchQueue.main.async { [self] in
      var animationTasks: [IINAAnimation.Task] = []

      animationTasks.append(.instantTask { [self] in
        refreshKeyWindowStatus()
        // Need to call this here, or else when opening directly to fullscreen, window title is just "Window"
        updateTitle()
        window?.isExcludedFromWindowsMenu = false
        forceDraw()  // needed if restoring while paused
      })

      animationTasks += pendingVideoGeoUpdateTasks
      pendingVideoGeoUpdateTasks = []

      animationTasks.append(.instantTask { [self] in
        // Make sure to save after opening (possibly new) window
        player.saveState()
        // Especially need to save the updated windows list!
        // At launch, any unreferenced PWin entries will be deleted from prefs
        Preference.UIState.saveCurrentOpenWindowList()
      })

      animationPipeline.submit(animationTasks)

      player.mpv.queue.async { [self] in
        if player.pendingResumeWhenShowingWindow {
          player.pendingResumeWhenShowingWindow = false
          player.mpv.setFlag(MPVOption.PlaybackControl.pause, false)
        }
      }
    }
  }

  /// Do not use the offical `NSWindowDelegate` method. This method will be called by the global window listener.
  func windowWillClose() {
    log.verbose("Window will close")
    defer {
      player.events.emit(.windowWillClose)
    }

    co.removeObservers()

    // Close PIP
    if pipStatus == .inPIP {
      exitPIP()
    }

    if currentLayout.isLegacyFullScreen {
      updatePresentationOptionsForLegacyFullScreen(entering: false)
    }

    // Stop playing. This will save state if configured to do so:
    player.stop()

    guard !AppDelegate.shared.isTerminating else { return }
    
    isInitialSizeDone = false  // reset for reopen

    // stop tracking mouse event
    if let window, let contentView = window.contentView {
      contentView.trackingAreas.forEach(contentView.removeTrackingArea)
    }
    playSlider.trackingAreas.forEach(playSlider.removeTrackingArea)

    hideOSD(immediately: true)

    // Reset state flags
    isWindowMiniturized = false
    player.overrideAutoMusicMode = false

    /// Use `!player.info.isFileLoadedAndSized` to prevent saving if there was an error loading video
    if player.info.isFileLoadedAndSized {
      /// Prepare window for possible reuse: restore default geometry, close sidebars, etc.
      if currentLayout.mode == .musicMode {
        musicModeGeo = musicModeGeoForCurrentFrame()
      } else if currentLayout.mode.isWindowed {
        // Update frame since it may have moved
        windowedModeGeo = windowedGeoForCurrentFrame()
      }

      // CLOSE SIDEBARS for reopen
      let currentLayout = currentLayout
      let newLayoutSpec = currentLayout.spec.clone(leadingSidebar: currentLayout.leadingSidebar.clone(visibility: .hide),
                                               trailingSidebar: currentLayout.trailingSidebar.clone(visibility: .hide))
      let resetTransition = buildLayoutTransition(named: "ResetWindowOnClose", from: currentLayout, to: newLayoutSpec, totalStartingDuration: 0, totalEndingDuration: 0)
      // Just like at window restore, do all the layout in one block
      animationPipeline.submit(.instantTask { [self] in
        do {
          for task in resetTransition.tasks {
            try task.runFunc()
          }

          // The user may expect both to be updated
          PlayerWindowController.windowedModeGeoLastClosed = windowedModeGeo
          PlayerWindowController.musicModeGeoLastClosed = musicModeGeo
        } catch {
          log.error("Failed to run reset layout tasks: \(error)")
        }
      })
    }

    if player.info.isRestoring {
      log.debug("Discarding unfinished restore of window")
      // May not have finishing restoring when user closes. Make sure to clean up here
      player.info.priorState = nil
      player.info.isRestoring = false
    }

    player.mpv.queue.async { [self] in
      player.info.currentPlayback = nil
      osd.clearQueuedOSDs()
    }
  }

  /// Hide menu bar & dock if current window is in legacy full screen.
  /// Show menu bar & dock if current window is not in full screen (either legacy or native).
  func updatePresentationOptionsForLegacyFullScreen(entering: Bool? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))

    // Use currentLayout if not explicitly specified
    var isEnteringLegacyFS = entering ?? currentLayout.isLegacyFullScreen
    if let window, window.isAnotherWindowInFullScreen {
      isEnteringLegacyFS = true  // override if still in FS in another window
    }

    guard !NSApp.presentationOptions.contains(.fullScreen) else {
      log.error("Cannot add presentation options for legacy full screen: window is already in full screen!")
      return
    }

    log.verbose("Updating presentation options for legacyFS: \(isEnteringLegacyFS ? "entering" : "exiting")")
    if isEnteringLegacyFS {
      // Unfortunately, the check for native FS can return false if the window is in full screen but not the active space.
      // Fall back to checking this one
      guard !NSApp.presentationOptions.contains(.hideMenuBar) else {
        log.error("Cannot add presentation options for legacy full screen: option .hideMenuBar already present! Will try to avoid crashing")
        return
      }
      NSApp.presentationOptions.insert(.autoHideMenuBar)
      NSApp.presentationOptions.insert(.autoHideDock)
    } else {
      NSApp.presentationOptions.remove(.autoHideMenuBar)
      NSApp.presentationOptions.remove(.autoHideDock)
    }
  }

  // MARK: - Window delegate: Full screen

  func customWindowsToEnterFullScreen(for window: NSWindow) -> [NSWindow]? {
    return [window]
  }

  func customWindowsToExitFullScreen(for window: NSWindow) -> [NSWindow]? {
    return [window]
  }

  func windowWillEnterFullScreen(_ notification: Notification) {
  }

  func window(_ window: NSWindow, startCustomAnimationToEnterFullScreenOn screen: NSScreen, withDuration duration: TimeInterval) {
    animateEntryIntoFullScreen(withDuration: IINAAnimation.NativeFullScreenTransitionDuration, isLegacy: false)
  }

  // Animation: Enter FullScreen
  private func animateEntryIntoFullScreen(withDuration duration: TimeInterval, isLegacy: Bool) {
    let oldLayout = currentLayout

    let newMode: PlayerWindowMode = oldLayout.mode == .windowedInteractive ? .fullScreenInteractive : .fullScreen
    log.verbose("Animating \(duration)s entry from \(oldLayout.mode) → \(isLegacy ? "legacy " : "")\(newMode)")
    // May be in interactive mode, with some panels hidden. Honor existing layout but change value of isFullScreen
    let fullscreenLayout = LayoutSpec.fromPreferences(andMode: newMode, isLegacyStyle: isLegacy, fillingInFrom: oldLayout.spec)

    buildLayoutTransition(named: "Enter\(isLegacy ? "Legacy" : "")FullScreen", from: oldLayout, to: fullscreenLayout,
                          totalStartingDuration: 0, totalEndingDuration: duration, thenRun: true)
  }

  func window(_ window: NSWindow, startCustomAnimationToExitFullScreenWithDuration duration: TimeInterval) {
    if !AccessibilityPreferences.motionReductionEnabled {  /// see note in `windowDidExitFullScreen()`
      animateExitFromFullScreen(withDuration: duration, isLegacy: false)
    }
  }

  /// Workaround for Apple quirk. When exiting fullscreen, MacOS uses a relatively slow animation to open the Dock and fade in other windows.
  /// It appears we cannot call `setFrame()` (or more precisely, we must make sure any `setFrame()` animation does not end) until after this
  /// animation completes, or the window size will be incorrectly set to the same size of the screen.
  /// There does not appear to be any similar problem when entering fullscreen.
  func windowDidExitFullScreen(_ notification: Notification) {
    if AccessibilityPreferences.motionReductionEnabled {
      animateExitFromFullScreen(withDuration: IINAAnimation.FullScreenTransitionDuration, isLegacy: false)
    } else {
      animationPipeline.submitInstantTask { [self] in
        // Kludge/workaround for race condition when exiting native FS to native windowed mode
        updateTitle()
      }
    }

  }

  // Animation: Exit Full Screen
  private func animateExitFromFullScreen(withDuration duration: TimeInterval, isLegacy: Bool) {
    // If a window is closed while in full screen mode (control-w pressed) AppKit will still call
    // this method. Because windows are tied to player cores and cores are cached and reused some
    // processing must be performed to leave the window in a consistent state for reuse. However
    // the windowWillClose method will have initiated unloading of the file being played. That
    // operation is processed asynchronously by mpv. If the window is being closed due to IINA
    // quitting then mpv could be in the process of shutting down. Must not access mpv while it is
    // asynchronously processing stop and quit commands.
    guard !isClosing else { return }

    let oldLayout = currentLayout

    let nextMode: PlayerWindowMode
    if oldLayout.mode == .fullScreenInteractive {
      nextMode = .windowedInteractive
    } else {
      nextMode = .windowed
    }
    let windowedLayoutSpec = LayoutSpec.fromPreferences(andMode: nextMode, fillingInFrom: oldLayout.spec)

    log.verbose("Animating \(duration)s exit from \(isLegacy ? "legacy " : "")\(oldLayout.mode) → \(windowedLayoutSpec.mode)")
    assert(!windowedLayoutSpec.isFullScreen, "Cannot exit full screen into mode \(windowedLayoutSpec.mode)! Spec: \(windowedLayoutSpec)")
    /// Split the duration between `openNewPanels` animation and `fadeInNewViews` animation
    let exitFSTransition = buildLayoutTransition(named: "Exit\(isLegacy ? "Legacy" : "")FullScreen",
                                                 from: oldLayout, to: windowedLayoutSpec,
                                                 totalStartingDuration: 0, totalEndingDuration: duration)

    if modeToSetAfterExitingFullScreen == .musicMode {
      let windowedLayout = LayoutState.buildFrom(windowedLayoutSpec)
      let geo = geo.clone(windowed: exitFSTransition.outputGeometry)
      let enterMusicModeTransition = buildTransitionToEnterMusicMode(from: windowedLayout, geo)
      animationPipeline.submit(exitFSTransition.tasks)
      animationPipeline.submit(enterMusicModeTransition.tasks)
      modeToSetAfterExitingFullScreen = nil
    } else {
      animationPipeline.submit(exitFSTransition.tasks)
    }
  }

  func toggleWindowFullScreen() {
    log.verbose("ToggleWindowFullScreen")
    let layout = currentLayout

    switch layout.mode {
    case .windowed, .windowedInteractive:
      enterFullScreen()
    case .fullScreen, .fullScreenInteractive:
      exitFullScreen()
    case .musicMode:
      enterFullScreen()
    }
  }

  func enterFullScreen(legacy: Bool? = nil) {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }
    let isLegacy: Bool = legacy ?? Preference.bool(for: .useLegacyFullScreen)
    let isFullScreen = NSApp.presentationOptions.contains(.fullScreen)
    log.verbose("EnterFullScreen called. Legacy: \(isLegacy.yn), isNativeFullScreenNow: \(isFullScreen.yn)")

    if isLegacy {
      animationPipeline.submitInstantTask({ [self] in
        animateEntryIntoFullScreen(withDuration: IINAAnimation.FullScreenTransitionDuration, isLegacy: true)
      })
    } else if !isFullScreen {
      /// `collectionBehavior` *must* be correct or else `toggleFullScreen` may do nothing!
      resetCollectionBehavior()
      window.toggleFullScreen(self)
    }
  }

  func exitFullScreen() {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }

    let isLegacyFS = currentLayout.isLegacyFullScreen

    if isLegacyFS {
      log.verbose("ExitFullScreen called, legacy=\(isLegacyFS.yn)")
      animationPipeline.submitInstantTask({ [self] in
        // If "legacy" pref was toggled while in fullscreen, still need to exit native FS
        animateExitFromFullScreen(withDuration: IINAAnimation.FullScreenTransitionDuration, isLegacy: true)
      })
    } else {
      let isActuallyNativeFullScreen = NSApp.presentationOptions.contains(.fullScreen)
      log.verbose("ExitFullScreen called, legacy=\(isLegacyFS.yn), isNativeFullScreenNow=\(isActuallyNativeFullScreen.yn)")
      guard isActuallyNativeFullScreen else { return }
      window.toggleFullScreen(self)
    }

  }

  /// Called after window is resized from (almost) any cause. Will be called many times during every call to `window.setFrame()`.
  /// Do not use `windowDidEndLiveResize`! It is unreliable. Use `windowDidResize` instead.
  /// Not currently used!
//  func windowDidResize(_ notification: Notification) {
    // Do not want to trigger this during layout transition. It will mess up the intended viewport size.
//    guard !player.info.isRestoring, !isClosing, !isAnimatingLayoutTransition, !isMagnifying else { return }
//    log.verbose("Win-DID-Resize mode=\(currentLayout.mode) frame=\(window?.frame.debugDescription ?? "nil")")

  // MARK: - Window Delegate: window move, screen changes

  /// This does not appear to be called anymore in MacOS 14.5...
  /// Make sure to duplicate its functionality in `windowDidChangeScreenParameters`
  func windowDidChangeBackingProperties(_ notification: Notification) {
    log.verbose("WindowDidChangeBackingProperties received")
    videoView.refreshContentsScale()
    // Do not allow MacOS to change the window size when changing screen
    denyNextWindowResize = true
  }

  func windowDidChangeOcclusionState(_ notification: Notification) {
    log.verbose("WindowDidChangeOcclusionState received")
    assert(DispatchQueue.isExecutingIn(.main))
    forceDraw()
  }

  func colorSpaceDidChange(_ notification: Notification) {
    log.verbose("ColorSpaceDidChange received")
    videoView.refreshEdrMode()
  }

  // Note: this gets triggered by many unnecessary situations, e.g. several times each time full screen is toggled.
  func windowDidChangeScreen(_ notification: Notification) {
    var ticket: Int = 0
    $screenChangedTicketCounter.withLock {
      $0 += 1
      ticket = $0
    }
    // Do not allow MacOS to change the window size
    denyNextWindowResize = true

    // MacOS Sonoma sometimes blasts tons of these for unknown reasons. Attempt to prevent slowdown by de-duplicating
    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) { [self] in
      guard ticket == screenChangedTicketCounter else { return }
      guard let window = window, let screen = window.screen else { return }
      guard !isClosing else { return }

      let displayId = screen.displayId
      // Legacy FS work below can be very slow. Try to avoid if possible
      guard videoView.currentDisplay != displayId else {
        log.trace("WindowDidChangeScreen (tkt \(ticket)): no work needed; currentDisplayID \(displayId) is unchanged")
        return
      }

      let blackWindows = self.blackWindows
      if isFullScreen && Preference.bool(for: .blackOutMonitor) && blackWindows.compactMap({$0.screen?.displayId}).contains(displayId) {
        log.verbose("WindowDidChangeScreen: black windows contains window's displayId \(displayId); removing & regenerating black windows")
        // Window changed screen: adjust black windows accordingly
        removeBlackWindows()
        blackOutOtherMonitors()
      }

      animationPipeline.submitInstantTask({ [self] in
        log.verbose("WindowDidChangeScreen (tkt \(ticket)): screenFrame=\(screen.frame)")
        videoView.refreshAll()
        player.events.emit(.windowScreenChanged)
      })

      guard !player.info.isRestoring, !isAnimatingLayoutTransition else { return }

      animationPipeline.submitTask(timing: .easeInEaseOut, { [self] in
        let screenID = bestScreen.screenID

        /// Need to recompute legacy FS's window size so it exactly fills the new screen.
        /// But looks like the OS will try to reposition the window on its own and can't be stopped...
        /// Just wait until after it does its thing before calling `setFrame()`.
        if currentLayout.isLegacyFullScreen {
          let layout = currentLayout
          guard layout.isLegacyFullScreen else { return }  // check again now that we are inside animation
          log.verbose("WindowDidChangeScreen: updating legacy full screen window")
          let fsGeo = layout.buildFullScreenGeometry(inScreenID: screenID, video: geo.video)
          applyLegacyFSGeo(fsGeo)
          // Update screenID at least, so that window won't go back to other screen when exiting FS
          windowedModeGeo = windowedModeGeo.clone(screenID: screenID)
          player.saveState()
        } else if currentLayout.mode == .windowed {
          // Update windowedModeGeo with new window position & screen (but preserve previous size)
          let newWindowFrame = NSRect(origin: window.frame.origin, size: windowedModeGeo.windowFrame.size)
          windowedModeGeo = windowedModeGeo.clone(windowFrame: newWindowFrame, screenID: screenID)
        }
      })
    }
  }

  /// Can be:
  /// • A Screen was connected or disconnected
  /// • Dock visiblity was toggled
  /// • Menu bar visibility toggled
  /// • Adding or removing window style mask `.titled`
  /// • Sometimes called hundreds(!) of times while window is closing
  private func windowDidChangeScreenParameters(_ notification: Notification) {
    guard !isClosing else { return }

    var ticket: Int = 0
    $screenParamsChangedTicketCounter.withLock {
      $0 += 1
      ticket = $0
    }

    // MacOS Sonoma sometimes blasts tons of these for unknown reasons. Attempt to prevent slowdown by de-duplicating
    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) { [self] in
      guard ticket == screenParamsChangedTicketCounter else { return }

      let screens = PlayerWindowController.buildScreenMap()
      let screenIDs = screens.keys.sorted()
      let cachedScreenIDs = cachedScreens.keys.sorted()
      log.verbose("WndDidChangeScreenParams (tkt \(ticket)): screenIDs was \(cachedScreenIDs), is now \(screenIDs)")

      // Update the cached value
      cachedScreens = screens

      videoView.refreshAll()

      guard !player.info.isRestoring, !isAnimatingLayoutTransition else { return }

      // In normal full screen mode AppKit will automatically adjust the window frame if the window
      // is moved to a new screen such as when the window is on an external display and that display
      // is disconnected. In legacy full screen mode IINA is responsible for adjusting the window's
      // frame.
      // Use very short duration. This usually gets triggered at the end when entering fullscreen, when the dock and/or menu bar are hidden.
      animationPipeline.submitTask(duration: IINAAnimation.FullScreenTransitionDuration * 0.2, { [self] in
        let layout = currentLayout
        if layout.isLegacyFullScreen {
          guard layout.isLegacyFullScreen else { return }  // check again now that we are inside animation
          log.verbose("WndDidChangeScreenParams: updating legacy full screen window")
          let fsGeo = layout.buildFullScreenGeometry(in: bestScreen, video: geo.video)
          applyLegacyFSGeo(fsGeo)
        } else if layout.mode == .windowed {
          /// In certain corner cases (e.g., exiting legacy full screen after changing screens while in full screen),
          /// the screen's `visibleFrame` can change after `transition.outputGeometry` was generated and won't be known until the end.
          /// By calling `refit()` here, we can make sure the window is constrained to the up-to-date `visibleFrame`.
          let oldGeo = windowedModeGeo
          let newGeo = oldGeo.refit()
          guard !newGeo.hasEqual(windowFrame: oldGeo.windowFrame, videoSize: oldGeo.videoSize) else {
            log.verbose("WndDidChangeScreenParams: no change to windowFrame")
            return
          }
          log.verbose("WndDidChangeScreenParams: calling setFrame with wf=\(newGeo.windowFrame) vidSize=\(newGeo.videoSize)")
          player.window.setFrameImmediately(newGeo, notify: false)
        }
      })
    }
  }

  func windowDidMove(_ notification: Notification) {
    guard !isAnimating, !isAnimatingLayoutTransition, !isMagnifying, !player.info.isRestoring else { return }
    guard let window = window else { return }

    // We can get here if external calls from accessibility APIs change the window location.
    // Inserting a small delay seems to help to avoid race conditions as the window seems to need time to "settle"
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
      animationPipeline.submitInstantTask({ [self] in
        let layout = currentLayout
        if layout.isLegacyFullScreen {
          // MacOS (as of 14.0 Sonoma) sometimes moves the window around when there are multiple screens
          // and the user is changing focus between windows or apps. This can also happen if the user is using a third-party
          // window management app such as Amethyst. If this happens, move the window back to its proper place:
          let screen = bestScreen
          log.verbose("WindowDidMove: Updating legacy full screen window in response to unexpected windowDidMove to frame=\(window.frame), screen=\(screen.screenID.quoted)")
          let fsGeo = layout.buildFullScreenGeometry(in: bestScreen, video: geo.video)
          applyLegacyFSGeo(fsGeo)
        } else {
          player.saveState()
          player.events.emit(.windowMoved, data: window.frame)
        }
      })
    }
  }

  // MARK: - Window delegate: Active status

  func windowDidBecomeKey(_ notification: Notification) {
    animationPipeline.submitInstantTask { [self] in
      guard !isClosing else { return }

      if Preference.bool(for: .pauseWhenInactive) && isPausedDueToInactive {
        log.verbose("Window is key & isPausedDueToInactive=Y. Resuming playback")
        player.resume()
        isPausedDueToInactive = false
      }

      refreshKeyWindowStatus()
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    animationPipeline.submitInstantTask { [self] in
      // keyWindow is nil: The whole app is inactive
      // keyWindow is another PlayerWindow: Switched to another video window
      let otherAppWindow = NSApp.keyWindow
      let wholeAppIsInactive = otherAppWindow == nil
      let otherPlayerWindow = otherAppWindow?.windowController as? PlayerWindowController
      let anotherPlayerWindowIsActive = otherPlayerWindow != nil
      if wholeAppIsInactive || anotherPlayerWindowIsActive {
        if Preference.bool(for: .pauseWhenInactive), player.info.isPlaying {
          log.verbose("WindowDidResignKey: pausing cuz either wholeAppIsInactive (\(wholeAppIsInactive.yn)) or anotherPlayerWindowIsActive (\(anotherPlayerWindowIsActive.yn))")
          player.pause()
          isPausedDueToInactive = true
        }
      }
      
      refreshKeyWindowStatus()
    }
  }

  func refreshKeyWindowStatus() {
    animationPipeline.submitInstantTask { [self] in
      guard let window else { return }
      guard !isClosing else { return }

      if let customTitleBar {
        // The traffic light buttons should change to active/inactive
        customTitleBar.leadingTitleBarView.markButtonsDirty()
        customTitleBar.refreshTitle()
      }

      let isKey = window.isKeyWindow
      log.verbose("Window isKey: \(isKey.yn)")
      if isKey {
        PlayerCore.lastActive = player

        if RemoteCommandController.useSystemMediaControl {
          NowPlayingInfoManager.updateInfo(withTitle: true)
        }
        AppDelegate.shared.menuController?.updatePluginMenu()

        if isFullScreen && Preference.bool(for: .blackOutMonitor) {
          blackOutOtherMonitors()
        }

        if currentLayout.isLegacyFullScreen && window.level != .iinaFloating {
          log.verbose("Window is key: resuming legacy FS window")
          window.level = .iinaFloating
        }

        // If focus changed from a different window, need to recalculate the current bindings
        // so that this window's input sections are included and the other window's are not:
        AppInputConfig.rebuildCurrent()
      } else {
        /// Always restore window level from `floating` to `normal`, so other windows aren't blocked & cause confusion
        if currentLayout.isLegacyFullScreen && window.level != .normal {
          log.verbose("Window is not key: restoring legacy FS window level to normal")
          window.level = .normal
        }

        if Preference.bool(for: .blackOutMonitor) {
          removeBlackWindows()
        }
      }
    }
  }

  // Don't really care if window is main in IINA Advance; we care only if window is key,
  // because the key window is the active window in AppKit.
  // Fire events anyway to keep compatibility with upstream IINA.
  func windowDidBecomeMain(_ notification: Notification) {
    animationPipeline.submitInstantTask { [self] in
      player.events.emit(.windowMainStatusChanged, data: true)
      NotificationCenter.default.post(name: .iinaPlayerWindowChanged, object: true)
    }
  }

  func windowDidResignMain(_ notification: Notification) {
    animationPipeline.submitInstantTask { [self] in
      player.events.emit(.windowMainStatusChanged, data: false)
      NotificationCenter.default.post(name: .iinaPlayerWindowChanged, object: false)
    }
  }

  func windowWillMiniaturize(_ notification: Notification) {
    if Preference.bool(for: .pauseWhenMinimized), player.info.isPlaying {
      isPausedDueToMiniaturization = true
      player.pause()
    }
  }

  func windowDidMiniaturize(_ notification: Notification) {
    animationPipeline.submitInstantTask { [self] in
      log.verbose("Window did miniaturize")
      isWindowMiniturized = true
      if Preference.bool(for: .togglePipByMinimizingWindow) && !isWindowMiniaturizedDueToPip {
        enterPIP()
      }
      player.events.emit(.windowMiniaturized)
    }
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    animationPipeline.submitInstantTask { [self] in
      log.verbose("Window did deminiaturize")
      isWindowMiniturized = false
      if Preference.bool(for: .pauseWhenMinimized) && isPausedDueToMiniaturization {
        player.resume()
        isPausedDueToMiniaturization = false
      }
      if Preference.bool(for: .togglePipByMinimizingWindow) && !isWindowMiniaturizedDueToPip {
        exitPIP()
      }
      player.events.emit(.windowDeminiaturized)
    }
  }

  // MARK: - UI: Title

  @objc
  func updateTitle() {
    player.mpv.queue.async { [self] in
      _updateTitle()
    }
  }

  private func _updateTitle() {
    guard player.isActive else { return }
    guard let currentPlayback = player.info.currentPlayback else {
      log.verbose("Cannot update window title: currentPlayback is nil")
      return
    }

    let (mediaTitle, mediaAlbum, mediaArtist) = player.getMusicMetadata()

    DispatchQueue.main.async { [self] in
      guard let window else { return }
      let title: String
      if isInMiniPlayer {
        miniPlayer.loadIfNeeded()
        title = mediaTitle
        window.title = title
        miniPlayer.updateTitle(mediaTitle: mediaTitle, mediaAlbum: mediaAlbum, mediaArtist: mediaArtist)
      } else if player.info.isNetworkResource {
        title = player.getMediaTitle()
        window.title = title
      } else {
        window.representedURL = player.info.currentURL
        // Workaround for issue #3543, IINA crashes reporting:
        // NSInvalidArgumentException [NSNextStepFrame _displayName]: unrecognized selector
        // When running on an M1 under Big Sur and using legacy full screen.
        //
        // Changes in Big Sur broke the legacy full screen feature. The PlayerWindowController method
        // legacyAnimateToFullscreen had to be changed to get this feature working again. Under Big
        // Sur that method now calls "window.styleMask.remove(.titled)". Removing titled from the
        // style mask causes the AppKit method NSWindow.setTitleWithRepresentedFilename to trigger the
        // exception listed above. This appears to be a defect in the Cocoa framework. The window's
        // title can still be set directly without triggering the exception. The problem seems to be
        // isolated to the setTitleWithRepresentedFilename method, possibly only when running on an
        // Apple Silicon based Mac. Based on the Apple documentation setTitleWithRepresentedFilename
        // appears to be a convenience method. As a workaround for the issue directly set the window
        // title.
        //
        // This problem has been reported to Apple as:
        // "setTitleWithRepresentedFilename throws NSInvalidArgumentException: NSNextStepFrame _displayName"
        // Feedback number FB9789129
        title = currentPlayback.url.lastPathComponent
        window.setTitleWithRepresentedFilename(currentPlayback.url.path)
      }

      /// This call is needed when using custom window style, otherwise the window won't get added to the Window menu or the Dock.
      /// Oddly, there are 2 separate functions for adding and changing the item, but `addWindowsItem` has no effect if called more than once,
      /// while `changeWindowsItem` needs to be called if `addWindowsItem` was already called. To be safe, just call both.
      NSApplication.shared.addWindowsItem(window, title: title, filename: false)
      NSApplication.shared.changeWindowsItem(window, title: title, filename: false)

      if log.isTraceEnabled {
        log.trace("Updating window title to: \(title.pii.quoted)")
      }
      customTitleBar?.refreshTitle()
    }  // end DispatchQueue.main work item

  }

  // MARK: - UI: Interactive mode


  func enterInteractiveMode(_ mode: InteractiveMode) {
    let currentLayout = currentLayout
    // Especially needed to avoid duplicate transitions
    guard currentLayout.canEnterInteractiveMode else { return }

    player.mpv.queue.async { [self] in
      let videoGeo = geo.video
      let videoSizeRaw = videoGeo.videoSizeRaw

      log.verbose("Entering interactive mode: \(mode)")

      if videoGeo.codecRotation != 0 {
        log.warn("FIXME: Video codec rotation is not yet supported in interactive mode! Any selection chosen will be completely wrong!")
      }

      // TODO: use key binding interceptor to support ESC and ENTER keys for interactive mode

      let newVideoGeo: VideoGeometry
      if mode == .crop, let vf = videoGeo.cropFilter {
        log.error("Crop mode requested, but found an existing crop filter (\(vf.stringFormat.quoted)). Will remove it before entering")
        // A crop is already set. Need to temporarily remove it so that the whole video can be seen again,
        // so that a new crop can be chosen. But keep info from the old filter in case the user cancels.
        // Change this pre-emptively so that removeVideoFilter doesn't trigger a window geometry change
        player.info.videoFiltersDisabled[vf.label!] = vf
        newVideoGeo = videoGeo.clone(selectedCropLabel: AppData.noneCropIdentifier)
        if !player.removeVideoFilter(vf) {
          log.error("Failed to remove prev crop filter: (\(vf.stringFormat.quoted)) for some reason. Will ignore and try to proceed anyway")
        }
      } else {
        newVideoGeo = geo.video
      }
      // Save disabled crop video filter
      player.saveState()

      DispatchQueue.main.async { [self] in
        guard currentLayout.canEnterInteractiveMode else { return }
        var tasks: [IINAAnimation.Task] = []

        if let prevCropFilter = player.info.videoFiltersDisabled[Constants.FilterLabel.crop] {
          // Not yet in interactive mode, but the active crop was just disabled prior to entering it,
          // so that full video can be seen during interactive mode

          // FIXME: need to un-rotate while in interactive mode
          let prevCropBox = prevCropFilter.cropRect(origVideoSize: videoSizeRaw, flipY: true)
          log.verbose("EnterInteractiveMode: Uncropping video from cropRectRaw: \(prevCropBox) to videoSizeRaw: \(videoSizeRaw)")
          let newVideoAspect = videoSizeRaw.mpvAspect

          switch currentLayout.mode {
          case .windowed, .fullScreen:
            let oldVideoAspect = prevCropBox.size.mpvAspect
            // Scale viewport to roughly match window size
            let lockViewportToVideoSize = Preference.bool(for: .lockViewportToVideoSize)
            var uncroppedClosedBarsGeo = windowedGeoForCurrentFrame()
              .withResizedBars(outsideTop: 0, outsideTrailing: 0,
                               outsideBottom: 0, outsideLeading: 0,
                               insideTop: 0, insideTrailing: 0,
                               insideBottom: 0, insideLeading: 0,
                               video: newVideoGeo,
                               keepFullScreenDimensions: !lockViewportToVideoSize)

            if lockViewportToVideoSize {
              // Otherwise try to avoid shrinking the window too much if the aspect changes dramatically.
              // This heuristic seems to work ok
              let viewportSize = uncroppedClosedBarsGeo.viewportSize
              let aspectChangeFactor = newVideoAspect / oldVideoAspect
              let viewportSizeMultiplier = (aspectChangeFactor < 0) ? (1.0 / aspectChangeFactor) : aspectChangeFactor
              var newViewportSize = viewportSize * viewportSizeMultiplier

              // Calculate viewport size needed to satisfy min margins of interactive mode, then grow video at least as large
              let minViewportSizeIM = uncroppedClosedBarsGeo.minViewportSize(mode: .windowedInteractive)
              let minViewportSizeWindowed = CGSize.computeMinSize(withAspect: newVideoAspect,
                                                                  minWidth: minViewportSizeIM.width,
                                                                  minHeight: minViewportSizeIM.height)
              let minViewportMarginsIM = PWinGeometry.minViewportMargins(forMode: .windowedInteractive)
              newViewportSize = NSSize(width: max(newViewportSize.width + minViewportMarginsIM.totalWidth, minViewportSizeWindowed.width),
                                       height: max(newViewportSize.height + minViewportMarginsIM.totalHeight, minViewportSizeWindowed.height))

              log.verbose("EnterInteractiveMode: aspectChangeFactor:\(aspectChangeFactor), viewportSizeMultiplier: \(viewportSizeMultiplier), newViewportSize:\(newViewportSize)")
              uncroppedClosedBarsGeo = uncroppedClosedBarsGeo.scaleViewport(to: newViewportSize)
            } else {
              // If not locking viewport to video, just reuse viewport
              uncroppedClosedBarsGeo = uncroppedClosedBarsGeo.refit()
            }
            log.verbose("EnterInteractiveMode: Generated uncroppedGeo: \(uncroppedClosedBarsGeo)")

            if currentLayout.mode == .windowed {
              // TODO: integrate this task into LayoutTransition build
              let uncropDuration = IINAAnimation.CropAnimationDuration * 0.1
              tasks.append(IINAAnimation.Task(duration: uncropDuration, timing: .easeInEaseOut) { [self] in
                isAnimatingLayoutTransition = true  // tell window resize listeners to do nothing
                player.window.setFrameImmediately(uncroppedClosedBarsGeo)
              })
            }

            // supply an override for windowedModeGeo here, because it won't be set until the animation above executes
            let geoOverride = geo.clone(windowed: uncroppedClosedBarsGeo)
            tasks.append(contentsOf: buildTransitionToEnterInteractiveMode(.crop, geoOverride))

          default:
            assert(false, "Bad state! Invalid mode: \(currentLayout.spec.mode)")
            return
          }
        } else {
          tasks = buildTransitionToEnterInteractiveMode(mode)
        }

        animationPipeline.submit(tasks)
      }
    }
  }

  func buildTransitionToEnterInteractiveMode(_ mode: InteractiveMode, _ geo: GeometrySet? = nil) -> [IINAAnimation.Task] {
    let newMode: PlayerWindowMode = currentLayout.mode == .fullScreen ? .fullScreenInteractive : .windowedInteractive
    let interactiveModeLayout = currentLayout.spec.clone(mode: newMode, interactiveMode: mode)
    let startDuration = IINAAnimation.CropAnimationDuration * 0.5
    let endDuration = currentLayout.mode == .fullScreen ? startDuration * 0.5 : startDuration
    let transition = buildLayoutTransition(named: "EnterInteractiveMode", from: currentLayout, to: interactiveModeLayout,
                                           totalStartingDuration: startDuration, totalEndingDuration: endDuration, geo)
    return transition.tasks
  }

  /// Use `immediately: true` to exit without animation.
  /// This method can be run safely even if not in interactive mode
  func exitInteractiveMode(immediately: Bool = false, newVidGeo: VideoGeometry? = nil,  then doAfter: (() -> Void)? = nil) {
    animationPipeline.submitInstantTask({ [self] in
      let currentLayout = currentLayout

      var tasks: [IINAAnimation.Task] = []

      if currentLayout.isInteractiveMode {
        // This alters state in addtion to (maybe) generating a task
        tasks = exitInteractiveMode(immediately: immediately, newVidGeo: newVidGeo)
      }

      if let doAfter {
        tasks.append(IINAAnimation.Task({
          doAfter()
        }))
      }
      
      animationPipeline.submit(tasks)
    })
  }

  // Exits interactive mode, using animations.
  private func exitInteractiveMode(immediately: Bool, newVidGeo: VideoGeometry? = nil) -> [IINAAnimation.Task] {
    var tasks: [IINAAnimation.Task] = []

    var geoSet: GeometrySet? = nil
    // If these params are present and valid, then need to apply a crop
    if let cropController = cropSettingsView, let newVidGeo, let cropRect = newVidGeo.cropRect {

      log.verbose("Cropping video from videoSizeRaw: \(newVidGeo.videoSizeRaw), videoSizeScaled: \(cropController.cropBoxView.videoRect), cropRect: \(cropRect)")

      /// Must update `windowedModeGeo` outside of animation task!
      // this works for full screen modes too
      assert(currentLayout.isInteractiveMode, "CurrentLayout is not in interactive mode: \(currentLayout)")
      let winGeoUpdated = windowedGeoForCurrentFrame()  // not even needed if in full screen
      let currentIMGeo = currentLayout.buildGeometry(windowFrame: winGeoUpdated.windowFrame,
                                                     screenID: winGeoUpdated.screenID,
                                                     video: geo.video)
      let newIMGeo = currentIMGeo.cropVideo(using: newVidGeo)
      if currentLayout.mode == .windowedInteractive {
        geoSet = buildGeoSet(windowed: newIMGeo)
      }

      // Crop animation:
      let cropAnimationDuration = immediately ? 0 : IINAAnimation.CropAnimationDuration * 0.005
      tasks.append(IINAAnimation.Task(duration: cropAnimationDuration, timing: .default) { [self] in
        player.window.setFrameImmediately(newIMGeo)

        // Add the crop filter now, if applying crop. The timing should mostly add up and look like it cut out a piece of the whole.
        // It's not perfect but better than before
        if let cropController = cropSettingsView {
          let newCropFilter = MPVFilter.crop(w: cropController.cropw, h: cropController.croph, x: cropController.cropx, y: cropController.cropy)
          /// Set the filter. This will result in `applyVideoGeoTransform` getting called, which will trigger an exit from interactive mode.
          /// But that task can only happen once we return and relinquish the main queue.
          _ = player.addVideoFilter(newCropFilter)
        }

        // Fade out cropBox selection rect
        cropController.cropBoxView.isHidden = true
        cropController.cropBoxView.alphaValue = 0
      })
    }


    // Build exit animation
    let newMode: PlayerWindowMode = currentLayout.mode == .fullScreenInteractive ? .fullScreen : .windowed
    let lastSpec = currentLayout.mode == .fullScreenInteractive ? currentLayout.spec : lastWindowedLayoutSpec
    log.verbose("Exiting interactive mode, newMode: \(newMode)")
    let newLayoutSpec = LayoutSpec.fromPreferences(andMode: newMode, fillingInFrom: lastSpec)
    let startDuration = immediately ? 0 : IINAAnimation.CropAnimationDuration * 0.75
    let endDuration = immediately ? 0 : IINAAnimation.CropAnimationDuration * 0.25
    let transition = buildLayoutTransition(named: "ExitInteractiveMode", from: currentLayout, to: newLayoutSpec,
                                           totalStartingDuration: startDuration, totalEndingDuration: endDuration, geoSet)
    tasks.append(contentsOf: transition.tasks)

    return tasks
  }

  // MARK: - UI: Seek Time & Thumbnail Preview

  func shouldSeekTimeAndThumbnailBeVisible(forPointInWindow pointInWindow: NSPoint) -> Bool {
    let isOSCHidden = currentControlBar?.isHidden ?? false
    guard !player.disableUI && !isOSCHidden && !osd.isShowingPersistentOSD && !isAnimatingLayoutTransition
            && !currentLayout.isInteractiveMode else {
      return false
    }
    return isInScrollWheelSeek || isDraggingPlaySlider || isPoint(pointInWindow, inAnyOf: [playSlider])
  }

  /// Display time label & thumbnail when mouse over slider
  func refreshSeekTimeAndThumbnailAsync(forPointInWindow pointInWindow: NSPoint) {
    thumbDisplayTicketCounter += 1
    let currentTicket = thumbDisplayTicketCounter

    DispatchQueue.main.async { [self] in
      guard currentTicket == thumbDisplayTicketCounter else { return }
      refreshSeekTimeAndThumbnail(forPointInWindow: pointInWindow)
    }
  }

  func refreshSeekTimeAndThumbnail(forPointInWindow pointInWindow: NSPoint) {
    guard shouldSeekTimeAndThumbnailBeVisible(forPointInWindow: pointInWindow),
            let duration = player.info.playbackDurationSec else {
      hideSeekTimeAndThumbnail()
      return
    }

    // - 1. Time Hover Label

    let xOffsetInPlaySlider = playSlider.convert(pointInWindow, from: nil).x

    timePositionHoverLabelHorizontalCenterConstraint.constant = xOffsetInPlaySlider

    let playbackPositionRatio = max(0, Double((xOffsetInPlaySlider - 3) / (playSlider.frame.width - 6)))
    let previewTimeSec = duration * playbackPositionRatio
    let stringRepresentation = VideoTime.string(from: previewTimeSec)
    if timePositionHoverLabel.stringValue != stringRepresentation {
      timePositionHoverLabel.stringValue = stringRepresentation
    }
    timePositionHoverLabel.isHidden = false

    // - 2. Thumbnail Preview

    guard let currentControlBar else {
      thumbnailPeekView.isHidden = true
      return
    }
    guard !currentLayout.isMusicMode || (Preference.bool(for: .enableThumbnailForMusicMode) && musicModeGeo.isVideoVisible) else {
      thumbnailPeekView.isHidden = true
      return
    }

    let didHide = thumbnailPeekView.displayThumbnail(forTime: previewTimeSec, originalPosX: pointInWindow.x, player, currentLayout,
                                                     currentControlBar: currentControlBar, geo.video,
                                                     viewportSize: viewportView.frame.size,
                                                     isRightToLeft: videoView.userInterfaceLayoutDirection == .rightToLeft)
    guard didHide else { return }
    seekTimeAndThumbnailAnimationState = .shown
    // Start timer (or reset it), even if just hovering over the play slider. The Cocoa "mouseExited" event doesn't fire
    // reliably, so using a timer works well as a failsafe.
    resetSeekTimeAndThumbnailTimer()
  }

  // MARK: - UI: Other

  func showContextMenu() {
    // TODO
  }

  func refreshHidesOnDeactivateStatus() {
    guard let window else { return }
    window.hidesOnDeactivate = currentLayout.isWindowed && Preference.bool(for: .hideWindowsWhenInactive)
  }

  func abLoop() {
    assert(DispatchQueue.isExecutingIn(.main))

    player.mpv.queue.async { [self] in
      _ = player.abLoop()
    }
  }

  func enterMusicMode(withNewVidGeo newVidGeo: VideoGeometry? = nil) {
    exitInteractiveMode(then: { [self] in
      /// Start by hiding OSC and/or "outside" panels, which aren't needed and might mess up the layout.
      /// We can do this by creating a `LayoutSpec`, then using it to build a `LayoutTransition` and executing its animation.
      let oldLayout = currentLayout
      if oldLayout.isFullScreen {
        // Use exit FS as main animation and piggypack on that.
        // Need to do some gymnastics to parameterize exit from native full screen
        modeToSetAfterExitingFullScreen = .musicMode
        exitFullScreen()
      } else {
        let geo = buildGeoSet(video: newVidGeo, from: oldLayout)
        let transition = buildTransitionToEnterMusicMode(from: oldLayout, geo)
        animationPipeline.submit(transition.tasks)
      }
    })
  }

  private func buildTransitionToEnterMusicMode(from oldLayout: LayoutState, _ geo: GeometrySet? = nil) -> LayoutTransition {
    let miniPlayerLayout = oldLayout.spec.clone(mode: .musicMode)
    return buildLayoutTransition(named: "EnterMusicMode", from: oldLayout, to: miniPlayerLayout, geo)
  }

  func exitMusicMode(withNewVidGeo newVidGeo: VideoGeometry? = nil) {
    animationPipeline.submitInstantTask { [self] in
      /// Start by hiding OSC and/or "outside" panels, which aren't needed and might mess up the layout.
      /// We can do this by creating a `LayoutSpec`, then using it to build a `LayoutTransition` and executing its animation.
      let oldLayout = currentLayout
      let windowedLayout = LayoutSpec.fromPreferences(andMode: .windowed, fillingInFrom: lastWindowedLayoutSpec)
      let geo = buildGeoSet(video: newVidGeo, from: oldLayout)
      buildLayoutTransition(named: "ExitMusicMode", from: oldLayout, to: windowedLayout, thenRun: true, geo)
    }
  }

  func blackOutOtherMonitors() {
    removeBlackWindows()

    let screens = NSScreen.screens.filter { $0 != window?.screen }
    var blackWindows: [NSWindow] = []

    for screen in screens {
      var screenRect = screen.frame
      screenRect.origin = CGPoint(x: 0, y: 0)
      let blackWindow = NSWindow(contentRect: screenRect, styleMask: [], backing: .buffered, defer: false, screen: screen)
      blackWindow.backgroundColor = .black
      blackWindow.level = .iinaBlackScreen

      blackWindows.append(blackWindow)
      blackWindow.orderFront(nil)
    }
    self.blackWindows = blackWindows
    log.verbose("Added black windows for screens \((blackWindows.compactMap({$0.screen?.displayId}).map{String($0)}))")
  }

  func removeBlackWindows() {
    let blackWindows = self.blackWindows
    self.blackWindows = []
    guard !blackWindows.isEmpty else { return }
    for window in blackWindows {
      window.orderOut(self)
    }
    log.verbose("Removed black windows for screens \(blackWindows.compactMap({$0.screen?.displayId}).map{String($0)})")
  }

  func setWindowFloatingOnTop(_ onTop: Bool, updateOnTopStatus: Bool = true) {
    guard !isFullScreen else { return }
    guard let window = window else { return }

    window.level = onTop ? .iinaFloating : .normal
    if updateOnTopStatus {
      self.isOnTop = onTop
      player.mpv.setFlag(MPVOption.Window.ontop, onTop)
      updateOnTopButton()
      player.saveState()
    }
    resetCollectionBehavior()
  }

  func setEmptySpaceColor(to newColor: CGColor) {
    guard let window else { return }
    window.contentView?.layer?.backgroundColor = newColor
    viewportView.layer?.backgroundColor = newColor
  }

  func updateCustomBorderBoxAndWindowOpacity(using layout: LayoutState? = nil, windowOpacity: Float? = nil) {
    let layout = layout ?? currentLayout
    /// The title bar of the native `titled` style doesn't support translucency. So do not allow it for native modes:
    let windowOpacity: Float = layout.isFullScreen || !layout.spec.isLegacyStyle ? 1.0 : windowOpacity ?? (Preference.isAdvancedEnabled ? Preference.float(for: .playerWindowOpacity) : 1.0)
    // Native window removes the border if winodw background is transparent.
    // Try to match this behavior for legacy window
    let hide = !layout.spec.isLegacyStyle || layout.isFullScreen || windowOpacity < 1.0
    if hide != customWindowBorderBox.isHidden {
      log.debug("Changing custom border to: \(hide ? "hidden" : "shown")")
      customWindowBorderBox.isHidden = hide
      customWindowBorderTopHighlightBox.isHidden = hide
    }

    // Set this *after* showing the views above. Apparently their alpha values will not get updated if shown afterwards
    setWindowOpacity(to: windowOpacity)
  }

  /// Do not call this. Call `updateCustomBorderBoxAndWindowOpacity` instead.
  private func setWindowOpacity(to newValue: Float) {
    guard let window else { return }
    let existingValue = window.contentView?.layer?.opacity ?? -1
    guard existingValue != newValue else { return }
    log.debug("Changing window opacity, \(existingValue) → \(newValue)")
    window.backgroundColor = newValue < 1.0 ? .clear : .black
    window.contentView?.layer?.opacity = newValue
  }

  // MARK: - Sync UI with playback

  func isUITimerNeeded() -> Bool {
    //    log.verbose("Checking if UITimer needed. hasPermanentOSC:\(currentLayout.hasPermanentOSC.yn) fadeableViews:\(fadeableViewsAnimationState) topBar: \(fadeableTopBarAnimationState) OSD:\(osd.animationState)")
    if currentLayout.hasPermanentOSC {
      return true
    }
    let showingFadeableViews = fadeableViewsAnimationState == .shown || fadeableViewsAnimationState == .willShow
    let showingFadeableTopBar = fadeableTopBarAnimationState == .shown || fadeableViewsAnimationState == .willShow
    let showingOSD = osd.animationState == .shown || osd.animationState == .willShow
    return showingFadeableViews || showingFadeableTopBar || showingOSD
  }

  func updateUI() {
    assert(DispatchQueue.isExecutingIn(.main))
    // This method is often run outside of the animation queue, which can be dangerous.
    // Just don't update in this case
    guard !isAnimatingLayoutTransition else { return }
    guard loaded else { return }

    if !isInScrollWheelSeek {  // scroll wheel will set newer value; do not overwrite it until it is done
      player.updatePlaybackTimeInfo()
    }

    /// Make sure `isInitialSizeDone` is true before displaying, or else OSD text can be incorrectly stretched horizontally.
    /// Make sure file is completely loaded, or else the "watch-later" message may appear separately from the `fileStart` msg.
    if isInitialSizeDone && player.info.isFileLoadedAndSized {
      // Run all tasks in the OSD queue until it is depleted
      osd.queueLock.withLock {
        while !osd.queue.isEmpty {
          if let taskFunc = osd.queue.removeFirst() {
            taskFunc()
          }
        }
      }
    } else {
      // Do not refresh syncUITimer. It will cause an infinite loop
      hideOSD(immediately: true, refreshSyncUITimer: false)
    }

    updatePlayButtonAndSpeedUI()
    updatePlaybackTimeUI()
    updateAdditionalInfo()

    if isInMiniPlayer {
      miniPlayer.updateScrollingLabels()
    }
    if player.info.isNetworkResource {
      updateNetworkState()
    }
    // Need to also sync volume slider here, because this is called in response to repeated key presses
    updateVolumeUI()
  }

  private func updatePlaybackTimeUI() {
    // IINA listens for changes to mpv properties such as chapter that can occur during file loading
    // resulting in this function being called before mpv has set its position and duration
    // properties. Confirm the window and file have been loaded.

    guard loaded, player.info.isFileLoaded || player.info.isRestoring else { return }
    // The mpv documentation for the duration property indicates mpv is not always able to determine
    // the video duration in which case the property is not available.
    guard let duration = player.info.playbackDurationSec, let pos = player.info.playbackPositionSec else { return }

    // If the OSD is visible and is showing playback position, keep its displayed time up to date:
    setOSDViews()

    // Update playback position slider in OSC:
    for label in [leftLabel, rightLabel] {
      label?.updateText(with: duration, given: pos)
    }
    let percentage = (pos / duration) * 100
    playSlider.updateTo(percentage: percentage)

    // Touch bar
    player.touchBarSupport.touchBarPlaySlider?.setDoubleValueSafely(percentage)
    player.touchBarSupport.touchBarPosLabels.forEach { $0.updateText(with: duration, given: pos) }
  }

  func updateVolumeUI() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard loaded, !isClosing else { return }
    guard player.info.isFileLoaded || player.info.isRestoring else { return }

    let volume = player.info.volume
    let isMuted = player.info.isMuted
    let hasAudio = player.info.isAudioTrackSelected

    volumeSlider.isEnabled = hasAudio
    volumeSlider.maxValue = Double(Preference.integer(for: .maxVolume))
    volumeSlider.doubleValue = volume
    muteButton.isEnabled = hasAudio
    muteButton.state = isMuted ? .on : .off
    let volumeImage = volumeIcon(volume: volume, isMuted: isMuted)
    muteButton.image = volumeImage

    // Avoid race conditions between music mode & regular mode by just setting both sets of controls at the same time.
    // Also load music mode views ahead of time so that there are no delays when transitioning to/from it.
    // TODO: consolidate music mode buttons with regular player's
    miniPlayer.loadIfNeeded()
    miniPlayer.volumeSlider.isEnabled = hasAudio
    miniPlayer.volumeSlider.doubleValue = volume
    miniPlayer.volumeLabel.intValue = Int32(volume)
    miniPlayer.volumeButton.image = volumeImage
    miniPlayer.muteButton.image = volumeImage
  }

  func volumeIcon(volume: Double, isMuted: Bool) -> NSImage? {
    guard !isMuted else { return NSImage(named: "mute") }
    switch Int(volume) {
    case 0:
      return NSImage(named: "volume-0")
    case 1...33:
      return NSImage(named: "volume-1")
    case 34...66:
      return NSImage(named: "volume-2")
    case 67...1000:
      return NSImage(named: "volume")
    default:
      Logger.log("Volume level \(volume) is invalid", level: .error)
      return nil
    }
  }

  func updatePlayButtonAndSpeedUI() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard loaded else { return }

    let isPaused = player.info.isPaused
    let playPauseImage: NSImage
    if isPaused {
      if let mediaPosition = player.info.playbackPositionSec, let mediaDuration =  player.info.playbackDurationSec,
         mediaPosition == mediaDuration, Preference.bool(for: .resumeFromEndRestartsPlayback) {
        playPauseImage = replayImage
      } else {
        playPauseImage = playImage
      }
    } else {
      playPauseImage = pauseImage
    }

    let oscGeo = ControlBarGeometry.current
    let playSpeed = player.info.playSpeed
    let showSpeedLabel = player.info.shouldShowSpeedLabel && oscGeo.barHeight >= ControlBarGeometry.minBarHeightForSpeedLabel

    let hasLayoutChange = speedLabel.isHidden == showSpeedLabel
    let duration = hasLayoutChange ? IINAAnimation.OSDAnimationDuration : 0

    IINAAnimation.runAsync(IINAAnimation.Task(duration: duration, { [self] in
      // Avoid race conditions between music mode & regular mode by just setting both sets of controls at the same time.
      // Also load music mode views ahead of time so that there are no delays when transitioning to/from it.
      player.windowController.miniPlayer.loadIfNeeded()
      player.windowController.miniPlayer.playButton.image = playPauseImage
      playButton.image = playPauseImage

      speedLabel.isHidden = !showSpeedLabel

      if showSpeedLabel {
        speedLabel.stringValue = "\(playSpeed.stringTrunc3f)x"
      }
      player.touchBarSupport.updateTouchBarPlayBtn()
    }))
  }

  func syncPlaySliderABLoop() {
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))
    let a = player.abLoopA
    let b = player.abLoopB

    DispatchQueue.main.async { [self] in
      playSlider.abLoopA.isHidden = a == 0
      playSlider.abLoopA.doubleValue = secondsToPercent(a)
      playSlider.abLoopB.isHidden = b == 0
      playSlider.abLoopB.doubleValue = secondsToPercent(b)
      playSlider.needsDisplay = true
    }
  }

  /// Returns the percent of the total duration of the video the given position in seconds represents.
  ///
  /// The percentage returned must be considered an estimate that could change. The duration of the video is obtained from the
  /// [mpv](https://mpv.io/manual/stable/) `duration` property. The documentation for this property cautions that mpv
  /// is not always able to determine the duration and when it does return a duration it may be an estimate. If the duration is unknown
  /// this method will fallback to using the current playback position, if that is known. Otherwise this method will return zero.
  /// - Parameter seconds: Position in the video as seconds from start.
  /// - Returns: The percent of the video the given position represents.
  private func secondsToPercent(_ seconds: Double) -> Double {
    if let duration = player.info.playbackDurationSec {
      return duration == 0 ? 0 : seconds / duration * 100
    } else if let position = player.info.playbackPositionSec {
      return position == 0 ? 0 : seconds / position * 100
    } else {
      return 0
    }
  }

  func updateAdditionalInfo() {
    guard isFullScreen && Preference.bool(for: .displayTimeAndBatteryInFullScreen) else {
      return
    }

    additionalInfoLabel.stringValue = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
    let title = window?.representedURL?.lastPathComponent ?? window?.title ?? ""
    additionalInfoTitle.stringValue = title
    if let capacity = PowerSource.getList().filter({ $0.type == "InternalBattery" }).first?.currentCapacity {
      additionalInfoBattery.stringValue = "\(capacity)%"
      additionalInfoStackView.setVisibilityPriority(.mustHold, for: additionalInfoBatteryView)
    } else {
      additionalInfoStackView.setVisibilityPriority(.notVisible, for: additionalInfoBatteryView)
    }
  }

  func updateBufferIndicatorView() {
    guard loaded else { return }

    if player.info.isNetworkResource {
      bufferIndicatorView.isHidden = false
      bufferSpin.startAnimation(self)
      bufferProgressLabel.stringValue = NSLocalizedString("main.opening_stream", comment:"Opening stream…")
      bufferDetailLabel.stringValue = ""
    } else {
      bufferIndicatorView.isHidden = true
    }
  }

  func updateNetworkState() {
    let isNotYetLoaded = (player.info.currentPlayback?.state.isNotYet(.loaded) ?? false)
    // Indicator should only be shown for network resources (AKA streaming media).
    // When media is not yet loaded, mpv does not indicate it is paused for cache. Assume it is.
    let needShowIndicator = player.info.isNetworkResource && (player.info.pausedForCache || isNotYetLoaded)

    // Hide videoView so that prev media (if any) is not seen while loading current media
    videoView.isHidden = needShowIndicator && isNotYetLoaded

    if needShowIndicator {
      // FIXME: cacheUsed always returns 0
      let usedStr = FloatingPointByteCountFormatter.string(fromByteCount: player.info.cacheUsed, prefixedBy: .ki)
      let speedStr = FloatingPointByteCountFormatter.string(fromByteCount: player.info.cacheSpeed)
      let bufferingState = player.info.bufferingState
      bufferIndicatorView.isHidden = false
      bufferProgressLabel.stringValue = String(format: NSLocalizedString("main.buffering_indicator", comment:"Buffering... %d%%"), bufferingState)
      bufferDetailLabel.stringValue = "\(usedStr)B (\(speedStr)/s)"
      if !isNotYetLoaded && player.info.cacheSpeed == 0 {
        bufferSpin.stopAnimation(self)
      } else {
        bufferSpin.startAnimation(self)
      }
    } else {
      bufferSpin.stopAnimation(self)
      bufferIndicatorView.isHidden = true
    }
  }

  // These are the 2 buttons (Close & Exit) which replace the 3 traffic light title bar buttons in music mode.
  // There are 2 variants because of different styling needs depending on whether videoView is visible
  func updateMusicModeButtonsVisibility(using geometry: MusicModeGeometry) {
    if isInMiniPlayer {
      // Show only in music mode when video is visible
      let showCloseButtonOverVideo = geometry.isVideoVisible
      closeButtonBackgroundViewVE.isHidden = !showCloseButtonOverVideo

      // Show only in music mode when video is hidden
      closeButtonBackgroundViewBox.isHidden = showCloseButtonOverVideo

      miniPlayer.loadIfNeeded()
      // Push the volume button to the right if the buttons on at the same vertical position
      miniPlayer.volumeButtonLeadingConstraint.animateToConstant(showCloseButtonOverVideo ? 12 : 24)
    } else {
      closeButtonBackgroundViewVE.isHidden = true
      closeButtonBackgroundViewBox.isHidden = true
    }
  }

  func forceDraw() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let currentVideoTrack = player.info.currentTrack(.video), currentVideoTrack.id != 0 else {
      log.verbose("Skipping force video redraw: no video track selected")
      return
    }
    guard loaded, player.isActive, player.info.isPaused || currentVideoTrack.isAlbumart else { return }
    guard !Preference.bool(for: .isRestoreInProgress) else { return }
    log.verbose("Forcing video redraw")
    // Does nothing if already active. Will restart idle timer if paused
    videoView.displayActive(temporary: player.info.isPaused)
    videoView.videoLayer.drawAsync(forced: true)
  }

  // MARK: - IBActions

  @objc func menuSwitchToMiniPlayer(_ sender: NSMenuItem) {
    if isInMiniPlayer {
      player.exitMusicMode()
    } else {
      player.enterMusicMode()
    }
  }

  @IBAction func volumeSliderAction(_ sender: NSSlider) {
    // show volume popover when volume seek begins and hide on end
    if isInMiniPlayer {
      miniPlayer.showVolumePopover()
    }
    let value = sender.doubleValue
    if Preference.double(for: .maxVolume) > 100, value > 100 && value < 101 {
      NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
    player.setVolume(value)
  }

  @IBAction func backBtnAction(_ sender: NSButton) {
    player.exitMusicMode()
  }

  @IBAction func playButtonAction(_ sender: AnyObject) {
    let wasPaused = player.info.isPaused
    wasPaused ? player.resume() : player.pause()
  }

  @IBAction func muteButtonAction(_ sender: NSButton) {
    player.toggleMute()
  }

  @IBAction func leftArrowButtonAction(_ sender: NSButton) {
    arrowButtonAction(left: true, clickPressure: Int(sender.intValue))
  }

  @IBAction func rightArrowButtonAction(_ sender: NSButton) {
    arrowButtonAction(left: false, clickPressure: Int(sender.intValue))
  }

  /** handle action of either left or right arrow button */
  private func arrowButtonAction(left: Bool, clickPressure: Int) {
    let didRelease = clickPressure == 0

    let arrowBtnFunction: Preference.ArrowButtonAction = Preference.enum(for: .arrowButtonAction)
    switch arrowBtnFunction {
    case .playlist:
      guard didRelease else { return }
      player.mpv.command(left ? .playlistPrev : .playlistNext, checkError: false)

    case .seek:
      guard didRelease else { return }
      player.seek(relativeSecond: left ? -10 : 10, option: .defaultValue)

    case .speed:
      let indexSpeed1x = AppData.availableSpeedValues.count / 2
      let directionUnit: Int = (left ? -1 : 1)
      let currentSpeedIndex = findClosestCurrentSpeedIndex()

      let newSpeedIndex: Int
      if didRelease { // Released
        if maxPressure == 1 &&
            ((left ? currentSpeedIndex < indexSpeed1x - 1 : currentSpeedIndex > indexSpeed1x + 1) ||
             Date().timeIntervalSince(lastClick) < AppData.minimumPressDuration) { // Single click ended
          newSpeedIndex = oldSpeedValueIndex + directionUnit
        } else { // Force Touch or long press ended
          newSpeedIndex = indexSpeed1x
        }
        maxPressure = 0
      } else {
        if clickPressure == 1 && maxPressure == 0 { // First press
          oldSpeedValueIndex = currentSpeedIndex
          newSpeedIndex = currentSpeedIndex + directionUnit
          lastClick = Date()
        } else { // Force Touch
          newSpeedIndex = oldSpeedValueIndex + (clickPressure * directionUnit)
        }
        maxPressure = max(maxPressure, clickPressure)
      }
      let newSpeedIndexClamped = newSpeedIndex.clamped(to: 0..<AppData.availableSpeedValues.count)
      let newSpeed = AppData.availableSpeedValues[newSpeedIndexClamped]
      player.setSpeed(newSpeed, forceResume: true) // always resume if paused
    }
  }

  private func findClosestCurrentSpeedIndex() -> Int {
    let currentSpeed = player.info.playSpeed
    for (speedIndex, speedValue) in AppData.availableSpeedValues.enumerated() {
      if currentSpeed <= speedValue {
        return speedIndex
      }
    }
    return AppData.availableSpeedValues.count - 1
  }

  @IBAction func toggleOnTop(_ sender: AnyObject) {
    let onTop = isOnTop
    log.verbose("Toggling onTop: \(onTop.yn) → \((!onTop).yn)")
    if Preference.bool(for: .alwaysFloatOnTop) {
      let isPlaying = onTop
      if isPlaying {
        // Assume window is only on top because media is playing. Pause the media to remove on-top.
        player.pause()
        return
      }
    }
    setWindowFloatingOnTop(!onTop)
  }

  /// Called when `PlaySlider` changes value, either by clicking inside it, dragging inside it, or using scroll wheel (if configured).
  @IBAction func playSliderAction(_ sender: NSSlider) {
    guard player.info.isFileLoaded else { return }
    guard !isInInteractiveMode else { return }

    let progressRatio = sender.doubleValue / sender.maxValue
    let progressPercentage = 100 * progressRatio
    player.info.playbackPositionSec = player.info.playbackDurationSec! * progressRatio
    player.seek(percent: progressPercentage, forceExact: !followGlobalSeekTypeWhenAdjustSlider)

    // Make fake point in window to pass to function
    let xOffsetInPlaySlider: CGFloat = max(0.0, progressRatio * (playSlider.frame.width - 6.0) + 3.0)
    let pointInPlaySlider = CGPoint(x: xOffsetInPlaySlider, y: 0)
    let pointInWindow = playSlider.convert(pointInPlaySlider, to: nil)
    refreshSeekTimeAndThumbnailAsync(forPointInWindow: pointInWindow)
    setOSDViews()
  }

  @objc func toolBarButtonAction(_ sender: NSButton) {
    guard let buttonType = Preference.ToolBarButton(rawValue: sender.tag) else { return }
    switch buttonType {
    case .fullScreen:
      toggleWindowFullScreen()
    case .musicMode:
      player.enterMusicMode()
    case .pip:
      if pipStatus == .inPIP {
        exitPIP()
      } else if pipStatus == .notInPIP {
        enterPIP()
      }
    case .playlist:
      showSidebar(forTabGroup: .playlist)
    case .settings:
      showSidebar(forTabGroup: .settings)
    case .subTrack:
      quickSettingView.showSubChooseMenu(forView: sender, showLoadedSubs: true)
    case .screenshot:
      player.screenshot()
    }
  }

  // MARK: - Utility

  /// Do not call this in while in native full screen. It seems to cause FS to get stuck and unable to exit.
  /// Try not to call this while animating. It can cause the window to briefly disappear
  func resetCollectionBehavior() {
    guard !NSApp.presentationOptions.contains(.fullScreen) else {
      log.error("resetCollectionBehavior() should not have been called while in native FS - ignoring")
      return
    }
    guard let window else { return }
    if Preference.bool(for: .useLegacyFullScreen) {
      window.collectionBehavior.remove(.fullScreenPrimary)
      window.collectionBehavior.insert(.fullScreenAuxiliary)
    } else {
      window.collectionBehavior.remove(.fullScreenAuxiliary)
      window.collectionBehavior.insert(.fullScreenPrimary)
    }
  }

}
