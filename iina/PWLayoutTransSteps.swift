//
//  LayoutTransitionTasks.swift
//  iina
//
//  Created by Matt Svoboda on 10/4/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// Size of a side the 3 square playback button icons (Play/Pause, LeftArrow, RightArrow):
fileprivate var oscBarPlaybackIconSize: CGFloat {
  CGFloat(Preference.integer(for: .oscBarPlaybackIconSize)).clamped(to: 8...OSCToolbarButton.oscBarHeight)
}
/// Scale of spacing to the left & right of each playback button (for top/bottom OSC):
fileprivate var oscBarPlaybackIconSpacing: CGFloat {
  max(0, CGFloat(Preference.integer(for: .oscBarPlaybackIconSpacing)))
}

fileprivate let oscFloatingPlayBtnsSize: CGFloat = 24
fileprivate let oscFloatingPlayBtnsHPad: CGFloat = 24
fileprivate let oscFloatingToolbarButtonIconSize: CGFloat = 14
fileprivate let oscFloatingToolbarButtonIconPadding: CGFloat = 5

// TODO: reimplement OSC title bar feature
fileprivate let oscTitleBarPlayBtnsSize: CGFloat = 18
fileprivate let oscTitleBarPlayBtnsHPad: CGFloat = 6
fileprivate let oscTitleBarToolbarButtonIconSize: CGFloat = 14
fileprivate let oscTitleBarToolbarButtonIconPadding: CGFloat = 5

fileprivate extension NSStackView.VisibilityPriority {
  static let detachEarly = NSStackView.VisibilityPriority(rawValue: 950)
  static let detachEarlier = NSStackView.VisibilityPriority(rawValue: 900)
}

/// This file contains tasks to run in the animation queue, which form a `LayoutTransition`.
extension PlayerWindowController {

  /// -------------------------------------------------
  /// PRE TRANSITION
  func doPreTransitionWork(_ transition: LayoutTransition) {
    log.verbose("[\(transition.name)] DoPreTransitionWork")
    controlBarFloating.isDragging = false
    isAnimatingLayoutTransition = true

    /// Some methods where reference `currentLayout` get called as a side effect of the transition animations.
    /// To avoid possible bugs as a result, let's update this at the very beginning.
    currentLayout = transition.outputLayout

    if !transition.outputLayout.isWindowed && transition.inputLayout.isWindowed {
      /// `inputGeometry` may contain the most up-to-date `windowFrame` for `windowedModeGeo`, which `windowedModeGeo` does not have.
      /// Make sure to save it for later use:
      windowedModeGeo = transition.inputGeometry
    } else if !transition.outputLayout.isMusicMode && transition.inputLayout.isMusicMode {
      // Ditto with musicMode
      musicModeGeo = musicModeGeo.clone(windowFrame: transition.inputGeometry.windowFrame, screenID: transition.inputGeometry.screenID)
    }

    /// Set this here because we are setting `currentLayout`
    switch transition.outputLayout.mode {
    case .windowed, .windowedInteractive:
      windowedModeGeo = transition.outputGeometry
    case .fullScreen, .fullScreenInteractive:
      break  // Not applicable
    case .musicMode:
      // TODO: extend musicModeGeo from PWinGeometry and then use outputGeo instead of musicModeGeo reference
      let screenID = NSScreen.getOwnerOrDefaultScreenID(forViewRect: transition.outputGeometry.windowFrame)
      musicModeGeo = musicModeGeo.clone(windowFrame: transition.outputGeometry.windowFrame, screenID: screenID,
                                        video: transition.outputGeometry.video)
    }

    guard let window = window else { return }

    videoView.videoLayer.enterAsynchronousMode()

    // Need to call this here to avoid border being drawn incorrectly during FS transition.
    // But don't want to interfere with special effects such as fade-in
    let opacity = transition.isInitialLayout ? 0.0 : (window.contentView?.layer?.opacity ?? -1)
    updateCustomBorderBoxAndWindowOpacity(using: transition.outputLayout, windowOpacity: opacity)

    if transition.isEnteringFullScreen {
      /// `windowedModeGeo` should already be kept up to date. Might be hard to track down bugs...
      log.verbose("[\(transition.name)] Entering full screen; priorWindowedGeometry = \(windowedModeGeo)")
 
      // Hide traffic light buttons & title during the animation.
      // Do not move this block. It needs to go here.
      window.titleVisibility = .hidden
      hideBuiltInTitleBarViews(setAlpha: true)

      if #unavailable(macOS 10.14) {
        // Set the appearance to match the theme so the title bar matches the theme
        let iinaTheme = Preference.enum(for: .themeMaterial) as Preference.Theme
        switch(iinaTheme) {
        case .dark, .ultraDark:
          window.appearance = NSAppearance(named: .vibrantDark)
        default: 
          window.appearance = NSAppearance(named: .vibrantLight)
        }
      }

      setWindowFloatingOnTop(false, updateOnTopStatus: false)

      if transition.outputLayout.isLegacyFullScreen {
        // stylemask
        log.verbose("[\(transition.name)] Entering legacy FS; removing window styleMask.titled")
        if #available(macOS 10.16, *) {
          window.styleMask.remove(.titled)
          window.styleMask.insert(.borderless)
        } else {
          window.styleMask.insert(.fullScreen)
        }

        window.styleMask.remove(.resizable)

        // auto hide menubar and dock (this will freeze all other animations, so must do it last)
        updatePresentationOptionsForLegacyFullScreen(entering: true)

        /// When restoring, it's possible this window is not actually topmost.
        /// Make sure to check before putting it on top.
        refreshKeyWindowStatus()
      }
      if !player.isStopping {
        player.mpv.setFlag(MPVOption.Window.fullscreen, true)
        player.didEnterFullScreenViaUserToggle = true
      }

