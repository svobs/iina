//
//  PlayerWindowController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

// FIXME: Add Sparkle back in
// TODO: persist mpv properties in saved player state
// TODO: support parent playlist
// TODO: stick window to individual side of screen
// TODO: auto-adjust window size when Dock shown/hidden
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

  var bestScreen: NSScreen {
    window?.screen ?? NSScreen.main!
  }

  /** For blacking out other screens. */
  var blackWindows: [NSWindow] = []

  /// See `PWin_Observers.swift`.
  var cachedEffectiveAppearanceName: String? = nil

  // MARK: - View Controllers

  /** The quick setting sidebar (video, audio, subtitles). */
  let quickSettingView = QuickSettingViewController()

  /** The playlist and chapter sidebar. */
  let playlistView = PlaylistViewController()

  let pluginView = PluginViewController()

  /// The music player panel.
  ///
  /// This is only shown while in music mode, and will be a subview of `bottomBarView`. It contains a "mini" OSC, and if configured, the
  /// playlist.
  var miniPlayer: MiniPlayerViewController!

  /** The control view for interactive mode. */
  var cropSettingsView: CropBoxViewController?

  // For legacy windowed mode
  var customTitleBar: CustomTitleBarViewController? = nil


  // MARK: - Vars: Services

  unowned var tabDelegate: TabDelegate?

  // For Rotate gesture:
  let rotationHandler = RotationGestureHandler()

  // For Pinch To Magnify gesture:
  let magnificationHandler = MagnificationGestureHandler()

  let animationPipeline = IINAAnimation.Pipeline()

  /// Need to store this for use by `showWindow` when it is called asynchronously
  var pendingVideoGeoUpdateTasks: [IINAAnimation.Task] = []

  /// For responding to changes to app prefs & other notifications
  var co: CocoaObserver!

  // MARK: - Vars: State

  var isAnimating: Bool {
    return animationPipeline.isRunning
  }

  // While true, disable window geometry listeners so they don't overwrite cache with intermediate data
  var isAnimatingLayoutTransition: Bool = false {
    didSet {
      log.verbose("Updated isAnimatingLayoutTransition ≔ \(isAnimatingLayoutTransition.yesno)")
    }
  }

  var sessionState: PWinSessionState = .noSession {
    willSet {
      log.verbose("Changing sessionState: \(sessionState) → \(newValue)")
      assert(sessionState.isRestoring || DispatchQueue.isExecutingIn(DispatchQueue.main))
    }
  }
  
  var priorStateIfRestoring: PlayerSaveState? {
    if case .restoring(let priorState) = sessionState {
      return priorState
    }
    return nil
  }

  // - Mutually exclusive state bools:

  // TODO: replace these vars with window state var:
  /// WindowState enum cases: [.notYetLoaded, .loadedButClosed, .willOpen, .openVisible, .openDragging, .openMagnifying,
  /// .openLiveResizingWidth, .openLiveResizingHeight, .openDragging, .openHidden, .openMiniturized, .openMiniturizedPiP,
  /// .openInFullScreen, .closing]
  var loaded = false  // TODO: -> .isAtLeast(.loadedButClosed)
  var isWindowMiniturized = false
  var isWindowMiniaturizedDueToPip = false
  var isWindowPipDueToInactiveSpace = false
  /// Set only for PiP
  var isWindowHidden = false
  var isDragging: Bool = false
  var currentDragObject: NSView? = nil
  var isLiveResizingWidth: Bool? = nil
  var isMagnifying = false

  // - Non-exclusive state bools:

  var isOnTop: Bool = false

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
    let isVisible = window.isVisible || UIState.shared.windowsOpen.contains(savedStateName)
    let isMinimized = UIState.shared.windowsMinimized.contains(savedStateName)
    return isVisible || isMinimized
  }

  // Make sure the event loop is emptied before setting to false again. Otherwise a simple click can result in a resize.
  // Very kludgey, but nothing better discovered yet.
  var denyWindowResizeIntervalStartTime = Date()

  var isClosing: Bool {
    return player.state.isAtLeast(.stopping)
  }

  var modeToSetAfterExitingFullScreen: PlayerWindowMode? = nil

  var isPausedDueToInactive: Bool = false
  var isPausedDueToMiniaturization: Bool = false
  var isPausedPriorToInteractiveMode: Bool = false
  // TODO: also `player.pendingResumeWhenShowingWindow`

  var floatingOSCCenterRatioH = CGFloat(Preference.float(for: .controlBarPositionHorizontal))
  var floatingOSCOriginRatioV = CGFloat(Preference.float(for: .controlBarPositionVertical))

  // - Mouse

  /// When the speed arrow buttons were last clicked.
  var lastForceTouchClick = Date()
  /// The maximum pressure recorded when clicking on the speed arrow buttons.
  var maxPressure: Int = 0
  /// The value of speedValueIndex before Force Touch.
  var oldSpeedValueIndex: Int = AppData.availableSpeedValues.count / 2

  /// Force Touch: for `PK.forceTouchAction`
  var isCurrentPressInSecondStage = false

  /// Responder chain is a mess. Use this to prevent duplicate event processing
  var lastMouseDownEventID: Int = -1
  var mouseDownLocationInWindow: CGPoint?

  var lastKeyWindowStatus = false
  /// Special state needed to prevent hideOSC from happening on first mouse
  var wasKeyWindowAtMouseDown = false

  var lastMouseUpEventID: Int = -1
  /// Differentiate between single clicks and double clicks.
  var singleClickTimer: Timer?

  var lastRightMouseDownEventID: Int = -1
  var lastRightMouseUpEventID: Int = -1


  /// Scroll wheel (see `PWin_ScrollWheel.swift`)

  /// The window's virtual scroll wheel which may result in either volume or playback time seeking depending on direction
  var windowScrollWheel: PWinScrollWheel!

  var isScrollingOrDraggingPlaySlider: Bool {
    if playSlider.customCell.isDragging {
      // Dragging play slider
      return true
    }
    if (playSlider.scrollWheelDelegate?.isScrolling() ?? false) {
      // Scrolling play slider directly
      return true
    }
    if windowScrollWheel.isScrolling() && (windowScrollWheel.delegate as? PlaySliderScrollWheel != nil) {
      // Scrolling play slider via in-window scroll
      return true
    }
    return false
  }

  var isScrollingOrDraggingVolumeSlider: Bool {
    if volumeSliderCell.isDragging  {
      return true
    }
    if (volumeSlider.scrollWheelDelegate?.isScrolling() ?? false) {
      // Scrolling volume slider directly
      return true
    }
    if windowScrollWheel.isScrolling() && (windowScrollWheel.delegate as? VolumeSliderScrollWheel != nil) {
      // Scrolling volume slider via in-window scroll
      return true
    }
    return false
  }

  /// - Sidebars: See file `Sidebars.swift`

  /// For resize of `playlist` tab group
  var leadingSidebarIsResizing = false
  var trailingSidebarIsResizing = false

  // Is non-nil if within the activation rect of one of the sidebars
  var sidebarResizeCursor: NSCursor? = nil

  // - Fadeable Views
  var fadeableViews = FadeableViewsHandler()

  // Other visibility
  var hideCursorTimer: Timer?

  // - OSD

  var osd: OSDState

  // - PiP

  var pip: PIPState

  // MARK: - Vars: Window Layout State

  var currentLayout: LayoutState = LayoutState(spec: LayoutSpec.fromPrefsAndDefaults()) {
    didSet {
      if currentLayout.mode == .windowedNormal {
        lastWindowedLayoutSpec = currentLayout.spec
      }
    }
  }
  /// For restoring windowed mode layout from music mode or other mode which does not support sidebars.
  /// Also used to preserve layout if a new file is dragged & dropped into this window
  var lastWindowedLayoutSpec: LayoutSpec = LayoutSpec.fromPrefsAndDefaults()

  // Only used for debug logging:
  @Atomic var layoutTransitionCounter: Int = 0

  let titleBarAndOSCUpdateDebouncer = Debouncer(delay: Constants.TimeInterval.playerTitleBarAndOSCUpdateThrottlingDelay)
  /// For throttling `windowDidChangeScreen` notifications. MacOS 14 often sends hundreds in short bursts
  let screenChangedDebouncer = Debouncer(delay: Constants.TimeInterval.windowDidChangeScreenThrottlingDelay)
  /// For throttling `windowDidChangeScreenParameters` notifications. MacOS 14 often sends hundreds in short bursts
  let screenParamsChangedDebouncer = Debouncer(delay: Constants.TimeInterval.windowDidChangeScreenParametersThrottlingDelay)
  let thumbDisplayDebouncer = Debouncer()

  var isFullScreen: Bool { currentLayout.isFullScreen }

  var isInMiniPlayer: Bool { currentLayout.isMusicMode }

  var isInInteractiveMode: Bool { currentLayout.isInteractiveMode }

  // MARK: - Vars: Window Geometry

  var geo: GeometrySet

  var windowedModeGeo: PWinGeometry {
    get {
      return geo.windowed
    } set {
      geo = geo.clone(windowed: newValue)
      log.verbose("Updated windowedModeGeo ≔ \(newValue)")
      assert(newValue.mode.isWindowed, "windowedModeGeo has unexpected mode: \(newValue.mode)")
      assert(!newValue.screenFit.isFullScreen, "windowedModeGeo has invalid screenFit: \(newValue.screenFit)")
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
      if savedGeo.mode.isWindowed && !savedGeo.screenFit.isFullScreen {
        Logger.log.verbose("Loaded pref \(Preference.quoted(.uiLastClosedWindowedModeGeometry)): \(savedGeo)")
        return savedGeo
      } else {
        Logger.log.error("Saved pref \(Preference.quoted(.uiLastClosedWindowedModeGeometry)) is invalid. Falling back to default geometry (found: \(savedGeo))")
      }
    }
    // Compute default geometry for main screen
    let defaultScreen = NSScreen.screens[0]
    return LayoutState.buildFrom(LayoutSpec.fromPrefsAndDefaults()).buildDefaultInitialGeometry(screen: defaultScreen)
  }() {
    didSet {
      guard windowedModeGeoLastClosed.mode.isWindowed, !windowedModeGeoLastClosed.screenFit.isFullScreen else {
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

  // MARK: - Outlets

  // - Outlets: Constraints

  var viewportViewHeightContraint: NSLayoutConstraint? = nil

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

  var viewportTrailingToTrailingSidebarCropLeadingConstraint: NSLayoutConstraint!

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
  var titleBarHeightConstraint: NSLayoutConstraint!

  var fragPlaybackBtnsWidthConstraint: NSLayoutConstraint!

  /// Size of each side of the (square) `playButton`
  var playBtnWidthConstraint: NSLayoutConstraint!
  /// Size of each side of square buttons `leftArrowButton` & `rightArrowButton`
  var arrowBtnWidthConstraint: NSLayoutConstraint!

  var leftArrowBtn_CenterXOffsetConstraint: NSLayoutConstraint!
  var rightArrowBtn_CenterXOffsetConstraint: NSLayoutConstraint!

  var playSliderHeightConstraint: NSLayoutConstraint!

  var topOSCHeightConstraint: NSLayoutConstraint!

  var volumeIconHeightConstraint: NSLayoutConstraint!
  var volumeIconAspectConstraint: NSLayoutConstraint!
  var volumeSliderWidthConstraint: NSLayoutConstraint!

  // - Outlets: Views

  @IBOutlet weak var customWindowBorderBox: NSBox!
  @IBOutlet weak var customWindowBorderTopHighlightBox: NSBox!

  // MiniPlayer buttons:
  @IBOutlet weak var closeButtonView: NSView!
  // Mini island containing window buttons which hover over album art / video (when video is visible):
  @IBOutlet weak var closeButtonBackgroundViewVE: NSVisualEffectView!
  // Mini island containing window buttons which appear next to controls (when video not visible):
  @IBOutlet weak var closeButtonBackgroundViewBox: NSBox!
  @IBOutlet weak var closeButtonVE: NSButton!
  @IBOutlet weak var backButtonVE: NSButton!
  @IBOutlet weak var closeButtonBox: NSButton!
  @IBOutlet weak var backButtonBox: NSButton!

  // Title Bar:

  var leadingTitlebarAccesoryViewController: NSTitlebarAccessoryViewController?
  var trailingTitlebarAccesoryViewController: NSTitlebarAccessoryViewController?
  let leadingTitleBarAccessoryView = NSStackView()
  let trailingTitleBarAccessoryView = NSStackView()
  /// "Pin to Top" icon in title bar, if configured to  be shown
  let onTopButton = SymButton()
  let leadingSidebarToggleButton = SymButton()
  let trailingSidebarToggleButton = SymButton()

  var documentIconButton: NSButton? {
    window?.standardWindowButton(.documentIconButton)
  }

  var trafficLightButtons: [NSButton] {
    if let window, window.styleMask.contains(.titled) {
      return ([.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType]).compactMap {
        window.standardWindowButton($0)
      }
    }
    return customTitleBar?.trafficLightButtons ?? []
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

  /// Get the `NSTextField` of widow's title.
  var titleTextField: NSTextField? {
    return window?.standardWindowButton(.closeButton)?.superview?.subviews.compactMap({ $0 as? NSTextField }).first
  }

  /// Panel at top of window. May be `insideViewport` or `outsideViewport`. May contain `titleBarView` and/or `controlBarTop`
  /// depending on configuration.
  @IBOutlet weak var topBarView: NSVisualEffectView!
  /// Bottom border of `topBarView`.
  let topBarBottomBorder = NSBox()
  /// Reserves space for the title bar components. Can contain CustomTitleBarView *only* if using legacy
  /// windowed mode & topBarPlacement==.insideViewport
  let titleBarView = ClickThroughView()
  /// OSC at top of window, if configured.
  let controlBarTop = ClickThroughView()

  /// Floating OSC
  @IBOutlet weak var controlBarFloating: FloatingControlBarView!
  @IBOutlet weak var oscFloatingPlayButtonsContainerView: NSStackView!
  @IBOutlet weak var oscFloatingUpperView: NSStackView!
  @IBOutlet weak var oscFloatingLowerView: NSStackView!

  /// Current OSC container view. May be top, bottom, floating, or inside music mode window,
  /// depending on user pref and current configuration.
  var currentControlBar: NSView?

  /// Control bar at bottom of window, if configured. May be `insideViewport` or `outsideViewport`.
  /// Used to hold other views in music mode & interactive mode
  var bottomBarView: NSView = NSVisualEffectView()
  /// Top border of `bottomBarView`.
  let bottomBarTopBorder = NSBox()


  /// Layout options for how to layout controls inside `currentControlBar`.
  let oscOneRowView = SingleRowBarOSCView()
  let oscTwoRowView = TwoRowBarOSCView()
  let seekPreview = SeekPreview()

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

  let defaultAlbumArtView = ClickThroughView()

  /// Container for volume slider & mute button
  var fragVolumeView = ClickThroughView()
  let muteButton = OSCSymButton()
  let volumeSlider = ScrollableSlider()
  let volumeSliderCell = VolumeSliderCell()

  /// Container for playback buttons
  let fragPlaybackBtnsView = ClickThroughView()
  /// Speed indicator label, when playing at speeds other than 1x
  let speedLabel = NSTextField()
  let playButton = OSCSymButton()
  let leftArrowButton = OSCSymButton()
  let rightArrowButton = OSCSymButton()

  /// Toolbar Buttons container
  var fragToolbarView: ClickThroughStackView? = nil

  /// Container for legacy PlaySlider layout which shows time labels on left & right of slider.
  let playSliderAndTimeLabelsView = ClickThroughView()
  let playSlider = PlaySlider()
  let leftTimeLabel = DurationDisplayTextField()
  let rightTimeLabel = DurationDisplayTextField()

  var symButtons: [SymButton] {
    var buttons = [muteButton, playButton, leftArrowButton, rightArrowButton,
                   leadingSidebarToggleButton, trailingSidebarToggleButton, onTopButton]
    if let moreButtons = customTitleBar?.symButtons {
      buttons += moreButtons
    }
    return buttons
  }

  var mouseActionDisabledViews: [NSView?] {
    return [leadingSidebarView, trailingSidebarView, titleBarView, currentControlBar, subPopoverView]
  }

  lazy var pluginOverlayViewContainer: NSView! = {
    guard let window = window, let cv = window.contentView else { return nil }
    let view = NSView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(view, positioned: .below, relativeTo: bufferIndicatorView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": view])
    return view
  }()

  lazy var subPopoverView = playlistView.subPopover?.contentViewController?.view

  // MARK: - Initialization

  /// NOTE: this inits this `NSWindowController` & its properties. However, its `window` will be created
  /// until `self.window` is first accessed, and not until then! None of its `@IBOutlet` properties
  /// should be accessed without first checking `isLoaded`, otherwise a crash can occur. Do not use
  /// `isWindowLoaded` because that will cause `window` to be loaded (and will definitely crash if not
  /// accessed on the main thread).
  init(playerCore player: PlayerCore) {
    self.player = player
    self.osd = OSDState(log: player.log)
    self.pip = PIPState(player)
    self.geo = GeometrySet(windowed: PlayerWindowController.windowedModeGeoLastClosed,
                           musicMode: PlayerWindowController.musicModeGeoLastClosed,
                           video: VideoGeometry.defaultGeometry(player.log))
    super.init(window: nil)
    log.verbose("PlayerWindowController init")
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Returns the position in seconds for the given percent of the total duration of the video the percentage represents.
  ///
  /// The number of seconds returned must be considered an estimate that could change. The duration of the video is obtained from
  /// the [mpv](https://mpv.io/manual/stable/) `duration` property. The documentation for this property cautions that
  /// mpv is not always able to determine the duration and when it does return a duration it may be an estimate. If the duration is
  /// unknown this method will fallback to using the current playback position, if that is known. Otherwise this method will return zero.
  /// - Parameter percent: Position in the video as a percentage of the duration.
  /// - Returns: The position in the video the given percentage represents.
  func percentToSeconds(_ percent: Double) -> Double {
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
  func addVideoViewToWindow(using geo: MusicModeGeometry? = nil) {
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
        log.verbose{"Adding videoView to viewportView, screenScaleFactor: \(window.screenScaleFactor)"}
        /// Make sure `defaultAlbumArtView` stays above `videoView`
        viewportView.addSubview(videoView, positioned: .below, relativeTo: defaultAlbumArtView)
      }
    }
    // Screen may have changed. Refresh. Do not keep the OpenGL lock because it is locked in here
    videoView.refreshAllVideoState()
    /// Add constraints. These get removed each time `videoView` changes superviews.
    videoView.translatesAutoresizingMaskIntoConstraints = false
    if !sessionState.isRestoring {  // this can mess up music mode restore
      let geo = currentLayout.mode == .musicMode ? (geo ?? musicModeGeo).toPWinGeometry() : windowedModeGeo
      videoView.apply(geo)
    }
  }

  /// Set material & theme (light or dark mode) for OSC and title bar.
  func applyThemeMaterial(using layoutSpec: LayoutSpec? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let window, let screen = window.screen else {
      log.debug{"Cannot apply theme: no window or screen!"}
      return
    }
    animationPipeline.submitInstantTask { [self] in
      let theme: Preference.Theme = Preference.enum(for: .themeMaterial)
      // Can be nil, which means dynamic system appearance:
      let newAppearance: NSAppearance? = NSAppearance(iinaTheme: theme)
      window.appearance = newAppearance

      // Either dark or light, never nil:
      let effectiveAppearance: NSAppearance = newAppearance ?? window.effectiveAppearance

      let layoutSpec: LayoutSpec = layoutSpec ?? currentLayout.spec
      let oscGeo = layoutSpec.controlBarGeo

      let sliderAppearance = layoutSpec.effectiveOSCColorScheme == .clearGradient ? NSAppearance(iinaTheme: .dark)! : effectiveAppearance
      sliderAppearance.applyAppearanceFor {
        // This only needs to be run once, but doing it here will multiply the work by the number of player windows
        // currently open. Should be ok for now as this is fairly fast...
        // TODO: refactor to use an app-wide singleton to monitor prefs for changes to title bar & OSC styles.
        // TODO: do global state updates like this in singleton first, then have it kick off updates to player windows.
        BarFactory.updateBarStylesFromPrefs(effectiveAppearance: effectiveAppearance, oscGeo: oscGeo)

        // Need to set .appearance on thumbnailPeekView, or else it will fall back to superview appearance
        seekPreview.thumbnailPeekView.appearance = sliderAppearance
        playSlider.appearance = sliderAppearance
        volumeSlider.appearance = sliderAppearance
        playSlider.abLoopA.updateKnobImage(to: .loopKnob)
        playSlider.abLoopB.updateKnobImage(to: .loopKnob)

         let scaleFactor = screen.backingScaleFactor
          if let hoverIndicator = playSlider.hoverIndicator {
            hoverIndicator.update(scaleFactor: scaleFactor, oscGeo: oscGeo, isDark: sliderAppearance.isDark)
          } else {
            playSlider.hoverIndicator = SliderHoverIndicator(slider: playSlider, oscGeo: oscGeo,
                                                             scaleFactor: scaleFactor, isDark: sliderAppearance.isDark)
          }
      }
    }
  }

  /// Asynchronous with throttling!
  func updateTitleBarAndOSC() {
    titleBarAndOSCUpdateDebouncer.run { [self] in
      animationPipeline.submitInstantTask { [self] in
        let oldLayout = currentLayout
        let newLayoutSpec = LayoutSpec.fromPreferences(fillingInFrom: oldLayout.spec)
        log.verbose{"Applying theme from UpdateTitleBarAndOSC"}
        applyThemeMaterial(using: newLayoutSpec)
        buildLayoutTransition(named: "UpdateTitleBarAndOSC", from: oldLayout, to: newLayoutSpec, thenRun: true)
      }
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
      log.error{"Failed to restore property \(PlayerSaveState.PropName.miscWindowBools.rawValue.quoted): could not parse \(stateString.quoted)"}
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
    /// See `PWin_Input.swift`
    if cv.trackingAreas.isEmpty {
      cv.addTrackingArea(NSTrackingArea(rect: cv.bounds,
                                        options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                        owner: self, userInfo: [TrackingArea.key: TrackingArea.playerWindow]))
    }
    if playSlider.trackingAreas.isEmpty {
      // Not needed for now: enabledDuringMouseDrag
      playSlider.addTrackingArea(NSTrackingArea(rect: playSlider.bounds,
                                                options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
                                                owner: self, userInfo: [TrackingArea.key: TrackingArea.playSlider]))
    }
    // Track the thumbs on the progress bar representing the A-B loop points and treat them as part
    // of the slider.
    if playSlider.abLoopA.trackingAreas.count <= 1 {
      playSlider.abLoopA.addTrackingArea(NSTrackingArea(rect: playSlider.abLoopA.bounds, options:  [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseMoved], owner: self, userInfo: [TrackingArea.key: TrackingArea.playSlider]))
    }
    if playSlider.abLoopB.trackingAreas.count <= 1 {
      playSlider.abLoopB.addTrackingArea(NSTrackingArea(rect: playSlider.abLoopB.bounds, options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseMoved], owner: self, userInfo: [TrackingArea.key: TrackingArea.playSlider]))
    }

    if volumeSlider.trackingAreas.isEmpty {
      // Not needed for now: enabledDuringMouseDrag
      volumeSlider.addTrackingArea(NSTrackingArea(rect: volumeSlider.bounds,
                                                  options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
                                                  owner: self, userInfo: [TrackingArea.key: TrackingArea.volumeSlider]))
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

    addAllObservers()

    /// Enqueue this in case `windowDidLoad` is not yet done
    animationPipeline.submitInstantTask{ [self] in
      if case .restoring(let priorState) = sessionState {
        restoreFromMiscWindowBools(priorState)
      } else {
        AppDelegate.shared.initialWindow.closePriorToOpeningPlayerWindow()
      }

      /// Do this *after* `restoreFromMiscWindowBools` call
      if window.isMiniaturized {
        UIState.shared.windowsMinimized.insert(window.savedStateName)
      } else {
        UIState.shared.windowsOpen.insert(window.savedStateName)
      }
    }

    log.verbose("PlayerWindow openWindow done")
    // Don't wait for load for network stream; open immediately & show loading msg
    player.mpv.queue.async { [self] in
      if let currentPlayback = player.info.currentPlayback, currentPlayback.isNetworkResource {
        log.verbose("Current playback is network resource: calling applyVideoGeoTransform now")
        applyVideoGeoTransform("OpenNetStreamWindow", video: GeometryTransform.trackChanged)
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
        videoView.refreshEdrMode()  // if restoring, this will have been prevented until now
        forceDraw()  // needed if restoring while paused
      })

      let pendingTasks = pendingVideoGeoUpdateTasks
      pendingVideoGeoUpdateTasks = []
      if !pendingTasks.isEmpty {
        log.verbose{"After opening window: will run \(pendingTasks.count) pending vidGeo update tasks"}
        animationTasks += pendingTasks
      }

      animationTasks.append(.instantTask { [self] in
        // Make sure to save after opening (possibly new) window
        player.saveState()
        // Especially need to save the updated windows list!
        // At launch, any unreferenced PWin entries will be deleted from prefs
        UIState.shared.saveCurrentOpenWindowList()
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

    removeAllObservers()

    // Close PIP
    if pip.status == .inPIP {
      exitPIP()
    }

    if currentLayout.isLegacyFullScreen {
      updatePresentationOptionsForLegacyFullScreen(entering: false)
    }

    // Stop playing. This will save state if configured to do so:
    player.stop()

    guard !AppDelegate.shared.isTerminating else { return }

    // stop tracking mouse event
    if let window, let contentView = window.contentView {
      contentView.trackingAreas.forEach(contentView.removeTrackingArea)
    }
    playSlider.trackingAreas.forEach(playSlider.removeTrackingArea)

    hideOSD(immediately: true)

    // Reset state flags
    isWindowMiniturized = false
    player.overrideAutoMusicMode = false
    let wasSessionFinishedOpening = sessionState.hasOpenSession
    sessionState = .noSession  // reset for reopen

    /// Use value of `sessionState.hasOpenSession` to prevent from saving when there was an error loading video
    if wasSessionFinishedOpening {
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
        log.verbose("Resetting window geometry for close")
        pendingVideoGeoUpdateTasks = []
        do {
          for task in resetTransition.tasks {
            try task.runFunc()
          }

        } catch {
          log.error("Failed to run reset layout tasks: \(error)")
        }

        // The user may expect both to be updated.
        // Make sure to set these *after* running the above layout tasks, to ensure correct geometry.
        PlayerWindowController.windowedModeGeoLastClosed = windowedModeGeo
        PlayerWindowController.musicModeGeoLastClosed = musicModeGeo

        log.verbose{"Done: window cleanup on main DQ"}
      })
    }

    player.mpv.queue.async { [self] in
      // May not have finishing restoring when user closes. Make sure to clean up here
      if case .restoring = sessionState {
        log.debug("Discarding unfinished restore of window")
      }

      player.info.currentPlayback = nil
      osd.clearQueuedOSDs()
      log.verbose{"Done: window cleanup on mpv DQ"}
    }
  }

  // MARK: - Full Screen

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

    let newMode: PlayerWindowMode = oldLayout.mode == .windowedInteractive ? .fullScreenInteractive : .fullScreenNormal
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
      nextMode = .windowedNormal
    }
    let windowedLayoutSpec = LayoutSpec.fromPreferences(andMode: nextMode, fillingInFrom: oldLayout.spec)

    log.verbose{"Animating \(duration)s exit from \(isLegacy ? "legacy " : "")\(oldLayout.mode) → \(windowedLayoutSpec.mode)"}
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
    case .windowedNormal, .windowedInteractive:
      enterFullScreen()
    case .fullScreenNormal, .fullScreenInteractive:
      exitFullScreen()
    case .musicMode:
      enterFullScreen()
    }
  }

  func enterFullScreen(legacy: Bool? = nil) {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }
    let isLegacy: Bool = legacy ?? Preference.bool(for: .useLegacyFullScreen)
    let isFullScreen = NSApp.presentationOptions.contains(.fullScreen)
    log.verbose{"EnterFullScreen called. Legacy: \(isLegacy.yn), isNativeFullScreenNow: \(isFullScreen.yn)"}

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
      log.verbose{"ExitFullScreen called, legacy=\(isLegacyFS.yn)"}
      animationPipeline.submitInstantTask({ [self] in
        // If "legacy" pref was toggled while in fullscreen, still need to exit native FS
        animateExitFromFullScreen(withDuration: IINAAnimation.FullScreenTransitionDuration, isLegacy: true)
      })
    } else {
      let isActuallyNativeFullScreen = NSApp.presentationOptions.contains(.fullScreen)
      log.verbose{"ExitFullScreen called, legacy=\(isLegacyFS.yn), isNativeFullScreenNow=\(isActuallyNativeFullScreen.yn)"}
      guard isActuallyNativeFullScreen else { return }
      window.toggleFullScreen(self)
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

    log.verbose{"Updating presentationOptions, legacyFS=\(isEnteringLegacyFS ? "entering" : "exiting")"}
    if isEnteringLegacyFS {
      // Unfortunately, the check for native FS can return false if the window is in full screen but not the active space.
      // Fall back to checking this one
      guard !NSApp.presentationOptions.contains(.hideMenuBar) else {
        log.error("Cannot add presentation options for legacy full screen: option .hideMenuBar already present! Will try to avoid crashing")
        return
      }
      NSApp.presentationOptions.insert(.autoHideMenuBar)
      if !NSApp.presentationOptions.contains(.autoHideDock) {
        NSApp.presentationOptions.insert(.autoHideDock)
      }
    } else {
      if NSApp.presentationOptions.contains(.autoHideMenuBar) {
        NSApp.presentationOptions.remove(.autoHideMenuBar)
      }
      if NSApp.presentationOptions.contains(.autoHideDock) {
        NSApp.presentationOptions.remove(.autoHideDock)
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
        log.verbose{"User toggled legacy FS pref to \(outputLayoutSpec.isLegacyStyle.yesno) while in FS. Will try to exit FS"}
        exitFullScreen()
      }
    }
  }

  func window(_ window: NSWindow, willUseFullScreenContentSize proposedSize: NSSize) -> NSSize {
    let fsGeo = currentLayout.buildFullScreenGeometry(inScreenID: windowedModeGeo.screenID, video: geo.video)
    log.verbose{"Full screen content size proposed=\(proposedSize), returning=\(fsGeo.windowFrame.size)"}
    return fsGeo.windowFrame.size
  }

  // MARK: - Window Delegate: window move, screen changes

  /// This does not appear to be called anymore in MacOS 14.5...
  /// Make sure to duplicate its functionality in `windowDidChangeScreenParameters`
  func windowDidChangeBackingProperties(_ notification: Notification) {
    log.verbose("WindowDidChangeBackingProperties received")
    videoView.refreshContentsScale()
    // Do not allow MacOS to change the window size
    denyWindowResizeIntervalStartTime = Date()
  }

  func windowDidChangeScreenProfile(_ notification: Notification) {
    log.verbose("WindowDidChangeScreenProfile received")
    videoView.refreshContentsScale()
    // Do not allow MacOS to change the window size
    denyWindowResizeIntervalStartTime = Date()
  }

  func windowDidChangeOcclusionState(_ notification: Notification) {
    log.trace("WindowDidChangeOcclusionState received")
    assert(DispatchQueue.isExecutingIn(.main))
    forceDraw()
  }

  func colorSpaceDidChange(_ notification: Notification) {
    log.verbose("ColorSpaceDidChange received")
    videoView.refreshEdrMode()
  }

  // Note: this gets triggered by many unnecessary situations, e.g. several times each time full screen is toggled.
  func windowDidChangeScreen(_ notification: Notification) {
    // Do not allow MacOS to change the window size
    denyWindowResizeIntervalStartTime = Date()

    // MacOS Sonoma sometimes blasts tons of these for unknown reasons. Attempt to prevent slowdown by debouncing
    screenChangedDebouncer.run { [self] in
      guard !isClosing else { return }
      guard let window = window, let screen = window.screen else { return }
      let displayId = screen.displayId
      guard videoView.currentDisplay != displayId else {
        log.trace{"WindowDidChangeScreen: no work needed; currentDisplayID \(displayId) is unchanged"}
        return
      }


      animationPipeline.submitInstantTask({ [self] in
        log.verbose("WindowDidChangeScreen wnd=\(window.windowNumber): screenID=\(screen.screenID.quoted) screenFrame=\(screen.frame)")
        videoView.refreshAllVideoState()
        player.events.emit(.windowScreenChanged)
      })

      // Legacy FS work below can be very slow. Try to avoid if possible

      let blackWindows = self.blackWindows
      if isFullScreen && Preference.bool(for: .blackOutMonitor) && blackWindows.compactMap({$0.screen?.displayId}).contains(displayId) {
        log.verbose{"WindowDidChangeScreen: black windows contains window's displayId \(displayId); removing & regenerating black windows"}
        // Window changed screen: adjust black windows accordingly
        removeBlackWindows()
        blackOutOtherMonitors()
      }

      guard !sessionState.isRestoring, !isAnimatingLayoutTransition else { return }

      animationPipeline.submitTask(timing: .easeInEaseOut, { [self] in
        let screenID = bestScreen.screenID

        /// Need to recompute legacy FS's window size so it exactly fills the new screen.
        /// But looks like the OS will try to reposition the window on its own and can't be stopped...
        /// Just wait until after it does its thing before calling `setFrame()`.
        if currentLayout.isLegacyFullScreen {
          let layout = currentLayout
          guard layout.isLegacyFullScreen else { return }  // check again now that we are inside animation
          log.verbose{"WindowDidChangeScreen: updating legacy full screen window"}
          let fsGeo = layout.buildFullScreenGeometry(inScreenID: screenID, video: geo.video)
          applyLegacyFSGeo(fsGeo)
          // Update screenID at least, so that window won't go back to other screen when exiting FS
          windowedModeGeo = windowedModeGeo.clone(screenID: screenID)
          player.saveState()
        } else if currentLayout.mode == .windowedNormal {
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
  func windowDidChangeScreenParameters() {
    // MacOS Sonoma sometimes blasts tons of these for unknown reasons. Attempt to prevent slowdown by de-duplicating
    screenParamsChangedDebouncer.run { [self] in
      guard !isClosing else { return }
      UIState.shared.updateCachedScreens()
      log.verbose{"WndDidChangeScreenParams: Rebuilt cached screen meta: \(UIState.shared.cachedScreens.values)"}
      videoView.refreshAllVideoState()

      guard !sessionState.isRestoring, !isAnimatingLayoutTransition else { return }

      // In normal full screen mode AppKit will automatically adjust the window frame if the window
      // is moved to a new screen such as when the window is on an external display and that display
      // is disconnected. In legacy full screen mode IINA is responsible for adjusting the window's
      // frame.
      // Use very short duration. This usually gets triggered at the end when entering fullscreen, when the dock and/or menu bar are hidden.
      animationPipeline.submitTask(duration: IINAAnimation.VideoReconfigDuration, { [self] in
        let layout = currentLayout
        if layout.isLegacyFullScreen {
          guard layout.isLegacyFullScreen else { return }  // check again now that we are inside animation
          log.verbose("WndDidChangeScreenParams: updating legacy full screen window")
          let fsGeo = layout.buildFullScreenGeometry(in: bestScreen, video: geo.video)
          applyLegacyFSGeo(fsGeo)
        } else if layout.mode == .windowedNormal {
          /// In certain corner cases (e.g., exiting legacy full screen after changing screens while in full screen),
          /// the screen's `visibleFrame` can change after `transition.outputGeometry` was generated and won't be known until the end.
          /// By calling `refitted()` here, we can make sure the window is constrained to the up-to-date `visibleFrame`.
          let oldGeo = windowedModeGeo
          let newGeo = oldGeo.refitted()
          guard !newGeo.hasEqual(windowFrame: oldGeo.windowFrame, videoSize: oldGeo.videoSize) else {
            log.verbose("WndDidChangeScreenParams: in windowed mode; no change to windowFrame")
            return
          }
          log.verbose{"WndDidChangeScreenParams: calling setFrame with wf=\(newGeo.windowFrame) vidSize=\(newGeo.videoSize)"}
          player.window.setFrameImmediately(newGeo, notify: false)
        }
      })
    }
  }

  func windowDidMove(_ notification: Notification) {
    guard !isAnimating, !isAnimatingLayoutTransition, !isMagnifying, !sessionState.isRestoring else { return }
    guard let window = window else { return }

    // We can get here if external calls from accessibility APIs change the window location.
    // Inserting a small delay seems to help to avoid race conditions as the window seems to need time to "settle"
    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.TimeInterval.windowDidMoveProcessingDelay) { [self] in
      animationPipeline.submitInstantTask({ [self] in
        let layout = currentLayout
        if layout.isLegacyFullScreen {
          // MacOS (as of 14.0 Sonoma) sometimes moves the window around when there are multiple screens
          // and the user is changing focus between windows or apps. This can also happen if the user is using a third-party
          // window management app such as Amethyst. If this happens, move the window back to its proper place:
          let screen = bestScreen
          log.verbose{"WindowDidMove: Updating legacy full screen window in response to unexpected windowDidMove to frame=\(window.frame), screen=\(screen.screenID.quoted)"}
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
          log.verbose{"WindowDidResignKey: pausing cuz either wholeAppIsInactive (\(wholeAppIsInactive.yn)) or anotherPlayerWindowIsActive (\(anotherPlayerWindowIsActive.yn))"}
          player.pause()
          isPausedDueToInactive = true
        }
      }
      
      refreshKeyWindowStatus()
    }
  }

  func updateColorsForKeyWindowStatus(isKey: Bool) {
    if let customTitleBar {
      // The traffic light buttons should change to active/inactive
      customTitleBar.leadingStackView.markButtonsDirty()
      updateTitle()
    } else {
      /// Duplicate some of the logic in `customTitleBar.refreshTitle()`
      let alphaValue = isKey ? 1.0 : 0.4
      for view in [leadingSidebarToggleButton, trailingSidebarToggleButton, onTopButton] {
        // Skip buttons which are not visible
        guard view.alphaValue > 0.0 else { continue }
        view.alphaValue = alphaValue
      }
    }
  }

  func refreshKeyWindowStatus() {
    animationPipeline.submitInstantTask { [self] in
      guard let window else { return }
      guard !isClosing else { return }

      let isKey = window.isKeyWindow
      lastKeyWindowStatus = isKey
      log.verbose{"Window isKey=\(isKey.yesno)"}
      updateColorsForKeyWindowStatus(isKey: isKey)

      if isKey {
        PlayerManager.shared.lastActivePlayer = player
        MediaPlayerIntegration.shared.update()
        AppDelegate.shared.menuController?.updatePluginMenu()

        if isFullScreen && Preference.bool(for: .blackOutMonitor) {
          blackOutOtherMonitors()
        }

        if currentLayout.isLegacyFullScreen && window.level != .iinaFloating {
          log.verbose("Window is key: resuming legacy FS window level")
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

  func window(_ window: NSWindow, shouldPopUpDocumentPathMenu menu: NSMenu) -> Bool {
    guard let currentPlayback = player.info.currentPlayback else { return false }
    return !currentPlayback.isNetworkResource
  }

  // MARK: - UI: Title

  @objc
  func updateTitle() {
    player.mpv.queue.async { [self] in
      guard player.isActive else { return }
      guard let currentPlayback = player.info.currentPlayback else {
        log.verbose("Cannot update window title: currentPlayback is nil")
        return
      }

      let title: String

      if isInMiniPlayer {
        // Update title in music mode control bar
        let (mediaTitle, mediaAlbum, mediaArtist) = player.getMusicMetadata()
        title = mediaTitle

        DispatchQueue.main.async { [self] in
          setWindowTitle(title, isFilename: false)
          miniPlayer.loadIfNeeded()
          miniPlayer.updateTitle(mediaTitle: mediaTitle, mediaAlbum: mediaAlbum, mediaArtist: mediaArtist)
        }

      } else if player.info.isNetworkResource {
        // Streaming media: title can change unpredictably
        title = player.getMediaTitle()

        DispatchQueue.main.async { [self] in
          setWindowTitle(title, isFilename: false)
        }
      } else {
        let currentURL = currentPlayback.url
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
        title = currentURL.lastPathComponent

        DispatchQueue.main.async { [self] in
          guard let window else { return }
          // Local file: facilitate document icon
          window.representedURL = currentURL
          setWindowTitle(title, isFilename: false)
          window.setTitleWithRepresentedFilename(currentURL.path)
        }
      }
    }  // end DispatchQueue.main work item

  }

  private func setWindowTitle(_ titleText: String, isFilename: Bool) {
    guard let window else { return }

    // Interesting. The Swift preprocessor will not see this variable inside the DEBUG block if it is also named "isFilename".
    var filename = isFilename
#if DEBUG
    // Include player ID in window (example: "[PLR-1234c0] MyVideo.mp4")
    let debugTitle = "[\(player.label)] \(titleText)"
    log.trace{"Updating window title to: \(debugTitle.pii.quoted)"}
    window.title = debugTitle
    filename = false
    customTitleBar?.updateTitle(to: debugTitle)
#else
    window.title = titleText
    customTitleBar?.updateTitle(to: titleText)
#endif

    /// This call is needed when using custom window style, otherwise the window won't get added to the Window menu or the Dock.
    /// Oddly, there are 2 separate functions for adding and changing the item, but `addWindowsItem` has no effect if called more than once,
    /// while `changeWindowsItem` needs to be called if `addWindowsItem` was already called. To be safe, just call both.
    NSApplication.shared.addWindowsItem(window, title: titleText, filename: filename)
    NSApplication.shared.changeWindowsItem(window, title: titleText, filename: filename)

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
        log.error{"Crop mode requested, but found an existing crop filter (\(vf.stringFormat.quoted)). Will remove it before entering"}
        // A crop is already set. Need to temporarily remove it so that the whole video can be seen again,
        // so that a new crop can be chosen. But keep info from the old filter in case the user cancels.
        // Change this pre-emptively so that removeVideoFilter doesn't trigger a window geometry change
        player.info.videoFiltersDisabled[vf.label!] = vf
        newVideoGeo = videoGeo.clone(selectedCropLabel: AppData.noneCropIdentifier)
        if !player.removeVideoFilter(vf) {
          log.error{"Failed to remove prev crop filter: (\(vf.stringFormat.quoted)) for some reason. Will ignore and try to proceed anyway"}
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
          log.verbose{"EnterInteractiveMode: Uncropping video from cropRectRaw: \(prevCropBox) to videoSizeRaw: \(videoSizeRaw)"}
          let newVideoAspect = videoSizeRaw.mpvAspect

          switch currentLayout.mode {
          case .windowedNormal, .fullScreenNormal:
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

              log.verbose{"EnterInteractiveMode: aspectChangeFactor:\(aspectChangeFactor), viewportSizeMultiplier: \(viewportSizeMultiplier), newViewportSize:\(newViewportSize)"}
              uncroppedClosedBarsGeo = uncroppedClosedBarsGeo.scalingViewport(to: newViewportSize)
            } else {
              // If not locking viewport to video, just reuse viewport
              uncroppedClosedBarsGeo = uncroppedClosedBarsGeo.refitted()
            }
            log.verbose{"EnterInteractiveMode: Generated uncroppedGeo: \(uncroppedClosedBarsGeo)"}

            if currentLayout.mode == .windowedNormal {
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
    let newMode: PlayerWindowMode = currentLayout.mode == .fullScreenNormal ? .fullScreenInteractive : .windowedInteractive
    let interactiveModeLayout = currentLayout.spec.clone(mode: newMode, interactiveMode: mode)
    let startDuration = IINAAnimation.CropAnimationDuration * 0.5
    let endDuration = currentLayout.mode == .fullScreenNormal ? startDuration * 0.5 : startDuration
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

      log.verbose{"Cropping video from videoSizeRaw: \(newVidGeo.videoSizeRaw), videoSizeScaled: \(cropController.cropBoxView.videoRect), cropRect: \(cropRect)"}

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
    let newMode: PlayerWindowMode = currentLayout.mode == .fullScreenInteractive ? .fullScreenNormal : .windowedNormal
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

  // MARK: - UI: Music mode

  func showContextMenu() {
    // TODO
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
      let windowedLayout = LayoutSpec.fromPreferences(andMode: .windowedNormal, fillingInFrom: lastWindowedLayoutSpec)
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
    log.verbose{"Added black windows for screens \((blackWindows.compactMap({$0.screen?.displayId}).map{String($0)}))"}
  }

  func removeBlackWindows() {
    let blackWindows = self.blackWindows
    self.blackWindows = []
    guard !blackWindows.isEmpty else { return }
    for window in blackWindows {
      window.orderOut(self)
    }
    log.verbose{"Removed black windows for screens \(blackWindows.compactMap({$0.screen?.displayId}).map{String($0)})"}
  }

  func setWindowFloatingOnTop(_ onTop: Bool, updateOnTopStatus: Bool = true) {
    guard !isFullScreen else { return }
    guard let window = window else { return }

    window.level = onTop ? .iinaFloating : .normal
    if updateOnTopStatus {
      self.isOnTop = onTop
      player.mpv.setFlag(MPVOption.Window.ontop, onTop)
      updateOnTopButton(from: currentLayout, showIfFadeable: true)
      player.saveState()
    }
    resetCollectionBehavior()
  }

  // MARK: - Sync UI with playback

  func isUITimerNeeded() -> Bool {
    //    log.verbose("Checking if UITimer needed. hasPermanentControlBar:\(currentLayout.hasPermanentControlBar.yn) fadeableViews:\(fadeableViewsAnimationState) topBar: \(fadeableTopBarAnimationState) OSD:\(osd.animationState)")
    if currentLayout.hasPermanentControlBar {
      return true
    }
    let showingFadeableViews = fadeableViews.animationState == .shown || fadeableViews.animationState == .willShow
    let showingFadeableTopBar = fadeableViews.topBarAnimationState == .shown || fadeableViews.topBarAnimationState == .willShow
    let showingOSD = osd.animationState == .shown || osd.animationState == .willShow
    return showingFadeableViews || showingFadeableTopBar || showingOSD
  }

  /// Updates all UI controls
  func updateUI() {
    assert(DispatchQueue.isExecutingIn(.main))
    // This method is often run outside of the animation queue, which can be dangerous.
    // Just don't update in this case
    guard !isAnimatingLayoutTransition else { return }
    guard loaded else { return }
    guard player.state.isNotYet(.shuttingDown) else { return }

    // scroll wheel will set newer value; do not overwrite it until it is done
    if !isScrollingOrDraggingPlaySlider {
      player.updatePlaybackTimeInfo()
    }

    /// Make sure window is done being sized before displaying, or else OSD text can be incorrectly stretched horizontally.
    /// Make sure file is completely loaded, or else the "watch-later" message may appear separately from the `fileStart` msg.
    if player.info.isFileLoadedAndSized {
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
      miniPlayer.stepScrollingLabels()
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

    guard loaded, player.info.isFileLoaded || player.isRestoring else { return }
    // The mpv documentation for the duration property indicates mpv is not always able to determine
    // the video duration in which case the property is not available.
    guard let duration = player.info.playbackDurationSec,
          let position = player.info.playbackPositionSec else { return }

    // If the OSD is visible and is showing playback position, keep its displayed time up to date:
    setOSDViews()

    // Update playback position slider in OSC:
    for label in [leftTimeLabel, rightTimeLabel] {
      label.updateText(with: duration, given: position)
    }
    let percentage = (position / duration) * 100
    playSlider.doubleValue = percentage

    // Touch bar
    player.touchBarSupport.touchBarPlaySlider?.setDoubleValueSafely(percentage)
    player.touchBarSupport.touchBarPosLabels.forEach { $0.updateText(with: duration, given: position) }
  }

  func updateVolumeUI() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard loaded, !isClosing else { return }
    guard player.info.isFileLoaded || player.isRestoring else { return }

    let volume = player.info.volume
    let isMuted = player.info.isMuted
    let hasAudio = player.info.isAudioTrackSelected

    volumeSlider.isEnabled = hasAudio
    volumeSlider.maxValue = Double(Preference.integer(for: .maxVolume))
    volumeSlider.doubleValue = volume
    muteButton.isEnabled = hasAudio

    let volumeImage = volumeIcon(volume: volume, isMuted: isMuted)
    if let volumeImage, volumeImage != muteButton.image {
      let task = IINAAnimation.Task(duration: IINAAnimation.btnLayoutChangeDuration, { [self] in
        volumeIconAspectConstraint.isActive = false
        volumeIconAspectConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: volumeImage.aspect)
        volumeIconAspectConstraint.priority = .init(900)
        volumeIconAspectConstraint.isActive = true
      })
      IINAAnimation.runAsync(task, then: { [self] in
        muteButton.image = volumeImage
      })
    }

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
    if isMuted {
      return Images.mute
    }
    switch Int(volume) {
    case 0:
      return Images.volume0
    case 1...33:
      return Images.volume1
    case 34...66:
      return Images.volume2
    case 67...1000:
      return Images.volume3
    default:
      log.error{"Volume level \(volume) is invalid"}
      return nil
    }
  }

  func updatePlayButtonAndSpeedUI() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard loaded else { return }

    let isPaused = player.info.isPaused
    let playPauseImage: NSImage
    if isPaused {
      if player.shouldShowRestartFromEOFIcon() {
        playPauseImage = Images.replay
      } else {
        playPauseImage = Images.play
      }
    } else {
      playPauseImage = Images.pause
    }

    let oscGeo = currentLayout.controlBarGeo
    let playSpeed = player.info.playSpeed
    let showSpeedLabel = player.info.shouldShowSpeedLabel && oscGeo.barHeight >= Constants.Distance.minOSCBarHeightForSpeedLabel

    let hasPlayButtonChange = playButton.image != playPauseImage
    let hasSpeedLayoutChange = speedLabel.isHidden == !showSpeedLabel

    // Update status in menu bar menu (if enabled)
    MediaPlayerIntegration.shared.update()

    let duration = (hasSpeedLayoutChange || hasPlayButtonChange) ? IINAAnimation.btnLayoutChangeDuration * 4 : 0.0
    IINAAnimation.runAsync(.init(duration: duration) { [self] in
      // Avoid race conditions between music mode & regular mode by just setting both sets of controls at the same time.
      // Also load music mode views ahead of time so that there are no delays when transitioning to/from it.
      var effect: SymButton.ReplacementEffect = .downUp
      if playButton.image == Images.replay, playPauseImage != Images.replay {
        // looks less bad
        effect = .offUp
      }
      playButton.replaceSymbolImage(with: playPauseImage, effect: effect)

      speedLabel.isHidden = !showSpeedLabel

      if showSpeedLabel {
        speedLabel.stringValue = "\(playSpeed.stringTrunc3f)x"
      }
      player.touchBarSupport.updateTouchBarPlayBtn()
    })
  }

  func syncPlaySliderABLoop() {
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))
    guard loaded, !player.isStopping else { return }
    let a = player.abLoopA
    let b = player.abLoopB

    DispatchQueue.main.async { [self] in
      playSlider.abLoopA.isHidden = a == 0
      playSlider.abLoopA.posInSliderPercent = secondsToPercent(a)
      playSlider.abLoopB.isHidden = b == 0
      playSlider.abLoopB.posInSliderPercent = secondsToPercent(b)
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
      if bufferIndicatorView.isHidden {
        log.verbose("Showing bufferIndicatorView for network stream")
      }
      bufferIndicatorView.isHidden = false
      bufferSpin.startAnimation(self)
      bufferProgressLabel.stringValue = NSLocalizedString("main.opening_stream", comment:"Opening stream…")
      bufferDetailLabel.stringValue = ""
    } else {
      if !bufferIndicatorView.isHidden {
        log.verbose("Hiding bufferIndicatorView: not a network stream")
      }
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
      let usedStr = FloatingPointByteCountFormatter.string(fromByteCount: player.info.cacheUsed, prefixedBy: .ki)
      let speedStr = FloatingPointByteCountFormatter.string(fromByteCount: player.info.cacheSpeed)
      let bufferingState = player.info.bufferingState
      // mpv usually hangs at 0% the entire time. Do not show any progress if we do not have progress to show.
      let showNumbers = bufferingState > 0
      let bufStateString = showNumbers ? "\(bufferingState)%" : ""
      log.verbose{"Showing bufferIndicatorView (\(bufferingState)%, \(usedStr)B, \(speedStr)/s)"}
      bufferIndicatorView.isHidden = false
      bufferProgressLabel.stringValue = String(format: NSLocalizedString("main.buffering_indicator", comment:"Buffering... %@"), bufStateString)
      bufferDetailLabel.stringValue = showNumbers ? "\(usedStr)B (\(speedStr)/s)" : ""
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

  func refreshHidesOnDeactivateStatus() {
    guard let window else { return }
    window.hidesOnDeactivate = currentLayout.isWindowed && Preference.bool(for: .hideWindowsWhenInactive)
  }

  /// All args are optional overrides
  func updateWindowBorderAndOpacity(using layout: LayoutState? = nil, windowOpacity newOpacity: Float? = nil) {
    let layout = layout ?? currentLayout
    /// The title bar of the native `titled` style doesn't support translucency. So do not allow it for native modes:
    let newOpacity: Float = layout.isFullScreen || !layout.spec.isLegacyStyle ? 1.0 : newOpacity ?? (Preference.isAdvancedEnabled ? Preference.float(for: .playerWindowOpacity) : 1.0)
    // Native window removes the border if winodw background is transparent.
    // Try to match this behavior for legacy window
    let hide = !layout.spec.isLegacyStyle || layout.isFullScreen || newOpacity < 1.0
    if hide != customWindowBorderBox.isHidden {
      log.debug{"Changing custom border to: \(hide ? "hidden" : "shown")"}
      customWindowBorderBox.isHidden = hide
      customWindowBorderTopHighlightBox.isHidden = hide
    }

    // Update window opacity *after* showing the views above. Apparently their alpha values will not get updated if shown afterwards.
    guard let window else { return }
    let existingOpacity = window.contentView?.layer?.opacity ?? -1
    guard existingOpacity != newOpacity else { return }
    log.debug{"Changing window opacity: \(existingOpacity) → \(newOpacity)"}
    window.backgroundColor = newOpacity < 1.0 ? .clear : .black
    window.contentView?.layer?.opacity = newOpacity
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

  @objc func playButtonAction(_ sender: AnyObject) {
    player.togglePause()
  }

  @IBAction func muteButtonAction(_ sender: AnyObject) {
    player.toggleMute()
  }

  @objc func leftArrowButtonAction(_ sender: NSControl) {
    let clickPressure: Int = (sender as? SymButton)?.pressureStage ?? sender.integerValue
    arrowButtonAction(left: true, clickPressure: clickPressure)
  }

  @objc func rightArrowButtonAction(_ sender: NSControl) {
    let clickPressure: Int = (sender as? SymButton)?.pressureStage ?? sender.integerValue
    arrowButtonAction(left: false, clickPressure: clickPressure)
  }

  /** handle action of either left or right arrow button */
  func arrowButtonAction(left: Bool, clickPressure: Int) {
    let didRelease = clickPressure == 0

    let arrowBtnFunction: Preference.ArrowButtonAction = Preference.enum(for: .arrowButtonAction)
    switch arrowBtnFunction {
    case .unused:
      return
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

      if Preference.bool(for: .useForceTouchForSpeedArrows) {
        if didRelease { // Released

          // Discard redundant release events
          guard maxPressure > 0 else { return }

          if maxPressure == 1 &&
              ((left ? currentSpeedIndex < indexSpeed1x - 1 : currentSpeedIndex > indexSpeed1x + 1) ||
               Date().timeIntervalSince(lastForceTouchClick) < Constants.TimeInterval.minimumPressDuration) { // Single click ended
            newSpeedIndex = oldSpeedValueIndex + directionUnit
          } else { // Force Touch or long press ended
            newSpeedIndex = indexSpeed1x
          }
          maxPressure = 0
        } else {
          if clickPressure == 1 && maxPressure == 0 { // First press
            oldSpeedValueIndex = currentSpeedIndex
            newSpeedIndex = currentSpeedIndex + directionUnit
            lastForceTouchClick = Date()
          } else { // Force Touch
            newSpeedIndex = oldSpeedValueIndex + (clickPressure * directionUnit)
          }
          maxPressure = max(maxPressure, clickPressure)
        }
      } else {
        guard didRelease else { return }
        newSpeedIndex = currentSpeedIndex + directionUnit
      }
      let newSpeedIndexClamped = newSpeedIndex.clamped(to: 0..<AppData.availableSpeedValues.count)
      let newSpeed = AppData.availableSpeedValues[newSpeedIndexClamped]
      guard player.info.playSpeed != newSpeed else { return }
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
    log.verbose{"Toggling onTop: \(onTop.yn) → \((!onTop).yn)"}
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

  /// Executes an absolute seek using `playSlider`'s current value.
  ///
  /// Called when `PlaySlider` changes value, either by:
  /// - clicking inside it
  /// - dragging inside it
  /// Scroll wheel seek should call `seekFromPlaySlider` directly.
  @IBAction func playSliderAction(_ slider: PlaySlider) {
    // Update player.info & UI proactively
    let playbackPositionAbsSec = player.info.playbackDurationSec! * slider.progressRatio
    let forceExactSeek = !Preference.bool(for: .followGlobalSeekTypeWhenAdjustSlider)
    seekFromPlaySlider(playbackPositionSec: playbackPositionAbsSec, forceExactSeek: forceExactSeek)
  }

  func seekFromPlaySlider(playbackPositionSec absoluteSecond: CGFloat, forceExactSeek: Bool) {
    guard !isInInteractiveMode, let playSliderFrameInWindowCoords = playSlider.frameInWindowCoords else { return }

    // Update player.info & UI proactively
    player.info.playbackPositionSec = absoluteSecond
    updatePlaybackTimeUI()
    // Make fake point in window to position seek time & thumbnail
    let pointInWindow = CGPoint(x: playSlider.centerOfKnobInWindowCoordX(), y: playSliderFrameInWindowCoords.midY)
    refreshSeekPreviewAsync(forPointInWindow: pointInWindow)

    player.sliderSeekDebouncer.run { [self] in
      guard player.info.isFileLoaded else { return }

      let option: Preference.SeekOption = forceExactSeek ? .exact : Preference.enum(for: .useExactSeek)
      player.seek(absoluteSecond: absoluteSecond, option: option)
    }
  }

  @objc func toolBarButtonAction(_ sender: NSButton) {
    guard let buttonType = Preference.ToolBarButton(rawValue: sender.tag) else { return }
    switch buttonType {
    case .fullScreen:
      toggleWindowFullScreen()
    case .musicMode:
      player.enterMusicMode()
    case .pip:
      if pip.status == .inPIP {
        exitPIP()
      } else if pip.status == .notInPIP {
        enterPIP()
      }
    case .playlist:
      showSidebar(forTabGroup: .playlist)
    case .settings:
      showSidebar(forTabGroup: .settings)
    case .subTrack:
      quickSettingView.showSubChooseMenu(forView: sender, showLoadedSubs: true)
    case .screenshot:
      player.mpv.queue.async { [self] in
        player.screenshot()
      }
    case .plugins:
      showSidebar(forTabGroup: .plugins)
    }
  }

  // MARK: - Utility

  func forceDraw() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let currentVideoTrack = player.info.currentTrack(.video), currentVideoTrack.id != 0 else {
      log.verbose("Skipping force video redraw: no video track selected")
      return
    }
    guard loaded, player.isActive, player.info.isPaused || currentVideoTrack.isAlbumart else { return }
    guard !Preference.bool(for: .isRestoreInProgress) else { return }
    log.trace("Forcing video redraw")
    // Does nothing if already active. Will restart idle timer if paused
    videoView.displayActive(temporary: player.info.isPaused)
    videoView.videoLayer.drawAsync(forced: true)
  }

  func setEmptySpaceColor(to newColor: CGColor) {
    guard let window else { return }
    window.contentView?.layer?.backgroundColor = newColor
    viewportView.layer?.backgroundColor = newColor
  }

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
