//
//  PWin_LayoutTxSteps.swift
//  iina
//
//  Created by Matt Svoboda on 10/4/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// This file contains tasks to run in the animation queue, which form a `LayoutTransition`.
/// Each task is a separate `CATransaction`. Some tasks are assumed to have animations (although they can also be run immediately),
/// but others are expected to always be immediate.
extension PlayerWindowController {

  /// -------------------------------------------------
  /// PRE TRANSITION
  /// Setup work. Always immediate (i.e., not animated).
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

      setWindowFloatingOnTop(false, from: transition.inputLayout, updateOnTopStatus: false)

      if transition.outputLayout.isLegacyFullScreen {
        // stylemask
        let hasTitled = window.styleMask.contains(.titled)
        log.verbose{"[\(transition.name)] Entering legacy FS\(hasTitled ? ": removing window styleMask: .titled" : "")"}
        if #available(macOS 10.16, *) {
          if hasTitled {
            window.styleMask.remove(.titled)
          }
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
      fadeableViews.applyVisibility(.hidden, to: additionalInfoView)

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
        player.setVideoTrackEnabled()
      }
    }

    if !transition.isWindowInitialLayout && transition.isTogglingLegacyStyle {
      forceDraw()
    }
  }

  /// -------------------------------------------------
  /// FADE OUT OLD VIEWS
  /// Expected to be animated.
  func fadeOutOldViews(_ transition: LayoutTransition) {
    let outputLayout = transition.outputLayout
    log.verbose{"[\(transition.name)] FadeOutOldViews"}

    // Title bar & title bar accessories:

    let needToHideTopBar = transition.isTopBarPlacementOrStyleChanging || transition.isTogglingLegacyStyle

    // Hide all title bar items if top bar placement is changing
    if needToHideTopBar || outputLayout.titleIconAndText == .hidden {
      fadeableViews.applyVisibility(.hidden, documentIconButton, titleTextField, customTitleBar?.view)
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
      fadeableViews.fadeableViewsInTopBar.remove(leadingTitleBarAccessoryView)
      trailingTitleBarAccessoryView.alphaValue = 0
      fadeableViews.fadeableViewsInTopBar.remove(trailingTitleBarAccessoryView)
    } else {
      /// We may have gotten here in response to one of these buttons' visibility being toggled in the prefs,
      /// so we need to allow for showing/hiding these individually.
      /// Setting `.isHidden = true` for these icons visibly messes up their layout.
      /// So just set alpha value for now, and hide later in `updateHiddenViewsAndConstraints()`
      if outputLayout.leadingSidebarToggleButton == .hidden {
        leadingSidebarToggleButton.alphaValue = 0
        fadeableViews.fadeableViewsInTopBar.remove(leadingSidebarToggleButton)

        // Match behavior for custom title bar's copy:
        if let customTitleBar {
          customTitleBar.leadingSidebarToggleButton.alphaValue = 0
          fadeableViews.fadeableViewsInTopBar.remove(customTitleBar.leadingSidebarToggleButton)
        }
      }
      if outputLayout.trailingSidebarToggleButton == .hidden {
        trailingSidebarToggleButton.alphaValue = 0
        fadeableViews.fadeableViewsInTopBar.remove(trailingSidebarToggleButton)

        if let customTitleBar {
          customTitleBar.trailingSidebarToggleButton.alphaValue = 0
          fadeableViews.fadeableViewsInTopBar.remove(customTitleBar.trailingSidebarToggleButton)
        }
      }

      let onTopButtonVisibility = transition.outputLayout.computeOnTopButtonVisibility(isOnTop: isOnTop)
      if onTopButtonVisibility == .hidden {
        onTopButton.alphaValue = 0
        fadeableViews.fadeableViewsInTopBar.remove(onTopButton)

        if let customTitleBar {
          customTitleBar.onTopButton.alphaValue = 0
        }
      }
    }

    if transition.inputLayout.hasFloatingOSC && !outputLayout.hasFloatingOSC {
      // Hide floating OSC
      fadeableViews.applyVisibility(outputLayout.controlBarFloating, to: controlBarFloating)
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
      fadeableViews.applyVisibility(.hidden, to: additionalInfoView)
    }

    if transition.isExitingInteractiveMode, let cropController = self.cropSettingsView {
      // Exiting interactive mode
      cropController.view.alphaValue = 0
      cropController.view.isHidden = true
      cropController.cropBoxView.isHidden = true
      cropController.cropBoxView.alphaValue = 0
    }

    if transition.isTopBarPlacementOrStyleChanging || transition.isBottomBarPlacementOrStyleChanging || transition.isTogglingVisibilityOfAnySidebar {
      hideSeekPreviewImmediately()
    }
  }

  /// -------------------------------------------------
  /// CLOSE OLD PANELS
  /// This step is not always executed (e.g., for full screen toggle).
  /// Expected to be animated.
  func closeOldPanels(_ transition: LayoutTransition) {
    let outputLayout = transition.outputLayout
    log.verbose{"[\(transition.name)] CloseOldPanels: title_H=\(outputLayout.titleBarHeight), topOSC_H=\(outputLayout.topOSCHeight)"}

    // TODO: incorporate this into middleGeometry for cleaner code
    if transition.isClosingThenReopeningOSC {
      // Shrink all the buttons to create cool animated effect
      for toolbarItem in fragToolbarView.views {
        (toolbarItem as! OSCToolbarButton).setStyle(iconSize: 0)
      }

      // Volume icon
      volumeIconHeightConstraint.animateToConstant(0)
      // Play & arrow buttons
      playBtnWidthConstraint.animateToConstant(0)
      arrowBtnWidthConstraint.animateToConstant(0)
    } else if outputLayout.hasControlBar {
      // Reduce size of icons if they are smaller. This is needed to look pleasant when panels are also shrinking.
      let oscGeo = outputLayout.controlBarGeo

      if volumeIconHeightConstraint.constant > oscGeo.volumeIconHeight {
        volumeIconHeightConstraint.animateToConstant(oscGeo.volumeIconHeight)
      }
      if volumeSliderWidthConstraint.constant > oscGeo.volumeSliderWidth {
        volumeSliderWidthConstraint.animateToConstant(oscGeo.volumeSliderWidth)
      }
      if let img = muteButton.image {
        volumeIconAspectConstraint.isActive = false
        volumeIconAspectConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: img.aspect)
        volumeIconAspectConstraint.isActive = true
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

      if leftArrowBtn_CenterXOffsetConstraint.constant > oscGeo.leftArrowCenterXOffset {
        leftArrowBtn_CenterXOffsetConstraint.animateToConstant(oscGeo.leftArrowCenterXOffset)
      }

      if rightArrowBtn_CenterXOffsetConstraint.constant > oscGeo.rightArrowCenterXOffset {
        rightArrowBtn_CenterXOffsetConstraint.animateToConstant(oscGeo.rightArrowCenterXOffset)
      }
    }

    if transition.inputLayout.titleBarHeight > outputLayout.titleBarHeight {
      titleBarHeightConstraint.animateToConstant(outputLayout.titleBarHeight)
    }

    if transition.inputLayout.topOSCHeight > outputLayout.topOSCHeight {
      topOSCHeightConstraint.animateToConstant(outputLayout.topOSCHeight)
    }

    if transition.inputLayout.controlBarGeo.playSliderHeight > outputLayout.controlBarGeo.playSliderHeight {
      playSliderHeightConstraint.animateToConstant(outputLayout.controlBarGeo.playSliderHeight)
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

      if transition.outputLayout.hasFloatingOSC && !transition.isExitingFullScreen {
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
  /// This is needed as its own transaction in case constraints need to be replaced or views need to be added or replaced in the window such that
  /// there is not an appropriate animation which should be seen.
  func updateHiddenViewsAndConstraints(_ transition: LayoutTransition) {
    guard let window = window else { return }
    let outputLayout = transition.outputLayout
    log.verbose{"[\(transition.name)] UpdateHiddenViewsAndConstraints"}

    if transition.outputLayout.spec.isLegacyStyle {
      // Set legacy style
      setWindowStyleToLegacy()

      if transition.outputLayout.isLegacyFullScreen {
        window.styleMask.insert(.borderless)
      } else {
        window.styleMask.remove(.borderless)
      }

      /// if `isTogglingLegacyStyle==true && isExitingFullScreen==true`, we are toggling out of legacy FS
      /// -> don't change `styleMask` to `.titled` here - it will look bad if screen has camera housing. Change at end of animation
    } else {
      // Not legacy style

      if !transition.isEnteringFullScreen {
        setWindowStyleToNative()
      }
    }

    // If exiting music mode, need to restore views early in this step
    if transition.isExitingMusicMode {
      log.verbose{"[\(transition.name)] Cleaning up for music mode exit"}
      miniPlayer.view.removeFromSuperview()

      // Make sure to restore video
      miniPlayer.updateVideoViewHeightConstraint(isVideoVisible: true)
      if viewportBtmOffsetFromContentViewBtmConstraint.priority != .required {
        log.verbose{"[\(transition.name)] Setting viewportBtmOffsetFromContentViewBtmConstraint priority = required"}
      }
      viewportBtmOffsetFromContentViewBtmConstraint.priority = .required

      // Make sure to reset constraints for OSD
      miniPlayer.hideControllerButtons()
      closeButtonView.isHidden = true
      if !transition.inputGeometry.isVideoVisible {
        addVideoViewToWindow()
      }
    }

    if transition.isWindowInitialLayout || transition.isBottomBarPlacementOrStyleChanging {
      rebuildBottomBarView(in: window.contentView!, style: transition.outputLayout.effectiveOSCColorScheme)
      updateBottomBarPlacement(placement: outputLayout.bottomBarPlacement)
    }

    // Title bar views

    // Allow for showing/hiding each button individually
    let onTopButtonVisibility = transition.outputLayout.computeOnTopButtonVisibility(isOnTop: isOnTop)

    if outputLayout.titleBar == .hidden || transition.isTopBarPlacementOrStyleChanging || transition.isTogglingFullScreen {
      /// Even if exiting FS, still don't want to show title & buttons until after panel open animation:
      hideBuiltInTitleBarViews(setAlpha: true)

      if let customTitleBar {
        customTitleBar.removeAndCleanUp()
        self.customTitleBar = nil
      }
    } else if let customTitleBar {
      fadeableViews.applyOnlyIfHidden(outputLayout.leadingSidebarToggleButton, to: customTitleBar.leadingSidebarToggleButton)
      fadeableViews.applyOnlyIfHidden(outputLayout.trailingSidebarToggleButton, to: customTitleBar.trailingSidebarToggleButton)
      fadeableViews.applyOnlyIfHidden(onTopButtonVisibility, to: customTitleBar.onTopButton)
    }

    fadeableViews.applyOnlyIfHidden(outputLayout.leadingSidebarToggleButton, to: leadingSidebarToggleButton)
    fadeableViews.applyOnlyIfHidden(outputLayout.trailingSidebarToggleButton, to: trailingSidebarToggleButton)
    fadeableViews.applyOnlyIfHidden(onTopButtonVisibility, to: onTopButton)

    /// These should all be either 0 height or unchanged from `transition.inputLayout`.
    /// But may need to add or remove from fadeableViews
    fadeableViews.applyVisibility(outputLayout.bottomBarView, to: bottomBarView)
    // Note: hiding top bar here when entering FS with "top outside" OSC will cause it to go black too soon.
    // But we do need it when tranitioning from music mode → FS, or top bar may never be shown
    if !transition.isEnteringFullScreen || transition.isExitingMusicMode {
      fadeableViews.applyVisibility(outputLayout.topBarView, to: topBarView)
    }

    if outputLayout.titleBar.isShowable {
      if transition.outputLayout.spec.isLegacyStyle {

        // Custom title bar
        if customTitleBar == nil {
          let titleBar = CustomTitleBarViewController()
          titleBar.windowController = self
          customTitleBar = titleBar
          titleBar.view.alphaValue = 0  // prep it to fade in later
        }

        if let customTitleBar {
          // Update superview based on placement. Cannot always add to contentView due to constraint issues
          if transition.outputLayout.topBarPlacement == .outsideViewport {
            customTitleBar.addViewTo(superview: titleBarView)
          } else {
            if let contentView = window.contentView {
              customTitleBar.addViewTo(superview: contentView)
            }
          }
          if !transition.inputLayout.titleBar.isShowable {
            customTitleBar.view.alphaValue = 0  // prep it to fade in later
          }
        }
      }
    }

    if !outputLayout.hasControlBar {
      log.verbose{"[\(transition.name)] Removing OSC views from window"}
      playSliderAndTimeLabelsView.removeFromSuperview()
      oscOneRowView.removeFromSuperview()
      oscTwoRowView.removeFromSuperview()
    }

    /// Show dividing line only for `.outsideViewport` bottom bar. Don't show in music mode as it doesn't look good
    let showBottomBarTopBorder = outputLayout.bottomBarPlacement == .outsideViewport || (outputLayout.hasBottomOSC && !outputLayout.oscHasClearBG)
    bottomBarTopBorder.isHidden = !showBottomBarTopBorder

    // Sidebars

    /// Remove views for closed sidebars *BEFORE* doing logic for opening: the same transition can be doing both
    if transition.isHidingLeadingSidebar, let tabToHide = transition.inputLayout.leadingSidebar.visibleTab {
      /// Finish closing (if closing)
      removeSidebarTabGroupView(group: tabToHide.group)
    }
    if transition.isHidingTrailingSidebar, let tabToHide = transition.inputLayout.trailingSidebar.visibleTab {
      /// Finish closing (if closing).
      /// If entering music mode, make sure to do this BEFORE moving `playlistView` down below:
      removeSidebarTabGroupView(group: tabToHide.group)
    }

    // - Leading Sidebar
    if transition.isShowingLeadingSidebar {
      // Opening sidebar from closed state
      prepareLayoutForOpening(leadingSidebar: transition.outputLayout.leadingSidebar,
                              parentLayout: transition.outputLayout, ΔWindowWidth: transition.ΔWindowWidth)
    } else if let tabToShow = transition.outputLayout.leadingSidebar.visibleTab,
              transition.isWindowInitialLayout || tabToShow != transition.inputLayout.leadingSidebar.visibleTab,
              transition.inputLayout.leadingSidebar.visibleTabGroup == transition.outputLayout.leadingSidebar.visibleTabGroup {
      // Tab group is already showing, but just need to switch tab
      switchToTabInTabGroup(tab: tabToShow)
    }

    // - Trailing Sidebar
    if transition.isShowingTrailingSidebar {
      // Opening sidebar from closed state
      prepareLayoutForOpening(trailingSidebar: transition.outputLayout.trailingSidebar,
                              parentLayout: transition.outputLayout, ΔWindowWidth: transition.ΔWindowWidth)
    } else if let tabToShow = transition.outputLayout.trailingSidebar.visibleTab,
              transition.isWindowInitialLayout || tabToShow != transition.inputLayout.trailingSidebar.visibleTab,
              transition.inputLayout.trailingSidebar.visibleTabGroup == transition.outputLayout.trailingSidebar.visibleTabGroup {
      // Tab group is already showing, but just need to switch tab
      switchToTabInTabGroup(tab: tabToShow)
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

    // Music mode

    // If initial layout, bottomBar has been rebuilt, so we need to repopulate it
    if transition.isWindowInitialLayout || transition.isTogglingMusicMode {
      miniPlayer.loadIfNeeded()
      showOrHidePipOverlayView()

      if transition.outputLayout.isMusicMode {
        log.verbose{"[\(transition.name)] Entering music mode: adding views to bottomBarView"}
        bottomBarView.addSubview(miniPlayer.view, positioned: .below, relativeTo: bottomBarTopBorder)
        miniPlayer.view.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)

        let bottomConstraint = miniPlayer.view.superview!.bottomAnchor.constraint(equalTo: miniPlayer.view.bottomAnchor, constant: 0)
        bottomConstraint.priority = .defaultHigh
        bottomConstraint.isActive = true

        // move playist view
        let playlistView = playlistView.view
        miniPlayer.playlistWrapperView.addSubview(playlistView)
        playlistView.addAllConstraintsToFillSuperview()

        playSlider.customCell.knobHeight = Constants.Distance.Slider.musicModeKnobHeight

        // move playback buttons
        if !miniPlayer.playbackBtnsWrapperView.subviews.contains(fragPlaybackBtnsView) {
          miniPlayer.playbackBtnsWrapperView.addSubview(fragPlaybackBtnsView)
          miniPlayer.playbackBtnsWrapperView.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor).isActive = true
          miniPlayer.playbackBtnsWrapperView.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor).isActive = true
        }

        let shouldDisableConstraint = musicModeGeo.isPlaylistVisible  // musicModeGeo==transition.outputGeo
        /// If needing to deactivate this constraint, do it before the toggle animation, so that window doesn't jump.
        /// (See note in `applyMusicModeGeo`)
        if shouldDisableConstraint {
          log.verbose{"Setting viewportBtmOffsetFromContentViewBtmConstraint priority = 1"}
          viewportBtmOffsetFromContentViewBtmConstraint.priority = .minimum
        }

        if !miniPlayer.volumeSliderView.subviews.contains(fragVolumeView) {
          miniPlayer.volumeSliderView.addSubview(fragVolumeView)
          fragVolumeView.centerYAnchor.constraint(equalTo: miniPlayer.volumeSliderView.centerYAnchor).isActive = true
          volumeSlider.leadingAnchor.constraint(equalTo: miniPlayer.volumeSliderView.leadingAnchor, constant: 40).isActive = true
          miniPlayer.volumeSliderView.trailingAnchor.constraint(equalTo: volumeSlider.trailingAnchor, constant: 40).isActive = true
          muteButton.target = self
          muteButton.action = #selector(muteButtonAction(_:))
        }

        seekPreview.timeLabel.font = NSFont.systemFont(ofSize: 9)

        // Update music mode UI
        updateTitle()
      }
    }

    if transition.outputLayout.isMusicMode {
      // move playback position slider & time labels
      let wasThere = miniPlayer.positionSliderWrapperView.subviews.contains(playSliderAndTimeLabelsView)
      miniPlayer.positionSliderWrapperView.addSubview(playSliderAndTimeLabelsView)
      addSubviewsToPlaySliderAndTimeLabelsView(transition.outputLayout.controlBarGeo)
      if !wasThere {
        playSliderAndTimeLabelsView.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: 0, trailing: 0)
        playSliderAndTimeLabelsView.isHidden = false
      }
    }

    // Need to call this for initial layout also:
    updateMusicModeButtonsVisibility(using: musicModeGeo)

    // OSC

    // [Re-]add OSC:
    if outputLayout.enableOSC {
      let oscGeo = outputLayout.controlBarGeo
      log.verbose{"[\(transition.name)] Setting up OSC: pos=\(outputLayout.oscPosition) musicMode=\(outputLayout.isMusicMode.yn) playIconSize=\(oscGeo.playIconSize) playIconSpacing=\(oscGeo.playIconSpacing)"}

      rebuildOSCToolbar(transition)

      switch outputLayout.oscPosition {
      case .top:
        currentControlBar = controlBarTop


        let oscContentView: NSView
        if oscGeo.isTwoRowBarOSC {
          oscContentView = oscTwoRowView
          log.verbose{"[\(transition.name)] Adding subviews to oscTwoRowView for top bar, topBarHeight=\(outputLayout.topBarHeight)"}
          oscTwoRowView.updateSubviews(from: self, oscGeo)
        } else {
          oscContentView = oscOneRowView
          log.verbose{"[\(transition.name)] Adding subviews to oscOneRowView for top bar"}
          oscOneRowView.updateSubviews(from: self, oscGeo)
        }

        if !controlBarTop.subviews.contains(oscContentView) {
          controlBarTop.addSubview(oscContentView, positioned: .below, relativeTo: topBarBottomBorder)
          // Match leading/trailing spacing of title bar icons above
          oscContentView.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: Constants.Distance.titleBarIconHSpacing,
                                                       trailing: Constants.Distance.titleBarIconHSpacing)
        }

      case .bottom:
        currentControlBar = bottomBarView

        let oscContentView: NSView
        if oscGeo.isTwoRowBarOSC {
          oscContentView = oscTwoRowView
          log.verbose{"[\(transition.name)] Adding subviews to oscTwoRowView for bottom bar, bottomBarHeight=\(outputLayout.bottomBarHeight)"}
          oscTwoRowView.updateSubviews(from: self, oscGeo)
        } else {
          oscContentView = oscOneRowView
          log.verbose{"[\(transition.name)] Adding subviews to oscOneRowView for bottom bar"}
          oscOneRowView.updateSubviews(from: self, oscGeo)
        }

        if !bottomBarView.subviews.contains(oscContentView) {
          bottomBarView.addSubview(oscContentView, positioned: .below, relativeTo: bottomBarTopBorder)
          // Match leading/trailing spacing of title bar icons above
          oscContentView.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: Constants.Distance.titleBarIconHSpacing,
                                                       trailing: Constants.Distance.titleBarIconHSpacing)
        }

      case .floating:
        currentControlBar = controlBarFloating
        if !oscFloatingUpperView.views.contains(fragToolbarView) {
          oscFloatingUpperView.addView(fragToolbarView, in: .trailing)
          oscFloatingUpperView.setVisibilityPriority(.detachEarlier, for: fragToolbarView)
          fragToolbarView.isHidden = false
        }
      }

      seekPreview.updateTimeLabelFontSize(to: oscGeo.seekPreviewTimeLabelFontSize)

    } else if outputLayout.isMusicMode {

      // Music mode always has a control bar
      currentControlBar = miniPlayer.musicModeControlBarView

    } else {  // No OSC & not music mode
      currentControlBar = nil
    }

    if outputLayout.hasControlBar {
      // Has OSC, or music mode
      let oscGeo = outputLayout.controlBarGeo
      playSliderHeightConstraint.animateToConstant(oscGeo.playSliderHeight)
      updateArrowButtons(oscGeo: oscGeo)
      rightTimeLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

      let hideArrowBtns = oscGeo.arrowIconWidth == 0
      leftArrowButton.isHidden = hideArrowBtns
      rightArrowButton.isHidden = hideArrowBtns

      let timeLabelFont: NSFont = oscGeo.timeLabelFont
      leftTimeLabel.font = timeLabelFont
      rightTimeLabel.font = timeLabelFont
      oscTwoRowView.timeSlashLabel.font = timeLabelFont

      // Not floating OSC!
      if !transition.outputLayout.hasFloatingOSC {
        updateSpeedLabelFont(for: transition)
      }

      let sliderKnobWidth = oscGeo.sliderKnobWidth
      let sliderKnobHeight = oscGeo.sliderKnobHeight
      playSlider.customCell.knobWidth = sliderKnobWidth
      playSlider.customCell.knobHeight = sliderKnobHeight
      playSlider.abLoopA.updateKnobImage(to: .loopKnob)
      playSlider.abLoopB.updateKnobImage(to: .loopKnob)
      playSlider.needsDisplay = true

      let volumeSliderCell = volumeSlider.cell as! VolumeSliderCell
      volumeSliderCell.knobWidth = sliderKnobWidth
      volumeSliderCell.knobHeight = sliderKnobHeight
      volumeSlider.needsDisplay = true

      if transition.isWindowInitialLayout || transition.isOSCStyleChanging || transition.inputLayout.controlBarGeo.barHeight != transition.outputLayout.controlBarGeo.barHeight {
        let hasClearBG = transition.outputLayout.oscHasClearBG
        log.verbose{"[\(transition.name)] Updating OSC colors: hasClearBG=\(hasClearBG.yn)"}

        playButton.setOSCColors(hasClearBG: hasClearBG)
        leftArrowButton.setOSCColors(hasClearBG: hasClearBG)
        rightArrowButton.setOSCColors(hasClearBG: hasClearBG)
        muteButton.setOSCColors(hasClearBG: hasClearBG)

        let textAlpha: CGFloat
        let timeLabelTextColor: NSColor?
        if transition.outputLayout.oscHasClearBG {
          textAlpha = 0.8
          timeLabelTextColor = .white

          let blurRadiusConstant = Constants.Distance.oscClearBG_TextShadowBlurRadius_Constant
          let blurRadiusMultiplier = Constants.Distance.oscClearBG_TextShadowBlurRadius_Multiplier
          leftTimeLabel.addShadow(blurRadiusMultiplier: blurRadiusMultiplier, blurRadiusConstant: blurRadiusConstant)
          rightTimeLabel.addShadow(blurRadiusMultiplier: blurRadiusMultiplier, blurRadiusConstant: blurRadiusConstant)
          oscTwoRowView.timeSlashLabel.addShadow(blurRadiusMultiplier: blurRadiusMultiplier, blurRadiusConstant: blurRadiusConstant)

          knobFactory.mainKnobColor = NSColor.controlForClearBG
        } else {
          // Default alpha for text labels is 0.5. They don't change their text color.
          textAlpha = 0.5
          timeLabelTextColor = nil

          leftTimeLabel.shadow = nil
          rightTimeLabel.shadow = nil
          oscTwoRowView.timeSlashLabel.shadow = nil

          knobFactory.mainKnobColor = NSColor.mainSliderKnob
        }

        leftTimeLabel.textColor = timeLabelTextColor
        rightTimeLabel.textColor = timeLabelTextColor
        oscTwoRowView.timeSlashLabel.textColor = timeLabelTextColor
        leftTimeLabel.alphaValue = textAlpha
        rightTimeLabel.alphaValue = textAlpha
        oscTwoRowView.timeSlashLabel.alphaValue = textAlpha

        // Invalidate all cached knob images so they are rebuilt with new style
        knobFactory.invalidateCachedKnobs()
      }
    }

    // Interactive mode

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
        bottomBarView.addSubview(cropController.view, positioned: .below, relativeTo: bottomBarTopBorder)
        cropController.view.addAllConstraintsToFillSuperview()
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
              log.verbose{"[\(transition.name)] Setting crop box selection from prevFilter: \(selectedRect)"}
            } else {
              selectedRect = NSRect(origin: .zero, size: videoSizeRaw)
              log.verbose{"[\(transition.name)] Setting crop box selection to default whole videoSize: \(selectedRect)"}
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

    updateDepthOrderOfBars(topBar: outputLayout.topBarPlacement, bottomBar: outputLayout.bottomBarPlacement,
                           leadingSidebar: outputLayout.leadingSidebarPlacement, trailingSidebar: outputLayout.trailingSidebarPlacement)

    prepareDepthOrderOfOutsideSidebarsForToggle(transition)

    // So that panels toggling between "inside" and "outside" don't change until they need to (different strategy than fullscreen)
    if !transition.isTogglingFullScreen {
      updatePanelBlendingModes(to: outputLayout)
    }

    // Other misc views

    updateAdditionalInfo()
    updateVolumeUI()
    playSlider.needsDisplay = true

    if !transition.isWindowInitialLayout && transition.isTogglingLegacyStyle {
      forceDraw()
    }
  }  /// end `updateHiddenViewsAndConstraints`

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
      volumeSliderWidthConstraint.animateToConstant(oscGeo.volumeSliderWidth)
      if let img = muteButton.image {
        volumeIconAspectConstraint.isActive = false
        volumeIconAspectConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: img.aspect)
        volumeIconAspectConstraint.isActive = true
      }

      arrowBtnWidthConstraint.animateToConstant(oscGeo.arrowIconWidth)
      playBtnWidthConstraint.animateToConstant(oscGeo.playIconSize)
      fragPlaybackBtnsWidthConstraint.animateToConstant(oscGeo.totalPlayControlsWidth)
      leftArrowBtn_CenterXOffsetConstraint.animateToConstant(oscGeo.leftArrowCenterXOffset)
      rightArrowBtn_CenterXOffsetConstraint.animateToConstant(oscGeo.rightArrowCenterXOffset)

      // Animate toolbar icons to full size now
      for toolbarItem in fragToolbarView.views {
        (toolbarItem as! OSCToolbarButton).setStyle(using: transition.outputLayout)
      }
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

    // Update sidebar downshift & tab heights
    updateSidebarVerticalConstraints(tabHeight: outputLayout.sidebarTabHeight, downshift: outputLayout.sidebarDownshift)

    if outputLayout.hasFloatingOSC {

      // Wait until now to set up floating OSC views. Doing this in prev or next task while animating results in visibility bugs

      if transition.isWindowInitialLayout || !transition.inputLayout.hasFloatingOSC {
        oscFloatingPlayButtonsContainerView.addView(fragPlaybackBtnsView, in: .center)
        // There sweems to be a race condition when adding to these StackViews.
        // Sometimes it still contains the old view, and then trying to add again will cause a crash.
        // Must check if it already contains the view before adding.
        if !oscFloatingUpperView.views(in: .leading).contains(fragVolumeView) {
          oscFloatingUpperView.addView(fragVolumeView, in: .leading)
          fragVolumeView.isHidden = false
        }
        oscFloatingUpperView.setVisibilityPriority(.detachEarly, for: fragVolumeView)

        oscFloatingUpperView.setClippingResistancePriority(.defaultLow, for: .horizontal)

        addSubviewsToPlaySliderAndTimeLabelsView(transition.outputLayout.controlBarGeo)
        oscFloatingLowerView.addSubview(playSliderAndTimeLabelsView)
        playSliderAndTimeLabelsView.isHidden = false
        playSliderAndTimeLabelsView.addAllConstraintsToFillSuperview()

        controlBarFloating.addMarginConstraints()
      }
      updateSpeedLabelFont(for: transition)

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
      } else if !player.isRestoring, player.info.isFileLoaded, !player.info.isVideoTrackSelected {
        // if restoring, there will be a brief delay before getting player info, which is ok
        Utility.showAlert("no_video_track")
      }
    } else if transition.isExitingInteractiveMode && transition.outputLayout.isFullScreen {
      videoView.apply(transition.outputGeometry)
    }

    // Do this here so that BarFactory regenerates close enough to mid-animation (so bar thickness changes pleasantly)
    if let window, let screen = window.screen {
      applyThemeMaterial(using: transition.outputLayout.spec, window, screen)
    } else {
      // In some rare cases, window might be off screen its frame size is zero (the latter can happen when exiting music mode with no
      // playlist & no video), in which case window.screen will be nil. Just log & continue. In principle, applyThemeMaterial will still
      // be called via windowDidChangeScreen.
      log.verbose{"[\(transition.name)] Skipped applyThemeMaterial due to missing window or screen"}
    }

    if !transition.isWindowInitialLayout && transition.isTogglingLegacyStyle {
      forceDraw()
    }
  }

  /// -------------------------------------------------
  /// FADE IN NEW VIEWS
  /// Expected to be animated.
  func fadeInNewViews(_ transition: LayoutTransition) {
    guard let window = window else { return }
    let outputLayout = transition.outputLayout
    log.verbose("[\(transition.name)] FadeInNewViews")

    fadeableViews.applyOnlyIfShowable(outputLayout.controlBarFloating, to: controlBarFloating)

    if outputLayout.isFullScreen {
      if !outputLayout.isInteractiveMode && Preference.bool(for: .displayTimeAndBatteryInFullScreen) {
        fadeableViews.applyVisibility(.showFadeableNonTopBar, to: additionalInfoView)
      }
    }

    // If exiting FS, the openNewPanels and fadInNewViews steps are combined. Wait till later
    if outputLayout.titleBar.isShowable {
      if !transition.isExitingFullScreen {
        if outputLayout.spec.isLegacyStyle {  // Legacy windowed mode
          if let customTitleBar {
            customTitleBar.view.alphaValue = 1
          }
        } else {  // Native windowed mode
          showBuiltInTitleBarViews()
          window.titleVisibility = .visible

          /// Title bar accessories get removed by fullscreen or if window `styleMask` did not include `.titled`.
          /// Add them back:
          addTitleBarAccessoryViews()
        }
      }
      // covers both native & custom variants
      updateTitleBarUI(from: outputLayout)
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
  /// Cleanup & variable state updates. Always instantaneous (not animated).
  func doPostTransitionWork(_ transition: LayoutTransition) {
    log.verbose{"[\(transition.name)] DoPostTransitionWork"}
    // Update blending mode:
    updatePanelBlendingModes(to: transition.outputLayout)

    fadeableViews.animationState = .shown
    fadeableViews.topBarAnimationState = .shown
    fadeableViews.hideTimer.restart()

    guard let window else { return }

    if transition.isEnteringFullScreen {
      // Entered FS

      hideCursorTimer.restart()

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
        if !player.isRestoring && Preference.bool(for: .playWhenEnteringFullScreen) {
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
        window.styleMask.remove(.borderless)
        if let customTitleBar {
          customTitleBar.view.alphaValue = 1
        }
      } else {  // native windowed
        /// Same logic as in `fadeInNewViews()`
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
      setWindowFloatingOnTop(isOnTop, from: transition.outputLayout, updateOnTopStatus: false)

      if Preference.bool(for: .pauseWhenLeavingFullScreen) && player.info.isPlaying {
        player.pause()
      }

      player.events.emit(.windowFullscreenChanged, data: false)
    }

    if transition.isTogglingFullScreen || transition.isTogglingMusicMode {
      if transition.outputLayout.isMusicMode && !musicModeGeo.isVideoVisible && pip.status == .notInPIP {
        player.setVideoTrackDisabled()
      } else {
        player.updateMPVWindowScale(using: transition.outputGeometry)
      }
    }

    if transition.isTogglingMusicMode && Preference.bool(for: .playlistShowMetadataInMusicMode) {
      /// Need to toggle music metadata due to music mode switch.
      /// Do this even if playlist is not visible now, because it will not be be reloaded when toggled.
      playlistView.reloadPlaylistRows()
      playlistView.scrollPlaylistToCurrentItem()
    }

    refreshHidesOnDeactivateStatus()
    updateIsMoveableByWindowBackground()

    if !transition.isWindowInitialLayout {
      window.layoutIfNeeded()
      forceDraw()

      // Do not run sanity checks for initial layout, because in that case all task funcs combined into a single
      // animation task, which means that frames will not be updated yet & can't be measured correctly
      if Logger.isEnabled(.error) && pip.status == .notInPIP && player.state.isNotYet(.stopping) && player.info.isVideoTrackSelected {
        let vidSizeA = videoView.frame.size
        let vidSizeE = transition.outputGeometry.videoSize
        let viewportSizeA = viewportView.frame.size
        let viewportSizeE = transition.outputGeometry.viewportSize
        let winSizeA = window.frame.size
        let winSizeE = transition.outputGeometry.windowFrame.size

        let enableVidCheck = !player.info.currentMediaAudioStatus.isAudio
        let isWrongVidSize = enableVidCheck && (vidSizeE.area > 0 && vidSizeA.area > 0) &&
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
                       "  VideoSize: Expect=\(enableVidCheck ? vidSizeE.description : "NA") Actual=\(vidSizeA)  \(isWrongVidSize ? wrong : "")",
                       "  Viewport:  Expect=\(viewportSizeE) Actual=\(viewportSizeA)",
                       "  WinFrame:  Expect=\(transition.outputGeometry.windowFrame) Actual=\(window.frame)  \(isWrongWinSize ? wrong : "")",
                       "  VidMargins: \(transition.outputGeometry.viewportMargins)",  // Size should == viewport - video. (Unless video is wrong)
                       ]
          log.error(lines.joined(separator: "\n"))
        }
      }

    }

    if transition.outputLayout.isWindowed {
      player.updateMPVWindowScale(using: windowedModeGeo)
    }

    log.verbose("[\(transition.name)] Done with transition. IsFullScreen:\(transition.outputLayout.isFullScreen.yn), IsLegacy:\(transition.outputLayout.spec.isLegacyStyle.yn), Mode:\(currentLayout.mode)")

    // abort any queued screen updates
    screenChangedDebouncer.invalidate()
    screenParamsChangedDebouncer.invalidate()
    isAnimatingLayoutTransition = false

    player.saveState()
  }

  // MARK: - Bars Layout

  // - Top bar

  func updateTopBarHeight(to topBarHeight: CGFloat, topBarPlacement: Preference.PanelPlacement, cameraHousingOffset: CGFloat) {
    log.trace{"Updating topBar height to: \(topBarHeight) for placement=\(topBarPlacement) cameraOffset=\(cameraHousingOffset)"}

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
    log.trace{"Updating osdTopToTopBarConstraint to: \(newOffsetFromTop)"}
    osdTopToTopBarConstraint.animateToConstant(newOffsetFromTop)
  }

  // - Bottom bar

  private func updateBottomBarPlacement(placement: Preference.PanelPlacement) {
    log.trace{"Updating bottomBar placement to: \(placement)"}
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
    log.trace{"Updating bottomBar height to \(bottomBarHeight) for placement=\(bottomBarPlacement)"}

    switch bottomBarPlacement {
    case .insideViewport:
      viewportBtmOffsetFromTopOfBottomBarConstraint.animateToConstant(bottomBarHeight)
      viewportBtmOffsetFromBtmOfBottomBarConstraint.animateToConstant(0)
      viewportBtmOffsetFromContentViewBtmConstraint.animateToConstant(0)
    case .outsideViewport:
      viewportBtmOffsetFromTopOfBottomBarConstraint.animateToConstant(0)
      viewportBtmOffsetFromBtmOfBottomBarConstraint.animateToConstant(bottomBarHeight)
      viewportBtmOffsetFromContentViewBtmConstraint.animateToConstant(bottomBarHeight)
    }
  }

  // MARK: - Title bar items

  func updateTitleBarUI(from layoutState: LayoutState) {
    guard let window else { return }
    updateColorsForKeyWindowStatus(isKey: window.isKeyWindow)
    let enableGlow = Preference.bool(for: .titleBarBtnsGlow)
    // Leading sidebar toggle button
    for button in [leadingSidebarToggleButton, customTitleBar?.leadingSidebarToggleButton].compactMap({$0}) {
      if layoutState.leadingSidebarToggleButton.isShowable {
        button.setGlowForTitleBar(enabled: enableGlow && layoutState.leadingSidebar.isVisible)
      }
      fadeableViews.applyVisibility(layoutState.leadingSidebarToggleButton, button)
    }
    // Trailing sidebar toggle button
    for button in [trailingSidebarToggleButton, customTitleBar?.trailingSidebarToggleButton].compactMap({$0}) {
      if layoutState.trailingSidebarToggleButton.isShowable {
        button.setGlowForTitleBar(enabled: enableGlow && layoutState.trailingSidebar.isVisible)
      }
      fadeableViews.applyVisibility(layoutState.trailingSidebarToggleButton, button)
    }

    updateOnTopButton(from: layoutState, showIfFadeable: false)

    // Title bar accessories (to cover native windowed mode):
    fadeableViews.applyVisibility(layoutState.titlebarAccessoryViewControllers, to: leadingTitleBarAccessoryView)
    fadeableViews.applyVisibility(layoutState.titlebarAccessoryViewControllers, to: trailingTitleBarAccessoryView)
  }

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
    if window.styleMask.contains(.titled) {
      if !window.titlebarAccessoryViewControllers.contains(leadingTitlebarAccesoryViewController!) {
        window.addTitlebarAccessoryViewController(leadingTitlebarAccesoryViewController!)
        leadingTitleBarAccessoryView.translatesAutoresizingMaskIntoConstraints = false
        leadingTitleBarAccessoryView.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: 0)
      }

      if !window.titlebarAccessoryViewControllers.contains(trailingTitlebarAccesoryViewController!) {
        window.addTitlebarAccessoryViewController(trailingTitlebarAccesoryViewController!)
        trailingTitleBarAccessoryView.translatesAutoresizingMaskIntoConstraints = false
        trailingTitleBarAccessoryView.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: 0)
      }
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

  func updateOnTopButton(from layout: LayoutState, showIfFadeable: Bool = false) {
    let onTopButtonVisibility = layout.computeOnTopButtonVisibility(isOnTop: isOnTop)
    let image = isOnTop ? Images.onTopOn : Images.onTopOff
    for button in [onTopButton, customTitleBar?.onTopButton].compactMap({$0}) {
      button.replaceSymbolImage(with: image, effect: nil)
      button.setGlowForTitleBar(enabled: Preference.bool(for: .titleBarBtnsGlow) && isOnTop)
      fadeableViews.applyVisibility(onTopButtonVisibility, to: button)
    }

    if showIfFadeable, onTopButtonVisibility == .showFadeableTopBar {
      showFadeableViews()
    }
  }

  // MARK: - Controller content layout

  private func updateArrowButtons(oscGeo: ControlBarGeometry) {
    leftArrowButton.replaceSymbolImage(with: oscGeo.leftArrowImage, effect: .offUp)
    rightArrowButton.replaceSymbolImage(with: oscGeo.rightArrowImage, effect: .offUp)
    arrowBtnWidthConstraint.animateToConstant(oscGeo.arrowIconWidth)
    fragPlaybackBtnsWidthConstraint.animateToConstant(oscGeo.totalPlayControlsWidth)
    leftArrowBtn_CenterXOffsetConstraint.animateToConstant(oscGeo.leftArrowCenterXOffset)
    rightArrowBtn_CenterXOffsetConstraint.animateToConstant(oscGeo.rightArrowCenterXOffset)
  }

  func updateSpeedLabelFont(for transition: LayoutTransition) {
    let oscGeo = transition.outputLayout.controlBarGeo
    let speedLabelFontSize = oscGeo.speedLabelFontSize
    log.trace{"Updating speed label fontSize=\(speedLabelFontSize)"}
    speedLabel.font = .messageFont(ofSize: speedLabelFontSize)
  }

  /// Recreates the toolbar with the latest icons with the latest sizes & padding from prefs
  private func rebuildOSCToolbar(_ transition: LayoutTransition) {
    let oldGeo = transition.inputLayout.controlBarGeo
    let newGeo = transition.outputLayout.controlBarGeo
    let newButtonTypes = newGeo.toolbarItems

    let hasSizeChange = oldGeo.toolIconSize != newGeo.toolIconSize || oldGeo.toolIconSpacing != newGeo.toolIconSpacing
    let hasColorChange = transition.inputLayout.oscHasClearBG != transition.outputLayout.oscHasClearBG
    var needsButtonsUpdate = hasSizeChange || hasColorChange

    let isOpeningOSC = transition.isOpeningOSC
    if isOpeningOSC || !oldGeo.toolbarItemsAreSame(as: newGeo) {
      fragToolbarView.views.forEach { fragToolbarView.removeView($0) }

      if newButtonTypes.count > 0 {
        let oscGeo = transition.outputLayout.controlBarGeo
        let iconSize: CGFloat = isOpeningOSC && !transition.isWindowInitialLayout ? 0 : oscGeo.toolIconSize
        let iconSpacing = oscGeo.toolIconSpacing
        log.verbose{"[\(transition.name)] Updating OSC toolbar: iconSize=\(iconSize) iconSpacing=\(iconSpacing) barHeight=\(oscGeo.barHeight) fullIconHeight=\(oscGeo.fullIconHeight) btns=[\(newButtonTypes.map({$0.keyString}).joined(separator: ","))]"}
        for buttonType in newButtonTypes {
          let button = OSCToolbarButton()
          button.setStyle(buttonType: buttonType, iconSize: iconSize, iconSpacing: iconSpacing)
          button.setOSCColors(hasClearBG: transition.outputLayout.oscHasClearBG)
          button.action = #selector(self.toolBarButtonAction(_:))
          fragToolbarView.addView(button, in: .trailing)
          fragToolbarView.setVisibilityPriority(.detachOnlyIfNecessary, for: button)
        }
        needsButtonsUpdate = false
      }
    }

    if needsButtonsUpdate {
      log.verbose{
        let oscGeo = transition.outputLayout.controlBarGeo
        return "[\(transition.name)] Updating OSC toolbar: iconSize=\(oscGeo.toolIconSize) iconSpacing=\(oscGeo.toolIconSpacing) barHeight=\(oscGeo.barHeight) fullIconHeight=\(oscGeo.fullIconHeight) btns=[\(newButtonTypes.map({$0.keyString}).joined(separator: ","))]"
      }
      for btn in fragToolbarView.views.compactMap({ $0 as? OSCToolbarButton }) {
        btn.setStyle(using: transition.outputLayout)
        btn.setOSCColors(hasClearBG: transition.outputLayout.oscHasClearBG)
      }
    }

    // It's not possible to control the icon padding from inside the buttons in all cases.
    // Instead we can get the same effect with a little more work, by controlling the stack view:
    let iconSpacing = newGeo.toolIconSpacing
    fragToolbarView.spacing = 2 * iconSpacing
    let sideInset = (iconSpacing * 0.5).rounded()
    fragToolbarView.edgeInsets = .init(top: iconSpacing, left: sideInset,
                                       bottom: iconSpacing, right: sideInset)
    log.verbose{"[\(transition.name)] Toolbar spacing=\(fragToolbarView.spacing) edgeInsets=\(fragToolbarView.edgeInsets)"}
  }

  // MARK: - Misc support functions

  /// Call this when `origVideoSize` is known.
  /// `videoRect` should be `videoView.frame`
  func addOrReplaceCropBoxSelection(rawVideoSize: NSSize, videoViewSize: NSSize) {
    guard let cropController = self.cropSettingsView else { return }

    if !videoView.subviews.contains(cropController.cropBoxView) {
      videoView.addSubview(cropController.cropBoxView)
      cropController.cropBoxView.addAllConstraintsToFillSuperview()
    }

    cropController.cropBoxView.actualSize = rawVideoSize
    cropController.cropBoxView.resized(with: NSRect(origin: .zero, size: videoViewSize))
  }

  /// Either legacy FS or windowed
  private func setWindowStyleToLegacy() {
    guard let window = window else { return }
    if window.styleMask.contains(.titled) {
      log.verbose("Removing window styleMask.titled")
      window.styleMask.remove(.titled)
    }
    window.styleMask.insert(.closable)
    window.styleMask.insert(.miniaturizable)
  }

  /// "Native" == `.titled` style mask
  private func setWindowStyleToNative() {
    guard let window = window else { return }

    if !window.styleMask.contains(.titled) {
      log.verbose("Inserting window styleMask.titled")
      window.styleMask.remove(.borderless)
      window.styleMask.insert(.titled)
    }

    if let customTitleBar {
      customTitleBar.removeAndCleanUp()
      self.customTitleBar = nil
    }
  }

  /// Remove the tab group view associated with `group` from its parent view (also removes constraints)
  private func removeSidebarTabGroupView(group: Sidebar.TabGroup) {
    log.verbose{"Removing sidebar tab group view for \(group)"}
    let viewController: NSViewController
    switch group {
    case .playlist:
      viewController = playlistView
    case .settings:
      viewController = quickSettingView
    case .plugins:
      viewController = pluginView
    }
    viewController.view.removeFromSuperview()
  }

  private func resetViewsForModeTransition() {
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // needless processing. It must be running while transitioning to/from full screen mode.
    videoView.displayActive()

    hideSeekPreviewImmediately()
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
