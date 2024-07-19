//
//  CustomTitleBarViewController.swift
//  iina
//
//  Created by Matt Svoboda on 10/16/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

fileprivate let iconSpacingH: CGFloat = 6  // matches spacing as of MacOS Sonoma (14.0)
// try to roughly match Apple's title bar text:
fileprivate let activeTitleTextOpacity: CGFloat = 0.85
fileprivate let inactiveTitleTextOpacity: CGFloat = 0.35
fileprivate let inactiveTitleControlOpacity: CGFloat = 0.50

/// For legacy windowed mode. Manual reconstruction of title bar is needed when not using `titled` window style.
class CustomTitleBarViewController: NSViewController {
  var windowController: PlayerWindowController!

  // Leading side
  var leadingTitleBarView: TitleBarButtonsContainerView!
  var trafficLightButtons: [NSButton]!
  var leadingSidebarToggleButton: NSButton!

  // Center
  var centerTitleBarView: NSStackView!
  var documentIconButton: NSButton!
  var titleText: NSTextView!
  var titleTextWidthConstraint: NSLayoutConstraint!

  // Trailing side
  var trailingTitleBarView: NSStackView!
  var trailingSidebarToggleButton: NSButton!
  var onTopButton: NSButton!

  /// Use `loadView` instead of `viewDidLoad` because controller is not using storyboard
  override func loadView() {
    view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false

    // - Leading views

    // Add fake traffic light buttons:
    let btnTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    trafficLightButtons = btnTypes.compactMap{ NSWindow.standardWindowButton($0, for: .titled) }

    leadingSidebarToggleButton = makeTitleBarButton(imgName: "sidebar.leading",
                                                    action: #selector(windowController.toggleLeadingSidebarVisibility(_:)))

    let leadingStackView = TitleBarButtonsContainerView(views: trafficLightButtons + [leadingSidebarToggleButton])
    leadingStackView.wantsLayer = true
    leadingStackView.layer?.backgroundColor = .clear
    leadingStackView.orientation = .horizontal
    leadingStackView.distribution = .fill
    leadingStackView.detachesHiddenViews = true
    leadingStackView.spacing = iconSpacingH
    leadingStackView.alignment = .centerY
    leadingStackView.setHuggingPriority(.required, for: .horizontal)
    leadingStackView.edgeInsets = NSEdgeInsets(top: 0, left: iconSpacingH, bottom: iconSpacingH, right: iconSpacingH)
    for btn in trafficLightButtons {
      btn.alphaValue = 1
      btn.isHidden = false
      // Never expand in size, even if there is extra space:
      btn.setContentHuggingPriority(.required, for: .horizontal)
      btn.setContentHuggingPriority(.required, for: .vertical)
      // Never collapse in size:
      btn.setContentCompressionResistancePriority(.required, for: .horizontal)
      btn.setContentCompressionResistancePriority(.required, for: .vertical)
    }
    view.addSubview(leadingStackView)
    leadingStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
    leadingStackView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
    leadingStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    leadingTitleBarView = leadingStackView

    if leadingStackView.trackingAreas.count <= 1 && trafficLightButtons.count == 3 {
      for btn in trafficLightButtons {
        /// This solution works better than using `window` as owner, because with that the green button would get stuck with highlight
        /// when menu was shown.
        btn.addTrackingArea(NSTrackingArea(rect: btn.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: leadingStackView, userInfo: [PlayerWindowController.TrackingArea.key: PlayerWindowController.TrackingArea.customTitleBar]))
      }
    }

    // - Center views

    // See https://github.com/indragiek/INAppStoreWindow/blob/master/INAppStoreWindow/INAppStoreWindow.m
    windowController.window!.representedURL = windowController.player.info.currentURL

    titleText = TitleTextView()
    titleText.isEditable = false
    titleText.isSelectable = false
    titleText.isFieldEditor = false
    titleText.backgroundColor = .clear
    let pStyle: NSMutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    pStyle.lineBreakMode = .byTruncatingMiddle
    titleText.defaultParagraphStyle = pStyle
    titleText.alignment = .center
    titleText.heightAnchor.constraint(equalToConstant: 16).isActive = true
    titleText.setContentHuggingPriority(.required, for: .horizontal)

    if #available(macOS 11.0, *) {
      documentIconButton = NSWindow.standardWindowButton(.documentIconButton, for: .titled)
      let suffix = windowController.player.info.currentURL?.pathExtension ?? ""
      documentIconButton.image = NSImage.documentIcon(forSuffix: suffix, height: documentIconButton.frame.height)
    }
    centerTitleBarView = NSStackView(views: [titleText])
    centerTitleBarView.translatesAutoresizingMaskIntoConstraints = false
    centerTitleBarView.wantsLayer = true
    centerTitleBarView.layer?.backgroundColor = .clear
    centerTitleBarView.orientation = .horizontal
    centerTitleBarView.detachesHiddenViews = true
    centerTitleBarView.alignment = .centerY
    centerTitleBarView.spacing = 4

    view.addSubview(centerTitleBarView)
    centerTitleBarView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
    centerTitleBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    centerTitleBarView.setHuggingPriority(.defaultLow, for: .horizontal)  // 250
    centerTitleBarView.setHuggingPriority(.defaultHigh, for: .vertical)
    let c0 = centerTitleBarView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
    c0.priority = .defaultHigh
    c0.isActive = true

    // - Trailing views

    onTopButton = makeTitleBarButton(imgName: "ontop_off",
                                        action: #selector(windowController.toggleOnTop(_:)))
    onTopButton.setButtonType(.toggle)
    onTopButton.alternateImage = NSImage(imageLiteralResourceName: "ontop")

    trailingSidebarToggleButton = makeTitleBarButton(imgName: "sidebar.trailing",
                                                     action: #selector(windowController.toggleTrailingSidebarVisibility(_:)))
    let trailingStackView = NSStackView(views: [trailingSidebarToggleButton, onTopButton])
    trailingStackView.wantsLayer = true
    trailingStackView.layer?.backgroundColor = .clear
    trailingStackView.orientation = .horizontal
    trailingStackView.detachesHiddenViews = true
    trailingStackView.alignment = .centerY
    trailingStackView.spacing = iconSpacingH
    trailingStackView.edgeInsets = NSEdgeInsets(top: 0, left: iconSpacingH, bottom: 0, right: iconSpacingH)
    trailingStackView.distribution = .fill
    trailingStackView.setHuggingPriority(.required, for: .horizontal)  // 1000

    view.addSubview(trailingStackView)
    trailingStackView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
    trailingStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
    trailingStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    trailingStackView.setHuggingPriority(.defaultHigh, for: .horizontal)
    trailingTitleBarView = trailingStackView

    // make it expand to fill all available space
    centerTitleBarView.leadingAnchor.constraint(equalTo: leadingTitleBarView.trailingAnchor).isActive = true
//    let c1 = centerTitleBarView.leadingAnchor.constraint(lessThanOrEqualTo: leadingTitleBarView.trailingAnchor)
//    c1.priority = .defaultHigh
//    c1.isActive = true
    trailingTitleBarView.leadingAnchor.constraint(equalTo: titleText.trailingAnchor).isActive = true

    view.heightAnchor.constraint(equalToConstant: PlayerWindowController.standardTitleBarHeight).isActive = true

    view.configureSubtreeForCoreAnimation()
  }

  func makeTitleBarButton(imgName: String, action: Selector) -> NSButton {
    let btnImage = NSImage(imageLiteralResourceName: imgName)
    let button = NSButton(image: btnImage, target: windowController, action: action)
    button.setButtonType(.momentaryPushIn)
    button.bezelStyle = .smallSquare
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.refusesFirstResponder = true
    button.imageScaling = .scaleNone
    button.font = NSFont.systemFont(ofSize: 17)
    button.isHidden = true
    // Never expand in size, even if there is extra space:
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentHuggingPriority(.required, for: .vertical)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .vertical)
    return button
  }

  // Add to [different] superview
  func addViewToSuperview(_ superview: NSView) {
    superview.addSubview(view)
    view.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)
    refreshTitle()
  }