      resetViewsForModeTransition()

    } else if transition.isExitingFullScreen {
      // Exiting Full Screen

      resetViewsForModeTransition()
      apply(visibility: .hidden, to: additionalInfoView)

      if transition.inputLayout.isNativeFullScreen {
        // Hide traffic light buttons & title during the animation:
        hideBuiltInTitleBarViews(setAlpha: true)
      }

      if !player.isStopping {
        player.mpv.setFlag(MPVOption.Window.fullscreen, false)
        player.didEnterFullScreenViaUserToggle = false
      }
    }

    // Apply workaround for edge case when both sidebars are "outside" and visible, then one is opened or closed.
    // Need extra checks here so that the workaround isn't also applied when switching sidebar from "inside" to "outside".
    if transition.inputLayout.leadingSidebar.isVisible, transition.inputLayout.leadingSidebar.placement == .outsideViewport,
       transition.inputLayout.trailingSidebar.isVisible, transition.inputLayout.trailingSidebar.placement == .outsideViewport {
      prepareDepthOrderOfOutsideSidebarsForToggle(transition)
    }

    // Interactive mode
    if transition.isEnteringInteractiveMode {
      resetViewsForModeTransition()

      isPausedPriorToInteractiveMode = player.info.isPaused
      player.pause()

      videoView.layer?.shadowColor = .black
      videoView.layer?.shadowOffset = .zero
      videoView.layer?.shadowOpacity = 1
      videoView.layer?.shadowRadius = 3
    }

    // Music mode
    if transition.isTogglingMusicMode {
      resetViewsForModeTransition()

      if transition.isExitingMusicMode && !miniPlayer.isVideoVisible {
        // Restore video if needed
        player.setVideoTrackEnabled(true)
      }
    }

    if !transition.isInitialLayout && transition.isTogglingLegacyStyle {
      forceDraw()
    }
  }

  /// -------------------------------------------------
  /// FADE OUT OLD VIEWS
  func fadeOutOldViews(_ transition: LayoutTransition) {
    let outputLayout = transition.outputLayout
    log.verbose("[\(transition.name)] FadeOutOldViews")

    // Title bar & title bar accessories:

    let needToHideTopBar = transition.isTopBarPlacementChanging || transition.isTogglingLegacyStyle

    // Hide all title bar items if top bar placement is changing
    if needToHideTopBar || outputLayout.titleIconAndText == .hidden {
      apply(visibility: .hidden, documentIconButton, titleTextField, customTitleBar?.view)
    }

    if needToHideTopBar || outputLayout.trafficLightButtons == .hidden {
      if let customTitleBar {
        // legacy windowed mode
        customTitleBar.view.alphaValue = 0
      } else {
        // native windowed or full screen
        for button in trafficLightButtons {
          button.alphaValue = 0
        }
      }
    }

    if needToHideTopBar || outputLayout.titlebarAccessoryViewControllers == .hidden {
      // Hide all title bar accessories (if needed):
      leadingTitleBarAccessoryView.alphaValue = 0
      fadeableViewsTopBar.remove(leadingTitleBarAccessoryView)
      trailingTitleBarAccessoryView.alphaValue = 0
      fadeableViewsTopBar.remove(trailingTitleBarAccessoryView)
    } else {
      /// We may have gotten here in response to one of these buttons' visibility being toggled in the prefs,
      /// so we need to allow for showing/hiding these individually.
      /// Setting `.isHidden = true` for these icons visibly messes up their layout.
      /// So just set alpha value for now, and hide later in `updateHiddenViewsAndConstraints()`
      if outputLayout.leadingSidebarToggleButton == .hidden {
        leadingSidebarToggleButton.alphaValue = 0
        fadeableViewsTopBar.remove(leadingSidebarToggleButton)

        // Match behavior for custom title bar's copy:
        if let customTitleBar {
          customTitleBar.leadingSidebarToggleButton.alphaValue = 0
          fadeableViewsTopBar.remove(customTitleBar.leadingSidebarToggleButton)
        }
      }
      if outputLayout.trailingSidebarToggleButton == .hidden {
        trailingSidebarToggleButton.alphaValue = 0
        fadeableViewsTopBar.remove(trailingSidebarToggleButton)

        if let customTitleBar {
          customTitleBar.trailingSidebarToggleButton.alphaValue = 0
          fadeableViewsTopBar.remove(customTitleBar.trailingSidebarToggleButton)
        }
      }

      let onTopButtonVisibility = transition.outputLayout.computeOnTopButtonVisibility(isOnTop: isOnTop)
      if onTopButtonVisibility == .hidden {
        onTopButton.alphaValue = 0
        fadeableViewsTopBar.remove(onTopButton)

        if let customTitleBar {
          customTitleBar.onTopButton.alphaValue = 0
        }
      }
    }

    if transition.inputLayout.hasFloatingOSC && !outputLayout.hasFloatingOSC {
      // Hide floating OSC
      apply(visibility: outputLayout.controlBarFloating, to: controlBarFloating)
    }

    // Change blending modes
    if transition.isTogglingFullScreen {
      /// Need to use `.withinWindow` during animation or else panel tint can change in odd ways
      topBarView.blendingMode = .withinWindow
      bottomBarView.blendingMode = .withinWindow
      leadingSidebarView.blendingMode = .withinWindow
      trailingSidebarView.blendingMode = .withinWindow
    }

    if transition.isEnteringMusicMode {
      hideOSD()
    }

    if !outputLayout.hasFloatingOSC {
      controlBarFloating.removeMarginConstraints()
    }

    if outputLayout.mode == .fullScreenInteractive {
      apply(visibility: .hidden, to: additionalInfoView)
    }

    if transition.isExitingInteractiveMode, let cropController = self.cropSettingsView {
      // Exiting interactive mode
      cropController.view.alphaValue = 0
      cropController.view.isHidden = true
      cropController.cropBoxView.isHidden = true
      cropController.cropBoxView.alphaValue = 0
    }

    if transition.isTopBarPlacementChanging || transition.isBottomBarPlacementChanging || transition.isTogglingVisibilityOfAnySidebar {
      hideSeekTimeAndThumbnail()
    }
  }

  /// -------------------------------------------------
  /// CLOSE OLD PANELS
  /// This step is not always executed (e.g., for full screen toggle)
  func closeOldPanels(_ transition: LayoutTransition) {
    let outputLayout = transition.outputLayout
    log.verbose("[\(transition.name)] CloseOldPanels: title_H=\(outputLayout.titleBarHeight), topOSC_H=\(outputLayout.topOSCHeight)")

    if transition.inputLayout.titleBarHeight > 0 && outputLayout.titleBarHeight == 0 {
      titleBarHeightConstraint.animateToConstant(0)
    }
    if transition.inputLayout.topOSCHeight > 0 && outputLayout.topOSCHeight == 0 {
      topOSCHeightConstraint.animateToConstant(0)
    }
    
    if transition.isEnteringInteractiveMode {
      // Animate the close of viewport margins:
      videoView.apply(transition.outputGeometry)
    } else if transition.isExitingInteractiveMode {
      if transition.outputLayout.isFullScreen {
        videoView.apply(transition.outputGeometry)
      } else {
        // No margins (for a nice animation)
        videoView.apply(nil)
      }
    }

    // Update heights of top & bottom bars
    if let middleGeo = transition.middleGeometry {
      let topBarHeight = transition.inputLayout.topBarPlacement == .insideViewport ? middleGeo.insideBars.top : middleGeo.outsideBars.top
      let cameraOffset: CGFloat
      if transition.isExitingLegacyFullScreen {
        // Use prev offset for a smoother animation
        cameraOffset = transition.inputGeometry.topMarginHeight
      } else {
        cameraOffset = transition.outputGeometry.topMarginHeight
      }
      log.debug("[\(transition.name)] Applying middleGeo: topBarHeight=\(topBarHeight), cameraOffset=\(cameraOffset)")
      updateTopBarHeight(to: topBarHeight, topBarPlacement: transition.inputLayout.topBarPlacement, cameraHousingOffset: cameraOffset)

      if !transition.isExitingMusicMode && !transition.isExitingInteractiveMode {  // don't do this too soon when exiting Music Mode
        // Update sidebar vertical alignments to match top bar:
        let downshift = min(transition.inputLayout.sidebarDownshift, outputLayout.sidebarDownshift)
        let tabHeight = min(transition.inputLayout.sidebarTabHeight, outputLayout.sidebarTabHeight)
        updateSidebarVerticalConstraints(tabHeight: tabHeight, downshift: downshift)
      }

      let bottomBarHeight = transition.inputLayout.bottomBarPlacement == .insideViewport ? middleGeo.insideBars.bottom : middleGeo.outsideBars.bottom
      updateBottomBarHeight(to: bottomBarHeight, bottomBarPlacement: transition.inputLayout.bottomBarPlacement)

      if !transition.isExitingFullScreen {
        controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH, originRatioV: floatingOSCOriginRatioV,
                                  layout: transition.outputLayout, viewportSize: middleGeo.viewportSize)
      }

      // Sidebars (if closing)
      let ΔWindowWidth = middleGeo.windowFrame.width - transition.inputGeometry.windowFrame.width
      animateShowOrHideSidebars(transition: transition, layout: transition.inputLayout,
                                setLeadingTo: transition.isHidingLeadingSidebar ? .hide : nil,
                                setTrailingTo: transition.isHidingTrailingSidebar ? .hide : nil,
                                ΔWindowWidth: ΔWindowWidth)

      // Do not do this when first opening the window though, because it will cause the window location restore to be incorrect.
      // Also do not apply when toggling fullscreen because it is not relevant at this stage and will look glitchy because the
      // animation has zero duration.
      if !transition.isInitialLayout && (transition.isTogglingMusicMode || !transition.isTogglingFullScreen) {
        log.debug("[\(transition.name)] Calling setFrame from closeOldPanels with \(middleGeo.windowFrame)")
        player.window.setFrameImmediately(middleGeo, updateVideoView: !transition.isExitingInteractiveMode)
      }
    }

    if !transition.isInitialLayout && transition.isTogglingLegacyStyle {
      forceDraw()
    }
  }

  /// -------------------------------------------------
  /// MIDPOINT: UPDATE INVISIBLES
  func updateHiddenViewsAndConstraints(_ transition: LayoutTransition) {
    guard let window = window else { return }
    let outputLayout = transition.outputLayout
    log.verbose("[\(transition.name)] UpdateHiddenViewsAndConstraints")

    if transition.outputLayout.spec.isLegacyStyle {
      // Set legacy style
      setWindowStyleToLegacy()

      /// if `isTogglingLegacyStyle==true && isExitingFullScreen==true`, we are toggling out of legacy FS
      /// -> don't change `styleMask` to `.titled` here - it will look bad if screen has camera housing. Change at end of animation
    } else {
      // Not legacy style

      if !transition.isEnteringFullScreen {
        setWindowStyleToNative()
      }

      if transition.isExitingFullScreen {
        /// Setting `.titled` style will show buttons & title by default, but we don't want to show them until after panel open animation:
        window.titleVisibility = .hidden
        hideBuiltInTitleBarViews(setAlpha: true)
      }
    }

    // Allow for showing/hiding each button individually

    applyHiddenOnly(visibility: outputLayout.leadingSidebarToggleButton, to: leadingSidebarToggleButton)
    applyHiddenOnly(visibility: outputLayout.trailingSidebarToggleButton, to: trailingSidebarToggleButton)
    let onTopButtonVisibility = transition.outputLayout.computeOnTopButtonVisibility(isOnTop: isOnTop)
    applyHiddenOnly(visibility: onTopButtonVisibility, to: onTopButton)

    if let customTitleBar {
      applyHiddenOnly(visibility: outputLayout.leadingSidebarToggleButton, to: customTitleBar.leadingSidebarToggleButton)
      applyHiddenOnly(visibility: outputLayout.trailingSidebarToggleButton, to: customTitleBar.trailingSidebarToggleButton)
      applyHiddenOnly(visibility: onTopButtonVisibility, to: customTitleBar.onTopButton)
    }

    if outputLayout.titleBar == .hidden || transition.isTopBarPlacementChanging {
      /// Note: MUST use `titleVisibility` to guarantee that `documentIcon` & `titleTextField` are shown/hidden consistently.
      /// Setting `isHidden=true` on `titleTextField` and `documentIcon` do not animate and do not always work.
      /// We can use `alphaValue=0` to fade out in `fadeOutOldViews()`, but `titleVisibility` is needed to remove them.
      window.titleVisibility = .hidden
      hideBuiltInTitleBarViews(setAlpha: true)

      if let customTitleBar {
        customTitleBar.removeAndCleanUp()
        self.customTitleBar = nil
      }
    }

    /// These should all be either 0 height or unchanged from `transition.inputLayout`.
    /// But may need to add or remove from fadeableViews
    apply(visibility: outputLayout.bottomBarView, to: bottomBarView)
    // Note: hiding top bar here when entering FS with "top outside" OSC will cause it to go black too soon.
    // But we do need it when tranitioning from music mode → FS, or top bar may never be shown
    if !transition.isEnteringFullScreen || transition.isExitingMusicMode {
      apply(visibility: outputLayout.topBarView, to: topBarView)
    }

    if !transition.inputLayout.hasFloatingOSC {
      // Always remove subviews from OSC - is inexpensive + easier than figuring out if anything has changed
      // (except for floating OSC, which doesn't change much and has animation glitches if removed & re-added)
      for view in [fragVolumeView, fragToolbarView, fragPlaybackControlButtonsView] {
        view?.removeFromSuperview()
      }
      removeToolBar()
    }

    if !outputLayout.enableOSC && !outputLayout.isMusicMode {
      fragPositionSliderView?.removeFromSuperview()
    }

    if transition.isBottomBarPlacementChanging {
      updateBottomBarPlacement(placement: outputLayout.bottomBarPlacement)
    }

    /// Show dividing line only for `.outsideViewport` bottom bar. Don't show in music mode as it doesn't look good
    let showBottomBarTopBorder = transition.outputGeometry.outsideBars.bottom > 0 && outputLayout.bottomBarPlacement == .outsideViewport && !outputLayout.isMusicMode
    bottomBarTopBorder.isHidden = !showBottomBarTopBorder

    if let playSliderHeightConstraint {
      playSliderHeightConstraint.isActive = false
    }

    if let timePositionHoverLabelVerticalSpaceConstraint {
      timePositionHoverLabelVerticalSpaceConstraint.isActive = false
    }

    if transition.isExitingMusicMode {
      // Exiting music mode. Make sure to execute this before adding OSC below
      miniPlayer.loadIfNeeded()
      miniPlayer.cleanUpForMusicModeExit()
    }

    // [Re-]add OSC:
    if outputLayout.enableOSC {

      switch outputLayout.oscPosition {
      case .top:
        log.verbose("[\(transition.name)] Setting up control bar: \(outputLayout.oscPosition)")
        currentControlBar = controlBarTop

        addControlBarViews(to: oscTopMainView, playBtnSize: oscBarPlaybackIconSize, playBtnSpacing: oscBarPlaybackIconSpacing)

        // Subtract height of slider bar (4), then divide by 2 to get total bottom space, then subtract time label height to get total margin
        let timeLabelOffset = max(0, (((OSCToolbarButton.oscBarHeight - 4) / 2) - timePositionHoverLabel.frame.height) / 4)
        timePositionHoverLabelVerticalSpaceConstraint = timePositionHoverLabel.bottomAnchor.constraint(equalTo: timePositionHoverLabel.superview!.bottomAnchor, constant: -timeLabelOffset)

      case .bottom:
        log.verbose("[\(transition.name)] Setting up control bar: \(outputLayout.oscPosition)")
        currentControlBar = bottomBarView

        if !bottomBarView.subviews.contains(oscBottomMainView) {
          bottomBarView.addSubview(oscBottomMainView)
          oscBottomMainView.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: 8, trailing: 8)
        }

        addControlBarViews(to: oscBottomMainView, playBtnSize: oscBarPlaybackIconSize, playBtnSpacing: oscBarPlaybackIconSpacing)

        let timeLabelOffset = max(-1, (((OSCToolbarButton.oscBarHeight - 4) / 2) - timePositionHoverLabel.frame.height) / 4 - 2)
        timePositionHoverLabelVerticalSpaceConstraint = timePositionHoverLabel.topAnchor.constraint(equalTo: timePositionHoverLabel.superview!.topAnchor, constant: timeLabelOffset)

      case .floating:
        timePositionHoverLabelVerticalSpaceConstraint = timePositionHoverLabel.bottomAnchor.constraint(equalTo: timePositionHoverLabel.superview!.bottomAnchor, constant: -2)

        let toolbarView = rebuildToolbar(iconSize: oscFloatingToolbarButtonIconSize, iconPadding: oscFloatingToolbarButtonIconPadding)
        oscFloatingUpperView.addView(toolbarView, in: .trailing)
        oscFloatingUpperView.setVisibilityPriority(.detachEarlier, for: toolbarView)

        playbackButtonsSquareWidthConstraint.animateToConstant(oscFloatingPlayBtnsSize)
        playbackButtonsHorizontalPaddingConstraint.animateToConstant(oscFloatingPlayBtnsHPad)
      }

      let timeLabelFontSize: CGFloat
      let knobHeight: CGFloat
      if outputLayout.oscPosition == .floating {
        timeLabelFontSize = NSFont.smallSystemFontSize
        knobHeight = Constants.Distance.floatingOSCPlaySliderKnobHeight
      } else {
        let barHeight = OSCToolbarButton.oscBarHeight

        // Expand slider bounds to entire bar so it's easier to hover and/or click on it
        playSliderHeightConstraint = playSlider.heightAnchor.constraint(equalToConstant: barHeight)
        playSliderHeightConstraint.isActive = true

        switch barHeight {
        case 60...:
          timeLabelFontSize = NSFont.systemFontSize
          knobHeight = 24
        case 48...:
          timeLabelFontSize = NSFont.systemFontSize
          knobHeight = outputLayout.oscPosition == .bottom ? 18 : 15
        default:
          timeLabelFontSize = NSFont.smallSystemFontSize
          knobHeight = 15
        }
      }
      playSlider.customCell.knobHeight = knobHeight
      timePositionHoverLabel.font = NSFont.systemFont(ofSize: timeLabelFontSize)
      timePositionHoverLabelVerticalSpaceConstraint?.isActive = true

      updateArrowButtonImages()

      if outputLayout.oscPosition == .top {
        speedLabelVerticalConstraint.isActive = false
        speedLabelVerticalConstraint = speedLabel.bottomAnchor.constraint(equalTo: speedLabel.superview!.bottomAnchor, constant: 10)
        speedLabelVerticalConstraint.isActive = true
      } else {
        speedLabelVerticalConstraint.isActive = false
        speedLabelVerticalConstraint = speedLabel.topAnchor.constraint(equalTo: speedLabel.superview!.topAnchor, constant: -11)
        speedLabelVerticalConstraint.isActive = true
      }

    } else { // No OSC
      if outputLayout.isMusicMode {
        miniPlayer.loadIfNeeded()
        currentControlBar = miniPlayer.musicModeControlBarView
        updateArrowButtonImages()
      } else {
        currentControlBar = nil
      }
    }

    // Sidebars: finish closing (if closing)
    if transition.isHidingLeadingSidebar, let visibleTab = transition.inputLayout.leadingSidebar.visibleTab {
      /// Remove `tabGroupView` from its parent (also removes constraints):
      let viewController = (visibleTab.group == .playlist) ? playlistView : quickSettingView
      viewController.view.removeFromSuperview()
    }
    if transition.isHidingTrailingSidebar, let visibleTab = transition.inputLayout.trailingSidebar.visibleTab {
      /// Remove `tabGroupView` from its parent (also removes constraints):
      let viewController = (visibleTab.group == .playlist) ? playlistView : quickSettingView
      viewController.view.removeFromSuperview()
    }

    if transition.isEnteringMusicMode {
      // Entering music mode
      oscBottomMainView.removeFromSuperview()
      bottomBarView.addSubview(miniPlayer.view, positioned: .above, relativeTo: bottomBarTopBorder)
      miniPlayer.view.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)

      let bottomConstraint = miniPlayer.view.superview!.bottomAnchor.constraint(equalTo: miniPlayer.view.bottomAnchor, constant: 0)
      bottomConstraint.priority = .defaultHigh
      bottomConstraint.isActive = true

      // move playist view
      let playlistView = playlistView.view
      playlistView.removeFromSuperview()
      miniPlayer.playlistWrapperView.addSubview(playlistView)
      playlistView.addConstraintsToFillSuperview()

      // move playback position slider
      miniPlayer.positionSliderWrapperView.addSubview(fragPositionSliderView)
      fragPositionSliderView.addConstraintsToFillSuperview()
      // Expand slider bounds so that hovers are more likely to register
      playSliderHeightConstraint = playSlider.heightAnchor.constraint(equalToConstant: miniPlayer.positionSliderWrapperView.frame.height - 4)
      playSliderHeightConstraint.isActive = true
      playSlider.customCell.knobHeight = Constants.Distance.MusicMode.playSliderKnobHeight

      timePositionHoverLabelVerticalSpaceConstraint = timePositionHoverLabel.topAnchor.constraint(equalTo: timePositionHoverLabel.superview!.topAnchor, constant: -1)
      timePositionHoverLabelVerticalSpaceConstraint?.isActive = true
      timePositionHoverLabel.font = NSFont.systemFont(ofSize: 9)

      // Decrease font size of time labels
      leftLabel.font = NSFont.labelFont(ofSize: 9)
      rightLabel.font = NSFont.labelFont(ofSize: 9)

      // Update music mode UI
      updateTitle()
      applyThemeMaterial()

      if !miniPlayer.isVideoVisible, player.info.isVideoTrackSelected {
        player.setVideoTrackEnabled(false)
      }
    }
    // Need to call this for initial layout also:
    updateMusicModeButtonsVisibility()

    if transition.isTogglingInteractiveMode {
      // Even if entering IM, may have a prev crop due to a bug elsewhere. Remove if found
      if let cropController = self.cropSettingsView {
        cropController.cropBoxView.removeFromSuperview()
        cropController.view.removeFromSuperview()
        self.cropSettingsView = nil
      }

      if transition.isEnteringInteractiveMode {
        // Entering interactive mode
        if #available(macOS 10.14, *) {
          setEmptySpaceColor(to: Constants.Color.interactiveModeBackground)
        } else {
          setEmptySpaceColor(to: NSColor(calibratedWhite: 0.1, alpha: 1).cgColor)
        }

        // Add crop settings at bottom
        let cropController = self.cropSettingsView ?? transition.outputLayout.spec.interactiveMode!.viewController()
        cropController.windowController = self
        self.cropSettingsView = cropController
        bottomBarView.addSubview(cropController.view)
        cropController.view.addConstraintsToFillSuperview()
        cropController.view.alphaValue = 0
        let videoSizeRaw = player.videoGeo.videoSizeRaw
        if let cropController = cropSettingsView {
          addOrReplaceCropBoxSelection(rawVideoSize: videoSizeRaw, videoViewSize: transition.outputGeometry.videoSize)

          /// `selectedRect` should be subrect of`actualSize`
          let selectedRect: NSRect
          switch currentLayout.spec.interactiveMode {
          case .crop:
            if let prevCropFilter = player.info.videoFiltersDisabled[Constants.FilterLabel.crop] {
              selectedRect = prevCropFilter.cropRect(origVideoSize: videoSizeRaw, flipY: true)
              log.verbose("Setting crop box selection from prevFilter: \(selectedRect)")
            } else {
              selectedRect = NSRect(origin: .zero, size: videoSizeRaw)
              log.verbose("Setting crop box selection to default entire video size: \(selectedRect)")
            }
          case .freeSelecting, .none:
            selectedRect = .zero
          }
          cropController.cropBoxView.selectedRect = selectedRect
        }

      } else if transition.isExitingInteractiveMode {
        // Exiting interactive mode
        setEmptySpaceColor(to: Constants.Color.defaultWindowBackgroundColor)

        if let cropController = self.cropSettingsView {
          cropController.cropBoxView.removeFromSuperview()
          cropController.view.removeFromSuperview()
          self.cropSettingsView = nil
        }
      }
    }

    // Sidebars: if (re)opening
    if let tabToShow = transition.outputLayout.leadingSidebar.visibleTab {
      if transition.isShowingLeadingSidebar {
        prepareLayoutForOpening(leadingSidebar: transition.outputLayout.leadingSidebar, ΔWindowWidth: transition.ΔWindowWidth)
      } else if transition.inputLayout.leadingSidebar.visibleTabGroup == transition.outputLayout.leadingSidebar.visibleTabGroup {
        // Tab group is already showing, but just need to switch tab
        switchToTabInTabGroup(tab: tabToShow)
      }
    }
    if let tabToShow = transition.outputLayout.trailingSidebar.visibleTab {
      if transition.isShowingTrailingSidebar {
        prepareLayoutForOpening(trailingSidebar: transition.outputLayout.trailingSidebar, ΔWindowWidth: transition.ΔWindowWidth)
      } else if transition.inputLayout.trailingSidebar.visibleTabGroup == transition.outputLayout.trailingSidebar.visibleTabGroup {
        // Tab group is already showing, but just need to switch tab
        switchToTabInTabGroup(tab: tabToShow)
      }
    }

    if transition.outputLayout.isMusicMode {
      window.titleVisibility = .hidden
      hideBuiltInTitleBarViews()
    } else if transition.outputLayout.isWindowed && transition.outputLayout.spec.isLegacyStyle && LayoutSpec.enableTitleBarForLegacyWindow {
      if customTitleBar == nil {
        let titleBar = CustomTitleBarViewController()
        titleBar.windowController = self
        customTitleBar = titleBar
        titleBar.view.alphaValue = 0  // prep it to fade in later
      }

      if let customTitleBar {
        // Update superview based on placement. Cannot always add to contentView due to constraint issues
        if transition.outputLayout.topBarPlacement == .outsideViewport {
          customTitleBar.addViewToSuperview(titleBarView)
        } else {
          if let contentView = window.contentView {
            customTitleBar.addViewToSuperview(contentView)
          }
        }
        if !transition.inputLayout.titleBar.isShowable {
          customTitleBar.view.alphaValue = 0  // prep it to fade in later
        }
      }
    }

    updateDepthOrderOfBars(topBar: outputLayout.topBarPlacement, bottomBar: outputLayout.bottomBarPlacement,
                           leadingSidebar: outputLayout.leadingSidebarPlacement, trailingSidebar: outputLayout.trailingSidebarPlacement)

    prepareDepthOrderOfOutsideSidebarsForToggle(transition)

    // So that panels toggling between "inside" and "outside" don't change until they need to (different strategy than fullscreen)
    if !transition.isTogglingFullScreen {
      updatePanelBlendingModes(to: outputLayout)
    }

    updateUI()  // need this to update AdditionalInfo, volume

    if !transition.isInitialLayout && transition.isTogglingLegacyStyle {
      forceDraw()
    }
  }

  /// -------------------------------------------------
  /// OPEN PANELS & FINALIZE OFFSETS
  func openNewPanelsAndFinalizeOffsets(_ transition: LayoutTransition) {
    let outputLayout = transition.outputLayout
    log.verbose("[\(transition.name)] OpenNewPanels. TitleBar_H: \(outputLayout.titleBarHeight), TopOSC_H: \(outputLayout.topOSCHeight)")

    if transition.isExitingLegacyFullScreen {
      /// Seems this needs to be called before the final `setFrame` call, or else the window can end up incorrectly sized at the end
      updatePresentationOptionsForLegacyFullScreen(entering: false)
    }

    if transition.isEnteringMusicMode {
      miniPlayer.updateVideoViewVisibilityConstraints(isVideoVisible: musicModeGeo.isVideoVisible)
      miniPlayer.resetScrollingLabels()
    }

    // Update heights to their final values:
    topOSCHeightConstraint.animateToConstant(outputLayout.topOSCHeight)
    titleBarHeightConstraint.animateToConstant(outputLayout.titleBarHeight)

    updateOSDTopBarOffset(transition.outputGeometry, isLegacyFullScreen: transition.outputLayout.isLegacyFullScreen)

    // Update heights of top & bottom bars:
    updateTopBarHeight(to: outputLayout.topBarHeight, topBarPlacement: transition.outputLayout.topBarPlacement, cameraHousingOffset: transition.outputGeometry.topMarginHeight)

    let bottomBarHeight = transition.outputLayout.bottomBarPlacement == .insideViewport ? transition.outputGeometry.insideBars.bottom : transition.outputGeometry.outsideBars.bottom
    updateBottomBarHeight(to: bottomBarHeight, bottomBarPlacement: transition.outputLayout.bottomBarPlacement)

    // Sidebars (if opening)
    let leadingSidebar = transition.outputLayout.leadingSidebar
    let trailingSidebar = transition.outputLayout.trailingSidebar
    let ΔWindowWidth = transition.ΔWindowWidth
    animateShowOrHideSidebars(transition: transition,
                              layout: transition.outputLayout,
                              setLeadingTo: transition.isShowingLeadingSidebar ? leadingSidebar.visibility : nil,
                              setTrailingTo: transition.isShowingTrailingSidebar ? trailingSidebar.visibility : nil,
                              ΔWindowWidth: ΔWindowWidth)

    // Update sidebar vertical alignments
    updateSidebarVerticalConstraints(tabHeight: outputLayout.sidebarTabHeight, downshift: outputLayout.sidebarDownshift)

    if outputLayout.enableOSC && outputLayout.hasFloatingOSC {
      // Wait until now to set up floating OSC views. Doing this in prev or next task while animating results in visibility bugs
      currentControlBar = controlBarFloating

      if !transition.inputLayout.hasFloatingOSC {
        oscFloatingPlayButtonsContainerView.addView(fragPlaybackControlButtonsView, in: .center)
        // There sweems to be a race condition when adding to these StackViews.
        // Sometimes it still contains the old view, and then trying to add again will cause a crash.
        // Must check if it already contains the view before adding.
        if !oscFloatingUpperView.views(in: .leading).contains(fragVolumeView) {
          oscFloatingUpperView.addView(fragVolumeView, in: .leading)
        }
        oscFloatingUpperView.setVisibilityPriority(.detachEarly, for: fragVolumeView)

        oscFloatingUpperView.setClippingResistancePriority(.defaultLow, for: .horizontal)

        oscFloatingLowerView.addSubview(fragPositionSliderView)
        fragPositionSliderView.addConstraintsToFillSuperview()

        controlBarFloating.addMarginConstraints()
      }

      // Update floating control bar position
      controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH, originRatioV: floatingOSCOriginRatioV,
                                layout: transition.outputLayout, viewportSize: transition.outputGeometry.viewportSize)
    }

    switch transition.outputLayout.mode {
    case .fullScreen, .fullScreenInteractive:
      if transition.outputLayout.isNativeFullScreen {
        // Native Full Screen: set frame not including camera housing because it looks better with the native animation
        log.verbose("[\(transition.name)] Calling setFrame to animate into nativeFS, to: \(transition.outputGeometry.windowFrame)")
        player.window.setFrameImmediately(transition.outputGeometry)
      } else if transition.outputLayout.isLegacyFullScreen {
        let screen = NSScreen.getScreenOrDefault(screenID: transition.outputGeometry.screenID)
        let newGeo: PWinGeometry
        if transition.isEnteringLegacyFullScreen {
          // Deal with possible top margin needed to hide camera housing
          if transition.isInitialLayout {
            /// No animation after this
            newGeo = transition.outputGeometry
          } else if transition.outputGeometry.hasTopPaddingForCameraHousing {
            /// Entering legacy FS on a screen with camera housing, but `Use entire Macbook screen` is unchecked in Settings.
            /// Prevent an unwanted bouncing near the top by using this animation to expand to visibleFrame.
            /// (will expand window to cover `cameraHousingHeight` in next animation)
            newGeo = transition.outputGeometry.clone(windowFrame: screen.frameWithoutCameraHousing, screenID: screen.screenID, topMarginHeight: 0)
          } else {
            /// `Use entire Macbook screen` is checked in Settings. As of MacOS before Sonoma 14.4, Apple has been making improvements
            /// but we still need to use  a separate animation to give the OS time to hide the menu bar - otherwise there will be a flicker.
            let cameraHeight = screen.cameraHousingHeight ?? 0
            let geo = transition.outputGeometry
            let margins = geo.viewportMargins.addingTo(top: -cameraHeight)
            newGeo = geo.clone(windowFrame: geo.windowFrame.addingTo(top: -cameraHeight), viewportMargins: margins)
          }
        } else {
          /// Either already in legacy FS, or entering legacy FS. Apply final geometry.
          newGeo = transition.outputGeometry
        }
        log.verbose("[\(transition.name)] Calling setFrame for legacyFS in OpenNewPanels")
        /// This calls `videoView.apply`:
        applyLegacyFSGeo(newGeo)
      }
    case .musicMode:
      // Especially needed when applying initial layout:
      applyMusicModeGeo(musicModeGeo)
    case .windowed, .windowedInteractive:
      log.verbose("[\(transition.name)] Calling setFrame from OpenNewPanels with \(transition.outputGeometry.windowFrame)")
      player.window.setFrameImmediately(transition.outputGeometry)
    }

    if transition.outputGeometry.mode.isInteractiveMode {
      let videoSizeRaw = player.videoGeo.videoSizeRaw
      if let cropController = cropSettingsView {
        addOrReplaceCropBoxSelection(rawVideoSize: videoSizeRaw, videoViewSize: transition.outputGeometry.videoSize)
        // Hide for now, to prepare for a nice fade-in animation
        cropController.cropBoxView.isHidden = true
        cropController.cropBoxView.alphaValue = 0
        cropController.cropBoxView.layoutSubtreeIfNeeded()
      } else if !player.info.isRestoring, player.info.isFileLoaded, !player.info.isVideoTrackSelected {
        // if restoring, there will be a brief delay before getting player info, which is ok
        Utility.showAlert("no_video_track")
      }
    } else if transition.isExitingInteractiveMode && transition.outputLayout.isFullScreen {
      videoView.apply(transition.outputGeometry)
    }

    if !transition.isInitialLayout && transition.isTogglingLegacyStyle {
      forceDraw()
    }
  }

  /// -------------------------------------------------
  /// FADE IN NEW VIEWS
  func fadeInNewViews(_ transition: LayoutTransition) {
    guard let window = window else { return }
    let outputLayout = transition.outputLayout
    log.verbose("[\(transition.name)] FadeInNewViews")

    applyShowableOnly(visibility: outputLayout.controlBarFloating, to: controlBarFloating)

    if outputLayout.isFullScreen {
      if !outputLayout.isInteractiveMode && Preference.bool(for: .displayTimeAndBatteryInFullScreen) {
        apply(visibility: .showFadeableNonTopBar, to: additionalInfoView)
      }
    } else if outputLayout.titleBar.isShowable {
      if !transition.isExitingFullScreen {  // If exiting FS, the openNewPanels and fadInNewViews steps are combined. Wait till later
        if outputLayout.spec.isLegacyStyle {
          if let customTitleBar {
            customTitleBar.view.alphaValue = 1
          }
        } else {
          showBuiltInTitleBarViews()
          window.titleVisibility = .visible

          /// Title bar accessories get removed by fullscreen or if window `styleMask` did not include `.titled`.
          /// Add them back:
          addTitleBarAccessoryViews()
        }
      }

      applyShowableOnly(visibility: outputLayout.leadingSidebarToggleButton, to: leadingSidebarToggleButton)
      applyShowableOnly(visibility: outputLayout.trailingSidebarToggleButton, to: trailingSidebarToggleButton)
      updateOnTopButton()

      if let customTitleBar {
        apply(visibility: outputLayout.leadingSidebarToggleButton, to: customTitleBar.leadingSidebarToggleButton)
        apply(visibility: outputLayout.trailingSidebarToggleButton, to: customTitleBar.trailingSidebarToggleButton)
        /// onTop button is already handled by `updateOnTopButton()`
      }

      // Add back title bar accessories (if needed):
      applyShowableOnly(visibility: outputLayout.titlebarAccessoryViewControllers, to: leadingTitleBarAccessoryView)
      applyShowableOnly(visibility: outputLayout.titlebarAccessoryViewControllers, to: trailingTitleBarAccessoryView)
    }

    if let cropController = cropSettingsView {
      if transition.outputLayout.isInteractiveMode {
        // show crop settings view
        cropController.view.alphaValue = 1
        cropController.cropBoxView.isHidden = false
        cropController.cropBoxView.alphaValue = 1
      }

      // Native FS seems to change frame sizes on its own in some undocumented way, so just measure whatever is displayed for that.
      // But all other modes should use precalculated values because NSView bounds is sometimes not reliable depending on timing
      let cropBoxBounds = outputLayout.isNativeFullScreen ? videoView.bounds : NSRect(origin: CGPointZero, size: transition.outputGeometry.videoSize)
      cropController.cropBoxView.resized(with: cropBoxBounds)
      cropController.cropBoxView.layoutSubtreeIfNeeded()
    }

    if transition.isExitingInteractiveMode {
      if !isPausedPriorToInteractiveMode {
        player.resume()
      }
    }

    if transition.isExitingFullScreen && !transition.outputLayout.spec.isLegacyStyle && transition.outputLayout.titleBar.isShowable {
      // MUST put this in prev task to avoid race condition!
      window.titleVisibility = .visible
    }

    if !transition.isInitialLayout || transition.outputLayout.isFullScreen {
      updateCustomBorderBoxAndWindowOpacity(using: transition.outputLayout)
    }
  }

  /// -------------------------------------------------
  /// POST TRANSITION: UPDATE INVISIBLES
  func doPostTransitionWork(_ transition: LayoutTransition) {
    log.verbose("[\(transition.name)] DoPostTransitionWork")
    // Update blending mode:
    updatePanelBlendingModes(to: transition.outputLayout)

    fadeableViewsAnimationState = .shown
    fadeableTopBarAnimationState = .shown
    resetFadeTimer()

    guard let window else { return }

    if transition.isEnteringFullScreen {
      // Entered FullScreen

      restartHideCursorTimer()

      if transition.outputLayout.isNativeFullScreen {
        /// Special case: need to wait until now to call `trafficLightButtons.isHidden = false` due to their quirks
        for button in trafficLightButtons {
          button.isHidden = false
        }
      }

      if Preference.bool(for: .blackOutMonitor) {
        blackOutOtherMonitors()
      }

      if player.info.isPaused {
        if !player.info.isRestoring && Preference.bool(for: .playWhenEnteringFullScreen) {
          player.resume()
        } else {
          // When playback is paused the display link is stopped in order to avoid wasting energy on
          // needless processing. It must be running while transitioning to full screen mode. Now that
          // the transition has completed it can be stopped.
          videoView.displayIdle()
        }
      }

      if #available(macOS 10.12.2, *) {
        player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: true)
      }

      // Exit PIP if necessary
      if pipStatus == .inPIP,
         #available(macOS 10.12, *) {
        exitPIP()
      }

      player.events.emit(.windowFullscreenChanged, data: true)

    } else if transition.isExitingFullScreen {
      // Exited FullScreen

      if #available(macOS 10.16, *) {
        window.level = .normal
      } else {
        window.styleMask.remove(.fullScreen)
      }

      if transition.inputLayout.isLegacyFullScreen {
        window.styleMask.insert(.resizable)
      }

      if player.info.isPaused {
        // When playback is paused the display link is stopped in order to avoid wasting energy on
        // needless processing. It must be running while transitioning from full screen mode. Now that
        // the transition has completed it can be stopped.
        videoView.displayIdle()
      }

      if #available(macOS 10.12.2, *) {
        player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: false)
      }

      if transition.outputLayout.spec.isLegacyStyle {  // legacy windowed
        setWindowStyleToLegacy()
        if let customTitleBar {
          customTitleBar.view.alphaValue = 1
        }
      } else {  // native windowed
        /// Same logic as in `fadeInNewViews()`
        setWindowStyleToNative()
        if transition.outputLayout.isMusicMode {
          hideBuiltInTitleBarViews()
        } else {
          showBuiltInTitleBarViews()  /// do this again after adding `titled` style
        }
        // Need to make sure this executes after styleMask is .titled
        addTitleBarAccessoryViews()
        updateTitle()
      }

      if Preference.bool(for: .blackOutMonitor) {
        removeBlackWindows()
      }

      // restore ontop status
      if player.info.isPlaying {
        setWindowFloatingOnTop(isOnTop, updateOnTopStatus: false)
      }

      if Preference.bool(for: .pauseWhenLeavingFullScreen) && player.info.isPlaying {
        player.pause()
      }

      player.events.emit(.windowFullscreenChanged, data: false)
    }

    if transition.isTogglingFullScreen || transition.isTogglingMusicMode {
      if transition.outputLayout.isMusicMode && !musicModeGeo.isVideoVisible {
        player.setVideoTrackEnabled(false)
      } else {
        player.updateMPVWindowScale(using: transition.outputGeometry)
      }
    }

    refreshHidesOnDeactivateStatus()

    if !transition.isInitialLayout {
      window.layoutIfNeeded()
      forceDraw()
    }

    log.verbose("[\(transition.name)] Done with transition. IsFullScreen:\(transition.outputLayout.isFullScreen.yn), IsLegacy:\(transition.outputLayout.spec.isLegacyStyle.yn), Mode:\(currentLayout.mode)")

    if Logger.isEnabled(.error) {
      let actualVideoSize = videoView.frame.size
      let expectedVideoSize = transition.outputGeometry.videoSize
      if ((expectedVideoSize.area > 0) && (actualVideoSize.area > 0)) {
        if (expectedVideoSize.width != actualVideoSize.width) || (expectedVideoSize.height != actualVideoSize.height) {
          log.error("[\(transition.name)] ❌ 'VideoViewSize' sanity check failed! Expected=\(expectedVideoSize) Actual=\(actualVideoSize). Aspect: expected=\(expectedVideoSize.mpvAspect), actual=\(actualVideoSize.mpvAspect)")
        }
      }
      let actualWindowSize = window.frame.size
      let expectedWindowSize = transition.outputGeometry.windowFrame.size
      if (expectedWindowSize.width != actualWindowSize.width) || (expectedWindowSize.height != actualWindowSize.height) {
        log.error("[\(transition.name)] ❌ 'WindowSize' sanity check failed! Expected=\(expectedWindowSize)  Actual=\(actualWindowSize)")
      }
    }

    // abort any queued screen updates
    $screenChangedTicketCounter.withLock { $0 += 1 }
    $screenParamsChangedTicketCounter.withLock { $0 += 1 }
    isAnimatingLayoutTransition = false

    player.saveState()
  }

  // MARK: - Bars Layout

  // - Top bar

  func updateTopBarHeight(to topBarHeight: CGFloat, topBarPlacement: Preference.PanelPlacement, cameraHousingOffset: CGFloat) {
    log.verbose("Updating topBar height: \(topBarHeight), placement: \(topBarPlacement), cameraOffset: \(cameraHousingOffset)")

    switch topBarPlacement {
    case .insideViewport:
      viewportTopOffsetFromTopBarBottomConstraint.animateToConstant(-topBarHeight)
      viewportTopOffsetFromTopBarTopConstraint.animateToConstant(0)
      viewportTopOffsetFromContentViewTopConstraint.animateToConstant(0 + cameraHousingOffset)
    case .outsideViewport:
      viewportTopOffsetFromTopBarBottomConstraint.animateToConstant(0)
      viewportTopOffsetFromTopBarTopConstraint.animateToConstant(topBarHeight)
      viewportTopOffsetFromContentViewTopConstraint.animateToConstant(topBarHeight + cameraHousingOffset)
    }
  }

  // Update OSD (& Additional Info) views have correct offset from top of screen
  func updateOSDTopBarOffset(_ geometry: PWinGeometry, isLegacyFullScreen: Bool) {
    var newOffsetFromTop: CGFloat = 8
    if isLegacyFullScreen {
      let screen = NSScreen.forScreenID(geometry.screenID)!
      // OSD & Additional Info must never overlap camera housing, even if video does
      let cameraHousingHeight = screen.cameraHousingHeight ?? 0
      let usedSpaceAbove = geometry.outsideBars.top + geometry.insideBars.top

      if usedSpaceAbove < cameraHousingHeight {
        let windowGapForCameraHousing = screen.frame.height - geometry.windowFrame.height
        newOffsetFromTop -= windowGapForCameraHousing

        let videoFillsEntireScreen = !geometry.hasTopPaddingForCameraHousing
        if videoFillsEntireScreen {
          newOffsetFromTop += cameraHousingHeight
        }
      }
    }
    log.verbose("Updating osdTopToTopBarConstraint to: \(newOffsetFromTop)")
    osdTopToTopBarConstraint.animateToConstant(newOffsetFromTop)
  }

  // - Bottom bar

  private func updateBottomBarPlacement(placement: Preference.PanelPlacement) {
    log.verbose("Updating bottomBar placement to: \(placement)")
    guard let window = window, let contentView = window.contentView else { return }
    contentView.removeConstraint(bottomBarLeadingSpaceConstraint)
    contentView.removeConstraint(bottomBarTrailingSpaceConstraint)

    switch placement {
    case .insideViewport:
      // Align left & right sides with sidebars (top bar will squeeze to make space for sidebars)
      bottomBarLeadingSpaceConstraint = bottomBarView.leadingAnchor.constraint(equalTo: leadingSidebarView.trailingAnchor, constant: 0)
      bottomBarTrailingSpaceConstraint = bottomBarView.trailingAnchor.constraint(equalTo: trailingSidebarView.leadingAnchor, constant: 0)
    case .outsideViewport:
      // Align left & right sides with window (sidebars go below top bar)
      bottomBarLeadingSpaceConstraint = bottomBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0)
      bottomBarTrailingSpaceConstraint = bottomBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0)
    }
    bottomBarLeadingSpaceConstraint.isActive = true
    bottomBarTrailingSpaceConstraint.isActive = true
  }

  func updateBottomBarHeight(to bottomBarHeight: CGFloat, bottomBarPlacement: Preference.PanelPlacement) {
    log.verbose("Updating bottomBar height to: \(bottomBarHeight), placement: \(bottomBarPlacement)")

    switch bottomBarPlacement {
    case .insideViewport:
      viewportBottomOffsetFromBottomBarTopConstraint.animateToConstant(bottomBarHeight)
      viewportBottomOffsetFromBottomBarBottomConstraint.animateToConstant(0)
      viewportBottomOffsetFromContentViewBottomConstraint.animateToConstant(0)
    case .outsideViewport:
      viewportBottomOffsetFromBottomBarTopConstraint.animateToConstant(0)
      viewportBottomOffsetFromBottomBarBottomConstraint.animateToConstant(-bottomBarHeight)
      viewportBottomOffsetFromContentViewBottomConstraint.animateToConstant(bottomBarHeight)
    }
  }

  /// After bars are shown or hidden, or their placement changes, this ensures that their shadows appear in the correct places.
  /// • Outside bars never cast shadows or have shadows cast on them.
  /// • Inside sidebars cast shadows over inside top bar & inside bottom bar, and over `viewportView`.
  /// • Inside top & inside bottom bars do not cast shadows over `viewportView`.
  private func updateDepthOrderOfBars(topBar: Preference.PanelPlacement, bottomBar: Preference.PanelPlacement,
                                      leadingSidebar: Preference.PanelPlacement, trailingSidebar: Preference.PanelPlacement) {
    guard let window = window, let contentView = window.contentView else { return }

    // If a sidebar is "outsideViewport", need to put it behind the video because:
    // (1) Don't want sidebar to cast a shadow on the video
    // (2) Animate sidebar open/close with "slide in" / "slide out" from behind the video
    if leadingSidebar == .outsideViewport {
      contentView.addSubview(leadingSidebarView, positioned: .below, relativeTo: viewportView)
    }
    if trailingSidebar == .outsideViewport {
      contentView.addSubview(trailingSidebarView, positioned: .below, relativeTo: viewportView)
    }

    contentView.addSubview(topBarView, positioned: .above, relativeTo: viewportView)
    contentView.addSubview(bottomBarView, positioned: .above, relativeTo: viewportView)

    if leadingSidebar == .insideViewport {
      contentView.addSubview(leadingSidebarView, positioned: .above, relativeTo: viewportView)

      if bottomBar == .insideViewport {
        contentView.addSubview(bottomBarView, positioned: .below, relativeTo: leadingSidebarView)
      }
    }

    if trailingSidebar == .insideViewport {
      contentView.addSubview(trailingSidebarView, positioned: .above, relativeTo: viewportView)

      if bottomBar == .insideViewport {
        contentView.addSubview(bottomBarView, positioned: .below, relativeTo: trailingSidebarView)
      }
    }

    contentView.addSubview(controlBarFloating, positioned: .below, relativeTo: bottomBarView)
  }

  /// This fixes an edge case when both sidebars are shown and are `.outsideViewport`. When one is toggled, and width of
  /// `videoView` is smaller than that of the sidebar being toggled, must ensure that the sidebar being animated is below
  /// the other one, otherwise it will be briefly seen popping out on top of the other one.
  private func prepareDepthOrderOfOutsideSidebarsForToggle(_ transition: LayoutTransition) {
    guard transition.isTogglingVisibilityOfAnySidebar,
          transition.outputLayout.leadingSidebar.placement == .outsideViewport,
          transition.outputLayout.trailingSidebar.placement == .outsideViewport else { return }
    guard let contentView = window?.contentView else { return }

    if transition.isShowingLeadingSidebar || transition.isHidingLeadingSidebar {
      contentView.addSubview(leadingSidebarView, positioned: .below, relativeTo: trailingSidebarView)
    } else if transition.isShowingTrailingSidebar || transition.isHidingTrailingSidebar {
      contentView.addSubview(trailingSidebarView, positioned: .below, relativeTo: leadingSidebarView)
    }
  }

  // MARK: - Title bar items

  func addTitleBarAccessoryViews() {
    guard let window = window else { return }
    if leadingTitlebarAccesoryViewController == nil {
      let controller = NSTitlebarAccessoryViewController()
      leadingTitlebarAccesoryViewController = controller
      controller.view = leadingTitleBarAccessoryView
      controller.layoutAttribute = .leading

      leadingTitleBarAccessoryView.heightAnchor.constraint(equalToConstant: PlayerWindowController.standardTitleBarHeight).isActive = true
    }
    if trailingTitlebarAccesoryViewController == nil {
      let controller = NSTitlebarAccessoryViewController()
      trailingTitlebarAccesoryViewController = controller
      controller.view = trailingTitleBarAccessoryView
      controller.layoutAttribute = .trailing

      trailingTitleBarAccessoryView.heightAnchor.constraint(equalToConstant: PlayerWindowController.standardTitleBarHeight).isActive = true
    }
    if window.styleMask.contains(.titled) && window.titlebarAccessoryViewControllers.isEmpty {
      window.addTitlebarAccessoryViewController(leadingTitlebarAccesoryViewController!)
      window.addTitlebarAccessoryViewController(trailingTitlebarAccesoryViewController!)

      trailingTitleBarAccessoryView.translatesAutoresizingMaskIntoConstraints = false
      leadingTitleBarAccessoryView.translatesAutoresizingMaskIntoConstraints = false
    }
  }

  func hideBuiltInTitleBarViews(setAlpha: Bool = false) {
    /// Workaround for Apple bug (as of MacOS 13.3.1) where setting `alphaValue=0` on the "minimize" button will
    /// cause `window.performMiniaturize()` to be ignored. So to hide these, use `isHidden=true` + `alphaValue=1`
    /// (except for temporary animations).
    if setAlpha {
      documentIconButton?.alphaValue = 0
      titleTextField?.alphaValue = 0
    }
    documentIconButton?.isHidden = true
    titleTextField?.isHidden = true
    for button in trafficLightButtons {
      /// Special case for fullscreen transition due to quirks of `trafficLightButtons`.
      /// In most cases it's best to avoid setting `alphaValue = 0` for these because doing so will disable their menu items,
      /// but should be ok for brief animations
      if setAlpha {
        button.alphaValue = 0
      }
      button.isHidden = false
    }
  }

  /// Special case for these because their instances may change. Do not use `fadeableViews`. Always set `alphaValue = 1`.
  func showBuiltInTitleBarViews() {
    for button in trafficLightButtons {
      button.alphaValue = 1
      button.isHidden = false
    }
    titleTextField?.isHidden = false
    titleTextField?.alphaValue = 1
    documentIconButton?.isHidden = false
    documentIconButton?.alphaValue = 1
  }

  func updateOnTopButton() {
    let onTopButtonVisibility = currentLayout.computeOnTopButtonVisibility(isOnTop: isOnTop)
    onTopButton.state = isOnTop ? .on : .off
    apply(visibility: onTopButtonVisibility, to: onTopButton)

    if let customTitleBar {
      customTitleBar.onTopButton.state = isOnTop ? .on : .off
      apply(visibility: onTopButtonVisibility, to: customTitleBar.onTopButton)
    }

    if onTopButtonVisibility == .showFadeableTopBar {
      showFadeableViews()
    }
    player.saveState()
  }

  // MARK: - Controller content layout

  private func addControlBarViews(to containerView: NSStackView, playBtnSize: CGFloat, playBtnSpacing: CGFloat,
                                  toolbarIconSize: CGFloat? = nil, toolbarIconSpacing: CGFloat? = nil) {
    containerView.addView(fragPlaybackControlButtonsView, in: .leading)
    containerView.addView(fragPositionSliderView, in: .leading)
    containerView.addView(fragVolumeView, in: .leading)

    let toolbarView = rebuildToolbar(iconSize: toolbarIconSize, iconPadding: toolbarIconSpacing)
    containerView.addView(toolbarView, in: .leading)

    containerView.configureSubtreeForCoreAnimation()

    containerView.setClippingResistancePriority(.defaultLow, for: .horizontal)
    containerView.setVisibilityPriority(.mustHold, for: fragPositionSliderView)
    containerView.setVisibilityPriority(.detachEarly, for: fragVolumeView)
    containerView.setVisibilityPriority(.detachEarlier, for: toolbarView)

    playbackButtonsSquareWidthConstraint.animateToConstant(playBtnSize)

    var spacing = playBtnSpacing
    let arrowButtonAction: Preference.ArrowButtonAction = Preference.enum(for: .arrowButtonAction)
    if arrowButtonAction == .seek {
      spacing *= 0.5
    }
    playbackButtonsHorizontalPaddingConstraint.animateToConstant(spacing)
  }

  private func updateArrowButtonImages() {
    let arrowBtnAction: Preference.ArrowButtonAction = Preference.enum(for: .arrowButtonAction)
    let leftImage: NSImage
    let rightImage: NSImage
    switch arrowBtnAction {
    case .playlist:
      leftImage = #imageLiteral(resourceName: "nextl")
      rightImage = #imageLiteral(resourceName: "nextr")
    case .speed:
      leftImage = #imageLiteral(resourceName: "speedl")
      rightImage = #imageLiteral(resourceName: "speed")
    case .seek:
      if #available(macOS 11.0, *) {
        let leftIcon = NSImage(systemSymbolName: "gobackward.10", accessibilityDescription: "Step Backward 10s")!
        leftImage = leftIcon
        let rightIcon = NSImage(systemSymbolName: "goforward.10", accessibilityDescription: "Step Forward 10s")!
        rightImage = rightIcon
      } else {
        leftImage = #imageLiteral(resourceName: "speedl")
        rightImage = #imageLiteral(resourceName: "speed")
      }
    }
    let imageScaling: NSImageScaling = arrowBtnAction == .seek ? .scaleProportionallyDown : .scaleProportionallyUpOrDown
    leftArrowButton.image = leftImage
    rightArrowButton.image = rightImage
    leftArrowButton.imageScaling = imageScaling
    rightArrowButton.imageScaling = imageScaling

    if isInMiniPlayer {
      miniPlayer.loadIfNeeded()
      miniPlayer.leftArrowButton.image = leftImage
      miniPlayer.rightArrowButton.image = rightImage

      let spacing: CGFloat = arrowBtnAction == .seek ? 12 : 16
      miniPlayer.leftArrowToPlayButtonSpaceConstraint.animateToConstant(spacing)
      miniPlayer.playButtonToRightArrowSpaceConstraint.animateToConstant(spacing)
      miniPlayer.leftArrowButton.imageScaling = imageScaling
      miniPlayer.rightArrowButton.imageScaling = imageScaling
    }
  }

  private func rebuildToolbar(iconSize: CGFloat? = nil, iconPadding: CGFloat? = nil) -> NSStackView {
    let buttonTypeRawValues = Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []
    var buttonTypes = buttonTypeRawValues.compactMap(Preference.ToolBarButton.init(rawValue:))
    if #available(macOS 10.12.2, *) {} else {
      buttonTypes = buttonTypes.filter { $0 != .pip }
    }
    log.verbose("Adding buttons to OSC toolbar: \(buttonTypes)")

    var toolButtons: [OSCToolbarButton] = []
    for buttonType in buttonTypes {
      let button = OSCToolbarButton()
      button.setStyle(buttonType: buttonType, iconSize: iconSize, iconPadding: iconPadding)
      button.action = #selector(self.toolBarButtonAction(_:))
      toolButtons.append(button)
    }
    
    removeToolBar()

    let toolbarView = ClickThroughStackView()
    toolbarView.orientation = .horizontal
    toolbarView.distribution = .gravityAreas
    for button in toolButtons {
      toolbarView.addView(button, in: .trailing)
      toolbarView.setVisibilityPriority(.detachOnlyIfNecessary, for: button)
    }
    fragToolbarView = toolbarView

    // FIXME: this causes a crash due to conflicting constraints. Need to rewrite layout for toolbar button spacing!
    // It's not possible to control the icon padding from inside the buttons in all cases.
    // Instead we can get the same effect with a little more work, by controlling the stack view:
    //    if !toolButtons.isEmpty {
    //      let button = toolButtons[0]
    //      toolbarView.spacing = 2 * button.iconPadding
    //      toolbarView.edgeInsets = .init(top: button.iconPadding, left: button.iconPadding,
    //                                     bottom: button.iconPadding, right: button.iconPadding)
    //      Logger.log("Toolbar spacing: \(toolbarView.spacing), edgeInsets: \(toolbarView.edgeInsets)", level: .verbose, subsystem: player.subsystem)
    //    }
    return toolbarView
  }

  // Looks like in some cases, the toolbar doesn't disappear unless all its buttons are also removed
  private func removeToolBar() {
    guard let toolBarStackView = fragToolbarView else { return }

    toolBarStackView.views.forEach { toolBarStackView.removeView($0) }
    toolBarStackView.removeFromSuperview()
    fragToolbarView = nil
  }

  // MARK: - Misc support functions

  /// Call this when `origVideoSize` is known.
  /// `videoRect` should be `videoView.frame`
  func addOrReplaceCropBoxSelection(rawVideoSize: NSSize, videoViewSize: NSSize) {
    guard let cropController = self.cropSettingsView else { return }

    if !videoView.subviews.contains(cropController.cropBoxView) {
      videoView.addSubview(cropController.cropBoxView)
      cropController.cropBoxView.addConstraintsToFillSuperview()
    }

    cropController.cropBoxView.actualSize = rawVideoSize
    cropController.cropBoxView.resized(with: NSRect(origin: .zero, size: videoViewSize))
  }

  // Either legacy FS or windowed
  private func setWindowStyleToLegacy() {
    guard let window = window else { return }
    guard window.styleMask.contains(.titled) else { return }
    log.verbose("Removing window styleMask.titled")
    window.styleMask.remove(.titled)
    window.styleMask.insert(.borderless)
    window.styleMask.insert(.closable)
    window.styleMask.insert(.miniaturizable)
  }

  // "Native" == "titled"
  private func setWindowStyleToNative() {
    guard let window = window else { return }

    if !window.styleMask.contains(.titled) {
      log.verbose("Inserting window styleMask.titled")
      window.styleMask.insert(.titled)
      window.styleMask.remove(.borderless)
    }

    if let customTitleBar {
      customTitleBar.removeAndCleanUp()
      self.customTitleBar = nil
    }
  }

  private func resetViewsForModeTransition() {
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // needless processing. It must be running while transitioning to/from full screen mode.
    videoView.displayActive()

    hideSeekTimeAndThumbnail()
  }

  private func updatePanelBlendingModes(to outputLayout: LayoutState) {
    // Full screen + "behindWindow" doesn't blend properly and looks ugly
    if outputLayout.topBarPlacement == .insideViewport || outputLayout.isFullScreen {
      topBarView.blendingMode = .withinWindow
    } else {
      topBarView.blendingMode = .behindWindow
    }

    // Full screen + "behindWindow" doesn't blend properly and looks ugly
    if outputLayout.bottomBarPlacement == .insideViewport || outputLayout.isFullScreen {
      bottomBarView.blendingMode = .withinWindow
    } else {
      bottomBarView.blendingMode = .behindWindow
    }

    updateSidebarBlendingMode(.leadingSidebar, layout: outputLayout)
    updateSidebarBlendingMode(.trailingSidebar, layout: outputLayout)
  }
}
