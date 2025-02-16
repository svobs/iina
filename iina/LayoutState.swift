//
//  LayoutState.swift
//  iina
//
//  Created by Matt Svoboda on 10/3/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// `LayoutSpec`: data structure containing a player window's layout configuration, and contains all the info needed to build a `LayoutState`.
/// (`LayoutSpec` is more compact & convenient for state storage, but `LayoutState` contains extra derived data which is more useful for
/// window operations).
/// The values for most fields in this struct can be derived from IINA's application settings, although some state like active sidebar tab
/// and window mode can vary for each player window.
/// See also: `LayoutState.buildFrom()`, which compiles a `LayoutSpec` into a `LayoutState`.
struct LayoutSpec {

  let leadingSidebar: Sidebar
  let trailingSidebar: Sidebar

  let mode: PlayerWindowMode
  let isLegacyStyle: Bool

  let topBarPlacement: Preference.PanelPlacement
  let bottomBarPlacement: Preference.PanelPlacement
  var leadingSidebarPlacement: Preference.PanelPlacement { return leadingSidebar.placement }
  var trailingSidebarPlacement: Preference.PanelPlacement { return trailingSidebar.placement }

  /// Can only be `true` for `windowedNormal` & `fullScreenNormal` modes!
  let enableOSC: Bool
  let oscPosition: Preference.OSCPosition
  let oscColorScheme: Preference.OSCColorScheme

  let controlBarGeo: ControlBarGeometry

  /// The mode of the interactive mode. ONLY used if `mode==.windowedInteractive || mode==.fullScreenInteractive`
  let interactiveMode: InteractiveMode?

  let moreSidebarState: Sidebar.SidebarMiscState

  init(leadingSidebar: Sidebar, trailingSidebar: Sidebar, mode: PlayerWindowMode, isLegacyStyle: Bool,
       topBarPlacement: Preference.PanelPlacement, bottomBarPlacement: Preference.PanelPlacement,
       enableOSC: Bool, oscPosition: Preference.OSCPosition,
       oscColorScheme: Preference.OSCColorScheme,
       controlBarGeo: ControlBarGeometry? = nil,
       interactiveMode: InteractiveMode?,
       moreSidebarState: Sidebar.SidebarMiscState) {

    var mode = mode
    if (mode == .windowedInteractive || mode == .fullScreenInteractive) && interactiveMode == nil {
      Logger.log("Cannot enter interactive mode (\(mode)) because its mode field is nil! Falling back to windowed mode")
      // Prevent invalid mode from crashing IINA. Just go to windowed instead
      mode = .windowedNormal
    }
    self.mode = mode
    self.oscColorScheme = oscColorScheme

    switch mode {
    case .windowedNormal, .fullScreenNormal:
      self.leadingSidebar = leadingSidebar
      self.trailingSidebar = trailingSidebar
      self.topBarPlacement = topBarPlacement
      self.bottomBarPlacement = bottomBarPlacement
      self.enableOSC = enableOSC
      self.interactiveMode = nil

    case .musicMode, .windowedInteractive, .fullScreenInteractive:
      // Override most properties for music mode & interactive mode
      self.leadingSidebar = leadingSidebar.clone(visibility: .hide)
      self.trailingSidebar = trailingSidebar.clone(visibility: .hide)
      self.topBarPlacement = mode == .windowedInteractive ? .outsideViewport : .insideViewport
      self.bottomBarPlacement = .outsideViewport
      self.enableOSC = false
      self.interactiveMode = interactiveMode
    }

    self.isLegacyStyle = isLegacyStyle
    self.oscPosition = oscPosition
    self.moreSidebarState = moreSidebarState
    // Should be ok to fill in most of ControlBarGeometry from prefs if not given
    self.controlBarGeo = controlBarGeo ?? ControlBarGeometry(mode: mode, oscPosition: oscPosition)
  }

  /// Factory method. Fills in most from app singleton preferences, and the rest from default values.
  static func fromPrefsAndDefaults() -> LayoutSpec {
    return fromPreferences()
  }

