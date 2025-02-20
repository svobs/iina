//
//  LayoutTransition.swift
//  iina
//
//  Created by Matt Svoboda on 10/3/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

extension PlayerWindowController {
  /// `LayoutTransition`: data structure which holds metadata needed to execute a series of animations which transition
  /// a single `PlayerWindow` from one layout (`inputLayout`) to another (`outputLayout`). Instances of `PWinGeometry`
  /// are also used along the way to dictate window location/size, viewport size, sidebar sizes, & other geometry.
  ///
  /// See `buildLayoutTransition()`, where an instance of this class is assembled.
  /// Other important variables: `currentLayout`, `windowedModeGeo`, `musicModeGeo` (in `PlayerWindowController`)
  class LayoutTransition {
    let name: String  // just used for debugging

    let inputLayout: LayoutState
    let outputLayout: LayoutState

    let inputGeometry: PWinGeometry
    var middleGeometry: PWinGeometry?
    let outputGeometry: PWinGeometry

    /// Should only be true when setting layout on session open. See `buildWindowInitialLayoutTasks()`.
    let isWindowInitialLayout: Bool

    var tasks: [IINAAnimation.Task] = []

    init(name: String, from inputLayout: LayoutState, from inputGeometry: PWinGeometry,
         to outputLayout: LayoutState, to outputGeometry: PWinGeometry,
         middleGeometry: PWinGeometry? = nil,
         isWindowInitialLayout: Bool = false) {
      self.name = name
      self.inputLayout = inputLayout
      self.inputGeometry = inputGeometry
      self.middleGeometry = middleGeometry
      self.outputLayout = outputLayout
      self.outputGeometry = outputGeometry
      self.isWindowInitialLayout = isWindowInitialLayout
    }

    // Always need to execute this step. But may not need to use an animation
    var needsAnimationForShowFadeables: Bool {
      return !outputLayout.isInteractiveMode && needsFadeOutOldViews
    }

    var needsFadeOutOldViews: Bool {
      return isTogglingLegacyStyle || isTopBarPlacementOrStyleChanging
      || (inputLayout.mode != outputLayout.mode)
      || (inputLayout.bottomBarPlacement == .insideViewport && isBottomBarPlacementOrStyleChanging) // fade OUT
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (inputLayout.enableOSC && (inputLayout.oscPosition != outputLayout.oscPosition))
      || (inputLayout.leadingSidebarToggleButton.isShowable && !outputLayout.leadingSidebarToggleButton.isShowable)
      || (inputLayout.trailingSidebarToggleButton.isShowable && !outputLayout.trailingSidebarToggleButton.isShowable)
    }

    var needsFadeInNewViews: Bool {
      if isTogglingFullScreen { return false }
      return isTogglingLegacyStyle || isTopBarPlacementOrStyleChanging
      || (inputLayout.mode != outputLayout.mode)
      || (outputLayout.bottomBarPlacement == .insideViewport && isBottomBarPlacementOrStyleChanging) // fade IN
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (outputLayout.enableOSC && (inputLayout.oscPosition != outputLayout.oscPosition))
      || (!inputLayout.leadingSidebarToggleButton.isShowable && outputLayout.leadingSidebarToggleButton.isShowable)
      || (!inputLayout.trailingSidebarToggleButton.isShowable && outputLayout.trailingSidebarToggleButton.isShowable)
    }

    var needsCloseOldPanels: Bool {
      if isEnteringFullScreen {
        // Avoid bounciness and possible unwanted video scaling animation (not needed for ->FS anyway)
        return false
      }
      return isHidingLeadingSidebar || isHidingTrailingSidebar
      || isTopBarPlacementOrStyleChanging || isBottomBarPlacementOrStyleChanging
      || (inputLayout.spec.isLegacyStyle != outputLayout.spec.isLegacyStyle)
      || (inputLayout.mode != outputLayout.mode)
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (inputLayout.enableOSC && (inputLayout.oscPosition != outputLayout.oscPosition))
    }

