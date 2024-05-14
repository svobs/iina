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

  @IBOutlet var watchLaterCountView: NSTextField!
  @IBOutlet var watchLaterOptionsView: NSTextField!

  override func viewWillAppear() {
    super.viewWillAppear()
    watchLaterOptionsView.stringValue = MPVController.watchLaterOptions.replacingOccurrences(of: ",", with: ", ")

    let searchOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]

    var watchLaterCount = 0
    if let files = try? FileManager.default.contentsOfDirectory(at: Utility.watchLaterURL, includingPropertiesForKeys: nil, options: searchOptions) {
      watchLaterCount = files.count
    }
    watchLaterCountView.stringValue = "Found Watch Later data for \(watchLaterCount) media files."
  }

  // MARK: - IBAction

  @IBAction func showWatchLaterDirAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(Utility.watchLaterURL)
  }

}
