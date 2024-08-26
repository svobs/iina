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

  private var observers: [NSObjectProtocol] = []

  override func viewDidLoad() {
    super.viewDidLoad()

    setTextColorToRed(clearSavedWindowDataBtn)
    setTextColorToRed(clearWatchLaterBtn)
    setTextColorToRed(clearHistoryBtn)
  }

  override func viewWillAppear() {
    Logger.log("Saved Data pref pane will appear", level: .verbose)
    super.viewWillAppear()

    observers.append(NotificationCenter.default.addObserver(forName: .savedWindowStateDidChange, object: nil,
                                                            queue: .main, using: self.refreshSavedLaunchSummary(_:)))

    observers.append(NotificationCenter.default.addObserver(forName: .iinaHistoryUpdated, object: nil,
                                                            queue: .main, using: self.reloadHistoryCount(_:)))

    observers.append(NotificationCenter.default.addObserver(forName: .watchLaterOptionsDidChange, object: nil,
                                                            queue: .main, using: self.reloadWatchLaterOptions(_:)))

    observers.append(NotificationCenter.default.addObserver(forName: .watchLaterDirDidChange, object: nil,
                                                            queue: .main, using: self.reloadWatchLaterCount(_:)))

    observers.append(NotificationCenter.default.addObserver(forName: .recentDocumentsDidChange, object: nil,
                                                            queue: .main, using: self.refreshRecentDocumentsCount(_:)))

    observers.append(NotificationCenter.default.addObserver(forName: .iinaThumbnailCacheDidUpdate, object: nil,
                                                            queue: .main, using: self.reloadThumbnailCacheStat(_:)))

    let dummy = Notification(name: .recentDocumentsDidChange)
    refreshSavedLaunchSummary(dummy)
    reloadHistoryCount(dummy)
    reloadWatchLaterOptions(dummy)
    reloadWatchLaterCount(dummy)
    refreshRecentDocumentsCount(dummy)
    reloadThumbnailCacheStat(dummy)
  }

  override func viewWillDisappear() {
    Logger.log("Saved Data pref pane will disappear", level: .verbose)
    super.viewWillDisappear()
    // Disable observers when not in use to save CPU
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  // TODO: this can get called often. Add throttling
  private func refreshSavedLaunchSummary(_ notification: Notification) {
    let (hasData, launchDataSummary) = buildSavedLaunchSummary()
    Logger.log(launchDataSummary)
    savedLaunchSummaryView.stringValue = launchDataSummary

    clearSavedWindowDataBtn.isEnabled = hasData
  }

  private func buildSavedLaunchSummary() -> (Bool, String) {
    let launches = Preference.UIState.collectLaunchState()
    if !launches.isEmpty {

      // Aggregate all windows into set of unique windows
      let allSavedWindows = launches.reduce(Set<SavedWindow>(), {windowSet, launch in windowSet.union(launch.savedWindows ?? [])})
      let playerWindowCount = allSavedWindows.reduce(0, {count, wind in count + (wind.isPlayerWindow ? 1 : 0)})
      let nonPlayerWindowCount = allSavedWindows.count - playerWindowCount
      let hasData = playerWindowCount > 0 || nonPlayerWindowCount > 0
      if hasData {
        let launchesString = launches.count > 1 ? " across \(launches.count) launches" : ""
        return (true, "Saved state exists for \(playerWindowCount) player windows & \(nonPlayerWindowCount) other windows\(launchesString).")
      }
    }
    return (false, "No saved window state found.")
  }

  private func setTextColorToRed(_ button: NSButton) {
    if let mutableAttributedTitle = button.attributedTitle.mutableCopy() as? NSMutableAttributedString {
      mutableAttributedTitle.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: mutableAttributedTitle.length))
      button.attributedTitle = mutableAttributedTitle
    }
  }

  private func reloadHistoryCount(_ notification: Notification) {
    let historyCount = HistoryController.shared.history.count
    let infoMsg = historyCount == 0 ? "No history data exists." : "History exists for \(historyCount) media."
    Logger.log("Updating msg for PrefData tab: \(infoMsg.quoted)", level: .verbose)
    historyCountView.stringValue = infoMsg
    clearHistoryBtn.isEnabled = historyCount > 0
  }

  private func reloadWatchLaterOptions(_ notification: Notification) {
    Logger.log("Refreshing Watch Later options", level: .verbose)
    watchLaterOptionsView.stringValue = MPVController.watchLaterOptions.replacingOccurrences(of: ",", with: ", ")
  }

  // TODO: this is expensive. Add throttling
  private func reloadWatchLaterCount(_ notification: Notification) {
    HistoryController.shared.queue.async {
      var watchLaterCount = 0
      let searchOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
      if let files = try? FileManager.default.contentsOfDirectory(at: Utility.watchLaterURL, includingPropertiesForKeys: nil, options: searchOptions) {
        watchLaterCount = files.count
      }
      DispatchQueue.main.async { [self] in
        let infoMsg = watchLaterCount == 0 ? "No Watch Later data found." : "Watch Later data exists for \(watchLaterCount) media files."
        watchLaterCountView.stringValue = infoMsg
        Logger.log("Refreshed Watch Later count: \(infoMsg)", level: .verbose)
        clearWatchLaterBtn.isEnabled = watchLaterCount > 0
      }
    }
  }

  private func refreshRecentDocumentsCount(_ notification: Notification) {
    let recentDocCount = NSDocumentController.shared.recentDocumentURLs.count
    recentDocumentsCountView.stringValue = "Current number of recent items: \(recentDocCount)"
  }

  // TODO: this is expensive. Add throttling
  private func reloadThumbnailCacheStat(_ notification: Notification) {
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
    guard !Preference.UIState.isSaveEnabled else {
      Utility.showAlert("clear_saved_windows_while_enabled", sheetWindow: view.window)
      return
    }

    Utility.quickAskPanel("clear_saved_windows", sheetWindow: view.window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      guard !Preference.UIState.isSaveEnabled else {
        Logger.log("User chose to clear all saved window data, but save is still enabled!", level: .error)
        return
      }
      Logger.log("User chose to clear all saved window data")
      Preference.UIState.clearAllSavedLaunches(force: true)
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
      reloadThumbnailCacheStat(Notification(name: .iinaThumbnailCacheDidUpdate))
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