    // Always need to execute this step. But may not need to use an animation
    var needsAnimationForOpenFinalPanels: Bool {
      return (inputGeometry.topMarginHeight != outputGeometry.topMarginHeight)
      || isShowingLeadingSidebar || isShowingTrailingSidebar
      || isTopBarPlacementOrStyleChanging || isBottomBarPlacementOrStyleChanging
      || (inputLayout.spec.isLegacyStyle != outputLayout.spec.isLegacyStyle)
      || (inputLayout.mode != outputLayout.mode)
      || (inputLayout.topBarHeight != outputLayout.topBarHeight)
      || (inputGeometry.insideBars.bottom != outputGeometry.insideBars.bottom)
      || (inputGeometry.outsideBars.bottom != outputGeometry.outsideBars.bottom)
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (inputLayout.enableOSC && (inputLayout.oscPosition != outputLayout.oscPosition))
    }

    var isAddingLegacyStyle: Bool {
      return !inputLayout.spec.isLegacyStyle && outputLayout.spec.isLegacyStyle
    }

    var isRemovingLegacyStyle: Bool {
      return inputLayout.spec.isLegacyStyle && !outputLayout.spec.isLegacyStyle
    }

    var isTogglingLegacyStyle: Bool {
      return inputLayout.spec.isLegacyStyle != outputLayout.spec.isLegacyStyle
    }

    var isTogglingFullScreen: Bool {
      return inputLayout.isFullScreen != outputLayout.isFullScreen
    }

    var isEnteringFullScreen: Bool {
      return outputLayout.isFullScreen && (!inputLayout.isFullScreen || isWindowInitialLayout)
    }

    var isExitingFullScreen: Bool {
      return inputLayout.isFullScreen && !outputLayout.isFullScreen
    }

    var isEnteringNativeFullScreen: Bool {
      return isEnteringFullScreen && outputLayout.isNativeFullScreen
    }

    var isExitingNativeFullScreen: Bool {
      return isExitingFullScreen && inputLayout.isNativeFullScreen
    }

    var isEnteringLegacyFullScreen: Bool {
      return isEnteringFullScreen && outputLayout.isLegacyFullScreen
    }

    var isExitingLegacyFullScreen: Bool {
      return isExitingFullScreen && inputLayout.isLegacyFullScreen
    }

    var isTogglingLegacyFullScreen: Bool {
      return isEnteringLegacyFullScreen || isExitingLegacyFullScreen
    }

    var isEnteringMusicMode: Bool {
      return !inputLayout.isMusicMode && outputLayout.isMusicMode
    }

    var isExitingMusicMode: Bool {
      return inputLayout.isMusicMode && !outputLayout.isMusicMode
    }

    var isTogglingMusicMode: Bool {
      return inputLayout.isMusicMode != outputLayout.isMusicMode
    }

    var isEnteringInteractiveMode: Bool {
      return !inputLayout.isInteractiveMode && outputLayout.isInteractiveMode
    }

    var isExitingInteractiveMode: Bool {
      return inputLayout.isInteractiveMode && !outputLayout.isInteractiveMode
    }

    var isTogglingInteractiveMode: Bool {
      return isEnteringInteractiveMode || isExitingInteractiveMode
    }

    var isTopBarPlacementChanging: Bool {
      return inputLayout.topBarPlacement != outputLayout.topBarPlacement
    }

    var isOSCStyleChanging: Bool {
      return (inputLayout.effectiveOSCColorScheme != outputLayout.effectiveOSCColorScheme) ||
       (inputLayout.controlBarGeo.isTwoRowBarOSC != outputLayout.controlBarGeo.isTwoRowBarOSC)
    }

    var isTopBarPlacementOrStyleChanging: Bool {
      // assume that if a style change is happening, it affects active panel
      return isTopBarPlacementChanging // || (outputLayout.hasTopOSC && isOSCStyleChanging)
    }

    var isBottomBarPlacementChanging: Bool {
      return inputLayout.bottomBarPlacement != outputLayout.bottomBarPlacement
    }

