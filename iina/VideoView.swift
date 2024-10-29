//
//  VideoView.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa


class VideoView: NSView {

  weak var player: PlayerCore!
  var link: CVDisplayLink?

  var log: Logger.Subsystem {
    return player.log
  }

  var videoLayer: GLVideoLayer {
    return layer as! GLVideoLayer
  }

  @Atomic var isUninited = false

  // cached indicator to prevent unnecessary updates of DisplayLink
  var currentDisplay: UInt32?

  private var displayIdleTimer: Timer?

  private var videoViewConstraints: VideoViewConstraints? = nil

  private lazy var logHDR = Logger.makeSubsystem("hdr\(player.label)")

  static let SRGB = CGColorSpaceCreateDeviceRGB()

  // MARK: Init

  init(frame: CGRect, player: PlayerCore) {
    self.player = player
    super.init(frame: frame)

    translatesAutoresizingMaskIntoConstraints = false

    // dragging init
    registerForDraggedTypes([.nsFilenames, .nsURL, .string])
  }

  convenience init(player: PlayerCore) {
    self.init(frame: NSRect(origin: CGPointZero, size: AppData.minVideoSize), player: player)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: De-Init

  /// Uninitialize this view.
  ///
  /// This method will stop drawing and free the mpv render context. This is done before sending a quit command to mpv.
  /// - Important: Once mpv has been instructed to quit accessing the mpv core can result in a crash, therefore locks must be
  ///     used to coordinate uninitializing the view so that other threads do not attempt to use the mpv core while it is shutting down.
  func uninit() {
    log.verbose("VideoView uninit start")
    guard player.mpv.lockAndSetOpenGLContext() else { return }
    defer { player.mpv.unlockOpenGLContext() }
    $isUninited.withLock() { [self] isUninited in
      guard !isUninited else { 
        log.verbose("VideoView uninit already done, skipping")
        return
      }
      isUninited = true
      
      stopDisplayLink()
      player.mpv.mpvUninitRendering()
      log.verbose("VideoView uninit done")
    }
  }

  deinit {
    uninit()
  }

  /// Called when property `self.wantsLayer` is set to `true`.
  override func makeBackingLayer() -> CALayer {
    let layer = GLVideoLayer(self)
    return layer
  }

  override func draw(_ dirtyRect: NSRect) {
    // do nothing
  }

  /// Returns `true` if screenScaleFactor changed
  @discardableResult
  func refreshContentsScale() -> Bool {
    guard let window else { return false }
    guard player.isActive else { return false }
    let oldScaleFactor = videoLayer.contentsScale
    let newScaleFactor = window.backingScaleFactor
    if oldScaleFactor != newScaleFactor {
      log.verbose("Window backingScaleFactor changed: \(oldScaleFactor) → \(newScaleFactor)")
      videoLayer.contentsScale = newScaleFactor
      return true
    }
    log.verbose("No change to window backingScaleFactor (\(oldScaleFactor))")
    return false
  }

  func refreshAll() {
    // Do not execute if hidden during restore! Some of these calls may cause the window to show
    guard player.windowController.loaded, player.isActive && !player.info.isRestoring else { return }
    updateDisplayLink()
    refreshContentsScale()
    refreshEdrMode()
  }

  // MARK: - Constraints

  struct VideoViewConstraints {
    let eqOffsetTop: NSLayoutConstraint
    let eqOffsetTrailing: NSLayoutConstraint
    let eqOffsetBottom: NSLayoutConstraint
    let eqOffsetLeading: NSLayoutConstraint

    // Use aspect ratio constraint + weak center constraints to improve the video resize animation when
    // tiling the window while lockViewportToVideoSize is enabled.
    // Previously the video would get squeezed during resize. This became more noticable with the introduction
    // of MacOS Sequoia 15.0.
    let centerX: NSLayoutConstraint
    let centerY: NSLayoutConstraint
    let aspectRatio: NSLayoutConstraint
  }

  private func addOrUpdate(_ existingConstraint: NSLayoutConstraint?,
                   _ attr: NSLayoutConstraint.Attribute, _ relation: NSLayoutConstraint.Relation, _ constant: CGFloat,
                   _ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
    let constraint: NSLayoutConstraint
    if let existingConstraint {
      constraint = existingConstraint
      constraint.animateToConstant(constant)
    } else {
      constraint = NSLayoutConstraint(item: self, attribute: attr, relatedBy: relation, toItem: superview!,
                                      attribute: attr, multiplier: 1, constant: constant)
    }
    constraint.priority = priority
    return constraint
  }

  private func rebuildConstraints(top: CGFloat = 0, trailing: CGFloat = 0, bottom: CGFloat = 0, leading: CGFloat = 0,
                                  aspectMultiplier: CGFloat,
                                  eqIsActive: Bool = true, eqPriority: NSLayoutConstraint.Priority,
                                  centerIsActive: Bool = true, centerPriority: NSLayoutConstraint.Priority,
                                  aspectIsActive: Bool = true, aspectPriority: NSLayoutConstraint.Priority) {
    guard let superview else {
      // Should not get here
      log.error("Cannot rebuild constraints for videoView: it has no superview!")
      return
    }
    var existing = self.videoViewConstraints
    self.videoViewConstraints = nil

    var newCenterX: NSLayoutConstraint
    var newCenterY: NSLayoutConstraint
    let newAspect: NSLayoutConstraint
    if let existing {
      newCenterX = existing.centerX
      newCenterY = existing.centerY
      if existing.aspectRatio.isActive != aspectIsActive || aspectMultiplier != existing.aspectRatio.multiplier {
        existing.aspectRatio.isActive = false
        newAspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: aspectMultiplier, constant: 0)
      } else {
        newAspect = existing.aspectRatio
      }
    } else {
      newCenterX = centerXAnchor.constraint(equalTo: superview.centerXAnchor)
      newCenterY = centerYAnchor.constraint(equalTo: superview.centerYAnchor)
      newAspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: aspectMultiplier, constant: 0)
    }
    newCenterX.priority = centerPriority
    newCenterY.priority = centerPriority
    newAspect.priority = aspectPriority

