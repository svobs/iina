//
//  SingleRowBarOSCView.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-30.
//  Copyright © 2025 lhc. All rights reserved.
//

/// For "bar"-type OSCs: `bottom` and `top` only - not `floating` or music mode.
class SingleRowBarOSCView: ClickThroughStackView {
  static let id = "OSC_1RowView"
  let hStackView = ClickThroughStackView()

  init() {
    super.init(frame: .zero)
    identifier = .init(SingleRowBarOSCView.id)

    /// `oscOneRowView`
    idString = SingleRowBarOSCView.id
    spacing = Constants.Distance.oscSectionHSpacing_SingleLine
    orientation = .horizontal
    alignment = .centerY
    distribution = .gravityAreas
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.backgroundColor = .clear
    setClippingResistancePriority(.defaultLow, for: .horizontal)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func dispose() {
    // Not much to do here presently
    removeAllSubviews()
    removeFromSuperview()
  }

  func updateSubviews(from pwc: PlayerWindowController) {
    var views: [NSView] = [pwc.fragPlaybackBtnsView, pwc.playSliderAndTimeLabelsView, pwc.fragVolumeView]

    if let fragToolbarView = pwc.fragToolbarView {
      views.append(fragToolbarView)
    }

    setViews(views, in: .leading)

    setVisibilityPriority(.mustHold, for: pwc.fragPlaybackBtnsView)
    setVisibilityPriority(.detachLessEarly, for: pwc.playSliderAndTimeLabelsView)
    setVisibilityPriority(.detachEarly, for: pwc.fragVolumeView)
    if let fragToolbarView = pwc.fragToolbarView {
      setVisibilityPriority(.detachEarlier, for: fragToolbarView)
    }
  }

}
