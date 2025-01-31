//
//  SeekPreview.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-21.
//  Copyright © 2024 lhc. All rights reserved.
//

extension PlayerWindowController {

  /// Encapsulates state & objects needed for seek preview UI.
  /// This class is not a view in itself.
  class SeekPreview {
    /// Min distance between `thumbnailPeekView` & sides of `viewportView`.
    /// For the side which includes `timeLabel`, the margin is split 1/2 above & 1/2 below the label,
    /// and does not include the offset added by the label's height itself.
    static let minThumbMargins = MarginQuad(top: Constants.Distance.Thumbnail.extraOffsetY,
                                            trailing: Constants.Distance.Thumbnail.extraOffsetX,
                                            bottom: Constants.Distance.Thumbnail.extraOffsetY,
                                            leading: Constants.Distance.Thumbnail.extraOffsetX)

    let timeLabel = NSTextField()
    let thumbnailPeekView = ThumbnailPeekView()

    var timeLabelHorizontalCenterConstraint: NSLayoutConstraint!
    var timeLabelVerticalSpaceConstraint: NSLayoutConstraint!

    var animationState: UIAnimationState = .shown {
      didSet {
        if animationState == .willHide || animationState == .hidden {
          currentPreviewTimeSec = nil
        }
        // Trigger redraw of PlaySlider, in case knob needs to be shown or hidden
        thumbnailPeekView.associatedPlayer?.windowController.playSlider.needsDisplay = true
      }
    }
    var currentPreviewTimeSec: Double? = nil  // only non-nil when shown
    /// For auto hiding seek time & thumbnail after a timeout.
    /// Calls `PlayerWindowController.seekPreviewTimeout` on timeout.
    let hideTimer = TimeoutTimer(timeout: Constants.TimeInterval.seekPreviewHideTimeout)

    init() {
      timeLabel.identifier = .init("SeekTimeLabel")
      timeLabel.translatesAutoresizingMaskIntoConstraints = false
      timeLabel.isBordered = false
      timeLabel.drawsBackground = false
      timeLabel.isBezeled = false
      timeLabel.isEditable = false
      timeLabel.isSelectable = false
      timeLabel.isEnabled = true
      timeLabel.refusesFirstResponder = true
      timeLabel.alignment = .center
      timeLabel.textColor = .white  // always

      timeLabel.setContentHuggingPriority(.required, for: .horizontal)
      timeLabel.setContentHuggingPriority(.required, for: .vertical)

      thumbnailPeekView.identifier = .init("ThumbnailPeekView")
      thumbnailPeekView.isHidden = true

      timeLabel.isHidden = true
      timeLabel.alphaValue = 0.0
      addShadow()
    }

    func restartHideTimer() {
      guard animationState == .shown else { return }
      hideTimer.restart()
    }

    func addShadow() {
      timeLabel.addShadow(blurRadiusConstant: Constants.Distance.seekPreviewTimeLabel_ShadowRadiusConstant)
    }

    /// This is expected to be called at first layout
    func updateTimeLabelFontSize(to newSize: CGFloat) {
      guard timeLabel.font?.pointSize != newSize else { return }

      timeLabel.font = NSFont.boldSystemFont(ofSize: newSize)
      addShadow()
    }

