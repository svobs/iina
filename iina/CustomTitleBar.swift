//
//  CustomTitleBarViewController.swift
//  iina
//
//  Created by Matt Svoboda on 10/16/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

// Try to roughly match Apple's title bar colors:
fileprivate let activeControlOpacity: CGFloat = 1.0
fileprivate let inactiveControlOpacity: CGFloat = 0.40

/// For legacy windowed mode. Manual reconstruction of title bar is needed when not using `titled` window style.
class CustomTitleBarViewController: NSViewController {
  var windowController: PlayerWindowController!

  // Leading side
  var leadingTitleBarView: TitleBarButtonsContainerView!
  var closeButton: NSButton?
  var miniaturizeButton: NSButton?
  var zoomButton: NSButton?
  let leadingSidebarToggleButton = SymButton()

  var trafficLightButtons: [NSButton] {
    return [closeButton, miniaturizeButton, zoomButton].compactMap({ $0 })
  }

  // Center
  var documentIconButton: NSButton!
  var titleText: NSTextView!

  // Trailing side
  var trailingTitleBarView: NSStackView!
  let trailingSidebarToggleButton = SymButton()
  let onTopButton = SymButton()

  /// Use `loadView` instead of `viewDidLoad` because controller is not using storyboard
  override func loadView() {
    view = NSView()
    let builder = CustomTitleBar.shared

    let iconSpacingH = Constants.Distance.titleBarIconHSpacing

    // - Leading views

    // Add fake traffic light buttons:

    closeButton = NSWindow.standardWindowButton(.closeButton, for: .titled)
    miniaturizeButton = NSWindow.standardWindowButton(.miniaturizeButton, for: .titled)
    zoomButton = NSWindow.standardWindowButton(.zoomButton, for: .titled)
    let trafficLightButtons = trafficLightButtons
    builder.configureTitleBarButton(leadingSidebarToggleButton,
                                    Images.sidebarLeading,
                                    identifier: "leadingSidebarToggleButton",
                                    target: windowController,
                                    action: #selector(windowController.toggleLeadingSidebarVisibility(_:)),
                                    bounceOnClick: true)

    let leadingStackView = TitleBarButtonsContainerView(views: trafficLightButtons + [leadingSidebarToggleButton])
    leadingStackView.layer?.backgroundColor = .clear
    leadingStackView.orientation = .horizontal
    leadingStackView.detachesHiddenViews = true
    leadingStackView.alignment = .centerY
    leadingStackView.spacing = iconSpacingH
    leadingStackView.distribution = .fill
    leadingStackView.edgeInsets = NSEdgeInsets(top: 0, left: iconSpacingH, bottom: 0, right: iconSpacingH)
    leadingStackView.setHuggingPriority(.init(500), for: .horizontal)

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

    if #available(macOS 11.0, *) {
      documentIconButton = NSWindow.standardWindowButton(.documentIconButton, for: .titled)
      documentIconButton.image = Utility.icon(for: windowController.player.info.currentURL,
                                              optimizingForHeight: documentIconButton.frame.height)
    }

    // - Trailing views

    builder.configureTitleBarButton(onTopButton,
                                    Images.onTopOff,
                                    identifier: "onTopButton",
                                    target: windowController,
                                    action: #selector(windowController.toggleOnTop(_:)),
                                    bounceOnClick: false)

    builder.configureTitleBarButton(trailingSidebarToggleButton,
                                    Images.sidebarTrailing,
                                    identifier: "trailingSidebarToggleButton",
                                    target: windowController,
                                    action: #selector(windowController.toggleTrailingSidebarVisibility(_:)),
                                    bounceOnClick: true)
    let trailingStackView = NSStackView(views: [trailingSidebarToggleButton, onTopButton])
    trailingStackView.layer?.backgroundColor = .clear
    trailingStackView.orientation = .horizontal
    trailingStackView.detachesHiddenViews = true
    trailingStackView.alignment = .centerY
    trailingStackView.spacing = iconSpacingH
    trailingStackView.distribution = .fill
    trailingStackView.edgeInsets = NSEdgeInsets(top: 0, left: iconSpacingH, bottom: 0, right: iconSpacingH)
    trailingStackView.setHuggingPriority(.init(500), for: .horizontal)

    trailingTitleBarView = trailingStackView


