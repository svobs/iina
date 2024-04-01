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

  lazy var hdrSubsystem = Logger.makeSubsystem("hdr")

  static let SRGB = CGColorSpaceCreateDeviceRGB()

  // MARK: - Attributes

  // MARK: - Init

  override init(frame: CGRect) {
    super.init(frame: frame)
    wantsLayer = true

    translatesAutoresizingMaskIntoConstraints = false

    // dragging init
    registerForDraggedTypes([.nsFilenames, .nsURL, .string])
  }

  convenience init(player: PlayerCore) {
    self.init(frame: NSRect(origin: CGPointZero, size: AppData.minVideoSize))
    self.player = player
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Uninitialize this view.
  ///
  /// This method will stop drawing and free the mpv render context. This is done before sending a quit command to mpv.
  /// - Important: Once mpv has been instructed to quit accessing the mpv core can result in a crash, therefore locks must be
  ///     used to coordinate uninitializing the view so that other threads do not attempt to use the mpv core while it is shutting down.
  func uninit() {
    $isUninited.withLock() { [self] isUninited in
      guard !isUninited else { return }
      isUninited = true

      stopDisplayLink()
      player.mpv.mpvUninitRendering()
    }
  }

  deinit {
    uninit()
  }

  override func makeBackingLayer() -> CALayer {
    let layer = GLVideoLayer(videoView: self)
    layer.colorspace = VideoView.SRGB
    return layer
  }

  override func draw(_ dirtyRect: NSRect) {
    // do nothing
  }

  /// Returns `true` if screenScaleFactor changed
  @discardableResult
  func refreshContentsScale() -> Bool {
    guard let window else { return false }
    let oldScaleFactor = videoLayer.contentsScale
    let newScaleFactor = window.screenScaleFactor
    if oldScaleFactor != newScaleFactor {
      log.verbose("ScreenScaleFactor changed from \(oldScaleFactor) to \(newScaleFactor)")
      videoLayer.contentsScale = newScaleFactor
      return true
    }
    return false
  }

  // MARK: - VideoView Constraints

  struct VideoViewConstraints {
    let eqOffsetTop: NSLayoutConstraint
    let eqOffsetTrailing: NSLayoutConstraint
    let eqOffsetBottom: NSLayoutConstraint
    let eqOffsetLeading: NSLayoutConstraint

    // Shouldn't really need these anymore. But leave them in at low priority as a backup if something unexpected comes up
    let centerX: NSLayoutConstraint
    let centerY: NSLayoutConstraint

    func setActive(eq: Bool = true, center: Bool = true, aspect: Bool = true) {
      eqOffsetTop.isActive = eq
      eqOffsetTrailing.isActive = eq
      eqOffsetBottom.isActive = eq
      eqOffsetLeading.isActive = eq

      centerX.isActive = center
      centerY.isActive = center
    }
  }

  private func addOrUpdate(_ existingConstraint: NSLayoutConstraint?,
                   _ attr: NSLayoutConstraint.Attribute, _ relation: NSLayoutConstraint.Relation, _ constant: CGFloat,
                   _ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
    let constraint: NSLayoutConstraint
    if let existingConstraint {
      constraint = existingConstraint
      constraint.animateToConstant(constant)
    } else {
      constraint = existingConstraint ?? NSLayoutConstraint(item: self, attribute: attr, relatedBy: relation, toItem: superview!,
                                                            attribute: attr, multiplier: 1, constant: constant)
    }
    constraint.priority = priority
    return constraint
  }

  private func rebuildConstraints(top: CGFloat = 0, trailing: CGFloat = 0, bottom: CGFloat = 0, leading: CGFloat = 0,
                                  eqIsActive: Bool = true, eqPriority: NSLayoutConstraint.Priority,
                                  centerIsActive: Bool = true, centerPriority: NSLayoutConstraint.Priority) {
    var existing = self.videoViewConstraints
    self.videoViewConstraints = nil

    let newConstraints = VideoViewConstraints(
      eqOffsetTop: addOrUpdate(existing?.eqOffsetTop, .top, .equal, top, eqPriority),
      eqOffsetTrailing: addOrUpdate(existing?.eqOffsetTrailing, .trailing, .equal, trailing, eqPriority),
      eqOffsetBottom: addOrUpdate(existing?.eqOffsetBottom, .bottom, .equal, bottom, eqPriority),
      eqOffsetLeading: addOrUpdate(existing?.eqOffsetLeading, .leading, .equal, leading, eqPriority),

      centerX: existing?.centerX ?? centerXAnchor.constraint(equalTo: superview!.centerXAnchor),
      centerY: existing?.centerY ?? centerYAnchor.constraint(equalTo: superview!.centerYAnchor)
    )
    newConstraints.centerX.priority = centerPriority
    newConstraints.centerY.priority = centerPriority
    existing = nil
    videoViewConstraints = newConstraints

    newConstraints.setActive(eq: eqIsActive, center: centerIsActive)
  }

  private func setFixedOffsetConstraints(margins: BoxQuad) {

    log.verbose("Constraining videoView for fixed offsets only: \(margins.top) \(margins.trailing) \(margins.bottom) \(margins.leading)")
    // Use only EQ. Remove all other constraints
    rebuildConstraints(top: margins.top, trailing: -margins.trailing, bottom: -margins.bottom, leading: margins.leading,
                       eqIsActive: true, eqPriority: .required,
                       centerIsActive: true, centerPriority: .defaultLow)

    window?.layoutIfNeeded()
  }

  func apply(_ geometry: PWGeometry?) {
    guard player.windowController.pipStatus == .notInPIP else {
      log.verbose("VideoView: currently in PiP; ignoring request to set viewportMargin constraints")
      return
    }
    if let geometry = geometry {
      if log.isTraceEnabled {
        log.verbose("VideoView: updating viewportMargin constraints to \(geometry.viewportMargins)")
      }
      setFixedOffsetConstraints(margins: geometry.viewportMargins)
    } else {
      if log.isTraceEnabled {
        log.verbose("VideoView: zeroing out viewportMargin constraints")
      }
      setFixedOffsetConstraints(margins: .zero)
    }
    layoutSubtreeIfNeeded()
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

    var canProceed = true
    $isUninited.withLock() { isUninited in
      canProceed = !isUninited
    }
    guard canProceed else { return }
    guard !CVDisplayLinkIsRunning(link) else { return }
    updateDisplayLink()

    checkResult(CVDisplayLinkSetOutputCallback(link, displayLinkCallback, mutableRawPointerOf(obj: self)),
                "CVDisplayLinkSetOutputCallback")
    checkResult(CVDisplayLinkStart(link), "CVDisplayLinkStart")
  }

  func stopDisplayLink() {
    guard let link = link, CVDisplayLinkIsRunning(link) else { return }
    checkResult(CVDisplayLinkStop(link), "CVDisplayLinkStop")
    log.verbose("DisplayLink stopped")
  }

  /// This should be called at start or if the window has changed displays
  func updateDisplayLink() {
    guard let window = window, let link = link, let screen = window.screen else { return }
    let displayId = screen.displayId

    // Do nothing if on the same display
    if (currentDisplay == displayId) {
      log.verbose("No need to update DisplayLink; currentDisplayID (\(displayId)) is unchanged")
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
    player.mpv.setDouble(MPVOption.Video.overrideDisplayFps, actualFps)

    if #available(macOS 10.15, *) {
      refreshEdrMode()
    } else {
      setICCProfile(displayId)
    }
  }

  // MARK: - Reducing Energy Use

  /// Starts the display link if it has been stopped in order to save energy.
  func displayActive(temporary: Bool = false) {
    log.trace("VideoView displayActive")
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
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
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
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
    videoLayer.videoView.stopDisplayLink()
    videoLayer.exitAsynchronousMode()
  }

  // MARK: - Color

  func setICCProfile(_ displayId: UInt32) {
    if !Preference.bool(for: .loadIccProfile) {
      hdrSubsystem.debug("Not using ICC due to user preference")
      player.mpv.setString(MPVOption.GPURendererOptions.iccProfile, "")
    } else {
      hdrSubsystem.debug("Loading ICC profile")
      typealias ProfileData = (uuid: CFUUID, profileUrl: URL?)
      guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayId)?.takeRetainedValue() else { return }

      var argResult: ProfileData = (uuid, nil)
      withUnsafeMutablePointer(to: &argResult) { data in
        ColorSyncIterateDeviceProfiles({ (dict: CFDictionary?, ptr: UnsafeMutableRawPointer?) -> Bool in
          if let info = dict as? [String: Any], let current = info["DeviceProfileIsCurrent"] as? Int {
            let deviceID = info["DeviceID"] as! CFUUID
            let ptr = ptr!.bindMemory(to: ProfileData.self, capacity: 1)
            let uuid = ptr.pointee.uuid

            if current == 1, deviceID == uuid, let profileURL = info["DeviceProfileURL"] as? URL {
              ptr.pointee.profileUrl = profileURL
              return false
            }
          }
          return true
        }, data)
      }

      if let iccProfilePath = argResult.profileUrl?.path, FileManager.default.fileExists(atPath: iccProfilePath) {
        player.mpv.setString(MPVOption.GPURendererOptions.iccProfile, iccProfilePath)
      }
    }

    if videoLayer.colorspace != VideoView.SRGB {
      videoLayer.colorspace = VideoView.SRGB
      videoLayer.wantsExtendedDynamicRangeContent = false
      player.mpv.setString(MPVOption.GPURendererOptions.targetTrc, "auto")
      player.mpv.setString(MPVOption.GPURendererOptions.targetPrim, "auto")
      player.mpv.setString(MPVOption.GPURendererOptions.targetPeak, "auto")
      player.mpv.setString(MPVOption.GPURendererOptions.toneMapping, "auto")
      player.mpv.setString(MPVOption.GPURendererOptions.toneMappingParam, "default")
      player.mpv.setFlag(MPVOption.Screenshot.screenshotTagColorspace, false)
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

@available(macOS 10.15, *)
extension VideoView {
  func refreshEdrMode() {
    guard player.windowController.loaded else { return }
    guard player.info.isFileLoaded else { return }
    guard let displayId = currentDisplay else { return }
    if let screen = self.window?.screen {
      screen.log("Refreshing HDR for \(player.subsystem.rawValue) @ screen\(displayId): ")
    } else {
      log.verbose("Refreshing HDR for \(player.subsystem.rawValue)")
    }
    let edrEnabled = requestEdrMode()
    let edrAvailable = edrEnabled != false
    if player.info.hdrAvailable != edrAvailable {
      player.windowController.quickSettingView.setHdrAvailability(to: edrAvailable)
    }
    if edrEnabled != true { setICCProfile(displayId) }
  }

  func requestEdrMode() -> Bool? {
    guard let mpv = player.mpv else { return false }

    guard let primaries = mpv.getString(MPVProperty.videoGeoPrimaries), let gamma = mpv.getString(MPVProperty.videoGeoGamma) else {
      hdrSubsystem.debug("HDR primaries and gamma not available")
      return false
    }
  
    let peak = mpv.getDouble(MPVProperty.videoGeoSigPeak)
    hdrSubsystem.debug("HDR gamma=\(gamma), primaries=\(primaries), sig_peak=\(peak)")

    var name: CFString? = nil
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
      hdrSubsystem.debug("Unknown HDR color space information gamma=\(gamma) primaries=\(primaries)")
      return false
    }

    guard (window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0) > 1.0 else {
      hdrSubsystem.debug("HDR video was found but the display does not support EDR mode")
      return false
    }

    guard player.info.hdrEnabled else { return nil }

    if videoLayer.colorspace?.name == name {
      hdrSubsystem.debug("HDR mode already enabled, skipping")
      return true
    }

    hdrSubsystem.debug("Will activate HDR color space instead of using ICC profile")

    videoLayer.wantsExtendedDynamicRangeContent = true
    videoLayer.colorspace = CGColorSpace(name: name!)
    mpv.setString(MPVOption.GPURendererOptions.iccProfile, "")
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
          hdrSubsystem.debug("Successfully obtained information about the display")
          // Prefer ReferencePeakHDRLuminance, which is reported by newer macOS versions.
          if let hdrLuminance = displayInfo["ReferencePeakHDRLuminance"] as? Int {
            hdrSubsystem.debug("Found ReferencePeakHDRLuminance: \(hdrLuminance)")
            targetPeak = hdrLuminance
          } else if let hdrLuminance = displayInfo["DisplayBacklight"] as? Int {
            // We know macOS Catalina uses this key.
            hdrSubsystem.debug("Found DisplayBacklight: \(hdrLuminance)")
            targetPeak = hdrLuminance
          } else {
            hdrSubsystem.debug("Didn't find ReferencePeakHDRLuminance or DisplayBacklight, assuming HDR400")
            hdrSubsystem.debug("Display info dictionary: \(displayInfo)")
            targetPeak = 400
          }
        } else {
          hdrSubsystem.warn("Unable to obtain display information, assuming HDR400")
          targetPeak = 400
        }
      }
      let algorithm = Preference.ToneMappingAlgorithmOption(rawValue: Preference.integer(for: .toneMappingAlgorithm))?.mpvString
      ?? Preference.ToneMappingAlgorithmOption.defaultValue.mpvString

      hdrSubsystem.debug("Will enable tone mapping target-peak=\(targetPeak) algorithm=\(algorithm)")
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