  /// Factory method. Init from preferences, except for `mode` and tab params
  static func fromPreferences(andMode newMode: PlayerWindowMode? = nil,
                              isLegacyStyle: Bool? = nil,
                              fillingInFrom oldSpec: LayoutSpec? = nil) -> LayoutSpec {

    let oldLeadingSidebar = oldSpec?.leadingSidebar
    let oldTrailingSidebar = oldSpec?.trailingSidebar

    let leadingSidebar =  Sidebar(.leadingSidebar,
                                  tabGroups: Sidebar.TabGroup.fromPrefs(for: .leadingSidebar),
                                  placement: Preference.enum(for: .leadingSidebarPlacement),
                                  visibility: oldLeadingSidebar?.visibility ?? .hide,
                                  lastVisibleTab: oldLeadingSidebar?.lastVisibleTab)
    let trailingSidebar = Sidebar(.trailingSidebar,
                                  tabGroups: Sidebar.TabGroup.fromPrefs(for: .trailingSidebar),
                                  placement: Preference.enum(for: .trailingSidebarPlacement),
                                  visibility: oldTrailingSidebar?.visibility ?? .hide,
                                  lastVisibleTab: oldTrailingSidebar?.lastVisibleTab)
    let mode = newMode ?? oldSpec?.mode ?? .windowedNormal
    let isLegacyStyle = isLegacyStyle ?? mode.isFullScreen ? Preference.bool(for: .useLegacyFullScreen) : Preference.bool(for: .useLegacyWindowedMode)
    let interactiveMode = mode.isInteractiveMode ? oldSpec?.interactiveMode ?? InteractiveMode.crop : nil

    return LayoutSpec(leadingSidebar: leadingSidebar, trailingSidebar: trailingSidebar,
                      mode: mode,
                      isLegacyStyle: isLegacyStyle,
                      topBarPlacement: Preference.enum(for: .topBarPlacement),
                      bottomBarPlacement: Preference.enum(for: .bottomBarPlacement),
                      enableOSC: Preference.bool(for: .enableOSC),
                      oscPosition: Preference.enum(for: .oscPosition),
                      oscColorScheme: effectiveOSCColorSchemeFromPrefs,
                      interactiveMode: interactiveMode,
                      moreSidebarState: oldSpec?.moreSidebarState ?? Sidebar.SidebarMiscState.fromDefaultPrefs())
  }

  static var effectiveOSCColorSchemeFromPrefs: Preference.OSCColorScheme {
    if Preference.bool(for: .enableOSC), Preference.enum(for: .oscPosition) == Preference.OSCPosition.bottom,
        Preference.enum(for: .bottomBarPlacement) == Preference.PanelPlacement.insideViewport {
      return Preference.enum(for: .oscColorScheme)
    }
    return .visualEffectView
  }

  /// Specify any properties to override; if nil, will use self's property values -
  /// EXCEPT for `oscColorScheme`, which is computed.
  func clone(leadingSidebar: Sidebar? = nil,
             trailingSidebar: Sidebar? = nil,
             mode: PlayerWindowMode? = nil,
             isLegacyStyle: Bool? = nil,
             topBarPlacement: Preference.PanelPlacement? = nil,
             bottomBarPlacement: Preference.PanelPlacement? = nil,
             enableOSC: Bool? = nil,
             oscPosition: Preference.OSCPosition? = nil,
             controlBarGeo: ControlBarGeometry? = nil,
             interactiveMode: InteractiveMode? = nil,
             moreSidebarState: Sidebar.SidebarMiscState? = nil) -> LayoutSpec {

    // make sure mode is consistent for self & controlBarGeo
    let controlBarGeo = controlBarGeo ?? (mode == nil ? self.controlBarGeo : self.controlBarGeo.clone(mode: mode!))

    return LayoutSpec(leadingSidebar: leadingSidebar ?? self.leadingSidebar,
                      trailingSidebar: trailingSidebar ?? self.trailingSidebar,
                      mode: mode ?? self.mode,
                      isLegacyStyle: isLegacyStyle ?? self.isLegacyStyle,
                      topBarPlacement: topBarPlacement ?? self.topBarPlacement,
                      bottomBarPlacement: bottomBarPlacement ?? self.bottomBarPlacement,
                      enableOSC: enableOSC ?? self.enableOSC,
                      oscPosition: self.oscPosition,
                      oscColorScheme: self.oscColorScheme,
                      controlBarGeo: controlBarGeo,
                      interactiveMode: interactiveMode ?? self.interactiveMode,
                      moreSidebarState: moreSidebarState ?? self.moreSidebarState)
  }

