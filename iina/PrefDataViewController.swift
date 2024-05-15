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
    return [pastLaunchesView, historyView, watchLaterView]
  }

  @IBOutlet var pastLaunchesView: NSView!
  @IBOutlet var historyView: NSView!
  @IBOutlet var watchLaterView: NSView!

  @IBOutlet var historyCountView: NSTextField!

  @IBOutlet var watchLaterCountView: NSTextField!
  @IBOutlet var watchLaterOptionsView: NSTextField!

  override func viewDidLoad() {
    super.viewDidLoad()

    NotificationCenter.default.addObserver(self, selector: #selector(self.reloadWatchLaterViews(_:)),
                                           name: .watchLaterOptionsDidChange, object: nil)

    NotificationCenter.default.addObserver(self, selector: #selector(self.reloadHistoryCount(_:)),
                                           name: .iinaHistoryUpdated, object: nil)

  }

  override func viewWillAppear() {
    super.viewWillAppear()

    reloadWatchLaterViews(nil)
    reloadHistoryCount(nil)
  }

  // MARK: - IBActions

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
    Logger.log("Found Watch Later data for \(watchLaterCount) media files", level: .verbose)
    watchLaterCountView.stringValue = "Found Watch Later data for \(watchLaterCount) media files."
  }

  @IBAction func showWatchLaterDirAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(Utility.watchLaterURL)
  }

  @IBAction func rememberRecentChanged(_ sender: NSButton) {
    if sender.state == .off {
      AppDelegate.shared.clearRecentDocuments(self)
    }
  }
}
