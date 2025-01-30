//
//  TwoRowBarOSCView.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-30.
//  Copyright © 2025 lhc. All rights reserved.
//

class TwoRowBarOSCView: ClickThroughView {
  static let id = "OSC_2RowView"
  static let leadingMargin: CGFloat = 4
  static let trailingMargin: CGFloat = 4
  let hStackView = ClickThroughStackView()
  let centralSpacerView = SpacerView.buildNew(id: "\(TwoRowBarOSCView.id)-CentralSpacer")

  init() {
    super.init(frame: .zero)
    identifier = .init(TwoRowBarOSCView.id)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.backgroundColor = .clear

    hStackView.idString = "\(TwoRowBarOSCView.id)-HStackView"
    hStackView.orientation = .horizontal
    hStackView.alignment = .centerY
    hStackView.translatesAutoresizingMaskIntoConstraints = false
    hStackView.detachesHiddenViews = true
    hStackView.setClippingResistancePriority(.defaultLow, for: .horizontal)
    hStackView.spacing = Constants.Distance.oscSectionHSpacing_MultiLine

    addSubview(hStackView)
    hStackView.addConstraintsToFillSuperview(bottom: 0,
                                             leading: TwoRowBarOSCView.leadingMargin,
                                             trailing: TwoRowBarOSCView.trailingMargin)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateControls(from pwc: PlayerWindowController) {
    let playSliderAndTimeLabelsView = pwc.playSliderAndTimeLabelsView
    if !subviews.contains(playSliderAndTimeLabelsView) {
      let verticalOffsetBetweenLines: CGFloat = Constants.Distance.multiLineOSC_SpaceBetweenLines
      addSubview(playSliderAndTimeLabelsView)

      playSliderAndTimeLabelsView.addConstraintsToFillSuperview(top: 0, leading: TwoRowBarOSCView.leadingMargin,
                                                                trailing: TwoRowBarOSCView.trailingMargin)
      hStackView.topAnchor.constraint(equalTo: playSliderAndTimeLabelsView.bottomAnchor, constant: verticalOffsetBetweenLines).isActive = true
    }

    var views: [NSView] = [pwc.fragPlaybackBtnsView, centralSpacerView, pwc.fragVolumeView]

    if let toolbarView = pwc.fragToolbarView {
      views.append(toolbarView)
    }

    hStackView.setViews(views, in: .leading)

    hStackView.setVisibilityPriority(.detachEarly, for: pwc.fragVolumeView)
    if let toolbarView = pwc.fragToolbarView {
      hStackView.setVisibilityPriority(.detachEarlier, for: toolbarView)
    }
  }
}