    /// `posInWindowX` is where center of timeLabel, thumbnailPeekView should be
    // TODO: Investigate using CoreAnimation!
    // https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html
    func showPreview(withThumbnail showThumbnail: Bool, forTime previewTimeSec: Double,
                     posInWindowX: CGFloat, _ player: PlayerCore, currentControlBar: NSView,
                     _ currentGeo: PWinGeometry) {

      let log = player.log
      let margins = SeekPreview.minThumbMargins
      let thumbStore = player.info.currentPlayback?.thumbnails
      let ffThumbnail = thumbStore?.getThumbnail(forSecond: previewTimeSec)
      let viewportSize = currentGeo.viewportSize
      let currentLayout = player.windowController.currentLayout

      var showThumbnail = showThumbnail
      var thumbWidth: Double
      var thumbHeight: Double
      if showThumbnail, let ffThumbnail {
        let rotatedImage = ffThumbnail.image
        thumbWidth = Double(rotatedImage.width)
        thumbHeight = Double(rotatedImage.height)
        if thumbWidth <= 0 || thumbHeight <= 0 {
          showThumbnail = false
        }
      } else {
        showThumbnail = false
        thumbWidth = 0
        thumbHeight = 0
      }

      let stringRepresentation = VideoTime.string(from: previewTimeSec)
      if timeLabel.stringValue != stringRepresentation {
        timeLabel.stringValue = stringRepresentation
        timeLabel.sizeToFit()
      }
      currentPreviewTimeSec = previewTimeSec

      // Get size *after* stringValue is set:
      let timeLabelSize = timeLabel.attributedStringValue.size()

      // Subtract some height for less margin before time label
      let adjustedMarginTotalHeight = margins.totalHeight * 0.75

      /// Calculate `availableHeight`: viewport height, minus top & bottom bars, minus extra space
      let availableHeight = viewportSize.height - currentGeo.insideBars.totalHeight - adjustedMarginTotalHeight - timeLabelSize.height
      /// `availableWidth`: entire window width, minus extra space
      let availableWidth = currentGeo.windowFrame.width - margins.totalWidth
      let oscOriginInWindowY = currentControlBar.superview!.convert(currentControlBar.frame.origin, to: nil).y
      let oscHeight = currentControlBar.frame.size.height

      var thumbAspect = showThumbnail ? (thumbWidth / thumbHeight) : 1.0

      if showThumbnail {
        // The aspect ratio of some videos is different at display time. May need to resize these videos
        // once the actual aspect ratio is known. (Should they be resized before being stored on disk? Doing so
        // would increase the file size without improving the quality, whereas resizing on the fly seems fast enough).
        let videoAspectCAR = currentGeo.video.videoAspectCAR
        if thumbAspect != videoAspectCAR {
          thumbHeight = (thumbWidth / videoAspectCAR).rounded()
          /// Recalculate this for later use (will use it and `thumbHeight`, and derive width)
          thumbAspect = thumbWidth / thumbHeight
        }

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
        if thumbHeight < Constants.Distance.Thumbnail.minHeight {
          thumbHeight = Constants.Distance.Thumbnail.minHeight
        }

        // Thumb too tall?
        if thumbHeight > availableHeight {
          // Scale down thumbnail so it doesn't overlap top or bottom bars
          thumbHeight = availableHeight
        }
        thumbWidth = thumbHeight * thumbAspect

        // Also scale down thumbnail if it's wider than the viewport
        if thumbWidth > availableWidth {
          thumbWidth = availableWidth
          thumbHeight = thumbWidth / thumbAspect
        }
      }  // end if showThumbnail

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
          // Need to check available space in viewport above & below OSC
          let totalExtraVerticalSpace = adjustedMarginTotalHeight + timeLabelSize.height
          let availableHeightBelow = max(0, oscOriginInWindowY - currentGeo.insideBars.bottom - totalExtraVerticalSpace)
          if availableHeightBelow > thumbHeight {
            // Show below by default, if there is space for the desired size
            showAbove = false
          } else {
            // If not enough space to show the full-size thumb below, then show above if it has more space
            let availableHeightAbove = max(0, viewportSize.height - (oscOriginInWindowY + oscHeight + totalExtraVerticalSpace + currentGeo.insideBars.top))
            showAbove = availableHeightAbove > availableHeightBelow
            if showThumbnail, showAbove, thumbHeight > availableHeightAbove {
              // Scale down thumbnail so it doesn't get clipped by the side of the window
              thumbHeight = availableHeightAbove
              thumbWidth = thumbHeight * thumbAspect
            }
          }

          if showThumbnail, !showAbove, thumbHeight > availableHeightBelow {
            thumbHeight = availableHeightBelow
            thumbWidth = thumbHeight * thumbAspect
          }
        }
      }