  func refreshTitle() {
    guard let currentPlayback = windowController.player.info.currentPlayback else {
      windowController.player.log.debug("Cannot update window title for custom title bar: no current media")
      return
    }
    let drawAsKeyWindow = titleText.window?.isKeyWindow ?? false
    titleText.alphaValue = drawAsKeyWindow ? activeTitleTextOpacity : inactiveTitleTextOpacity
    let controlAlpha = drawAsKeyWindow ? 1 : inactiveTitleControlOpacity
    for view in [leadingSidebarToggleButton, documentIconButton, trailingSidebarToggleButton, onTopButton] {
      // Skip buttons which are not visible
      guard let view, view.alphaValue > 0.0 else { continue }
      view.alphaValue = controlAlpha
    }

    let title = currentPlayback.url.lastPathComponent
    titleText.textColor = NSColor.windowFrameTextColor
    titleText.font = NSFont.titleBarFont(ofSize: NSFont.systemFontSize(for: .regular))
    titleText.string = title
    titleText.sizeToFit()
  }

  func removeAndCleanUp() {
    // Remove fake traffic light buttons & other custom title bar buttons (if any)
    for subview in view.subviews {
      for subSubview in subview.subviews {
        subSubview.removeFromSuperview()
      }
      subview.removeFromSuperview()
    }
    view.removeFromSuperview()
  }
}


/// Leading stack view for custom title bar. Needed to subclass parent view of traffic light buttons
/// in order to get their highlight working properly. See: https://stackoverflow.com/a/30417372/1347529
class TitleBarButtonsContainerView: NSStackView {
  var isMouseInside: Bool = false

  @objc func _mouseInGroup(_ button: NSButton) -> Bool {
    return isMouseInside
  }

  func markButtonsDirty() {
    for btn in views {
      btn.needsDisplay = true
    }
  }

  override func mouseEntered(with event: NSEvent) {
    isMouseInside = true
    markButtonsDirty()
  }

  override func mouseExited(with event: NSEvent) {
    isMouseInside = false
    markButtonsDirty()
  }
}

// Need to override to get mouse working properly for it
class TitleTextView: NSTextView {
  override var acceptsFirstResponder: Bool {
    return false
  }

  override func mouseDown(with event: NSEvent) {
    window?.mouseDown(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    window?.mouseUp(with: event)
  }

  override func rightMouseDown(with event: NSEvent) {
    window?.rightMouseDown(with: event)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }
}
