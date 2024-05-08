//
//  HistoryController.swift
//  iina
//
//  Created by lhc on 25/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class HistoryController {

  static let shared = HistoryController(plistFileURL: Utility.playbackHistoryURL)

  var plistURL: URL
  var history: [PlaybackHistory]
  var queue = DispatchQueue(label: "IINAHistoryController", qos: .background)

  var cachedRecentDocumentURLs: [URL]

  init(plistFileURL: URL) {
    self.plistURL = plistFileURL
    self.history = []
    cachedRecentDocumentURLs = []
  }

  func reloadAll(silent: Bool = false) {
    dispatchPrecondition(condition: .onQueue(HistoryController.shared.queue))
    Logger.log("Reloading playback history from \(plistURL.path.pii.quoted)")
    var sw = Utility.Stopwatch()
    history = (NSKeyedUnarchiver.unarchiveObject(withFile: plistURL.path) as? [PlaybackHistory]) ?? []
    Logger.log("Finished reloading playback history (\(history.count) entries) in \(sw.secElapsedString)")
    sw = Utility.Stopwatch()
    cachedRecentDocumentURLs = NSDocumentController.shared.recentDocumentURLs
    Logger.log("Finished reloading \(cachedRecentDocumentURLs.count) recentDocuments in \(sw.secElapsedString)")
    if !silent {
      Logger.log("Posting iinaHistoryUpdated after History reloadAll", level: .verbose)
      NotificationCenter.default.post(Notification(name: .iinaHistoryUpdated))
    }
  }

  private func save() {
    let result = NSKeyedArchiver.archiveRootObject(history, toFile: plistURL.path)
    if !result {
      Logger.log("Cannot save playback history!", level: .error)
    }
    Logger.log("Posting iinaHistoryUpdated after History save", level: .verbose)
    NotificationCenter.default.post(Notification(name: .iinaHistoryUpdated))
  }

  func add(_ url: URL, duration: Double) {
    guard Preference.bool(for: .recordPlaybackHistory) else { return }
    if let existingItem = history.first(where: { $0.mpvMd5 == url.path.md5 }), let index = history.firstIndex(of: existingItem) {
      history.remove(at: index)
    }
    history.insert(PlaybackHistory(url: url, duration: duration), at: 0)
    save()
  }

  func remove(_ entries: [PlaybackHistory]) {
    history = history.filter { !entries.contains($0) }
    save()
  }

  func removeAll() {
    history.removeAll()
    save()
  }

}