      // Constrain X origin so that it stays entirely inside the window and doesn't spill off the sides
      let isRightToLeft = player.videoView.userInterfaceLayoutDirection == .rightToLeft
      let minX = isRightToLeft ? margins.trailing : margins.leading
      let maxX = minX + availableWidth


      let halfMargin = margins.top * 0.5
      // Y offset calculation
      let timeLabelOriginY: CGFloat
      if showAbove {
        let oscTopY = oscOriginInWindowY + oscHeight
        let halfMargin = margins.bottom * 0.5
        // Show thumbnail above seek time, which is above slider
        if currentLayout.oscPosition == .floating || currentLayout.isMusicMode {
          timeLabelOriginY = oscTopY + halfMargin
        } else {
          let sliderFrameInWindowCoords = player.windowController.playSlider.frameInWindowCoords
          let sliderCenterY = sliderFrameInWindowCoords.origin.y + (sliderFrameInWindowCoords.height * 0.5)
          // If clear background, align the label consistently close to the slider bar.
          // Else if using gray panel, try to align the label either wholly inside or outside the panel.
          if !currentLayout.spec.oscBackgroundIsClear, sliderCenterY + timeLabelSize.height >= oscTopY {
            timeLabelOriginY = oscTopY + halfMargin
          } else {
            let quarterMargin = margins.bottom * 0.25
            timeLabelOriginY = sliderCenterY + (player.windowController.playSlider.customCell.knobHeight * 0.5) + quarterMargin
          }
        }
      } else {  // Show below PlaySlider
        let quarterMargin = margins.top * 0.25
        if currentLayout.oscPosition == .floating {
          timeLabelOriginY = oscOriginInWindowY - quarterMargin - timeLabelSize.height
        } else {
          let sliderFrameInWindowCoords = player.windowController.playSlider.frameInWindowCoords
          let sliderCenterY = sliderFrameInWindowCoords.origin.y + (sliderFrameInWindowCoords.height * 0.5)
          if !currentLayout.spec.oscBackgroundIsClear, sliderCenterY - timeLabelSize.height <= oscOriginInWindowY {
            timeLabelOriginY = oscOriginInWindowY + halfMargin - timeLabelSize.height
          } else {
            timeLabelOriginY = sliderCenterY - (player.windowController.playSlider.customCell.knobHeight * 0.5) - halfMargin - timeLabelSize.height
          }
        }
      }
      timeLabelVerticalSpaceConstraint.constant = timeLabelOriginY

      // Keep timeLabel centered with seek time location, which should usually match center of thumbnailPeekView.
      // But keep text fully inside window.
      let timeLabelWidth_Halved = timeLabelSize.width * 0.5
      let timeLabelCenterX = round(posInWindowX).clamped(to: (minX + timeLabelWidth_Halved)...(maxX - timeLabelWidth_Halved))
      timeLabelHorizontalCenterConstraint.constant = timeLabelCenterX

      timeLabel.alphaValue = 1.0
      timeLabel.isHidden = false

      // Done with timeLabel.
      log.trace{"TimeLabel centerX=\(timeLabelCenterX), originY=\(timeLabelOriginY)"}

      // Need integers below.
      if showThumbnail {
        thumbWidth = round(thumbWidth)
        thumbHeight = round(thumbHeight)

        if thumbWidth < Constants.Distance.Thumbnail.minHeight || thumbHeight < Constants.Distance.Thumbnail.minHeight {
          log.verbose("Not enough space to display thumbnail")
          showThumbnail = false
        }
      }

