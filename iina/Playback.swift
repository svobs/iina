//
//  Playback.swift
//  iina
//
//  Created by Matt Svoboda on 7/8/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// Encapsulates the load status & other runtime metadata relating to a single playback of a given media.
///
/// An instance of this class should be created as soon as the user indicates their intent to play the media,
/// and should not be reused for subsequent play(s).
class Playback: CustomStringConvertible {
  var description: String {
    return "Playback(plPos:\(playlistPos) status:\(state) path:\(path.pii.quoted))"
  }

  /// State of the individual playack
  enum LifecycleState: Int, StateEnum, CustomStringConvertible {
    case notYetStarted = 1    /// set before mpv is aware of it
    case started              /// set after mpv sends `fileStarted` notification
    case loaded               /// set after mpv sends `fileLoaded` notification & IINA has processed it
    case loadedAndSized
    case ended                /// Not used at present

    var description: String {
      switch self {
      case .notYetStarted:
        return "notYetStarted"
      case .started:
        return "started"
      case .loaded:
        return "loaded"
      case .loadedAndSized:
        return "loadedAndSized"
      case .ended:
        return "ended"
      }
    }

    func isAtLeast(_ minStatus: LifecycleState) -> Bool {
      return rawValue >= minStatus.rawValue
    }

    func isNotYet(_ status: LifecycleState) -> Bool {
      return rawValue < status.rawValue
    }
  }  /// `Playback.LifecycleState`

  let url: URL
  let mpvMD5: String

  var playlistPos: Int

  /// Lifecycle state of this playback
  var state: LifecycleState {
    willSet {
      if newValue != state {
        Logger.log("Δ Playback.lifecycleState: \(state) → \(newValue)")
      }
    }
  }

  var path: String {
    return Playback.path(from: url)
  }

  var isNetworkResource: Bool {
    return !url.isFileURL
  }

  var thumbnails: SingleMediaThumbnailsLoader? = nil

  var isFileLoaded: Bool {
    return state.isAtLeast(.loaded)
  }

  /// if `url` is `nil`, assumed to be `stdin`
  init(url: URL?, playlistPos: Int = 0, state: LifecycleState = .notYetStarted) {
    let url = url ?? URL(string: "stdin")!
    self.url = url
    mpvMD5 = Utility.mpvWatchLaterMd5(url.path)
    self.playlistPos = playlistPos
    self.state = state
  }

  convenience init?(path: String, playlistPos: Int = 0, state: LifecycleState = .notYetStarted) {
    let url = Playback.url(fromPath: path)
    guard let url else { return nil }
    self.init(url: url, playlistPos: playlistPos, state: state)
  }

  static func path(from url: URL?) -> String {
    let url = url ?? URL(string: "stdin")!
    if url.absoluteString == "stdin" {
      return "-"
    } else {
      return url.isFileURL ? url.path : url.absoluteString
    }
  }

  static func url(fromPath path: String) -> URL? {
    if path.contains("://") {
      return URL(string: path.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? path)
    } else {
      return URL(fileURLWithPath: path)
    }
  }
}