    var isBottomBarPlacementOrStyleChanging: Bool {
      // assume that if a style change is happening, it affects active panel
      return isBottomBarPlacementChanging || (outputLayout.hasBottomOSC && isOSCStyleChanging)
    }

    var isLeadingSidebarPlacementChanging: Bool {
      return inputLayout.leadingSidebarPlacement != outputLayout.leadingSidebarPlacement
    }

    var isTrailingSidebarPlacementChanging: Bool {
      return inputLayout.trailingSidebarPlacement != outputLayout.trailingSidebarPlacement
    }

    lazy var isShowingLeadingSidebar: Bool = {
      return isShowing(.leadingSidebar)
    }()

    lazy var isShowingTrailingSidebar: Bool = {
      return isShowing(.trailingSidebar)
    }()

    lazy var isHidingLeadingSidebar: Bool = {
      return isHiding(.leadingSidebar)
    }()

    lazy var isHidingTrailingSidebar: Bool = {
      return isHiding(.trailingSidebar)
    }()

    lazy var isTogglingVisibilityOfAnySidebar: Bool = {
      return isShowingLeadingSidebar || isShowingTrailingSidebar || isHidingLeadingSidebar || isHidingTrailingSidebar
    }()

    /// Is opening given sidebar?
    func isShowing(_ sidebarID: Preference.SidebarLocation) -> Bool {
      let oldState = inputLayout.sidebar(withID: sidebarID)
      let newState = outputLayout.sidebar(withID: sidebarID)
      if !oldState.isVisible && newState.isVisible {
        return true
      }
      return isHidingAndThenShowing(sidebarID)
    }

    /// Is closing given sidebar?
    func isHiding(_ sidebarID: Preference.SidebarLocation) -> Bool {
      let oldState = inputLayout.sidebar(withID: sidebarID)
      let newState = outputLayout.sidebar(withID: sidebarID)
      if oldState.isVisible {
        if !newState.isVisible {
          return true
        }
        if let oldVisibleTabGroup = oldState.visibleTabGroup, let newVisibleTabGroup = newState.visibleTabGroup,
           oldVisibleTabGroup != newVisibleTabGroup {
          return true
        }
        if let visibleTabGroup = oldState.visibleTabGroup, !newState.tabGroups.contains(visibleTabGroup) {
          Logger.log("isHiding(sidebarID:): visibleTabGroup \(visibleTabGroup.rawValue.quoted) is not present in newState!", level: .error)
          return true
        }
      }
      return isHidingAndThenShowing(sidebarID)
    }

    func isHidingAndThenShowing(_ sidebarID: Preference.SidebarLocation) -> Bool {
      let oldState = inputLayout.sidebar(withID: sidebarID)
      let newState = outputLayout.sidebar(withID: sidebarID)
      if oldState.isVisible && newState.isVisible {
        if oldState.placement != newState.placement {
          return true
        }
        guard let oldGroup = oldState.visibleTabGroup, let newGroup = newState.visibleTabGroup else {
          Logger.log("needToCloseAndReopen(sidebarID:): visibleTabGroup missing!", level: .error)
          return false
        }
        if oldGroup != newGroup {
          return true
        }
      }
      return false
    }

    var ΔWindowWidth: CGFloat {
      return outputGeometry.windowFrame.width - inputGeometry.windowFrame.width
    }

    var isOpeningOSC: Bool {
      isWindowInitialLayout || !inputLayout.hasControlBar || isClosingThenReopeningOSC
    }

    /// For animation purposes only
    var isClosingThenReopeningOSC: Bool {
      (inputLayout.mode == outputLayout.mode && outputLayout.mode != .musicMode) &&
      (inputLayout.enableOSC != outputLayout.enableOSC || (inputLayout.hasBottomOSC && outputLayout.hasBottomOSC && isBottomBarPlacementOrStyleChanging) || (inputLayout.hasTopOSC && outputLayout.hasTopOSC && isTopBarPlacementChanging))
    }
  }

}
