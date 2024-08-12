//
//  MPVController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import JavaScriptCore
import VideoToolbox

fileprivate let yes_str = "yes"
fileprivate let no_str = "no"

fileprivate let logEvents = false

/*
 * Change this variable to adjust threshold for *receiving* MPV_EVENT_LOG_MESSAGE messages.
 * NOTE: Lua keybindings require at *least* level "debug", so don't set threshold to be stricter than this level
 */
fileprivate let mpvLogSubscriptionLevel: String = MPVLogLevel.debug.description

fileprivate func errorString(_ code: Int32) -> String {
  return String(cString: mpv_error_string(code))
}

extension mpv_event_id: CustomStringConvertible {
  // Generated code from mpv is objc and does not have Swift's built-in enum name introspection.
  // We provide that here using mpv_event_name()
  public var description: String {
    get {
      String(cString: mpv_event_name(self))
    }
  }
}

extension mpv_event_end_file {
  // For help with debugging
  var reasonString: String {
    let reason = self.reason
    var reasonString: String
    switch reason {
    case MPV_END_FILE_REASON_EOF:
      reasonString = "EOF"
    case MPV_END_FILE_REASON_STOP:
      reasonString = "STOP"
    case MPV_END_FILE_REASON_QUIT:
      reasonString = "QUIT"
    case MPV_END_FILE_REASON_ERROR:
      reasonString = "ERROR"
    case MPV_END_FILE_REASON_REDIRECT:
      reasonString = "REDIRECT"
    default:
      reasonString = "???"
    }
    if reason == MPV_END_FILE_REASON_ERROR {
      reasonString += " \(error) (\(errorString(error)))"
    }
    return reasonString
  }
}

// Global functions

class MPVController: NSObject {
  static var watchLaterOptions: String = ""

  struct UserData {
    static let screenshot: UInt64 = 1000000
  }

  /// Version number of the libass library.
  ///
  /// The mpv libass version property returns an integer encoded as a hex binary-coded decimal.
  var libassVersion: String {
    let version = getInt(MPVProperty.libassVersion)
    let major = String(version >> 28 & 0xF, radix: 16)
    let minor = String(version >> 20 & 0xFF, radix: 16)
    let patch = String(version >> 12 & 0xFF, radix: 16)
    return "\(major).\(minor).\(patch)"
  }

  // The mpv_handle
  var mpv: OpaquePointer!
  var mpvRenderContext: OpaquePointer?

  var openGLContext: CGLContextObj! = nil

  var mpvVersion: String!

  var queue: DispatchQueue

  static func createQueue(playerLabel: String) -> DispatchQueue {
    return DispatchQueue.newDQ(label: "com.colliderli.iina.controller.\(playerLabel)", qos: .userInitiated)
  }

  unowned let player: PlayerCore

  var needRecordSeekTime: Bool = false
  var recordedSeekStartTime: CFTimeInterval = 0
  var recordedSeekTimeListener: ((Double) -> Void)?

  let mpvLogScanner: MPVLogScanner!

  @Atomic private var hooks: [UInt64: MPVHookValue] = [:]
  private var hookCounter: UInt64 = 1

  let observeProperties: [String: mpv_format] = [
    MPVProperty.trackList: MPV_FORMAT_NONE,
    MPVProperty.vf: MPV_FORMAT_NONE,
    MPVProperty.af: MPV_FORMAT_NONE,
    MPVOption.Video.videoAspectOverride: MPV_FORMAT_NONE,
    MPVOption.TrackSelection.vid: MPV_FORMAT_INT64,
    MPVOption.TrackSelection.aid: MPV_FORMAT_INT64,
    MPVOption.TrackSelection.sid: MPV_FORMAT_INT64,
    MPVOption.Subtitles.secondarySid: MPV_FORMAT_INT64,
    MPVOption.PlaybackControl.pause: MPV_FORMAT_FLAG,
    MPVOption.PlaybackControl.loopPlaylist: MPV_FORMAT_STRING,
    MPVOption.PlaybackControl.loopFile: MPV_FORMAT_STRING,
    MPVProperty.chapter: MPV_FORMAT_INT64,
    MPVOption.Video.deinterlace: MPV_FORMAT_FLAG,
    MPVOption.Video.hwdec: MPV_FORMAT_STRING,
    MPVOption.Video.videoRotate: MPV_FORMAT_INT64,
    MPVOption.Audio.mute: MPV_FORMAT_FLAG,
    MPVOption.Audio.volume: MPV_FORMAT_DOUBLE,
    MPVOption.Audio.audioDelay: MPV_FORMAT_DOUBLE,
    MPVOption.PlaybackControl.speed: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.secondarySubVisibility: MPV_FORMAT_FLAG,
    MPVOption.Subtitles.secondarySubDelay: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.secondarySubPos: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subDelay: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subPos: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subColor: MPV_FORMAT_STRING,
    MPVOption.Subtitles.subFont: MPV_FORMAT_STRING,
    MPVOption.Subtitles.subFontSize: MPV_FORMAT_INT64,
    MPVOption.Subtitles.subBold: MPV_FORMAT_FLAG,
    MPVOption.Subtitles.subBorderColor: MPV_FORMAT_STRING,
    MPVOption.Subtitles.subBorderSize: MPV_FORMAT_INT64,
    MPVOption.Subtitles.subBackColor: MPV_FORMAT_STRING,
    MPVOption.Subtitles.subScale: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subVisibility: MPV_FORMAT_FLAG,
    MPVOption.Equalizer.contrast: MPV_FORMAT_INT64,
    MPVOption.Equalizer.brightness: MPV_FORMAT_INT64,
    MPVOption.Equalizer.gamma: MPV_FORMAT_INT64,
    MPVOption.Equalizer.hue: MPV_FORMAT_INT64,
    MPVOption.Equalizer.saturation: MPV_FORMAT_INT64,
    MPVOption.Window.fullscreen: MPV_FORMAT_FLAG,
    MPVOption.Window.ontop: MPV_FORMAT_FLAG,
    MPVOption.Window.windowScale: MPV_FORMAT_DOUBLE,
    MPVProperty.mediaTitle: MPV_FORMAT_STRING,
    MPVProperty.videoParamsRotate: MPV_FORMAT_INT64,
    MPVProperty.videoParamsPrimaries: MPV_FORMAT_STRING,
    MPVProperty.videoParamsGamma: MPV_FORMAT_STRING,
    MPVProperty.idleActive: MPV_FORMAT_FLAG
  ]

  /// Map from mpv codec name to core media video codec types.
  ///
  /// This map only contains the mpv codecs `adjustCodecWhiteList` can remove from the mpv `hwdec-codecs` option.
  /// If any codec types are added then `HardwareDecodeCapabilities` will need to be updated to support them.
  private let mpvCodecToCodecTypes: [String: [CMVideoCodecType]] = [
    "av1": [kCMVideoCodecType_AV1],
    "prores": [kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
               kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy,
               kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes4444XQ,
               kCMVideoCodecType_AppleProResRAW, kCMVideoCodecType_AppleProResRAWHQ],
    "vp9": [kCMVideoCodecType_VP9]
  ]

  var log: Logger.Subsystem {
    return mpvLogScanner.mpvLogSubsystem
  }

  /// Creates a `MPVController` object.
  /// - Parameters:
  ///   - playerCore: The player this `MPVController` will be associated with.
  init(playerCore: PlayerCore) {
    self.player = playerCore
    self.queue = MPVController.createQueue(playerLabel: playerCore.label)
    self.mpvLogScanner = MPVLogScanner(player: playerCore)
    super.init()
  }

  deinit {
    removeOptionObservers()
  }
  /// Remove codecs from the hardware decoding white list that this Mac does not support.
  ///
  /// As explained in [HWAccelIntro](https://trac.ffmpeg.org/wiki/HWAccelIntro),  [FFmpeg](https://ffmpeg.org/)
  /// will automatically fall back to software decoding. _However_ when it does so `FFmpeg` emits an error level log message
  /// referring to "Failed setup". This has confused users debugging problems. To eliminate the overhead of setting up for hardware
  /// decoding only to have it fail, this method removes codecs from the mpv
  /// [hwdec-codecs](https://mpv.io/manual/stable/#options-hwdec-codecs) option that are known to not have
  /// hardware decoding support on this Mac. This is not comprehensive. This method only covers the recent codecs whose support
  /// for hardware decoding varies among Macs. This merely reduces the dependence upon the FFmpeg fallback to software decoding
  /// feature in some cases.
  private func adjustCodecWhiteList() {
    // Allow the user to override this behavior.
    guard !userOptionsContains(MPVOption.Video.hwdecCodecs) else {
      log.debug("""
        Option \(MPVOption.Video.hwdecCodecs) has been set in advanced settings, \
        will not adjust white list
        """)
      return
    }
    guard let whitelist = getString(MPVOption.Video.hwdecCodecs) else {
      // Internal error. Make certain this method is called after mpv_initialize which sets the
      // default value.
      log.error("Failed to obtain the value of option \(MPVOption.Video.hwdecCodecs)")
      return
    }
    log.debug("Hardware decoding whitelist (\(MPVOption.Video.hwdecCodecs)) is set to \(whitelist)")
    var adjusted: [String] = []
    var needsAdjustment = false
  codecLoop: for codec in whitelist.components(separatedBy: ",") {
    guard let codecTypes = mpvCodecToCodecTypes[codec] else {
      // Not a codec this method supports removing. Retain it in the option value.
      adjusted.append(codec)
      continue
    }
    // The mpv codec name can map to multiple codec types. If hardware decoding is supported for
    // any of them retain the codec in the option value.
    for codecType in codecTypes {
      if HardwareDecodeCapabilities.shared.isSupported(codecType) {
        adjusted.append(codec)
        continue codecLoop
      }
    }
    needsAdjustment = true
    log.debug("This Mac does not support \(codec) hardware decoding")
  }
    // Only set the option if a change is needed to avoid logging when nothing has changed.
    if needsAdjustment {
      setString(MPVOption.Video.hwdecCodecs, adjusted.joined(separator: ","))
    }
  }

