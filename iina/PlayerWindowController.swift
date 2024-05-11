//
//  PlayerWindowController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import Mustache
import WebKit

// MARK: - Constants

fileprivate let thumbnailExtraOffsetX: CGFloat = 15
fileprivate let thumbnailExtraOffsetY: CGFloat = 15

// MARK: - Constants

class PlayerWindowController: IINAWindowController, NSWindowDelegate {
  enum TrackingArea: Int {
    static let key: String = "area"

    case playerWindow = 0
    case playSlider
    case customTitleBar
  }

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

  var loaded = false

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

  var miniPlayer: MiniPlayerController!

  /** The control view for interactive mode. */
  var cropSettingsView: CropBoxViewController?

  // For legacy windowed mode
  var customTitleBar: CustomTitleBarViewController? = nil

  // For Rotate gesture:
  let rotationHandler = RotationGestureHandler()

  // For Pinch To Magnify gesture:
  let magnificationHandler = MagnificationGestureHandler()

  let animationPipeline = IINAAnimation.Pipeline()

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

  var isOpen: Bool {
    if !self.loaded {
      return false
    }
    guard let window = self.window else { return false }
    // Also check if hidden due to PIP, or minimized
    return window.isVisible || isWindowHidden || window.isMiniaturized
  }
  private(set) var isWindowHidden: Bool = false

  var isClosing = false
  var isInitialSizeDone = false
  var isWindowMiniturized = false
  var isWindowMiniaturizedDueToPip = false
  var isWindowPipDueToInactiveSpace = false

  var isMagnifying = false
  var denyNextWindowResize = false
  var modeToSetAfterExitingFullScreen: PlayerWindowMode? = nil

  var isPausedDueToInactive: Bool = false
  var isPausedDueToMiniaturization: Bool = false
  var isPausedPriorToInteractiveMode: Bool = false

  var floatingOSCCenterRatioH = CGFloat(Preference.float(for: .controlBarPositionHorizontal))
  var floatingOSCOriginRatioV = CGFloat(Preference.float(for: .controlBarPositionVertical))

  // - Mouse

  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false
  var isLiveResizingWidth: Bool? = nil

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

  // - Fadeable Views

  /** Views that will show/hide when cursor moving in/out the window. */
  var fadeableViews = Set<NSView>()
  /** Similar to `fadeableViews`, but may fade in differently depending on configuration of top bar. */
  var fadeableViewsTopBar = Set<NSView>()
  var fadeableViewsAnimationState: UIAnimationState = .shown
  var fadeableTopBarAnimationState: UIAnimationState = .shown
  /** For auto hiding UI after a timeout. */
  var hideFadeableViewsTimer: Timer?

  // - OSD

  /// Whether current OSD needs user interaction to be dismissed.
  private var isShowingPersistentOSD = false
  var osdAnimationState: UIAnimationState = .hidden
  var hideOSDTimer: Timer?
  private var osdNextSeekIcon: NSImage? = nil
  private var osdCurrentSeekIcon: NSImage? = nil
  var osdLastPlaybackPosition: Double? = nil
  var osdLastPlaybackDuration: Double? = nil
  private var osdLastDisplayedMsgTS: TimeInterval = 0
  var osdLastDisplayedMsg: OSDMessage? = nil {
    didSet {
      guard osdLastDisplayedMsg != nil else { return }
      osdLastDisplayedMsgTS = Date().timeIntervalSince1970
    }
  }
  func osdDidShowLastMsgRecently() -> Bool {
    return Date().timeIntervalSince1970 - osdLastDisplayedMsgTS < 0.25
  }
  // Need to keep a reference to NSViewController here in order for its Objective-C selectors to work
  var osdContext: NSViewController? = nil {
    didSet {
      if let osdContext {
        log.verbose("Updated osdContext to: \(osdContext)")
      } else {
        log.verbose("Updated osdContext to: nil")
      }
    }
  }
  private var osdQueueLock = Lock()
  private var osdQueue = LinkedList<() -> Void>()

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

  // MARK: - Window geometry vars

  lazy var windowedModeGeo: PWGeometry = PlayerWindowController.windowedModeGeoLastClosed {
    didSet {
      log.verbose("Updated windowedModeGeo ≔ \(windowedModeGeo)")
      assert(windowedModeGeo.mode.isWindowed, "windowedModeGeo has unexpected mode: \(windowedModeGeo.mode)")
      assert(!windowedModeGeo.fitOption.isFullScreen, "windowedModeGeo has invalid fitOption: \(windowedModeGeo.fitOption)")
    }
  }

  // Remembers the geometry of the "last closed" window in windowed, so future windows will default to its layout.
  // The first "get" of this will load from saved pref. Every "set" of this will update the pref.
  static var windowedModeGeoLastClosed: PWGeometry = {
    let csv = Preference.string(for: .uiLastClosedWindowedModeGeometry)
    if csv?.isEmpty ?? true {
      Logger.log("Pref entry for \(Preference.quoted(.uiLastClosedWindowedModeGeometry)) is empty. Will fall back to default geometry",
                 level: .verbose)
    } else if let savedGeo = PWGeometry.fromCSV(csv) {
      if !savedGeo.mode.isWindowed || savedGeo.fitOption.isFullScreen {
        Logger.log("Saved pref \(Preference.quoted(.uiLastClosedWindowedModeGeometry)) is invalid. Will fall back to default geometry (found: \(savedGeo))",
                   level: .error)
      } else {
        return savedGeo
      }
    }
    // Compute default geometry for main screen
    let defaultScreen = NSScreen.screens[0]
    return LayoutState.buildFrom(LayoutSpec.defaultLayout()).buildDefaultInitialGeometry(screen: defaultScreen)
  }() {
    didSet {
      guard windowedModeGeoLastClosed.mode.isWindowed, !windowedModeGeoLastClosed.fitOption.isFullScreen else {
        Logger.log("Will not save windowedModeGeoLastClosed because it is invalid: not in windowed mode! Found: \(windowedModeGeoLastClosed)", level: .error)
        return
      }
      Preference.set(windowedModeGeoLastClosed.toCSV(), for: .uiLastClosedWindowedModeGeometry)
      Logger.log("Updated pref \(Preference.quoted(.uiLastClosedWindowedModeGeometry)) ≔ \(windowedModeGeoLastClosed)", level: .verbose)
    }
  }

  lazy var musicModeGeo: MusicModeGeometry = PlayerWindowController.musicModeGeoLastClosed {
    didSet {
      log.verbose("Updated musicModeGeo ≔ \(musicModeGeo)")
    }
  }

  // Remembers the geometry of the "last closed" music mode window, so future music mode windows will default to its layout.
  // The first "get" of this will load from saved pref. Every "set" of this will update the pref.
  static var musicModeGeoLastClosed: MusicModeGeometry = {
    let csv = Preference.string(for: .uiLastClosedMusicModeGeometry)
    if csv?.isEmpty ?? true {
      Logger.log("Pref entry for \(Preference.quoted(.uiLastClosedMusicModeGeometry)) is empty. Will fall back to default music mode geometry",
                 level: .verbose)
    } else if let savedGeo = MusicModeGeometry.fromCSV(csv) {
      return savedGeo
    }
    let defaultScreen = NSScreen.screens[0]
    let defaultGeo = MiniPlayerController.buildMusicModeGeometryFromPrefs(screen: defaultScreen,
                                                                          videoAspect: AppData.defaultVideoSize.mpvAspect)
    return defaultGeo
  }() {
    didSet {
      Preference.set(musicModeGeoLastClosed.toCSV(), for: .uiLastClosedMusicModeGeometry)
      Logger.log("Updated musicModeGeoLastClosed := \(musicModeGeoLastClosed)", level: .verbose)
    }
  }

  // MARK: - Enums

  // Window state

  enum PIPStatus {
    case notInPIP
    case inPIP
    case intermediate
  }

  enum InteractiveMode: Int {
    case crop = 1
    case freeSelecting

    func viewController() -> CropBoxViewController {
      var vc: CropBoxViewController
      switch self {
      case .crop:
        vc = CropSettingsViewController()
      case .freeSelecting:
        vc = FreeSelectingViewController()
      }
      return vc
    }
  }

  // Animation state

  /// Animation state of he hide/show part
  enum UIAnimationState {
    case shown, hidden, willShow, willHide

    var isInTransition: Bool {
      return self == .willShow || self == .willHide
    }
  }

  // MARK: - Observed user defaults

  // Cached user default values
  lazy var displayTimeAndBatteryInFullScreen: Bool = Preference.bool(for: .displayTimeAndBatteryInFullScreen)
  // Cached user defaults values
  internal lazy var followGlobalSeekTypeWhenAdjustSlider: Bool = Preference.bool(for: .followGlobalSeekTypeWhenAdjustSlider)
  internal lazy var useExactSeek: Preference.SeekOption = Preference.enum(for: .useExactSeek)
  internal lazy var relativeSeekAmount: Int = Preference.integer(for: .relativeSeekAmount)
  internal lazy var volumeScrollAmount: Int = Preference.integer(for: .volumeScrollAmount)
  internal lazy var singleClickAction: Preference.MouseClickAction = Preference.enum(for: .singleClickAction)
  internal lazy var doubleClickAction: Preference.MouseClickAction = Preference.enum(for: .doubleClickAction)
  internal lazy var horizontalScrollAction: Preference.ScrollAction = Preference.enum(for: .horizontalScrollAction)
  internal lazy var verticalScrollAction: Preference.ScrollAction = Preference.enum(for: .verticalScrollAction)

  static private let observedPrefKeys: [Preference.Key] = [
    .enableAdvancedSettings,
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

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard isOpen else { return }  // do not want to respond to some things like blackOutOtherMonitors while closed!
    guard let keyPath = keyPath, let change = change else { return }

    switch keyPath {
    case PK.enableAdvancedSettings.rawValue:
      animationPipeline.submit(IINAAnimation.Task({ [self] in
        updateCustomBorderBoxAndWindowOpacity()
        // may need to hide cropbox label and other advanced stuff
        quickSettingView.reload()
      }))
    case PK.themeMaterial.rawValue:
      applyThemeMaterial()
    case PK.playerWindowOpacity.rawValue:
      animationPipeline.submit(IINAAnimation.Task({ [self] in
        updateCustomBorderBoxAndWindowOpacity()
      }))
    case PK.showRemainingTime.rawValue:
      if let newValue = change[.newKey] as? Bool {
        rightLabel.mode = newValue ? .remaining : .duration
      }
    case PK.maxVolume.rawValue:
      if let newValue = change[.newKey] as? Int {
        if player.mpv.getDouble(MPVOption.Audio.volume) > Double(newValue) {
          player.mpv.setDouble(MPVOption.Audio.volume, Double(newValue))
        } else {
          updateVolumeUI()
        }
      }
    case PK.useExactSeek.rawValue:
      if let newValue = change[.newKey] as? Int {
        useExactSeek = Preference.SeekOption(rawValue: newValue)!
      }
    case PK.relativeSeekAmount.rawValue:
      if let newValue = change[.newKey] as? Int {
        relativeSeekAmount = newValue.clamped(to: 1...5)
      }
    case PK.volumeScrollAmount.rawValue:
      if let newValue = change[.newKey] as? Int {
        volumeScrollAmount = newValue.clamped(to: 1...4)
      }
    case PK.singleClickAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        singleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }
    case PK.doubleClickAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        doubleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }
    case PK.playlistShowMetadata.rawValue, PK.playlistShowMetadataInMusicMode.rawValue, PK.shortenFileGroupsInPlaylist.rawValue:
      if player.isPlaylistVisible {
        player.windowController.playlistView.playlistTableView.reloadData()
      }
    case PK.autoSwitchToMusicMode.rawValue:
      player.overrideAutoMusicMode = false

    case PK.keepOpenOnFileEnd.rawValue, PK.playlistAutoPlayNext.rawValue:
      player.mpv.updateKeepOpenOptionFromPrefs()

    case PK.enableOSC.rawValue,
      PK.oscPosition.rawValue,
      PK.topBarPlacement.rawValue,
      PK.bottomBarPlacement.rawValue,
      PK.oscBarHeight.rawValue,
      PK.oscBarPlaybackIconSize.rawValue,
      PK.oscBarPlaybackIconSpacing.rawValue,
      PK.oscBarToolbarIconSize.rawValue,
      PK.oscBarToolbarIconSpacing.rawValue,
      PK.showLeadingSidebarToggleButton.rawValue,
      PK.showTrailingSidebarToggleButton.rawValue,
      PK.controlBarToolbarButtons.rawValue,
      PK.allowVideoToOverlapCameraHousing.rawValue,
      PK.useLegacyWindowedMode.rawValue:

      log.verbose("Calling updateTitleBarAndOSC in response to pref change: \(keyPath.quoted)")
      updateTitleBarAndOSC()
    case PK.lockViewportToVideoSize.rawValue:
      if let isLocked = change[.newKey] as? Bool, isLocked {
        log.debug("Pref \(keyPath.quoted) changed to \(isLocked): resizing viewport to remove any excess space")
        resizeViewport()
      }
    case PK.hideWindowsWhenInactive.rawValue:
      animationPipeline.submitSudden({ [self] in
        refreshHidesOnDeactivateStatus()
      })

    case PK.thumbnailSizeOption.rawValue,
      PK.thumbnailFixedLength.rawValue,
      PK.thumbnailRawSizePercentage.rawValue,
      PK.enableThumbnailPreview.rawValue,
      PK.enableThumbnailForRemoteFiles.rawValue, 
      PK.enableThumbnailForMusicMode.rawValue:

      log.verbose("Pref \(keyPath.quoted) changed: requesting thumbs regen")
      // May need to remove thumbs or generate new ones: let method below figure it out:
      player.reloadThumbnails(forMedia: player.info.currentMedia)

