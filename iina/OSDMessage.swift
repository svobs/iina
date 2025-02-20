//
//  OSDMessage.swift
//  iina
//
//  Created by lhc on 27/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

/// Available constants in OSD messages:
///
/// {{duration}}
/// {{position}}
/// {{percentPos}}
/// {{currChapter}}
/// {{chapterCount}}

import Foundation

fileprivate func toPercent(_ value: Double, _ bound: Double) -> Double {
  return (value + bound).clamped(to: 0...(bound * 2)) / (bound * 2)
}

enum OSDType {
  case normal
  case withText(String)
  case withProgress(Double)
  case withLeftToRightProgress(Double)  // always left-to-right, even for R2L languages
  case withLeftToRightText(String)
}

enum OSDMessage {

  case debug(String, String)
  case fileStart(String, String)

  case pause(playbackPositionSec: Double, playbackDurationSec: Double)
  case resume(playbackPositionSec: Double, playbackDurationSec: Double)
  case resumeFromWatchLater
  case seekRelative(step: String)
  case seek(playbackPositionSec: Double, playbackDurationSec: Double)
  case frameStep
  case frameStepBack
  case volume(Int)
  case speed(Double)
  case aspect(String)
  case crop(String)
  case rotation(Int)
  case deinterlace(Bool)
  case hwdec(Bool)
  case audioDelay(Double)
  case subDelay(Double)
  case subScale(Double)
  case subHidden
  case subVisible
  case secondSubDelay(Double)
  case secondSubHidden
  case secondSubPos(Double)
  case secondSubVisible
  case subPos(Double)
  case mute(Int)
  case unMute(Int)
  case screenshot
  case abLoop(LoopStatus)
  case abLoopUpdate(LoopStatus, String)
  case stop
  case chapter(String)
  case track(MPVTrack)
  case audioTrack(MPVTrack, Double)
  case addToPlaylist(Int)
  case clearPlaylist

  case contrast(Int)
  case hue(Int)
  case saturation(Int)
  case brightness(Int)
  case gamma(Int)

  case addFilter(String)
  case removeFilter

  case startFindingSub(String)  // sub source
  case foundSub(Int)
  case downloadingSub(Int, String)  // download count, sub source
  case downloadedSub(String)  // filename
  case savedSub
  case cannotLogin
  case fileError
  case networkError
  case canceled
  case cannotConnect
  case timedOut

  case fileLoop
  case playlistLoop
  case noLoop

  case custom(String)
  case customWithDetail(String, String)

  /// `True` if this OSD message has been suppressed by the user, otherwise `false`.
  ///
  /// Through settings on the `UI` tab a user can choose to not have certain OSD messages shown. This is useful in certain
  /// applications such as looping in a kiosk or scrubbing through a video without distractions.
  var isDisabled: Bool {
    switch self {
    case .fileStart: return Preference.bool(for: .disableOSDFileStartMsg)
    case .pause: return Preference.bool(for: .disableOSDPauseResumeMsgs)
    case .resume: return Preference.bool(for: .disableOSDPauseResumeMsgs)
    case .seek: return Preference.bool(for: .disableOSDSeekMsg)
    case .speed: return Preference.bool(for: .disableOSDSpeedMsg)
    default: return false
    }
  }

  /// `True` if this message must always be shown, otherwise `false`.
  ///
  /// A user may disable the OSD by unchecking the `Enable OSD` setting found on the `UI` tab in the `On Screen Display`
  /// section of IINA's settings. Or they may check the `Use mpv's OSD` setting found on the `Advanced` tab which implicitly
  /// disables IINA's OSD. _However_ not all OSD messages are optional notifications. The `Find Online Subtitles` feature
  /// uses the OSD for its user interface. These messages must still be displayed when the OSD is disabled.
  var alwaysEnabled: Bool {
    switch self {
    case .debug: fallthrough
    case .canceled: fallthrough
    case .cannotConnect: fallthrough
    case .cannotLogin: fallthrough
    case .downloadedSub: fallthrough
    case .fileError: fallthrough
    case .foundSub: fallthrough
    case .networkError: fallthrough
    case .savedSub: fallthrough
    case .startFindingSub: fallthrough
    case .timedOut:
      return true
    default: return false
    }
  }