  func withSidebarsHidden() -> LayoutSpec {
    return clone(leadingSidebar: leadingSidebar.clone(visibility: .hide),
                 trailingSidebar: trailingSidebar.clone(visibility: .hide))
  }

  var insideLeadingBarWidth: CGFloat {
    if leadingSidebar.placement == .outsideViewport {
      return 0
    }
    return leadingSidebar.visibleTabGroup?.width(using: moreSidebarState) ?? 0
  }

  /// NOTE: Is mutable!
  var insideTrailingBarWidth: CGFloat {
    if trailingSidebar.placement == .outsideViewport {
      return 0
    }
    return trailingSidebar.visibleTabGroup?.width(using: moreSidebarState) ?? 0
  }

  /// NOTE: Is mutable!
  var outsideTrailingBarWidth: CGFloat {
    if trailingSidebar.placement == .insideViewport {
      return 0
    }
    return trailingSidebar.visibleTabGroup?.width(using: moreSidebarState) ?? 0
  }

  /// NOTE: Is mutable!
  var outsideLeadingBarWidth: CGFloat {
    if leadingSidebar.placement == .insideViewport {
      return 0
    }
    return leadingSidebar.visibleTabGroup?.width(using: moreSidebarState) ?? 0
  }

  var isInteractiveMode: Bool {
    return mode.isInteractiveMode
  }

  var isFullScreen: Bool {
    return mode.isFullScreen
  }

  var isWindowed: Bool {
    return mode.isWindowed
  }

  var isNativeFullScreen: Bool {
    return isFullScreen && !isLegacyStyle
  }

  var isLegacyFullScreen: Bool {
    return isFullScreen && isLegacyStyle
  }

  /// Returns `true` if `otherSpec` has the same values which are configured from IINA app-wide prefs
  func hasSamePrefsValues(as otherSpec: LayoutSpec) -> Bool {
    return otherSpec.enableOSC == enableOSC
    && otherSpec.oscPosition == oscPosition
    && otherSpec.isLegacyStyle == isLegacyStyle
    && otherSpec.topBarPlacement == topBarPlacement
    && otherSpec.bottomBarPlacement == bottomBarPlacement
    && otherSpec.leadingSidebarPlacement == leadingSidebarPlacement
    && otherSpec.trailingSidebarPlacement == trailingSidebarPlacement
    && otherSpec.leadingSidebar.tabGroups == leadingSidebar.tabGroups
    && otherSpec.trailingSidebar.tabGroups == trailingSidebar.tabGroups
    && otherSpec.moreSidebarState.playlistSidebarWidth == moreSidebarState.playlistSidebarWidth
  }

  func getWidthBetweenInsideSidebars(leadingSidebarWidth: CGFloat? = nil, trailingSidebarWidth: CGFloat? = nil,
                                     in viewportWidth: CGFloat) -> CGFloat {
    let lead = leadingSidebarWidth ?? insideLeadingBarWidth
    let trail = trailingSidebarWidth ?? insideTrailingBarWidth
    return viewportWidth - lead - trail
  }

  func getExcessSpaceBetweenInsideSidebars(leadingSidebarWidth: CGFloat? = nil, trailingSidebarWidth: CGFloat? = nil,
                                           in viewportWidth: CGFloat) -> CGFloat {
    return getWidthBetweenInsideSidebars(leadingSidebarWidth: leadingSidebarWidth, trailingSidebarWidth: trailingSidebarWidth, in: viewportWidth) - Constants.Sidebar.minWidthBetweenInsideSidebars
  }

