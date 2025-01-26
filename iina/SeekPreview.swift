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
                     posInWindowX: CGFloat, _ player: PlayerCore,
                     _ currentLayout: LayoutState, currentControlBar: NSView,
                     _ videoGeo: VideoGeometry, viewportSize: NSSize, isRightToLeft: Bool) {

      let log = player.log
      let margins = SeekPreview.minThumbMargins
      let timeLabelHeight = timeLabel.fittingSize.height
      let thumbStore = player.info.currentPlayback?.thumbnails
      let ffThumbnail = thumbStore?.getThumbnail(forSecond: previewTimeSec)

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
      }

      // Subtract some height for less margin before time label
      let adjustedMarginTotalHeight = margins.totalHeight * 0.75

      /// Calculate `availableHeight`: viewport height, minus top & bottom bars, minus extra space
      let availableHeight = viewportSize.height - currentLayout.insideBars.totalHeight - adjustedMarginTotalHeight - timeLabelHeight
      /// `availableWidth`: viewport width, minus extra space
      let availableWidth = viewportSize.width - margins.totalWidth
      let oscOriginInWindowY = currentControlBar.superview!.convert(currentControlBar.frame.origin, to: nil).y
      let oscHeight = currentControlBar.frame.size.height

      var thumbAspect = showThumbnail ? (thumbWidth / thumbHeight) : 1.0

      if showThumbnail {
        // The aspect ratio of some videos is different at display time. May need to resize these videos
        // once the actual aspect ratio is known. (Should they be resized before being stored on disk? Doing so
        // would increase the file size without improving the quality, whereas resizing on the fly seems fast enough).
        let videoAspectCAR = videoGeo.videoAspectCAR
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
          let totalExtraVerticalSpace = adjustedMarginTotalHeight + timeLabelHeight
          let availableHeightBelow = max(0, oscOriginInWindowY - currentLayout.insideBottomBarHeight - totalExtraVerticalSpace)
          if availableHeightBelow > thumbHeight {
            // Show below by default, if there is space for the desired size
            showAbove = false
          } else {
            // If not enough space to show the full-size thumb below, then show above if it has more space
            let availableHeightAbove = max(0, viewportSize.height - (oscOriginInWindowY + oscHeight + totalExtraVerticalSpace + currentLayout.insideTopBarHeight))
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

      // Need integers below.
      thumbWidth = round(thumbWidth)
      thumbHeight = round(thumbHeight)

      // Y offset calculation
      let timeLabelOriginY: CGFloat
      let thumbOriginY: CGFloat
      if showAbove {
        let halfMargin = margins.bottom * 0.5
        let quarterMargin = margins.bottom * 0.25
        // Show thumbnail above seek time, which is above slider
        if currentLayout.oscPosition == .floating || currentLayout.isMusicMode {
          timeLabelOriginY = oscOriginInWindowY + oscHeight + quarterMargin
        } else {
          timeLabelOriginY = oscOriginInWindowY + (oscHeight * 0.5) + (player.windowController.playSlider.customCell.knobHeight * 0.5) + quarterMargin
        }
        thumbOriginY = timeLabelOriginY + timeLabelHeight + halfMargin
      } else {
        let halfMargin = margins.top * 0.5
        // Show thumbnail below slider
        timeLabelOriginY = oscOriginInWindowY - (player.windowController.playSlider.customCell.knobHeight * 0.5) - timeLabelHeight
        thumbOriginY = timeLabelOriginY - halfMargin - thumbHeight
      }
      // Constrain X origin so that it stays entirely inside the viewport (and not inside the outside sidebars)
      let minX = isRightToLeft ? currentLayout.outsideTrailingBarWidth + margins.trailing : currentLayout.outsideLeadingBarWidth + margins.leading
      let maxX = minX + availableWidth
      let halfThumbWidth = thumbWidth / 2
      let thumbOriginX = min(max(minX, round(posInWindowX - halfThumbWidth)), maxX - thumbWidth)
      // Keep timeLabel centered with thumbnail center. If thumb is not visible, halfThumbWidth will be 0.
      let timeLabelCenterX = round(thumbOriginX + halfThumbWidth)

      let thumbFrame = NSRect(x: thumbOriginX, y: thumbOriginY, width: thumbWidth, height: thumbHeight)

      log.trace{"TimeLabel centerX=\(timeLabelCenterX), originY=\(timeLabelOriginY); thumbFrame=\(thumbFrame)"}
      timeLabelHorizontalCenterConstraint.constant = timeLabelCenterX
      timeLabelVerticalSpaceConstraint.constant = timeLabelOriginY

      if showThumbnail && (thumbWidth < Constants.Distance.Thumbnail.minHeight || thumbHeight < Constants.Distance.Thumbnail.minHeight) {
        log.verbose("Not enough space to display thumbnail")
        showThumbnail = false
      }

      if showThumbnail {
        // Scaling is a potentially expensive operation, so do not change the last image if no change is needed
        let ffThumbnail = ffThumbnail!
        let somethingChanged = thumbStore!.currentDisplayedThumbFFTimestamp != ffThumbnail.timestamp || thumbnailPeekView.frame.width != thumbFrame.width || thumbnailPeekView.frame.height != thumbFrame.height
        if somethingChanged {
          thumbStore!.currentDisplayedThumbFFTimestamp = ffThumbnail.timestamp

          let cornerRadius = thumbnailPeekView.updateBorderStyle(thumbWidth: thumbWidth, thumbHeight: thumbHeight)

          // Apply crop first. Then aspect
          let croppedImage: CGImage
          let rotatedImage = ffThumbnail.image
          if let normalizedCropRect = videoGeo.cropRectNormalized {
            if videoGeo.userRotation != 0 {
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

      timeLabel.alphaValue = 1.0
      timeLabel.isHidden = false
      thumbnailPeekView.isHidden = !showThumbnail

      currentPreviewTimeSec = previewTimeSec
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
    guard !shouldSeekPreviewBeVisible(forPointInWindow: pointInWindow) else {
      seekPreview.restartHideTimer()
      return
    }
    hideSeekPreviewWithAnimation()
  }

  /// With animation. For non-animated version, see: `hideSeekPreviewImmediately()`.
  func hideSeekPreviewWithAnimation() {
    var tasks: [IINAAnimation.Task] = []

    tasks.append(.init(duration: IINAAnimation.OSDAnimationDuration * 0.5) { [self] in
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
      guard seekPreview.animationState == .willHide else { return }
      hideSeekPreviewImmediately()
    })

    animationPipeline.submit(tasks)
  }

  /// Without animation. For animated version, see: `hideSeekPreviewWithAnimation()`.
  func hideSeekPreviewImmediately() {
    seekPreview.hideTimer.cancel()
    seekPreview.animationState = .hidden
    seekPreview.thumbnailPeekView.isHidden = true
    seekPreview.timeLabel.isHidden = true
  }

  /// Display time label & thumbnail when mouse over slider
  func refreshSeekPreviewAsync(forPointInWindow pointInWindow: NSPoint) {
    thumbDisplayDebouncer.run { [self] in
      if shouldSeekPreviewBeVisible(forPointInWindow: pointInWindow), let duration = player.info.playbackDurationSec {
        if showSeekPreview(forPointInWindow: pointInWindow, mediaDuration: duration) {
          return
        }
      }
      hideSeekPreviewImmediately()
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

    seekPreview.showPreview(withThumbnail: showThumbnail, forTime: previewTimeSec, posInWindowX: pointInWindowCorrected.x, player, currentLayout,
                            currentControlBar: currentControlBar, geo.video, viewportSize: viewportView.frame.size,
                            isRightToLeft: videoView.userInterfaceLayoutDirection == .rightToLeft)
    return true
  }

}