    let newConstraints = VideoViewConstraints(
      eqOffsetTop: addOrUpdate(existing?.eqOffsetTop, .top, .equal, top, eqPriority),
      eqOffsetTrailing: addOrUpdate(existing?.eqOffsetTrailing, .trailing, .equal, trailing, eqPriority),
      eqOffsetBottom: addOrUpdate(existing?.eqOffsetBottom, .bottom, .equal, bottom, eqPriority),
      eqOffsetLeading: addOrUpdate(existing?.eqOffsetLeading, .leading, .equal, leading, eqPriority),

      centerX: newCenterX,
      centerY: newCenterY,
      aspectRatio: newAspect
    )
    existing = nil
    videoViewConstraints = newConstraints

    newConstraints.eqOffsetTop.isActive = eqIsActive
    newConstraints.eqOffsetTrailing.isActive = eqIsActive
    newConstraints.eqOffsetBottom.isActive = eqIsActive
    newConstraints.eqOffsetLeading.isActive = eqIsActive
    newConstraints.centerX.isActive = centerIsActive
    newConstraints.centerY.isActive = centerIsActive
    newConstraints.aspectRatio.isActive = aspectIsActive
    superview.needsLayout = true
  }

  func apply(_ geometry: PWinGeometry?) {
    assert(DispatchQueue.isExecutingIn(.main))

    guard player.windowController.pipStatus == .notInPIP else {
      log.verbose("VideoView: currently in PiP; ignoring request to set viewportMargin constraints")
      return
    }

    let margins: MarginQuad
    let videoAspect: Double
    let aspectPriority: NSLayoutConstraint.Priority = .required
    let eqPriority: NSLayoutConstraint.Priority = .init(499)

    if let geometry {
      if log.isTraceEnabled { log.trace("VideoView: updating viewportMargin constraints to \(geometry.viewportMargins)") }

      margins = geometry.viewportMargins
      videoAspect = geometry.videoAspect

    } else {
      log.trace("VideoView: zeroing out viewportMargin constraints")

      margins = .zero
      videoAspect = -1
    }

    rebuildConstraints(top: margins.top,
                       trailing: -margins.trailing,
                       bottom: -margins.bottom,
                       leading: margins.leading,
                       aspectMultiplier: videoAspect,
                       eqIsActive: true, eqPriority: eqPriority,
                       centerIsActive: true, centerPriority: .defaultLow,
                       aspectIsActive: videoAspect > 0.0, aspectPriority: aspectPriority)
  }

  // MARK: - Mouse events

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }

  /// In native full screen, `VideoView` receives mouse events instead of the window, so it is necessary to forward them
  /// to the window controller for handling.
  override func mouseDown(with event: NSEvent) {
    player.windowController.mouseDown(with: event)
    super.mouseDown(with: event)
  }

  /// Workaround for issue #4183, Cursor remains visible after resuming playback with the touchpad using secondary click
  ///
  /// See `PlayerWindowController.workaroundCursorDefect` and the issue for details on this workaround.
  override func rightMouseDown(with event: NSEvent) {
    player.windowController.rightMouseDown(with: event)
    super.rightMouseDown(with: event)
  }

  /// Workaround for issue #3211, Legacy fullscreen is broken (11.0.1)
  ///
  /// Changes in Big Sur broke the legacy full screen feature. The `PlayerWindowController` method `legacyAnimateToWindowed`
  /// had to be changed to get this feature working again. Under Big Sur that method now calls the AppKit method
  /// `window.styleMask.insert(.titled)`. This is a part of restoring the window's style mask to the way it was before entering
  /// full screen mode. A side effect of restoring the window's title is that AppKit stops calling `PlayerWindowController.mouseUp`.
  /// This appears to be a defect in the Cocoa framework. See the issue for details. As a workaround the mouse up event is caught in
  /// the view which then calls the window controller's method.
  override func mouseUp(with event: NSEvent) {
    // Only check for Big Sur or greater, not if the preference use legacy full screen is enabled as
    // that can be changed while running and once the window title has been removed and added back
    // AppKit malfunctions from then on. The check for running under Big Sur or later isn't really
    // needed as it would be fine to always call the controller. The check merely makes it clear
    // that this is only needed due to macOS changes starting with Big Sur.
    if #available(macOS 11, *) {
      player.windowController.mouseUp(with: event)
    } else {
      super.mouseUp(with: event)
    }
  }

  // MARK: - Drag and drop

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    return player.acceptFromPasteboard(sender)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return player.openFromPasteboard(sender)
  }

  // MARK: - Display link

  /// Returns a [Core Video](https://developer.apple.com/documentation/corevideo) display link.
  ///
  /// If a display link has already been created then that link will be returned, otherwise a display link will be created and returned.
  ///
  /// - Note: Issue [#4520](https://github.com/iina/iina/issues/4520) reports a case where it appears the call to
  ///[CVDisplayLinkCreateWithActiveCGDisplays](https://developer.apple.com/documentation/corevideo/1456863-cvdisplaylinkcreatewithactivecgd) is failing. In case that failure is
  ///encountered again this method is careful to log any failure and include the [result code](https://developer.apple.com/documentation/corevideo/1572713-result_codes) in the alert displayed
  /// by `Logger.fatal`.
  /// - Returns: A [CVDisplayLink](https://developer.apple.com/documentation/corevideo/cvdisplaylink-k0k).
  private func obtainDisplayLink() -> CVDisplayLink {
    if let link = link { return link }
    log.verbose("Obtaining DisplayLink")
    let result = CVDisplayLinkCreateWithActiveCGDisplays(&link)
    checkResult(result, "CVDisplayLinkCreateWithActiveCGDisplays")
    guard let link = link else {
      Logger.fatal("Cannot create display link: \(codeToString(result)) (\(result))")
    }
    return link
  }

  func startDisplayLink() {
    let link = obtainDisplayLink()

    guard !CVDisplayLinkIsRunning(link) else { return }
    updateDisplayLink()

    checkResult(CVDisplayLinkSetOutputCallback(link, displayLinkCallback, mutableRawPointerOf(obj: self)),
                "CVDisplayLinkSetOutputCallback")
    checkResult(CVDisplayLinkStart(link), "CVDisplayLinkStart")
    log.verbose("Started DisplayLink")
  }

  func stopDisplayLink() {
    guard let link = link, CVDisplayLinkIsRunning(link) else { return }
    checkResult(CVDisplayLinkStop(link), "CVDisplayLinkStop")
    log.verbose("DisplayLink stopped")
  }

  /// This should be called at start or if the window has changed displays
  func updateDisplayLink() {
    guard let window = window, let link = link, let screen = window.screen else { return }
    guard !player.isStopping else { return }
    let displayId = screen.displayId

    // Do nothing if on the same display
    guard currentDisplay != displayId else {
      if log.isTraceEnabled {
        log.trace("No need to update DisplayLink; currentDisplayID (\(displayId)) is unchanged")
      }
      return
    }
    log.verbose("Updating DisplayLink for display: \(displayId)")
    currentDisplay = displayId

    checkResult(CVDisplayLinkSetCurrentCGDisplay(link, displayId), "CVDisplayLinkSetCurrentCGDisplay")
    let actualData = CVDisplayLinkGetActualOutputVideoRefreshPeriod(link)
    let nominalData = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
    var actualFps: Double = 0

    if (nominalData.flags & Int32(CVTimeFlags.isIndefinite.rawValue)) < 1 {
      let nominalFps = Double(nominalData.timeScale) / Double(nominalData.timeValue)

      if actualData > 0 {
        actualFps = 1/actualData
      }

      if abs(actualFps - nominalFps) > 1 {
        log.debug("Falling back to nominal display refresh rate: \(nominalFps) from \(actualFps)")
        actualFps = nominalFps
      }
    } else {
      log.debug("Falling back to standard display refresh rate: 60 from \(actualFps)")
      actualFps = 60
    }
    player.mpv.setDouble(MPVOption.Video.displayFpsOverride, actualFps)

    log.verbose("Done updating DisplayLink")
  }

  // MARK: - Reducing Energy Use

  /// Starts the display link if it has been stopped in order to save energy.
  func displayActive(temporary: Bool = false) {
    log.trace("VideoView displayActive")
    assert(DispatchQueue.isExecutingIn(.main))
    if !temporary {
      displayIdleTimer?.invalidate()
    }
    startDisplayLink()
    if temporary {
      displayIdle()
    }
  }

  /// Reduces energy consumption when the display link does not need to be running.
  ///
  /// Adherence to energy efficiency best practices requires that IINA be absolutely idle when there is no reason to be performing any
  /// processing, such as when playback is paused. The [CVDisplayLink](https://developer.apple.com/documentation/corevideo/cvdisplaylink-k0k)
  /// is a high-priority thread that runs at the refresh rate of a display. If the display is not being updated it is desirable to stop the
  /// display link in order to not waste energy on needless processing.
  ///
  /// However, IINA will pause playback for short intervals when performing certain operations. In such cases it does not make sense to
  /// shutdown the display link only to have to immediately start it again. To avoid this a `Timer` is used to delay shutting down the
  /// display link. If playback becomes active again before the timer has fired then the `Timer` will be invalidated and the display link
  /// will not be shutdown.
  ///
  /// - Note: In addition to playback the display link must be running for operations such seeking, stepping and entering and leaving
  ///         full screen mode.
  func displayIdle() {
    log.trace("VideoView displayIdle")
    assert(DispatchQueue.isExecutingIn(.main))
    displayIdleTimer?.invalidate()
    // The time of 6 seconds was picked to match up with the time QuickTime delays once playback is
    // paused before stopping audio. As mpv does not provide an event indicating a frame step has
    // completed the time used must not be too short or will catch mpv still drawing when stepping.
    displayIdleTimer = Timer(timeInterval: 6.0, target: self, selector: #selector(makeDisplayIdle), userInfo: nil, repeats: false)
    // Not super picky about timeout; favor efficiency
    displayIdleTimer?.tolerance = 0.5
    RunLoop.current.add(displayIdleTimer!, forMode: .default)
  }

  @objc func makeDisplayIdle() {
    videoLayer.exitAsynchronousMode()
    guard player.mpv.lockAndSetOpenGLContext() else { return }
    defer { player.mpv.unlockOpenGLContext() }
    $isUninited.withLock() { [self] isUninited in
      guard !isUninited else { return }
      videoLayer.videoView.stopDisplayLink()
    }
  }

  // MARK: - Color

  func setICCProfile() {
    let screenColorSpace = player.windowController.window?.screen?.colorSpace
    if !Preference.bool(for: .loadIccProfile) {
      logHDR.verbose("Not using ICC profile due to user preference")
    } else if let screenColorSpace {
      logHDR.verbose("Configuring auto ICC profile")
      // This MUST be locked via openGLContext

      guard player.mpv.lockAndSetOpenGLContext() else { return }
      defer { player.mpv.unlockOpenGLContext() }
      $isUninited.withLock() { [self] isUninited in
        guard !isUninited else { return }
        setRenderICCProfile(screenColorSpace)
      }

    } else {
      logHDR.warn("Cannot set auto ICC profile; no screen color space")
    }

    let sdrColorSpace = screenColorSpace?.cgColorSpace ?? VideoView.SRGB
    if videoLayer.colorspace != sdrColorSpace {
      let name = sdrColorSpace.name as? String ?? screenColorSpace?.localizedName ?? "Unspecified"
      logHDR.debug("Setting layer color space to \(name)")
      videoLayer.colorspace = sdrColorSpace
    }

    let useAutoICC = Preference.bool(for: .loadIccProfile) &&  screenColorSpace != nil
    player.mpv.setFlag(MPVOption.GPURendererOptions.iccProfileAuto, useAutoICC)

    player.mpv.setString(MPVOption.GPURendererOptions.targetTrc, "auto")
    player.mpv.setString(MPVOption.GPURendererOptions.targetPrim, "auto")
    player.mpv.setString(MPVOption.GPURendererOptions.targetPeak, "auto")
    player.mpv.setString(MPVOption.GPURendererOptions.toneMapping, "auto")
    player.mpv.setString(MPVOption.GPURendererOptions.toneMappingParam, "default")
    player.mpv.setFlag(MPVOption.Screenshot.screenshotTagColorspace, false)
  }

  /// Set an ICC profile for use with the mpv [icc-profile-auto](https://mpv.io/manual/stable/#options-icc-profile-auto)
  /// option.
  ///
  /// This method fulfills the mpv requirement that applications using libmpv with the render API provide the ICC profile via
  /// `MPV_RENDER_PARAM_ICC_PROFILE` in order for the `--icc-profile-auto` option to work. The ICC profile data will not
  /// be used by mpv unless the option is enabled.
  ///
  /// The IINA `Load ICC profile` setting is tied to the `--icc-profile-auto` option. This allows users to override IINA using
  /// the [--icc-profile](https://mpv.io/manual/stable/#options-icc-profile) option.
  private func setRenderICCProfile(_ profile: NSColorSpace) {
    guard let renderContext = player.mpv.mpvRenderContext else { return }
    guard var iccData = profile.iccProfileData else {
      let name = profile.localizedName ?? "unnamed"
      player.log.warn("Color space \(name) does not contain ICC profile data")
      return
    }
    iccData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
      guard let baseAddress = ptr.baseAddress, ptr.count > 0 else { return }

      let u8Ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
      var icc = mpv_byte_array(data: u8Ptr, size: ptr.count)
      withUnsafeMutableBytes(of: &icc) { (ptr: UnsafeMutableRawBufferPointer) in
        let params = mpv_render_param(type: MPV_RENDER_PARAM_ICC_PROFILE, data: ptr.baseAddress)
        mpv_render_context_set_parameter(renderContext, params)
      }
    }
  }


  // MARK: - Error Logging

  /// Check the result of calling a [Core Video](https://developer.apple.com/documentation/corevideo) method.
  ///
  /// If the result code is not [kCVReturnSuccess](https://developer.apple.com/documentation/corevideo/kcvreturnsuccess)
  /// then a warning message will be logged. Failures are only logged because previously the result was not checked. We want to see if
  /// calls have been failing before taking any action other than logging.
  /// - Note: Error checking was added in response to issue [#4520](https://github.com/iina/iina/issues/4520)
  ///         where a core video method unexpectedly failed.
  /// - Parameters:
  ///   - result: The [CVReturn](https://developer.apple.com/documentation/corevideo/cvreturn)
  ///           [result code](https://developer.apple.com/documentation/corevideo/1572713-result_codes)
  ///           returned by the core video method.
  ///   - method: The core video method that returned the result code.
  private func checkResult(_ result: CVReturn, _ method: String) {
    guard result != kCVReturnSuccess else { return }
    log.warn("Core video method \(method) returned: \(codeToString(result)) (\(result))")
  }

  /// Return a string describing the given [CVReturn](https://developer.apple.com/documentation/corevideo/cvreturn)
  ///           [result code](https://developer.apple.com/documentation/corevideo/1572713-result_codes).
  ///
  /// What is needed is an API similar to `strerr` for a `CVReturn` code. A search of Apple documentation did not find such a
  /// method.
  /// - Parameter code: The [CVReturn](https://developer.apple.com/documentation/corevideo/cvreturn)
  ///           [result code](https://developer.apple.com/documentation/corevideo/1572713-result_codes)
  ///           returned by a core video method.
  /// - Returns: A description of what the code indicates.
  private func codeToString(_ code: CVReturn) -> String {
    switch code {
    case kCVReturnSuccess:
      return "Function executed successfully without errors"
    case kCVReturnInvalidArgument:
      return "At least one of the arguments passed in is not valid. Either out of range or the wrong type"
    case kCVReturnAllocationFailed:
      return "The allocation for a buffer or buffer pool failed. Most likely because of lack of resources"
    case kCVReturnInvalidDisplay:
      return "A CVDisplayLink cannot be created for the given DisplayRef"
    case kCVReturnDisplayLinkAlreadyRunning:
      return "The CVDisplayLink is already started and running"
    case kCVReturnDisplayLinkNotRunning:
      return "The CVDisplayLink has not been started"
    case kCVReturnDisplayLinkCallbacksNotSet:
      return "The output callback is not set"
    case kCVReturnInvalidPixelFormat:
      return "The requested pixelformat is not supported for the CVBuffer type"
    case kCVReturnInvalidSize:
      return "The requested size (most likely too big) is not supported for the CVBuffer type"
    case kCVReturnInvalidPixelBufferAttributes:
      return "A CVBuffer cannot be created with the given attributes"
    case kCVReturnPixelBufferNotOpenGLCompatible:
      return "The Buffer cannot be used with OpenGL as either its size, pixelformat or attributes are not supported by OpenGL"
    case kCVReturnPixelBufferNotMetalCompatible:
      return "The Buffer cannot be used with Metal as either its size, pixelformat or attributes are not supported by Metal"
    case kCVReturnWouldExceedAllocationThreshold:
      return """
        The allocation request failed because it would have exceeded a specified allocation threshold \
        (see kCVPixelBufferPoolAllocationThresholdKey)
        """
    case kCVReturnPoolAllocationFailed:
      return "The allocation for the buffer pool failed. Most likely because of lack of resources. Check if your parameters are in range"
    case kCVReturnInvalidPoolAttributes:
      return "A CVBufferPool cannot be created with the given attributes"
    case kCVReturnRetry:
      return "a scan hasn't completely traversed the CVBufferPool due to a concurrent operation. The client can retry the scan"
    default:
      return "Unrecognized core video return code"
    }
  }
}

