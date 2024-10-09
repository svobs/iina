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

  /// WIP. Set this to `true` to continue working on recreating title bar in legacy windowed mode.
  /// See `fakeLeadingTitleBarView`.
  static let enableTitleBarForLegacyWindow = true

  let leadingSidebar: Sidebar
  let trailingSidebar: Sidebar

  let mode: PlayerWindowMode
  let isLegacyStyle: Bool

  let topBarPlacement: Preference.PanelPlacement
  let bottomBarPlacement: Preference.PanelPlacement
  var leadingSidebarPlacement: Preference.PanelPlacement { return leadingSidebar.placement }
  var trailingSidebarPlacement: Preference.PanelPlacement { return trailingSidebar.placement }

  let enableOSC: Bool
  let oscPosition: Preference.OSCPosition

  /// The mode of the interactive mode. ONLY used if `mode==.windowedInteractive || mode==.fullScreenInteractive`
  let interactiveMode: InteractiveMode?

  let moreSidebarState: Sidebar.SidebarMiscState

  init(leadingSidebar: Sidebar, trailingSidebar: Sidebar, mode: PlayerWindowMode, isLegacyStyle: Bool,
       topBarPlacement: Preference.PanelPlacement, bottomBarPlacement: Preference.PanelPlacement,
       enableOSC: Bool, oscPosition: Preference.OSCPosition, interactiveMode: InteractiveMode?,
       moreSidebarState: Sidebar.SidebarMiscState) {

    var mode = mode
    if (mode == .windowedInteractive || mode == .fullScreenInteractive) && interactiveMode == nil {
      Logger.log("Cannot enter interactive mode (\(mode)) because its mode field is nil! Falling back to windowed mode")
      // Prevent invalid mode from crashing IINA. Just go to windowed instead
      mode = .windowed
    }
    self.mode = mode

    switch mode {
    case .windowed, .fullScreen:
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
  }

  /// Factory method. Matches what is shown in the XIB
  static func defaultLayout() -> LayoutSpec {
    let leadingSidebar = Sidebar(.leadingSidebar, tabGroups: Sidebar.TabGroup.fromPrefs(for: .leadingSidebar),
                                 placement: Preference.enum(for: .leadingSidebarPlacement),
                                 visibility: .hide)
    let trailingSidebar = Sidebar(.trailingSidebar, tabGroups: Sidebar.TabGroup.fromPrefs(for: .trailingSidebar),
                                  placement: Preference.enum(for: .trailingSidebarPlacement),
                                  visibility: .hide)
    let moreSidebarState = Sidebar.SidebarMiscState.fromDefaultPrefs()
    return LayoutSpec(leadingSidebar: leadingSidebar,
                      trailingSidebar: trailingSidebar,
                      mode: .windowed,
                      isLegacyStyle: false,
                      topBarPlacement:.insideViewport,
                      bottomBarPlacement: .insideViewport,
                      enableOSC: false,
                      oscPosition: .floating,
                      interactiveMode: nil,
                      moreSidebarState: moreSidebarState)
  }

  /// Factory method. Init from preferences, except for `mode` and tab params
  static func fromPreferences(andMode newMode: PlayerWindowMode? = nil,
                              interactiveMode: InteractiveMode? = nil,
                              isLegacyStyle: Bool? = nil,
                              fillingInFrom oldSpec: LayoutSpec) -> LayoutSpec {

    let leadingSidebarVisibility = oldSpec.leadingSidebar.visibility
    let leadingSidebarLastVisibleTab = oldSpec.leadingSidebar.lastVisibleTab
    let trailingSidebarVisibility = oldSpec.trailingSidebar.visibility
    let trailingSidebarLastVisibleTab = oldSpec.trailingSidebar.lastVisibleTab

    let leadingSidebar =  Sidebar(.leadingSidebar,
                                  tabGroups: Sidebar.TabGroup.fromPrefs(for: .leadingSidebar),
                                  placement: Preference.enum(for: .leadingSidebarPlacement),
                                  visibility: leadingSidebarVisibility,
                                  lastVisibleTab: leadingSidebarLastVisibleTab)
    let trailingSidebar = Sidebar(.trailingSidebar,
                                  tabGroups: Sidebar.TabGroup.fromPrefs(for: .trailingSidebar),
                                  placement: Preference.enum(for: .trailingSidebarPlacement),
                                  visibility: trailingSidebarVisibility,
                                  lastVisibleTab: trailingSidebarLastVisibleTab)
    let mode = newMode ?? oldSpec.mode
    let interactiveMode = interactiveMode ?? oldSpec.interactiveMode
    let isLegacyStyle = isLegacyStyle ?? (mode.isFullScreen ? Preference.bool(for: .useLegacyFullScreen) : Preference.bool(for: .useLegacyWindowedMode))
    return LayoutSpec(leadingSidebar: leadingSidebar, trailingSidebar: trailingSidebar,
                      mode: mode,
                      isLegacyStyle: isLegacyStyle,
                      topBarPlacement: Preference.enum(for: .topBarPlacement),
                      bottomBarPlacement: Preference.enum(for: .bottomBarPlacement),
                      enableOSC: Preference.bool(for: .enableOSC),
                      oscPosition: Preference.enum(for: .oscPosition),
                      interactiveMode: interactiveMode,
                      moreSidebarState: oldSpec.moreSidebarState)
  }

  // Specify any properties to override; if nil, will use self's property values.
  func clone(leadingSidebar: Sidebar? = nil,
             trailingSidebar: Sidebar? = nil,
             mode: PlayerWindowMode? = nil,
             topBarPlacement: Preference.PanelPlacement? = nil,
             bottomBarPlacement: Preference.PanelPlacement? = nil,
             enableOSC: Bool? = nil,
             oscPosition: Preference.OSCPosition? = nil,
             isLegacyStyle: Bool? = nil,
             interactiveMode: InteractiveMode? = nil,
             moreSidebarState: Sidebar.SidebarMiscState? = nil) -> LayoutSpec {
    return LayoutSpec(leadingSidebar: leadingSidebar ?? self.leadingSidebar,
                      trailingSidebar: trailingSidebar ?? self.trailingSidebar,
                      mode: mode ?? self.mode,
                      isLegacyStyle: isLegacyStyle ?? self.isLegacyStyle,
                      topBarPlacement: topBarPlacement ?? self.topBarPlacement,
                      bottomBarPlacement: bottomBarPlacement ?? self.bottomBarPlacement,
                      enableOSC: enableOSC ?? self.enableOSC,
                      oscPosition: self.oscPosition,
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
}

/// `LayoutState`: data structure which contains all the variables which describe a single layout configuration of the `PlayerWindow`.
/// ("Layout" might have been a better name for this class, but it's already used by AppKit). Notes:
/// • With all the different window layout configurations which are now possible, it's crucial to use this class in order for animations
///   to work reliably.
/// • It should be treated like a read-only object after it's built. Its member variables are only mutable to make it easier to build.
/// • When any member variable inside it needs to be changed, a new `LayoutState` object should be constructed to describe the new state,
///   and a `LayoutTransition` should be built to describe the animations needs to go from old to new.
/// • The new `LayoutState`, once active, should be stored in the `currentLayout` of `PlayerWindowController` for future reference.
class LayoutState {
  init(spec: LayoutSpec) {
    self.spec = spec
  }

  // MARK: Stored properties

  // All other variables in this class are derived from this spec, or from stored prefs:
  let spec: LayoutSpec

  // - Visibility of views/categories

  var titleBar: VisibilityMode = .hidden
  var titleIconAndText: VisibilityMode = .hidden
  var trafficLightButtons: VisibilityMode = .hidden
  var titlebarAccessoryViewControllers: VisibilityMode = .hidden
  var leadingSidebarToggleButton: VisibilityMode = .hidden
  var trailingSidebarToggleButton: VisibilityMode = .hidden

  var controlBarFloating: VisibilityMode = .hidden

  var bottomBarView: VisibilityMode = .hidden
  var topBarView: VisibilityMode = .hidden

  // Only applies for legacy full screen:
  var hasTopPaddingForCameraHousing = false

  // - Sizes / offsets

  var sidebarDownshift: CGFloat = Constants.Sidebar.defaultDownshift
  var sidebarTabHeight: CGFloat = Constants.Sidebar.defaultTabHeight

  var titleBarHeight: CGFloat = 0
  var topOSCHeight: CGFloat = 0

  // MARK: Derived / computed properties

  var topBarHeight: CGFloat {
    self.titleBarHeight + self.topOSCHeight
  }

  var bottomBarHeight: CGFloat {
    if isInteractiveMode {
      return Constants.InteractiveMode.outsideBottomBarHeight
    }
    if enableOSC && oscPosition == .bottom {
      // FIXME: store this instead!
      return ControlBarGeometry.current.barHeight
    }
    return 0
  }

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
    return spec.mode == .windowed || spec.mode == .fullScreen
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
    return spec.mode == .windowed || spec.mode == .fullScreen
  }

  /// Only windowed & full screen modes can have floating OSC, and OSC must be enabled
  var hasFloatingOSC: Bool {
    return enableOSC && oscPosition == .floating
  }

  var hasTopOSC: Bool {
    return enableOSC && oscPosition == .top
  }

  var hasBottomOSC: Bool {
    return enableOSC && oscPosition == .bottom
  }

  var hasPermanentOSC: Bool {
    if isMusicMode {
      return true
    }
    return enableOSC && ((oscPosition == .top && topBarPlacement == .outsideViewport) ||
                         (oscPosition == .bottom && bottomBarPlacement == .outsideViewport))
  }

  var mode: PlayerWindowMode {
    return spec.mode
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
    if isFullScreen || !showOnTopStatus {
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

    // Title bar & title bar accessories:

    if outputLayout.isFullScreen {
      if layoutSpec.isLegacyStyle {
        outputLayout.hasTopPaddingForCameraHousing = Preference.bool(for: .allowVideoToOverlapCameraHousing)
      } else {
        outputLayout.titleIconAndText = .showAlways
        outputLayout.trafficLightButtons = .showAlways
      }

    } else if !outputLayout.isMusicMode {
      let visibleState: VisibilityMode = outputLayout.topBarPlacement == .insideViewport ? .showFadeableTopBar : .showAlways

      outputLayout.topBarView = visibleState

      if !layoutSpec.isLegacyStyle || LayoutSpec.enableTitleBarForLegacyWindow {
        outputLayout.titleBar = visibleState

        outputLayout.trafficLightButtons = visibleState
        outputLayout.titleIconAndText = visibleState
        // May be overridden depending on OSC layout anyway
        outputLayout.titleBarHeight = PlayerWindowController.standardTitleBarHeight

        outputLayout.titlebarAccessoryViewControllers = visibleState

        // LeadingSidebar toggle button
        let hasLeadingSidebar = !outputLayout.isInteractiveMode && !layoutSpec.leadingSidebar.tabGroups.isEmpty
        if hasLeadingSidebar && Preference.bool(for: .showLeadingSidebarToggleButton) {
          outputLayout.leadingSidebarToggleButton = visibleState
        }
        // TrailingSidebar toggle button
        let hasTrailingSidebar = !outputLayout.isInteractiveMode && !layoutSpec.trailingSidebar.tabGroups.isEmpty
        if hasTrailingSidebar && Preference.bool(for: .showTrailingSidebarToggleButton) {
          outputLayout.trailingSidebarToggleButton = visibleState
        }
      }

    }

    // OSC:

    if layoutSpec.enableOSC {
      // add fragment views
      switch layoutSpec.oscPosition {
      case .floating:
        outputLayout.controlBarFloating = .showFadeableNonTopBar  // floating is always fadeable
      case .top:
        if outputLayout.titleBar.isShowable {
          // If legacy window mode, do not show title bar.
          // Otherwise reduce its height a bit because it will share space with OSC
          outputLayout.titleBarHeight = PlayerWindowController.reducedTitleBarHeight
        }

        let visibility: VisibilityMode = outputLayout.topBarPlacement == .insideViewport ? .showFadeableTopBar : .showAlways
        outputLayout.topBarView = visibility
        outputLayout.topOSCHeight = ControlBarGeometry.current.barHeight
      case .bottom:
        outputLayout.bottomBarView = (outputLayout.bottomBarPlacement == .insideViewport) ? .showFadeableNonTopBar : .showAlways
      }
    } else {  // No OSC
      if layoutSpec.mode == .musicMode || layoutSpec.isInteractiveMode {
        assert(outputLayout.bottomBarPlacement == .outsideViewport)
        outputLayout.bottomBarView = .showAlways
      }
    }

    /// Sidebar tabHeight and downshift.
    /// Downshift: try to match height of title bar
    /// Tab height: if top OSC is `insideViewport`, try to match its height
    if outputLayout.isMusicMode {
      /// Special case for music mode. Only really applies to `playlistView`,
      /// because `quickSettingView` is never shown in this mode.
      outputLayout.sidebarTabHeight = Constants.Sidebar.musicModeTabHeight
    } else if outputLayout.topBarView.isShowable {
      // Top bar always spans the whole width of the window (unlike the bottom bar)
      // FIXME: someday, refactor title bar & top OSC outside of top bar & make iinto 2 independent bars.
      // (so that top OSC will not overlap outside sidebars)
      if outputLayout.topBarPlacement == .outsideViewport {
        outputLayout.sidebarDownshift = Constants.Sidebar.defaultDownshift
      } else {
        outputLayout.sidebarDownshift = outputLayout.topBarHeight
      }

      let tabHeight = outputLayout.topOSCHeight
      // Put some safeguards in place. Don't want to waste space or be too tiny to read.
      // Leave default height if not in reasonable range.
      if tabHeight >= Constants.Sidebar.minTabHeight && tabHeight <= Constants.Sidebar.maxTabHeight {
        outputLayout.sidebarTabHeight = tabHeight
      }
    }

    return outputLayout
  }

  // Converts & updates existing geometry to this layout
  func convertWindowedModeGeometry(from existingGeometry: PWinGeometry, video: VideoGeometry? = nil,
                                   keepFullScreenDimensions: Bool) -> PWinGeometry {
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
                                                          keepFullScreenDimensions: keepFullScreenDimensions)
    return resizedBarsGeo.refit()
  }

  func buildFullScreenGeometry(inScreenID screenID: String, video: VideoGeometry) -> PWinGeometry {
    let screen = NSScreen.getScreenOrDefault(screenID: screenID)
    return buildFullScreenGeometry(in: screen, video: video)
  }

  func buildFullScreenGeometry(in screen: NSScreen, video: VideoGeometry) -> PWinGeometry {
    assert(isFullScreen)
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
    case .fullScreen, .fullScreenInteractive:
      return buildFullScreenGeometry(inScreenID: screenID, video: video)
    case .windowedInteractive:
      return PWinGeometry.buildInteractiveModeWindow(windowFrame: windowFrame, screenID: screenID, video: video)
    case .windowed:
      let geo = PWinGeometry(windowFrame: windowFrame, screenID: screenID, fitOption: .stayInside,
                             mode: mode,
                             topMarginHeight: 0,  // is only nonzero when in legacy FS
                             outsideBars: outsideBars,
                             insideBars: insideBars,
                             video: video)
      return geo.scaleViewport()
    case .musicMode:
      let musicModeGeo = MusicModeGeometry(windowFrame: windowFrame, screenID: screenID, video: video,
                                           isVideoVisible: Preference.bool(for: .musicModeShowAlbumArt),
                                           isPlaylistVisible: Preference.bool(for: .musicModeShowPlaylist))
      return musicModeGeo.toPWinGeometry()
    }

  }

  /// Only for windowed modes!
  func buildDefaultInitialGeometry(screen: NSScreen) -> PWinGeometry {
    let defaultVideoGeo = VideoGeometry.defaultGeometry()
    let videoSize = defaultVideoGeo.videoSizeRaw
    let windowFrame = NSRect(origin: CGPoint.zero, size: videoSize)
    let geo = buildGeometry(windowFrame: windowFrame, screenID: screen.screenID, video: defaultVideoGeo)
    return geo.refit(.centerInside)
  }


}  // end class LayoutState