    case PK.showChapterPos.rawValue:
      if let newValue = change[.newKey] as? Bool {
        playSlider.customCell.drawChapters = newValue
      }
    case PK.verticalScrollAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        verticalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }
    case PK.horizontalScrollAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        horizontalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }
    case PK.arrowButtonAction.rawValue:
      updateTitleBarAndOSC()
    case PK.blackOutMonitor.rawValue:
      if let newValue = change[.newKey] as? Bool {
        if isFullScreen {
          newValue ? blackOutOtherMonitors() : removeBlackWindows()
        }
      }
    case PK.useLegacyFullScreen.rawValue:
      updateUseLegacyFullScreen()
    case PK.displayTimeAndBatteryInFullScreen.rawValue:
      if let newValue = change[.newKey] as? Bool {
        displayTimeAndBatteryInFullScreen = newValue
        if !newValue {
          additionalInfoView.isHidden = true
        }
      }
    case PK.alwaysShowOnTopIcon.rawValue:
      updateOnTopButton()
    case PK.leadingSidebarPlacement.rawValue, PK.trailingSidebarPlacement.rawValue:
      updateSidebarPlacements()
    case PK.settingsTabGroupLocation.rawValue:
      if let newRawValue = change[.newKey] as? Int, let newLocationID = Preference.SidebarLocation(rawValue: newRawValue) {
        self.moveTabGroup(.settings, toSidebarLocation: newLocationID)
      }
    case PK.playlistTabGroupLocation.rawValue:
      if let newRawValue = change[.newKey] as? Int, let newLocationID = Preference.SidebarLocation(rawValue: newRawValue) {
        self.moveTabGroup(.playlist, toSidebarLocation: newLocationID)
      }
    case PK.osdAutoHideTimeout.rawValue:
      if let newTimeout = change[.newKey] as? Double {
        if osdAnimationState == .shown, let hideOSDTimer = hideOSDTimer, hideOSDTimer.isValid {
          // Reschedule timer to prevent prev long timeout from lingering
          self.hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(newTimeout), target: self,
                                                   selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
        }
      }
    case PK.osdPosition.rawValue:
      // If OSD is showing, it will move over as a neat animation:
      animationPipeline.submitSudden {
        self.updateOSDPosition()
      }
    case PK.osdTextSize.rawValue:
      animationPipeline.submitSudden { [self] in
        updateOSDTextSize()
      }
    case PK.aspectRatioPanelPresets.rawValue, PK.cropPanelPresets.rawValue:
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
  // Needs to be changed to align with either sidepanel or left of screen:
  @IBOutlet weak var topBarLeadingSpaceConstraint: NSLayoutConstraint!
  // Needs to be changed to align with either sidepanel or right of screen:
  @IBOutlet weak var topBarTrailingSpaceConstraint: NSLayoutConstraint!

  // - Bottom OSC constraints
  @IBOutlet weak var viewportBottomOffsetFromBottomBarTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var viewportBottomOffsetFromBottomBarBottomConstraint: NSLayoutConstraint!
  @IBOutlet var viewportBottomOffsetFromContentViewBottomConstraint: NSLayoutConstraint!
  // Needs to be changed to align with either sidepanel or left of screen:
  @IBOutlet weak var bottomBarLeadingSpaceConstraint: NSLayoutConstraint!
  // Needs to be changed to align with either sidepanel or right of screen:
  @IBOutlet weak var bottomBarTrailingSpaceConstraint: NSLayoutConstraint!

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
  @IBOutlet weak var osdIconHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdTopMarginConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdTrailingMarginConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdLeadingMarginConstraint: NSLayoutConstraint!
  @IBOutlet weak var osdBottomMarginConstraint: NSLayoutConstraint!

  // Sets the size of the spacer view in the top overlay which reserves space for a title bar:
  @IBOutlet weak var titleBarHeightConstraint: NSLayoutConstraint!
  /// Size of each side of the 3 square playback buttons ⏪⏯️⏩ (`leftArrowButton`, Play/Pause, `rightArrowButton`):
  @IBOutlet weak var playbackButtonsSquareWidthConstraint: NSLayoutConstraint!
  /// Space added to the left and right of *each* of the 3 square playback buttons:
  @IBOutlet weak var playbackButtonsHorizontalPaddingConstraint: NSLayoutConstraint!
  @IBOutlet weak var topOSCHeightConstraint: NSLayoutConstraint!

  @IBOutlet weak var timePositionHoverLabelHorizontalCenterConstraint: NSLayoutConstraint!
  @IBOutlet weak var timePositionHoverLabelVerticalSpaceConstraint: NSLayoutConstraint!
  @IBOutlet weak var playSliderHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var speedLabelVerticalConstraint: NSLayoutConstraint!

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
  @IBOutlet weak var bottomBarView: NSVisualEffectView!
  /// Top border of `bottomBarView`.
  @IBOutlet weak var bottomBarTopBorder: NSBox!

  @IBOutlet weak var timePositionHoverLabel: NSTextField!
  @IBOutlet weak var thumbnailPeekView: ThumbnailPeekView!
  @IBOutlet weak var leftArrowButton: NSButton!
  @IBOutlet weak var rightArrowButton: NSButton!

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
  @IBOutlet var oscBottomMainView: NSStackView!
  @IBOutlet weak var oscTopMainView: NSStackView!

  var fragToolbarView: NSStackView? = nil
  @IBOutlet weak var fragVolumeView: NSView!
  @IBOutlet var fragPositionSliderView: NSView!
  @IBOutlet weak var fragPlaybackControlButtonsView: NSView!

  @IBOutlet weak var speedLabel: NSTextField!

  @IBOutlet weak var osdVisualEffectView: NSVisualEffectView!
  @IBOutlet weak var osdHStackView: NSStackView!
  @IBOutlet weak var osdVStackView: NSStackView!
  @IBOutlet weak var osdIcon: NSTextField!
  @IBOutlet weak var osdLabel: NSTextField!
  @IBOutlet weak var osdAccessoryText: NSTextField!
  @IBOutlet weak var osdAccessoryProgress: NSProgressIndicator!

  @IBOutlet weak var pipOverlayView: NSVisualEffectView!
  @IBOutlet weak var viewportView: ViewportView!
  let defaultAlbumArtView = NSView()

  @IBOutlet weak var volumeSlider: NSSlider!
  @IBOutlet weak var muteButton: NSButton!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var playSlider: PlaySlider!
  @IBOutlet weak var rightLabel: DurationDisplayTextField!
  @IBOutlet weak var leftLabel: DurationDisplayTextField!

  /// Differentiate between single clicks and double clicks.
  internal var singleClickTimer: Timer?
  internal var mouseExitEnterCount = 0

  internal var hideCursorTimer: Timer?

  // Scroll direction

  /// The direction of current scrolling event.
  enum ScrollDirection {
    case horizontal
    case vertical
  }

  internal var scrollDirection: ScrollDirection?

  /** We need to pause the video when a user starts seeking by scrolling.
   This property records whether the video is paused initially so we can
   recover the status when scrolling finished. */
  private var wasPlayingBeforeSeeking = false

  /** Subclasses should set these value to true if the mouse is in some
   special views (e.g. volume slider, play slider) before calling
   `super.scrollWheel()` and set them back to false after calling
   `super.scrollWheel()`.*/
  internal var seekOverride = false
  internal var volumeOverride = false

  private var lastScrollWheelSeekTime: TimeInterval = 0
  var isInScrollWheelSeek: Bool {
    set {
      if newValue {
        lastScrollWheelSeekTime = Date().timeIntervalSince1970
      } else {
        lastScrollWheelSeekTime = 0
      }
    }
    get {
      Date().timeIntervalSince1970 - lastScrollWheelSeekTime < 0.5
    }
  }

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

  // MARK: - PIP

  lazy var _pip: PIPViewController = {
    let pip = VideoPIPViewController()
    if #available(macOS 10.12, *) {
      pip.delegate = self
    }
    return pip
  }()
  
  @available(macOS 10.12, *)
  var pip: PIPViewController {
    _pip
  }

  var pipVideo: NSViewController!

  // MARK: - Initialization

  init(playerCore: PlayerCore) {
    self.player = playerCore
    super.init(window: nil)
    log.verbose("PlayerWindowController init")
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func windowDidLoad() {
    log.verbose("PlayerWindow windowDidLoad starting")
    super.windowDidLoad()
    
    miniPlayer = MiniPlayerController()
    miniPlayer.windowController = self

    viewportView.player = player

    loaded = true

    guard let window = window else { return }
    guard let cv = window.contentView else { return }

    window.initialFirstResponder = nil

    viewportView.clipsToBounds = true
    topBarView.clipsToBounds = true
    bottomBarView.clipsToBounds = true

    /// Set `window.contentView`'s background to black so that the windows behind this one don't bleed through
    /// when `lockViewportToVideoSize` is disabled, or when in legacy full screen on a Macbook screen  with a
    /// notch and the preference `allowVideoToOverlapCameraHousing` is false.
    cv.wantsLayer = true
    // Need this to be black also, for sidebar animations
    viewportView.wantsLayer = true
    setEmptySpaceColor(to: Constants.Color.defaultWindowBackgroundColor)

    applyThemeMaterial()
    // Update to corect values before displaying. Only useful when restoring at launch
    updateUI()

    leftLabel.mode = .current
    rightLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

    // size
    window.minSize = AppData.minVideoSize

    // need to deal with control bar, so we handle it manually
    window.isMovableByWindowBackground  = false

    // Titlebar accessories

    // Update this here to reduce animation jitter on older versions of MacOS:
    viewportTopOffsetFromTopBarTopConstraint.constant = PlayerWindowController.standardTitleBarHeight

    addTitleBarAccessoryViews()

    // video view

    // gesture recognizers
    rotationHandler.windowController = self
    magnificationHandler.windowController = self
    cv.addGestureRecognizer(magnificationHandler.magnificationGestureRecognizer)
    cv.addGestureRecognizer(rotationHandler.rotationGestureRecognizer)

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
      cv.addSubview(view)
    }

    // Default album art
    defaultAlbumArtView.wantsLayer = true
    defaultAlbumArtView.alphaValue = 1
    defaultAlbumArtView.isHidden = true
    defaultAlbumArtView.layer?.contents = #imageLiteral(resourceName: "default-album-art")
    viewportView.addSubview(defaultAlbumArtView)
    defaultAlbumArtView.translatesAutoresizingMaskIntoConstraints = false
    // Add 1:1 aspect ratio constraint
    defaultAlbumArtView.widthAnchor.constraint(equalTo: defaultAlbumArtView.heightAnchor, multiplier: 1).isActive = true
    // Always fill superview
    defaultAlbumArtView.leadingAnchor.constraint(lessThanOrEqualTo: defaultAlbumArtView.superview!.leadingAnchor).isActive = true
    defaultAlbumArtView.trailingAnchor.constraint(greaterThanOrEqualTo: defaultAlbumArtView.superview!.trailingAnchor).isActive = true
    defaultAlbumArtView.topAnchor.constraint(lessThanOrEqualTo: defaultAlbumArtView.superview!.topAnchor).isActive = true
    defaultAlbumArtView.bottomAnchor.constraint(greaterThanOrEqualTo: defaultAlbumArtView.superview!.bottomAnchor).isActive = true
    // Center in superview
    defaultAlbumArtView.centerXAnchor.constraint(equalTo: defaultAlbumArtView.superview!.centerXAnchor).isActive = true
    defaultAlbumArtView.centerYAnchor.constraint(equalTo: defaultAlbumArtView.superview!.centerYAnchor).isActive = true

    playlistView.windowController = self
    quickSettingView.windowController = self

    // other initialization
    osdAccessoryProgress.usesThreadedAnimation = false
    if #available(macOS 10.14, *) {
      topBarBottomBorder.fillColor = NSColor(named: .titleBarBorder)!
    }

    // Do not make visual effects views opaque when window is not in focus
    for view in [topBarView, osdVisualEffectView, bottomBarView, controlBarFloating,
                 leadingSidebarView, trailingSidebarView, pipOverlayView, bufferIndicatorView] {
      view?.state = .active
    }

    let roundedCornerRadius: CGFloat = 6.0
    bufferIndicatorView.roundCorners(withRadius: roundedCornerRadius)
    osdVisualEffectView.roundCorners(withRadius: roundedCornerRadius)
    additionalInfoView.roundCorners(withRadius: roundedCornerRadius)
    
    if player.disableUI { hideFadeableViews() }

    // add notification observers

    // FIXME: these should be added at window open instead, and removed at window close!

    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil, using: { [unowned self] _ in
      // FIXME: this is not ready for production yet! Need to fix issues with freezing video
      guard Preference.bool(for: .togglePipWhenSwitchingSpaces) else { return }
      if !window.isOnActiveSpace && pipStatus == .notInPIP {
        animationPipeline.submitSudden({ [self] in
          log.debug("Window is no longer in active space; entering PIP")
          enterPIP()
          isWindowPipDueToInactiveSpace = true
        })
      } else if window.isOnActiveSpace && isWindowPipDueToInactiveSpace && pipStatus == .inPIP {
        animationPipeline.submitSudden({ [self] in
          log.debug("Window is in active space again; exiting PIP")
          isWindowPipDueToInactiveSpace = false
          exitPIP()
        })
      }
    })

    if #available(macOS 10.15, *) {
      addObserver(to: .default, forName: NSScreen.colorSpaceDidChangeNotification, object: nil) { [unowned self] noti in
        player.refreshEdrMode()
      }
    }

    addObserver(to: .default, forName: .iinaMediaTitleChanged, object: player) { [self] _ in
      updateTitle()
    }

    /// The `iinaFileLoaded` event is useful here because it is posted after `fileLoaded`.
    /// This ensures that `info.vid` will have been updated with the current audio track selection, or `0` if none selected.
    /// Before `fileLoaded` it may be `0` (indicating no selection) as the track info is still being processed, which is misleading.
    addObserver(to: .default, forName: .iinaFileLoaded, object: player) { [self] note in
      log.verbose("Got iinaFileLoaded notification")

      hideSeekTimeAndThumbnail()

      quickSettingView.reload()

      updateTitle()
      playlistView.scrollPlaylistToCurrentItem()

      if Preference.bool(for: .fullScreenWhenOpen) && !isFullScreen && !isInMiniPlayer && !player.info.isRestoring {
        log.debug("Changing to fullscreen because \(Preference.Key.fullScreenWhenOpen.rawValue)==Y")
        enterFullScreen()
      }
    }

    // This observer handles when the user connected a new screen or removed a screen, or shows/hides the Dock.
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: self.windowDidChangeScreenParameters)

    // Observe the loop knobs on the progress bar and update mpv when the knobs move.
    addObserver(to: .default, forName: .iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopA) { [weak self] _ in
      guard let self = self else { return }
      let seconds = self.percentToSeconds(self.playSlider.abLoopA.doubleValue)
      self.player.abLoopA = seconds
      self.player.sendOSD(.abLoopUpdate(.aSet, VideoTime(seconds).stringRepresentation))
    }
    addObserver(to: .default, forName: .iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopB) { [weak self] _ in
      guard let self = self else { return }
      let seconds = self.percentToSeconds(self.playSlider.abLoopB.doubleValue)
      self.player.abLoopB = seconds
      self.player.sendOSD(.abLoopUpdate(.bSet, VideoTime(seconds).stringRepresentation))
    }

    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [unowned self] _ in
      if Preference.bool(for: .pauseWhenGoesToSleep) {
        self.player.pause()
      }
    }

    PlayerWindowController.observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    log.verbose("PlayerWindow windowDidLoad done")
    player.events.emit(.windowLoaded)
  }

  deinit {
    removeObservers()
  }

  private func removeObservers() {
    ObjcUtils.silenced {
      for key in PlayerWindowController.observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }
  }

  internal func addObserver(to notificationCenter: NotificationCenter, forName name: Notification.Name, object: Any? = nil, using block: @escaping (Notification) -> Void) {
    notificationCenter.addObserver(forName: name, object: object, queue: .main, using: block)
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
    if let duration = player.info.videoDuration?.second {
      return duration * percent / 100
    } else if let position = player.info.videoPosition?.second {
      return position * percent / 100
    } else {
      return 0
    }
  }

  /// When entering "windowed" mode (either from initial load, PIP, or music mode), call this to add/return `videoView`
  /// to this window. Will do nothing if it's already there.
  func addVideoViewToWindow(_ geometry: PWGeometry) {
    guard let window else { return }
    videoView.$isUninited.withLock() { isUninited in
      guard !viewportView.subviews.contains(videoView) else { return }
      player.log.verbose("Adding videoView to viewportView, screenScaleFactor: \(window.screenScaleFactor)")
      /// Make sure `defaultAlbumArtView` stays above `videoView`
      viewportView.addSubview(videoView, positioned: .below, relativeTo: defaultAlbumArtView)
      videoView.videoLayer.autoresizingMask = CAAutoresizingMask(rawValue: 0)
      // Screen may have changed. Refresh contentsScale
      videoView.refreshContentsScale()
    }
    // add constraints
    videoView.translatesAutoresizingMaskIntoConstraints = false
    if !player.info.isRestoring {  // this can mess up music mode restore
      videoView.apply(geometry)
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
    animationPipeline.submitSudden { [self] in
      let oldLayout = currentLayout
      let newLayoutSpec = LayoutSpec.fromPreferences(fillingInFrom: oldLayout.spec)
      buildLayoutTransition(named: "UpdateTitleBarAndOSC", from: oldLayout, to: newLayoutSpec, thenRun: true)
    }
  }

  // MARK: - Key events

  // Returns true if handled
  @discardableResult
  func handleKeyBinding(_ keyBinding: KeyMapping) -> Bool {
    if let menuItem = keyBinding.menuItem {
      log.error("Key binding is attached to menu item: \(menuItem.title.quoted). Assuming it is disabled since it was not handled by MenuController")
      return false
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

          // beep if cmd failed
          return handleKeyBinding(keyBinding)
        }
        return false
      }, defaultHandler: {
        // invalid key
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

  // MARK: - Mouse / Trackpad events

  /// This method is provided soly for invoking plugin input handlers.
  func informPluginMouseDragged(with event: NSEvent) {
    PluginInputManager.handle(
      input: PluginInputManager.Input.mouse, event: .mouseDrag, player: player,
      arguments: mouseEventArgs(event)
    )
  }

  fileprivate func mouseEventArgs(_ event: NSEvent) -> [[String: Any]] {
    return [[
      "x": event.locationInWindow.x,
      "y": event.locationInWindow.y,
      "clickCount": event.clickCount,
      "pressure": event.pressure
    ] as [String : Any]]
  }

  fileprivate func keyEventArgs(_ event: NSEvent) -> [[String: Any]] {
    return [[
      "x": event.locationInWindow.x,
      "y": event.locationInWindow.y,
      "isRepeat": event.isARepeat
    ] as [String : Any]]
  }

  func isMouseEvent(_ event: NSEvent, inAnyOf views: [NSView?]) -> Bool {
    return views.filter { $0 != nil }.reduce(false, { (result, view) in
      return result || view!.isMousePoint(view!.convert(event.locationInWindow, from: nil), in: view!.bounds)
    })
  }

  /**
   Being called to perform single click action after timeout.

   - SeeAlso:
   mouseUp(with:)
   */
  @objc internal func performMouseActionLater(_ timer: Timer) {
    guard let action = timer.userInfo as? Preference.MouseClickAction else { return }
    if mouseExitEnterCount >= 2 && action == .hideOSC {
      /// the counter being greater than or equal to 2 means that the mouse re-entered the window
      /// `showFadeableViews()` must be called due to the movement in the window, thus `hideOSC` action should be cancelled
      return
    }
    performMouseAction(action)
  }

  override func pressureChange(with event: NSEvent) {
    if isCurrentPressInSecondStage == false && event.stage == 2 {
      performMouseAction(Preference.enum(for: .forceTouchAction))
      isCurrentPressInSecondStage = true
    } else if event.stage == 1 {
      isCurrentPressInSecondStage = false
    }
  }

  func restartHideCursorTimer() {
    if let timer = hideCursorTimer {
      timer.invalidate()
    }
    hideCursorTimer = Timer.scheduledTimer(timeInterval: max(0, Preference.double(for: .cursorAutoHideTimeout)), target: self, selector: #selector(hideCursor), userInfo: nil, repeats: false)
  }

  @objc private func hideCursor() {
    guard !currentLayout.isInteractiveMode, !currentLayout.isMusicMode else { return }
    if log.isTraceEnabled {
      log.verbose("Hiding cursor")
    }
    hideCursorTimer = nil
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  override func mouseDown(with event: NSEvent) {
    guard event.eventNumber != lastMouseDownEventID else { return }
    lastMouseDownEventID = event.eventNumber
    if Logger.enabled && Logger.Level.preferred >= .verbose {
      log.verbose("PlayerWindow mouseDown @ \(event.locationInWindow)")
    }
    if let controlBarFloating = controlBarFloating, !controlBarFloating.isHidden, isMouseEvent(event, inAnyOf: [controlBarFloating]) {
      controlBarFloating.mouseDown(with: event)
      return
    }
    if let cropSettingsView, !cropSettingsView.cropBoxView.isHidden, isMouseEvent(event, inAnyOf: [cropSettingsView.cropBoxView]) {
      log.verbose("PlayerWindow: mouseDown should have been handled by CropBoxView")
      return
    }
    // record current mouse pos
    mousePosRelatedToWindow = event.locationInWindow
    // Start resize if applicable
    let wasHandled = startResizingSidebar(with: event)
    guard !wasHandled else { return }

    restartHideCursorTimer()

    PluginInputManager.handle(
      input: PluginInputManager.Input.mouse, event: .mouseDown,
      player: player, arguments: mouseEventArgs(event)
    )
    // we don't call super here because before adding the plugin system,
    // PlayerWindowController didn't call super at all
  }

  override func mouseDragged(with event: NSEvent) {
    hideCursorTimer?.invalidate()
    if let controlBarFloating = controlBarFloating, !controlBarFloating.isHidden, controlBarFloating.isDragging {
      controlBarFloating.mouseDragged(with: event)
      return
    }
    if let cropSettingsView, cropSettingsView.cropBoxView.isDraggingToResize || cropSettingsView.cropBoxView.isDraggingNew {
      cropSettingsView.cropBoxView.mouseDragged(with: event)
      return
    }
    let didResizeSidebar = resizeSidebar(with: event)
    guard !didResizeSidebar else {
      return
    }

    if !isFullScreen && !controlBarFloating.isDragging {
      if let mousePosRelatedToWindow = mousePosRelatedToWindow {
        if !isDragging {
          /// Require that the user must drag the cursor at least a small distance for it to start a "drag" (`isDragging==true`)
          /// The user's action will only be counted as a click if `isDragging==false` when `mouseUp` is called.
          /// (Apple's trackpad in particular is very sensitive and tends to call `mouseDragged()` if there is even the slightest
          /// roll of the finger during a click, and the distance of the "drag" may be less than `minimumInitialDragDistance`)
          if mousePosRelatedToWindow.distance(to: event.locationInWindow) <= Constants.Distance.windowControllerMinInitialDragThreshold {
            return
          }
          if Logger.enabled && Logger.Level.preferred >= .verbose {
            log.verbose("PlayerWindow mouseDrag: minimum dragging distance was met")
          }
          isDragging = true
        }
        window?.performDrag(with: event)
        informPluginMouseDragged(with: event)
      }
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard event.eventNumber != lastMouseUpEventID else { return }
    lastMouseUpEventID = event.eventNumber
    if Logger.enabled && Logger.Level.preferred >= .verbose {
      log.verbose("PlayerWindow mouseUp @ \(event.locationInWindow), dragging: \(isDragging.yn), clickCount: \(event.clickCount): eventNum: \(event.eventNumber)")
    }

    restartHideCursorTimer()
    mousePosRelatedToWindow = nil

    if let cropSettingsView, cropSettingsView.cropBoxView.isDraggingToResize || cropSettingsView.cropBoxView.isDraggingNew {
      log.verbose("PlayerWindow mouseUp: finishing cropBoxView selection drag")
      cropSettingsView.cropBoxView.mouseUp(with: event)
    } else if let controlBarFloating = controlBarFloating, !controlBarFloating.isHidden,
        controlBarFloating.isDragging || isMouseEvent(event, inAnyOf: [controlBarFloating]) {
      log.verbose("PlayerWindow mouseUp: finished drag of floating OSC")
      controlBarFloating.mouseUp(with: event)
    } else if isDragging {
      // if it's a mouseup after dragging window
      log.verbose("PlayerWindow mouseUp: finished drag of window")
      isDragging = false
    } else if finishResizingSidebar(with: event) {
      log.verbose("PlayerWindow mouseUp: finished resizing sidebar")
    } else {
      // if it's a mouseup after clicking

      /// Single click. Note that `event.clickCount` will be 0 if there is at least one call to `mouseDragged()`,
      /// but we will only count it as a drag if `isDragging==true`
      if event.clickCount <= 1 && !isMouseEvent(event, inAnyOf: [leadingSidebarView, trailingSidebarView, subPopoverView,
                                                                 topBarView, bottomBarView]) {
        if hideSidebarsOnClick() {
          log.verbose("PlayerWindow mouseUp: hiding sidebars")
          return
        }
      }
      let titleBarMinY = window!.frame.height - PlayerWindowController.standardTitleBarHeight
      if event.clickCount == 2 {
        if !isFullScreen && (event.locationInWindow.y >= titleBarMinY) {
          if let userDefault = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            log.verbose("Double-click occurred in title bar. Executing \(userDefault.quoted)")
            if userDefault == "Minimize" {
              window?.performMiniaturize(nil)
            } else if userDefault == "Maximize" {
              window?.performZoom(nil)
            }
            return
          } else {
            log.verbose("Double-click occurred in title bar, but no action for AppleActionOnDoubleClick")
          }
        } else {
          log.verbose("Double-click did not occur inside title bar (minY: \(titleBarMinY)) or is full screen (\(isFullScreen))")
        }
      }

      guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else {
        player.log.verbose("MouseUp: click occurred in a disabled view; ignoring")
        super.mouseUp(with: event)
        return
      }
      PluginInputManager.handle(
        input: PluginInputManager.Input.mouse, event: .mouseUp, player: player,
        arguments: mouseEventArgs(event), defaultHandler: { [self] in
          // default handler
          if event.clickCount == 1 {
            if doubleClickAction == .none {
              performMouseAction(singleClickAction)
            } else {
              singleClickTimer = Timer.scheduledTimer(timeInterval: NSEvent.doubleClickInterval, target: self, selector: #selector(performMouseActionLater), userInfo: singleClickAction, repeats: false)
              mouseExitEnterCount = 0
            }
          } else if event.clickCount == 2 {
            if let timer = singleClickTimer {
              timer.invalidate()
              singleClickTimer = nil
            }
            performMouseAction(doubleClickAction)
          }
        })
    }
  }

  override func otherMouseDown(with event: NSEvent) {
    restartHideCursorTimer()
    super.otherMouseDown(with: event)
  }

  override func otherMouseUp(with event: NSEvent) {
    log.verbose("PlayerWindow otherMouseUp!")
    restartHideCursorTimer()
    guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else { return }

    PluginInputManager.handle(
      input: PluginInputManager.Input.otherMouse, event: .mouseUp, player: player,
      arguments: mouseEventArgs(event), defaultHandler: {
        if event.type == .otherMouseUp {
          self.performMouseAction(Preference.enum(for: .middleClickAction))
        } else {
          super.otherMouseUp(with: event)
        }
      })
  }

  /// Workaround for issue #4183, Cursor remains visible after resuming playback with the touchpad using secondary click
  ///
  /// AppKit contains special handling for [rightMouseDown](https://developer.apple.com/documentation/appkit/nsview/event_handling/1806802-rightmousedown) having to do with contextual menus.
  /// Even though the documentation indicates the event will be passed up the responder chain, the event is not being received by the
  /// window controller. We are having to catch the event in the view. Because of that we do not call the super method and instead
  /// return to the view.`
  override func rightMouseDown(with event: NSEvent) {
    guard event.eventNumber != lastRightMouseDownEventID else { return }
    lastRightMouseDownEventID = event.eventNumber
    log.verbose("PlayerWindow rightMouseDown!")

    if let controlBarFloating = controlBarFloating, !controlBarFloating.isHidden, isMouseEvent(event, inAnyOf: [controlBarFloating]) {
      controlBarFloating.rightMouseDown(with: event)
      return
    }
    restartHideCursorTimer()
    PluginInputManager.handle(
      input: PluginInputManager.Input.rightMouse, event: .mouseDown,
      player: player, arguments: mouseEventArgs(event)
    )
  }

  override func rightMouseUp(with event: NSEvent) {
    guard event.eventNumber != lastRightMouseUpEventID else { return }
    lastRightMouseUpEventID = event.eventNumber
    log.verbose("PlayerWindow rightMouseUp!")
    restartHideCursorTimer()
    guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else { return }

    PluginInputManager.handle(
      input: PluginInputManager.Input.rightMouse, event: .mouseUp, player: player,
      arguments: mouseEventArgs(event), defaultHandler: {
        self.performMouseAction(Preference.enum(for: .rightClickAction))
      })
  }

  func performMouseAction(_ action: Preference.MouseClickAction) {
    log.verbose("Performing mouseAction: \(action)")
    switch action {
    case .pause:
      player.togglePause()
    case .fullscreen:
      toggleWindowFullScreen()
    case .hideOSC:
      hideFadeableViews()
    case .togglePIP:
      if #available(macOS 10.12, *) {
        menuTogglePIP(.dummy)
      }
    case .contextMenu:
      showContextMenu()
    default:
      break
    }
  }

  private func showContextMenu() {
    // TODO
  }

  override func scrollWheel(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard !isMouseEvent(event, inAnyOf: [leadingSidebarView, trailingSidebarView, titleBarView, subPopoverView]) else { return }
    // TODO: tweak scroll so it doesn't get tripped so easily

    if isMouseEvent(event, inAnyOf: [fragPositionSliderView]) && playSlider.isEnabled {
      seekOverride = true
    } else if volumeSlider.isEnabled && (isInMiniPlayer && isMouseEvent(event, inAnyOf: [miniPlayer.volumeSliderView])
                                         || isMouseEvent(event, inAnyOf: [fragVolumeView])) {
      volumeOverride = true
    } else {
      guard !isMouseEvent(event, inAnyOf: [currentControlBar]) else { return }
    }

    let isMouse = event.phase.isEmpty
    let isTrackpadBegan = event.phase.contains(.began)
    let isTrackpadEnd = event.phase.contains(.ended)

    // determine direction

    if isMouse || isTrackpadBegan {
      if event.scrollingDeltaX != 0 {
        scrollDirection = .horizontal
      } else if event.scrollingDeltaY != 0 {
        scrollDirection = .vertical
      }
    } else if isTrackpadEnd {
      scrollDirection = nil
    }

    let scrollAction: Preference.ScrollAction
    if seekOverride {
      scrollAction = .seek
      isInScrollWheelSeek = true
    } else if volumeOverride {
      scrollAction = .volume
    } else {
      scrollAction = scrollDirection == .horizontal ? horizontalScrollAction : verticalScrollAction
      // show volume popover when volume seek begins and hide on end
      if scrollAction == .volume && isInMiniPlayer {
        player.windowController.miniPlayer.handleVolumePopover(isTrackpadBegan, isTrackpadEnd, isMouse)
      }
    }

    // pause video when seek begins

    if scrollAction == .seek && isTrackpadBegan {
      // record pause status
      if player.info.isPlaying {
        player.pause()
        wasPlayingBeforeSeeking = true
      }
    }

    if isTrackpadEnd && wasPlayingBeforeSeeking {
      // only resume playback when it was playing before seeking
      if wasPlayingBeforeSeeking {
        player.resume()
      }
      wasPlayingBeforeSeeking = false
    }

    // handle the delta value

    let isPrecise = event.hasPreciseScrollingDeltas
    let isNatural = event.isDirectionInvertedFromDevice

    var deltaX = isPrecise ? Double(event.scrollingDeltaX) : event.scrollingDeltaX.unifiedDouble
    var deltaY = isPrecise ? Double(event.scrollingDeltaY) : event.scrollingDeltaY.unifiedDouble * 2

    if isNatural {
      deltaY = -deltaY
    } else {
      deltaX = -deltaX
    }

    let delta = scrollDirection == .horizontal ? deltaX : deltaY

    // perform action

    switch scrollAction {
    case .seek:
      let seekAmount = (isMouse ? AppData.seekAmountMapMouse : AppData.seekAmountMap)[relativeSeekAmount] * delta
      player.seek(relativeSecond: seekAmount, option: useExactSeek)
      isInScrollWheelSeek = true
    case .volume:
      // don't use precised delta for mouse
      let newVolume = player.info.volume + (isMouse ? delta : AppData.volumeMap[volumeScrollAmount] * delta)
      player.setVolume(newVolume)
      if isInMiniPlayer {
        player.windowController.miniPlayer.volumeSlider.doubleValue = newVolume
      } else {
        volumeSlider.doubleValue = newVolume
      }
    default:
      break
    }

    seekOverride = false
    volumeOverride = false

    // Need to manually update the OSC & OSD because they may be missed otherwise
    updateUI()
  }

  override func mouseEntered(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard let area = event.trackingArea?.userInfo?[TrackingArea.key] as? TrackingArea else {
      log.warn("No data for tracking area")
      return
    }
    mouseExitEnterCount += 1

    switch area {
    case .playerWindow:
      isMouseInWindow = true
      showFadeableViews(duration: 0)
    case .playSlider:
      if controlBarFloating.isDragging { return }
      refreshSeekTimeAndThumbnail(from: event)
    case .customTitleBar:
      customTitleBar?.leadingTitleBarView.mouseEntered(with: event)
    }
  }

  override func mouseExited(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard let area = event.trackingArea?.userInfo?[TrackingArea.key] as? TrackingArea else {
      log.warn("No data for tracking area")
      return
    }
    mouseExitEnterCount += 1

    switch area {
    case .playerWindow:
      isMouseInWindow = false
      if controlBarFloating.isDragging { return }
      if !isAnimating && Preference.bool(for: .hideFadeableViewsWhenOutsideWindow) {
        hideFadeableViews()
      } else {
        // Closes loophole in case cursor hovered over OSC before exiting (in which case timer was destroyed)
        resetFadeTimer()
      }
    case .playSlider:
      refreshSeekTimeAndThumbnail(from: event)
    case .customTitleBar:
      customTitleBar?.leadingTitleBarView.mouseExited(with: event)
    }
  }

  override func mouseMoved(with event: NSEvent) {
    /// When using multiple monitors, `mouseExited` may not get fired when cursor moves directly from OSC to other screen.
    /// In this case, thumbnail & seek time can get stuck in the visible state. We can make this less annoying by hiding when other windows'
    /// events fire, like here...
    for playerWinCon in NSApplication.playerWindows {
      if playerWinCon != self {
        playerWinCon.hideSeekTimeAndThumbnail()
      }
    }
    guard !isInInteractiveMode else { return }

    /// Set or unset the cursor to `resizeLeftRight` if able to resize the sidebar
    if isMousePosWithinLeadingSidebarResizeRect(mousePositionInWindow: event.locationInWindow) ||
        isMousePosWithinTrailingSidebarResizeRect(mousePositionInWindow: event.locationInWindow) {
      if sidebarResizeCursor == nil {
        let newCursor = NSCursor.resizeLeftRight
        newCursor.push()
        sidebarResizeCursor = newCursor
      }
    } else {
      if let currentCursor = sidebarResizeCursor {
        currentCursor.pop()
        sidebarResizeCursor = nil
      }
    }

    refreshSeekTimeAndThumbnail(from: event)

    if isMouseInWindow {
      let isTopBarHoverEnabled = Preference.isAdvancedEnabled && Preference.enum(for: .showTopBarTrigger) == Preference.ShowTopBarTrigger.topBarHover
      let forceShowTopBar = isTopBarHoverEnabled && isMouseInTopBarArea(event) && fadeableTopBarAnimationState == .hidden
      // Check whether mouse is in OSC
      let shouldRestartFadeTimer = !isMouseEvent(event, inAnyOf: [currentControlBar, titleBarView])
      showFadeableViews(thenRestartFadeTimer: shouldRestartFadeTimer, duration: 0, forceShowTopBar: forceShowTopBar)
    }

    if isMouseInWindow || isFullScreen {
      // Always hide after timeout even if OSD fade time is longer
      restartHideCursorTimer()
    } else {
      hideCursorTimer?.invalidate()
      hideCursorTimer = nil
    }
  }

  // assumes mouse is in window
  private func isMouseInTopBarArea(_ event: NSEvent) -> Bool {
    if isMouseEvent(event, inAnyOf: [bottomBarView]) {
      return false
    }
    guard let window = window, let contentView = window.contentView else { return false }
    let heightThreshold = contentView.frame.height - currentLayout.topBarHeight
    return event.locationInWindow.y >= heightThreshold
  }

  @objc func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    magnificationHandler.handleMagnifyGesture(recognizer: recognizer)
  }

  @objc func handleRotationGesture(recognizer: NSRotationGestureRecognizer) {
    rotationHandler.handleRotationGesture(recognizer: recognizer)
  }

  // MARK: - Window delegate: Open / Close

  override func openWindow(_ sender: Any?) {
    guard let window = self.window, let cv = window.contentView else { return }
    isClosing = false
    isInitialSizeDone = false  // reset for reopen

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
    updateTitle()  // Need to call this here, or else when opening directly to fullscreen, window title is just "Window"
    window.isExcludedFromWindowsMenu = false

    resetCollectionBehavior()
    updateBufferIndicatorView()
    updateOSDPosition()
    addVideoViewToWindow(windowedModeGeo)

    /// `isOpen==true` if opening a new file in an already open window
    if isOpen, !player.info.isRestoring {
      /// `windowFrame` may be slightly off; update it
      if currentLayout.mode == .windowed {
        windowedModeGeo = currentLayout.buildGeometry(windowFrame: window.frame, screenID: bestScreen.screenID, 
                                                      videoAspect: windowedModeGeo.videoAspect)
        /// Set this so that `applyVidGeo` will use the correct window frame if it looks for it.
        /// Side effect: future opened windows may use this size even if this window wasn't closed. Should be ok?
        PlayerWindowController.windowedModeGeoLastClosed = windowedModeGeo
      } else if currentLayout.mode == .musicMode {
        /// Set this so that `applyVidGeo` will use the correct window frame if it looks for it.
        musicModeGeo = musicModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
        PlayerWindowController.musicModeGeoLastClosed = musicModeGeo
      }
    } else {
      // Restore layout from last launch or configure from prefs. Do not animate.
      setInitialWindowLayout()
    }

    // Unlike other windows, we need to show player window as soon as mpv starts because it will crash if it tries to render offscreen.
    if player.info.isRestoring {
      window.postWindowIsReadyToShow()
    }

    if !window.isMiniaturized {
      log.verbose("Showing Player Window")
      window.setIsVisible(true)
    }
    log.verbose("Hiding defaultAlbumArt for window open")
    defaultAlbumArtView.isHidden = true

    player.initVideo()
    videoView.startDisplayLink()

    log.verbose("PlayerWindow openWindow done")
  }

  func windowWillClose(_ notification: Notification) {
    log.verbose("Window will close")

    isClosing = true

    // Close PIP
    if pipStatus == .inPIP {
      if #available(macOS 10.12, *) {
        exitPIP()
      }
    }

    if currentLayout.isLegacyFullScreen {
      updatePresentationOptionsForLegacyFullScreen(entering: false)
    }

    // Stop playing. This will save state if configured to do so:
    player.stop()
    // stop tracking mouse event
    guard let window, let contentView = window.contentView else { return }
    contentView.trackingAreas.forEach(contentView.removeTrackingArea)
    playSlider.trackingAreas.forEach(playSlider.removeTrackingArea)

    // Reset state flags
    isWindowMiniturized = false
    player.overrideAutoMusicMode = false

    /// Use `!player.info.justOpenedFile` to prevent saving if there was an error loading video
    if !AppDelegate.shared.isTerminating && !player.info.justOpenedFile {
      /// Prepare window for possible reuse: restore default geometry, close sidebars, etc.
      if currentLayout.mode == .musicMode {
        PlayerWindowController.musicModeGeoLastClosed = musicModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
      } else if currentLayout.mode.isWindowed {
        // Update frame since it may have moved
        windowedModeGeo = windowedModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
        PlayerWindowController.windowedModeGeoLastClosed = windowedModeGeo
      }
    }
    lastWindowedLayoutSpec = LayoutSpec.defaultLayout()

    player.info.currentMedia = nil
    if player.info.isRestoring {
      log.verbose("Discarding unfinished restore cuz window closing")
      // May not have finishing restoring when user closes. Make sure to clean up here
      player.info.priorState = nil
      player.info.isRestoring = false
    }

    player.events.emit(.windowWillClose)
  }

  /// Hide menu bar & dock if current window is in legacy full screen.
  /// Show menu bar & dock if current window is not in full screen (either legacy or native).
  func updatePresentationOptionsForLegacyFullScreen(entering: Bool? = nil) {
    dispatchPrecondition(condition: .onQueue(.main))

    // Use currentLayout if not explicitly specified
    let isEnteringLegacyFS = entering ?? currentLayout.isLegacyFullScreen

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

  func windowDidFailToEnterFullScreen(_ window: NSWindow) {
    // FIXME: handle this
    log.error("Window failed to enter full screen!")
  }

  func windowDidFailToExitFullScreen(_ window: NSWindow) {
    // FIXME: handle this
    log.error("Window failed to exit full screen!")
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
      animationPipeline.submitSudden { [self] in
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
      let geo = geo(windowed: exitFSTransition.outputGeometry)
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
      animationPipeline.submitSudden({ [self] in
        animateEntryIntoFullScreen(withDuration: IINAAnimation.FullScreenTransitionDuration, isLegacy: true)
      })
    } else if !isFullScreen {
      window.toggleFullScreen(self)
    }
  }

  func exitFullScreen() {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }

    let isLegacyFS = currentLayout.isLegacyFullScreen

    if isLegacyFS {
      log.verbose("ExitFullScreen called, legacy=\(isLegacyFS.yn)")
      animationPipeline.submitSudden({ [self] in
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

  // MARK: - Window delegate: Resize

  func windowWillStartLiveResize(_ notification: Notification) {
    guard !isAnimatingLayoutTransition else { return }
    log.verbose("WindowWillStartLiveResize")
    isLiveResizingWidth = nil  // reset this
  }

  func windowWillResize(_ window: NSWindow, to requestedSize: NSSize) -> NSSize {
    guard !isAnimatingLayoutTransition else { return requestedSize }

    let currentLayout = currentLayout
    log.verbose("Win-WILL-Resize mode=\(currentLayout.mode) RequestedSize=\(requestedSize) isAnimatingTx=\(isAnimatingLayoutTransition.yn) denyNext=\(denyNextWindowResize.yn)")
    videoView.videoLayer.enterAsynchronousMode()

    if !currentLayout.isFullScreen && denyNextWindowResize {
      log.verbose("WinWillResize: denying this resize; will stay at \(window.frame.size)")
      denyNextWindowResize = false
      return window.frame.size
    }

    let lockViewportToVideoSize = Preference.bool(for: .lockViewportToVideoSize) || currentLayout.mode.alwaysLockViewportToVideoSize
    if lockViewportToVideoSize && window.inLiveResize {
      /// Notes on the trickiness of live window resize:
      /// 1. We need to decide whether to (A) keep the width fixed, and resize the height, or (B) keep the height fixed, and resize the width.
      /// "A" works well when the user grabs the top or bottom sides of the window, but will not allow resizing if the user grabs the left
      /// or right sides. Similarly, "B" works with left or right sides, but will not work with top or bottom.
      /// 2. We can make all 4 sides allow resizing by first checking if the user is requesting a different height: if yes, use "B";
      /// and if no, use "A".
      /// 3. Unfortunately (2) causes resize from the corners to jump all over the place, because in that case either height or width will change
      /// in small increments (depending on how fast the user moves the cursor) but this will result in a different choice between "A" or "B" schemes
      /// each time, with very different answers, which causes the jumpiness. In this case either scheme will work fine, just as long as we stick
      /// to the same scheme for the whole resize. So to fix this, we add `isLiveResizingWidth`, and once set, stick to scheme "B".
      if isLiveResizingWidth == nil {
        if window.frame.height != requestedSize.height {
          isLiveResizingWidth = false
        } else if window.frame.width != requestedSize.width {
          isLiveResizingWidth = true
        }
      }
      log.verbose("WinWillResize: PREV:\(window.frame.size), REQ:\(requestedSize) choseWidth:\(isLiveResizingWidth?.yesno ?? "nil")")
    }

    let isLiveResizingWidth = isLiveResizingWidth ?? true
    switch currentLayout.mode {
    case .windowed, .windowedInteractive:
      let newGeometry = resizeWindow(window, to: requestedSize, lockViewportToVideoSize: lockViewportToVideoSize, isLiveResizingWidth: isLiveResizingWidth)
      IINAAnimation.disableAnimation { [self] in
        videoView.apply(newGeometry)
      }
      return newGeometry.windowFrame.size

    case .fullScreen, .fullScreenInteractive:
      if currentLayout.isLegacyFullScreen {
        let newGeometry = currentLayout.buildFullScreenGeometry(inScreenID: windowedModeGeo.screenID, videoAspect: player.info.videoAspect)
        IINAAnimation.disableAnimation { [self] in
          videoView.apply(newGeometry)
        }
        return newGeometry.windowFrame.size
      } else {  // is native full screen
        // This method can be called as a side effect of the animation. If so, ignore.
        return requestedSize
      }

    case .musicMode:
      return miniPlayer.resizeWindow(window, to: requestedSize, isLiveResizingWidth: isLiveResizingWidth)
    }
  }

  /// Called after window is resized from (almost) any cause. Will be called many times during every call to `window.setFrame()`.
  /// Do not use `windowDidEndLiveResize`! It is unreliable. Use `windowDidResize` instead.
  /// Not currently used!
  func windowDidResize(_ notification: Notification) {
    // Do not want to trigger this during layout transition. It will mess up the intended viewport size.
    guard !player.info.isRestoring, !isClosing, !isAnimatingLayoutTransition, !isMagnifying else { return }
    log.verbose("Win-DID-Resize mode=\(currentLayout.mode) frame=\(window?.frame.debugDescription ?? "nil")")

    applyWindowResize()
  }

  // MARK: - Window Delegate: window move, screen changes

  func windowDidChangeBackingProperties(_ notification: Notification) {
    log.verbose("WindowDidChangeBackingProperties received")
    if videoView.refreshContentsScale() {
      // Do not allow MacOS to change the window size:
      log.verbose("Will deny next window resize")
      denyNextWindowResize = true
    }
  }

  // Note: this gets triggered by many unnecessary situations, e.g. several times each time full screen is toggled.
  func windowDidChangeScreen(_ notification: Notification) {
    var ticket: Int = 0
    $screenChangedTicketCounter.withLock {
      $0 += 1
      ticket = $0
    }

    // MacOS Sonoma sometimes blasts tons of these for unknown reasons. Attempt to prevent slowdown by de-duplicating
    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) { [self] in
      guard ticket == screenChangedTicketCounter else { return }
      guard let window = window, let screen = window.screen else { return }
      guard !isClosing, !player.isShuttingDown else { return }

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

      animationPipeline.submitSudden({ [self] in
        log.verbose("WindowDidChangeScreen (tkt \(ticket)): screenFrame=\(screen.frame)")
        videoView.updateDisplayLink()
        player.events.emit(.windowScreenChanged)
      })

      guard !player.info.isRestoring, !isAnimatingLayoutTransition else { return }

      animationPipeline.submit(IINAAnimation.Task(timing: .easeInEaseOut, { [self] in
        let screenID = bestScreen.screenID

        /// Need to recompute legacy FS's window size so it exactly fills the new screen.
        /// But looks like the OS will try to reposition the window on its own and can't be stopped...
        /// Just wait until after it does its thing before calling `setFrame()`.
        if currentLayout.isLegacyFullScreen {
          let layout = currentLayout
          guard layout.isLegacyFullScreen else { return }  // check again now that we are inside animation
          log.verbose("Updating legacy full screen window in response to WindowDidChangeScreen")
          let fsGeo = layout.buildFullScreenGeometry(inScreenID: screenID, videoAspect: player.info.videoAspect)
          applyLegacyFSGeo(fsGeo)
          // Update screenID at least, so that window won't go back to other screen when exiting FS
          windowedModeGeo = windowedModeGeo.clone(screenID: screenID)
          player.saveState()
        } else if currentLayout.mode == .windowed {
          // Update windowedModeGeo with new window position & screen (but preserve previous size)
          let newWindowFrame = NSRect(origin: window.frame.origin, size: windowedModeGeo.windowFrame.size)
          windowedModeGeo = windowedModeGeo.clone(windowFrame: newWindowFrame, screenID: screenID)
        }
      }))
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
      log.verbose("WindowDidChangeScreenParameters (tkt \(ticket)): screenIDs was \(cachedScreenIDs), is now \(screenIDs)")

      // Update the cached value
      self.cachedScreens = screens

      self.videoView.updateDisplayLink()

      guard !player.info.isRestoring, !isAnimatingLayoutTransition else { return }

      // In normal full screen mode AppKit will automatically adjust the window frame if the window
      // is moved to a new screen such as when the window is on an external display and that display
      // is disconnected. In legacy full screen mode IINA is responsible for adjusting the window's
      // frame.
      // Use very short duration. This usually gets triggered at the end when entering fullscreen, when the dock and/or menu bar are hidden.
      animationPipeline.submit(IINAAnimation.Task(duration: IINAAnimation.FullScreenTransitionDuration * 0.2, { [self] in
        let layout = currentLayout
        if layout.isLegacyFullScreen {
          guard layout.isLegacyFullScreen else { return }  // check again now that we are inside animation
          log.verbose("Updating legacy full screen window in response to ScreenParametersNotification")
          let fsGeo = layout.buildFullScreenGeometry(inside: bestScreen, videoAspect: player.info.videoAspect)
          applyLegacyFSGeo(fsGeo)
        } else if layout.mode == .windowed {
          /// In certain corner cases (e.g., exiting legacy full screen after changing screens while in full screen),
          /// the screen's `visibleFrame` can change after `transition.outputGeometry` was generated and won't be known until the end.
          /// By calling `refit()` here, we can make sure the window is constrained to the up-to-date `visibleFrame`.
          let oldGeo = windowedModeGeo
          let newGeo = oldGeo.refit()
          guard !newGeo.hasEqual(windowFrame: oldGeo.windowFrame, videoSize: oldGeo.videoSize) else {
            log.verbose("No need to update windowFrame in response to ScreenParametersNotification - no change")
            return
          }
          let newWindowFrame = newGeo.windowFrame
          log.verbose("Calling setFrame() in response to ScreenParametersNotification with windowFrame \(newWindowFrame), videoSize \(newGeo.videoSize)")
          videoView.apply(newGeo)
          player.window.setFrameImmediately(newWindowFrame, animate: false)
        }
      }))
    }
  }

  func windowDidMove(_ notification: Notification) {
    guard !isAnimating, !isAnimatingLayoutTransition, !isMagnifying, !player.info.isRestoring else { return }
    guard let window = window else { return }

    // We can get here if external calls from accessibility APIs change the window location.
    // Inserting a small delay seems to help to avoid race conditions as the window seems to need time to "settle"
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
      animationPipeline.submitSudden({ [self] in
        let layout = currentLayout
        if layout.isLegacyFullScreen {
          // MacOS (as of 14.0 Sonoma) sometimes moves the window around when there are multiple screens
          // and the user is changing focus between windows or apps. This can also happen if the user is using a third-party
          // window management app such as Amethyst. If this happens, move the window back to its proper place:
          let screen = bestScreen
          log.verbose("WindowDidMove: Updating legacy full screen window in response to unexpected windowDidMove to frame=\(window.frame), screen=\(screen.screenID.quoted)")
          let fsGeo = layout.buildFullScreenGeometry(inside: bestScreen, videoAspect: player.info.videoAspect)
          applyLegacyFSGeo(fsGeo)
        } else {
          player.saveState()
          player.events.emit(.windowMoved, data: window.frame)
        }
      })
    }
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

  // MARK: - Window delegate: Active status

  func windowDidBecomeKey(_ notification: Notification) {
    animationPipeline.submitSudden { [self] in
      log.verbose("WindowDidBecomeKey")
      if currentLayout.isLegacyFullScreen {
        log.verbose("WindowDidBecomeKey: resuming legacy FS window")
        window?.level = .iinaFloating
        updatePresentationOptionsForLegacyFullScreen(entering: true)
      }

      // If focus changed from a different window, need to recalculate the current bindings
      // so that this window's input sections are included and the other window's are not:
      AppInputConfig.rebuildCurrent()

      if Preference.bool(for: .pauseWhenInactive) && isPausedDueToInactive {
        log.verbose("WindowDidBecomeKey: resuming cuz isPausedDueToInactive")
        player.resume()
        isPausedDueToInactive = false
      }
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    animationPipeline.submitSudden { [self] in
      // keyWindow is nil: The whole app is inactive
      // keyWindow is another PlayerWindow: Switched to another video window
      let otherAppWindow = NSApp.keyWindow
      let wholeAppIsInactive = otherAppWindow == nil
      let otherPlayerWindow = otherAppWindow?.windowController as? PlayerWindowController
      let anotherAppWindowIsActive = !wholeAppIsInactive
      let anotherPlayerWindowIsActive = otherPlayerWindow != nil
      if wholeAppIsInactive || anotherPlayerWindowIsActive {
        if Preference.bool(for: .pauseWhenInactive), player.info.isPlaying {
          log.verbose("WindowDidResignKey: pausing cuz either wholeAppIsInactive (\(wholeAppIsInactive.yn)) or anotherPlayerWindowIsActive (\(anotherPlayerWindowIsActive.yn))")
          player.pause()
          isPausedDueToInactive = true
        }
      }
      if currentLayout.isLegacyFullScreen {
        /// Always restore window level from `floating` to `normal`, so that other windows aren't blocked and lead to confusion
        log.verbose("WindowDidResignKey: restoring legacy FS window level to normal")
        window?.level = .normal

        // Restore presentation options only for other windows in the same app which are not in FS!
        // For the case of other apps, MacOS will figure out what to do
        var shouldRestoreMenuBarAndDock = anotherAppWindowIsActive
        if let otherPlayerWindow, !otherPlayerWindow.currentLayout.isFullScreen {
          shouldRestoreMenuBarAndDock = true
        }
        if shouldRestoreMenuBarAndDock {
          log.verbose("WindowDidResignKey: relaxing legacy FS window because another non-FS app window is now active")
          /// Restore menu bar visibility
          updatePresentationOptionsForLegacyFullScreen(entering: false)
        }
      }
    }
  }

  func windowDidBecomeMain(_ notification: Notification) {
    guard let window else { return }
    animationPipeline.submitSudden { [self] in
      log.verbose("Window became main: \(window.savedStateName.quoted)")

      PlayerCore.lastActive = player
      if #available(macOS 10.13, *), RemoteCommandController.useSystemMediaControl {
        NowPlayingInfoManager.updateInfo(withTitle: true)
      }
      AppDelegate.shared.menuController?.updatePluginMenu()

      if isFullScreen && Preference.bool(for: .blackOutMonitor) {
        blackOutOtherMonitors()
      }

      if let customTitleBar {
        // The traffic light buttons should change to active
        customTitleBar.leadingTitleBarView.markButtonsDirty()
        customTitleBar.refreshTitle()
      }

      player.events.emit(.windowMainStatusChanged, data: true)
      NotificationCenter.default.post(name: .iinaPlayerWindowChanged, object: true)
    }
  }

  func windowDidResignMain(_ notification: Notification) {
    guard let window else { return }
    animationPipeline.submitSudden { [self] in
      log.verbose("Window is no longer main: \(window.savedStateName.quoted)")

      if Preference.bool(for: .blackOutMonitor) {
        removeBlackWindows()
      }

      if let customTitleBar {
        // The traffic light buttons should change to inactive
        customTitleBar.leadingTitleBarView.markButtonsDirty()
        customTitleBar.refreshTitle()
      }

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
    animationPipeline.submitSudden { [self] in
      log.verbose("Window did miniaturize")
      isWindowMiniturized = true
      if Preference.bool(for: .togglePipByMinimizingWindow) && !isWindowMiniaturizedDueToPip {
        if #available(macOS 10.12, *) {
          enterPIP()
        }
      }
      player.events.emit(.windowMiniaturized)
    }
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    animationPipeline.submitSudden { [self] in
      log.verbose("Window did deminiaturize")
      isWindowMiniturized = false
      if Preference.bool(for: .pauseWhenMinimized) && isPausedDueToMiniaturization {
        player.resume()
        isPausedDueToMiniaturization = false
      }
      if Preference.bool(for: .togglePipByMinimizingWindow) && !isWindowMiniaturizedDueToPip, 
          #available(macOS 10.12, *) {
        exitPIP()
      }
      player.events.emit(.windowDeminiaturized)
    }
  }

  // MARK: - UI: Show / Hide Fadeable Views

  func isUITimerNeeded() -> Bool {
//    log.verbose("Checking if UITimer needed. hasPermanentOSC:\(currentLayout.hasPermanentOSC.yn) fadeableViews:\(fadeableViewsAnimationState) topBar: \(fadeableTopBarAnimationState) OSD:\(osdAnimationState)")
    if currentLayout.hasPermanentOSC {
      return true
    }
    let showingFadeableViews = fadeableViewsAnimationState == .shown || fadeableViewsAnimationState == .willShow
    let showingFadeableTopBar = fadeableTopBarAnimationState == .shown || fadeableViewsAnimationState == .willShow
    let showingOSD = osdAnimationState == .shown || osdAnimationState == .willShow
    return showingFadeableViews || showingFadeableTopBar || showingOSD
  }

  // Shows fadeableViews and titlebar via fade
  func showFadeableViews(thenRestartFadeTimer restartFadeTimer: Bool = true,
                         duration: CGFloat = IINAAnimation.DefaultDuration,
                         forceShowTopBar: Bool = false) {
    guard !player.disableUI && !isInInteractiveMode else { return }
    let tasks: [IINAAnimation.Task] = buildAnimationToShowFadeableViews(restartFadeTimer: restartFadeTimer,
                                                                                 duration: duration,
                                                                                 forceShowTopBar: forceShowTopBar)
    animationPipeline.submit(tasks)
  }

  func buildAnimationToShowFadeableViews(restartFadeTimer: Bool = true,
                                         duration: CGFloat = IINAAnimation.DefaultDuration,
                                         forceShowTopBar: Bool = false) -> [IINAAnimation.Task] {
    var tasks: [IINAAnimation.Task] = []

    /// Default `showTopBarTrigger` setting to `.windowHover` if advanced settings not enabled
    let wantsTopBarVisible = forceShowTopBar || (!Preference.isAdvancedEnabled || Preference.enum(for: .showTopBarTrigger) == Preference.ShowTopBarTrigger.windowHover)

    guard !player.disableUI && !isInInteractiveMode else {
      return tasks
    }

    guard wantsTopBarVisible || fadeableViewsAnimationState == .hidden else {
      if restartFadeTimer {
        resetFadeTimer()
      } else {
        destroyFadeTimer()
      }
      return tasks
    }

    let currentLayout = self.currentLayout

    tasks.append(IINAAnimation.Task(duration: duration, { [self] in
      guard fadeableViewsAnimationState == .hidden || fadeableViewsAnimationState == .shown else { return }
      fadeableViewsAnimationState = .willShow
      player.refreshSyncUITimer(logMsg: "Showing fadeable views ")
      destroyFadeTimer()

      for v in fadeableViews {
        v.animator().alphaValue = 1
      }

      if wantsTopBarVisible {  // start top bar
        fadeableTopBarAnimationState = .willShow
        for v in fadeableViewsTopBar {
          v.animator().alphaValue = 1
        }

        if currentLayout.titleBar == .showFadeableTopBar {
          if currentLayout.spec.isLegacyStyle {
            customTitleBar?.view.animator().alphaValue = 1
          } else {
            for button in trafficLightButtons {
              button.alphaValue = 1
            }
            titleTextField?.alphaValue = 1
            documentIconButton?.alphaValue = 1
          }
        }
      }  // end top bar
    }))

    // Not animated, but needs to wait until after fade is done
    tasks.append(IINAAnimation.suddenTask { [self] in
      // if no interrupt then hide animation
      if fadeableViewsAnimationState == .willShow {
        fadeableViewsAnimationState = .shown
        for v in fadeableViews {
          v.isHidden = false
        }

        if restartFadeTimer {
          resetFadeTimer()
        }
      }

      if wantsTopBarVisible && fadeableTopBarAnimationState == .willShow {
        fadeableTopBarAnimationState = .shown
        for v in fadeableViewsTopBar {
          v.isHidden = false
        }

        if currentLayout.titleBar == .showFadeableTopBar {
          if currentLayout.spec.isLegacyStyle {
            customTitleBar?.view.isHidden = false
          } else {
            for button in trafficLightButtons {
              button.isHidden = false
            }
            titleTextField?.isHidden = false
            documentIconButton?.isHidden = false
          }
        }
      }  // end top bar
    })
    return tasks
  }

  @objc func hideFadeableViewsAndCursor() {
    // don't hide UI when dragging control bar
    if controlBarFloating.isDragging { return }
    if hideFadeableViews() {
      NSCursor.setHiddenUntilMouseMoves(true)
    }
  }

  @discardableResult
  private func hideFadeableViews() -> Bool {
    guard pipStatus == .notInPIP, (!(window?.isMiniaturized ?? false)), fadeableViewsAnimationState == .shown else {
      return false
    }

    var tasks: [IINAAnimation.Task] = []

    tasks.append(IINAAnimation.Task{ [self] in
      // Don't hide overlays when in PIP or when they are not actually shown
      destroyFadeTimer()
      fadeableViewsAnimationState = .willHide
      fadeableTopBarAnimationState = .willHide
      player.refreshSyncUITimer(logMsg: "Hiding fadeable views ")

      for v in fadeableViews {
        v.animator().alphaValue = 0
      }
      for v in fadeableViewsTopBar {
        v.animator().alphaValue = 0
      }
      /// Quirk 1: special handling for `trafficLightButtons`
      if currentLayout.titleBar == .showFadeableTopBar {
        if currentLayout.spec.isLegacyStyle {
          customTitleBar?.view.alphaValue = 0
        } else {
          documentIconButton?.alphaValue = 0
          titleTextField?.alphaValue = 0
          for button in trafficLightButtons {
            button.alphaValue = 0
          }
        }
      }
    })

    tasks.append(IINAAnimation.Task(duration: IINAAnimation.DefaultDuration) { [self] in
      // if no interrupt then hide animation
      guard fadeableViewsAnimationState == .willHide else { return }

      fadeableViewsAnimationState = .hidden
      fadeableTopBarAnimationState = .hidden
      for v in fadeableViews {
        v.isHidden = true
      }
      for v in fadeableViewsTopBar {
        v.isHidden = true
      }
      /// Quirk 1: need to set `alphaValue` back to `1` so that each button's corresponding menu items still work
      if currentLayout.titleBar == .showFadeableTopBar {
        if currentLayout.spec.isLegacyStyle {
          customTitleBar?.view.isHidden = true
        } else {
          hideBuiltInTitleBarViews(setAlpha: false)
        }
      }
    })

    animationPipeline.submit(tasks)
    return true
  }

  // MARK: - UI: Show / Hide Fadeable Views Timer

  func resetFadeTimer() {
    // If timer exists, destroy first
    destroyFadeTimer()

    // Create new timer.
    // Timer and animation APIs require Double, but we must support legacy prefs, which store as Float
    var timeout = Double(Preference.float(for: .controlBarAutoHideTimeout))
    if timeout < IINAAnimation.DefaultDuration {
      timeout = IINAAnimation.DefaultDuration
    }
    hideFadeableViewsTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideFadeableViewsAndCursor), userInfo: nil, repeats: false)
    hideFadeableViewsTimer?.tolerance = 0.1
  }

  private func destroyFadeTimer() {
    if let hideFadeableViewsTimer = hideFadeableViewsTimer {
      hideFadeableViewsTimer.invalidate()
      self.hideFadeableViewsTimer = nil
    }
  }

  // MARK: - UI: Title

  @objc
  func updateTitle() {
    guard let window else { return }
    guard let currentMedia = player.info.currentMedia else {
      log.verbose("Cannot update window title: currentMedia is nil")
      return
    }

    let title: String
    if isInMiniPlayer {
      miniPlayer.loadIfNeeded()
      let (mediaTitle, mediaAlbum, mediaArtist) = player.getMusicMetadata()
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
      title = currentMedia.url.lastPathComponent
      window.setTitleWithRepresentedFilename(currentMedia.url.path)
    }

    /// This call is needed when using custom window style, otherwise the window won't get added to the Window menu or the Dock.
    /// Oddly, there are 2 separate functions for adding and changing the item, but `addWindowsItem` has no effect if called more than once,
    /// while `changeWindowsItem` needs to be called if `addWindowsItem` was already called. To be safe, just call both.
    NSApplication.shared.addWindowsItem(window, title: title, filename: false)
    NSApplication.shared.changeWindowsItem(window, title: title, filename: false)

    log.verbose("Updating window title to: \(title.pii.quoted)")
    customTitleBar?.refreshTitle()
  }

  // MARK: - UI: OSD

  private func updateOSDPosition() {
    guard let contentView = window?.contentView else { return }
    contentView.removeConstraint(leadingSidebarToOSDSpaceConstraint)
    contentView.removeConstraint(trailingSidebarToOSDSpaceConstraint)
    let osdPosition: Preference.OSDPosition = Preference.enum(for: .osdPosition)
    switch osdPosition {
    case .topLeading:
      // OSD on left, AdditionalInfo on right
      leadingSidebarToOSDSpaceConstraint = leadingSidebarView.trailingAnchor.constraint(equalTo: osdVisualEffectView.leadingAnchor, constant: -8.0)
      trailingSidebarToOSDSpaceConstraint = trailingSidebarView.leadingAnchor.constraint(equalTo: additionalInfoView.trailingAnchor, constant: 8.0)
    case .topTrailing:
      // AdditionalInfo on left, OSD on right
      leadingSidebarToOSDSpaceConstraint = leadingSidebarView.trailingAnchor.constraint(equalTo: additionalInfoView.leadingAnchor, constant: -8.0)
      trailingSidebarToOSDSpaceConstraint = trailingSidebarView.leadingAnchor.constraint(equalTo: osdVisualEffectView.trailingAnchor, constant: 8.0)
    }

    leadingSidebarToOSDSpaceConstraint.priority = .defaultHigh
    leadingSidebarToOSDSpaceConstraint.isActive = true
    trailingSidebarToOSDSpaceConstraint.isActive = true
    contentView.layoutSubtreeIfNeeded()
  }

  private func setOSDViews(fromMessage message: OSDMessage) {
    dispatchPrecondition(condition: .onQueue(.main))
    let (osdText, osdType) = message.details()

    var icon: NSImage? = nil
    var isImageDisabled = false
    if #available(macOS 11.0, *) {
      if message.isSoundRelated {
        // Add sound icon which indicates current audio status.
        // Gray color == disabled. Slash == muted. Can be combined

        let isAudioDisabled = !player.info.isAudioTrackSelected
        let currentVolume = player.info.volume
        let isMuted = player.info.isMuted
        isImageDisabled = isAudioDisabled
        if isMuted {
          icon = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: "Audio is muted")!
        } else if isAudioDisabled {
          icon = NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: "No audio track is selected")!
        } else {
          if #available(macOS 13.0, *) {
            // Vary icon slightly based on volume level
            icon = NSImage(systemSymbolName: "speaker.wave.3.fill", variableValue: currentVolume, accessibilityDescription: "Sound is enabled")!
          } else {
            icon = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: "Sound is enabled")!
          }
        }
      } else {
        switch message {
        case .resume:
          icon = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")!
        case .pause:
          icon = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")!
        case .stop:
          icon = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")!
        case .seek:
          icon = osdCurrentSeekIcon
        default:
          break
        }
      }
    }

    if let icon {
      let attachment = NSTextAttachment()
      attachment.image = icon
      let iconString = NSMutableAttributedString(attachment: attachment)
      if isImageDisabled {
        iconString.addAttributes([.foregroundColor: NSColor.disabledControlTextColor], range: NSMakeRange(0, iconString.length))
      }
      osdIcon.isHidden = false
      osdIcon.attributedStringValue = iconString
      osdLabel.stringValue = osdText

      if #available(macOS 11.0, *) {
        // Need this only for OSD messages which use the icon, and MacOS 11.0+
        osdIconHeightConstraint.priority = .required
      }
    } else {
      // No icon
      osdIcon.isHidden = true
      osdIcon.stringValue = ""
      osdLabel.stringValue = osdText

      osdIconHeightConstraint.constant = 0
      osdIconHeightConstraint.priority = .defaultLow
    }

    switch osdType {
    case .normal:
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryProgress)
    case .withProgress(let value):
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.mustHold, for: osdAccessoryProgress)
      osdAccessoryProgress.doubleValue = value
    case .withText(let text):
      osdVStackView.setVisibilityPriority(.mustHold, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryProgress)

      // data for mustache redering
      let osdData: [String: String] = [
        "duration": player.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "position": player.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "currChapter": (player.mpv.getInt(MPVProperty.chapter) + 1).description,
        "chapterCount": player.info.chapters.count.description
      ]
      osdAccessoryText.stringValue = try! (try! Template(string: text)).render(osdData)
    }
  }

  /// If `position` and `duration` are different than their previously cached values, overwrites the cached values and
  /// returns `true`. Returns `false` if the same or one of the values is `nil`.
  ///
  /// Lots of redundant `seek` messages which are emitted at all sorts of different times, and each triggers a call to show
  /// a `seek` OSD. To prevent duplicate OSDs, call this method to compare against the previous seek position.
  private func compareAndSetIfNewPlaybackTime(position: Double?, duration: Double?) -> Bool {
    guard let position, let duration else {
      log.verbose("Ignoring request for OSD seek: position or duration is missing")
      return false
    }
    // There seem to be precision errors which break equality when comparing values beyond 6 decimal places.
    // Just round to nearest 1/1000000 sec for comparison.
    let newPosRounded = round(position * AppData.osdSeekSubSecPrecisionComparison)
    let newDurRounded = round(duration * AppData.osdSeekSubSecPrecisionComparison)
    let oldPosRounded = round((osdLastPlaybackPosition ?? -1) * AppData.osdSeekSubSecPrecisionComparison)
    let oldDurRounded = round((osdLastPlaybackDuration ?? -1) * AppData.osdSeekSubSecPrecisionComparison)
    guard newPosRounded != oldPosRounded || newDurRounded != oldDurRounded else {
      log.verbose("Ignoring request for OSD seek; position/duration has not changed")
      return false
    }
    osdLastPlaybackPosition = position
    osdLastPlaybackDuration = duration
    return true
  }

  func clearOSDQueue() {
    osdQueueLock.withLock {
      osdQueue.clear()
    }
  }

  /// Do not call `displayOSD` directly. Call `PlayerCore.sendOSD` instead.
  ///
  /// There is a timing issue that can occur when the user holds down a key to rapidly repeat a key binding or menu item equivalent,
  /// which should result in an OSD being displayed for each keypress. But for some reason, the task to update the OSD,
  /// which is enqueued via `DispatchQueue.main.async` (or even `sync`), does not run at all while the key events continue to come in.
  /// To work around this issue, we instead enqueue the tasks to display OSD using a simple LinkedList and Lock. Then we call
  /// `updateUI()` both from here (as before), and inside the key event callbacks in `PlayerWindow` so that that the key events
  /// themselves process the display of any enqueued OSD messages.
  func displayOSD(_ msg: OSDMessage, autoHide: Bool = true, forcedTimeout: Double? = nil,
                  accessoryViewController: NSViewController? = nil, isExternal: Bool = false) {
    guard player.canShowOSD() else { return }

    let disableOSDForFileLoading: Bool = player.info.justOpenedFile || player.info.timeSinceLastFileOpenFinished < 0.2
    if disableOSDForFileLoading && !isExternal {
      switch msg {
      case .fileStart,
          .resumeFromWatchLater:
        break
      default:
        return
      }
    }

    // Enqueue first, in case main queue is blocked
    osdQueueLock.withLock {
      osdQueue.append({ [self] in
        animationPipeline.submitSudden{ [self] in
          _displayOSD(msg, autoHide: autoHide, forcedTimeout: forcedTimeout, accessoryViewController: accessoryViewController)
        }
      })
    }
    // Need to do the UI sync in the main queue
    DispatchQueue.main.async { [self] in
      updateUI()
    }
  }

  private func _displayOSD(_ msg: OSDMessage, autoHide: Bool = true, forcedTimeout: Double? = nil,
                           accessoryViewController: NSViewController? = nil) {
    dispatchPrecondition(condition: .onQueue(.main))

    // Check again. May have been enqueued a while
    guard player.canShowOSD() else { return }

    // Filter out unwanted OSDs first

    guard !isShowingPersistentOSD || accessoryViewController != nil else { return }

    var msg = msg
    switch msg {
    case .seek(_, _):
      // Many redundant messages are sent from mpv. Try to filter them out here
      if osdDidShowLastMsgRecently() {
        if case .speed = osdLastDisplayedMsg { return }
        if case .frameStep = osdLastDisplayedMsg { return }
        if case .frameStepBack = osdLastDisplayedMsg { return }
      }
      player.updatePlaybackTimeInfo()  // need to call this to update info.videoPosition, info.videoDuration
      guard compareAndSetIfNewPlaybackTime(position: player.info.videoPosition?.second, duration: player.info.videoDuration?.second) else {
        // Is redundant msg; discard
        return
      }
    case .pause, .resume:
      if osdDidShowLastMsgRecently() {
        if case .speed = osdLastDisplayedMsg, case .resume = msg { return }
        if case .frameStep = osdLastDisplayedMsg { return }
        if case .frameStepBack = osdLastDisplayedMsg { return }
      }
      player.updatePlaybackTimeInfo()  // need to call this to update info.videoPosition, info.videoDuration
      osdLastPlaybackPosition = player.info.videoPosition?.second
      osdLastPlaybackDuration = player.info.videoDuration?.second
    case .crop(let newCropLabel):
      if newCropLabel == AppData.noneCropIdentifier && !isInInteractiveMode && player.info.videoFiltersDisabled[Constants.FilterLabel.crop] != nil {
        log.verbose("Ignoring request to show OSD crop 'None': looks like user starting to edit an existing crop")
        return
      }
    case .resumeFromWatchLater:
      if case .fileStart(let filename, _) = osdLastDisplayedMsg {
        // Append details msg indicating restore state to existing msg
        let detailsMsg = msg.details().0
        msg = .fileStart(filename, detailsMsg)
      }

    default:
      break
    }

    // End filtering

    osdLastDisplayedMsg = msg

    if #available(macOS 11.0, *) {

      /// The pseudo-OSDMessage `seekRelative`, if present, contains the step time for a relative seek.
      /// But because it needs to be parsed from the mpv log, it is sent as a separate msg which arrives immediately
      /// prior to the `seek` msg. With some smart logic, the info from the two messages can be combined to display
      /// the most appropriate "jump" icon in the OSD in addition to the time display & progress bar.
      if case .seekRelative(let stepString) = msg, let step = Double(stepString) {
        log.verbose("Got OSD '\(msg)'")

        let isBackward = step < 0
        let accDescription = "Relative Seek \(isBackward ? "Backward" : "Forward")"
        var name: String
        if isInScrollWheelSeek {
          name = isBackward ? "backward.fill" : "forward.fill"
        } else {
          switch abs(step) {
          case 5, 10, 15, 30, 45, 60, 75, 90:
            let absStep = Int(abs(step))
            name = isBackward ? "gobackward.\(absStep)" : "goforward.\(absStep)"
          default:
            name = isBackward ? "gobackward.minus" : "goforward.plus"
          }
        }
        /// Set icon for next msg, which is expected to be a `seek`
        osdNextSeekIcon = NSImage(systemSymbolName: name, accessibilityDescription: accDescription)!
        /// Done with `seekRelative` msg. It is not used for display.
        return
      } else if case .seek(_, _) = msg {
        /// Shift next icon into current icon, which will be used until the next call to `displayOSD()`
        /// (although note that there can be subsequent calls to `setOSDViews()` to update the OSD's displayed time while playing,
        /// but those do not count as "new" OSD messages, and thus will continue to use `osdCurrentSeekIcon`).
        if osdNextSeekIcon != nil || !isInScrollWheelSeek {  // fudge this a bit for scroll wheel seek to look better
          osdCurrentSeekIcon = osdNextSeekIcon
          osdNextSeekIcon = nil
        }
      } else {
        osdCurrentSeekIcon = nil
      }
    }

    // Restart timer
    hideOSDTimer?.invalidate()
    if osdAnimationState != .shown {
      osdAnimationState = .shown  /// set this before calling `refreshSyncUITimer()`
      DispatchQueue.main.async { [self] in  /// launch async task to avoid recursion, which `osdQueueLock` doesn't like
        player.refreshSyncUITimer()
      }
    } else {
      osdAnimationState = .shown
    }

    if autoHide {
      let timeout: Double
      if let forcedTimeout = forcedTimeout {
        timeout = forcedTimeout
        log.verbose("Showing OSD '\(msg)', forced timeout: \(timeout) s")
      } else {
        // Timer and animation APIs require Double, but we must support legacy prefs, which store as Float
        timeout = max(IINAAnimation.OSDAnimationDuration, Double(Preference.float(for: .osdAutoHideTimeout)))
        log.verbose("Showing OSD '\(msg)', timeout: \(timeout) s")
      }
      hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
    } else {
      log.verbose("Showing OSD '\(msg)', no timeout")
    }

    updateOSDTextSize()
    setOSDViews(fromMessage: msg)

    let existingAccessoryViews = osdVStackView.views(in: .bottom)
    if !existingAccessoryViews.isEmpty {
      for subview in osdVStackView.views(in: .bottom) {
        osdVStackView.removeView(subview)
      }
    }
    if let accessoryViewController {  // e.g., ScreenshootOSDView
      let accessoryView = accessoryViewController.view
      osdContext = accessoryViewController
      isShowingPersistentOSD = true

      if #available(macOS 10.14, *) {} else {
        accessoryView.appearance = NSAppearance(named: .vibrantDark)
      }

      osdVStackView.addView(accessoryView, in: .bottom)
    }

    osdVisualEffectView.layoutSubtreeIfNeeded()
    osdVisualEffectView.alphaValue = 1
    osdVisualEffectView.isHidden = false
    fadeableViews.remove(osdVisualEffectView)
  }

  @objc
  func hideOSD(immediately: Bool = false) {
    dispatchPrecondition(condition: .onQueue(.main))
    log.verbose("Hiding OSD")
    osdAnimationState = .willHide
    isShowingPersistentOSD = false
    osdContext = nil
    hideOSDTimer?.invalidate()

    player.refreshSyncUITimer()

    IINAAnimation.runAsync(IINAAnimation.Task(duration: immediately ? 0 : IINAAnimation.OSDAnimationDuration, { [self] in
      osdVisualEffectView.alphaValue = 0
    }), then: {
      if self.osdAnimationState == .willHide {
        self.osdAnimationState = .hidden
        self.osdVisualEffectView.isHidden = true
        self.osdVStackView.views(in: .bottom).forEach { self.osdVStackView.removeView($0) }
      }
    })
  }

  func updateOSDTextSize() {
    // Reduce text size if horizontal space is tight
    var osdTextSize = max(8.0, CGFloat(Preference.float(for: .osdTextSize)))
    let availableSpaceForOSD = currentLayout.spec.getWidthBetweenInsideSidebars(in: viewportView.frame.size.width)
    switch availableSpaceForOSD {
    case ..<300:
      osdTextSize = min(osdTextSize, 18)
    case 300..<400:
      osdTextSize = min(osdTextSize, 28)
    case 400..<500:
      osdTextSize = min(osdTextSize, 36)
    case 500..<700:
      osdTextSize = min(osdTextSize, 50)
    case 700..<900:
      osdTextSize = min(osdTextSize, 72)
    case 900..<1200:
      osdTextSize = min(osdTextSize, 96)
    case 1200..<1500:
      osdTextSize = min(osdTextSize, 120)
    default:
      osdTextSize = min(osdTextSize, 150)
    }

    let osdAccessoryTextSize = (osdTextSize * 0.75).clamped(to: 11...25)
    osdAccessoryText.font = NSFont.monospacedDigitSystemFont(ofSize: osdAccessoryTextSize, weight: .regular)

    let fullMargin = 8 + (osdTextSize * 0.12)
    let halfMargin = fullMargin * 0.5
    osdTopMarginConstraint.constant = halfMargin
    osdBottomMarginConstraint.constant = halfMargin
    osdTrailingMarginConstraint.constant = fullMargin
    osdLeadingMarginConstraint.constant = fullMargin

    let osdLabelFont = NSFont.monospacedDigitSystemFont(ofSize: osdTextSize, weight: .regular)
    osdLabel.font = osdLabelFont

    if #available(macOS 11.0, *) {
      switch osdTextSize {
      case 32...:
        osdAccessoryProgress.controlSize = .regular
      default:
        osdAccessoryProgress.controlSize = .small
      }
    }

    let osdIconTextSize = (osdTextSize * 1.1) + (osdAccessoryProgress.fittingSize.height * 1.5)
    let osdIconFont = NSFont.monospacedDigitSystemFont(ofSize: osdIconTextSize, weight: .regular)
    osdIcon.font = osdIconFont

    if #available(macOS 11.0, *) {
      // Use dimensions of a dummy image to keep the height fixed. Because all the components are vertically aligned
      // and each icon has a different height, this is needed to prevent the progress bar from jumping up and down
      // each time the OSD message changes.
      let attachment = NSTextAttachment()
      attachment.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "")!
      let iconString = NSMutableAttributedString(attachment: attachment)
      iconString.addAttribute(.font, value: osdIconFont, range: NSRange(location: 0, length: iconString.length))
      let iconHeight = iconString.size().height

      osdIconHeightConstraint.constant = iconHeight
    } else {
      // don't use constraint for older versions. OSD text's vertical position may change depending on icon
      osdIconHeightConstraint.priority = .defaultLow
      osdIconHeightConstraint.constant = 0
    }
  }

  // MARK: - UI: Interactive mode


  func enterInteractiveMode(_ mode: InteractiveMode) {
    let currentLayout = currentLayout
    // Especially needed to avoid duplicate transitions
    guard currentLayout.canEnterInteractiveMode else { return }
    guard let window else { return }

    player.mpv.queue.async { [self] in
      let videoGeo = player.info.videoGeo
      guard let videoSizeRaw = videoGeo.videoSizeRaw, videoGeo.videoSizeACR != nil else {
        log.debug("Cannot enter interactive mode: missing videoSizeACR from \(videoGeo)")
        DispatchQueue.main.async {
          Utility.showAlert("no_video_track")
        }
        return
      }

      log.verbose("Entering interactive mode: \(mode)")

      // TODO: use key binding interceptor to support ESC and ENTER keys for interactive mode

      if mode == .crop, let vf = player.info.videoGeo.cropFilter {
        log.error("Crop mode requested, but found an existing crop filter (\(vf.stringFormat.quoted)). Will remove it before entering")
        // A crop is already set. Need to temporarily remove it so that the whole video can be seen again,
        // so that a new crop can be chosen. But keep info from the old filter in case the user cancels.
        player.info.videoFiltersDisabled[vf.label!] = vf
        // Change this pre-emptively so that removeVideoFilter doesn't trigger a window geometry change
        player.info.videoGeo = player.info.videoGeo.clone(selectedCropLabel: AppData.noneCropIdentifier)
        if !player.removeVideoFilter(vf) {
          log.error("Failed to remove prev crop filter: (\(vf.stringFormat.quoted)) for some reason. Will ignore and try to proceed anyway")
        }
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
          case .windowed:
            let oldVideoAspect = prevCropBox.size.mpvAspect
            // Scale viewport to roughly match window size
            assert(windowedModeGeo.mode == .windowed)
            let lockViewportToVideoSize = Preference.bool(for: .lockViewportToVideoSize)
            var uncroppedClosedBarsGeo = windowedModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
              .withResizedBars(outsideTopBarHeight: 0, outsideTrailingBarWidth: 0,
                               outsideBottomBarHeight: 0, outsideLeadingBarWidth: 0,
                               insideTopBarHeight: 0, insideTrailingBarWidth: 0,
                               insideBottomBarHeight: 0, insideLeadingBarWidth: 0,
                               videoAspect: newVideoAspect,
                               keepFullScreenDimensions: !lockViewportToVideoSize)

            if lockViewportToVideoSize {
              // Otherwise try to avoid shrinking the window too much if the aspect changes dramatically.
              // This heuristic seems to work ok
              let viewportSize = uncroppedClosedBarsGeo.viewportSize
              let aspectChangeFactor = newVideoAspect / oldVideoAspect
              let viewportSizeMultiplier = (aspectChangeFactor < 0) ? (1.0 / aspectChangeFactor) : aspectChangeFactor
              var newViewportSize = viewportSize.multiply(viewportSizeMultiplier)

              // Calculate viewport size needed to satisfy min margins of interactive mode, then grow video at least as large
              let minViewportSizeIM = uncroppedClosedBarsGeo.minViewportSize(mode: .windowedInteractive)
              let minViewportSizeWindowed = PWGeometry.computeMinSize(withAspect: newVideoAspect,
                                                                      minWidth: minViewportSizeIM.width,
                                                                      minHeight: minViewportSizeIM.height)
              let minViewportMarginsIM = PWGeometry.minViewportMargins(forMode: .windowedInteractive)
              newViewportSize = NSSize(width: max(newViewportSize.width + minViewportMarginsIM.totalWidth, minViewportSizeWindowed.width),
                                       height: max(newViewportSize.height + minViewportMarginsIM.totalHeight, minViewportSizeWindowed.height))

              log.verbose("EnterInteractiveMode: aspectChangeFactor:\(aspectChangeFactor), viewportSizeMultiplier: \(viewportSizeMultiplier), newViewportSize:\(newViewportSize)")
              uncroppedClosedBarsGeo = uncroppedClosedBarsGeo.scaleViewport(to: newViewportSize)
            } else {
              // If not locking viewport to video, just reuse viewport
              uncroppedClosedBarsGeo = uncroppedClosedBarsGeo.refit()
            }
            log.verbose("EnterInteractiveMode: Generated uncroppedGeo: \(uncroppedClosedBarsGeo)")

            // TODO: integrate this task into LayoutTransition build
            let uncropDuration = IINAAnimation.CropAnimationDuration * 0.1
            tasks.append(IINAAnimation.Task(duration: uncropDuration, timing: .easeInEaseOut) { [self] in
              isAnimatingLayoutTransition = true  // tell window resize listeners to do nothing
              videoView.apply(uncroppedClosedBarsGeo)
              player.window.setFrameImmediately(uncroppedClosedBarsGeo.windowFrame)
            })

            // supply an override for windowedModeGeo here, because it won't be set until the animation above executes
            let geoOverride = geo(windowed: uncroppedClosedBarsGeo, videoAspect: newVideoAspect)
            tasks.append(contentsOf: buildTransitionToEnterInteractiveMode(.crop, geoOverride))

          case .fullScreen:

            let geoOverride = geo(videoAspect: newVideoAspect)
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

  func buildTransitionToEnterInteractiveMode(_ mode: InteractiveMode, _ geo: Geometries? = nil) -> [IINAAnimation.Task] {
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
    animationPipeline.submitSudden({ [self] in
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

    // If these params are present and valid, then need to apply a crop
    if let cropController = cropSettingsView, let videoSizeRaw = newVidGeo?.videoSizeRaw, let cropRect = newVidGeo?.cropRect {

      log.verbose("Cropping video from videoSizeRaw: \(videoSizeRaw), videoSizeScaled: \(cropController.cropBoxView.videoRect), cropRect: \(cropRect)")

      /// Must update `windowedModeGeo` outside of animation task!
      // this works for full screen modes too
      let currentIMGeo = currentLayout.buildGeometry(windowFrame: windowedModeGeo.windowFrame, screenID: bestScreen.screenID, videoAspect: videoSizeRaw.mpvAspect)
      let newIMGeo = currentIMGeo.cropVideo(from: videoSizeRaw, to: cropRect)
      if currentLayout.mode == .windowedInteractive {
        windowedModeGeo = newIMGeo
      }

      // Crop animation:
      let cropAnimationDuration = immediately ? 0 : IINAAnimation.CropAnimationDuration * 0.005
      tasks.append(IINAAnimation.Task(duration: cropAnimationDuration, timing: .default) { [self] in
        videoView.apply(newIMGeo)
        player.window.setFrameImmediately(newIMGeo.windowFrame)

        // Add the crop filter now, if applying crop. The timing should mostly add up and look like it cut out a piece of the whole.
        // It's not perfect but better than before
        if let cropController = cropSettingsView {
          let newCropFilter = MPVFilter.crop(w: cropController.cropw, h: cropController.croph, x: cropController.cropx, y: cropController.cropy)
          /// Set the filter. This will result in `applyVidGeo` getting called, which will trigger an exit from interactive mode.
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
    let geo = self.geo(videoAspect: newVidGeo?.cropRect?.size.mpvAspect)
    let transition = buildLayoutTransition(named: "ExitInteractiveMode", from: currentLayout, to: newLayoutSpec,
                                           totalStartingDuration: startDuration, totalEndingDuration: endDuration, geo)
    tasks.append(contentsOf: transition.tasks)

    return tasks
  }

  // MARK: - UI: Thumbnail Preview

  /// Display time label & thumbnail when mouse over slider
  private func refreshSeekTimeAndThumbnail(from event: NSEvent) {
    thumbDisplayTicketCounter += 1
    let currentTicket = thumbDisplayTicketCounter

    DispatchQueue.main.async { [self] in
      guard currentTicket == thumbDisplayTicketCounter else { return }
      refreshSeekTimeAndThumbnailInternal(from: event)
    }
  }

  private func refreshSeekTimeAndThumbnailInternal(from event: NSEvent) {
    guard !currentLayout.isInteractiveMode else { return }
    let isCoveredByOSD = !osdVisualEffectView.isHidden && isMouseEvent(event, inAnyOf: [osdVisualEffectView])
    let isCoveredBySidebar = isMouseEvent(event, inAnyOf: [leadingSidebarView, trailingSidebarView])
    let isMouseInPlaySlider = isMouseEvent(event, inAnyOf: [playSlider])
    guard isMouseInPlaySlider, !isCoveredByOSD, !isCoveredBySidebar, !isAnimatingLayoutTransition, let duration = player.info.videoDuration else {
      hideSeekTimeAndThumbnail()
      return
    }

    // - 1. Time Hover Label

    let mousePosX = playSlider.convert(event.locationInWindow, from: nil).x
    let originalPosX = event.locationInWindow.x

    timePositionHoverLabelHorizontalCenterConstraint.constant = mousePosX

    let playbackPositionPercentage = max(0, Double((mousePosX - 3) / (playSlider.frame.width - 6)))
    let previewTime = duration * playbackPositionPercentage
    if timePositionHoverLabel.stringValue != previewTime.stringRepresentation {
      timePositionHoverLabel.stringValue = previewTime.stringRepresentation
    }
    timePositionHoverLabel.isHidden = false

    // - 2. Thumbnail Preview

    let videoGeo = player.info.videoGeo

    guard let thumbnails = player.info.currentMedia?.thumbnails,
          let ffThumbnail = thumbnails.getThumbnail(forSecond: previewTime.second),
          let videoAspectACR = videoGeo.videoAspectACR, let currentControlBar else {
      thumbnailPeekView.isHidden = true
      return
    }
    guard !currentLayout.isMusicMode || (Preference.bool(for: .enableThumbnailForMusicMode) && musicModeGeo.isVideoVisible) else {
      thumbnailPeekView.isHidden = true
      return
    }

    let rotatedImage = ffThumbnail.image
    var thumbWidth: Double = rotatedImage.size.width
    var thumbHeight: Double = rotatedImage.size.height

    guard thumbWidth > 0, thumbHeight > 0 else {
      log.error("Cannot display thumbnail: thumbnail width or height is not positive!")
      return
    }
    var thumbAspect = thumbWidth / thumbHeight

    // The aspect ratio of some videos is different at display time. May need to resize these videos
    // once the actual aspect ratio is known. (Should they be resized before being stored on disk? Doing so
    // would increase the file size without improving the quality, whereas resizing on the fly seems fast enough).
    if thumbAspect != videoAspectACR {
      thumbHeight = (thumbWidth / videoAspectACR).rounded()
      /// Recalculate this for later use (will use it and `thumbHeight`, and derive width)
      thumbAspect = thumbWidth / thumbHeight
    }

    /// Calculate `availableHeight` (viewport height, minus top & bottom bars)
    let availableHeight = viewportView.frame.height - currentLayout.insideTopBarHeight - currentLayout.insideBottomBarHeight - thumbnailExtraOffsetY - thumbnailExtraOffsetY

    let sizeOption: Preference.ThumbnailSizeOption = Preference.enum(for: .thumbnailSizeOption)
    switch sizeOption {
    case .fixedSize:
      // Stored thumb size should be correct (but may need to be scaled down)
      break
    case .scaleWithViewport:
      // Scale thumbnail as percentage of available height
      let percentage = min(1, max(0, Preference.double(for: .thumbnailDisplayedSizePercentage) / 100.0))
      thumbHeight = availableHeight * percentage
    }

    // Thumb too small?
    if thumbHeight < Constants.Distance.minThumbnailHeight {
      thumbHeight = Constants.Distance.minThumbnailHeight
    }

    // Thumb too tall?
    if thumbHeight > availableHeight {
      // Scale down thumbnail so it doesn't overlap top or bottom bars
      thumbHeight = availableHeight
    }
    thumbWidth = thumbHeight * thumbAspect

    // Also scale down thumbnail if it's wider than the viewport
    let availableWidth = viewportView.frame.width - thumbnailExtraOffsetX - thumbnailExtraOffsetX
    if thumbWidth > availableWidth {
      thumbWidth = availableWidth
      thumbHeight = thumbWidth / thumbAspect
    }

    let oscOriginInWindowY = currentControlBar.superview!.convert(currentControlBar.frame.origin, to: nil).y
    let oscHeight = currentControlBar.frame.size.height

    let showAbove: Bool
    if currentLayout.isMusicMode {
      showAbove = true  // always show above in music mode
    } else {
      switch currentLayout.oscPosition {
      case .top:
        showAbove = false
      case .bottom:
        showAbove = true
      case .floating:
        let totalMargin = thumbnailExtraOffsetY + thumbnailExtraOffsetY
        let availableHeightBelow = max(0, oscOriginInWindowY - currentLayout.insideBottomBarHeight - totalMargin)
        if availableHeightBelow > thumbHeight {
          // Show below by default, if there is space for the desired size
          showAbove = false
        } else {
          // If not enough space to show the full-size thumb below, then show above if it has more space
          let availableHeightAbove = max(0, viewportView.frame.height - (oscOriginInWindowY + oscHeight + totalMargin + currentLayout.insideTopBarHeight))
          showAbove = availableHeightAbove > availableHeightBelow
          if showAbove, thumbHeight > availableHeightAbove {
            // Scale down thumbnail so it doesn't get clipped by the side of the window
            thumbHeight = availableHeightAbove
            thumbWidth = thumbHeight * thumbAspect
          }
        }

        if !showAbove, thumbHeight > availableHeightBelow {
          thumbHeight = availableHeightBelow
          thumbWidth = thumbHeight * thumbAspect
        }
      }
    }

    // Need integers below.
    thumbWidth = round(thumbWidth)
    thumbHeight = round(thumbHeight)

    guard thumbWidth >= Constants.Distance.minThumbnailHeight,
          thumbHeight >= Constants.Distance.minThumbnailHeight else {
      log.verbose("Not enough space to display thumbnail")
      thumbnailPeekView.isHidden = true
      return
    }

    // Scaling is a potentially expensive operation, so reuse the last image if no change is needed
    if thumbnails.currentDisplayedThumbFFTimestamp != ffThumbnail.timestamp {
      thumbnails.currentDisplayedThumbFFTimestamp = ffThumbnail.timestamp

      let finalImage: NSImage
      // Apply crop first. Then aspect
      let croppedImage: NSImage
      if let normalizedCropRect = player.info.videoGeo.cropRectNormalized {
        croppedImage = rotatedImage.cropped(normalizedCropRect: normalizedCropRect)
      } else {
        croppedImage = rotatedImage
      }
      finalImage = croppedImage.resized(newWidth: Int(thumbWidth), newHeight: Int(thumbHeight))
      thumbnailPeekView.imageView.image = finalImage
      thumbnailPeekView.frame.size = finalImage.size
    }

    let thumbOriginY: CGFloat
    if showAbove {
      // Show thumbnail above seek time, which is above slider
      thumbOriginY = oscOriginInWindowY + oscHeight + thumbnailExtraOffsetY
    } else {
      // Show thumbnail below slider
      thumbOriginY = max(thumbnailExtraOffsetY, oscOriginInWindowY - thumbHeight - thumbnailExtraOffsetY)
    }
    // Constrain X origin so that it stays entirely inside the viewport (and not inside the outside sidebars)
    let minX = currentLayout.outsideLeadingBarWidth + thumbnailExtraOffsetX
    let maxX = minX + availableWidth
    let thumbOriginX = min(max(minX, round(originalPosX - thumbWidth / 2)), maxX - thumbWidth)
    thumbnailPeekView.frame.origin = NSPoint(x: thumbOriginX, y: thumbOriginY)

    thumbnailPeekView.refreshBorderStyle()

    if log.isTraceEnabled {
      log.trace("Displaying thumbnail \(showAbove ? "above" : "below") OSC, size \(thumbnailPeekView.frame.size)")
    }
    thumbnailPeekView.isHidden = false
  }

  // MARK: - UI: Other

  func hideSeekTimeAndThumbnail() {
    thumbnailPeekView.isHidden = true
    timePositionHoverLabel.isHidden = true
  }

  func refreshHidesOnDeactivateStatus() {
    guard let window else { return }
    window.hidesOnDeactivate = currentLayout.isWindowed && Preference.bool(for: .hideWindowsWhenInactive)
  }

  func abLoop() {
    dispatchPrecondition(condition: .onQueue(.main))

    player.mpv.queue.async { [self] in
      _abLoop()
    }
  }

  @discardableResult
  func _abLoop() -> Int32 {
    dispatchPrecondition(condition: .onQueue(player.mpv.queue))

    let returnValue = player.abLoop()
    if returnValue == 0 {
      syncPlaySliderABLoop()
    }
    return returnValue
  }

  func enterMusicMode() {
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
        let transition = buildTransitionToEnterMusicMode(from: oldLayout)
        animationPipeline.submit(transition.tasks)
      }
    })
  }

  private func buildTransitionToEnterMusicMode(from oldLayout: LayoutState, _ geo: Geometries? = nil) -> LayoutTransition {
    let miniPlayerLayout = oldLayout.spec.clone(mode: .musicMode)
    return buildLayoutTransition(named: "EnterMusicMode", from: oldLayout, to: miniPlayerLayout, geo)
  }

  func exitMusicMode() {
    animationPipeline.submitSudden { [self] in
      /// Start by hiding OSC and/or "outside" panels, which aren't needed and might mess up the layout.
      /// We can do this by creating a `LayoutSpec`, then using it to build a `LayoutTransition` and executing its animation.
      let oldLayout = currentLayout
      let windowedLayout = LayoutSpec.fromPreferences(andMode: .windowed, fillingInFrom: lastWindowedLayoutSpec)
      buildLayoutTransition(named: "ExitMusicMode", from: oldLayout, to: windowedLayout, thenRun: true)
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

  func updateUI() {
    dispatchPrecondition(condition: .onQueue(.main))
    player.updatePlaybackTimeInfo()

    // Run all tasks in the OSD queue until it is depleted
    osdQueueLock.withLock {
      while !osdQueue.isEmpty {
        osdQueue.removeFirst()?()
      }
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
    guard let duration = player.info.videoDuration, let pos = player.info.videoPosition else { return }

    // If the OSD is visible and is showing playback position, keep its displayed time up to date:
    if osdAnimationState == .shown, let osdLastDisplayedMsg {
      let message: OSDMessage?
      switch osdLastDisplayedMsg {
      case .pause:
        message = .pause(videoPosition: pos, videoDuration: duration)
      case .resume:
        message = .resume(videoPosition: pos, videoDuration: duration)
      case .seek(_, _):
        message = .seek(videoPosition: pos, videoDuration: duration)
      default:
        message = nil
      }

      if let message = message {
        setOSDViews(fromMessage: message)
      }
    }

    // Update playback position slider in OSC:
    let percentage = (pos.second / duration.second) * 100
    [leftLabel, rightLabel].forEach { $0.updateText(with: duration, given: pos) }
    playSlider.updateTo(percentage: percentage)

    // Touch bar
    if #available(macOS 10.12.2, *) {
      player.touchBarSupport.touchBarPlaySlider?.setDoubleValueSafely(percentage)
      player.touchBarSupport.touchBarPosLabels.forEach { $0.updateText(with: duration, given: pos) }
    }
  }

  func updateVolumeUI() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard loaded, !isClosing, !player.isShuttingDown else { return }
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

    if isInMiniPlayer {
      miniPlayer.loadIfNeeded()

      miniPlayer.volumeSlider.isEnabled = hasAudio
      miniPlayer.volumeSlider.doubleValue = volume
      miniPlayer.volumeLabel.intValue = Int32(volume)
      miniPlayer.volumeButton.image = volumeImage
      miniPlayer.muteButton.image = volumeImage
    }
  }

  func updatePlayButtonAndSpeedUI() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard loaded else { return }

    let isPaused = player.info.isPaused
    let state: NSControl.StateValue = isPaused ? .off : .on
    if isInMiniPlayer {
      player.windowController.miniPlayer.loadIfNeeded()
      player.windowController.miniPlayer.playButton.state = state
    }
    playButton.state = state

    let playSpeed = player.info.playSpeed
    let isNormalSpeed = playSpeed == 1
    speedLabel.isHidden = isPaused || isNormalSpeed

    if !isNormalSpeed {
      speedLabel.stringValue = "\(playSpeed.stringTrunc3f)x"
    }

    if #available(macOS 10.12.2, *) {
      player.touchBarSupport.updateTouchBarPlayBtn()
    }
  }

  func syncPlaySliderABLoop() {
    dispatchPrecondition(condition: .onQueue(player.mpv.queue))
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
    if let duration = player.info.videoDuration?.second {
      return duration == 0 ? 0 : seconds / duration * 100
    } else if let position = player.info.videoPosition?.second {
      return position == 0 ? 0 : seconds / position * 100
    } else {
      return 0
    }
  }

  func updateAdditionalInfo() {
    guard isFullScreen && displayTimeAndBatteryInFullScreen else {
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
      bufferSpin.startAnimation(nil)
      bufferProgressLabel.stringValue = NSLocalizedString("main.opening_stream", comment:"Opening stream…")
      bufferDetailLabel.stringValue = ""
    } else {
      bufferIndicatorView.isHidden = true
    }
  }

  func updateNetworkState() {
    let needShowIndicator = player.info.pausedForCache || player.info.isSeeking

    if needShowIndicator {
      let usedStr = FloatingPointByteCountFormatter.string(fromByteCount: player.info.cacheUsed, prefixedBy: .ki)
      let speedStr = FloatingPointByteCountFormatter.string(fromByteCount: player.info.cacheSpeed)
      let bufferingState = player.info.bufferingState
      bufferIndicatorView.isHidden = false
      bufferProgressLabel.stringValue = String(format: NSLocalizedString("main.buffering_indicator", comment:"Buffering... %d%%"), bufferingState)
      bufferDetailLabel.stringValue = "\(usedStr)B (\(speedStr)/s)"
    } else {
      bufferIndicatorView.isHidden = true
    }
  }

  func updateMusicModeButtonsVisibility() {
    // Show only in music mode when video is visible
    closeButtonBackgroundViewVE.isHidden = !miniPlayer.isVideoVisible

    // Show only in music mode when video is hidden
    closeButtonBackgroundViewBox.isHidden = miniPlayer.isVideoVisible

    guard isInMiniPlayer else { return }

    miniPlayer.loadIfNeeded()
    // Push the volume button to the right if the buttons on at the same vertical position
    miniPlayer.volumeButtonLeadingConstraint.animateToConstant(miniPlayer.isVideoVisible ? 12 : 24)
  }

  func forceDraw() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let currentVideoTrack = player.info.currentTrack(.video), currentVideoTrack.id != 0 else {
      log.verbose("Will not force video redraw: no video track selected")
      return
    }
    guard loaded, player.info.isPaused || currentVideoTrack.isAlbumart else { return }
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

  @IBAction func volumeSliderDidChange(_ sender: NSSlider) {
    let value = sender.doubleValue
    if Preference.double(for: .maxVolume) > 100, value > 100 && value < 101 {
      NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
    player.setVolume(value)
  }

  @IBAction func backBtnAction(_ sender: NSButton) {
    player.exitMusicMode()
  }

  @IBAction func playButtonAction(_ sender: NSButton) {
    let wasPaused = player.info.isPaused
    wasPaused ? player.resume() : player.pause()
    assert(player.info.isPaused == !wasPaused)
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

  /** When slider changes */
  @IBAction func playSliderDidChange(_ sender: NSSlider) {
    guard player.info.isFileLoaded else { return }

    let percentage = 100 * sender.doubleValue / sender.maxValue
    player.seek(percent: percentage, forceExact: !followGlobalSeekTypeWhenAdjustSlider)

    // update position of time label
    timePositionHoverLabelHorizontalCenterConstraint.constant = sender.knobPointPosition() - playSlider.frame.origin.x

    // update text of time label
    let seekTime = player.info.videoDuration! * percentage * 0.01
    if log.isTraceEnabled {
      log.trace("PlaySliderDidChange: setting slider position time label to \(seekTime.stringRepresentation.quoted)")
    }
    timePositionHoverLabel.stringValue = seekTime.stringRepresentation
  }

  @objc func toolBarButtonAction(_ sender: NSButton) {
    guard let buttonType = Preference.ToolBarButton(rawValue: sender.tag) else { return }
    switch buttonType {
    case .fullScreen:
      toggleWindowFullScreen()
    case .musicMode:
      player.enterMusicMode()
    case .pip:
      if #available(macOS 10.12, *) {
        if pipStatus == .inPIP {
          exitPIP()
        } else if pipStatus == .notInPIP {
          enterPIP()
        }
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

  func handleIINACommand(_ cmd: IINACommand) {
    switch cmd {
    case .openFile:
      AppDelegate.shared.showOpenFileWindow(isAlternativeAction: false)
    case .openURL:
      AppDelegate.shared.showOpenURLWindow(isAlternativeAction: false)
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
    case .toggleMusicMode:
      menuSwitchToMiniPlayer(.dummy)
    case .togglePIP:
      if #available(macOS 10.12, *) {
        menuTogglePIP(.dummy)
      }
    case .videoPanel:
      menuShowVideoQuickSettings(.dummy)
    case .audioPanel:
      menuShowAudioQuickSettings(.dummy)
    case .subPanel:
      menuShowSubQuickSettings(.dummy)
    case .playlistPanel:
      menuShowPlaylistPanel(.dummy)
    case .chapterPanel:
      menuShowChaptersPanel(.dummy)
    case .deleteCurrentFileHard:
      menuDeleteCurrentFileHard(.dummy)
    case .biggerWindow:
      let item = NSMenuItem()
      item.tag = 11
      menuChangeWindowSize(item)
    case .smallerWindow:
      let item = NSMenuItem()
      item.tag = 10
      menuChangeWindowSize(item)
    case .fitToScreen:
      let item = NSMenuItem()
      item.tag = 3
      menuChangeWindowSize(item)
    }
  }

  /// Do not call this in while in native full screen. It seems to cause FS to get stuck and unable to exit.
  /// Try not to call this while animating. It can cause the window to briefly disappear
  func resetCollectionBehavior() {
    guard !NSApp.presentationOptions.contains(.fullScreen) else {
      log.error("resetCollectionBehavior() should not have been called while in native FS - ignoring")
      return
    }
    /// Set option `.fullScreenDisallowsTiling` always.
    /// As of MacOS 14.2.1, tiling is at best glitchy and at worst results in an infinite loop
    // FIXME: support tiling for at least native full screen
    if Preference.bool(for: .useLegacyFullScreen) {
      window?.collectionBehavior = [.managed, .fullScreenDisallowsTiling, .fullScreenAuxiliary]
    } else {
      window?.collectionBehavior = [.managed, .fullScreenDisallowsTiling, .fullScreenPrimary]
    }
  }

}

// MARK: - Picture in Picture

@available(macOS 10.12, *)
extension PlayerWindowController: PIPViewControllerDelegate {

  func enterPIP(usePipBehavior: Preference.WindowBehaviorWhenPip? = nil) {
    dispatchPrecondition(condition: .onQueue(.main))

    // Must not try to enter PiP if already in PiP - will crash!
    guard pipStatus == .notInPIP else { return }
    pipStatus = .intermediate

    exitInteractiveMode(then: { [self] in
      log.verbose("About to enter PIP")
      doPIPEntry(usePipBehavior: usePipBehavior)
    })
  }

  private func doPIPEntry(usePipBehavior: Preference.WindowBehaviorWhenPip? = nil) {
    guard let window else { return }
    pipStatus = .inPIP
    showFadeableViews()

    videoView.$isUninited.withLock() { isUninited in
      pipVideo = NSViewController()
      // Remove these. They screw up PIP drag
      videoView.apply(nil)
      pipVideo.view = videoView
      videoView.videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
      pip.playing = player.info.isPlaying
      pip.title = window.title
      
      pip.presentAsPicture(inPicture: pipVideo)
      pipOverlayView.isHidden = false
    }

    if !window.styleMask.contains(.fullScreen) && !window.isMiniaturized {
      let pipBehavior = usePipBehavior ?? Preference.enum(for: .windowBehaviorWhenPip) as Preference.WindowBehaviorWhenPip
      log.verbose("Entering PIP with behavior: \(pipBehavior)")
      switch pipBehavior {
      case .doNothing:
        break
      case .hide:
        isWindowHidden = true
        window.orderOut(self)
        log.verbose("PIP entered; adding player to hidden windows list: \(window.savedStateName.quoted)")
        AppDelegate.windowsHidden.insert(window.savedStateName)
        break
      case .minimize:
        isWindowMiniaturizedDueToPip = true
        /// No need to add to `AppDelegate.windowsMinimized` - it will be handled by app-wide listener
        window.miniaturize(self)
        break
      }
      if Preference.bool(for: .pauseWhenPip) {
        player.pause()
      }
    }

    forceDraw()
    player.saveState()
    player.events.emit(.pipChanged, data: true)
  }

  func exitPIP() {
    guard pipStatus == .inPIP else { return }
    log.verbose("Exiting PIP")
    if pipShouldClose(pip) {
      // Prod Swift to pick the dismiss(_ viewController: NSViewController)
      // overload over dismiss(_ sender: Any?). A change in the way implicitly
      // unwrapped optionals are handled in Swift means that the wrong method
      // is chosen in this case. See https://bugs.swift.org/browse/SR-8956.
      pip.dismiss(pipVideo!)
    }
    player.events.emit(.pipChanged, data: false)
  }

  func prepareForPIPClosure(_ pip: PIPViewController) {
    guard pipStatus == .inPIP else { return }
    guard let window = window else { return }
    log.verbose("Preparing for PIP closure")
    // This is called right before we're about to close the PIP
    pipStatus = .intermediate

    // Hide the overlay view preemptively, to prevent any issues where it does
    // not hide in time and ends up covering the video view (which will be added
    // to the window under everything else, including the overlay).
    pipOverlayView.isHidden = true

    if AppDelegate.shared.isTerminating {
      // Don't bother restoring window state past this point
      return
    }

    // Set frame to animate back to
    let geo = currentLayout.mode == .musicMode ? musicModeGeo.toPWGeometry() : windowedModeGeo
    pip.replacementRect = geo.videoFrameInWindowCoords
    pip.replacementWindow = window

    // Bring the window to the front and deminiaturize it
    NSApp.activate(ignoringOtherApps: true)
    if isWindowMiniturized {
      window.deminiaturize(pip)
    }
  }

  func pipWillClose(_ pip: PIPViewController) {
    prepareForPIPClosure(pip)
  }

  func pipShouldClose(_ pip: PIPViewController) -> Bool {
    prepareForPIPClosure(pip)
    return true
  }

  func pipDidClose(_ pip: PIPViewController) {
    guard !AppDelegate.shared.isTerminating else { return }

    // seems to require separate animation blocks to work properly
    var tasks: [IINAAnimation.Task] = []

    if isWindowHidden {
      tasks.append(contentsOf: buildApplyWindowGeoTasks(windowedModeGeo)) // may have skipped updates while hidden
      tasks.append(IINAAnimation.Task({ [self] in
        showWindow(self)
        if let window {
          log.verbose("PIP did close; removing player from hidden windows list: \(window.savedStateName.quoted)")
          AppDelegate.windowsHidden.remove(window.savedStateName)
        }
      }))
    }

    tasks.append(IINAAnimation.suddenTask { [self] in
      /// Must set this before calling `addVideoViewToWindow()`
      pipStatus = .notInPIP

      let geo = currentLayout.mode == .musicMode ? musicModeGeo.toPWGeometry() : windowedModeGeo
      addVideoViewToWindow(geo)

      // If using legacy windowed mode, need to manually add title to Window menu & Dock
      updateTitle()
    })

    tasks.append(IINAAnimation.suddenTask { [self] in
      // Similarly, we need to run a redraw here as well. We check to make sure we
      // are paused, because this causes a janky animation in either case but as
      // it's not necessary while the video is playing and significantly more
      // noticeable, we only redraw if we are paused.
      forceDraw()

      resetFadeTimer()

      isWindowMiniaturizedDueToPip = false
      isWindowHidden = false
      player.saveState()
    })

    animationPipeline.submit(tasks)
  }

  func pipActionPlay(_ pip: PIPViewController) {
    player.resume()
  }

  func pipActionPause(_ pip: PIPViewController) {
    player.pause()
  }

  func pipActionStop(_ pip: PIPViewController) {
    // Stopping PIP pauses playback
    player.pause()
  }
}