      if showThumbnail {
        let thumbOriginY: CGFloat
        if showAbove {
          thumbOriginY = timeLabelOriginY + timeLabelSize.height + halfMargin
        } else {
          thumbOriginY = timeLabelOriginY - halfMargin - thumbHeight
        }

        let thumbWidth_Halved = thumbWidth / 2
        let thumbOriginX = round(posInWindowX - thumbWidth_Halved).clamped(to: minX...(maxX - thumbWidth))
        let thumbFrame = NSRect(x: thumbOriginX, y: thumbOriginY, width: thumbWidth, height: thumbHeight)

        // Scaling is a potentially expensive operation, so do not change the last image if no change is needed
        let ffThumbnail = ffThumbnail!
        let somethingChanged = thumbStore!.currentDisplayedThumbFFTimestamp != ffThumbnail.timestamp || thumbnailPeekView.frame.width != thumbFrame.width || thumbnailPeekView.frame.height != thumbFrame.height
        if somethingChanged {
          thumbStore!.currentDisplayedThumbFFTimestamp = ffThumbnail.timestamp

          let cornerRadius = thumbnailPeekView.updateBorderStyle(thumbWidth: thumbWidth, thumbHeight: thumbHeight)

          // Apply crop first. Then aspect
          let croppedImage: CGImage
          let rotatedImage = ffThumbnail.image
          if let normalizedCropRect = currentGeo.video.cropRectNormalized {
            if currentGeo.video.userRotation != 0 {
              // FIXME: Need to rotate crop box coordinates to match image rotation
              log.warn{"Thumbnail generation with crop + rotation is currently broken! Using uncropped image instead"}
              croppedImage = rotatedImage
            } else {
              croppedImage = rotatedImage.cropped(normalizedCropRect: normalizedCropRect)
            }
          } else {
            croppedImage = rotatedImage
          }
          let finalImage = croppedImage.resized(newWidth: Int(thumbWidth), newHeight: Int(thumbHeight), cornerRadius: cornerRadius)
          thumbnailPeekView.image = NSImage.from(finalImage)
          thumbnailPeekView.widthConstraint.constant = thumbFrame.width
          thumbnailPeekView.heightConstraint.constant = thumbFrame.height
        }

        thumbnailPeekView.frame.origin = thumbFrame.origin
        log.trace{"Displaying thumbnail \(showAbove ? "above" : "below") OSC, frame=\(thumbFrame)"}
        thumbnailPeekView.alphaValue = 1.0
      }

      thumbnailPeekView.isHidden = !showThumbnail

