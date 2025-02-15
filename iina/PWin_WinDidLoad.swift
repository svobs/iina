//
//  PWin_WinDidLoad.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-23.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

extension PlayerWindowController {

  /// Called when window is initially loaded. Add all subviews here.
  override func windowDidLoad() {
    log.verbose("PlayerWindow windowDidLoad starting")
    super.windowDidLoad()
    guard let window else { return }
    guard let contentView = window.contentView else { return }

    miniPlayer = MiniPlayerViewController()
    miniPlayer.windowController = self

    viewportView.player = player

    co = buildObservers()

    // The fade timer is only used if auto-hide is enabled
    fadeableViews.hideTimer.startFunction = { _ in Preference.bool(for: .enableControlBarAutoHide) }
    fadeableViews.hideTimer.action = hideFadeableViewsAndCursor
    hideCursorTimer.action = hideCursor

    /// Set base options for `collectionBehavior` here, and then insert/remove full screen options
    /// using `resetCollectionBehavior`. Do not mess with the base options again because doing so seems
    /// to cause flickering while animating.
    /// Always use option `.fullScreenDisallowsTiling`. As of MacOS 14.2.1, tiling is at best glitchy &
    /// at worst results in an infinite loop with our code.
    // FIXME: support tiling for at least native full screen
    window.collectionBehavior = [.managed, .fullScreenDisallowsTiling]

    window.initialFirstResponder = nil

    window.minSize = Constants.WindowedMode.minWindowSize

    // Registers this window for didChangeScreenProfileNotification
    window.displaysWhenScreenProfileChanges = true

    leftTimeLabel.mode = .current
    rightTimeLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

    // gesture recognizers
    rotationHandler.windowController = self
    magnificationHandler.pwc = self
    contentView.addGestureRecognizer(magnificationHandler.magnificationGestureRecognizer)
    contentView.addGestureRecognizer(rotationHandler.rotationGestureRecognizer)

    // scroll wheel
    playSlider.scrollWheelDelegate = PlaySliderScrollWheel(slider: playSlider, log)
    volumeSlider.scrollWheelDelegate = VolumeSliderScrollWheel(slider: volumeSlider, log)
    windowScrollWheel = PWinScrollWheel(self)

    playlistView.windowController = self
    pluginView.windowController = self
    quickSettingView.windowController = self

    // other initialization
    osdAccessoryProgress.usesThreadedAnimation = false

    /// Note that this will add `videoView`, but at first run it will not yet have a video layer.
    /// Need to wait until after mpv is initialized before creating `videoView.layer`
    addVideoViewToWindow()
    player.start()

    /// Use an animation task to init views, to hopefully prevent partial/redundant draws.
    /// NOTE: this will likely execute *after* `_showWindow()`
    animationPipeline.submitInstantTask{ [self] in

      viewportView.clipsToBounds = true

      /// Set `window.contentView`'s background to black so that the windows behind this one don't bleed through
      /// when `lockViewportToVideoSize` is disabled, or when in legacy full screen on a Macbook screen  with a
      /// notch and the preference `allowVideoToOverlapCameraHousing` is false. Also needed so that sidebars don't
      /// bleed through during their show/hide animations.
      setEmptySpaceColor(to: Constants.Color.defaultWindowBackgroundColor)

      // Titlebar accessories

      // Update this here to reduce animation jitter on older versions of MacOS:
      viewportTopOffsetFromTopBarTopConstraint.constant = Constants.Distance.standardTitleBarHeight

      // Work around a bug in macOS Ventura where HDR content becomes dimmed when playing in full
      // screen mode once overlaying views are fully hidden (issue #3844). After applying this
      // workaround another bug in Ventura where an external monitor goes black could not be
      // reproduced (issue #4015). The workaround adds a tiny subview with such a low alpha level it
      // is invisible to the human eye. This workaround may not be effective in all cases.
      if #available(macOS 13, *) {
        let view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 0.1, height: 0.1)))
        view.layer?.backgroundColor = Constants.Color.defaultWindowBackgroundColor
        view.layer?.opacity = 0.01
        contentView.addSubview(view)
      }

      initSeekPreview(in: contentView)
      initTitleBar()
      initTopBarView(in: contentView)
      initBottomBarTopBorder()
      rebuildBottomBarView(in: contentView, style: .visualEffectView)
      initSpeedLabel()
      initPlaybackBtnsView()
      initPlaySliderAndTimeLabelsView()
      addSubviewsToPlaySliderAndTimeLabelsView()
      initVolumeView()
      initAlbumArtView()
      playSlider.customCell.pwc = self
      volumeSliderCell.pwc = self
      playSlider.target = self
      playSlider.action = #selector(playSliderAction(_:))

      bufferIndicatorView.roundCorners()
      additionalInfoView.roundCorners()
      osdVisualEffectView.roundCorners()

      log.verbose{"Configuring for CoreAnimation: window"}
      contentView.configureSubtreeForCoreAnimation()

      // Make sure to set this inside the animation task! See note above
      loaded = true

      // Update to corect values before displaying. Only useful when restoring at launch
      updateUI()

      if let priorState = priorStateIfRestoring {
        if let layoutSpec = priorState.layoutSpec {
          // Preemptively set window frames to prevent windows from "jumping" during restore
          if layoutSpec.mode == .musicMode {
            let pwinGeo = priorState.geoSet.musicMode.toPWinGeometry()
            player.window.setFrameImmediately(pwinGeo, notify: false)
          } else {
            let pwinGeo = priorState.geoSet.windowed
            player.window.setFrameImmediately(pwinGeo, notify: false)
          }
        }

        defaultAlbumArtView.isHidden = player.info.isVideoTrackSelected
      }

      if player.disableUI { hideFadeableViews() }

      // Must wait until *after* loaded==true to load plugins!
      player.loadPlugins()

      log.verbose("PlayerWindow windowDidLoad done")
      player.events.emit(.windowLoaded)
    }
  }

  // MARK: - Building Components

  private func initSeekPreview(in contentView: NSView) {
    seekPreview.player = player
    contentView.addSubview(seekPreview.timeLabel, positioned: .below, relativeTo: osdVisualEffectView)
    contentView.addSubview(seekPreview.thumbnailPeekView, positioned: .below, relativeTo: seekPreview.timeLabel)
    // This is above the play slider and by default, will swallow clicks. Send events to play slider instead
    seekPreview.timeLabel.nextResponder = playSlider

    // Yes, left, not leading!
    seekPreview.timeLabelHorizontalCenterConstraint = seekPreview.timeLabel.centerXAnchor.constraint(equalTo: contentView.leftAnchor, constant: 200) // dummy value for now
    seekPreview.timeLabelHorizontalCenterConstraint.identifier = .init("SeekTimeHoverLabelHSpaceConstraint")
    seekPreview.timeLabelHorizontalCenterConstraint.isActive = true

    // This is a bit confusing but the constant here can be thought of as the X value in window,
    // not flipped (so, larger values toward the top)
    seekPreview.timeLabelVerticalSpaceConstraint = contentView.bottomAnchor.constraint(equalTo: seekPreview.timeLabel.bottomAnchor, constant: 0)
    seekPreview.timeLabelVerticalSpaceConstraint.identifier = .init("SeekTimeHoverLabelVSpaceConstraint")
    seekPreview.timeLabelVerticalSpaceConstraint?.isActive = true

    seekPreview.hideTimer.action = self.seekPreviewTimeout
  }

  private func initTitleBar() {
    let builder = CustomTitleBar.shared
    let iconSpacingH = Constants.Distance.titleBarIconHSpacing
    // - LEADING

    let leadingTB = leadingTitleBarAccessoryView
    leadingTB.idString = "leadingTitleBarAccessoryView"

    builder.configureTitleBarButton(leadingSidebarToggleButton,
                                    Images.sidebarLeading,
                                    identifier: "LeadingSidebarToggleButton_Native",
                                    target: self,
                                    action: #selector(toggleLeadingSidebarVisibility(_:)),
                                    bounceOnClick: true)

    leadingTB.orientation = .horizontal
    leadingTB.alignment = .centerY
    leadingTB.distribution = .fill
    leadingTB.spacing = 0
    leadingTB.detachesHiddenViews = true
    leadingTB.setHuggingPriority(.init(500), for: .horizontal)

    leadingTB.addArrangedSubview(leadingSidebarToggleButton)

    // - TRAILING

    let trailingTB = trailingTitleBarAccessoryView
    trailingTB.idString = "trailingTitleBarAccessoryView"

    builder.configureTitleBarButton(onTopButton,
                                    Images.onTopOff,
                                    identifier: "OnTopButton_Native",
                                    target: self, action: #selector(toggleOnTop(_:)),
                                    bounceOnClick: false) // Do not bounce (looks weird)

    builder.configureTitleBarButton(trailingSidebarToggleButton,
                                    Images.sidebarTrailing,
                                    identifier: "TrailingSidebarToggleButton_Native",
                                    target: self,
                                    action: #selector(toggleTrailingSidebarVisibility(_:)),
                                    bounceOnClick: true)

    trailingTB.orientation = .horizontal
    trailingTB.alignment = .centerY
    trailingTB.distribution = .fill
    trailingTB.spacing = iconSpacingH
    trailingTB.detachesHiddenViews = true
    trailingTB.setHuggingPriority(.init(500), for: .horizontal)
    trailingTB.edgeInsets = NSEdgeInsets(top: 0, left: iconSpacingH, bottom: 0, right: iconSpacingH)

    trailingTB.addArrangedSubview(trailingSidebarToggleButton)
    trailingTB.addArrangedSubview(onTopButton)

    addTitleBarAccessoryViews()
  }

  func initTopBarView(in contentView: NSView) {
    // Top bar: other init
    topBarView.clipsToBounds = true

    /// `controlBarTop`
    controlBarTop.translatesAutoresizingMaskIntoConstraints = false
    controlBarTop.identifier = .init("ControlBarTopView")
    topBarView.addSubviewAndConstraints(controlBarTop,
                                        bottom: 0, leading: 0, trailing: 0)

    topOSCHeightConstraint = topBarView.bottomAnchor.constraint(equalTo: controlBarTop.topAnchor, constant: 0)
    topOSCHeightConstraint.identifier = .init("TopOSC-HeightConstraint")
    topOSCHeightConstraint.priority = .init(900)
    topOSCHeightConstraint.isActive = true

    /// `titleBarView`
    titleBarView.translatesAutoresizingMaskIntoConstraints = false
    topBarView.addSubview(titleBarView)
    titleBarView.identifier = .init("TitleBarView")
    let titleBarBottom_ToControlBarTop_Constraint = titleBarView.bottomAnchor.constraint(equalTo: controlBarTop.topAnchor, constant: 0)
    titleBarBottom_ToControlBarTop_Constraint.identifier = .init("TitleBar-Bottom_ToControlBarTop_Constraint")
    titleBarBottom_ToControlBarTop_Constraint.isActive = true

    titleBarView.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)

    titleBarHeightConstraint = titleBarView.bottomAnchor.constraint(equalTo: topBarView.topAnchor, constant: 20)
    titleBarHeightConstraint.identifier = .init("TitleBarView-HeightConstraint")
    titleBarHeightConstraint.priority = .init(900)
    titleBarHeightConstraint.isActive = true

    // Bottom border
    topBarBottomBorder.identifier = .init("TopBarBottomBorder")
    topBarBottomBorder.boxType = .custom
    topBarBottomBorder.titlePosition = .noTitle
    topBarBottomBorder.borderWidth = 0
    topBarBottomBorder.borderColor = .clear
    topBarBottomBorder.fillColor = .titleBarBorder
    topBarBottomBorder.translatesAutoresizingMaskIntoConstraints = false
    topBarView.addSubview(topBarBottomBorder)
    topBarBottomBorder.addConstraintsToFillSuperview(bottom: 0, leading: 0, trailing: 0)
    let topBarBottomBorder_HeightConstraint = topBarView.bottomAnchor.constraint(equalTo: topBarBottomBorder.topAnchor, constant: 0.5)
    topBarBottomBorder_HeightConstraint.identifier = .init("TopBarBottomBorder-HeightConstraint")
    topBarBottomBorder_HeightConstraint.isActive = true

  }

  func initBottomBarTopBorder() {
    bottomBarTopBorder.identifier = .init("BottomBar-TopBorder")  // helps with debug logging
    bottomBarTopBorder.boxType = .custom
    bottomBarTopBorder.titlePosition = .noTitle
    bottomBarTopBorder.borderWidth = 0
    bottomBarTopBorder.borderColor = .clear
    bottomBarTopBorder.fillColor = .titleBarBorder
    bottomBarTopBorder.translatesAutoresizingMaskIntoConstraints = false
  }

  func rebuildBottomBarView(in contentView: NSView, style: Preference.OSCColorScheme) {
    log.verbose{"Rebuilding bottomBarView: style=\(style)"}
    bottomBarView.removeAllSubviews()
    bottomBarView.removeFromSuperview()

    let bottomBarView: NSView
    switch style {
    case .visualEffectView:
      bottomBarView = NSVisualEffectView()
    case .clearGradient:
      bottomBarView = NSView()
      let gradient = CAGradientLayer()
      gradient.frame = bottomBarView.bounds
      // Top → Bottom
      gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
      gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
      // Ideally the gradient would use a quadratic function, but seems we are limited to linear, so just fudge it a bit.
      gradient.colors = [CGColor(red: 0, green: 0, blue: 0, alpha: 0.0),
                         CGColor(red: 0, green: 0, blue: 0, alpha: 0.2),
                         CGColor(red: 0, green: 0, blue: 0, alpha: 0.5),
                         CGColor(red: 0, green: 0, blue: 0, alpha: 0.7)]
      bottomBarView.layer = gradient
      bottomBarView.wantsLayer = true
    }

    bottomBarView.clipsToBounds = true
    if let bottomBarView = bottomBarView as? NSVisualEffectView {
      bottomBarView.blendingMode = .withinWindow
      bottomBarView.material = .sidebar
      bottomBarView.state = .active
    }
    bottomBarView.identifier = .init("BottomBarView")  // helps with debug logging
    bottomBarView.isHidden = true
    bottomBarView.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(bottomBarView, positioned: .above, relativeTo: viewportView)

    viewportBtmOffsetFromTopOfBottomBarConstraint = viewportView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 0)
    viewportBtmOffsetFromTopOfBottomBarConstraint.isActive = true
    viewportBtmOffsetFromTopOfBottomBarConstraint.identifier = .init("viewportBtmOffsetFromTopOfBottomBarConstraint")

    viewportBtmOffsetFromBtmOfBottomBarConstraint = viewportView.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor, constant: 0)
    viewportBtmOffsetFromBtmOfBottomBarConstraint.isActive = true
    viewportBtmOffsetFromBtmOfBottomBarConstraint.identifier = .init("viewportBtmOffsetFromBtmOfBottomBarConstraint")

    bottomBarLeadingSpaceConstraint = bottomBarView.leadingAnchor.constraint(equalTo: leadingSidebarView.trailingAnchor, constant: 0)
    bottomBarLeadingSpaceConstraint.isActive = true
    bottomBarLeadingSpaceConstraint.identifier = .init("bottomBarLeadingSpaceConstraint")

    bottomBarTrailingSpaceConstraint = bottomBarView.trailingAnchor.constraint(equalTo: trailingSidebarView.leadingAnchor, constant: 0)
    bottomBarTrailingSpaceConstraint.isActive = true
    bottomBarTrailingSpaceConstraint.identifier = .init("bottomBarTrailingSpaceConstraint")

    bottomBarView.addSubview(bottomBarTopBorder)
    bottomBarTopBorder.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)
    bottomBarTopBorder.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 0.5).isActive = true

    self.bottomBarView = bottomBarView
  }

  /// Init `fragPlaybackBtnsView` & its subviews
  private func initPlaybackBtnsView() {
    let oscGeo = currentLayout.controlBarGeo

    // Play button
    playButton.image = Images.play
    playButton.target = self
    playButton.action = #selector(playButtonAction(_:))
    playButton.refusesFirstResponder = true
    playButton.identifier = .init("PlayButton")  // helps with debug logging
    playButton.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    playButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    let playIconSize = oscGeo.playIconSize
    playBtnWidthConstraint = playButton.widthAnchor.constraint(equalToConstant: playIconSize)
    playBtnWidthConstraint.identifier = .init("PlayBtnWidthConstraint")
    playBtnWidthConstraint.priority = .init(850)  // allow to shrink for animations or speedLabel
    playBtnWidthConstraint.isActive = true
    let playAspectConstraint = playButton.widthAnchor.constraint(equalTo: playButton.heightAnchor)
    playAspectConstraint.isActive = true

    let playBtnSpeedVStackView = ClickThroughStackView()
    playBtnSpeedVStackView.identifier = .init("PlayBtnSpeedVStackView")
    playBtnSpeedVStackView.orientation = .vertical
    playBtnSpeedVStackView.alignment = .centerX
    playBtnSpeedVStackView.detachesHiddenViews = true
    playBtnSpeedVStackView.spacing = 0
    playBtnSpeedVStackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    playBtnSpeedVStackView.addView(speedLabel, in: .center)
    playBtnSpeedVStackView.addView(playButton, in: .center)
    playBtnSpeedVStackView.setHuggingPriority(.init(250), for: .vertical)
    playBtnSpeedVStackView.setHuggingPriority(.init(250), for: .horizontal)
    playBtnSpeedVStackView.translatesAutoresizingMaskIntoConstraints = false

    let enableAcceleration = Preference.bool(for: .useForceTouchForSpeedArrows)
    // Left Arrow button
    leftArrowButton.image = oscGeo.leftArrowImage
    leftArrowButton.target = self
    leftArrowButton.action = #selector(leftArrowButtonAction(_:))
    leftArrowButton.identifier = .init("LeftArrowButton")
    leftArrowButton.refusesFirstResponder = true
    leftArrowButton.enableAcceleration = enableAcceleration
    leftArrowButton.bounceOnClick = true

    // Right Arrow button
    rightArrowButton.image = oscGeo.rightArrowImage
    rightArrowButton.target = self
    rightArrowButton.action = #selector(rightArrowButtonAction(_:))
    rightArrowButton.identifier = .init("RightArrowButton")
    rightArrowButton.refusesFirstResponder = true
    rightArrowButton.enableAcceleration = enableAcceleration
    rightArrowButton.bounceOnClick = true

    fragPlaybackBtnsView.identifier = .init("fragPlaybackBtnsView")
    fragPlaybackBtnsView.addSubview(leftArrowButton)
    fragPlaybackBtnsView.addSubview(playBtnSpeedVStackView)
    fragPlaybackBtnsView.addSubview(rightArrowButton)

    playBtnSpeedVStackView.heightAnchor.constraint(lessThanOrEqualTo: fragPlaybackBtnsView.heightAnchor).isActive = true

    fragPlaybackBtnsView.translatesAutoresizingMaskIntoConstraints = false
    fragPlaybackBtnsView.setContentHuggingPriority(.init(rawValue: 249), for: .vertical)  // hug superview more than default

    // Try to make sure the buttons' bounding boxes reach the full height, for activation
    // (their images will be limited by the width constraint & will stop scaling before this)
    let leftArrowHeightConstraint = leftArrowButton.heightAnchor.constraint(equalTo: fragPlaybackBtnsView.heightAnchor)
    leftArrowHeightConstraint.identifier = .init("leftArrow-HeightConstraint")
    leftArrowHeightConstraint.priority = .defaultHigh
    leftArrowHeightConstraint.isActive = true
    let rightArrowHeightConstraint = rightArrowButton.heightAnchor.constraint(equalTo: fragPlaybackBtnsView.heightAnchor)
    rightArrowHeightConstraint.identifier = .init("rightArrow-HeightConstraint")
    rightArrowHeightConstraint.priority = .defaultHigh
    rightArrowHeightConstraint.isActive = true

    // Video controllers and timeline indicators should not flip in a right-to-left language.
    fragPlaybackBtnsView.userInterfaceLayoutDirection = .leftToRight

    let playBtnVertOffsetConstraint = playButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    playBtnVertOffsetConstraint.isActive = true

    let playBtnHorizOffsetConstraint = playBtnSpeedVStackView.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor)
    playBtnHorizOffsetConstraint.isActive = true

    speedLabel.topAnchor.constraint(equalTo: fragPlaybackBtnsView.topAnchor).isActive = true

    fragPlaybackBtnsWidthConstraint = fragPlaybackBtnsView.widthAnchor.constraint(equalToConstant: oscGeo.totalPlayControlsWidth)
    fragPlaybackBtnsWidthConstraint.identifier = .init("fragPlaybackBtns-WidthConstraint")
    fragPlaybackBtnsWidthConstraint.isActive = true

    leftArrowBtn_CenterXOffsetConstraint = leftArrowButton.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor,
                                                                                    constant: oscGeo.leftArrowCenterXOffset)
    leftArrowBtn_CenterXOffsetConstraint.identifier = .init("leftArrowBtn-HorizOffsetConstraint")
    leftArrowBtn_CenterXOffsetConstraint.isActive = true

    arrowBtnWidthConstraint = leftArrowButton.widthAnchor.constraint(equalToConstant: oscGeo.arrowIconWidth)
    arrowBtnWidthConstraint.identifier = .init("arrowBtn-WidthConstraint")
    arrowBtnWidthConstraint.isActive = true

    rightArrowBtn_CenterXOffsetConstraint = rightArrowButton.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor,
                                                                                      constant: oscGeo.rightArrowCenterXOffset)
    rightArrowBtn_CenterXOffsetConstraint.identifier = .init("rightArrowBtn_CenterXOffsetConstraint")
    rightArrowBtn_CenterXOffsetConstraint.isActive = true

    // Left & Right arrow buttons are always same size
    let arrowBtnsEqualWidthConstraint = leftArrowButton.widthAnchor.constraint(equalTo: rightArrowButton.widthAnchor, multiplier: 1)
    arrowBtnsEqualWidthConstraint.identifier = .init("arrowBtnsEqualWidthConstraint")
    arrowBtnsEqualWidthConstraint.isActive = true

    let leftArrowBtnVertOffsetConstraint = leftArrowButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    leftArrowBtnVertOffsetConstraint.isActive = true
    let rightArrowBtnVertOffsetConstraint = rightArrowButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    rightArrowBtnVertOffsetConstraint.isActive = true
  }

  private func initSpeedLabel() {
    speedLabel.idString = "SpeedLabel"  // helps with debug logging
    speedLabel.translatesAutoresizingMaskIntoConstraints = false
    speedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
    speedLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    speedLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    speedLabel.setContentHuggingPriority(.required, for: .horizontal)
    speedLabel.setContentHuggingPriority(.required, for: .vertical)
    speedLabel.font = NSFont.messageFont(ofSize: 10)
    speedLabel.textColor = .textColor
    speedLabel.alphaValue = 0.75
    speedLabel.isBordered = false
    speedLabel.drawsBackground = false
    speedLabel.isBezeled = false
    speedLabel.isEditable = false
    speedLabel.isSelectable = false
    speedLabel.isEnabled = true
    speedLabel.refusesFirstResponder = true
    speedLabel.alignment = .center

    speedLabel.nextResponder = playButton
  }

  private func initPlaySliderAndTimeLabelsView() {
    // - Configure playSliderAndTimeLabelsView
    playSliderAndTimeLabelsView.idString = "PlaySliderAndTimeLabelsView"
    playSliderAndTimeLabelsView.translatesAutoresizingMaskIntoConstraints = false
    playSliderAndTimeLabelsView.userInterfaceLayoutDirection = .leftToRight
    playSliderAndTimeLabelsView.setContentHuggingPriority(.init(249), for: .horizontal)
    playSliderAndTimeLabelsView.setContentCompressionResistancePriority(.init(249), for: .horizontal)
    playSliderAndTimeLabelsView.widthAnchor.constraint(greaterThanOrEqualToConstant: 150.0).isActive = true

    // - Configure subviews

    leftTimeLabel.idString = "PlayPos-LeftTimeLabel"
    leftTimeLabel.alignment = .right
    leftTimeLabel.isBordered = false
    leftTimeLabel.drawsBackground = false
    leftTimeLabel.isEditable = false
    leftTimeLabel.refusesFirstResponder = true
    leftTimeLabel.translatesAutoresizingMaskIntoConstraints = false
    leftTimeLabel.setContentHuggingPriority(.init(501), for: .horizontal)
    leftTimeLabel.setContentCompressionResistancePriority(.init(501), for: .horizontal)

    playSlider.idString = "PlaySlider"
    playSlider.minValue = 0
    playSlider.maxValue = 100
    playSlider.isContinuous = true
    playSlider.refusesFirstResponder = true
    playSlider.translatesAutoresizingMaskIntoConstraints = false
    let widthConstraint = playSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 50)
    widthConstraint.identifier = "PlaySlider-MinWidthConstraint"
    widthConstraint.isActive = true

    playSliderHeightConstraint = playSlider.heightAnchor.constraint(equalToConstant: 20)
    playSliderHeightConstraint.identifier = "PlaySlider-HeightConstraint"
    playSliderHeightConstraint.priority = .init(900)
    playSliderHeightConstraint.isActive = true

    rightTimeLabel.idString = "PlayPos-RightTimeLabel"
    rightTimeLabel.alignment = .left
    rightTimeLabel.isBordered = false
    rightTimeLabel.drawsBackground = false
    rightTimeLabel.isEditable = false
    rightTimeLabel.refusesFirstResponder = true
    rightTimeLabel.translatesAutoresizingMaskIntoConstraints = false
    rightTimeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    rightTimeLabel.setContentCompressionResistancePriority(.init(749), for: .horizontal)
  }

  func addSubviewsToPlaySliderAndTimeLabelsView() {
    // Assume that if all subviews are inside, the constraints are properly configured as well,
    // and no more work is needed.
    playSliderAndTimeLabelsView.removeAllSubviews()

    playSliderAndTimeLabelsView.addSubview(leftTimeLabel)
    playSliderAndTimeLabelsView.addSubview(playSlider)
    playSliderAndTimeLabelsView.addSubview(rightTimeLabel)

    // - Add constraints to subviews

    let spacing = Constants.Distance.playSliderAndTimeLabelsViewHSpacing
    leftTimeLabel.leadingAnchor.constraint(equalTo: playSliderAndTimeLabelsView.leadingAnchor).isActive = true
    playSlider.leadingAnchor.constraint(equalTo: leftTimeLabel.trailingAnchor, constant: spacing).isActive = true

    // See also: playSliderHeightConstraint
    playSlider.addConstraintsToFillSuperview(top: 0, bottom: 0)

    playSlider.centerYAnchor.constraint(equalTo: leftTimeLabel.centerYAnchor).isActive = true
    playSlider.centerYAnchor.constraint(equalTo: rightTimeLabel.centerYAnchor).isActive = true

    rightTimeLabel.leadingAnchor.constraint(equalTo: playSlider.trailingAnchor, constant: spacing).isActive = true
    rightTimeLabel.trailingAnchor.constraint(equalTo: playSliderAndTimeLabelsView.trailingAnchor).isActive = true
  }

  private func initVolumeView() {
    // We are early in the loading process. Don't trust cached ControlBarGeometry too much...
    let oscGeo = ControlBarGeometry(mode: currentLayout.mode)
    let hSpacing: CGFloat = 2

    // Volume view
    fragVolumeView.identifier = .init("fragVolumeView")
    fragVolumeView.translatesAutoresizingMaskIntoConstraints = false
    fragVolumeView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

    // Mute button
    muteButton.idString = "MuteButton"
    let volImage = Images.volume3
    muteButton.image = Images.volume3
    muteButton.target = self
    muteButton.action = #selector(muteButtonAction(_:))
    muteButton.toolTip = "Toggle mute"
    fragVolumeView.addSubview(muteButton)
    muteButton.translatesAutoresizingMaskIntoConstraints = false
    muteButton.addConstraintsToFillSuperview(bottom: 0, leading: 0)
    muteButton.centerYAnchor.constraint(equalTo: fragVolumeView.centerYAnchor).isActive = true
    volumeIconHeightConstraint = muteButton.heightAnchor.constraint(equalToConstant: oscGeo.volumeIconHeight)
    volumeIconHeightConstraint.priority = .init(900)
    volumeIconHeightConstraint.isActive = true
    volumeIconAspectConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: volImage.aspect)
    volumeIconAspectConstraint.priority = .init(900)
    volumeIconAspectConstraint.isActive = true

    // Volume slider
    fragVolumeView.addSubview(volumeSlider)
    volumeSlider.cell = volumeSliderCell
    // For some reason this needs to be set here, instead of in volumeSliderCell init.
    // Otherwise action will continue to be nil...
    volumeSliderCell.hoverTimer.action = volumeSliderCell.refreshVolumeSliderHoverEffect
    volumeSlider.idString = "VolumeSlider"
    volumeSlider.controlSize = .regular
    volumeSlider.translatesAutoresizingMaskIntoConstraints = false
    volumeSliderWidthConstraint = volumeSlider.widthAnchor.constraint(equalToConstant: oscGeo.volumeSliderWidth)
    volumeSliderWidthConstraint.identifier = .init("VolumeSlider-WidthConstraint")
    volumeSliderWidthConstraint.isActive = true
    volumeSlider.centerYAnchor.constraint(equalTo: muteButton.centerYAnchor).isActive = true
    volumeSlider.leadingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: hSpacing).isActive = true
    volumeSlider.superview!.trailingAnchor.constraint(equalTo: volumeSlider.trailingAnchor).isActive = true
    volumeSlider.target = self
    volumeSlider.action = #selector(volumeSliderAction(_:))
  }

  private func initAlbumArtView() {
    defaultAlbumArtView.idString = "DefaultAlbumArtView"
    defaultAlbumArtView.wantsLayer = true
    defaultAlbumArtView.layer?.contents = #imageLiteral(resourceName: "default-album-art")
    defaultAlbumArtView.isHidden = true
    viewportView.addSubview(defaultAlbumArtView)

    defaultAlbumArtView.translatesAutoresizingMaskIntoConstraints = false

    // Add 1:1 aspect ratio constraint
    let aspectConstraint = defaultAlbumArtView.widthAnchor.constraint(equalTo: defaultAlbumArtView.heightAnchor, multiplier: 1)
    aspectConstraint.priority = .defaultHigh
    aspectConstraint.isActive = true
    // Always fill superview
    let widthGE = defaultAlbumArtView.widthAnchor.constraint(greaterThanOrEqualTo: viewportView.widthAnchor)
    widthGE.priority = .defaultHigh
    widthGE.isActive = true
    let heightGE = defaultAlbumArtView.heightAnchor.constraint(greaterThanOrEqualTo: viewportView.heightAnchor)
    heightGE.priority = .defaultHigh
    heightGE.isActive = true
    let widthEq = defaultAlbumArtView.widthAnchor.constraint(equalTo: viewportView.widthAnchor)
    widthEq.priority = .defaultLow
    widthEq.isActive = true
    let heightEq = defaultAlbumArtView.heightAnchor.constraint(equalTo: viewportView.heightAnchor)
    heightEq.priority = .defaultLow
    heightEq.isActive = true
    // Center in superview
    defaultAlbumArtView.centerXAnchor.constraint(equalTo: viewportView.centerXAnchor).isActive = true
    defaultAlbumArtView.centerYAnchor.constraint(equalTo: viewportView.centerYAnchor).isActive = true
  }

}
