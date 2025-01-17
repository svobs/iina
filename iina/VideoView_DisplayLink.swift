//
//  VideoView_DisplayLink.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

extension VideoView {
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
      log.trace{"No need to update DisplayLink; currentDisplayID (\(displayId)) is unchanged"}
      return
    }
    log.verbose{"Updating DisplayLink for displayID \(displayId)"}
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
    videoLayer.videoView.stopDisplayLink()
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
