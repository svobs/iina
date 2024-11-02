//
//  PrefControlViewController.swift
//  iina
//
//  Created by lhc on 20/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefControlViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefControlViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.control", comment: "Control")
  }

  var preferenceTabImage: NSImage {
    return makeSymbol("computermouse", fallbackImage: "pref_control")
  }

  override var sectionViews: [NSView] {
    return [sectionTrackpadView, sectionMouseView]
  }

  @IBOutlet var sectionTrackpadView: NSView!
  @IBOutlet var sectionMouseView: NSView!

  @IBOutlet weak var forceTouchLabel: NSTextField!
  @IBOutlet weak var scrollVerticallyLabel: NSTextField!

  @IBOutlet weak var seekScrollSensitivityLabel: NSTextField!
  @IBOutlet weak var volumeScrollSensitivityLabel: NSTextField!

  var co: CocoaObserver! = nil

  override func viewDidLoad() {
    super.viewDidLoad()
    configureObservers()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    co.addAllObservers()
    updateLabels()
  }

  override func viewWillDisappear() {
    co.removeAllObservers()
  }

  // MARK: Observers

  private func configureObservers() {
    co = CocoaObserver(Logger.log, prefDidChange: prefDidChange, [
      .relativeSeekAmount,
      .volumeScrollAmount,
    ])
  }

  /// Called each time a pref `key`'s value is set
  func prefDidChange(_ key: Preference.Key, _ newValue: Any?) {
    switch key {
    case PK.relativeSeekAmount, PK.volumeScrollAmount:
      updateLabels()
    default:
      break
    }
  }

  private func updateLabels() {
    seekScrollSensitivityLabel.stringValue = Preference.seekScrollSensitivity().stringMaxFrac2 + "x"
    volumeScrollSensitivityLabel.stringValue = Preference.volumeScrollSensitivity().stringMaxFrac2 + "x"
  }
}
