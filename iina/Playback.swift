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
    return "Playback(plPos:\(playlistPos) status:\(loadStatus) path:\(path.pii.quoted))"
  }

  enum LoadStatus: Int, StatusEnum, CustomStringConvertible {
    
    case notYetStarted = 1       /// set before mpv is aware of it
    case started              /// set after mpv sends `fileStarted` notification
    case loaded               /// set after mpv sends `fileLoaded` notification
    case completelyLoaded     /// everything loaded by mpv, including filters
    case ended                /// Not used at present

    var description: String {
      switch self {
      case .notYetStarted:
        return "notYetStarted"
      case .started:
        return "started"
      case .loaded:
        return "loaded"
      case .completelyLoaded:
        return "completelyLoaded"
      case .ended:
        return "ended"
      }
    }

    func isAtLeast(_ minStatus: LoadStatus) -> Bool {
      return rawValue >= minStatus.rawValue
    }

    func isNotYet(_ status: LoadStatus) -> Bool {
      return rawValue < status.rawValue
    }
  }  /// `Playback.LoadStatus`

  let url: URL
  let mpvMD5: String

  var playlistPos: Int
  var loadStatus: LoadStatus {
    willSet {
      if newValue != loadStatus {
        Logger.log("Δ Media LoadStatus: \(loadStatus) → \(newValue)")
      }
    }
  }

  var path: String {
    return Playback.path(for: url)
  }

  var isNetworkResource: Bool {
    return !url.isFileURL
  }

  var thumbnails: SingleMediaThumbnailsLoader? = nil

  var isFileLoaded: Bool {
    return loadStatus.rawValue >= LoadStatus.loaded.rawValue
  }

  /// if `url` is `nil`, assumed to be `stdin`
  init(url: URL?, playlistPos: Int = 0, loadStatus: LoadStatus = .notYetStarted) {
    let url = url ?? URL(string: "stdin")!
    self.url = url
    mpvMD5 = Utility.mpvWatchLaterMd5(url.path)
    self.playlistPos = playlistPos
    self.loadStatus = loadStatus
  }

  convenience init?(path: String, playlistPos: Int = 0, loadStatus: LoadStatus = .notYetStarted) {
    let url = path.contains("://") ?
    URL(string: path.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? path) :
    URL(fileURLWithPath: path)
    guard let url else { return nil }
    self.init(url: url, playlistPos: playlistPos, loadStatus: loadStatus)
  }

  static func path(for url: URL?) -> String {
    let url = url ?? URL(string: "stdin")!
    if url.absoluteString == "stdin" {
      return "-"
    } else {
      return url.isFileURL ? url.path : url.absoluteString
    }
  }
}
