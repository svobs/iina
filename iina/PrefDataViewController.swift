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

  @IBOutlet weak var savedLaunchSummaryView: NSTextField!
  @IBOutlet weak var recentDocumentsCountView: NSTextField!
  @IBOutlet weak var historyCountView: NSTextField!
  @IBOutlet weak var watchLaterCountView: NSTextField!
  @IBOutlet weak var watchLaterOptionsView: NSTextField!
  @IBOutlet weak var thumbCacheSizeLabel: NSTextField!

  @IBOutlet weak var clearSavedWindowDataBtn: NSButton!
  @IBOutlet weak var clearWatchLaterBtn: NSButton!
  @IBOutlet weak var clearHistoryBtn: NSButton!
  @IBOutlet weak var clearThumbnailCacheBtn: NSButton!

  var isWindowVisible: Bool {
    return view.window?.isVisible ?? false
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // TODO: add and remove listeners for viewWillDisappear and appear
    NotificationCenter.default.addObserver(self, selector: #selector(self.refreshSavedLaunchSummary(_:)),
                                           name: .savedWindowStateDidChange, object: nil)

    NotificationCenter.default.addObserver(self, selector: #selector(self.reloadHistoryCount(_:)),
                                           name: .iinaHistoryUpdated, object: nil)

    NotificationCenter.default.addObserver(self, selector: #selector(self.reloadWatchLaterOptions(_:)),
                                           name: .watchLaterOptionsDidChange, object: nil)

    NotificationCenter.default.addObserver(self, selector: #selector(self.reloadWatchLaterCount(_:)),
                                           name: .watchLaterDirDidChange, object: nil)

    NotificationCenter.default.addObserver(self, selector: #selector(self.refreshRecentDocumentsCount(_:)),
                                           name: .recentDocumentsDidChange, object: nil)

    setTextColorToRed(clearSavedWindowDataBtn)
    setTextColorToRed(clearWatchLaterBtn)
    setTextColorToRed(clearHistoryBtn)
  }

  override func viewWillAppear() {
    super.viewWillAppear()

    refreshSavedLaunchSummary(self)
    reloadHistoryCount(self)
    reloadWatchLaterOptions(self)
    reloadWatchLaterCount(self)
    refreshRecentDocumentsCount(self)
    reloadThumbnailCacheStat()
  }

  // TODO: this can get called often. Add throttling
  @objc func refreshSavedLaunchSummary(_ sender: AnyObject?) {
    let (hasData, launchDataSummary) = buildSavedLaunchSummary()
    Logger.log(launchDataSummary)
    savedLaunchSummaryView.stringValue = launchDataSummary

    clearSavedWindowDataBtn.isEnabled = hasData
  }

  func buildSavedLaunchSummary() -> (Bool, String) {
    let launches = Preference.UIState.collectLaunchState()
    if launches.isEmpty {
      return (false, "No saved window data found.")
    }

    let playerWindowCount = launches.reduce(0, {count, launch in count + launch.playerWindowCount})
    let nonPlayerWindowCount = launches.reduce(0, {count, launch in count + launch.nonPlayerWindowCount})
    let hasData = playerWindowCount > 0 || nonPlayerWindowCount > 0
    return (hasData, "\(playerWindowCount) player windows & \(nonPlayerWindowCount) other windows are currently saved.")
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
      guard isWindowVisible else { return }
      let infoMsg = "History exists for \(historyCount) media."
      Logger.log("Updating msg for PrefData tab: \(infoMsg.quoted)", level: .verbose)
      historyCountView.stringValue = infoMsg
      clearHistoryBtn.isEnabled = historyCount > 0
    }
  }

  @objc func reloadWatchLaterOptions(_ sender: AnyObject?) {
    DispatchQueue.main.async { [self] in
      guard isWindowVisible else { return }
      Logger.log("Refreshing Watch Later options", level: .verbose)
      watchLaterOptionsView.stringValue = MPVController.watchLaterOptions.replacingOccurrences(of: ",", with: ", ")
    }
  }

  // TODO: this is expensive. Add throttling
  @objc func reloadWatchLaterCount(_ sender: AnyObject?) {
    DispatchQueue.main.async { [self] in
      guard isWindowVisible else { return }
      HistoryController.shared.queue.async {
        var watchLaterCount = 0
        let searchOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        if let files = try? FileManager.default.contentsOfDirectory(at: Utility.watchLaterURL, includingPropertiesForKeys: nil, options: searchOptions) {
          watchLaterCount = files.count
        }
        DispatchQueue.main.async { [self] in
          let infoMsg = "Watch Later data exists for \(watchLaterCount) media files."
          watchLaterCountView.stringValue = infoMsg
          Logger.log("Refreshed Watch Later count: \(infoMsg)", level: .verbose)
          clearWatchLaterBtn.isEnabled = watchLaterCount > 0
        }
      }
    }
  }

  @objc func refreshRecentDocumentsCount(_ sender: AnyObject?) {
    DispatchQueue.main.async { [self] in
      guard isWindowVisible else { return }
      let recentDocCount = NSDocumentController.shared.recentDocumentURLs.count
      recentDocumentsCountView.stringValue = "Current number of recent items: \(recentDocCount)"
    }
  }

  // TODO: this is expensive. Add throttling
  private func reloadThumbnailCacheStat() {
    AppDelegate.shared.preferenceWindowController.indexingQueue.async { [self] in
      let cacheSize = ThumbnailCacheManager.shared.getCacheSize()
      let newString = "\(FloatingPointByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .binary))B"
      DispatchQueue.main.async { [self] in
        thumbCacheSizeLabel.stringValue = newString
        clearThumbnailCacheBtn.isEnabled = cacheSize > 0
      }
    }
  }

  // MARK: - IBActions

  @IBAction func clearSavedWindowDataBtnAction(_ sender: Any) {
    Utility.quickAskPanel("clear_saved_windows", sheetWindow: view.window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      guard !Preference.UIState.isSaveEnabled else {
        Logger.log("User chose to clear all saved window data, but save is still enabled!", level: .error)
        return
      }
      Logger.log("User chose to clear all saved window data")
      Preference.UIState.clearAllSavedLaunchState(force: true)
    }
  }

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
      HistoryController.shared.removeAll()
    }
  }

  @IBAction func clearCacheBtnAction(_ sender: Any) {
    Utility.quickAskPanel("clear_cache", sheetWindow: view.window) { [self] respond in
      guard respond == .alertFirstButtonReturn else { return }
      try? FileManager.default.removeItem(atPath: Utility.thumbnailCacheURL.path)
      Utility.createDirIfNotExist(url: Utility.thumbnailCacheURL)
      reloadThumbnailCacheStat()
    }
  }

  @IBAction func showWatchLaterDirAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(Utility.watchLaterURL)
  }

  @IBAction func rememberRecentChanged(_ sender: NSButton) {
    if sender.state == .off {
      HistoryController.shared.clearRecentDocuments(self)
    }
  }

  @IBAction func showPlaybackHistoryAction(_ sender: AnyObject) {
    AppDelegate.shared.showHistoryWindow(sender)
  }

}