  /// Returns `(shouldCloseLeadingSidebar, shouldCloseTrailingSidebar)`, indicating which sidebars should be hidden
  /// due to lack of space in the viewport.
  func isHideSidebarNeeded(in viewportWidth: CGFloat) -> (Bool, Bool) {
    var leadingSidebarSpace = insideLeadingBarWidth
    var trailingSidebarSpace = insideTrailingBarWidth
    var vidConSpace = viewportWidth

    var shouldCloseLeadingSidebar = false
    var shouldCloseTrailingSidebar = false
    if leadingSidebarSpace + trailingSidebarSpace > 0 {
      while getExcessSpaceBetweenInsideSidebars(leadingSidebarWidth: leadingSidebarSpace, trailingSidebarWidth: trailingSidebarSpace,
                                                in: vidConSpace) < 0 {
        if leadingSidebarSpace > 0 && leadingSidebarSpace >= trailingSidebarSpace {
          shouldCloseLeadingSidebar = true
          leadingSidebarSpace = 0
          vidConSpace -= leadingSidebarSpace
        } else if trailingSidebarSpace > 0 && trailingSidebarSpace >= leadingSidebarSpace {
          shouldCloseTrailingSidebar = true
          trailingSidebarSpace = 0
          vidConSpace -= trailingSidebarSpace
        } else {
          break
        }
      }
    }
    return (shouldCloseLeadingSidebar, shouldCloseTrailingSidebar)
  }

  var hasPermanentControlBar: Bool {
    if mode == .musicMode {
      return true
    }
    return enableOSC && ((oscPosition == .top && topBarPlacement == .outsideViewport) ||
                         (oscPosition == .bottom && bottomBarPlacement == .outsideViewport))
  }

  var hasBottomOSC: Bool {
    return enableOSC && oscPosition == .bottom
  }

  var hasTopOrBottomOSC: Bool {
    return enableOSC && (oscPosition == .top || oscPosition == .bottom)
  }

  var effectiveOSCColorScheme: Preference.OSCColorScheme {
    if hasBottomOSC && bottomBarPlacement == .insideViewport {
      return oscColorScheme
    }
    return .visualEffectView
  }

  var oscBackgroundIsClear: Bool {
    return effectiveOSCColorScheme == .clearGradient
  }
}

/// `LayoutState`: data structure which contains all the variables which describe a single layout configuration of the `PlayerWindow`.
/// ("Layout" might have been a better name for this class, but it's already used by AppKit). Notes:
/// • With all the different window layout configurations which are now possible, it's crucial to use this class in order for animations
///   to work reliably.
/// • It should be treated like a read-only object after it's built. Its member variables are only mutable to make it easier to build.
/// • When any member variable inside it needs to be changed, a new `LayoutState` object should be constructed to describe the new state,
///   and a `LayoutTransition` should be built to describe the animations needs to go from old to new.
/// • The new `LayoutState`, once active, should be stored in the `currentLayout` of `PlayerWindowController` for future reference.
struct LayoutState {
  // MARK: Stored properties

  // All other variables in this class are derived from this spec, or from stored prefs:
  let spec: LayoutSpec

  // - Visibility of views/categories

  let titleBar: VisibilityMode
  let titleIconAndText: VisibilityMode
  let trafficLightButtons: VisibilityMode
  let titlebarAccessoryViewControllers: VisibilityMode
  let leadingSidebarToggleButton: VisibilityMode
  let trailingSidebarToggleButton: VisibilityMode

  let controlBarFloating: VisibilityMode

  let bottomBarView: VisibilityMode
  let topBarView: VisibilityMode

  /// Only applies for legacy full screen
  let hasTopPaddingForCameraHousing: Bool

  // - Sizes / offsets

  let sidebarDownshift: CGFloat
  let sidebarTabHeight: CGFloat

  let titleBarHeight: CGFloat
  let topOSCHeight: CGFloat

  // - Colors / styles

  /// Has OSC with clear background.
  ///
  /// Equivalent to `effectiveOSCColorScheme == .clearGradient`
  let oscHasClearBG: Bool

  // MARK: Derived / computed properties

