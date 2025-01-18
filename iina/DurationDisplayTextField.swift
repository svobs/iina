//
//  DurationDisplayView.swift
//  iina
//
//  Created by Christophe Laprun on 26/01/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate let monoSystemFontSmall = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)

class DurationDisplayTextField: ClickThroughTextField {
  enum DisplayMode {
    case current
    case duration // displays the duration of the movie
    case remaining // displays the remaining time in the movie
  }

  static var precision : UInt = UInt(Preference.integer(for: .timeDisplayPrecision))
  var mode: DisplayMode = .duration { didSet { updateText() } }
  var duration: Double = 0
  var current: Double = 0

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    font = monoSystemFontSmall
  }
  
  @MainActor required init?(coder: NSCoder) {
    super.init(coder: coder)
    font = monoSystemFontSmall
  }

  /** Switches the display mode between duration and remaining time */
  private func switchMode() {
    switch mode {
    case .duration:
      mode = .remaining
    default:
      mode = .duration
    }
  }

  func updateText(with duration: Double, given current: Double) {
    self.duration = duration
    self.current = current
    updateText()
  }
  
  private func updateText() {
    let precision = DurationDisplayTextField.precision
    let stringValue: String
    switch mode {
    case .current:
      stringValue = VideoTime.string(from: current, precision: precision)
    case .duration:
      stringValue = VideoTime.string(from: duration, precision: precision)
    case .remaining:
      var remaining = (duration - current)
      if remaining < 0 {
        remaining = 0
      }
      stringValue = "-\(VideoTime.string(from: remaining, precision: precision))"
    }
    baseWritingDirection = .leftToRight
    self.stringValue = stringValue
  }

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)

    guard mode != .current else { return }
    self.switchMode()
    Preference.set(mode == .remaining, for: .showRemainingTime)
  }

  override func scrollWheel(with event: NSEvent) {
    return
  }

  override func rightMouseDown(with event: NSEvent) {
    let precision = DurationDisplayTextField.precision
    let menu = NSMenu(title: "Time label settings")
    menu.addItem(withTitle: NSLocalizedString("osc.precision", comment: "Precision"))
    ["1s", "100ms", "10ms", "1ms"].enumerated().forEach { (index, key) in
      menu.addItem(withTitle: NSLocalizedString("osc.\(key)", comment: ""),
                   action: #selector(self.setPrecision(_:)),
                   target: self, tag: index,
                   stateOn: precision == index)
    }
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }

  override func touchesBegan(with event: NSEvent) {
    // handles the remaining time text field in the touch bar
    super.touchesBegan(with: event)

    guard mode != .current else { return }
    self.switchMode()
    Preference.set(mode == .remaining, for: .touchbarShowRemainingTime)
  }

  @objc func setPrecision(_ sender: NSMenuItem) {
    let precision = UInt(sender.tag)
    DurationDisplayTextField.precision = precision
    Preference.set(Int(precision), for: .timeDisplayPrecision)
    PlayerManager.shared.playerCores.forEach { core in
      core.refreshSyncUITimer()
    }
  }
}