  /// Determine if this Mac has an Apple Silicon chip.
  /// - Returns: `true` if running on a Mac with an Apple Silicon chip, `false` otherwise.
  private func runningOnAppleSilicon() -> Bool {
    // Old versions of macOS do not support Apple Silicon.
    if #unavailable(macOS 11.0) {
      return false
    }
    var sysinfo = utsname()
    let result = uname(&sysinfo)
    guard result == EXIT_SUCCESS else {
      log.error("uname failed returning \(result)")
      return false
    }
    let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
    guard let machine = String(bytes: data, encoding: .ascii) else {
      log.error("Failed to construct string for sysinfo.machine")
      return false
    }
    return machine.starts(with: "arm64")
  }

  /// Apply a workaround for issue [#4486](https://github.com/iina/iina/issues/4486), if needed.
  ///
  /// On Macs with an Intel chip VP9 hardware acceleration is causing a hang in
  ///[VTDecompressionSessionWaitForAsynchronousFrames](https://developer.apple.com/documentation/videotoolbox/1536066-vtdecompressionsessionwaitforasy).
  /// This has been reproduced with FFmpeg and has been reported in ticket [9599](https://trac.ffmpeg.org/ticket/9599).
  ///
  /// The workaround removes VP9 from the value of the mpv [hwdec-codecs](https://mpv.io/manual/master/#options-hwdec-codecs) option,
  /// the list of codecs eligible for hardware acceleration.
  private func applyHardwareAccelerationWorkaround() {
    // The problem is not reproducible under Apple Silicon.
    guard !runningOnAppleSilicon() else {
      log.debug("Running on Apple Silicon, not applying FFmpeg 9599 workaround")
      return
    }
    // Allow the user to override this behavior.
    guard !userOptionsContains(MPVOption.Video.hwdecCodecs) else {
      log.debug("""
        Option \(MPVOption.Video.hwdecCodecs) has been set in advanced settings, \
        not applying FFmpeg 9599 workaround
        """)
      return
    }
    guard let whitelist = getString(MPVOption.Video.hwdecCodecs) else {
      // Internal error. Make certain this method is called after mpv_initialize which sets the
      // default value.
      log.error("Failed to obtain the value of option \(MPVOption.Video.hwdecCodecs)")
      return
    }
    var adjusted: [String] = []
    var needsWorkaround = false
  codecLoop: for codec in whitelist.components(separatedBy: ",") {
    guard codec == "vp9" else {
      adjusted.append(codec)
      continue
    }
    needsWorkaround = true
  }
    if needsWorkaround {
      log.debug("Disabling hardware acceleration for VP9 encoded videos to workaround FFmpeg 9599")
      setString(MPVOption.Video.hwdecCodecs, adjusted.joined(separator: ","))
    }
  }

  /// Returns true if mpv's state has fallen behind the current user intention and it is currently operating on an entry
  /// which IINA doesn't care about anymore.
  ///
  /// mpv's `playlist-current-pos` tracks the lifecycle of a playlist entry from start to end.
  /// Should not be confused with `playlist-playing-pos`, which is used for the "playing" highlighted row in the playlist.
  func isStale() -> Bool {
    assert(DispatchQueue.isExecutingIn(queue))
    let mpv = getInt(MPVProperty.playlistCurrentPos)
    guard let iina = player.info.currentPlayback?.playlistPos else {
      // Note: not current if both are nil
      player.log.verbose("The current playlistPos from mpv (\(mpv)) is stale because there should be no media loaded")
      return true
    }
    let isStale = mpv != iina
    player.log.verbose("IINA \(iina), mpv \(mpv) → isStale=\(isStale.yesno)")
    return isStale
  }

  func updateKeepOpenOptionFromPrefs() {
    setUserOption(PK.keepOpenOnFileEnd, type: .other, forName: MPVOption.Window.keepOpen,
                  level: .verbose) { key in
      let keepOpen = Preference.bool(for: PK.keepOpenOnFileEnd)
      let keepOpenPl = !Preference.bool(for: PK.playlistAutoPlayNext)
      return keepOpenPl ? "always" : (keepOpen ? yes_str : no_str)
    }

    setUserOption(PK.playlistAutoPlayNext, type: .other, forName: MPVOption.Window.keepOpen,
                  level: .verbose) { key in
      let keepOpen = Preference.bool(for: PK.keepOpenOnFileEnd)
      let keepOpenPl = !Preference.bool(for: PK.playlistAutoPlayNext)
      return keepOpenPl ? "always" : (keepOpen ? yes_str : no_str)
    }
  }

  /**
   Init the mpv context, set options
   */
  func mpvInit() {
    player.log.verbose("Init mpv")
    // Create a new mpv instance and an associated client API handle to control the mpv instance.
    mpv = mpv_create()

    // User default settings

    if !player.info.isRestoring {
      if Preference.bool(for: .enableInitialVolume) {
        setUserOption(PK.initialVolume, type: .int, forName: MPVOption.Audio.volume, sync: false,
                      level: .verbose)
      } else {
        setUserOption(PK.softVolume, type: .int, forName: MPVOption.Audio.volume, sync: false,
                      level: .verbose)
      }
    }

    // - Advanced

    // disable internal OSD
    let useMpvOSD = Preference.bool(for: .enableAdvancedSettings) && Preference.bool(for: .useMpvOsd)
    // FIXME: need to keep this synced with useMpvOsd during run
    player.isUsingMpvOSD = useMpvOSD
    if useMpvOSD {
      player.hideOSD()
    } else {
      chkErr(mpv_set_option_string(mpv, MPVOption.OSD.osdLevel, "0"))
    }

    // log
    if Logger.enabled {
      let path = Logger.logDirectory.appendingPathComponent("mpv-\(player.label).log").path
      player.log.debug("Path of mpv log: \(path.quoted)")
      chkErr(setOptionString(MPVOption.ProgramBehavior.logFile, path, level: .verbose))
    }

    // - General

    let setScreenshotPath = { (key: Preference.Key) -> String in
      let screenshotPath = Preference.string(for: .screenshotFolder)!
      return Preference.bool(for: .screenshotSaveToFile) ?
      NSString(string: screenshotPath).expandingTildeInPath :
      Utility.screenshotCacheURL.path
    }

    setUserOption(PK.screenshotFolder, type: .other, forName: MPVOption.Screenshot.screenshotDir,
                  level: .verbose, transformer: setScreenshotPath)
    setUserOption(PK.screenshotSaveToFile, type: .other, forName: MPVOption.Screenshot.screenshotDir,
                  level: .verbose, transformer: setScreenshotPath)

    setUserOption(PK.screenshotFormat, type: .other, forName: MPVOption.Screenshot.screenshotFormat,
                  level: .verbose) { key in
      let v = Preference.integer(for: key)
      return Preference.ScreenshotFormat(rawValue: v)?.string
    }

    setUserOption(PK.screenshotTemplate, type: .string, forName: MPVOption.Screenshot.screenshotTemplate,
                  level: .verbose)

    // Disable mpv's media key system as it now uses the MediaPlayer Framework.
    // Dropped media key support in 10.11 and 10.12.
    chkErr(mpv_set_option_string(mpv, MPVOption.Input.inputMediaKeys, no_str))

    updateKeepOpenOptionFromPrefs()

    chkErr(setOptionString(MPVOption.WatchLater.watchLaterDir, Utility.watchLaterURL.path, level: .verbose))
    setUserOption(PK.resumeLastPosition, type: .bool, forName: MPVOption.WatchLater.savePositionOnQuit,
                  level: .verbose)
    setUserOption(PK.resumeLastPosition, type: .bool, forName: "resume-playback", level: .verbose)

    if !player.info.isRestoring {  // if restoring, will use stored windowFrame instead
      setUserOption(.initialWindowSizePosition, type: .string, forName: MPVOption.Window.geometry,
                    level: .verbose)
    }

    // - Codec

    setUserOption(PK.hardwareDecoder, type: .other, forName: MPVOption.Video.hwdec,
                  level: .verbose) { key in
      let value = Preference.integer(for: key)
      return Preference.HardwareDecoderOption(rawValue: value)?.mpvString ?? "auto"
    }

    setUserOption(PK.maxVolume, type: .int, forName: MPVOption.Audio.volumeMax, level: .verbose)

    setUserOption(PK.videoThreads, type: .int, forName: MPVOption.Video.vdLavcThreads, level: .verbose)
    setUserOption(PK.audioThreads, type: .int, forName: MPVOption.Audio.adLavcThreads, level: .verbose)

    setUserOption(PK.audioLanguage, type: .string, forName: MPVOption.TrackSelection.alang,
                  level: .verbose)

    var spdif: [String] = []
    if Preference.bool(for: PK.spdifAC3) { spdif.append("ac3") }
    if Preference.bool(for: PK.spdifDTS){ spdif.append("dts") }
    if Preference.bool(for: PK.spdifDTSHD) { spdif.append("dts-hd") }
    setString(MPVOption.Audio.audioSpdif, spdif.joined(separator: ","), level: .verbose)

    setUserOption(PK.audioDevice, type: .string, forName: MPVOption.Audio.audioDevice, level: .verbose)

    setUserOption(PK.replayGain, type: .other, forName: MPVOption.Audio.replaygain) { key in
      let value = Preference.integer(for: key)
      return Preference.ReplayGainOption(rawValue: value)?.mpvString ?? "no"
    }
    setUserOption(PK.replayGainPreamp, type: .float, forName: MPVOption.Audio.replaygainPreamp)
    setUserOption(PK.replayGainClip, type: .bool, forName: MPVOption.Audio.replaygainClip)
    setUserOption(PK.replayGainFallback, type: .float, forName: MPVOption.Audio.replaygainFallback)

    // - Sub

    chkErr(setOptionString(MPVOption.Subtitles.subAuto, "no", level: .verbose))
    chkErr(setOptionalOptionString(MPVOption.Subtitles.subCodepage,
                                   Preference.string(for: .defaultEncoding), level: .verbose))
    player.info.subEncoding = Preference.string(for: .defaultEncoding)

    let subOverrideHandler: OptionObserverInfo.Transformer = { key in
      let v = Preference.bool(for: .ignoreAssStyles)
      let level: Preference.SubOverrideLevel = Preference.enum(for: .subOverrideLevel)
      return v ? level.string : "yes"
    }

    setUserOption(PK.ignoreAssStyles, type: .other, forName: MPVOption.Subtitles.subAssOverride,
                  level: .verbose, transformer: subOverrideHandler)
    setUserOption(PK.subOverrideLevel, type: .other, forName: MPVOption.Subtitles.subAssOverride,
                  level: .verbose, transformer: subOverrideHandler)

    setUserOption(PK.subTextFont, type: .string, forName: MPVOption.Subtitles.subFont, level: .verbose)
    setUserOption(PK.subTextSize, type: .float, forName: MPVOption.Subtitles.subFontSize, level: .verbose)

    setUserOption(PK.subTextColorString, type: .color, forName: MPVOption.Subtitles.subColor, level: .verbose)
    setUserOption(PK.subBgColorString, type: .color, forName: MPVOption.Subtitles.subBackColor, level: .verbose)

    setUserOption(PK.subBold, type: .bool, forName: MPVOption.Subtitles.subBold, level: .verbose)
    setUserOption(PK.subItalic, type: .bool, forName: MPVOption.Subtitles.subItalic, level: .verbose)

    setUserOption(PK.subBlur, type: .float, forName: MPVOption.Subtitles.subBlur, level: .verbose)
    setUserOption(PK.subSpacing, type: .float, forName: MPVOption.Subtitles.subSpacing, level: .verbose)

    setUserOption(PK.subBorderSize, type: .float, forName: MPVOption.Subtitles.subBorderSize,
                  level: .verbose)
    setUserOption(PK.subBorderColorString, type: .color, forName: MPVOption.Subtitles.subBorderColor,
                  level: .verbose)

    setUserOption(PK.subShadowSize, type: .float, forName: MPVOption.Subtitles.subShadowOffset,
                  level: .verbose)
    setUserOption(PK.subShadowColorString, type: .color, forName: MPVOption.Subtitles.subShadowColor,
                  level: .verbose)

    setUserOption(PK.subAlignX, type: .other, forName: MPVOption.Subtitles.subAlignX,
                  level: .verbose) { key in
      let v = Preference.integer(for: key)
      return Preference.SubAlign(rawValue: v)?.stringForX
    }

    setUserOption(PK.subAlignY, type: .other, forName: MPVOption.Subtitles.subAlignY,
                  level: .verbose) { key in
      let v = Preference.integer(for: key)
      return Preference.SubAlign(rawValue: v)?.stringForY
    }

    setUserOption(PK.subMarginX, type: .int, forName: MPVOption.Subtitles.subMarginX, level: .verbose)
    setUserOption(PK.subMarginY, type: .int, forName: MPVOption.Subtitles.subMarginY, level: .verbose)

    setUserOption(PK.subPos, type: .int, forName: MPVOption.Subtitles.subPos, level: .verbose)

    setUserOption(PK.subLang, type: .string, forName: MPVOption.TrackSelection.slang, level: .verbose)

    setUserOption(PK.displayInLetterBox, type: .bool, forName: MPVOption.Subtitles.subUseMargins, level: .verbose)
    setUserOption(PK.displayInLetterBox, type: .bool, forName: MPVOption.Subtitles.subAssForceMargins, level: .verbose)

    setUserOption(PK.subScaleWithWindow, type: .bool, forName: MPVOption.Subtitles.subScaleByWindow, level: .verbose)

    // - Network / cache settings

    setUserOption(PK.enableCache, type: .other, forName: MPVOption.Cache.cache,
                  level: .verbose) { key in
      return Preference.bool(for: key) ? nil : "no"
    }

    setUserOption(PK.defaultCacheSize, type: .other, forName: MPVOption.Demuxer.demuxerMaxBytes,
                  level: .verbose) { key in
      return "\(Preference.integer(for: key))KiB"
    }
    setUserOption(PK.secPrefech, type: .int, forName: MPVOption.Cache.cacheSecs, level: .verbose)

    setUserOption(PK.userAgent, type: .other, forName: MPVOption.Network.userAgent,
                  level: .verbose) { key in
      let ua = Preference.string(for: key)!
      return ua.isEmpty ? nil : ua
    }

    setUserOption(PK.transportRTSPThrough, type: .other, forName: MPVOption.Network.rtspTransport,
                  level: .verbose) { key in
      let v: Preference.RTSPTransportation = Preference.enum(for: .transportRTSPThrough)
      return v.string
    }

    setUserOption(PK.ytdlEnabled, type: .bool, forName: MPVOption.ProgramBehavior.ytdl, level: .verbose)
    setUserOption(PK.ytdlRawOptions, type: .string, forName: MPVOption.ProgramBehavior.ytdlRawOptions,
                  level: .verbose)
    let propertiesToReset = [MPVOption.PlaybackControl.abLoopA, MPVOption.PlaybackControl.abLoopB]
    chkErr(setOptionString(MPVOption.ProgramBehavior.resetOnNextFile,
                           propertiesToReset.joined(separator: ","), level: .verbose))

    // As mpv support for audio using the AVFoundation framework is new we enable it before applying
    // user's settings. This allows a user to roll back to the Core Audio framework should a problem
    // be encountered with the new code.
    // TODO: "avfoundation" has unacceptable 2s lag when muting. Add "ao" switch to Settings UI instead
// [fall back to coreaudio for now!]   chkErr(setOptionString(MPVOption.Audio.ao, "avfoundation", level: .verbose))

    // Set user defined conf dir.
    if Preference.bool(for: .enableAdvancedSettings),
       Preference.bool(for: .useUserDefinedConfDir),
       var userConfDir = Preference.string(for: .userDefinedConfDir) {
      userConfDir = NSString(string: userConfDir).standardizingPath
      setOptionString("config", "yes", level: .verbose)
      let status = setOptionString(MPVOption.ProgramBehavior.configDir, userConfDir)
      if status < 0 {
        DispatchQueue.main.async {
          Utility.showAlert("extra_option.config_folder", arguments: [userConfDir])
        }
      }
    }

    // Set user defined options.
    if Preference.bool(for: .enableAdvancedSettings) {
      if let userOptions = Preference.value(for: .userOptions) as? [[String]] {
        if !userOptions.isEmpty {
          log.debug("Setting \(userOptions.count) user configured mpv option values")
          userOptions.forEach { op in
            let status = setOptionString(op[0], op[1])
            if status < 0 {
              let errorString = String(cString: mpv_error_string(status))
              DispatchQueue.main.async {  // do not block startup! Must avoid deadlock in static initializers
                Utility.showAlert("extra_option.error", arguments: [op[0], op[1], status, errorString])
              }
            }
          }
        }
      } else {
        DispatchQueue.main.async {  // do not block startup! Must avoid deadlock in static initializers
          Utility.showAlert("extra_option.cannot_read")
        }
      }
    }

    // Load external scripts

    // Load keybindings. This is still required for mpv to handle media keys or apple remote.
    let inputConfPath = ConfTableState.current.selectedConfFilePath
    chkErr(setOptionalOptionString(MPVOption.Input.inputConf, inputConfPath, level: .verbose))

    // Receive log messages at given level of verbosity.
    chkErr(mpv_request_log_messages(mpv, mpvLogSubscriptionLevel))

    // Request tick event.
    // chkErr(mpv_request_event(mpv, MPV_EVENT_TICK, 1))

    // Set a custom function that should be called when there are new events.
    mpv_set_wakeup_callback(self.mpv, { (ctx) in
      let mpvController = unsafeBitCast(ctx, to: MPVController.self)
      mpvController.readEvents()
    }, mutableRawPointerOf(obj: self))

    // Observe properties.
    observeProperties.forEach { (k, v) in
      mpv_observe_property(mpv, 0, k, v)
    }

    // Initialize an uninitialized mpv instance. If the mpv instance is already running, an error is returned.
    chkErr(mpv_initialize(mpv))

    // The option watch-later-options is not available until after the mpv instance is initialized.
    // Workaround for mpv issue #14417, watch-later-options missing secondary subtitle delay and sid.
    // Allow the user to override this workaround by setting this mpv option in advanced settings.
    if !userOptionsContains(MPVOption.WatchLater.watchLaterOptions),
       var watchLaterOptions = getString(MPVOption.WatchLater.watchLaterOptions) {

      // In mpv 0.38.0 the default value for the watch-later-options property contains the options
      // sid and sub-delay, but not the corresponding options for the secondary subtitle. This
      // inconsistency is likely to confuse users, so insure the secondary options are also saved in
      // watch later files. Issue #14417 has been fixed, so this workaround will not be needed after
      // the next mpv upgrade.
      var needsUpdate = false
      if watchLaterOptions.contains(MPVOption.TrackSelection.sid),
         !watchLaterOptions.contains(MPVOption.Subtitles.secondarySid) {
        log.debug("Adding \(MPVOption.Subtitles.secondarySid) to \(MPVOption.WatchLater.watchLaterOptions)")
        watchLaterOptions += "," + MPVOption.Subtitles.secondarySid
        needsUpdate = true
      }
      if watchLaterOptions.contains(MPVOption.Subtitles.subDelay),
         !watchLaterOptions.contains(MPVOption.Subtitles.secondarySubDelay) {
        log.debug("Adding \(MPVOption.Subtitles.secondarySubDelay) to \(MPVOption.WatchLater.watchLaterOptions)")
        watchLaterOptions += "," + MPVOption.Subtitles.secondarySubDelay
        needsUpdate = true
      }
      if needsUpdate {
        setString(MPVOption.WatchLater.watchLaterOptions, watchLaterOptions, level: .verbose)
      }
    }
    if let watchLaterOptions = getString(MPVOption.WatchLater.watchLaterOptions) {
      let sorted = watchLaterOptions.components(separatedBy: ",").sorted().joined(separator: ",")
      log.debug("Options mpv is configured to save in watch later files: \(sorted)")
    }

    // Must be called after mpv_initialize which sets the default value for hwdec-codecs.
    adjustCodecWhiteList()
    applyHardwareAccelerationWorkaround()

    // Set options that can be override by user's config. mpv will log user config when initialize,
    // so we put them here.
    chkErr(setString(MPVOption.Video.vo, "libmpv", level: .verbose))
    chkErr(setString(MPVOption.Window.keepaspect, "no", level: .verbose))
    chkErr(setString(MPVOption.Video.gpuHwdecInterop, "auto", level: .verbose))

    // The option watch-later-options is not available until after the mpv instance is initialized.
    // In mpv 0.34.1 the default value for the watch-later-options property contains the option
    // sub-visibility, but the option secondary-sub-visibility is missing. This inconsistency is
    // likely to confuse users, so insure the visibility setting for secondary subtitles is also
    // saved in watch later files.
    if let watchLaterOptions = getString(MPVOption.WatchLater.watchLaterOptions),
       watchLaterOptions.contains(MPVOption.Subtitles.subVisibility),
       !watchLaterOptions.contains(MPVOption.Subtitles.secondarySubVisibility) {
      setString(MPVOption.WatchLater.watchLaterOptions, watchLaterOptions + "," +
                MPVOption.Subtitles.secondarySubVisibility)
    }
    if let watchLaterOptions = getString(MPVOption.WatchLater.watchLaterOptions) {
      player.log.debug("Options mpv is configured to save in watch later files: \(watchLaterOptions)")
      MPVController.watchLaterOptions = watchLaterOptions
      NotificationCenter.default.post(name: .watchLaterOptionsDidChange, object: player)
    }

    // get version
    mpvVersion = getString(MPVProperty.mpvVersion)

    // Unlike upstream IINA, we do not start any mpv cores until a window has been opened.
    // So we must wait until now to log this info, instead of at app start.
    // Should be fine to log this for every mpv core - it may be useful to have it in every mpv log file.
    player.log.debug("Using \(mpvVersion!) and libass \(libassVersion)")
    player.log.verbose("Configuration when building mpv: \(getString(MPVProperty.mpvConfiguration)!)")
  }

  /// Initialize the `mpv` renderer.
  ///
  /// This method creates and initializes the `mpv` renderer and sets the callback that `mpv` calls when a new video frame is available.
  ///
  /// - Note: Advanced control must be enabled for the screenshot command to work when the window flag is used. See issue
  ///         [#4822](https://github.com/iina/iina/issues/4822) for details.
  /// Initialize the `mpv` renderer.
  ///
  /// This method creates and initializes the `mpv` renderer and sets the callback that `mpv` calls when a new video frame is available.
  ///
  /// - Note: Advanced control must be enabled for the screenshot command to work when the window flag is used. See issue
  ///         [#4822](https://github.com/iina/iina/issues/4822) for details.
  func mpvInitRendering() {
    guard let mpv = mpv else {
      fatalError("mpvInitRendering() should be called after mpv handle being initialized!")
    }
    let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
    var openGLInitParams = mpv_opengl_init_params(get_proc_address: mpvGetOpenGLFunc,
                                                  get_proc_address_ctx: nil)
    withUnsafeMutablePointer(to: &openGLInitParams) { openGLInitParams in
      var advanced: CInt = 1
      withUnsafeMutablePointer(to: &advanced) { advanced in
        var params = [
          mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
          mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: openGLInitParams),
          mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: advanced),
          mpv_render_param()
        ]
        chkErr(mpv_render_context_create(&mpvRenderContext, mpv, &params))
      }
      openGLContext = CGLGetCurrentContext()
      mpv_render_context_set_update_callback(mpvRenderContext!, mpvUpdateCallback, mutableRawPointerOf(obj: player.videoView.videoLayer))
    }
  }

  /// Lock the OpenGL context associated with the mpv renderer and set it to be the current context for this thread.
  ///
  /// This method is needed to meet this requirement from `mpv/render.h`:
  ///
  /// If the OpenGL backend is used, for all functions the OpenGL context must be "current" in the calling thread, and it must be the
  /// same OpenGL context as the `mpv_render_context` was created with. Otherwise, undefined behavior will occur.
  ///
  /// - Reference: [mpv render.h](https://github.com/mpv-player/mpv/blob/master/libmpv/render.h)
  /// - Reference: [Concurrency and OpenGL](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_threading/opengl_threading.html)
  /// - Reference: [OpenGL Context](https://www.khronos.org/opengl/wiki/OpenGL_Context)
  /// - Attention: Do not forget to unlock the OpenGL context by calling `unlockOpenGLContext`
  @discardableResult
  func lockAndSetOpenGLContext() -> Bool {
    guard let openGLContext else { return false }
    CGLLockContext(openGLContext)
    CGLSetCurrentContext(openGLContext)
    return true
  }

  /// Unlock the OpenGL context associated with the mpv renderer.
  func unlockOpenGLContext() {
    CGLUnlockContext(openGLContext)
  }

  func mpvUninitRendering() {
    guard let mpvRenderContext = mpvRenderContext else { return }
    player.log.verbose("Uninit mpv rendering")
    mpv_render_context_set_update_callback(mpvRenderContext, nil, nil)
    mpv_render_context_free(mpvRenderContext)
    self.mpvRenderContext = nil
  }

  func mpvDestroy() {
    player.log.verbose("Destroying mpv")
    guard mpv != nil else {
      fatalError("mpvUninitRendering() called but mpv handle is nil!")
    }
    mpv_destroy(mpv)
    mpv = nil
  }

  func mpvReportSwap() {
    guard let mpvRenderContext = mpvRenderContext else { return }
    mpv_render_context_report_swap(mpvRenderContext)
  }

  func shouldRenderUpdateFrame() -> Bool {
    guard let mpvRenderContext = mpvRenderContext else { return false }
    guard !player.isStopping else { return false }
    let flags: UInt64 = mpv_render_context_update(mpvRenderContext)
    return flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) > 0
  }

  /// Remove observers for IINA preferences and mpv properties.
  /// - Important: Observers **must** be removed before sending a `quit` command to mpv. Accessing a mpv core after it
  ///     has shutdown is not permitted by mpv and can trigger a crash. During shutdown mpv will emit property change events,
  ///     thus it is critical that observers be removed, otherwise they may access the core and trigger a crash.
  func removeObservers() {
    // Remove observers for IINA preferences. Must not attempt to change a mpv setting in response
    // to an IINA preference change while mpv is shutting down.
    removeOptionObservers()
    // Remove observers for mpv properties. Because 0 was passed for reply_userdata when registering
    // mpv property observers all observers can be removed in one call.
    mpv_unobserve_property(mpv, 0)
  }

  /// Remove observers for IINA preferences.
  private func removeOptionObservers() {
    ObjcUtils.silenced {
      self.optionObservers.forEach { (k, _) in
        UserDefaults.standard.removeObserver(self, forKeyPath: k)
      }
    }
  }

  /// Shutdown this mpv controller.
  func mpvQuit() {
    player.log.verbose("Quitting mpv")
    // Observers must be removed to avoid accessing the mpv core after it has shutdown.
    removeObservers()
    // Start mpv quitting. Even though this command is being sent using the synchronous command API
    // the quit command is special and will be executed by mpv asynchronously.
    command(.quit, level: .verbose)
  }

  // MARK: - Command & property

  private func makeCArgs(_ command: MPVCommand, _ args: [String?]) -> [String?] {
    if args.count > 0 && args.last == nil {
      Logger.fatal("Command do not need a nil suffix")
    }
    var strArgs = args
    strArgs.insert(command.rawValue, at: 0)
    strArgs.append(nil)
    return strArgs
  }

  /// Send arbitrary mpv command. Returns mpv return code.
  @discardableResult
  func command(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true,
               level: Logger.Level = .debug) -> Int32 {
    if Logger.isEnabled(.verbose) {
      if command == .loadfile, let filename = args[0] {
        _ = Logger.getOrCreatePII(for: filename)
      }
    }
    log.log("Run command: \(command.rawValue) \(args.compactMap{$0}.joined(separator: " "))", level: level)
    var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
    defer {
      for ptr in cargs {
        if (ptr != nil) {
          free(UnsafeMutablePointer(mutating: ptr!))
        }
      }
    }
    let returnValue = mpv_command(self.mpv, &cargs)
    if checkError {
      chkErr(returnValue)
    }
    return returnValue
  }

  func command(rawString: String, level: Logger.Level = .debug) -> Int32 {
    log.log("Run command: \(rawString)", level: level)
    return mpv_command_string(mpv, rawString)
  }

  func asyncCommand(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true,
                    replyUserdata: UInt64, level: Logger.Level = .debug) {
    guard mpv != nil else { return }
    log.log("Asynchronously run command: \(command.rawValue) \(args.compactMap{$0}.joined(separator: " "))",
            level: level)
    var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
    defer {
      for ptr in cargs {
        if (ptr != nil) {
          free(UnsafeMutablePointer(mutating: ptr!))
        }
      }
    }
    let returnValue = mpv_command_async(self.mpv, replyUserdata, &cargs)
    if checkError {
      chkErr(returnValue)
    }
  }

  func observe(property: String, format: mpv_format = MPV_FORMAT_DOUBLE) {
    player.log.verbose("Adding mpv observer for prop \(property.quoted)")
    mpv_observe_property(mpv, 0, property, format)
  }

  // Set property
  func setFlag(_ name: String, _ flag: Bool, level: Logger.Level = .debug) {
    log.log("Set property: \(name)=\(flag.yesno)", level: level)
    var data: Int = flag ? 1 : 0
    let code = mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    if code < 0 {
      player.log.error("Failed to set mpv_property \(name.quoted) = \(flag). Error: \(errorString(code))")
    }
  }

  func setInt(_ name: String, _ value: Int, level: Logger.Level = .debug) {
    log.log("Set property: \(name)=\(value)", level: level)
    var data = Int64(value)
    mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
  }

  func setDouble(_ name: String, _ value: Double, level: Logger.Level = .debug) {
    log.log("Set property: \(name)=\(value)", level: level)
    var data = value
    mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
  }

  func setFlagAsync(_ name: String, _ flag: Bool) {
    var data: Int = flag ? 1 : 0
    mpv_set_property_async(mpv, 0, name, MPV_FORMAT_FLAG, &data)
  }

  func setIntAsync(_ name: String, _ value: Int) {
    var data = Int64(value)
    mpv_set_property_async(mpv, 0, name, MPV_FORMAT_INT64, &data)
  }

  func setDoubleAsync(_ name: String, _ value: Double) {
    var data = value
    mpv_set_property_async(mpv, 0, name, MPV_FORMAT_DOUBLE, &data)
  }

  @discardableResult
  func setString(_ name: String, _ value: String, level: Logger.Level = .debug) -> Int32 {
    log.log("Set property: \(name)=\(value)", level: level)
    return mpv_set_property_string(mpv, name, value)
  }

  func getInt(_ name: String) -> Int {
    var data = Int64()
    mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
    return Int(data)
  }

  func getDouble(_ name: String) -> Double {
    var data = Double()
    mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
    return data
  }

  func getFlag(_ name: String) -> Bool {
    var data = Int64()
    mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
    return data > 0
  }

  func getString(_ name: String) -> String? {
    let cstr = mpv_get_property_string(mpv, name)
    let str: String? = cstr == nil ? nil : String(cString: cstr!)
    mpv_free(cstr)
    return str
  }

  func getInputBindings(filterCommandsBy filter: ((Substring) -> Bool)? = nil) -> [KeyMapping] {
    player.log.verbose("Requesting from mpv: \(MPVProperty.inputBindings)")
    let parsed = getNode(MPVProperty.inputBindings)
    return toKeyMappings(parsed)
  }

  private func toKeyMappings(_ inputBindingArray: Any?, filterCommandsBy filter: ((Substring) -> Bool)? = nil) -> [KeyMapping] {
    var keyMappingList: [KeyMapping] = []
    if let mapList = inputBindingArray as? [Any?] {
      for mapRaw in mapList {
        if let map = mapRaw as? [String: Any?] {
          let key = getFromMap("key", map)
          let cmd = getFromMap("cmd", map)
          let comment = getFromMap("comment", map)
          let cmdTokens = cmd.split(separator: " ")
          if filter == nil || filter!(cmdTokens[0]) {
            keyMappingList.append(KeyMapping(rawKey: key, rawAction: cmd, isIINACommand: false, comment: comment))
          }
        }
      }
    } else {
      player.log.error("Failed to parse mpv input bindings!")
    }
    return keyMappingList
  }

  /** Get filter. only "af" or "vf" is supported for name */
  func getFilters(_ name: String) -> [MPVFilter] {
    Logger.ensure(name == MPVProperty.vf || name == MPVProperty.af, "getFilters() do not support \(name)!")

    var result: [MPVFilter] = []
    var node = mpv_node()
    mpv_get_property(mpv, name, MPV_FORMAT_NODE, &node)
    guard let filters = (try? MPVNode.parse(node)!) as? [[String: Any?]] else { return result }
    filters.forEach { f in
      let filter = MPVFilter(name: f["name"] as! String,
                             label: f["label"] as? String,
                             params: f["params"] as? [String: String])
      result.append(filter)
    }
    mpv_free_node_contents(&node)
    return result
  }

  /// Remove the audio or video filter at the given index in the list of filters.
  ///
  /// Previously IINA removed filters using the mpv `af remove` and `vf remove` commands described in the
  /// [Input Commands that are Possibly Subject to Change](https://mpv.io/manual/stable/#input-commands-that-are-possibly-subject-to-change)
  /// section of the mpv manual. The behavior of the remove command is described in the [video-filters](https://mpv.io/manual/stable/#video-filters)
  /// section of the manual under the entry for `--vf-remove-filter`.
  ///
  /// When searching for the filter to be deleted the remove command takes into consideration the order of filter parameters. The
  /// expectation is that the application using the mpv client will provide the filter to the remove command in the same way it was
  /// added. However IINA doe not always know how a filter was added. Filters can be added to mpv outside of IINA therefore it is not
  /// possible for IINA to know how filters were added. IINA obtains the filter list from mpv using `mpv_get_property`. The
  /// `mpv_node` tree returned for a filter list stores the filter parameters in a `MPV_FORMAT_NODE_MAP`. The key value pairs in a
  /// `MPV_FORMAT_NODE_MAP` are in **random** order. As a result sometimes the order of filter parameters in the filter string
  /// representation given by IINA to the mpv remove command would not match the order of parameters given when the filter was
  /// added to mpv and the remove command would fail to remove the filter. This was reported in
  /// [IINA issue #3620 Audio filters with same name cannot be removed](https://github.com/iina/iina/issues/3620).
  ///
  /// The issue of `mpv_get_property` returning filter parameters in random order even though the remove command is sensitive to
  /// filter parameter order was raised with the mpv project in
  /// [mpv issue #9841 mpv_get_property returns filter params in unordered map breaking remove](https://github.com/mpv-player/mpv/issues/9841)
  /// The response from the mpv project confirmed that the parameters in a `MPV_FORMAT_NODE_MAP` **must** be considered to
  /// be in random order even if they appear to be ordered. The recommended methods for removing filters is to use labels, which
  /// IINA does for filters it creates or removing based on position in the filter list. This method supports removal based on the
  /// position within the list of filters.
  ///
  /// The recommended implementation is to get the entire list of filters using `mpv_get_property`, remove the filter from the
  /// `mpv_node` tree returned by that method and then set the list of filters using `mpv_set_property`. This is the approach
  /// used by this method.
  /// - Parameter name: The kind of filter identified by the mpv property name, `MPVProperty.af` or `MPVProperty.vf`.
  /// - Parameter index: Index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` if the filter was not removed.
  func removeFilter(_ name: String, _ index: Int) -> Bool {
    assert(DispatchQueue.isExecutingIn(queue))
    Logger.ensure(name == MPVProperty.vf || name == MPVProperty.af, "removeFilter() does not support \(name)!")

    // Get the current list of filters from mpv as a mpv_node tree.
    var oldNode = mpv_node()
    defer { mpv_free_node_contents(&oldNode) }
    mpv_get_property(mpv, name, MPV_FORMAT_NODE, &oldNode)

    let oldList = oldNode.u.list!.pointee

    // If the user uses mpv's JSON-based IPC protocol to make changes to mpv's filters behind IINA's
    // back then there is a very small window of vulnerability where the list of filters displayed
    // by IINA may be stale and therefore the index to remove may be invalid. IINA listens for
    // changes to mpv's filter properties and updates the filters displayed when changes occur, so
    // it is unlikely in practice that this method will be called with an invalid index, but we will
    // validate the index nonetheless to insure this code does not trigger a crash.
    guard index < oldList.num else {
      log.error("Found \(oldList.num) \(name) filters, index of filter to remove (\(index)) is invalid")
      return false
    }

    // The documentation for mpv_node states:
    // "If mpv writes this struct (e.g. via mpv_get_property()), you must not change the data."
    // So the approach taken is to create new top level node objects as those need to be modified in
    // order to remove the filter, and reuse the lower level node objects representing the filters.
    // First we create a new node list that is one entry smaller than the current list of filters.
    let newNum = oldList.num - 1
    let newValues = UnsafeMutablePointer<mpv_node>.allocate(capacity: Int(newNum))
    defer {
      newValues.deinitialize(count: Int(newNum))
      newValues.deallocate()
    }
    var newList = mpv_node_list()
    newList.num = newNum
    newList.values = newValues

    // Make the new list of values point to the same values in the old list, skipping the entry to
    // be removed.
    var newValuesPtr = newValues
    var oldValuesPtr = oldList.values!
    for i in 0 ..< oldList.num {
      if i != index {
        newValuesPtr.pointee = oldValuesPtr.pointee
        newValuesPtr = newValuesPtr.successor()
      }
      oldValuesPtr = oldValuesPtr.successor()
    }

    // Add the new list to a new node.
    let newListPtr = UnsafeMutablePointer<mpv_node_list>.allocate(capacity: 1)
    defer {
      newListPtr.deinitialize(count: 1)
      newListPtr.deallocate()
    }
    newListPtr.pointee = newList
    var newNode = mpv_node()
    newNode.format = MPV_FORMAT_NODE_ARRAY
    newNode.u.list = newListPtr

    // Set the list of filters using the new node that leaves out the filter to be removed.
    log.debug("Set property: \(name)=<a mpv node>")
    let returnValue = mpv_set_property(mpv, name, MPV_FORMAT_NODE, &newNode)
    return returnValue == 0
  }

  /** Set filter. only "af" or "vf" is supported for name */
  func setFilters(_ name: String, filters: [MPVFilter]) {
    queue.async { [self] in
      guard !player.isStopping else { return }
      Logger.ensure(name == MPVProperty.vf || name == MPVProperty.af, "setFilters() do not support \(name)!")
      let cmd = name == MPVProperty.vf ? MPVCommand.vf : MPVCommand.af

      let str = filters.map { $0.stringFormat }.joined(separator: ",")
      let returnValue = command(cmd, args: ["set", str], checkError: false)
      if returnValue < 0 {
        DispatchQueue.main.async { [self] in
          Utility.showAlert("filter.incorrect")
          // reload data in filter setting window
          player.postNotification(.iinaVFChanged)
        }
      }
    }
  }

  func getNode(_ name: String) -> Any? {
    var node = mpv_node()
    mpv_get_property(mpv, name, MPV_FORMAT_NODE, &node)
    let parsed = try? MPVNode.parse(node)
    mpv_free_node_contents(&node)
    return parsed
  }

  func setNode(_ name: String, _ value: Any) {
    guard var node = try? MPVNode.create(value) else {
      log.error("setNode: cannot encode value for \(name)")
      return
    }
    log.debug("Set property: \(name)=<a mpv node>")
    mpv_set_property(mpv, name, MPV_FORMAT_NODE, &node)
    MPVNode.free(node)
  }

  private func getFromMap(_ key: String, _ map: [String: Any?]) -> String {
    if let keyOpt = map[key] as? Optional<String> {
      return keyOpt!
    }
    return ""
  }

  /// Makes calls to mpv to get the latest video params, then returns them.
  func getVideoGeometryFromProperties() -> VideoGeometry? {
    // If loading file, video reconfig can return 0 width and height
    guard let currentPlayback = player.info.currentPlayback else {
      log.verbose("Cannot get videoGeo from mpv: currentPlayback is nil")
      return nil
    }
    guard currentPlayback.isFileLoaded else {
      log.verbose("Cannot get videoGeo from mpv: file not loaded")
      return nil
    }
    // Will crash if querying mpv after stop command started
    guard player.isActive else {
      log.verbose("Cannot get videoGeo: player.status=\(player.status)")
      return nil
    }

    let rawWidth = getInt(MPVProperty.width)
    let rawHeight = getInt(MPVProperty.height)

    let mpvVideoParamsRotate = getInt(MPVProperty.videoParamsRotate)
    let mpvVideoRotate = getInt(MPVOption.Video.videoRotate)

    let dwidth = getInt(MPVProperty.dwidth)
    let dheight = getInt(MPVProperty.dheight)
    // filter the last video-reconfig event before quit
    if dwidth == 0 && dheight == 0 && getFlag(MPVProperty.coreIdle) {
      player.log.verbose("Cannot get videoGeo: core idle & dheight or dwidth is 0")
      return nil
    }

    let codecRotation = (mpvVideoParamsRotate - mpvVideoRotate) %% 360
    let vidGeo = VideoGeometry(rawWidth: rawWidth, rawHeight: rawHeight,
                               selectedAspectLabel: player.videoGeo.selectedAspectLabel,
                               codecRotation: codecRotation, userRotation: mpvVideoRotate,
                               selectedCropLabel: player.videoGeo.selectedCropLabel, log: player.log)

    player.log.verbose("Latest videoGeo after syncing from mpv: \(vidGeo), media: \(currentPlayback.path)")
    // Allow 1px clearance for each dimension here. Seems that we & mpv are not 100% identical in our rounding
    let videoSizeC = vidGeo.videoSizeC
    if (abs(Int(videoSizeC.width) - dwidth) > 1) || (abs(Int(videoSizeC.height) - dheight) > 1) {
      player.log.error("❌ VideoGeometry sanity check failed: mpv dsize (\(dwidth) x \(dheight)) != cached videoSizeC \(videoSizeC)")
    }
    return vidGeo
  }

  /// See notes on `backingScaleFactor` in `syncVideoGeometryFromMPV()`
  /// For mpv, window size is always the same as video size, but this is not always true with IINA due to exterior panels.
  /// Also, mpv uses `backingScaleFactor` for calcalations. IINA Advance does not, because that has no correlation with the
  /// screen's actual scale factor and is at best an oversimplification which is less wrong on average. It is like assuming
  /// "all men have a shoe size of 10 and all women have a shoe size of 8", which is only slightly better than "all humans have a shoe size of 9".
  func getVideoScale() -> Double {
    let mpvVideoScale = getDouble(MPVOption.Window.windowScale)
    let backingScaleFactor = NSScreen.getScreenOrDefault(screenID: player.windowController.windowedModeGeo.screenID).backingScaleFactor
    return mpvVideoScale / backingScaleFactor
  }

  // MARK: - Hooks

  func addHook(_ name: MPVHook, priority: Int32 = 0, hook: MPVHookValue) {
    $hooks.withLock {
      mpv_hook_add(mpv, hookCounter, name.rawValue, priority)
      $0[hookCounter] = hook
      hookCounter += 1
    }
  }

  func removeHooks(withIdentifier id: String) {
    $hooks.withLock { hooks in
      hooks.filter { (k, v) in v.isJavascript && v.id == id }.keys.forEach { hooks.removeValue(forKey: $0) }
    }
  }

  // MARK: - Events

  // Read event and handle it async
  private func readEvents() {
    queue.async {
      while ((self.mpv) != nil) {
        let event = mpv_wait_event(self.mpv, 0)
        // Do not deal with mpv-event-none
        if event?.pointee.event_id == MPV_EVENT_NONE {
          break
        }
        self.handleEvent(event)
      }
    }
  }

  // Handle the event
  private func handleEvent(_ event: UnsafePointer<mpv_event>!) {
    let eventId: mpv_event_id = event.pointee.event_id
    if logEvents && Logger.isEnabled(.verbose) {
      player.log.verbose("Got mpv event: \(eventId)")
    }

    switch eventId {
    case MPV_EVENT_CLIENT_MESSAGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      let msg = UnsafeMutablePointer<mpv_event_client_message>(dataOpaquePtr)
      let numArgs: Int = Int((msg?.pointee.num_args)!)
      var args: [String] = []
      if numArgs > 0 {
        let bufferPointer = UnsafeBufferPointer(start: msg?.pointee.args, count: numArgs)
        for i in 0..<numArgs {
          args.append(String(cString: (bufferPointer[i])!))
        }
      }
      player.log.verbose("Got mpv '\(eventId)': \(numArgs >= 0 ? "\(args)": "numArgs=\(numArgs)")")

    case MPV_EVENT_SHUTDOWN:
      player.log.verbose("Got mpv shutdown event")
      DispatchQueue.main.async {
        self.player.mpvHasShutdown()
      }

    case MPV_EVENT_LOG_MESSAGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      guard let dataPtr = UnsafeMutablePointer<mpv_event_log_message>(dataOpaquePtr) else { return }
      let prefix = String(cString: (dataPtr.pointee.prefix)!)
      let level = String(cString: (dataPtr.pointee.level)!)
      let text = String(cString: (dataPtr.pointee.text)!)

      mpvLogScanner.processLogLine(prefix: prefix, level: level, msg: text)

    case MPV_EVENT_HOOK:
      let userData = event.pointee.reply_userdata
      let hookEvent = event.pointee.data.bindMemory(to: mpv_event_hook.self, capacity: 1).pointee
      let hookID = hookEvent.id
      guard let hook = $hooks.withLock({ $0[userData] }) else { break }
      hook.call {
        mpv_hook_continue(self.mpv, hookID)
      }

    case MPV_EVENT_PROPERTY_CHANGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      if let property = UnsafePointer<mpv_event_property>(dataOpaquePtr)?.pointee {
        handlePropertyChange(property)
      }

    case MPV_EVENT_AUDIO_RECONFIG: break

    case MPV_EVENT_VIDEO_RECONFIG:
      break

    case MPV_EVENT_START_FILE:
      guard let path = getString(MPVProperty.path) else {
        player.log.error("FileStarted: no path!")
        break
      }
      /// Do not use `playlist_entry_id`. It doesn't make sense outside of FileStarted & FileEnded
      let playlistPos = getInt(MPVProperty.playlistPos)

      player.info.isIdle = false

      player.fileStarted(path: path, playlistPos: playlistPos)

    case MPV_EVENT_FILE_LOADED:
      player.fileLoaded()

    case MPV_EVENT_SEEK:
      if needRecordSeekTime {
        recordedSeekStartTime = CACurrentMediaTime()
      }
      player.seeking()

    case MPV_EVENT_PLAYBACK_RESTART:
      if needRecordSeekTime {
        recordedSeekTimeListener?(CACurrentMediaTime() - recordedSeekStartTime)
        recordedSeekTimeListener = nil
      }

      player.playbackRestarted()

    case MPV_EVENT_END_FILE:
      // if receive end-file when loading file, might be error
      // wait for idle
      guard let dataPtr = UnsafeMutablePointer<mpv_event_end_file>(OpaquePointer(event.pointee.data)) else { return }
      let reasonString = dataPtr.pointee.reasonString
      let reason = event!.pointee.data.load(as: mpv_end_file_reason.self)
      // let reasonString = dataPtr.pointee.reasonString
      player.log.verbose("FileEnded, reason: \(reasonString)")
      player.fileEnded(dueToStopCommand: reason == MPV_END_FILE_REASON_STOP)

    case MPV_EVENT_COMMAND_REPLY:
      let reply = event.pointee.reply_userdata
      if reply == MPVController.UserData.screenshot {
        let code = event.pointee.error
        guard code >= 0 else {
          let error = String(cString: mpv_error_string(code))
          player.log.error("Cannot take a screenshot, mpv API error: \(error), returnCalue: \(code)")
          // Unfortunately the mpv API does not provide any details on the failure. The error
          // code returned maps to "error running command", so all the alert can report is
          // that we cannot take a screenshot.
          DispatchQueue.main.async {
            Utility.showAlert("screenshot.error_taking")
          }
          return
        }
        player.screenshotCallback()
      }

    default:
      // Logger.log("Unhandled mpv event: \(eventId)", level: .verbose)
      break
    }

    // This code is running in the com.colliderli.iina.controller dispatch queue. We must not run
    // plugins from a task in this queue. Accessing EventController data from a thread in this queue
    // results in data races that can cause a crash. See issue 3986.
    DispatchQueue.main.async { [self] in
      let eventName = "mpv.\(String(cString: mpv_event_name(eventId)))"
      player.events.emit(.init(eventName))
    }
  }

  // MARK: - Property listeners

  private func handlePropertyChange(_ property: mpv_event_property) {
    let name = String(cString: property.name)

    switch name {

    case MPVProperty.videoParams:
      player.log.verbose("Δ mpv prop: \(MPVProperty.videoParams.quoted)")
      player.reloadQuickSettingsView()

    case MPVProperty.videoOutParams:
      /** From the mpv manual:
       ```
       video-out-params
       Same as video-params, but after video filters have been applied. If there are no video filters in use, this will contain the same values as video-params. Note that this is still not necessarily what the video window uses, since the user can change the window size, and all real VOs do their own scaling independently from the filter chain.

       Has the same sub-properties as video-params.
       ```
       */
      player.log.verbose("Δ mpv prop: \(MPVProperty.videoOutParams.quoted)")
      break

    case MPVProperty.videoParamsRotate:
      /** `video-params/rotate: Intended display rotation in degrees (clockwise).` - mpv manual
       Do not confuse with the user-configured `video-rotate` (below) */
      if let totalRotation = UnsafePointer<Int>(OpaquePointer(property.data))?.pointee {
        player.log.verbose("Δ mpv prop: 'video-params/rotate' ≔ \(totalRotation)")
        player.saveState()
        /// Any necessary resizing will be handled elsewhere
      }

    case MPVOption.Video.videoRotate:
      guard player.windowController.loaded else { break }
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else { break }
      let userRotation = Int(data)

      // Will only get here if rotation was initiated from mpv. If IINA initiated, the new value would have matched videoGeo.
      player.log.verbose("Δ mpv prop: 'video-rotate' ≔ \(userRotation)")

      player.userRotationDidChange(to: userRotation)

    case MPVProperty.videoParamsPrimaries:
      fallthrough

    case MPVProperty.videoParamsGamma:
      player.refreshEdrMode()

    case MPVOption.TrackSelection.vid:
      player.vidChanged()

    case MPVOption.TrackSelection.aid:
      player.aidChanged()

    case MPVOption.TrackSelection.sid:
      player.sidChanged()

    case MPVOption.Subtitles.secondarySid:
      player.secondarySidChanged()

    case MPVOption.PlaybackControl.pause:
      guard let paused = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else {
        player.log.error("Failed to parse mpv pause data!")
        break
      }
      player.log.verbose("Δ mpv prop: 'pause' = \(paused.yn)")

      player.pausedStateDidChange(to: paused)

    case MPVProperty.chapter:
      player.chapterChanged()

    case MPVOption.PlaybackControl.speed:
      guard let speed = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else { break }
      player.log.verbose("Δ mpv prop: `speed` = \(speed)")

      player.speedDidChange(to: speed)
      player.reloadQuickSettingsView()

    case MPVOption.PlaybackControl.loopPlaylist, MPVOption.PlaybackControl.loopFile:
      DispatchQueue.main.async { [self] in
        let loopMode = player.getLoopMode()
        switch loopMode {
        case .file:
          player.sendOSD(.fileLoop)
        case .playlist:
          player.sendOSD(.playlistLoop)
        default:
          player.sendOSD(.noLoop)
        }
        player.syncUI(.loop)
      }

    case MPVOption.Video.deinterlace:
      guard let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else { break }
      // this property will fire a change event at file start
      if player.info.deinterlace != data {
        player.log.verbose("Δ mpv prop: `deinterlace` = \(data)")
        player.info.deinterlace = data
        player.sendOSD(.deinterlace(data))
      }
      player.reloadQuickSettingsView()

    case MPVOption.Video.hwdec:
      let data = String(cString: property.data.assumingMemoryBound(to: UnsafePointer<UInt8>.self).pointee)
      if player.info.hwdec != data {
        player.info.hwdec = data
        player.sendOSD(.hwdec(player.info.hwdecEnabled))
      }
      player.reloadQuickSettingsView()

    case MPVOption.Audio.mute:
      if let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        player.info.isMuted = data
        player.syncUI(.muteButton)
        let volume = Int(player.info.volume)
        player.sendOSD(data ? OSDMessage.mute(volume) : OSDMessage.unMute(volume))
      }

    case MPVOption.Audio.volume:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Audio.volume, property.format)
        break
      }
      player.info.volume = data
      player.syncUI(.volume)
      player.sendOSD(.volume(Int(data)))

    case MPVOption.Audio.audioDelay:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Audio.audioDelay, property.format)
        break
      }
      player.info.audioDelay = data
      player.sendOSD(.audioDelay(data))
      player.reloadQuickSettingsView()

    case MPVOption.Subtitles.subVisibility:
      if let visible = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        if player.info.isSubVisible != visible {
          player.info.isSubVisible = visible
          player.sendOSD(visible ? .subVisible : .subHidden)
        }
      }

    case MPVOption.Subtitles.secondarySubVisibility:
      if let visible = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        if player.info.isSecondSubVisible != visible {
          player.info.isSecondSubVisible = visible
          player.sendOSD(visible ? .secondSubVisible : .secondSubHidden)
        }
      }

    case MPVOption.Subtitles.secondarySubDelay:
      fallthrough

    case MPVOption.Subtitles.subDelay:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(name, property.format)
        break
      }
      guard name == MPVOption.Subtitles.subDelay else {
        player.secondarySubDelayChanged(data)
        break
      }
      player.subDelayChanged(data)

    case MPVOption.Subtitles.subScale:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Subtitles.subScale, property.format)
        break
      }
      let displayValue = data >= 1 ? data : -1/data
      let truncated = round(displayValue * 100) / 100
      player.sendOSD(.subScale(truncated))
      player.reloadQuickSettingsView()

    case MPVOption.Subtitles.secondarySubPos:
      fallthrough

    case MPVOption.Subtitles.subPos:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(name, property.format)
        break
      }
      guard name == MPVOption.Subtitles.subPos else {
        player.secondarySubPosChanged(data)
        break
      }
      player.subPosChanged(data)

    case MPVOption.Equalizer.contrast:
      player.reloadQuickSettingsView()
      // TODO: OSD

    case MPVOption.Subtitles.subFont:
      player.reloadQuickSettingsView()
      // TODO: OSD

    case MPVOption.Subtitles.subFontSize:
      player.reloadQuickSettingsView()
      //      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
      //        let fontSize = Int(data)
      //        // TODO: OSD
      //      }

    case MPVOption.Subtitles.subBold:
      player.reloadQuickSettingsView()
      //      if let isBold = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
      //        // TODO: OSD
      //      }

    case MPVOption.Subtitles.subBorderColor:
      player.reloadQuickSettingsView()
      // TODO: OSD

    case MPVOption.Subtitles.subBorderSize:
      player.reloadQuickSettingsView()
      //      if let borderSize = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
      //        // TODO: OSD
      //      }

    case MPVOption.Subtitles.subBackColor:
      player.reloadQuickSettingsView()
      // TODO: OSD

    case MPVOption.Equalizer.contrast:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.contrast, property.format)
        break
      }
      let intData = Int(data)
      player.info.contrast = intData
      player.sendOSD(.contrast(intData))
      player.reloadQuickSettingsView()

    case MPVOption.Equalizer.hue:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.hue, property.format)
        break
      }
      let intData = Int(data)
      player.info.hue = intData
      player.sendOSD(.hue(intData))
      player.reloadQuickSettingsView()

    case MPVOption.Equalizer.brightness:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.brightness, property.format)
        break
      }
      let intData = Int(data)
      player.info.brightness = intData
      player.sendOSD(.brightness(intData))
      player.reloadQuickSettingsView()

    case MPVOption.Equalizer.gamma:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.gamma, property.format)
        break
      }
      let intData = Int(data)
      player.info.gamma = intData
      player.sendOSD(.gamma(intData))
      player.reloadQuickSettingsView()

    case MPVOption.Equalizer.saturation:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.saturation, property.format)
        break
      }
      let intData = Int(data)
      player.info.saturation = intData
      player.sendOSD(.saturation(intData))
      player.reloadQuickSettingsView()

    case MPVProperty.playlistCount: 
      player.log.verbose("Δ mpv prop: 'playlist-count'")
      player.reloadPlaylist()

    case MPVProperty.trackList:
      player.log.verbose("Δ mpv prop: 'track-list'")
      player.trackListChanged()

    case MPVProperty.vf:
      player.log.verbose("Δ mpv prop: 'vf'")
      player.vfChanged()
      player.reloadQuickSettingsView()

    case MPVProperty.af:
      player.log.verbose("Δ mpv prop: 'af'")
      player.afChanged()
      player.reloadQuickSettingsView()

    case MPVOption.Video.videoAspectOverride:
      guard player.windowController.loaded, !player.isShuttingDown else { break }
      guard let aspect = getString(MPVOption.Video.videoAspectOverride) else { break }
      player.log.verbose("Δ mpv prop: 'video-aspect-override' = \(aspect.quoted)")
      player._setVideoAspectOverride(aspect)

    case MPVOption.Window.fullscreen:
      player.syncFullScreenState()

    case MPVOption.Window.ontop:
      player.ontopChanged()

    case MPVOption.Window.windowScale:
      guard player.windowController.loaded else { break }
      // Ignore if magnifying - will mess up our animation. Will submit window-scale anyway at end of magnify
      guard !player.windowController.isMagnifying else { break }
      let isAlreadySized = player.info.currentPlayback?.state.isAtLeast(.loaded) ?? false
      guard isAlreadySized else { break }

      let cachedVideoScale: CGFloat
      if player.windowController.currentLayout.mode == .musicMode {
        cachedVideoScale = player.windowController.musicModeGeo.toPWinGeometry().mpvVideoScale()
      } else {
        cachedVideoScale = player.windowController.windowedModeGeo.mpvVideoScale()
      }
      let newVideoScale = getVideoScale()
      let needsUpdate = abs(newVideoScale - cachedVideoScale) > 10e-10
      if needsUpdate {
        player.log.verbose("Δ mpv prop: 'window-scale', \(cachedVideoScale) → \(newVideoScale)")
        DispatchQueue.main.async { [self] in
          player.log.verbose("Calling setVideoScale → \(newVideoScale)x")
          player.windowController.setVideoScale(newVideoScale)
        }
      } else {
        player.log.verbose("Δ mpv prop: 'window-scale'; videoScale \(newVideoScale) not changed")
      }

    case MPVProperty.mediaTitle:
      player.mediaTitleChanged()

    case MPVProperty.idleActive:
      guard let idleActive = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVProperty.idleActive, property.format)
        break
      }
      guard idleActive else { break }
      player.idleActiveChanged(to: idleActive)

    case MPVProperty.inputBindings:
      do {
        let dataNode = UnsafeMutablePointer<mpv_node>(OpaquePointer(property.data))?.pointee
        let inputBindingArray = try MPVNode.parse(dataNode!)
        let keyMappingList = toKeyMappings(inputBindingArray, filterCommandsBy: { s in return true} )

        let mappingListStr = keyMappingList.enumerated().map { (index, mapping) in
          return "\t\(String(format: "%03d", index))   \(mapping.confFileFormat)"
        }.joined(separator: "\n")

        player.log.verbose("Δ mpv prop: \(MPVProperty.inputBindings.quoted)≔\n\(mappingListStr)")
      } catch {
        player.log.error("Failed to parse property data for \(MPVProperty.inputBindings.quoted)!")
      }

    default:
      player.log.verbose("Unhandled mpv prop: \(name.quoted)")
      break

    }

    // This code is running in the com.colliderli.iina.controller dispatch queue. We must not run
    // plugins from a task in this queue. Accessing EventController data from a thread in this queue
    // results in data races that can cause a crash. See issue 3986.
    DispatchQueue.main.async { [self] in
      let eventName = EventController.Name("mpv.\(name).changed")
      if player.events.hasListener(for: eventName) {
        // FIXME: better convert to JSValue before passing to call()
        let data: Any
        switch property.format {
        case MPV_FORMAT_FLAG:
          data = property.data.bindMemory(to: Bool.self, capacity: 1).pointee
        case MPV_FORMAT_INT64:
          data = property.data.bindMemory(to: Int64.self, capacity: 1).pointee
        case MPV_FORMAT_DOUBLE:
          data = property.data.bindMemory(to: Double.self, capacity: 1).pointee
        case MPV_FORMAT_STRING:
          data = property.data.bindMemory(to: String.self, capacity: 1).pointee
        default:
          data = 0
        }
        player.events.emit(eventName, data: data)
      }
    }
  }

  // MARK: - User Options


  private enum UserOptionType {
    case bool, int, float, string, color, other
  }

  private struct OptionObserverInfo {
    typealias Transformer = (Preference.Key) -> String?

    var prefKey: Preference.Key
    var optionName: String
    var valueType: UserOptionType
    /** input a pref key and return the option value (as string) */
    var transformer: Transformer?

    init(_ prefKey: Preference.Key, _ optionName: String, _ valueType: UserOptionType, _ transformer: Transformer?) {
      self.prefKey = prefKey
      self.optionName = optionName
      self.valueType = valueType
      self.transformer = transformer
    }
  }

  private var optionObservers: [String: [OptionObserverInfo]] = [:]

  private func setOptionFloat(_ name: String, _ value: Float, level: Logger.Level = .debug) -> Int32 {
    log.log("Set option: \(name)=\(value)", level: level)
    var data = Double(value)
    return mpv_set_option(mpv, name, MPV_FORMAT_DOUBLE, &data)
  }

  private func setOptionInt(_ name: String, _ value: Int, level: Logger.Level = .debug) -> Int32 {
    log.log("Set option: \(name)=\(value)", level: level)
    var data = Int64(value)
    return mpv_set_option(mpv, name, MPV_FORMAT_INT64, &data)
  }

  @discardableResult
  private func setOptionString(_ name: String, _ value: String, level: Logger.Level = .debug) -> Int32 {
    log.log("Set option: \(name)=\(value)", level: level)
    return mpv_set_option_string(mpv, name, value)
  }

  private func setOptionalOptionString(_ name: String, _ value: String?,
                                       level: Logger.Level = .debug) -> Int32 {
    guard let value = value else { return 0 }
    return setOptionString(name, value, level: level)
  }

  private func setUserOption(_ key: Preference.Key, type: UserOptionType, forName name: String,
                             sync: Bool = true, level: Logger.Level = .debug,
                             transformer: OptionObserverInfo.Transformer? = nil) {
    var code: Int32 = 0

    let keyRawValue = key.rawValue

    switch type {
    case .int:
      code = setOptionInt(name, Preference.integer(for: key), level: level)

    case .float:
      code = setOptionFloat(name, Preference.float(for: key), level: level)

    case .bool:
      let value = Preference.bool(for: key)
      code = setOptionString(name, value ? yes_str : no_str, level: level)

    case .string:
      code = setOptionalOptionString(name, Preference.string(for: key), level: level)

    case .color:
      let value = Preference.string(for: key)
      code = mpv_set_option_string(mpv, name, value)
      // Random error here (perhaps a Swift or mpv one), so set it twice
      // 「没有什么是 set 不了的；如果有，那就 set 两次」
      if code < 0 {
        code = setOptionalOptionString(name, value, level: level)
      }

    case .other:
      guard let tr = transformer else {
        log.error("setUserOption: no transformer!")
        return
      }
      if let value = tr(key) {
        code = setOptionString(name, value, level: level)
      } else {
        code = 0
      }
    }

    if code < 0 {
      let message = errorString(code)
      player.log.error("Displaying mpv msg popup for error (\(code), name: \(name.quoted)): \"\(message)\"")
      Utility.showAlert("mpv_error", arguments: [message, "\(code)", name])
    }

    if sync {
      UserDefaults.standard.addObserver(self, forKeyPath: keyRawValue, options: [.new, .old], context: nil)
      if optionObservers[keyRawValue] == nil {
        optionObservers[keyRawValue] = []
      }
      optionObservers[keyRawValue]!.append(OptionObserverInfo(key, name, type, transformer))
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard !(change?[NSKeyValueChangeKey.oldKey] is NSNull) else { return }

    guard let keyPath = keyPath else { return }
    guard let infos = optionObservers[keyPath] else { return }

    for info in infos {
      switch info.valueType {
      case .int:
        let value = Preference.integer(for: info.prefKey)
        setInt(info.optionName, value)

      case .float:
        let value = Preference.float(for: info.prefKey)
        setDouble(info.optionName, Double(value))

      case .bool:
        let value = Preference.bool(for: info.prefKey)
        setFlag(info.optionName, value)

      case .string:
        if let value = Preference.string(for: info.prefKey) {
          setString(info.optionName, value)
        }

      case .color:
        if let value = Preference.string(for: info.prefKey) {
          setString(info.optionName, value)
        }

      case .other:
        guard let tr = info.transformer else {
          log.error("setUserOption: no transformer!")
          return
        }
        if let value = tr(info.prefKey) {
          setString(info.optionName, value)
        }
      }
    }
  }

  // MARK: - Utils

  /**
   Utility function for checking mpv api error
   */
  private func chkErr(_ status: Int32!) {
    guard status < 0 else { return }
    DispatchQueue.main.async { [self] in
      let message = "mpv API error: \"\(String(cString: mpv_error_string(status)))\", Return value: \(status!)."
      player.log.error(message)
      Utility.showAlert("fatal_error", arguments: [message])
      player.shutdown()
      player.windowController.close()
    }
  }

  /// Log an error when a `mpv` property change event can't be processed because a property value could not be converted to the
  /// expected type.
  ///
  /// A [MPV_EVENT_PROPERTY_CHANGE](https://mpv.io/manual/stable/#command-interface-mpv-event-property-change)
  /// event contains the new value of the property. If that value could not be converted to the expected type then this method is called
  /// to log the problem.
  ///
  /// _However_ the situation is not that simple. The documentation for [mpv_observe_property](https://github.com/mpv-player/mpv/blob/023d02c9504e308ba5a295cd1846f2508b3dd9c2/libmpv/client.h#L1192-L1195)
  /// contains the following warning:
  ///
  /// "if a property is unavailable or retrieving it caused an error, `MPV_FORMAT_NONE` will be set in `mpv_event_property`, even
  /// if the format parameter was set to a different value. In this case, the `mpv_event_property.data` field is invalid"
  ///
  /// With mpv 0.35.0 we are receiving some property change events for the video-params/rotate property that do not contain the
  /// property value. This happens when the core starts before a file is loaded and when the core is stopping. At some point this needs
  /// to be investigated. For now we suppress logging an error for this known case.
  /// - Parameter property: Name of the property whose value changed.
  /// - Parameter format: Format of the value contained in the property change event.
  private func logPropertyValueError(_ property: String, _ format: mpv_format) {
    guard property != MPVProperty.videoParamsRotate, format != MPV_FORMAT_NONE else { return }
    log.error("""
    Value of property \(property) in the property change event could not be converted from
    \(format) to the expected type
    """)
  }
}

/// Searches the list of user configured `mpv` options and returns `true` if the given option is present.
/// - Parameter option: Option to look for.
/// - Returns: `true` if the `mpv` option is found, `false` otherwise.
private func userOptionsContains(_ option: String) -> Bool {
  guard Preference.bool(for: .enableAdvancedSettings),
        let userOptions = Preference.value(for: .userOptions) as? [[String]] else { return false }
  return userOptions.contains { $0[0] == option }
}

fileprivate func mpvGetOpenGLFunc(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
  let symbolName: CFString = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
  guard let addr = CFBundleGetFunctionPointerForName(CFBundleGetBundleWithIdentifier(CFStringCreateCopy(kCFAllocatorDefault, "com.apple.opengl" as CFString)), symbolName) else {
    Logger.fatal("Cannot get OpenGL function pointer!")
  }
  return addr
}

fileprivate func mpvUpdateCallback(_ ctx: UnsafeMutableRawPointer?) {
  let layer = bridge(ptr: ctx!) as GLVideoLayer
  layer.drawAsync()
}
