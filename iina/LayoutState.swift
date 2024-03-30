//
//  LayoutState.swift
//  iina
//
//  Created by Matt Svoboda on 10/3/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

enum PlayerWindowMode: Int {
  case windowed = 1
  case fullScreen
  case musicMode
  case windowedInteractive
  case fullScreenInteractive

  var alwaysLockViewportToVideoSize: Bool {
    switch self {
    case .musicMode:
      return true
    case .fullScreen, .windowed, .windowedInteractive, .fullScreenInteractive:
      return false
    }
  }

  var neverLockViewportToVideoSize: Bool {
    switch self {
    case .fullScreen:
      return true
    case .musicMode, .windowedInteractive, .fullScreenInteractive, .windowed:
      return false
    }
  }

  var isInteractiveMode: Bool {
    return self == .windowedInteractive || self == .fullScreenInteractive
  }

  var lockViewportToVideoSize: Bool {
    if alwaysLockViewportToVideoSize {
      return true
    }
    if neverLockViewportToVideoSize {
      return false
    }
    return Preference.bool(for: .lockViewportToVideoSize)
  }
}

extension PlayerWindowController {

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

    init(leadingSidebar: Sidebar, trailingSidebar: Sidebar, mode: PlayerWindowMode, isLegacyStyle: Bool,
         topBarPlacement: Preference.PanelPlacement, bottomBarPlacement: Preference.PanelPlacement,
         enableOSC: Bool, oscPosition: Preference.OSCPosition, interactiveMode: InteractiveMode?) {

      var mode = mode
      if (mode == .windowedInteractive || mode == .fullScreenInteractive) && interactiveMode == nil {
        Logger.log("Cannot enter interactive mode (\(mode)) because its mode field is nil! Falling back to windowed mode")
        // Prevent invalid mode from crashing IINA. Just go to windowed instead
        mode = .windowed
      }
      self.mode = mode

      switch mode {
      case .musicMode, .windowedInteractive, .fullScreenInteractive:
        // Override most properties for music mode & interactive mode
        self.leadingSidebar = leadingSidebar.clone(visibility: .hide)
        self.trailingSidebar = trailingSidebar.clone(visibility: .hide)
        self.topBarPlacement = mode == .windowedInteractive ? .outsideViewport : .insideViewport
        self.bottomBarPlacement = .outsideViewport
        self.enableOSC = false
        self.interactiveMode = interactiveMode
      case .windowed, .fullScreen:
        self.leadingSidebar = leadingSidebar
        self.trailingSidebar = trailingSidebar
        self.topBarPlacement = topBarPlacement
        self.bottomBarPlacement = bottomBarPlacement
        self.enableOSC = enableOSC
        self.interactiveMode = nil
      }

      self.isLegacyStyle = isLegacyStyle
      self.oscPosition = oscPosition
    }

    /// Factory method. Matches what is shown in the XIB
    static func defaultLayout() -> LayoutSpec {
      let leadingSidebar = Sidebar(.leadingSidebar, tabGroups: Sidebar.TabGroup.fromPrefs(for: .leadingSidebar),
                                   placement: Preference.enum(for: .leadingSidebarPlacement),
                                   visibility: .hide)
      let trailingSidebar = Sidebar(.trailingSidebar, tabGroups: Sidebar.TabGroup.fromPrefs(for: .trailingSidebar),
                                    placement: Preference.enum(for: .trailingSidebarPlacement),
                                    visibility: .hide)
      return LayoutSpec(leadingSidebar: leadingSidebar,
                        trailingSidebar: trailingSidebar,
                        mode: .windowed,
                        isLegacyStyle: false,
                        topBarPlacement:.insideViewport,
                        bottomBarPlacement: .insideViewport,
                        enableOSC: false,
                        oscPosition: .floating,
                        interactiveMode: nil)
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
      let isLegacyStyle = isLegacyStyle ?? (mode == .fullScreen ? Preference.bool(for: .useLegacyFullScreen) : Preference.bool(for: .useLegacyWindowedMode))
      return LayoutSpec(leadingSidebar: leadingSidebar, trailingSidebar: trailingSidebar,
                        mode: mode,
                        isLegacyStyle: isLegacyStyle,
                        topBarPlacement: Preference.enum(for: .topBarPlacement),
                        bottomBarPlacement: Preference.enum(for: .bottomBarPlacement),
                        enableOSC: Preference.bool(for: .enableOSC),
                        oscPosition: Preference.enum(for: .oscPosition),
                        interactiveMode: interactiveMode)
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
               interactiveMode: InteractiveMode? = nil) -> LayoutSpec {
      return LayoutSpec(leadingSidebar: leadingSidebar ?? self.leadingSidebar,
                        trailingSidebar: trailingSidebar ?? self.trailingSidebar,
                        mode: mode ?? self.mode,
                        isLegacyStyle: isLegacyStyle ?? self.isLegacyStyle,
                        topBarPlacement: topBarPlacement ?? self.topBarPlacement,
                        bottomBarPlacement: bottomBarPlacement ?? self.bottomBarPlacement,
                        enableOSC: enableOSC ?? self.enableOSC,
                        oscPosition: self.oscPosition,
                        interactiveMode: interactiveMode ?? self.interactiveMode)
    }

