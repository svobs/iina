//
//  LayoutTransitionTasks.swift
//  iina
//
//  Created by Matt Svoboda on 10/4/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

fileprivate extension NSStackView.VisibilityPriority {
  static let detachEarly = NSStackView.VisibilityPriority(rawValue: 950)
  static let detachEarlier = NSStackView.VisibilityPriority(rawValue: 900)
}

/// This file contains tasks to run in the animation queue, which form a `LayoutTransition`.
extension PlayerWindowController {

  /// -------------------------------------------------
  /// PRE TRANSITION
  func doPreTransitionWork(_ transition: LayoutTransition) {
    log.verbose{"[\(transition.name)] DoPreTransitionWork"}
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
    case .windowedNormal, .windowedInteractive:
      windowedModeGeo = transition.outputGeometry
    case .fullScreenNormal, .fullScreenInteractive:
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
    let opacity = window.contentView?.layer?.opacity ?? -1
    updateWindowBorderAndOpacity(using: transition.outputLayout, windowOpacity: opacity)

    if transition.isEnteringFullScreen {
      /// `windowedModeGeo` should already be kept up to date. Might be hard to track down bugs...
      log.verbose{"[\(transition.name)] Entering full screen; priorWindowedGeometry = \(windowedModeGeo)"}

      // Hide traffic light buttons & title during the animation.
      // Do not move this block. It needs to go here.
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
        log.verbose{"[\(transition.name)] Entering legacy FS; removing window styleMask.titled"}
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
        // Video was disabled in music mode, but need to restore it now
        player.setVideoTrackEnabled(true)
      }
    }