  var isSoundRelated: Bool {
    switch self {
    case .volume, .audioDelay, .mute, .unMute, .audioTrack(_, _):
      return true
    case .track(let track):
      return track.type == .audio
    default:
      return false
    }
  }

  func details() -> (String, OSDType) {
    switch self {
    case .debug(let msg, let detailMsg):
      if detailMsg.isEmpty {
        // Omit caption if there is nothing to display in it
        return (msg, .normal)
      }
      return (msg, .withText(detailMsg))
    case .fileStart(let filename, let detailMsg):
      if detailMsg.isEmpty {
        // Omit caption if there is nothing to display in it
        return (filename, .normal)
      }
      return (filename, .withText(detailMsg))

    case .pause(let playbackPositionSec, let playbackDurationSec),
        .resume(let playbackPositionSec, let playbackDurationSec),
        .seek(let playbackPositionSec, let playbackDurationSec):
      let posStr = VideoTime.string(from: playbackPositionSec)
      guard playbackDurationSec > 0.0 else {
        let text = "\(posStr)"
        return (text, .normal)
      }
      let durStr = VideoTime.string(from: playbackDurationSec)
      let text = "\(posStr) / \(durStr)"
      let percentage: Double
      percentage = playbackPositionSec / playbackDurationSec
      return (text, .withLeftToRightProgress(percentage))

    case .resumeFromWatchLater:
      return ("Restored playback from watch-later", .normal)

    case .frameStep:
      return (NSLocalizedString("osd.frame_step", comment: "Next Frame"), .normal)

    case .frameStepBack:
      return (NSLocalizedString("osd.frame_step_back", comment: "Previous Frame"), .normal)

    case .seekRelative(let step):
      return (step, .normal)

    case .volume(let value):
      return (
        String(format: NSLocalizedString("osd.volume", comment: "Volume: %i"), value),
        .withProgress(Double(value) / Double(Preference.integer(for: .maxVolume)))
      )

    case .speed(let value):
      return (
        String(format: NSLocalizedString("osd.speed", comment: "Speed: %@x"), value.string),
        .normal
      )

    case .aspect(var value):
      if value == "Default" {
        value = Constants.String.default
      }
      return (
        String(format: NSLocalizedString("osd.aspect", comment: "Aspect Ratio: %@"), value),
        .normal
      )

    case .crop(var value):
      if value == "None" {
        value = Constants.String.none
      }
      return (
        String(format: NSLocalizedString("osd.crop", comment: "Crop: %@"), value),
        .normal
      )

    case .rotation(let value):
      return (
        String(format: NSLocalizedString("osd.rotate", comment: "Rotation: %i°"), value),
        .normal
      )

    case .deinterlace(let enabled):
      return (
        String(format: NSLocalizedString("osd.deinterlace", comment: "Deinterlace: %@"), enabled ? NSLocalizedString("general.on", comment: "On") : NSLocalizedString("general.off", comment: "Off")),
        .normal
      )

    case .hwdec(let enabled):
      return (
        String(format: NSLocalizedString("osd.hwdec", comment: "Hardware Decoding: %@"), enabled ? NSLocalizedString("general.on", comment: "On") : NSLocalizedString("general.off", comment: "Off")),
        .normal
      )

    case .audioDelay(let value):
      if value == 0.0 {
        return (
          NSLocalizedString("osd.audio_delay.nodelay", comment: "Audio Delay: No Delay"),
          .withProgress(0.5)
        )
      }

      let delayString = abs(value).string
      let str: String
      if value > 0.0 {
        str = String(format: NSLocalizedString("osd.audio_delay.later", comment: "Audio Delay: %@s Later"),
                     delayString)
      } else {
        str = String(format: NSLocalizedString("osd.audio_delay.earlier", comment: "Audio Delay: %@s Earlier"),
                     delayString)
      }
      return (str, .withProgress(toPercent(value, 10)))

    case .secondSubDelay(let value):
      if value == 0 {
        return (NSLocalizedString("osd.sub_second_delay.nodelay", comment: "Secondary Subtitle Delay: No Delay"),
          .withProgress(0.5))
      }

      let delayString = abs(value).string
      let str: String
      if value > 0.0 {
        str = String(format: NSLocalizedString("osd.sub_second_delay.later", comment: "Secondary Subtitle Delay: %@s Later"),
                     delayString)
      } else {
        str = String(format: NSLocalizedString("osd.sub_second_delay.earlier", comment: "Secondary Subtitle Delay: %@s Earlier"),
                     delayString)
      }
      return (str, .withProgress(toPercent(value, 10)))

    case .secondSubPos(let value):
      return (
        String(format: NSLocalizedString("osd.sub_second_pos", comment: "Secondary Subtitle Position: %f"), value),
        .withProgress(value / 100)
      )

    case .subDelay(let value):
      if value == 0 {
        return (NSLocalizedString("osd.sub_delay.nodelay", comment: "Subtitle Delay: No Delay"),
                .withProgress(0.5))
      }

      let delayString = abs(value).string
      let str: String
      if value > 0.0 {
        str = String(format: NSLocalizedString("osd.sub_delay.later", comment: "Subtitle Delay: %@s Later"),
                     delayString)
      } else {
        str = String(format: NSLocalizedString("osd.sub_delay.earlier", comment: "Subtitle Delay: %@s Earlier"),
                     delayString)
      }
      return (str, .withProgress(toPercent(value, 10)))

    case .subPos(let value):
      return (
        String(format: NSLocalizedString("osd.subtitle_pos", comment: "Subtitle Position: %f"), value),
        .withProgress(value / 100)
      )

    case .subHidden:
      return (NSLocalizedString("osd.sub_hidden", comment: "Subtitles Hidden"), .normal)

    case .subVisible:
      return (NSLocalizedString("osd.sub_visible", comment: "Subtitles Visible"), .normal)

    case .secondSubHidden:
      return (NSLocalizedString("osd.sub_second_hidden", comment: "Second Subtitles Hidden"), .normal)

    case .secondSubVisible:
      return (NSLocalizedString("osd.sub_second_visible", comment: "Second Subtitles Visible"), .normal)

    case .mute(let volume):
      return (NSLocalizedString("osd.mute", comment: "Mute"),
        .withProgress(Double(volume) / Double(Preference.integer(for: .maxVolume))))

    case .unMute(let volume):
      return (NSLocalizedString("osd.unmute", comment: "Unmute"),
              .withProgress(Double(volume) / Double(Preference.integer(for: .maxVolume))))

    case .screenshot:
      return (NSLocalizedString("osd.screenshot", comment: "Screenshot Captured"), .normal)

    case .abLoop(let value):
      // The A-B loop command was invoked.
      switch (value) {
      case .cleared:
        return (NSLocalizedString("osd.abloop.clear", comment: "AB-Loop: Cleared"), .normal)
      case .aSet:
        return (NSLocalizedString("osd.abloop.a", comment: "AB-Loop: A"),
                .withLeftToRightText("{{position}} / {{duration}}"))
      case .bSet:
        return (NSLocalizedString("osd.abloop.b", comment: "AB-Loop: B"),
                .withLeftToRightText("{{position}} / {{duration}}"))
      }

    case .abLoopUpdate(let value, let position):
      // One of the A-B loop points has been updated to the given position.
      switch (value) {
      case .cleared:
        Logger.fatal("Attempt to display invalid OSD message, type: .abLoopUpdate value: .cleared position \(position)")
      case .aSet:
        return (NSLocalizedString("osd.abloop.a", comment: "AB-Loop: A"),
                .withLeftToRightText("\(position) / {{duration}}"))
      case .bSet:
        return (NSLocalizedString("osd.abloop.b", comment: "AB-Loop: B"),
                .withLeftToRightText("\(position) / {{duration}}"))
      }

    case .stop:
      return (NSLocalizedString("osd.stop", comment: "Stop"), .normal)

    case .chapter(let name):
      return (
        String(format: NSLocalizedString("osd.chapter", comment: "Chapter: %@"), name),
        .withLeftToRightText("({{currChapter}}/{{chapterCount}}) {{position}} / {{duration}}")
      )

    case .audioTrack(let track, let volume):
      return ("Audio: " + track.readableTitle,
              .withProgress(Double(volume) / Double(Preference.integer(for: .maxVolume))))

    case .track(let track):
      let keySuffix: String
      switch track.type {
      case .video: keySuffix = "video"
      case .audio: keySuffix = "audio"
      case .sub: keySuffix = "sub"
      case .secondSub:
        // This enum constant is only used for setting the secondary subtitle. No track should use
        // this type. This is an internal error.
        Logger.log("Invalid subtitle track type: secondSub", level: .error)
        keySuffix = "sub"
      }
      let trackTypeStr = String(format: NSLocalizedString("track." + keySuffix,
        comment: "Kind of track (Audio, Video, Subtitle)"))
      return (trackTypeStr + ": " + track.readableTitle, .normal)

    case .subScale(let value):
      return (
        String(format: NSLocalizedString("osd.subtitle_scale", comment: "Subtitle Scale: %.2fx"), value),
        .normal
      )

    case .addToPlaylist(let count):
      return (
        String(format: NSLocalizedString("osd.add_to_playlist", comment: "Added %i Files to Playlist"), count),
        .normal
      )

    case .clearPlaylist:
      return (NSLocalizedString("osd.clear_playlist", comment: "Cleared Playlist"), .normal)

    case .contrast(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.contrast", comment: "Contrast: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .gamma(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.gamma", comment: "Grama: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .hue(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.hue", comment: "Hue: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .saturation(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.saturation", comment: "Saturation: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .brightness(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.brightness", comment: "Brightness: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .addFilter(let name):
      return (
        String(format: NSLocalizedString("osd.filter_added", comment: "Added Filter: %@"), name),
        .normal
      )

    case .removeFilter:
      return (
        NSLocalizedString("osd.filter_removed", comment: "Removed Filter"),
        .normal
      )

    case .startFindingSub(let source):
      return (
        NSLocalizedString("osd.find_online_sub", comment: "Finding online subtitles..."),
        .withText(NSLocalizedString("osd.find_online_sub.source", comment: "from") + " " + source)
      )

    case .foundSub(let count):
      let str = count == 0 ?
        NSLocalizedString("osd.sub_not_found", comment: "No subtitles found.") :
        String(format: NSLocalizedString("osd.sub_found", comment: "%d subtitle(s) found."), count)
      return (str, .normal)

    case .downloadingSub(let count, let source):
      let str = String(format: NSLocalizedString("osd.sub_downloading", comment: "Downloading %d subtitles"), count)
      return (str, .withText(NSLocalizedString("osd.find_online_sub.source", comment: "from") + " " + source))

    case .downloadedSub(let filename):
      return (
        NSLocalizedString("osd.sub_downloaded", comment: "Subtitle downloaded"),
        .withText(filename)
      )

    case .savedSub:
      return (
        NSLocalizedString("osd.sub_saved", comment: "Subtitle saved"),
        .normal
      )

    case .networkError:
      return (
        NSLocalizedString("osd.network_error", comment: "Network error"),
        .normal
      )

    case .fileError:
      return (
        NSLocalizedString("osd.file_error", comment: "Error reading file"),
        .normal
      )

    case .cannotLogin:
      return (
        NSLocalizedString("osd.cannot_login", comment: "Cannot login"),
        .normal
      )

    case .canceled:
      return (
        NSLocalizedString("osd.canceled", comment: "Canceled"),
        .normal
      )

    case .cannotConnect:
      return (
        NSLocalizedString("osd.cannot_connect", comment: "Cannot connect"),
        .normal
      )

    case .timedOut:
      return (
        NSLocalizedString("osd.timed_out", comment: "Timed out"),
        .normal
      )

    case .fileLoop:
      return (
        NSLocalizedString("osd.file_loop", comment: "Enable file looping"),
          .normal
      )

    case .playlistLoop:
      return (
        NSLocalizedString("osd.playlist_loop", comment: "Enable playlist looping"), 
          .normal
      )

    case .noLoop:
      return (
        NSLocalizedString("osd.no_loop", comment: "Disable loop"),
          .normal
      )

    case .custom(let message):
      return (message, .normal)

    case .customWithDetail(let message, let detail):
      return (message, .withText(detail))
    }
  }
}