  var topBarHeight: CGFloat {
    self.titleBarHeight + self.topOSCHeight
  }

  let bottomBarHeight: CGFloat

  /// - Bar widths/heights IF `.outsideViewport`

  var outsideTopBarHeight: CGFloat {
    return topBarPlacement == .outsideViewport ? topBarHeight : 0
  }

  /// NOTE: Is mutable!
  var outsideTrailingBarWidth: CGFloat {
    return spec.outsideTrailingBarWidth
  }

  var outsideBottomBarHeight: CGFloat {
    return bottomBarPlacement == .outsideViewport ? bottomBarHeight : 0
  }

  /// NOTE: Is mutable!
  var outsideLeadingBarWidth: CGFloat {
    return spec.outsideLeadingBarWidth
  }

  var outsideBars: MarginQuad {
    return MarginQuad(top: outsideTopBarHeight, trailing: outsideTrailingBarWidth,
                      bottom: outsideBottomBarHeight, leading: outsideLeadingBarWidth)
  }

  /// - Bar widths/heights IF `.insideViewport`

  /// NOTE: Is mutable!
  var insideLeadingBarWidth: CGFloat {
    return spec.insideLeadingBarWidth
  }

  /// NOTE: Is mutable!
  var insideTrailingBarWidth: CGFloat {
    return spec.insideTrailingBarWidth
  }

  var insideTopBarHeight: CGFloat {
    return topBarPlacement == .insideViewport ? topBarHeight : 0
  }

  var insideBottomBarHeight: CGFloat {
    return bottomBarPlacement == .insideViewport ? bottomBarHeight : 0
  }

  var insideBars: MarginQuad {
    return MarginQuad(top: insideTopBarHeight, trailing: insideTrailingBarWidth,
                      bottom: insideBottomBarHeight, leading: insideLeadingBarWidth)
  }

  // - Other derived properties

  var isInteractiveMode: Bool {
    return spec.isInteractiveMode
  }

  var canEnterInteractiveMode: Bool {
    return spec.mode == .windowedNormal || spec.mode == .fullScreenNormal
  }

  var isFullScreen: Bool {
    return spec.isFullScreen
  }

  var isWindowed: Bool {
    return spec.isWindowed
  }

  var isNativeFullScreen: Bool {
    return isFullScreen && !spec.isLegacyStyle
  }

  var isLegacyFullScreen: Bool {
    return isFullScreen && spec.isLegacyStyle
  }

  var isMusicMode: Bool {
    return spec.mode == .musicMode
  }

  /// Note: this is always `false` for music mode and interactive modes.
  ///
  /// To include possibility of music mode, see `hasControlBar()`.
  var enableOSC: Bool {
    return spec.enableOSC
  }

  var oscPosition: Preference.OSCPosition {
    return spec.oscPosition
  }

  var topBarPlacement: Preference.PanelPlacement {
    return spec.topBarPlacement
  }

  var bottomBarPlacement: Preference.PanelPlacement {
    return spec.bottomBarPlacement
  }

  var leadingSidebarPlacement: Preference.PanelPlacement {
    return spec.leadingSidebarPlacement
  }

  var trailingSidebarPlacement: Preference.PanelPlacement {
    return spec.trailingSidebarPlacement
  }

  var leadingSidebar: Sidebar {
    return spec.leadingSidebar
  }

  var trailingSidebar: Sidebar {
    return spec.trailingSidebar
  }

  var canShowSidebars: Bool {
    return spec.mode.canShowSidebars
  }

  /// Only windowed & full screen modes can have floating OSC, and OSC must be enabled
  var hasFloatingOSC: Bool {
    return enableOSC && oscPosition == .floating
  }

  var hasTopOSC: Bool {
    return enableOSC && oscPosition == .top
  }

  var hasBottomOSC: Bool {
    return spec.hasBottomOSC
  }

  var hasControlBar: Bool {
    return isMusicMode || enableOSC
  }

  var hasFadeableOSC: Bool {
    return enableOSC && (oscPosition == .floating ||
                         (oscPosition == .top && topBarView.isFadeable) ||
                         (oscPosition == .bottom && bottomBarView.isFadeable))
  }

