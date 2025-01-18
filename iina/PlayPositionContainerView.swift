//
//  PlayTimeAndSlider.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-18.
//  Copyright © 2025 lhc. All rights reserved.
//

/// Container view for play slider (`PlaySlider`) & time indicator labels (`DurationDisplayTextField`).
class PlayPositionContainerView: ClickThroughView {
  let playSlider = PlaySlider()
  let leftTimeLabel = DurationDisplayTextField()
  let rightTimeLabel = DurationDisplayTextField()
  var playSliderHeightConstraint: NSLayoutConstraint?

  private var wc: PlayerWindowController? {
    return window?.windowController as? PlayerWindowController
  }

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    userInterfaceLayoutDirection = .leftToRight
    setContentHuggingPriority(.init(249), for: .horizontal)
    setContentCompressionResistancePriority(.init(249), for: .horizontal)

    widthAnchor.constraint(greaterThanOrEqualToConstant: 150.0).isActive = true

    addSubview(leftTimeLabel)
    addSubview(playSlider)
    addSubview(rightTimeLabel)

    leftTimeLabel.identifier = .init("PlayPosition-LeftTimeLabel")
    leftTimeLabel.alignment = .right
    leftTimeLabel.isBordered = false
    leftTimeLabel.drawsBackground = false
    leftTimeLabel.isEditable = false
    leftTimeLabel.refusesFirstResponder = true
    leftTimeLabel.translatesAutoresizingMaskIntoConstraints = false
    leftTimeLabel.setContentHuggingPriority(.init(501), for: .horizontal)
    leftTimeLabel.setContentCompressionResistancePriority(.init(501), for: .horizontal)
    leftTimeLabel.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true

    playSlider.minValue = 0
    playSlider.maxValue = 100
    playSlider.isContinuous = true
    playSlider.leadingAnchor.constraint(equalTo: leftTimeLabel.trailingAnchor, constant: 4).isActive = true
    playSlider.refusesFirstResponder = true
    playSliderHeightConstraint = playSlider.heightAnchor.constraint(equalToConstant: 20)
    playSlider.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    playSlider.centerYAnchor.constraint(equalTo: leftTimeLabel.centerYAnchor).isActive = true
    playSlider.centerYAnchor.constraint(equalTo: rightTimeLabel.centerYAnchor).isActive = true
    playSlider.translatesAutoresizingMaskIntoConstraints = false
    playSlider.setContentHuggingPriority(.init(249), for: .horizontal)
    playSlider.setContentCompressionResistancePriority(.init(249), for: .horizontal)

    rightTimeLabel.identifier = .init("PlayPosition-RightTimeLabel")
    rightTimeLabel.alignment = .left
    rightTimeLabel.isBordered = false
    rightTimeLabel.drawsBackground = false
    rightTimeLabel.isEditable = false
    rightTimeLabel.refusesFirstResponder = true
    rightTimeLabel.translatesAutoresizingMaskIntoConstraints = false
    rightTimeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    rightTimeLabel.setContentCompressionResistancePriority(.init(749), for: .horizontal)
    rightTimeLabel.leadingAnchor.constraint(equalTo: playSlider.trailingAnchor, constant: 4).isActive = true
    rightTimeLabel.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

}