    if !transition.isWindowInitialLayout && transition.isTogglingLegacyStyle {
      forceDraw()
    }
  }

  /// -------------------------------------------------
  /// FADE OUT OLD VIEWS
  func fadeOutOldViews(_ transition: LayoutTransition) {
    let outputLayout = transition.outputLayout
    log.verbose{"[\(transition.name)] FadeOutOldViews"}

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
      fadeableViewsInTopBar.remove(leadingTitleBarAccessoryView)
      trailingTitleBarAccessoryView.alphaValue = 0
      fadeableViewsInTopBar.remove(trailingTitleBarAccessoryView)
    } else {
      /// We may have gotten here in response to one of these buttons' visibility being toggled in the prefs,
      /// so we need to allow for showing/hiding these individually.
      /// Setting `.isHidden = true` for these icons visibly messes up their layout.
      /// So just set alpha value for now, and hide later in `updateHiddenViewsAndConstraints()`
      if outputLayout.leadingSidebarToggleButton == .hidden {
        leadingSidebarToggleButton.alphaValue = 0
        fadeableViewsInTopBar.remove(leadingSidebarToggleButton)

        // Match behavior for custom title bar's copy:
        if let customTitleBar {
          customTitleBar.leadingSidebarToggleButton.alphaValue = 0
          fadeableViewsInTopBar.remove(customTitleBar.leadingSidebarToggleButton)
        }
      }
      if outputLayout.trailingSidebarToggleButton == .hidden {
        trailingSidebarToggleButton.alphaValue = 0
        fadeableViewsInTopBar.remove(trailingSidebarToggleButton)

        if let customTitleBar {
          customTitleBar.trailingSidebarToggleButton.alphaValue = 0
          fadeableViewsInTopBar.remove(customTitleBar.trailingSidebarToggleButton)
        }
      }

      let onTopButtonVisibility = transition.outputLayout.computeOnTopButtonVisibility(isOnTop: isOnTop)
      if onTopButtonVisibility == .hidden {
        onTopButton.alphaValue = 0
        fadeableViewsInTopBar.remove(onTopButton)

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
      if let bottomBarView = bottomBarView as? NSVisualEffectView {
        bottomBarView.blendingMode = .withinWindow
      }
      leadingSidebarView.blendingMode = .withinWindow
      trailingSidebarView.blendingMode = .withinWindow
    }

    if transition.isTogglingMusicMode {
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
      hideSeekPreview()
    }
  }

  /// -------------------------------------------------
  /// CLOSE OLD PANELS
  /// This step is not always executed (e.g., for full screen toggle)
  func closeOldPanels(_ transition: LayoutTransition) {
    let outputLayout = transition.outputLayout
    log.verbose{"[\(transition.name)] CloseOldPanels: title_H=\(outputLayout.titleBarHeight), topOSC_H=\(outputLayout.topOSCHeight)"}

    if outputLayout.hasControlBar {
      // Reduce size of icons if they are smaller
      let oscGeo = outputLayout.controlBarGeo

      if volumeIconHeightConstraint.constant > oscGeo.volumeIconHeight {
        volumeIconHeightConstraint.animateToConstant(oscGeo.volumeIconHeight)
        if let img = muteButton.image {
          volumeIconWidthConstraint.isActive = false
          volumeIconWidthConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: img.aspect)
          volumeIconWidthConstraint.priority = .init(900)
          volumeIconWidthConstraint.isActive = true
        }
      }

      if arrowBtnWidthConstraint.constant > oscGeo.arrowIconHeight {
        arrowBtnWidthConstraint.animateToConstant(oscGeo.arrowIconWidth)
      }
      if playBtnWidthConstraint.constant > oscGeo.playIconSize {
        playBtnWidthConstraint.animateToConstant(oscGeo.playIconSize)
      }

      if fragPlaybackBtnsWidthConstraint.constant > oscGeo.totalPlayControlsWidth {
        fragPlaybackBtnsWidthConstraint.animateToConstant(oscGeo.totalPlayControlsWidth)
      }

      if leftArrowBtnHorizOffsetConstraint.constant > oscGeo.leftArrowOffsetX {
        leftArrowBtnHorizOffsetConstraint.animateToConstant(oscGeo.leftArrowOffsetX)
      }

      if rightArrowBtnHorizOffsetConstraint.constant > oscGeo.rightArrowOffsetX {
        rightArrowBtnHorizOffsetConstraint.animateToConstant(oscGeo.rightArrowOffsetX)
      }
    }

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
      log.verbose{"[\(transition.name)] Applying middleGeo: topBarHeight=\(topBarHeight), cameraOffset=\(cameraOffset)"}
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
      if !transition.isWindowInitialLayout && (transition.isTogglingMusicMode || !transition.isTogglingFullScreen) {
        log.debug{"[\(transition.name)] Calling setFrame from closeOldPanels with middleGeo \(middleGeo.windowFrame)"}
        player.window.setFrameImmediately(middleGeo, updateVideoView: !transition.isExitingInteractiveMode)
      }
    }

    if !transition.isWindowInitialLayout && transition.isTogglingLegacyStyle {
      forceDraw()
    }
  }

  /// -------------------------------------------------
  /// MIDPOINT: UPDATE INVISIBLES
  func updateHiddenViewsAndConstraints(_ transition: LayoutTransition) {
    guard let window = window else { return }
    let outputLayout = transition.outputLayout
    log.verbose{"[\(transition.name)] UpdateHiddenViewsAndConstraints"}

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

    // TODO: be smarter about this, so animations can be improved
    if !transition.inputLayout.hasFloatingOSC {
      // Always remove subviews from OSC - is inexpensive + easier than figuring out if anything has changed
      // (except for floating OSC, which doesn't change much and has animation glitches if removed & re-added)
      for view in [fragVolumeView, fragToolbarView, fragPlaybackBtnsView] {
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

    playSliderHeightConstraint?.isActive = false

    seekPreview.timeLabelVerticalSpaceConstraint?.isActive = false
    seekPreview.timeLabelHorizontalCenterConstraint?.isActive = false

    if transition.isTogglingMusicMode {
      miniPlayer.loadIfNeeded()
      showOrHidePipOverlayView()

      if transition.isExitingMusicMode {
        miniPlayer.cleanUpForMusicModeExit()
        if !transition.inputGeometry.isVideoVisible {
          addVideoViewToWindow()
        }
      }
    }

    // [Re-]add OSC:
    if outputLayout.enableOSC {
      let oscGeo = outputLayout.controlBarGeo
      log.verbose("[\(transition.name)] Setting up control bar=\(outputLayout.oscPosition) playIconSize=\(oscGeo.playIconSize) playIconSpacing=\(oscGeo.playIconSpacing)")

      switch outputLayout.oscPosition {
      case .top:
        currentControlBar = controlBarTop

        addControlBarViews(to: oscTopMainView, oscGeo, transition)

        seekPreview.timeLabelVerticalSpaceConstraint = seekPreview.timeLabel.topAnchor.constraint(equalTo: playSlider.bottomAnchor, constant: -4)
        seekPreview.timeLabelVerticalSpaceConstraint?.isActive = true

      case .bottom:
        currentControlBar = bottomBarView

        if !bottomBarView.subviews.contains(oscBottomMainView) {
          bottomBarView.addSubview(oscBottomMainView, positioned: .below, relativeTo: bottomBarTopBorder)
          // Match leading/trailing spacing of title bar icons above
          oscBottomMainView.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: Constants.Distance.titleBarIconSpacingH, trailing: Constants.Distance.titleBarIconSpacingH)
        }

        addControlBarViews(to: oscBottomMainView, oscGeo, transition)

        seekPreview.timeLabelVerticalSpaceConstraint = seekPreview.timeLabel.bottomAnchor.constraint(equalTo: playSlider.topAnchor, constant: 4)
        seekPreview.timeLabelVerticalSpaceConstraint?.isActive = true

      case .floating:

        if let toolbarView = rebuildToolbar(transition) {
          oscFloatingUpperView.addView(toolbarView, in: .trailing)
          oscFloatingUpperView.setVisibilityPriority(.detachEarlier, for: toolbarView)
        }
      }

      let timeLabelFontSize: CGFloat
      let knobHeight: CGFloat
      if outputLayout.oscPosition == .floating {
        timeLabelFontSize = NSFont.smallSystemFontSize
        knobHeight = Constants.Distance.floatingOSCPlaySliderKnobHeight
      } else {
        let barHeight = oscGeo.barHeight

        // Expand slider bounds to entire bar so it's easier to hover and/or click on it
        playSliderHeightConstraint = playSlider.heightAnchor.constraint(equalToConstant: barHeight)
        playSliderHeightConstraint.isActive = true

        // Knob height > 24 is not supported
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
      (volumeSlider.cell as? VolumeSliderCell)?.knobHeight = knobHeight
      seekPreview.timeLabel.font = NSFont.systemFont(ofSize: timeLabelFontSize)

    } else if outputLayout.isMusicMode {

      // Music mode always has a control bar
      miniPlayer.loadIfNeeded()
      currentControlBar = miniPlayer.musicModeControlBarView

      // move playback buttons
      if !miniPlayer.playbackBtnsWrapperView.subviews.contains(fragPlaybackBtnsView) {
        miniPlayer.playbackBtnsWrapperView.addSubview(fragPlaybackBtnsView)
        miniPlayer.playbackBtnsWrapperView.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor).isActive = true
        miniPlayer.playbackBtnsWrapperView.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor).isActive = true
      }

    } else {  // No OSC & not music mode
      currentControlBar = nil
    }

    if currentControlBar == nil {
      if transition.inputLayout.hasTopOSC {
        oscBottomMainView.removeFromSuperview()
      }
    } else {
      // Has OSC, or music mode

      updateArrowButtons(oscGeo: outputLayout.controlBarGeo)
      playSlider.customCell.updateColorsFromPrefs()

      if transition.isWindowInitialLayout || (transition.inputLayout.contentTintColor != transition.outputLayout.contentTintColor) {
        let contentTintColor: NSColor? = transition.outputLayout.contentTintColor
        playButton.contentTintColor = contentTintColor
        leftArrowButton.contentTintColor = contentTintColor
        rightArrowButton.contentTintColor = contentTintColor
        muteButton.contentTintColor = contentTintColor

        // Default alpha for these is 0.5. They don't change their text color.
        let textAlpha: CGFloat = contentTintColor == nil ? 0.5 : 1.0
        leftTimeLabel.alphaValue = textAlpha
        rightTimeLabel.alphaValue = textAlpha
        RenderCache.shared.mainKnobColor = transition.outputLayout.spec.oscBackgroundIsClear ? NSColor.controlForClearBG : NSColor.mainSliderKnob
        // invalidate all cached knob images
        RenderCache.shared.invalidateCachedKnobs()
      }

      if !outputLayout.hasFloatingOSC {  // floating case will be handled in later step
                                         // Yes, left, not leading!
        seekPreview.timeLabelHorizontalCenterConstraint = seekPreview.timeLabel.centerXAnchor.constraint(equalTo: playSlider.leftAnchor, constant: 200)
        seekPreview.timeLabelHorizontalCenterConstraint.identifier = .init("SeekTimeHoverLabelHSpaceConstraint")
        seekPreview.timeLabelHorizontalCenterConstraint.isActive = true
      }

      if transition.isEnteringMusicMode {
        // Entering music mode
        bottomBarView.addSubview(miniPlayer.view, positioned: .below, relativeTo: bottomBarTopBorder)
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

        // move playback buttons
        if !miniPlayer.playbackBtnsWrapperView.subviews.contains(fragPlaybackBtnsView) {
          miniPlayer.playbackBtnsWrapperView.addSubview(fragPlaybackBtnsView)
          miniPlayer.playbackBtnsWrapperView.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor).isActive = true
          miniPlayer.playbackBtnsWrapperView.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor).isActive = true
        }

        seekPreview.timeLabelVerticalSpaceConstraint = seekPreview.timeLabel.bottomAnchor.constraint(equalTo: playSlider.topAnchor, constant: 2)
        seekPreview.timeLabelVerticalSpaceConstraint?.isActive = true

        seekPreview.timeLabel.font = NSFont.systemFont(ofSize: 9)

        // Decrease font size of time labels
        leftTimeLabel.font = NSFont.labelFont(ofSize: 9)
        rightTimeLabel.font = NSFont.labelFont(ofSize: 9)

        // Update music mode UI
        updateTitle()
        applyThemeMaterial()

        if !miniPlayer.isVideoVisible, pip.status == .notInPIP {
          player.setVideoTrackEnabled(false)
        }
      }
    }

    // Leading Sidebar
    if transition.isHidingLeadingSidebar,
        let visibleTab = transition.inputLayout.leadingSidebar.visibleTab {
      /// Finish closing (if closing).
      /// Remove `tabGroupView` from its parent (also removes constraints):
      let viewController = (visibleTab.group == .playlist) ? playlistView : quickSettingView
      viewController.view.removeFromSuperview()
    } else if let tabToShow = transition.outputLayout.leadingSidebar.visibleTab {  // Opening
      if transition.isShowingLeadingSidebar {
        prepareLayoutForOpening(leadingSidebar: transition.outputLayout.leadingSidebar,
                                parentLayout: transition.outputLayout, ΔWindowWidth: transition.ΔWindowWidth)
      } else if transition.inputLayout.leadingSidebar.visibleTabGroup == transition.outputLayout.leadingSidebar.visibleTabGroup {
        // Tab group is already showing, but just need to switch tab
        switchToTabInTabGroup(tab: tabToShow)
      }
    }

    // Trailing Sidebar
    if transition.isHidingTrailingSidebar,
        let visibleTab = transition.inputLayout.trailingSidebar.visibleTab {
      /// Finish closing (if closing).
      /// Remove `tabGroupView` from its parent (also removes constraints):
      let viewController = (visibleTab.group == .playlist) ? playlistView : quickSettingView
      viewController.view.removeFromSuperview()
    } else if let tabToShow = transition.outputLayout.trailingSidebar.visibleTab {  // Opening
      if transition.isShowingTrailingSidebar {
        prepareLayoutForOpening(trailingSidebar: transition.outputLayout.trailingSidebar,
                                parentLayout: transition.outputLayout, ΔWindowWidth: transition.ΔWindowWidth)
      } else if transition.inputLayout.trailingSidebar.visibleTabGroup == transition.outputLayout.trailingSidebar.visibleTabGroup {
        // Tab group is already showing, but just need to switch tab
        switchToTabInTabGroup(tab: tabToShow)
      }
    }

    // Not floating OSC!
    if !transition.outputLayout.hasFloatingOSC {
      addSpeedLabelToControlBar(transition)
    }

    // Need to call this for initial layout also:
    updateMusicModeButtonsVisibility(using: musicModeGeo)

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
              log.verbose{"Setting crop box selection from prevFilter: \(selectedRect)"}
            } else {
              selectedRect = NSRect(origin: .zero, size: videoSizeRaw)
              log.verbose{"Setting crop box selection to default entire video size: \(selectedRect)"}
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

    if transition.outputLayout.isMusicMode {
      hideBuiltInTitleBarViews()
    } else if transition.outputLayout.isWindowed,
              transition.outputLayout.spec.isLegacyStyle {
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

    if outputLayout.leadingSidebarPlacement == .insideViewport {
      leadingSidebarView.material = .menu
    } else {
      leadingSidebarView.material = .toolTip
    }

    if outputLayout.trailingSidebarPlacement == .insideViewport {
      trailingSidebarView.material = .menu
    } else {
      trailingSidebarView.material = .toolTip
    }

    updateDepthOrderOfBars(topBar: outputLayout.topBarPlacement, bottomBar: outputLayout.bottomBarPlacement,
                           leadingSidebar: outputLayout.leadingSidebarPlacement, trailingSidebar: outputLayout.trailingSidebarPlacement)

    prepareDepthOrderOfOutsideSidebarsForToggle(transition)

    // So that panels toggling between "inside" and "outside" don't change until they need to (different strategy than fullscreen)
    if !transition.isTogglingFullScreen {
      updatePanelBlendingModes(to: outputLayout)
    }

    updateAdditionalInfo()
    updateVolumeUI()

    if !transition.isWindowInitialLayout && transition.isTogglingLegacyStyle {
      forceDraw()
    }
  }

  /// -------------------------------------------------
  /// OPEN PANELS & FINALIZE OFFSETS
  func openNewPanelsAndFinalizeOffsets(_ transition: LayoutTransition) {
    let outputLayout = transition.outputLayout
    log.verbose{"[\(transition.name)] OpenNewPanels. TitleBar_H: \(outputLayout.titleBarHeight), TopOSC_H: \(outputLayout.topOSCHeight)"}

    if transition.isExitingLegacyFullScreen {
      /// Seems this needs to be called before the final `setFrame` call, or else the window can end up incorrectly sized at the end
      updatePresentationOptionsForLegacyFullScreen(entering: false)
    }

    // Update heights to their final values:
    topOSCHeightConstraint.animateToConstant(outputLayout.topOSCHeight)
    titleBarHeightConstraint.animateToConstant(outputLayout.titleBarHeight)

    updateOSDTopBarOffset(transition.outputGeometry, isLegacyFullScreen: transition.outputLayout.isLegacyFullScreen)

    // Update heights of top & bottom bars:
    updateTopBarHeight(to: outputLayout.topBarHeight, topBarPlacement: transition.outputLayout.topBarPlacement, cameraHousingOffset: transition.outputGeometry.topMarginHeight)

    let bottomBarHeight = transition.outputLayout.bottomBarPlacement == .insideViewport ? transition.outputGeometry.insideBars.bottom : transition.outputGeometry.outsideBars.bottom
    updateBottomBarHeight(to: bottomBarHeight, bottomBarPlacement: transition.outputLayout.bottomBarPlacement)

    if outputLayout.hasControlBar {
      // Increase size of icons if they are larger
      let oscGeo = outputLayout.controlBarGeo

      volumeIconHeightConstraint.animateToConstant(oscGeo.volumeIconHeight)
      if let img = muteButton.image {
        volumeIconWidthConstraint.isActive = false
        volumeIconWidthConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: img.aspect)
        volumeIconWidthConstraint.priority = .init(900)
        volumeIconWidthConstraint.isActive = true
      }

      arrowBtnWidthConstraint.animateToConstant(oscGeo.arrowIconWidth)
      playBtnWidthConstraint.animateToConstant(oscGeo.playIconSize)
      fragPlaybackBtnsWidthConstraint.animateToConstant(oscGeo.totalPlayControlsWidth)
      leftArrowBtnHorizOffsetConstraint.animateToConstant(oscGeo.leftArrowOffsetX)
      rightArrowBtnHorizOffsetConstraint.animateToConstant(oscGeo.rightArrowOffsetX)
    }


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
        oscFloatingPlayButtonsContainerView.addView(fragPlaybackBtnsView, in: .center)
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
      addSpeedLabelToControlBar(transition)

      // same as `.bottom`:
      seekPreview.timeLabelVerticalSpaceConstraint = seekPreview.timeLabel.bottomAnchor.constraint(equalTo: playSlider.topAnchor, constant: 4)
      seekPreview.timeLabelVerticalSpaceConstraint?.isActive = true

      // Yes, left, not leading!
      seekPreview.timeLabelHorizontalCenterConstraint = seekPreview.timeLabel.centerXAnchor.constraint(equalTo: playSlider.leftAnchor, constant: 200)
      seekPreview.timeLabelHorizontalCenterConstraint.identifier = .init("SeekTimeHoverLabelHSpaceConstraint")
      seekPreview.timeLabelHorizontalCenterConstraint.isActive = true

      // Update floating control bar position
      controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH, originRatioV: floatingOSCOriginRatioV,
                                layout: transition.outputLayout, viewportSize: transition.outputGeometry.viewportSize)
    }

    switch transition.outputLayout.mode {
    case .fullScreenNormal, .fullScreenInteractive:
      if transition.outputLayout.isNativeFullScreen {
        // Native Full Screen: set frame not including camera housing because it looks better with the native animation
        log.verbose{"[\(transition.name)] Calling setFrame to animate into nativeFS, to: \(transition.outputGeometry.windowFrame)"}
        player.window.setFrameImmediately(transition.outputGeometry)
      } else if transition.outputLayout.isLegacyFullScreen {
        let screen = NSScreen.getScreenOrDefault(screenID: transition.outputGeometry.screenID)
        let newGeo: PWinGeometry
        if transition.isEnteringLegacyFullScreen {
          // Deal with possible top margin needed to hide camera housing
          if transition.isWindowInitialLayout {
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
      applyMusicModeGeo(musicModeGeo, updateCache: false)
    case .windowedNormal, .windowedInteractive:
      log.verbose("[\(transition.name)] Calling setFrame from OpenNewPanels with output windowFrame=\(transition.outputGeometry.windowFrame)")
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

    if !transition.isWindowInitialLayout && transition.isTogglingLegacyStyle {
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

    if !transition.isWindowInitialLayout || transition.outputLayout.isFullScreen {
      updateWindowBorderAndOpacity(using: transition.outputLayout)
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
      // Entered FS

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

      player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: true)

      // Exit PIP when entering full screen
      if pip.status == .inPIP {
        exitPIP()
      }

      player.events.emit(.windowFullscreenChanged, data: true)

    } else if transition.isExitingFullScreen {
      // Exited FS

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

      player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: false)

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
      if transition.outputLayout.isMusicMode && !musicModeGeo.isVideoVisible && pip.status == .notInPIP {
        player.setVideoTrackEnabled(false)
      } else {
        player.updateMPVWindowScale(using: transition.outputGeometry)
      }
    }

    if transition.isTogglingMusicMode, Preference.bool(for: .playlistShowMetadataInMusicMode) {
      /// Need to toggle music metadata due to music mode switch.
      /// Do this even if playlist is not visible now, because it will not be be reloaded when toggled.
      playlistView.reloadPlaylistRows()
    }

    refreshHidesOnDeactivateStatus()

    if !transition.isWindowInitialLayout {
      window.layoutIfNeeded()
      forceDraw()

      // Do not run sanity checks for initial layout, because in that case all task funcs combined into a single
      // animation task, which means that frames will not be updated yet & can't be measured correctly
      if Logger.isEnabled(.error) && pip.status == .notInPIP && player.state.isNotYet(.stopping) {
        let vidSizeA = videoView.frame.size
        let vidSizeE = transition.outputGeometry.videoSize
        let viewportSizeA = viewportView.frame.size
        let viewportSizeE = transition.outputGeometry.viewportSize
        let winSizeA = window.frame.size
        let winSizeE = transition.outputGeometry.windowFrame.size

        let isWrongVidSize = (vidSizeE.area > 0 && vidSizeA.area > 0) &&
          ((vidSizeE.width != vidSizeA.width) || (vidSizeE.height != vidSizeA.height))
        let isWrongWinSize = (winSizeE.width != winSizeA.width) || (winSizeE.height != winSizeA.height)

        if isWrongVidSize || isWrongWinSize {
          /// Now that the transition is done and layout is complete, it is useful to check that our calculations are consistent with the result.
          /// In AppKit, `NSWindow` is the root object for the view hierarchy, so its size is easiest to get right. We start our calculations with
          /// the outermost panels & build inward (see `PWinGeometry`), so errors accumulate along the way & will result in `videoView.frame.size`
          /// (i.e. actual video size) since it is innermost.
          /// NOTE: this verifies (A) the AppKit NSView hierarchy with (B) `VideoGeometry` & `PWinGeometry`' layout calculations, but does not
          /// verify them against (C) mpv's internal video size calculations. Those are checked in `PWin_Resize.swift`
          /// (search for another instance of the UTF "X" like the one below).
          let wrong = "ⓧ"
          let lines = ["[\(transition.name)] ❌ Sanity check failed!",
                       "  VidAspect: Expect=\(vidSizeE.mpvAspect) Actual=\(vidSizeA.mpvAspect) Constraint=\(videoView.aspectMultiplier?.logStr ?? "nil")",
                       "  VideoSize: Expect=\(vidSizeE) Actual=\(vidSizeA)  \(isWrongVidSize ? wrong : "")",
                       "  Viewport:  Expect=\(viewportSizeE) Actual=\(viewportSizeA)",
                       "  WinFrame:  Expect=\(transition.outputGeometry.windowFrame) Actual=\(window.frame)  \(isWrongWinSize ? wrong : "")",
                       "  VidMargins: \(transition.outputGeometry.viewportMargins)",  // Size should == viewport - video. (Unless video is wrong)
                       ]
          log.error(lines.joined(separator: "\n"))
        }
      }

    }

    log.verbose("[\(transition.name)] Done with transition. IsFullScreen:\(transition.outputLayout.isFullScreen.yn), IsLegacy:\(transition.outputLayout.spec.isLegacyStyle.yn), Mode:\(currentLayout.mode)")

    // abort any queued screen updates
    $screenChangedTicketCounter.withLock { $0 += 1 }
    $screenParamsChangedTicketCounter.withLock { $0 += 1 }
    isAnimatingLayoutTransition = false

    player.saveState()
  }

  // MARK: - Bars Layout

  // - Top bar

  func updateTopBarHeight(to topBarHeight: CGFloat, topBarPlacement: Preference.PanelPlacement, cameraHousingOffset: CGFloat) {
    log.verbose{"Updating topBar height: \(topBarHeight), placement: \(topBarPlacement), cameraOffset: \(cameraHousingOffset)"}

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
    log.verbose{"Updating osdTopToTopBarConstraint to: \(newOffsetFromTop)"}
    osdTopToTopBarConstraint.animateToConstant(newOffsetFromTop)
  }

  // - Bottom bar

  private func updateBottomBarPlacement(placement: Preference.PanelPlacement) {
    log.verbose{"Updating bottomBar placement to: \(placement)"}
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
    log.verbose{"Updating bottomBar height to: \(bottomBarHeight), placement: \(bottomBarPlacement)"}

    switch bottomBarPlacement {
    case .insideViewport:
      viewportBtmOffsetFromTopOfBottomBarConstraint.animateToConstant(bottomBarHeight)
      viewportBtmOffsetFromBtmOfBottomBarConstraint.animateToConstant(0)
      viewportBtmOffsetFromContentViewBtmConstraint.animateToConstant(0)
    case .outsideViewport:
      viewportBtmOffsetFromTopOfBottomBarConstraint.animateToConstant(0)
      viewportBtmOffsetFromBtmOfBottomBarConstraint.animateToConstant(-bottomBarHeight)
      viewportBtmOffsetFromContentViewBtmConstraint.animateToConstant(bottomBarHeight)
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
    }
    if trailingTitlebarAccesoryViewController == nil {
      let controller = NSTitlebarAccessoryViewController()
      trailingTitlebarAccesoryViewController = controller
      controller.view = trailingTitleBarAccessoryView
      controller.layoutAttribute = .trailing
    }
    if window.styleMask.contains(.titled) && window.titlebarAccessoryViewControllers.isEmpty {
      window.addTitlebarAccessoryViewController(leadingTitlebarAccesoryViewController!)
      window.addTitlebarAccessoryViewController(trailingTitlebarAccesoryViewController!)

      trailingTitleBarAccessoryView.translatesAutoresizingMaskIntoConstraints = false
      leadingTitleBarAccessoryView.translatesAutoresizingMaskIntoConstraints = false
    }
  }

  /// Hides all the various buttons of the built-in title bar, some of which can have strange quirks.
  ///
  /// Note: there is an Apple bug (as of MacOS 13.3.1) where setting `alphaValue=0` on `miniaturizeButton` will
  /// cause `window.performMiniaturize()` to be ignored. So to hide these, use `isHidden=true` + `alphaValue=1`
  /// (except for temporary animations).
  ///
  /// Note 2: do not touch `titleVisibility` if at all possible. There seems to be no reliable way to toggle it
  /// while also guaranteeing that `documentIcon` & `titleTextField` are shown/hidden consistently.
  /// Setting `isHidden=true` on `titleTextField` and `documentIcon` do not animate and do not always work.
  /// We can use `alphaValue=0` to fade out in `fadeOutOldViews()`, but `titleVisibility` is needed to remove them.
  /// We can work around the problem by (1) inserting or removing `.titled` from the window's style mask, which
  /// effectively swaps the whole title bar in or out), and (2) in native windowed mode, *always* show the title bar when
  /// the mouse hovers over it, because even if we set the document icon's alpha to 0, the user can still click on it.
  func hideBuiltInTitleBarViews(setAlpha: Bool = false) {
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
    let image = isOnTop ? Images.onTopOn : Images.onTopOff
    onTopButton.image = image
    apply(visibility: onTopButtonVisibility, to: onTopButton)
    onTopButton.setButtonType(.momentaryPushIn)
    if let customTitleBar {
      customTitleBar.onTopButton.image = image
      apply(visibility: onTopButtonVisibility, to: customTitleBar.onTopButton)
    }

    if onTopButtonVisibility == .showFadeableTopBar {
      showFadeableViews()
    }
    player.saveState()
  }

  // MARK: - Controller content layout

  /// For `bottom` and `top` OSC only - not `floating`
  private func addControlBarViews(to containerView: NSStackView,
                                  _ oscGeo: ControlBarGeometry, _ transition: LayoutTransition) {
    containerView.addView(fragPlaybackBtnsView, in: .leading)
    containerView.addView(fragPositionSliderView, in: .leading)
    containerView.addView(fragVolumeView, in: .leading)

    containerView.setClippingResistancePriority(.defaultLow, for: .horizontal)
    containerView.setVisibilityPriority(.mustHold, for: fragPositionSliderView)
    containerView.setVisibilityPriority(.detachEarly, for: fragVolumeView)

    if let toolbarView = rebuildToolbar(transition) {
      containerView.addView(toolbarView, in: .leading)
      containerView.setVisibilityPriority(.detachEarlier, for: toolbarView)
    }
  }

  private func updateArrowButtons(oscGeo: ControlBarGeometry) {
    leftArrowButton.image = oscGeo.leftArrowImage
    rightArrowButton.image = oscGeo.rightArrowImage
    arrowBtnWidthConstraint.animateToConstant(oscGeo.arrowIconWidth)
    fragPlaybackBtnsWidthConstraint.animateToConstant(oscGeo.totalPlayControlsWidth)
    leftArrowBtnHorizOffsetConstraint.animateToConstant(oscGeo.leftArrowOffsetX)
    rightArrowBtnHorizOffsetConstraint.animateToConstant(oscGeo.rightArrowOffsetX)
  }

  func addSpeedLabelToControlBar(_ transition: LayoutTransition) {
    guard transition.outputLayout.isMusicMode || transition.outputLayout.enableOSC else { return }

    let oscGeo = transition.outputLayout.controlBarGeo
    let speedLabelFontSize = oscGeo.speedLabelFontSize
    log.verbose("Updating speed label fontSize=\(speedLabelFontSize)")
    speedLabel.font = .messageFont(ofSize: speedLabelFontSize)
  }

  /// Recreates the toolbar with the latest icons with the latest sizes & padding from prefs
  private func rebuildToolbar(_ transition: LayoutTransition) -> NSStackView? {
    let oscGeo = transition.outputLayout.controlBarGeo
    let buttonTypes = oscGeo.toolbarItems

    removeToolBar()

    guard !buttonTypes.isEmpty else {
      log.verbose("[\(transition.name)] Omitting OSC toolbar; no toolbarItems configured")
      return nil
    }

    let contentTintColor: NSColor? = transition.outputLayout.contentTintColor
    log.verbose("[\(transition.name)] Setting OSC toolbarItems to: [\(buttonTypes.map({$0.keyString}).joined(separator: ", "))]")

    var toolButtons: [OSCToolbarButton] = []
    for buttonType in buttonTypes {
      let button = OSCToolbarButton()
      button.setStyle(buttonType: buttonType, iconSize: oscGeo.toolIconSize, iconSpacing: oscGeo.toolIconSpacing)
      button.contentTintColor = contentTintColor
      button.action = #selector(self.toolBarButtonAction(_:))
      toolButtons.append(button)
    }

    let toolbarView = ClickThroughStackView()
    toolbarView.identifier = .init("OSC-ToolBarView")
    toolbarView.orientation = .horizontal
    toolbarView.distribution = .gravityAreas
    for button in toolButtons {
      toolbarView.addView(button, in: .trailing)
      toolbarView.setVisibilityPriority(.detachOnlyIfNecessary, for: button)
    }
    fragToolbarView = toolbarView

    // It's not possible to control the icon padding from inside the buttons in all cases.
    // Instead we can get the same effect with a little more work, by controlling the stack view:
    let button = toolButtons[0]
    toolbarView.spacing = 2 * button.iconSpacing
    toolbarView.edgeInsets = .init(top: button.iconSpacing, left: max(0, button.iconSpacing - 4),
                                   bottom: button.iconSpacing, right: 0)
    log.verbose("[\(transition.name)] Toolbar spacing=\(toolbarView.spacing) edgeInsets=\(toolbarView.edgeInsets)")
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

    hideSeekPreview()
  }

  private func updatePanelBlendingModes(to outputLayout: LayoutState) {
    // Full screen + "behindWindow" doesn't blend properly and looks ugly
    if outputLayout.topBarPlacement == .insideViewport || outputLayout.isFullScreen {
      topBarView.blendingMode = .withinWindow
    } else {
      topBarView.blendingMode = .behindWindow
    }

    if let bottomBarView = bottomBarView as? NSVisualEffectView {
      // Full screen + "behindWindow" doesn't blend properly and looks ugly
      if outputLayout.bottomBarPlacement == .insideViewport || outputLayout.isFullScreen {
        bottomBarView.blendingMode = .withinWindow
      } else {
        bottomBarView.blendingMode = .behindWindow
      }
    }

    updateSidebarBlendingMode(.leadingSidebar, layout: outputLayout)
    updateSidebarBlendingMode(.trailingSidebar, layout: outputLayout)
  }
}