  /// Whether PlaySlider & VolumeSlider should change height when in focus (on mouse hover or during scroll)
  var useSliderFocusEffect: Bool {
    return mode == .musicMode || (enableOSC && (oscPosition == .top || oscPosition == .bottom))
  }

  var hasPermanentControlBar: Bool {
    return spec.hasPermanentControlBar
  }

  var mode: PlayerWindowMode {
    return spec.mode
  }

  var controlBarGeo: ControlBarGeometry {
    return spec.controlBarGeo
  }

  var hasTopOrBottomOSC: Bool {
    return spec.hasTopOrBottomOSC
  }

  var effectiveOSCColorScheme: Preference.OSCColorScheme {
    return spec.effectiveOSCColorScheme
  }

  func sidebar(withID id: Preference.SidebarLocation) -> Sidebar {
    switch id {
    case .leadingSidebar:
      return leadingSidebar
    case .trailingSidebar:
      return trailingSidebar
    }
  }

  func computeOnTopButtonVisibility(isOnTop: Bool) -> VisibilityMode {
    let showOnTopStatus = Preference.bool(for: .alwaysShowOnTopIcon) || isOnTop
    if isFullScreen || isMusicMode || !showOnTopStatus {
      return .hidden
    }

    if topBarPlacement == .insideViewport {
      return .showFadeableNonTopBar
    }

    return .showAlways
  }

  // MARK: - Build LayoutState from LayoutSpec

  /// Compiles the given `LayoutSpec` into a `LayoutState`. This is an idempotent operation.
  static func buildFrom(_ layoutSpec: LayoutSpec) -> LayoutState {
    let outputLayout = LayoutState(spec: layoutSpec)
    return outputLayout
  }