// MARK: - HDR

extension VideoView {

  func refreshEdrMode() {
    guard player.windowController.loaded else { return }
    let isRestoring = player.info.isRestoring
    // Do not execute if hidden during restore! Some of these calls may cause the window to show
    guard player.isActive, !isRestoring else { return }
    guard player.info.isFileLoaded else { return }
    guard let displayId = currentDisplay else { return }

    log.debug("Refreshing HDR @ screen \(NSScreen.forDisplayID(displayId)?.screenID.quoted ?? "nil"): ")
    let edrEnabled = requestEdrMode()
    let edrAvailable = edrEnabled != false
    if player.info.hdrAvailable != edrAvailable {
      player.windowController.quickSettingView.setHdrAvailability(to: edrAvailable)
    }
    if edrEnabled != true { setICCProfile() }
  }

  private func requestEdrMode() -> Bool? {
    guard let mpv = player.mpv else { return false }

    guard let primaries = mpv.getString(MPVProperty.videoParamsPrimaries), let gamma = mpv.getString(MPVProperty.videoParamsGamma) else {
      logHDR.debug("Video gamma and primaries not available")
      return false
    }
  
    let peak = mpv.getDouble(MPVProperty.videoParamsSigPeak)
    logHDR.debug("Video gamma=\(gamma), primaries=\(primaries), sig_peak=\(peak)")

    // HDR videos use a Hybrid Log Gamma (HLG) or a Perceptual Quantization (PQ) transfer function.
    guard gamma == "hlg" || gamma == "pq" else { return false }

    let name: CFString
    switch primaries {
    case "display-p3":
      if #available(macOS 10.15.4, *) {
        name = CGColorSpace.displayP3_PQ
      } else {
        name = CGColorSpace.displayP3_PQ_EOTF
      }

    case "bt.2020":
      if #available(macOS 11.0, *) {
        name = CGColorSpace.itur_2100_PQ
      } else if #available(macOS 10.15.4, *) {
        name = CGColorSpace.itur_2020_PQ
      } else {
        name = CGColorSpace.itur_2020_PQ_EOTF
      }

    case "bt.709":
      return false // SDR

    default:
      logHDR.warn("Unsupported color space: gamma=\(gamma) primaries=\(primaries)")
      return false
    }

    let maxRangeEDR = window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0
    guard maxRangeEDR > 1.0 else {
      logHDR.debug("HDR video was found but the display does not support EDR mode (maxEDR=\(maxRangeEDR))")
      return false
    }

    guard player.info.hdrEnabled else { return nil }

    logHDR.debug("Using HDR color space instead of ICC profile (maxEDR=\(maxRangeEDR))")
    videoLayer.colorspace = CGColorSpace(name: name)
    mpv.setFlag(MPVOption.GPURendererOptions.iccProfileAuto, false)
    mpv.setString(MPVOption.GPURendererOptions.targetPrim, primaries)
    // PQ videos will be display as it was, HLG videos will be converted to PQ
    mpv.setString(MPVOption.GPURendererOptions.targetTrc, "pq")
    mpv.setFlag(MPVOption.Screenshot.screenshotTagColorspace, true)

    if Preference.bool(for: .enableToneMapping) {
      var targetPeak = Preference.integer(for: .toneMappingTargetPeak)
      // If the target peak is set to zero then IINA attempts to determine peak brightness of the
      // display.
      if targetPeak == 0 {
        if let displayInfo = CoreDisplay_DisplayCreateInfoDictionary(currentDisplay!)?.takeRetainedValue() as? [String: AnyObject] {
          logHDR.debug("Successfully obtained information about the display")
          // Prefer ReferencePeakHDRLuminance, which is reported by newer macOS versions.
          if let hdrLuminance = displayInfo["ReferencePeakHDRLuminance"] as? Int {
            logHDR.debug("Found ReferencePeakHDRLuminance: \(hdrLuminance)")
            targetPeak = hdrLuminance
          } else if let hdrLuminance = displayInfo["DisplayBacklight"] as? Int {
            // We know macOS Catalina uses this key.
            logHDR.debug("Found DisplayBacklight: \(hdrLuminance)")
            targetPeak = hdrLuminance
          } else {
            logHDR.debug("Didn't find ReferencePeakHDRLuminance or DisplayBacklight, assuming HDR400")
            logHDR.debug("Display info dictionary: \(displayInfo)")
            targetPeak = 400
          }
        } else {
          logHDR.warn("Unable to obtain display information, assuming HDR400")
          targetPeak = 400
        }
      }
      let algorithm = Preference.ToneMappingAlgorithmOption(rawValue: Preference.integer(for: .toneMappingAlgorithm))?.mpvString
      ?? Preference.ToneMappingAlgorithmOption.defaultValue.mpvString

      logHDR.debug("Will enable tone mapping: target-peak=\(targetPeak) algorithm=\(algorithm)")
      mpv.setInt(MPVOption.GPURendererOptions.targetPeak, targetPeak)
      mpv.setString(MPVOption.GPURendererOptions.toneMapping, algorithm)
    } else {
      mpv.setString(MPVOption.GPURendererOptions.targetPeak, "auto")
      mpv.setString(MPVOption.GPURendererOptions.toneMapping, "")
    }
    return true
  }
}

fileprivate func displayLinkCallback(
  _ displayLink: CVDisplayLink, _ inNow: UnsafePointer<CVTimeStamp>,
  _ inOutputTime: UnsafePointer<CVTimeStamp>,
  _ flagsIn: CVOptionFlags,
  _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
  _ context: UnsafeMutableRawPointer?) -> CVReturn {
    let videoView = unsafeBitCast(context, to: VideoView.self)
    videoView.$isUninited.withLock() { isUninited in
      guard !isUninited else { return }
      videoView.player.mpv.mpvReportSwap()
    }
    return kCVReturnSuccess
  }
