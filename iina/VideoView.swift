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

  var displayIdleTimer: Timer?

  var videoViewConstraints: VideoViewConstraints? = nil

  private let logHDR: Logger.Subsystem

  static let SRGB = CGColorSpaceCreateDeviceRGB()

  // MARK: Init

  init(frame: CGRect, player: PlayerCore) {
    self.logHDR = Logger.makeSubsystem("hdr-\(player.label)")
    self.player = player
    super.init(frame: frame)

    translatesAutoresizingMaskIntoConstraints = false
    setContentCompressionResistancePriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .vertical)
    setContentHuggingPriority(.required, for: .horizontal)
    setContentHuggingPriority(.required, for: .vertical)

    // dragging init
    registerForDraggedTypes([.nsFilenames, .nsURL, .string])
  }

  convenience init(player: PlayerCore) {
    self.init(frame: .zero, player: player)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Called when property `self.wantsLayer` is set to `true`.
  override func makeBackingLayer() -> CALayer {
    let layer = GLVideoLayer(self)
    return layer
  }

  // MARK: De-Init

  deinit {
    uninit()
  }

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

  // MARK: - Video State

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
      log.verbose{"Window backingScaleFactor changed: \(oldScaleFactor) → \(newScaleFactor)"}
      videoLayer.contentsScale = newScaleFactor
      return true
    }
    log.verbose{"No change to window backingScaleFactor (\(oldScaleFactor))"}
    return false
  }

  func refreshAllVideoState() {
    // Do not execute if hidden during restore! Some of these calls may cause the window to show
    guard player.windowController.loaded, player.isActive && !player.isRestoring else { return }
    updateDisplayLink()
    refreshContentsScale()
    refreshEdrMode()
  }

  // MARK: - Color

  func setICCProfile() {
    let screenColorSpace = player.windowController.window?.screen?.colorSpace
    if !Preference.bool(for: .loadIccProfile) {
      logHDR.verbose("Not using ICC profile due to user preference")
    } else if let screenColorSpace {
      let name = screenColorSpace.localizedName ?? "unnamed"
      logHDR.verbose{"Using the ICC profile of color space \(name.quoted)"}
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
      logHDR.verbose{"Setting layer color space to \(name.quoted)"}
      videoLayer.colorspace = sdrColorSpace
      videoLayer.wantsExtendedDynamicRangeContent = false
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
      player.log.warn{"Color space \(name) does not contain ICC profile data"}
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

  // MARK: - HDR

  func refreshEdrMode() {
    guard player.windowController.loaded else { return }
    // Do not execute if hidden during restore! Some of these calls may cause the window to show
    guard player.isActive, !player.isRestoring else { return }
    guard player.info.isFileLoaded else { return }
    guard let displayId = currentDisplay else { return }

    log.debug{"Refreshing HDR @ screen \(NSScreen.forDisplayID(displayId)?.screenID.quoted ?? "nil")"}
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
      logHDR.debug{"Video gamma and primaries not available"}
      return false
    }
  
    let peak = mpv.getDouble(MPVProperty.videoParamsSigPeak)
    logHDR.debug{"Video gamma=\(gamma), primaries=\(primaries), sig_peak=\(peak)"}

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
      if #unavailable(macOS 10.15.4) {
        name = CGColorSpace.itur_2020_PQ_EOTF
      } else if #unavailable(macOS 11.0) {
        name = CGColorSpace.itur_2020_PQ
      } else {
        name = CGColorSpace.itur_2100_PQ
      }

    case "bt.709":
      return false // SDR

    default:
      logHDR.warn{"Unsupported color space: gamma=\(gamma) primaries=\(primaries)"}
      return false
    }

    let maxRangeEDR = window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0
    guard maxRangeEDR > 1.0 else {
      logHDR.debug{"HDR video was found but the display does not support EDR mode (maxEDR=\(maxRangeEDR))"}
      return false
    }

    guard player.info.hdrEnabled else { return nil }

    logHDR.debug{"Using HDR color space instead of ICC profile (maxEDR=\(maxRangeEDR))"}
    videoLayer.wantsExtendedDynamicRangeContent = true
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
          // Apple Silicon Macs use the key NonReferencePeakHDRLuminance.
          if let hdrLuminance = displayInfo["NonReferencePeakHDRLuminance"] as? Int {
            logHDR.debug("Found NonReferencePeakHDRLuminance: \(hdrLuminance)")
            targetPeak = hdrLuminance
          } else if let hdrLuminance = displayInfo["DisplayBacklight"] as? Int {
            // Intel Macs use the key DisplayBacklight.
            logHDR.debug("Found DisplayBacklight: \(hdrLuminance)")
            targetPeak = hdrLuminance
          } else {
            logHDR.debug("Didn't find NonReferencePeakHDRLuminance or DisplayBacklight, assuming HDR400")
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
