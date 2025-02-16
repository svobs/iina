//
//  SeekPreview.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-21.
//  Copyright © 2024 lhc. All rights reserved.
//

extension PlayerWindowController {
  // TODO: PK.seekPreviewHasTimeDelta
  // TODO: PK.seekPreviewHasChapter

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

    // Components:
    let timeLabel = NSTextField()
    let thumbnailPeekView = ThumbnailPeekView()

    var timeLabelHorizontalCenterConstraint: NSLayoutConstraint!
    var timeLabelVerticalSpaceConstraint: NSLayoutConstraint!

    unowned var player: PlayerCore!
    var log: Logger.Subsystem { player.log }

    var animationState: UIAnimationState = .shown {
      didSet {
        if animationState == .willHide || animationState == .hidden {
          currentPreviewTimeSec = nil
        }
        // Trigger redraw of PlaySlider, in case knob needs to be shown or hidden
        thumbnailPeekView.associatedPlayer?.windowController.playSlider.needsDisplay = true
      }
    }
    // Only non-nil when SeekPreview is shown
    var currentPreviewTimeSec: Double? = nil

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
      updateStyle()
    }

    func restartHideTimer() {
      guard animationState == .shown else { return }
      hideTimer.restart()
    }

    func updateStyle() {
      timeLabel.addShadow(blurRadiusConstant: Constants.Distance.seekPreviewTimeLabel_ShadowRadiusConstant,
                          xOffsetConstant: Constants.Distance.seekPreviewTimeLabel_xOffsetConstant,
                          yOffsetConstant: Constants.Distance.seekPreviewTimeLabel_yOffsetConstant,
                          color: .black)
      let shadow: Preference.Shadow = Preference.enum(for: .seekPreviewShadow)
      let useGlow = shadow == .glow
      thumbnailPeekView.updateColors(glowShadow: useGlow)
    }

    /// This is expected to be called at first layout
    func updateTimeLabelFontSize(to newSize: CGFloat) {
      if timeLabel.font?.pointSize != newSize {
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: newSize, weight: .bold)
      }
    }

    /// `posInWindowX` is where center of timeLabel, thumbnailPeekView should be
    // TODO: Investigate using CoreAnimation!
    // https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html
    func showPreview(withThumbnail showThumbnail: Bool, forTime previewTimeSec: Double,
                     posInWindowX: CGFloat, currentControlBar: NSView,
                     _ currentGeo: PWinGeometry) {

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
        log.trace{"Not showing thumbnail for time=\(previewTimeSec): requested=\(showThumbnail.yn) found=\((ffThumbnail != nil).yn)"}
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
        // The aspect ratio of some videos is different at display time. Resize thumbs on-the-fly
        // once the actual aspect ratio is known.
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

        if showThumbnail {
          let totalExtraVerticalSpace = adjustedMarginTotalHeight + timeLabelSize.height
          let availableHeightAbove = max(0, viewportSize.height - totalExtraVerticalSpace)
          if thumbHeight > availableHeightAbove {
            // Scale down thumbnail so it doesn't get clipped by the side of the window
            thumbHeight = availableHeightAbove
            thumbWidth = thumbHeight * thumbAspect
          }
        }
      } else {
        switch currentLayout.oscPosition {
        case .top:
          showAbove = false
        case .bottom:
          showAbove = true
        case .floating:
          // Need to check available space in viewport above & below OSC
          let totalExtraVerticalSpace = adjustedMarginTotalHeight + timeLabelSize.height
          let availableHeightBelowOSC = max(0, oscOriginInWindowY - currentGeo.insideBars.bottom - totalExtraVerticalSpace)
          if availableHeightBelowOSC > thumbHeight {
            // Show below by default, if there is space for the desired size
            showAbove = false
          } else {
            // If not enough space to show the full-size thumb below, then show above if it has more space
            let availableHeightAboveOSC = max(0, viewportSize.height - (oscOriginInWindowY + oscHeight + totalExtraVerticalSpace + currentGeo.insideBars.top))
            showAbove = availableHeightAboveOSC > availableHeightBelowOSC
            if showThumbnail, showAbove, thumbHeight > availableHeightAboveOSC {
              // Scale down thumbnail so it doesn't get clipped by the side of the window
              thumbHeight = availableHeightAboveOSC
              thumbWidth = thumbHeight * thumbAspect
            }
          }

          if showThumbnail, !showAbove, thumbHeight > availableHeightBelowOSC {
            thumbHeight = availableHeightBelowOSC
            thumbWidth = thumbHeight * thumbAspect
          }
        }
      }

      // Constrain X origin so that it stays entirely inside the window and doesn't spill off the sides
      let isRightToLeft = player.videoView.userInterfaceLayoutDirection == .rightToLeft
      let minX = isRightToLeft ? margins.trailing : margins.leading
      let maxX = minX + availableWidth


      // Y offset calculation
      let timeLabelOriginY: CGFloat
      if showAbove {
        let oscTopY = oscOriginInWindowY + oscHeight
        let halfMargin = (margins.bottom * 0.5).rounded()
        // Show thumbnail above seek time, which is above slider
        if currentLayout.oscPosition == .floating || currentLayout.isMusicMode {
          timeLabelOriginY = (oscTopY + halfMargin).rounded()
        } else {
          guard let sliderFrameInWindowCoords = player.windowController.playSlider.frameInWindowCoords else { return }
          let sliderCenterY = sliderFrameInWindowCoords.origin.y + (sliderFrameInWindowCoords.height * 0.5)
          let quarterMargin = margins.bottom * 0.25
          let halfKnobHeight = player.windowController.playSlider.customCell.knobHeight * 0.5
          // If clear background, align the label consistently close to the slider bar.
          // Else if using gray panel, try to align the label either wholly inside or outside the panel.
          if !currentLayout.oscHasClearBG, sliderCenterY + halfKnobHeight + timeLabelSize.height >= oscTopY {
            timeLabelOriginY = (oscTopY + quarterMargin).rounded()
          } else {
            timeLabelOriginY = (sliderCenterY + halfKnobHeight + quarterMargin).rounded()
          }
        }
      } else {  // Show below PlaySlider
        let quarterMargin = margins.top * 0.25
        let halfMargin = margins.top * 0.5
        if currentLayout.oscPosition == .floating {
          timeLabelOriginY = (oscOriginInWindowY - quarterMargin - timeLabelSize.height).rounded()
        } else {
          guard let sliderFrameInWindowCoords = player.windowController.playSlider.frameInWindowCoords else { return }
          let sliderCenterY = (sliderFrameInWindowCoords.origin.y + (sliderFrameInWindowCoords.height * 0.5)).rounded()
          // See note for the Above case (but use ½ margin instead of ¼).
          let halfKnobHeight = (player.windowController.playSlider.customCell.knobHeight * 0.5).rounded()
          if !currentLayout.oscHasClearBG, sliderCenterY - halfKnobHeight - halfMargin - timeLabelSize.height <= oscOriginInWindowY {
            timeLabelOriginY = (oscOriginInWindowY - halfMargin - timeLabelSize.height).rounded()
          } else {
            timeLabelOriginY = (sliderCenterY - halfKnobHeight - halfMargin - timeLabelSize.height).rounded()
          }
        }
      }
      timeLabelVerticalSpaceConstraint.constant = timeLabelOriginY

      // Keep timeLabel centered with seek time location, which should usually match center of thumbnailPeekView.
      // But keep text fully inside window.
      let timeLabelWidth_Halved = timeLabelSize.width * 0.5
      let timeLabelCenterX = posInWindowX.clamped(to: (minX + timeLabelWidth_Halved)...(maxX - timeLabelWidth_Halved)).rounded()
      timeLabelHorizontalCenterConstraint.constant = timeLabelCenterX

      timeLabel.alphaValue = 1.0
      timeLabel.isHidden = false

      // Done with timeLabel.
      log.trace{"TimeLabel centerX=\(timeLabelCenterX), originY=\(timeLabelOriginY), size=\(timeLabelSize)"}

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
          let halfMargin = (margins.bottom * 0.5).rounded()
          thumbOriginY = timeLabelOriginY + timeLabelSize.height + halfMargin
        } else {
          let halfMargin = margins.top * 0.5
          thumbOriginY = timeLabelOriginY - halfMargin - thumbHeight
        }

        let thumbWidth_Halved = thumbWidth / 2
        let thumbOriginX = round(posInWindowX - thumbWidth_Halved).clamped(to: minX...(maxX - thumbWidth))
        let thumbFrame = NSRect(x: thumbOriginX, y: thumbOriginY.rounded(), width: thumbWidth, height: thumbHeight)

        if false {
          // Experiment with Thumbfast Lua script as an alternative (https://github.com/po5/thumbfast)
          player.mpv.showThumbfast(hoveredSecs: previewTimeSec, x: posInWindowX, y: 0)
          thumbnailPeekView.isHidden = true
        } else {
          updateThumbnailPeekView(to: ffThumbnail!, thumbFrame: thumbFrame, thumbStore!, currentGeo, previewTimeSec: previewTimeSec)
        }
      }
      thumbnailPeekView.isHidden = !showThumbnail
      animationState = .shown
      // Start timer (or reset it), even if just hovering over the play slider. The Cocoa "mouseExited" event doesn't fire
      // reliably, so using a timer works well as a failsafe.
      restartHideTimer()
    }

    private func updateThumbnailPeekView(to ffThumbnail: Thumbnail, thumbFrame: NSRect, _ thumbStore: SingleMediaThumbnailsLoader,
                                         _ currentGeo: PWinGeometry, previewTimeSec: CGFloat) {
      // Scaling is a potentially expensive operation, so do not change the last image if no change is needed
      let somethingChanged = true //thumbStore.currentDisplayedThumbFFTimestamp != ffThumbnail.timestamp || thumbnailPeekView.frame.width != thumbFrame.width || thumbnailPeekView.frame.height != thumbFrame.height
      if somethingChanged {
        thumbStore.currentDisplayedThumbFFTimestamp = ffThumbnail.timestamp
        let cornerRadius = thumbnailPeekView.updateBorderStyle(thumbSize: thumbFrame.size, previewTimeSec: previewTimeSec)

        // Apply crop first. Then aspect
        let croppedImage: CGImage
        if let normalizedCropRect = currentGeo.video.cropRectNormalized {
          croppedImage = ffThumbnail.image.cropped(normalizedCropRect: normalizedCropRect)
        } else {
          croppedImage = ffThumbnail.image
        }
        // The calculations for thumbFrame reflect the final image coordinates. But for faster speed we are going
        // to use the unflipped, unrotated thumbnail & apply rotation & mirroring/flipping via CoreAnimation transformations.
        let unrotatedImageSize: CGSize
        if currentGeo.video.isWidthSwappedWithHeightByRotation {
          unrotatedImageSize = CGSize(width: thumbFrame.height, height: thumbFrame.width)
        } else {
          unrotatedImageSize = thumbFrame.size
        }
        let affineImage = croppedImage.resized(newWidth: unrotatedImageSize.widthInt, newHeight: unrotatedImageSize.heightInt,
                                               cornerRadius: cornerRadius)
        thumbnailPeekView.image = NSImage.from(affineImage)
        thumbnailPeekView.widthConstraint.constant = unrotatedImageSize.width
        thumbnailPeekView.heightConstraint.constant = unrotatedImageSize.height

        thumbnailPeekView.frame.origin = thumbFrame.origin
      }

      // Apply flip, mirror, & rotate using CoreAnimation for blazing fast transformations
      if player.info.isFlippedHorizontal || player.info.isFlippedVertical || currentGeo.video.userRotation != 0 {
        let xFlip: CGFloat = player.info.isFlippedHorizontal ? -1 : 1
        let yFlip: CGFloat = player.info.isFlippedVertical ? -1 : 1
        var sumTF = CATransform3DMakeScale(xFlip, yFlip, 1)

        if currentGeo.video.userRotation != 0 {
          let rotationRadians = CGFloat.degToRad(CGFloat(-currentGeo.video.userRotation))
          let rotateTF = CATransform3DMakeRotation(rotationRadians, 0, 0, 1)
          sumTF = CATransform3DConcat(sumTF, rotateTF)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let layer = thumbnailPeekView.layer!
        let centerPoint = CGPointMake(NSMidX(thumbFrame), NSMidY(thumbFrame))
        layer.position = centerPoint
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.transform = sumTF

        CATransaction.commit()
      }

      log.trace{"Displaying thumbnail: frame=\(thumbFrame) in windowFrame=\(thumbnailPeekView.window?.frame.description ?? "nil"), calcWinFrame=\(currentGeo.windowFrame)"}
      thumbnailPeekView.alphaValue = 1.0
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
    return isScrollingOrDraggingPlaySlider || isPointInPlaySliderAndNotOtherViews(pointInWindow: pointInWindow)
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

      playSlider.hoverIndicator?.alphaValue = 0
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
    playSlider.hoverIndicator?.isHidden = true
  }

  /// Makes fake point in window to position seek time & thumbnail
  func refreshSeekPreviewAsync(forWindowCoordX windowCoordX: CGFloat, animateHide: Bool = false) {
    guard let playSliderFrameInWindowCoords = playSlider.frameInWindowCoords else { return }
    let pointInWindow = CGPoint(x: windowCoordX, y: playSliderFrameInWindowCoords.midY)
    refreshSeekPreviewAsync(forPointInWindow: pointInWindow, animateHide: animateHide)
  }

  /// Display time label & thumbnail when mouse over slider
  func refreshSeekPreviewAsync(forPointInWindow pointInWindow: NSPoint, animateHide: Bool = false) {
    thumbDisplayDebouncer.run { [self] in
      if shouldSeekPreviewBeVisible(forPointInWindow: pointInWindow), let duration = player.info.playbackDurationSec {
        if showSeekPreview(forPointInWindow: pointInWindow, mediaDuration: duration) {
          return
        }
      }

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

    // May need to adjust X to account for knob width
    let centerOfKnobInSliderCoordX = playSlider.computeCenterOfKnobInSliderCoordXGiven(pointInWindow: pointInWindow)
    let pointInSlider = NSPoint(x: centerOfKnobInSliderCoordX, y: 0)
    let pointInWindowCorrected = NSPoint(x: playSlider.convert(pointInSlider, to: nil).x, y: pointInWindow.y)

    // - 2. Thumbnail Preview

    let showThumbnail = Preference.bool(for: .enableThumbnailPreview) && player.info.isVideoTrackSelected
    let isShowingThumbnailForSeek = isScrollingOrDraggingPlaySlider
    if (isShowingThumbnailForSeek || playSlider.isDraggingLoopKnob) && !(Preference.bool(for: .enableThumbnailPreview) && Preference.bool(for: .showThumbnailDuringSliderSeek)) {
      // Do not show any preview if preview for seeking is disabled
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

    guard let (latestWindowFrame, latestScreenID) = getLatestWindowFrameAndScreenID() else {
      log.debug("Cannot display SeekPreview: could not get window.frame or screenID")
      return false
    }

    // Get X coord of hover (not the knob center)!
    let pointInWindowX: CGFloat = playSlider.convert(pointInWindow, from: nil).x
    playSlider.showHoverIndicator(atSliderCoordX: pointInWindowX)

    // This may be for music mode also!
    let currentGeo = currentLayout.buildGeometry(windowFrame: latestWindowFrame, screenID: latestScreenID, video: geo.video)

    seekPreview.showPreview(withThumbnail: showThumbnail, forTime: previewTimeSec, posInWindowX: pointInWindowCorrected.x,
                            currentControlBar: currentControlBar, currentGeo)
    return true
  }

}
