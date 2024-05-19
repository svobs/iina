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
  var log = Logger.Subsystem(rawValue: "history")
  var folderMonitor = FolderMonitor(url: Utility.watchLaterURL)

  var cachedRecentDocumentURLs: [URL]

  init(plistFileURL: URL) {
    self.plistURL = plistFileURL
    self.history = []
    cachedRecentDocumentURLs = []
  }

  private func watchLaterDirDidChange() {
    log.verbose("WatchLaterDir changed")
    NotificationCenter.default.post(Notification(name: .watchLaterDirDidChange))
  }

  func start() {
    // Launch this as a background task! Resolution can take a long time if waiting for remote servers to time out
    // and we don't want to tie up the main thread.
    queue.async { [self] in
      // Make sure to start listening before reload, to avoid creating race condition
      log.debug("Starting to watch for watch-later dir")
      folderMonitor.folderDidChange = self.watchLaterDirDidChange
      folderMonitor.startMonitoring()

      reloadAll(silent: true)

      // Workaround for macOS Sonoma clearing the recent documents list when the IINA code is not signed
      // with IINA's certificate as is the case for developer and nightly builds.
      restoreRecentDocuments()
    }
  }

  func stop() {
    log.debug("Stopping watchdog for watch-later dir")
    folderMonitor.stopMonitoring()
  }

  func reloadAll(silent: Bool = false) {
    dispatchPrecondition(condition: .onQueue(queue))

    log.verbose("ReloadAll starting from \(plistURL.path.pii.quoted)")
    let sw = Utility.Stopwatch()
    history = (NSKeyedUnarchiver.unarchiveObject(withFile: plistURL.path) as? [PlaybackHistory]) ?? []
    cachedRecentDocumentURLs = NSDocumentController.shared.recentDocumentURLs
    log.verbose("ReloadAll done: \(history.count) history entries & \(cachedRecentDocumentURLs.count) recentDocuments in \(sw.secElapsedString)")
    if !silent {
      log.verbose("ReloadAll: posting iinaHistoryUpdated")
      NotificationCenter.default.post(Notification(name: .iinaHistoryUpdated))

      log.verbose("ReloadAll: posting recentDocumentsDidChange")
      NotificationCenter.default.post(Notification(name: .recentDocumentsDidChange))
    }
  }

  private func save() {
    let result = NSKeyedArchiver.archiveRootObject(history, toFile: plistURL.path)
    if !result {
      log.error("Failed to save playback history!")
    }
    log.verbose("Saved history; posting iinaHistoryUpdated")
    NotificationCenter.default.post(Notification(name: .iinaHistoryUpdated))
  }

  func add(_ url: URL, duration: Double) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard Preference.bool(for: .recordPlaybackHistory) else { return }
    if let existingItem = history.first(where: { $0.mpvMd5 == url.path.md5 }), let index = history.firstIndex(of: existingItem) {
      history.remove(at: index)
    }
    history.insert(PlaybackHistory(url: url, duration: duration), at: 0)
    save()
  }

  func remove(_ entries: [PlaybackHistory]) {
    dispatchPrecondition(condition: .onQueue(queue))
    history = history.filter { !entries.contains($0) }
    save()
  }

  func removeAll() {
    queue.async { [self] in
      Logger.log("Clearing all history")
      try? FileManager.default.removeItem(atPath: Utility.playbackHistoryURL.path)
      clearRecentDocuments(nil)
      Preference.set(nil, for: .iinaLastPlayedFilePath)

      reloadAll()
    }
  }

  // MARK: - Recent Documents

  /// Empties the recent documents list for the application.
  func clearRecentDocuments(_ sender: Any?) {
    queue.async { [self] in
      Logger.log("Clearing recent documents")
      NSDocumentController.shared.clearRecentDocuments(sender)
      saveRecentDocuments()
    }
  }

  /// Adds or replaces an Open Recent menu item corresponding to the data located by the URL.
  ///
  /// This is part of a workaround for macOS Sonoma clearing the list of recent documents. See the method
  /// `restoreRecentDocuments` and the issue [#4688](https://github.com/iina/iina/issues/4688) for more
  /// information..
  /// - Parameter url: The URL to evaluate.
  func noteNewRecentDocumentURL(_ url: URL) {
    dispatchPrecondition(condition: .onQueue(queue))

    NSDocumentController.shared.noteNewRecentDocumentURL(url)
    saveRecentDocuments()
  }

  /// Restore the list of recently opened files.
  ///
  /// For macOS Sonoma `sharedfilelistd` was changed to tie the list of recent documents to the app based on its certificate.
  /// if `sharedfilelistd` determines the list is being accessed by a different app then it clears the list. See issue
  /// [#4688](https://github.com/iina/iina/issues/4688) for details.
  ///
  /// This new behavior does not cause a problem when the code is signed with IINA's certificate. However developer and nightly
  /// builds use an ad hoc certificate. This causes the list of recently opened files to be cleared each time a different unsigned IINA build
  /// is run. As a workaround a copy of the list of recent documents is saved in IINA's preference file to preserve the list and allow it to
  /// be restored when `sharedfilelistd` clears its list.
  ///
  /// If the following is true:
  /// - Running under macOS Sonoma and above
  /// - Recording of recent files is enabled
  /// - The list in  [NSDocumentController.shared.recentDocumentURLs](https://developer.apple.com/documentation/appkit/nsdocumentcontroller/1514976-recentdocumenturls) is empty
  /// - The list in the IINA setting `recentDocuments` is not empty
  ///
  /// Then this method assumes that the macOS daemon `sharedfilelistd` cleared the list and it populates the list of recent
  /// document URLs with the list stored in IINA's settings.
  private func restoreRecentDocuments() {
    dispatchPrecondition(condition: .onQueue(queue))

    /// Make sure `reloadAll()` was called before this
    let recentDocumentsURLs = cachedRecentDocumentURLs
    guard #available(macOS 14, *), Preference.bool(for: .recordRecentFiles),
          recentDocumentsURLs.isEmpty,
          let recentDocuments = Preference.array(for: .recentDocuments),
          !recentDocuments.isEmpty else {
      log.verbose("Will not restore list of recent documents from prefs")
      return
    }

    log.debug("Restoring list of recent documents from prefs...")

    var newRecentDocuments: [URL] = []
    var foundStale = false
    for document in recentDocuments {
      var isStale = false
      guard let asData = document as? Data,
            let bookmark = try? URL(resolvingBookmarkData: asData, bookmarkDataIsStale: &isStale) else {
        guard let asString = document as? String, let url = URL(string: asString) else { continue }
        // Saving as a bookmark must have failed and instead the URL was saved as a string.
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        newRecentDocuments.append(url)
        continue
      }
      foundStale = foundStale || isStale
      NSDocumentController.shared.noteNewRecentDocumentURL(bookmark)
      newRecentDocuments.append(bookmark)
    }
    cachedRecentDocumentURLs = newRecentDocuments

    if foundStale {
      log.debug("Found stale bookmarks in saved recent documents")
      // Save the recent documents in order to refresh stale bookmarks.
      saveRecentDocuments()
    }

    log.debug("Done restoring list of recent documents (\(newRecentDocuments.count)). Posting recentDocumentsDidChange")
    NotificationCenter.default.post(Notification(name: .recentDocumentsDidChange))
  }

  /// Save the list of recently opened files.
  ///
  /// Save the list of recent documents in [NSDocumentController.shared.recentDocumentURLs](https://developer.apple.com/documentation/appkit/nsdocumentcontroller/1514976-recentdocumenturls)
  /// to `recentDocuments` in the IINA settings property file.
  ///
  /// This is part of a workaround for macOS Sonoma clearing the list of recent documents. See the method
  /// `restoreRecentDocuments` and the issue [#4688](https://github.com/iina/iina/issues/4688) for more
  /// information..
  func saveRecentDocuments() {
    dispatchPrecondition(condition: .onQueue(queue))

    defer {
      // Notify even for older MacOS
      NotificationCenter.default.post(Notification(name: .recentDocumentsDidChange))
    }

    guard #available(macOS 14, *) else { return }
    var recentDocuments: [Any] = []
    for document in NSDocumentController.shared.recentDocumentURLs {
      guard let bookmark = try? document.bookmarkData() else {
        // Fall back to storing a string when unable to create a bookmark.
        recentDocuments.append(document.absoluteString)
        continue
      }
      recentDocuments.append(bookmark)
    }
    Preference.set(recentDocuments, for: .recentDocuments)
    if recentDocuments.isEmpty {
      log.debug("Cleared list of recent documents")
    } else {
      log.debug("Saved list of recent documents")
    }
  }
}