  init(spec: LayoutSpec) {
    self.spec = spec

    // Title bar & title bar accessories:

    self.hasTopPaddingForCameraHousing = spec.isLegacyFullScreen && Preference.bool(for: .allowVideoToOverlapCameraHousing)

    // Title bar views
    var titleBarHeight: CGFloat = 0
    let titleBarVisibleState: VisibilityMode
    if spec.isNativeFullScreen {
      titleBarVisibleState = .hidden
      self.trafficLightButtons = .showAlways
      self.titleIconAndText = .showAlways
    } else {
      if spec.isLegacyFullScreen {
        titleBarVisibleState = .hidden
      } else if spec.isWindowed {
        titleBarVisibleState = spec.topBarPlacement == .insideViewport ? .showFadeableTopBar : .showAlways
      } else {
        titleBarVisibleState = .hidden
      }
      self.trafficLightButtons = titleBarVisibleState
      self.titleIconAndText = titleBarVisibleState
    }
    self.titleBar = titleBarVisibleState
    self.titlebarAccessoryViewControllers = titleBarVisibleState
    if titleBarVisibleState.isShowable {
      // May be overridden depending on OSC layout anyway
      titleBarHeight = Constants.Distance.standardTitleBarHeight
    }
    // LeadingSidebar toggle button
    let hasLeadingSidebar = spec.mode.canShowSidebars && !spec.leadingSidebar.tabGroups.isEmpty
    self.leadingSidebarToggleButton = hasLeadingSidebar && Preference.bool(for: .showLeadingSidebarToggleButton) ? titleBarVisibleState : .hidden
    // TrailingSidebar toggle button
    let hasTrailingSidebar = spec.mode.canShowSidebars && !spec.trailingSidebar.tabGroups.isEmpty
    self.trailingSidebarToggleButton = hasTrailingSidebar && Preference.bool(for: .showTrailingSidebarToggleButton) ? titleBarVisibleState : .hidden

    // May be overridden below
    var topBarView: VisibilityMode = titleBarVisibleState
    var bottomBarView: VisibilityMode = .hidden
    var topOSCHeight: CGFloat = 0
    var controlBarFloating: VisibilityMode = .hidden
    var bottomBarHeight: CGFloat = 0
    var sidebarTabHeight: CGFloat = Constants.Sidebar.defaultTabHeight

    // OSC:

    if spec.enableOSC {
      // add fragment views
      switch spec.oscPosition {
      case .floating:
        controlBarFloating = .showFadeableNonTopBar  // floating is always fadeable
      case .top:
        if titleBarVisibleState.isShowable {
          // Reduce title height a bit because it will share space with OSC
          titleBarHeight = Constants.Distance.reducedTitleBarHeight
        }

        let topBarVisibility: VisibilityMode
        if spec.topBarPlacement == .outsideViewport {
          topBarVisibility = .showAlways
        } else if titleBarVisibleState.isShowable {
          // Match value from above
          topBarVisibility = titleBarVisibleState
        } else {
          topBarVisibility = .showFadeableTopBar
        }
        topBarView = topBarVisibility
        topOSCHeight = spec.controlBarGeo.barHeight
      case .bottom:
        bottomBarView = (spec.bottomBarPlacement == .insideViewport) ? .showFadeableNonTopBar : .showAlways
        bottomBarHeight = spec.controlBarGeo.barHeight
      }
    } else if spec.mode == .musicMode {
      assert(spec.bottomBarPlacement == .outsideViewport)
      bottomBarView = .showAlways
    } else if spec.isInteractiveMode {
      assert(spec.bottomBarPlacement == .outsideViewport)
      bottomBarView = .showAlways

      bottomBarHeight = Constants.InteractiveMode.outsideBottomBarHeight
    }
    self.topBarView = topBarView
    self.topOSCHeight = topOSCHeight
    self.controlBarFloating = controlBarFloating
    self.bottomBarView = bottomBarView
    self.bottomBarHeight = bottomBarHeight

    /// Sidebar tabHeight and downshift.
    /// Downshift: try to match height of title bar
    /// Tab height: if top OSC is `insideViewport`, try to match its height
    if spec.mode == .musicMode {
      /// Special case for music mode. Only really applies to `playlistView`,
      /// because `quickSettingView` is never shown in this mode.
      sidebarTabHeight = Constants.Sidebar.musicModeTabHeight
      self.sidebarDownshift = Constants.Sidebar.defaultDownshift
    } else if topBarView.isShowable {
      // Top bar always spans the whole width of the window (unlike the bottom bar)
      // FIXME: someday, refactor title bar & top OSC outside of top bar & make iinto 2 independent bars.
      // (so that top OSC will not overlap outside sidebars)
      if spec.topBarPlacement == .outsideViewport {
        self.sidebarDownshift = Constants.Sidebar.defaultDownshift
      } else {
        self.sidebarDownshift = titleBarHeight + topOSCHeight
      }

      let tabHeight = topOSCHeight
      // Put some safeguards in place. Don't want to waste space or be too tiny to read.
      // Leave default height if not in reasonable range.
      if tabHeight >= Constants.Sidebar.minTabHeight && tabHeight <= Constants.Sidebar.maxTabHeight {
        sidebarTabHeight = tabHeight
      }
    } else {
      self.sidebarDownshift = Constants.Sidebar.defaultDownshift
    }
    self.titleBarHeight = titleBarHeight
    self.sidebarTabHeight = sidebarTabHeight
    self.oscHasClearBG = spec.oscBackgroundIsClear
  }