    // - Add constraints

    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: Constants.Distance.standardTitleBarHeight).isActive = true

    view.addSubview(leadingStackView)
    leadingStackView.translatesAutoresizingMaskIntoConstraints = false
    leadingStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
    leadingStackView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
    leadingStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

    view.addSubview(documentIconButton)

    let titleText = TitleTextView()
    titleText.isEditable = false
    titleText.isSelectable = false
    titleText.isFieldEditor = false
    titleText.backgroundColor = .clear
    let pStyle: NSMutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    pStyle.lineBreakMode = .byTruncatingTail  // match native truncation
    titleText.defaultParagraphStyle = pStyle
    titleText.alignment = .center

    titleText.font = NSFont.titleBarFont(ofSize: NSFont.systemFontSize(for: .regular))
    titleText.textColor = .labelColor

    view.addSubview(titleText)
    titleText.translatesAutoresizingMaskIntoConstraints = false
    titleText.heightAnchor.constraint(equalToConstant: 16).isActive = true
    titleText.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    titleText.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
    // Kludge to include doc icon in text centering calculation, to match native title bar:
    let halfDocIconBtnWidth = (documentIconButton.image!.size.width * 0.5).rounded()
    // Priorities: CenterX < CompressionResistance < Equals(leading & trailing titles) < ContentHugging < 500
    // (>= 500 would interfere with window resize).
    // We want text's horizontal center to align with window's center, but more importantly it should use up
    // all available horizontal space.
    let cenXCon = titleText.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: halfDocIconBtnWidth)
    cenXCon.priority = .init(399)
    cenXCon.isActive = true
    titleText.setContentCompressionResistancePriority(.init(492), for: .horizontal)  // allow truncation
    titleText.setContentHuggingPriority(.init(499), for: .horizontal)
    self.titleText = titleText

    view.addSubview(trailingStackView)
    trailingStackView.translatesAutoresizingMaskIntoConstraints = false
    trailingStackView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
    trailingStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
    trailingStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

    documentIconButton.setContentHuggingPriority(.required, for: .horizontal)
    documentIconButton.setContentHuggingPriority(.required, for: .vertical)
    documentIconButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    documentIconButton.setContentCompressionResistancePriority(.required, for: .vertical)
    documentIconButton.translatesAutoresizingMaskIntoConstraints = false
    documentIconButton.trailingAnchor.constraint(equalTo: titleText.leadingAnchor).isActive = true
    documentIconButton.centerYAnchor.constraint(equalTo: titleText.centerYAnchor).isActive = true

    // make titleText expand to fill all available space
    let leadTitleCon = documentIconButton.leadingAnchor.constraint(greaterThanOrEqualTo: leadingTitleBarView.trailingAnchor)
    leadTitleCon.isActive = true
    let leadTitleConEQ = documentIconButton.leadingAnchor.constraint(equalTo: leadingTitleBarView.trailingAnchor)
    leadTitleConEQ.priority = .init(498)
    leadTitleConEQ.isActive = true
    let trailTitleCon = trailingStackView.leadingAnchor.constraint(greaterThanOrEqualTo: titleText.trailingAnchor)
    trailTitleCon.isActive = true
    let trailTitleConEQ = trailingStackView.leadingAnchor.constraint(equalTo: titleText.trailingAnchor)
    trailTitleConEQ.priority = .init(498)
    trailTitleConEQ.isActive = true

    view.configureSubtreeForCoreAnimation()
  }

  private func makeSpacerView() -> NSView {
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.setContentHuggingPriority(.minimum, for: .horizontal)
    spacer.setContentHuggingPriority(.minimum, for: .vertical)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return spacer
  }

  // Add to [different] superview
  func addViewToSuperview(_ superview: NSView) {
    superview.addSubview(view)
    view.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)
    refreshTitle()
  }

  override func viewWillAppear() {
    // Need to call this here to patch case where window is not active, but title bar is
    // "inside" & is made visible by mouse hover:
    refreshTitle()
  }

  func refreshTitle() {
    guard let currentPlayback = windowController.player.info.currentPlayback else {
      windowController.player.log.debug("Cannot update window title for custom title bar: no current media")
      return
    }

    // - Update colors

    let drawAsKeyWindow = titleText.window?.isKeyWindow ?? false

    // TODO: apply colors to buttons in inactive windows when toggling fadeable views!
    let alphaValue = drawAsKeyWindow ? activeControlOpacity : inactiveControlOpacity

    for view in [titleText, leadingSidebarToggleButton, trailingSidebarToggleButton, onTopButton] {
      // Skip buttons which are not visible
      guard let view, view.alphaValue > 0.0 else { continue }
      view.alphaValue = alphaValue
    }

    // - Update title text content
    
    let title = currentPlayback.url.lastPathComponent
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

    /// Apple note (https://developer.apple.com/documentation/appkit/nsview):
    /// NSView changes the default behavior of rightMouseDown(with:) so that it calls menu(for:) and, if non nil, presents the contextual menu. In macOS 10.7 and later, if the event is not handled, NSView passes the event up the responder chain. Because of these behaviorial changes, call super when implementing rightMouseDown(with:) in your custom NSView subclasses.
    super.rightMouseDown(with: event)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }

  // See https://stackoverflow.com/questions/11237622/using-autolayout-with-expanding-nstextviews
  override var intrinsicContentSize: NSSize {
    guard let textContainer = self.textContainer, let layoutManager = self.layoutManager else { return .zero }
    layoutManager.ensureLayout(for: textContainer)
    return layoutManager.usedRect(for: textContainer).size
  }

  override func didChangeText() {
    super.didChangeText()
    self.invalidateIntrinsicContentSize()
  }
}

class CustomTitleBar {
  static let shared = CustomTitleBar()

  func makeTitleBarButton(_ image: NSImage, identifier: String, target: AnyObject, action: Selector, bounceOnClick: Bool) -> SymButton {
    let button = SymButton()
    configureTitleBarButton(button, image, identifier: identifier, target: target, action: action, bounceOnClick: bounceOnClick)
    return button
  }

  func configureTitleBarButton(_ button: SymButton, _ image: NSImage, identifier: String, target: AnyObject, action: Selector, bounceOnClick: Bool) {
    button.image = image
    button.target = target
    button.action = action
    button.identifier = .init(identifier)
    button.refusesFirstResponder = true
    button.isHidden = true
    // Avoid expanding in size, even if there is extra space.
    // Use `defaultHigh` instead of `required`: this looks like it helps prevent title bar buttons from getting slightly clipped
    button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    button.setContentHuggingPriority(.defaultHigh, for: .vertical)
    // Never get compressed:
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .vertical)

    button.imageScaling = .scaleProportionallyUpOrDown

    button.bounceOnClick = bounceOnClick
  }
}
