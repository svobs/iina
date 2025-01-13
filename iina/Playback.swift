//
//  Playback.swift
//  iina
//
//  Created by Matt Svoboda on 2024-07-08.
//

import Foundation

/// Encapsulates the load status & other runtime metadata relating to a single playback of a given media.
///
/// An instance of this class should be created as soon as the user indicates their intent to play the media,
/// and should not be reused for subsequent play(s).
class Playback: CustomStringConvertible {

  /// State of the individual playack
  enum LifecycleState: Int, StateEnum, CustomStringConvertible {
    case notYetStarted = 1    /// set before mpv is aware of it
    case started              /// set after mpv sends `fileStarted` notification
    case loaded               /// set after mpv sends `fileLoaded` notification & IINA has processed it
    case loadedAndSized       /// see `vidTrackLastSized`
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
  }  /// end `enum Playback.LifecycleState`


  /// Lifecycle state of this playback
  var state: LifecycleState {
    willSet {
      if newValue != state {
        Logger.log("Δ Playback.lifecycleState: \(state) → \(newValue)")
      }
    }
  }

  let url: URL
  let mpvMD5: String

  /// Can be `nil` if not loaded yet
  var playlistPos: Int?

  var parentPlaylist: String = ""

  /// This must match the current `vid` track for the given media when determining whether a complete update is needed to VideoGeometry.
  ///
  /// Is set to `nil` initially because such an update must always run when state transitions to `fileLoaded`.
  var vidTrackLastSized: Int? = nil

  var path: String {
    return Playback.path(from: url)
  }

  var isNetworkResource: Bool {
    return !url.isFileURL
  }

  var thumbnails: SingleMediaThumbnailsLoader? = nil

  var displayName: String {
    return Playback.displayName(from: url)
  }

  var description: String {
    return "Playback(plPos:\(String(playlistPos)) status:\(state) path:\(path.pii.quoted))"
  }

  /// if `url` is `nil`, assumed to be `stdin`
  init(url: URL?, playlistPos: Int? = nil, state: LifecycleState = .notYetStarted) {
    let url = url ?? URL(string: "stdin")!
    self.url = url
    mpvMD5 = Utility.mpvWatchLaterMd5(url.path)
    self.playlistPos = playlistPos
    self.state = state
  }

  convenience init?(urlPath: String, playlistPos: Int? = nil, state: LifecycleState = .notYetStarted) {
    let url = Playback.url(fromPath: urlPath)
    guard let url else { return nil }
    self.init(url: url, playlistPos: playlistPos, state: state)
  }

  /// Do not use `url.path` for an unknown URL. Use this instead. It will handle both files and network URLs.
  static func path(from url: URL?) -> String {
    let url = url ?? URL(string: "stdin")!
    if url.absoluteString == "stdin" {
      return "-"
    } else {
      return url.isFileURL ? url.path : url.absoluteString
    }
  }

  /// Returns the name of this resource as it should be displayed in the UI. Does not account for its `title` or other metadata.
  static func displayName(from url: URL?) -> String {
    guard let url else { return "-" }
    let urlPath = Playback.path(from: url)
    let isNetworkResource = !url.isFileURL
    return isNetworkResource ? urlPath : NSString(string: urlPath).lastPathComponent
  }

  /// Converts `urlPath` from what mpv calls `filename` in its APIs.
  ///
  /// This is a string which follows one of the following formats:
  /// 1. If a file resource, a file path in slash notation
  /// 2. If a network resource, a URL string in protocol://domain/resource/etc notation
  static func url(fromPath urlPath: String) -> URL? {
    if urlPath.contains("://") {
      return URL(string: urlPath.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? urlPath)
    } else {
      return URL(fileURLWithPath: urlPath)
    }
  }
}