  // Converts & updates existing geometry to this layout
  func convertWindowedModeGeometry(from existingGeometry: PWinGeometry, video: VideoGeometry? = nil,
                                   keepFullScreenDimensions: Bool,
                                   applyOffsetIndex offsetIndex: Int = 0, _ log: Logger.Subsystem) -> PWinGeometry {
    assert(existingGeometry.mode.isWindowed, "Expected existingGeometry to be windowed: \(existingGeometry)")
    let resizedBarsGeo = existingGeometry.withResizedBars(outsideTop: outsideTopBarHeight,
                                                          outsideTrailing: outsideTrailingBarWidth,
                                                          outsideBottom: outsideBottomBarHeight,
                                                          outsideLeading: outsideLeadingBarWidth,
                                                          insideTop: insideTopBarHeight,
                                                          insideTrailing: insideTrailingBarWidth,
                                                          insideBottom: insideBottomBarHeight,
                                                          insideLeading: insideLeadingBarWidth,
                                                          video: video,
                                                          keepFullScreenDimensions: keepFullScreenDimensions).refitted()

    var geo = resizedBarsGeo
    if offsetIndex > 0 {
      let screenVisibleFrame: NSRect = PWinGeometry.getContainerFrame(forScreenID: geo.screenID, screenFit: .stayInside)!
      let offsetIncrement = Constants.Distance.multiWindowOpenOffsetIncrement
      for _ in 1...offsetIndex {
        var newWindowFrame = NSRect(origin: NSPoint(x: geo.windowFrame.origin.x + offsetIncrement,
                                                    y: geo.windowFrame.origin.y - offsetIncrement),
                                    size: geo.windowFrame.size)
        let x = newWindowFrame.maxX > screenVisibleFrame.maxX ? 0 : newWindowFrame.minX
        let y = newWindowFrame.minY < screenVisibleFrame.minY ? screenVisibleFrame.maxY - newWindowFrame.height : newWindowFrame.minY
        newWindowFrame = NSRect(origin: NSPoint(x: x, y: y), size: geo.windowFrame.size)
        // TODO: be more sophisticated
        geo = geo.clone(windowFrame: newWindowFrame).refitted(using: .stayInside)
      }
      log.verbose{"Applied windowedGeo offsetIndex=\(offsetIndex) for multi-window open: \(resizedBarsGeo.windowFrame) → \(geo.windowFrame)"}
    }
    return geo
  }

  func buildFullScreenGeometry(inScreenID screenID: String, video: VideoGeometry) -> PWinGeometry {
    let screen = NSScreen.getScreenOrDefault(screenID: screenID)
    return buildFullScreenGeometry(in: screen, video: video)
  }

  func buildFullScreenGeometry(in screen: NSScreen, video: VideoGeometry) -> PWinGeometry {
    return PWinGeometry.forFullScreen(in: screen, legacy: spec.isLegacyStyle, mode: mode,
                                      outsideBars: outsideBars,
                                      insideBars: insideBars,
                                      video: video,
                                      allowVideoToOverlapCameraHousing: hasTopPaddingForCameraHousing)
  }

  func buildGeometry(usingMode modeOverride: PlayerWindowMode? = nil,
                     windowFrame: NSRect, screenID: String, video: VideoGeometry) -> PWinGeometry {
    let mode = modeOverride ?? mode
    switch mode {
    case .fullScreenNormal, .fullScreenInteractive:
      return buildFullScreenGeometry(inScreenID: screenID, video: video)
    case .windowedInteractive:
      return PWinGeometry.buildInteractiveModeWindow(windowFrame: windowFrame, screenID: screenID, video: video)
    case .windowedNormal:
      let geo = PWinGeometry(windowFrame: windowFrame, screenID: screenID, screenFit: .stayInside,
                             mode: mode,
                             topMarginHeight: 0,  // is only nonzero when in legacy FS
                             outsideBars: outsideBars,
                             insideBars: insideBars,
                             video: video)
      return geo.scalingViewport()
    case .musicMode:
      let musicModeGeo = MusicModeGeometry(windowFrame: windowFrame, screenID: screenID, video: video,
                                           isVideoVisible: Preference.bool(for: .musicModeShowAlbumArt),
                                           isPlaylistVisible: Preference.bool(for: .musicModeShowPlaylist))
      return musicModeGeo.toPWinGeometry()
    }

  }

  /// Only for windowed modes!
  func buildDefaultInitialGeometry(screen: NSScreen, video: VideoGeometry? = nil) -> PWinGeometry {
    let videoGeo = video ?? VideoGeometry.defaultGeometry()
    let videoSize = videoGeo.videoSizeRaw
    let windowFrame = NSRect(origin: CGPoint.zero, size: videoSize)
    let geo = buildGeometry(windowFrame: windowFrame, screenID: screen.screenID, video: videoGeo)
    return geo.refitted(using: .centerInside)
  }


}  // end class LayoutState
