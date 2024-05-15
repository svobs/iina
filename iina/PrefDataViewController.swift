//
//  PrefSavedStateViewController.swift
//  iina
//
//  Created by Matt Svoboda on 5/9/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

@objcMembers
class PrefDataViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefDataViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.data", comment: "Saved Data")
  }

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_data"))!
  }

  override var sectionViews: [NSView] {
    return [pastLaunchesView, historyView, watchLaterView, sectionClearCacheView]
  }

  @IBOutlet var pastLaunchesView: NSView!
  @IBOutlet var historyView: NSView!
  @IBOutlet var watchLaterView: NSView!
  @IBOutlet var sectionClearCacheView: NSView!

  @IBOutlet weak var historyCountView: NSTextField!

  @IBOutlet weak var watchLaterCountView: NSTextField!
  @IBOutlet weak var watchLaterOptionsView: NSTextField!

  @IBOutlet weak var thumbCacheSizeLabel: NSTextField!
  @IBOutlet weak var clearWatchLaterBtn: NSButton!
  @IBOutlet weak var clearHistoryBtn: NSButton!
  @IBOutlet weak var clearThumbnailCacheBtn: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()

    NotificationCenter.default.addObserver(self, selector: #selector(self.reloadWatchLaterViews(_:)),
                                           name: .watchLaterOptionsDidChange, object: nil)

    NotificationCenter.default.addObserver(self, selector: #selector(self.reloadHistoryCount(_:)),
                                           name: .iinaHistoryUpdated, object: nil)

    setTextColorToRed(clearWatchLaterBtn)
    setTextColorToRed(clearHistoryBtn)
  }

  override func viewWillAppear() {
    super.viewWillAppear()

    reloadWatchLaterViews(nil)
    reloadHistoryCount(nil)
    updateThumbnailCacheStat()
  }

  private func setTextColorToRed(_ button: NSButton) {
    if let mutableAttributedTitle = button.attributedTitle.mutableCopy() as? NSMutableAttributedString {
      mutableAttributedTitle.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: mutableAttributedTitle.length))
      button.attributedTitle = mutableAttributedTitle
    }
  }

  @objc func reloadHistoryCount(_ sender: AnyObject?) {
    let historyCount = HistoryController.shared.history.count
    DispatchQueue.main.async { [self] in
      Logger.log("Refreshing History count: \(historyCount)", level: .verbose)
      historyCountView.stringValue = "Playback history exists for \(historyCount) media."
    }
  }

  @objc func reloadWatchLaterViews(_ sender: AnyObject?) {
    guard !view.isHidden else { return }
    Logger.log("Refreshing Watch Later views", level: .verbose)

    watchLaterOptionsView.stringValue = MPVController.watchLaterOptions.replacingOccurrences(of: ",", with: ", ")

    refreshWatchLaterCount()
  }

  private func refreshWatchLaterCount() {
    var watchLaterCount = 0
    let searchOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
    if let files = try? FileManager.default.contentsOfDirectory(at: Utility.watchLaterURL, includingPropertiesForKeys: nil, options: searchOptions) {
      watchLaterCount = files.count
    }
    Logger.log("Watch Later data exists for \(watchLaterCount) media files", level: .verbose)
    watchLaterCountView.stringValue = "Watch Later data exists for \(watchLaterCount) media files."
  }

  private func updateThumbnailCacheStat() {
    AppDelegate.shared.preferenceWindowController.indexingQueue.async { [self] in
      let newString = "\(FloatingPointByteCountFormatter.string(fromByteCount: ThumbnailCacheManager.shared.getCacheSize(), countStyle: .binary))B"
      DispatchQueue.main.async { [self] in
        thumbCacheSizeLabel.stringValue = newString
      }
    }
  }

  // MARK: - IBActions

  @IBAction func clearWatchLaterBtnAction(_ sender: Any) {
    Utility.quickAskPanel("clear_watch_later", sheetWindow: view.window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      try? FileManager.default.removeItem(atPath: Utility.watchLaterURL.path)
      Utility.createDirIfNotExist(url: Utility.watchLaterURL)
    }
  }

  @IBAction func clearHistoryBtnAction(_ sender: Any) {
    Utility.quickAskPanel("clear_history", sheetWindow: view.window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      try? FileManager.default.removeItem(atPath: Utility.playbackHistoryURL.path)
      AppDelegate.shared.clearRecentDocuments(self)
      Preference.set(nil, for: .iinaLastPlayedFilePath)
    }
  }

  @IBAction func clearCacheBtnAction(_ sender: Any) {
    Utility.quickAskPanel("clear_cache", sheetWindow: view.window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      try? FileManager.default.removeItem(atPath: Utility.thumbnailCacheURL.path)
      Utility.createDirIfNotExist(url: Utility.thumbnailCacheURL)
      self.updateThumbnailCacheStat()
    }
  }

  @IBAction func showWatchLaterDirAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(Utility.watchLaterURL)
  }

  @IBAction func rememberRecentChanged(_ sender: NSButton) {
    if sender.state == .off {
      AppDelegate.shared.clearRecentDocuments(self)
    }
  }

  @IBAction func showPlaybackHistoryAction(_ sender: AnyObject) {
    AppDelegate.shared.showHistoryWindow(sender)
  }

}
