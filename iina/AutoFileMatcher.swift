//
//  AutoFileMatcher.swift
//  iina
//
//  Created by lhc on 7/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class AutoFileMatcher {

  private enum TicketExpiredError: Error {
    case ticketExpired
  }

  weak private var player: PlayerCore!
  var ticket: Int

  private let fm = FileManager.default
  private let searchOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]

  private var currentFolder: URL!

  private var videoFiles: [FileInfo] = []
  private var audioFiles: [FileInfo] = []
  private var subFiles: [FileInfo] = []

  private var videosGroupedBySeries: [String: [FileInfo]] = [:]
  private var subtitles: [FileInfo] = []
  private var subsGroupedBySeries: [String: [FileInfo]] = [:]
  private var unmatchedVideos: [FileInfo] = []

  private let subsystem: Logger.Subsystem
  private var log: Logger.Subsystem { subsystem }

  init(player: PlayerCore, ticket: Int) {
    self.player = player
    self.ticket = ticket
    subsystem = Logger.makeSubsystem("fmatcher\(player.label)")
  }

  /// checkTicket
  private func checkTicket() throws {
    if player.backgroundQueueTicket != ticket {
      throw TicketExpiredError.ticketExpired
    }
  }

  private func getAllMediaFiles() throws {
    // get all files in current directory
    guard let urls = try? fm.contentsOfDirectory(at: currentFolder, includingPropertiesForKeys: nil, options: searchOptions) else { return }

    log.debug("Getting all media files...")
    // group by extension
    for url in urls {
      try checkTicket()
      let fileInfo = FileInfo(url)
      if let mediaType = Utility.mediaType(forExtension: fileInfo.ext) {
        switch mediaType {
        case .video:
          videoFiles.append(fileInfo)
        case .audio:
          audioFiles.append(fileInfo)
        case .sub, .secondSub:
          subFiles.append(fileInfo)
        }
      }
    }

    log.debug("Got all media files, video=\(videoFiles.count), audio=\(audioFiles.count)")

    // natural sort
    videoFiles.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    audioFiles.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
  }

  private func getAllPossibleSubs() throws -> [FileInfo] {
    try checkTicket()
    log.debug("Getting all sub files...")

    // search subs
    let subExts = Utility.supportedFileExt[.sub]!
    var subDirs: [URL] = []

    // search subs in other directories
    let rawUserDefinedSearchPaths = Preference.string(for: .subAutoLoadSearchPath) ?? "./*"
    let userDefinedSearchPaths = rawUserDefinedSearchPaths.components(separatedBy: ":").filter { !$0.isEmpty }
    for path in userDefinedSearchPaths {
      var p = path
      // handle `~`
      if path.hasPrefix("~") {
        p = NSString(string: path).expandingTildeInPath
      }
      if path.hasSuffix("/") { p.deleteLast(1) }
      // only check wildcard at the end
      let hasWildcard = path.hasSuffix("/*")
      if hasWildcard { p.deleteLast(2) }
      // handle absolute paths
      let pathURL = path.hasPrefix("/") || path.hasPrefix("~") ? URL(fileURLWithPath: p, isDirectory: true) : currentFolder.appendingPathComponent(p, isDirectory: true)
      // handle wildcards
      if hasWildcard {
        // append all sub dirs
        if let contents = try? fm.contentsOfDirectory(at: pathURL, includingPropertiesForKeys: [.isDirectoryKey], options: searchOptions) {
          subDirs.append(contentsOf: contents.filter { url in
            // Filter out bundles (here called "file packages") from the results.
            // They can otherwise look like directories, but some like iMovie libraries will cause a permission prompt
            // to be shown to the user when trying to access them.
            return url.isExistingDirectory && !NSWorkspace.shared.isFilePackage(atPath: url.path) && !isRestrictedByTCC(url.path)
          })
        }
      } else {
        subDirs.append(pathURL)
      }
    }

    log.debug("Searching subtitles from \(subDirs.count) directories...")
    log.verbose("\(subDirs)")
    // get all possible sub files
    var subtitles = subFiles

    for subDir in subDirs {
      try checkTicket()
      if let contents = try? fm.contentsOfDirectory(at: subDir, includingPropertiesForKeys: nil, options: searchOptions) {
        subtitles.append(contentsOf: contents.compactMap { subExts.contains($0.pathExtension.lowercased()) ? FileInfo($0) : nil })
      }
    }

    log.debug("Got \(subtitles.count) subtitles")
    return subtitles
  }

  /// Will the given file path possibly trigger Apple's TCC to prompt the user for permissions to access it?
  ///
  /// We have to guess in some cases.
  /// Currently only checks whether the given filePath is in the Movies folder's subtree.
  private func isRestrictedByTCC(_ filePath: String) -> Bool {
    let moviesDirPaths = FileManager.default.urls(for: .moviesDirectory, in: .allDomainsMask).compactMap{$0.path}
    for moviesDirPath in moviesDirPaths {
      if filePath.hasPrefix(moviesDirPath) {
        log.verbose{"Skipping \(filePath.pii.quoted) because it is inside \(moviesDirPath.pii.quoted)"}
        return true
      }
    }
    return false
  }

  private func addFilesToPlaylist() throws {
    let pathList = (videoFiles + audioFiles).compactMap{$0.path}
    try checkTicket()
    
    player.mpv.queue.async { [self] in
      log.debug("Adding \(videoFiles.count) video files & \(audioFiles.count) audio files to playlist")
      player._addToPlaylist(pathListIncludingCurrent: pathList)
    }
  }

  private func matchVideoAndSubSeries() throws -> [String: String] {
    var prefixDistance: [String: [String: UInt]] = [:]
    var closestVideoForSub: [String: String] = [:]

    log.debug("Matching video and sub series...")
    // calculate edit distance between each v/s prefix
    for (sp, _) in subsGroupedBySeries {
      try checkTicket()
      prefixDistance[sp] = [:]
      var minDist = UInt.max
      var minVideo = ""
      for (vp, vl) in videosGroupedBySeries {
        guard vl.count > 2 else { continue }
        let dist = ObjcUtils.levDistance(vp, and: sp)
        prefixDistance[sp]![vp] = dist
        if dist < minDist {
          minDist = dist
          minVideo = vp
        }
      }
      closestVideoForSub[sp] = minVideo
    }
    log.debug("Calculated editing distance")

    var matchedPrefixes: [String: String] = [:]  // video: sub
    for (vp, vl) in videosGroupedBySeries {
      try checkTicket()
      guard vl.count > 2 else { continue }
      var minDist = UInt.max
      var minSub = ""
      for (sp, _) in subsGroupedBySeries {
        let dist = prefixDistance[sp]![vp]!
        if dist < minDist {
          minDist = dist
          minSub = sp
        }
      }
      let threshold = UInt(Double(vp.count + minSub.count) * 0.6)
      if closestVideoForSub[minSub] == vp && minDist < threshold {
        matchedPrefixes[vp] = minSub
        log.debug("Matched \(vp) with \(minSub)")
      }
    }

    log.debug("Done matching")
    return matchedPrefixes
  }

  private func matchSubs(withMatchedSeries matchedPrefixes: [String: String]) throws {
    log.debug("Matching subs with matched series, prefixes=\(matchedPrefixes.count)...")

    // get auto load option
    let subAutoLoadOption: Preference.IINAAutoLoadAction = Preference.enum(for: .subAutoLoadIINA)
    guard subAutoLoadOption != .disabled else { return }

    for video in videoFiles {
      var matchedSubs = Set<FileInfo>()
      log.trace{"Matching for \(video.filename.pii.quoted)"}

      // match video and sub if both are the closest one to each other
      if subAutoLoadOption.shouldLoadSubsMatchedByIINA() {
        log.trace("Matching by IINA...")
        // is in series
        if !video.prefix.isEmpty, let matchedSubPrefix = matchedPrefixes[video.prefix] {
          // find sub with same name
          for sub in subtitles {
            guard let vn = video.nameInSeries, let sn = sub.nameInSeries else { continue }
            var nameMatched: Bool
            if let vnInt = Int(vn), let snInt = Int(sn) {
              nameMatched = vnInt == snInt
            } else {
              nameMatched = vn == sn
            }
            if nameMatched {
              log.verbose{"Matched by IINA: \(video.filename.pii.quoted) (\(vn)) & \(sub.filename.pii.quoted) (\(sn)) ..."}
              video.relatedSubs.append(sub)
              if sub.prefix == matchedSubPrefix {
                try checkTicket()
                player.info.$matchedSubs.withLock { $0[video.path, default: []].append(sub.url) }
                sub.isMatched = true
                matchedSubs.insert(sub)
              }
            }
          }
        }
        log.trace("Matching by IINA: done")
      }

      // add subs that contains video name
      if subAutoLoadOption.shouldLoadSubsContainingVideoName() {
        log.trace("Matching subtitles containing video name...")
        try subtitles.filter {
          $0.filename.contains(video.filename) && !$0.isMatched
        }.forEach { sub in
          try checkTicket()
          log.verbose{"Matched by name: \(sub.filename.pii.quoted) & \(video.filename.pii.quoted)"}
          player.info.$matchedSubs.withLock { $0[video.path, default: []].append(sub.url) }
          sub.isMatched = true
          matchedSubs.insert(sub)
        }
        log.trace("Matching subtitles containing video name: done")
      }

      // if no match
      if matchedSubs.isEmpty {
        log.trace{"No matched subs for \(video.filename.pii.quoted)"}
        unmatchedVideos.append(video)
      } else {
        log.debug{"Matched \(matchedSubs.count) subtitles for \(video.filename.pii.quoted)"}
      }

      // move the sub to front if it contains priority strings
      if let priorString = Preference.string(for: .subAutoLoadPriorityString), !matchedSubs.isEmpty {
        log.verbose("Moving sub containing priority strings...")
        let stringList = priorString
          .components(separatedBy: ",")
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
        // find the min occurrence count first
        var minOccurrences = Int.max
        matchedSubs.forEach { sub in
          sub.priorityStringOccurrences = stringList.reduce(0, { $0 + sub.filename.countOccurrences(of: $1, in: nil) })
          if sub.priorityStringOccurrences < minOccurrences {
            minOccurrences = sub.priorityStringOccurrences
          }
        }
        try player.info.$matchedSubs.withLock { subs in
          let urls = subs[video.path]!
          try matchedSubs
            .filter { $0.priorityStringOccurrences > minOccurrences }  // eliminate false positives in filenames
            .compactMap { urls.firstIndex(of: $0.url) }   // get index
            .forEach { // move the sub with index to first
              try checkTicket()
              log.verbose("Move \(urls[$0].absoluteString.pii.quoted) to front")
              if let s = subs[video.path]?.remove(at: $0) {
                subs[video.path]!.insert(s, at: 0)
              }
            }
        }
        log.trace("Moving sub: done")
      }
    }

    try checkTicket()
    player.info.currentVideosInfo = videoFiles
  }

  private func forceMatchUnmatchedVideos() throws {
    let unmatchedSubs = subtitles.filter { !$0.isMatched }
    guard unmatchedVideos.count * unmatchedSubs.count < 100 * 100 else {
      log.warn("Stopped force matching subs - too many files")
      return
    }

    log.verbose{"Force matching unmatched videos, video=\(unmatchedVideos.count), sub=\(unmatchedSubs.count)..."}
    if unmatchedSubs.count > 0 && unmatchedVideos.count > 0 {
      // calculate edit distance
      log.debug("Calculating edit distance...")
      for sub in unmatchedSubs {
        log.verbose("Calculating edit distance for \(sub.filename.pii)")
        var minDistToVideo: UInt = .max
        for video in unmatchedVideos {
          try checkTicket()
          let threshold = UInt(Double(video.filename.count + sub.filename.count) * 0.6)
          let rawDist = ObjcUtils.levDistance(video.prefix, and: sub.prefix) + ObjcUtils.levDistance(video.suffix, and: sub.suffix)
          let dist: UInt = rawDist < threshold ? rawDist : UInt.max
          sub.dist[video] = dist
          video.dist[sub] = dist
          if dist < minDistToVideo { minDistToVideo = dist }
        }
        guard minDistToVideo != .max else { continue }
        sub.minDist = videoFiles.filter { sub.dist[$0] == minDistToVideo }
      }

      // match them
      log.debug("Force matching...")
      for video in unmatchedVideos {
        let minDistToSub = video.dist.reduce(UInt.max, { min($0, $1.value) })
        guard minDistToSub != .max else { continue }
        try checkTicket()
        unmatchedSubs
          .filter { video.dist[$0]! == minDistToSub && $0.minDist.contains(video) }
          .forEach { sub in
            player.info.$matchedSubs.withLock { $0[video.path, default: []].append(sub.url) }
          }
      }
    }
  }

  func startMatching() {
    log.debug("**Start matching")
    let shouldAutoLoad = Preference.bool(for: .playlistAutoAdd)

    do {
      guard let folder = player.info.currentURL?.deletingLastPathComponent(), folder.isFileURL else { return }
      currentFolder = folder

      player.info.isMatchingSubtitles = true
      try getAllMediaFiles()

      // get all possible subtitles
      subtitles = try getAllPossibleSubs()
      player.info.currentSubsInfo = subtitles

      // add files to playlist
      if shouldAutoLoad {
        try addFilesToPlaylist()
      }

      // group video and sub files
      log.debug("Grouping video files...")
      videosGroupedBySeries = FileGroup.group(files: videoFiles).flatten()
      log.debug("Finished with \(videosGroupedBySeries.count) groups")

      log.debug("Grouping sub files...")
      subsGroupedBySeries = FileGroup.group(files: subtitles).flatten()
      log.debug("Finished with \(subsGroupedBySeries.count) groups")

      // match video and sub series
      let matchedPrefixes = try matchVideoAndSubSeries()

      // match sub stage 1
      try matchSubs(withMatchedSeries: matchedPrefixes)
      // match sub stage 2
      if shouldAutoLoad {
        try forceMatchUnmatchedVideos()
      }
      player.info.isMatchingSubtitles = false

      // Fill in file sizes after everything else is finished
      MediaMetaCache.shared.fillInVideoSizes(videoFiles, onBehalfOf: player)

      player.postNotification(.iinaPlaylistChanged)
      log.debug("**Finished matching")
    } catch let err as TicketExpiredError {
      player.info.isMatchingSubtitles = false
      guard case .ticketExpired = err else {
        log.error(err.localizedDescription)
        return
      }
      log.debug("Automatching cancelled: ticket expired")
      return
    } catch let err {
      player.info.isMatchingSubtitles = false
      log.error(err.localizedDescription)
      return
    }
  }
}