    var isInteractiveMode: Bool {
      return mode.isInteractiveMode
    }

    var isFullScreen: Bool {
      return mode == .fullScreen || mode == .fullScreenInteractive
    }

    var isWindowed: Bool {
      return mode == .windowed || mode == .windowedInteractive
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
      let lead = leadingSidebarWidth ?? leadingSidebar.insideWidth
      let trail = trailingSidebarWidth ?? trailingSidebar.insideWidth
      return viewportWidth - lead - trail
    }

    func getExcessSpaceBetweenInsideSidebars(leadingSidebarWidth: CGFloat? = nil, trailingSidebarWidth: CGFloat? = nil,
                                             in viewportWidth: CGFloat) -> CGFloat {
      return getWidthBetweenInsideSidebars(leadingSidebarWidth: leadingSidebarWidth, trailingSidebarWidth: trailingSidebarWidth, in: viewportWidth) - Constants.Sidebar.minSpaceBetweenInsideSidebars
    }

    /// Returns `(shouldCloseLeadingSidebar, shouldCloseTrailingSidebar)`, indicating which sidebars should be hidden
    /// due to lack of space in the viewport.
    func isHideSidebarNeeded(in viewportWidth: CGFloat) -> (Bool, Bool) {
      var leadingSidebarSpace = leadingSidebar.insideWidth
      var trailingSidebarSpace = trailingSidebar.insideWidth
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

    // All other variables in this class are derived from this spec, or from stored prefs:
    let spec: LayoutSpec

    // Visibility of views/categories

    var titleBar: Visibility = .hidden
    var titleIconAndText: Visibility = .hidden
    var trafficLightButtons: Visibility = .hidden
    var titlebarAccessoryViewControllers: Visibility = .hidden
    var leadingSidebarToggleButton: Visibility = .hidden
    var trailingSidebarToggleButton: Visibility = .hidden

    var controlBarFloating: Visibility = .hidden

    var bottomBarView: Visibility = .hidden
    var topBarView: Visibility = .hidden

    // Only applies for legacy full screen:
    var hasTopPaddingForCameraHousing = false

    // Sizes / offsets

    var sidebarDownshift: CGFloat = Constants.Sidebar.defaultDownshift
    var sidebarTabHeight: CGFloat = Constants.Sidebar.defaultTabHeight

    var titleBarHeight: CGFloat = 0
    var topOSCHeight: CGFloat = 0

    var topBarHeight: CGFloat {
      self.titleBarHeight + self.topOSCHeight
    }

    var insideTopBarHeight: CGFloat {
      return topBarPlacement == .insideViewport ? topBarHeight : 0
    }

    /// Bar widths/heights IF `outsideViewport`

    var outsideTopBarHeight: CGFloat {
      return topBarPlacement == .outsideViewport ? topBarHeight : 0
    }

    /// NOTE: Is mutable!
    var outsideTrailingBarWidth: CGFloat {
      return spec.trailingSidebar.outsideWidth
    }

    /// NOTE: Is mutable!
    var outsideLeadingBarWidth: CGFloat {
      return spec.leadingSidebar.outsideWidth
    }

    /// Bar widths/heights IF `insideViewport`

    /// NOTE: Is mutable!
    var insideLeadingBarWidth: CGFloat {
      return spec.leadingSidebar.insideWidth
    }

    /// NOTE: Is mutable!
    var insideTrailingBarWidth: CGFloat {
      return spec.trailingSidebar.insideWidth
    }
    

    var bottomBarHeight: CGFloat {
      if isInteractiveMode {
        return Constants.InteractiveMode.outsideBottomBarHeight
      }
      if enableOSC && oscPosition == .bottom {
        return OSCToolbarButton.oscBarHeight
      }
      return 0
    }

    var insideBottomBarHeight: CGFloat {
      return bottomBarPlacement == .insideViewport ? bottomBarHeight : 0
    }

    var outsideBottomBarHeight: CGFloat {
      return bottomBarPlacement == .outsideViewport ? bottomBarHeight : 0
    }

    // Derived properties & convenience accessors

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

    var hasFloatingOSC: Bool {
      return enableOSC && oscPosition == .floating
    }

    var hasTopOSC: Bool {
      return enableOSC && oscPosition == .top
    }

    var hasPermanentOSC: Bool {
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

    func computeOnTopButtonVisibility(isOnTop: Bool) -> Visibility {
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
        let visibleState: Visibility = outputLayout.topBarPlacement == .insideViewport ? .showFadeableTopBar : .showAlways

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

          let visibility: Visibility = outputLayout.topBarPlacement == .insideViewport ? .showFadeableTopBar : .showAlways
          outputLayout.topBarView = visibility
          outputLayout.topOSCHeight = OSCToolbarButton.oscBarHeight
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
      } else if outputLayout.topBarView.isShowable && outputLayout.topBarPlacement == .insideViewport {
        outputLayout.sidebarDownshift = outputLayout.titleBarHeight

        let tabHeight = outputLayout.topOSCHeight
        // Put some safeguards in place. Don't want to waste space or be too tiny to read.
        // Leave default height if not in reasonable range.
        if tabHeight >= Constants.Sidebar.minTabHeight && tabHeight <= Constants.Sidebar.maxTabHeight {
          outputLayout.sidebarTabHeight = tabHeight
        }
      }

      return outputLayout
    }

    func buildFullScreenGeometry(inScreenID screenID: String, videoAspect: CGFloat) -> PWGeometry {
      let screen = NSScreen.getScreenOrDefault(screenID: screenID)
      return buildFullScreenGeometry(inside: screen, videoAspect: videoAspect)
    }

    func buildFullScreenGeometry(inside screen: NSScreen, videoAspect: CGFloat) -> PWGeometry {
      assert(isFullScreen)

      if isInteractiveMode {
        let windowFrame = PWGeometry.fullScreenWindowFrame(in: screen, legacy: spec.isLegacyStyle)
        let fitOption: ScreenFitOption = spec.isLegacyStyle ? .legacyFullScreen : .nativeFullScreen
        let topMarginHeight = screen.cameraHousingHeight ?? 0
        return PWGeometry(windowFrame: windowFrame, screenID: screen.screenID, fitOption: fitOption,
                          mode: mode, topMarginHeight: topMarginHeight,
                          outsideTopBarHeight: 0, outsideTrailingBarWidth: 0,
                          outsideBottomBarHeight: Constants.InteractiveMode.outsideBottomBarHeight,
                          outsideLeadingBarWidth: 0, insideTopBarHeight: 0,
                          insideTrailingBarWidth: 0, insideBottomBarHeight: 0, insideLeadingBarWidth: 0,
                          videoAspect: videoAspect)
      }

      return PWGeometry.forFullScreen(in: screen, legacy: spec.isLegacyStyle, mode: mode,
                                      outsideTopBarHeight: outsideTopBarHeight,
                                      outsideTrailingBarWidth: outsideTrailingBarWidth,
                                      outsideBottomBarHeight: outsideBottomBarHeight,
                                      outsideLeadingBarWidth: outsideLeadingBarWidth,
                                      insideTopBarHeight: insideTopBarHeight,
                                      insideTrailingBarWidth: insideTrailingBarWidth,
                                      insideBottomBarHeight: insideBottomBarHeight,
                                      insideLeadingBarWidth: insideLeadingBarWidth,
                                      videoAspect: videoAspect,
                                      allowVideoToOverlapCameraHousing: hasTopPaddingForCameraHousing)
    }

    // Converts & updates existing geometry to this layout
    func convertWindowedModeGeometry(from existingGeometry: PWGeometry, videoAspect: CGFloat? = nil,
                                     preserveFullSizeDimensions: Bool) -> PWGeometry {
      let resizedBarsGeo = existingGeometry.withResizedBars(outsideTopBarHeight: outsideTopBarHeight,
                                                            outsideTrailingBarWidth: outsideTrailingBarWidth,
                                                            outsideBottomBarHeight: outsideBottomBarHeight,
                                                            outsideLeadingBarWidth: outsideLeadingBarWidth,
                                                            insideTopBarHeight: insideTopBarHeight,
                                                            insideTrailingBarWidth: insideTrailingBarWidth,
                                                            insideBottomBarHeight: insideBottomBarHeight,
                                                            insideLeadingBarWidth: insideLeadingBarWidth,
                                                            videoAspect: videoAspect,
                                                            preserveFullSizeDimensions: preserveFullSizeDimensions)
      return resizedBarsGeo.refit()
    }
    
    func buildGeometry(windowFrame: NSRect, screenID: String, videoAspect: CGFloat) -> PWGeometry {
      assert(isWindowed, "buildGeometry(fromWindowFrame): unexpected mode: \(mode)")

      let geo = PWGeometry(windowFrame: windowFrame, screenID: screenID, fitOption: .keepInVisibleScreen,
                           mode: mode,
                           topMarginHeight: 0,  // is only nonzero when in legacy FS
                           outsideTopBarHeight: outsideTopBarHeight,
                           outsideTrailingBarWidth: outsideTrailingBarWidth,
                           outsideBottomBarHeight: outsideBottomBarHeight,
                           outsideLeadingBarWidth: outsideLeadingBarWidth,
                           insideTopBarHeight: insideTopBarHeight,
                           insideTrailingBarWidth: insideTrailingBarWidth,
                           insideBottomBarHeight: insideBottomBarHeight,
                           insideLeadingBarWidth: insideLeadingBarWidth,
                           videoAspect: videoAspect)
      return geo.scaleViewport()
    }

    /// Only for windowed modes!
    func buildDefaultInitialGeometry(screen: NSScreen) -> PWGeometry {
      let videoSize = AppData.defaultVideoSize
      let windowFrame = NSRect(origin: CGPoint.zero, size: videoSize)
      let geo = buildGeometry(windowFrame: windowFrame, screenID: screen.screenID, videoAspect: videoSize.mpvAspect)
      return geo.refit(.centerInVisibleScreen)
    }


  }  // end class LayoutState

