//
//  PrefGeneralViewController.swift
//  iina
//
//  Created by lhc on 27/10/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import Sparkle

@objcMembers
class PrefGeneralViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefGeneralViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.general", comment: "General")
  }

  var preferenceTabImage: NSImage {
    return makeSymbol("gear", fallbackName: "pref_general")
  }

  override var sectionViews: [NSView] {
    return [behaviorView, playlistView, screenshotsView]
  }

  @IBOutlet var behaviorView: NSView!
  @IBOutlet var playlistView: NSView!
  @IBOutlet var screenshotsView: NSView!
  @IBOutlet var updatesView: NSView!

  @IBOutlet weak var afterOpenActionBox: NSBox!
  @IBOutlet weak var pauseActionBox: NSBox!
  
  // MARK: - IBAction

  @IBAction func chooseScreenshotPathAction(_ sender: AnyObject) {
    Utility.quickOpenPanel(title: "Choose screenshot save path", chooseDir: true, sheetWindow: view.window) { url in
      Preference.set(url.path, for: .screenshotFolder)
      UserDefaults.standard.synchronize()
    }
  }

  @IBAction func rememberRecentChanged(_ sender: NSButton) {
    if sender.state == .off {
      AppDelegate.shared.clearRecentDocuments(self)
    }
  }
}