      animationState = .shown
      // Start timer (or reset it), even if just hovering over the play slider. The Cocoa "mouseExited" event doesn't fire
      // reliably, so using a timer works well as a failsafe.
      restartHideTimer()
    }

  } // end class SeekPreview

  // MARK: - PlayerWindowController methods

  func shouldSeekPreviewBeVisible(forPointInWindow pointInWindow: NSPoint) -> Bool {
    guard !player.disableUI,
          !isAnimatingLayoutTransition,
          !osd.isShowingPersistentOSD,
          currentLayout.hasControlBar else {
      return false
    }
    return isScrollingOrDraggingPlaySlider || isPoint(pointInWindow, inAnyOf: [playSlider])
  }

  /// Called by `seekPreview.hideTimer`.
  func seekPreviewTimeout() {
    let pointInWindow = window!.convertPoint(fromScreen: NSEvent.mouseLocation)
    log.trace{"SeekPreview timed out: current mouseLoc=\(pointInWindow)"}
    refreshSeekPreviewAsync(forPointInWindow: pointInWindow, animateHide: true)
  }

  /// With animation. For non-animated version, see: `hideSeekPreviewImmediately()`.
  fileprivate func hideSeekPreviewWithAnimation() {
    var tasks: [IINAAnimation.Task] = []

    tasks.append(.init(duration: IINAAnimation.HideSeekPreviewDuration) { [self] in
      seekPreview.animationState = .willHide
      seekPreview.thumbnailPeekView.animator().alphaValue = 0
      seekPreview.timeLabel.animator().alphaValue = 0
      if fadeableViews.isShowingFadeableViewsForSeek {
        fadeableViews.isShowingFadeableViewsForSeek = false
        fadeableViews.hideTimer.restart()
      }
    })

    tasks.append(.init(duration: 0) { [self] in
      // if no interrupt then hide animation
      hideSeekPreviewImmediately()
    })

    animationPipeline.submit(tasks)
  }

  /// Without animation. For animated version, see `hideSeekPreviewWithAnimation()`, which will call this func (DRY).
  func hideSeekPreviewImmediately() {
    guard seekPreview.animationState == .shown || seekPreview.animationState == .willHide else { return }
    seekPreview.hideTimer.cancel()
    seekPreview.animationState = .hidden
    seekPreview.thumbnailPeekView.isHidden = true
    seekPreview.timeLabel.isHidden = true
    seekPreview.currentPreviewTimeSec = nil
  }

  /// Display time label & thumbnail when mouse over slider
  func refreshSeekPreviewAsync(forPointInWindow pointInWindow: NSPoint, animateHide: Bool = false) {
    thumbDisplayDebouncer.run { [self] in
      if shouldSeekPreviewBeVisible(forPointInWindow: pointInWindow), let duration = player.info.playbackDurationSec {
        if showSeekPreview(forPointInWindow: pointInWindow, mediaDuration: duration) {
          return
        }
      }

      // Check focus & show/hide volume slider hover
      isMouseHoveringOverVolumeSlider = isMouseActuallyInside(view: volumeSlider)
      player.windowController.volumeSlider.needsDisplay = true

      if animateHide {
        hideSeekPreviewWithAnimation()
      } else {
        hideSeekPreviewImmediately()
      }
    }
  }

  /// Should only be called by `refreshSeekPreviewAsync`
  private func showSeekPreview(forPointInWindow pointInWindow: NSPoint, mediaDuration: CGFloat) -> Bool {
    let notInMusicModeDisabled = !currentLayout.isMusicMode || (Preference.bool(for: .enableThumbnailForMusicMode) && musicModeGeo.isVideoVisible)

    // First check if both time & thumbnail are disabled
    guard let currentControlBar, notInMusicModeDisabled else {
      return false
    }

    let centerOfKnobInSliderCoordX = playSlider.computeCenterOfKnobInSliderCoordXGiven(pointInWindow: pointInWindow)

    // May need to adjust X to account for knob width
    let pointInSlider = NSPoint(x: centerOfKnobInSliderCoordX, y: 0)
    let pointInWindowCorrected = NSPoint(x: playSlider.convert(pointInSlider, to: nil).x, y: pointInWindow.y)

    // - 2. Thumbnail Preview

    let showThumbnail = Preference.bool(for: .enableThumbnailPreview)
    let isShowingThumbnailForSeek = isScrollingOrDraggingPlaySlider
    if isShowingThumbnailForSeek && (!showThumbnail || !Preference.bool(for: .showThumbnailDuringSliderSeek)) {
      // Do not show any preview if this feature is disabled
      return false
    }

    // Need to ensure OSC is displayed if showing thumbnail preview
    if currentLayout.hasFadeableOSC {
      let hasTopBarFadeableOSC = currentLayout.oscPosition == .top && currentLayout.topBarView == .showFadeableTopBar
      let isOSCHidden = hasTopBarFadeableOSC ? fadeableViews.topBarAnimationState == .hidden : fadeableViews.animationState == .hidden

      if isShowingThumbnailForSeek {
        if isOSCHidden {
          showFadeableViews(thenRestartFadeTimer: false, duration: 0, forceShowTopBar: hasTopBarFadeableOSC)
        } else {
          fadeableViews.hideTimer.cancel()
        }
        // Set this to remind ourselves to restart the fade timer when seek is done
        fadeableViews.isShowingFadeableViewsForSeek = true

      } else if isOSCHidden {
        // Do not show any preview if OSC is hidden and is not a showable seek
        return false
      }
    }

    let playbackPositionRatio = playSlider.computeProgressRatioGiven(centerOfKnobInSliderCoordX: centerOfKnobInSliderCoordX)
    let previewTimeSec = mediaDuration * playbackPositionRatio

    let winGeoUpdated = windowedGeoForCurrentFrame()  // not even needed if in full screen
    let currentGeo = currentLayout.buildGeometry(windowFrame: winGeoUpdated.windowFrame,
                                                 screenID: winGeoUpdated.screenID,
                                                 video: geo.video)
    seekPreview.showPreview(withThumbnail: showThumbnail, forTime: previewTimeSec, posInWindowX: pointInWindowCorrected.x, player,
                            currentControlBar: currentControlBar, currentGeo)
    return true
  }

}