  // MARK: - Visibility States

  enum Visibility {
    case hidden
    case showAlways
    case showFadeableTopBar     // fade in as part of the top bar
    case showFadeableNonTopBar  // fade in as a fadeable view which is not top bar

    var isShowable: Bool {
      return self != .hidden
    }
  }

  func apply(visibility: Visibility, to view: NSView) {
    switch visibility {
    case .hidden:
      view.alphaValue = 0
      view.isHidden = true
      fadeableViews.remove(view)
      fadeableViewsTopBar.remove(view)
    case .showAlways:
      view.alphaValue = 1
      view.isHidden = false
      fadeableViews.remove(view)
      fadeableViewsTopBar.remove(view)
    case .showFadeableTopBar:
      view.alphaValue = 1
      view.isHidden = false
      fadeableViewsTopBar.insert(view)
    case .showFadeableNonTopBar:
      view.alphaValue = 1
      view.isHidden = false
      fadeableViews.insert(view)
    }
  }

  func apply(visibility: Visibility, _ views: NSView?...) {
    for view in views {
      if let view = view {
        apply(visibility: visibility, to: view)
      }
    }
  }

  func applyHiddenOnly(visibility: Visibility, to view: NSView, isTopBar: Bool = true) {
    guard visibility == .hidden else { return }
    apply(visibility: visibility, view)
  }

  func applyShowableOnly(visibility: Visibility, to view: NSView, isTopBar: Bool = true) {
    guard visibility != .hidden else { return }
    apply(visibility: visibility, view)
  }
}
