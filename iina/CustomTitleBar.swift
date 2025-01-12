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
  let leadingStackView = TitleBarButtonsContainerView()
  var closeButton: NSButton?
  var miniaturizeButton: NSButton?
  var zoomButton: NSButton?
  let leadingSidebarToggleButton = SymButton()

  var trafficLightButtons: [NSButton] {
    return [closeButton, miniaturizeButton, zoomButton].compactMap({ $0 })
  }

  // Center
  let centerStackView = NSStackView()
  var documentIconButton: NSButton!
  let titleText = TitleTextView()

  // Trailing side
  let trailingStackView = NSStackView()
  let trailingSidebarToggleButton = SymButton()
  let onTopButton = SymButton()

  var symButtons: [SymButton] {
    return [leadingSidebarToggleButton, trailingSidebarToggleButton, onTopButton]
  }

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

    leadingStackView.setViews(trafficLightButtons + [leadingSidebarToggleButton], in: .center)
    leadingStackView.identifier = .init("TitleBar-LeadingStackView")
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

    documentIconButton = NSWindow.standardWindowButton(.documentIconButton, for: .titled)
    documentIconButton.image = Utility.icon(for: windowController.player.info.currentURL,
                                            optimizingForHeight: documentIconButton.frame.height)

    titleText.identifier = .init("TitleBar-TextView")
    titleText.isEditable = false
    titleText.isSelectable = false
    titleText.isFieldEditor = false
    titleText.backgroundColor = .clear
    let pStyle: NSMutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    pStyle.lineBreakMode = .byTruncatingTail  // match native truncation
    titleText.defaultParagraphStyle = pStyle
    titleText.font = NSFont.titleBarFont(ofSize: NSFont.systemFontSize(for: .regular))
    titleText.textColor = .labelColor

    centerStackView.setViews([documentIconButton, titleText], in: .center)
    centerStackView.identifier = .init("TitleBar-CenterStackView")
    centerStackView.layer?.backgroundColor = .clear
    centerStackView.orientation = .horizontal
    centerStackView.detachesHiddenViews = true
    centerStackView.alignment = .centerY
    centerStackView.spacing = 0
    centerStackView.distribution = .fill
    centerStackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    centerStackView.setHuggingPriority(.init(500), for: .horizontal)

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
    trailingStackView.setViews([trailingSidebarToggleButton, onTopButton], in: .center)
    trailingStackView.identifier = .init("TitleBar-TrailingStackView")
    trailingStackView.layer?.backgroundColor = .clear
    trailingStackView.orientation = .horizontal
    trailingStackView.detachesHiddenViews = true
    trailingStackView.alignment = .centerY
    trailingStackView.spacing = iconSpacingH
    trailingStackView.distribution = .fill
    trailingStackView.edgeInsets = NSEdgeInsets(top: 0, left: iconSpacingH, bottom: 0, right: iconSpacingH)
    trailingStackView.setHuggingPriority(.init(500), for: .horizontal)

    initConstraints()

    view.configureSubtreeForCoreAnimation()
  }

  private func initConstraints() {
    // Root view:
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: Constants.Distance.standardTitleBarHeight).isActive = true

    // Stack views:
    view.addSubview(leadingStackView)
    view.addSubview(centerStackView)
    view.addSubview(trailingStackView)
    initConstraintsForStackViews()

    initConstraintsForCenterStackViewItems()
  }

  private func initConstraintsForStackViews() {
    leadingStackView.translatesAutoresizingMaskIntoConstraints = false
    centerStackView.translatesAutoresizingMaskIntoConstraints = false
    trailingStackView.translatesAutoresizingMaskIntoConstraints = false

    // Vertical constraints:

    leadingStackView.addConstraintsToFillSuperview(top: 0, bottom: 0)
    centerStackView.addConstraintsToFillSuperview(top: 0, bottom: 0)
    trailingStackView.addConstraintsToFillSuperview(top: 0, bottom: 0)

    // Horizontal constraints:

    leadingStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true

    let centerStackLeadingEqCon = centerStackView.leadingAnchor.constraint(equalTo: leadingStackView.trailingAnchor)
    centerStackLeadingEqCon.priority = .init(400)
    centerStackLeadingEqCon.isActive = true
    centerStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingStackView.trailingAnchor).isActive = true

    let centerStackTrailingEqCon = centerStackView.trailingAnchor.constraint(equalTo: trailingStackView.trailingAnchor)
    centerStackTrailingEqCon.priority = .init(400)
    centerStackTrailingEqCon.isActive = true
    centerStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingStackView.leadingAnchor).isActive = true

    trailingStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
  }

  private func initConstraintsForCenterStackViewItems() {
    titleText.translatesAutoresizingMaskIntoConstraints = false
    titleText.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    // Priorities: CenterX < CompressionResistance < Equals(leading & trailing titles) < ContentHugging < 500
    // (>= 500 would interfere with window resize).
    // We want text's horizontal center to align with window's center, but more importantly it should use up
    // all available horizontal space.
    let cenXCon = centerStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0)
    cenXCon.priority = .init(401)  // make priority greater than leading & trailing EQ constraints above
    cenXCon.isActive = true
    titleText.setContentCompressionResistancePriority(.init(499), for: .horizontal)  // allow truncation
    titleText.setContentHuggingPriority(.init(499), for: .horizontal)

    documentIconButton.translatesAutoresizingMaskIntoConstraints = false
    documentIconButton.setContentHuggingPriority(.required, for: .horizontal)
    documentIconButton.setContentHuggingPriority(.required, for: .vertical)
    documentIconButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    documentIconButton.setContentCompressionResistancePriority(.required, for: .vertical)

    // Make titleText expand to fill all available space
    let leadTitleCon = documentIconButton.leadingAnchor.constraint(greaterThanOrEqualTo: leadingStackView.trailingAnchor)
    leadTitleCon.isActive = true
    let leadTitleConEQ = documentIconButton.leadingAnchor.constraint(equalTo: leadingStackView.trailingAnchor)
    leadTitleConEQ.priority = .init(498)
    leadTitleConEQ.isActive = true
    let trailTitleCon = trailingStackView.leadingAnchor.constraint(greaterThanOrEqualTo: titleText.trailingAnchor)
    trailTitleCon.isActive = true
    let trailTitleConEQ = trailingStackView.leadingAnchor.constraint(equalTo: titleText.trailingAnchor)
    trailTitleConEQ.priority = .init(498)
    trailTitleConEQ.isActive = true
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
  func addViewTo(superview: NSView) {
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

    // - Update title text content

    let title = currentPlayback.url.lastPathComponent
    if titleText.string != title {
      titleText.string = title
      titleText.sizeToFit()
      titleText.invalidateIntrinsicContentSize()
    }

    // - Update colors

    let drawAsKeyWindow = titleText.window?.isKeyWindow ?? false

    // TODO: apply colors to buttons in inactive windows when toggling fadeable views!
    let alphaValue = drawAsKeyWindow ? activeControlOpacity : inactiveControlOpacity

    for view in [titleText, leadingSidebarToggleButton, trailingSidebarToggleButton, onTopButton] {
      // Skip buttons which are not visible
      guard view.alphaValue > 0.0 else { continue }
      view.alphaValue = alphaValue
    }
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

// MARK: - Support Classes

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

/// Need to override `NSTextView` to get mouse working properly for it.
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
    guard let textContainer = self.textContainer, let layoutManager = self.layoutManager else {
      return super.intrinsicContentSize
    }
    layoutManager.ensureLayout(for: textContainer)

    let stringSize = attributedString().size()
    // Note: need to add some extra width to avoid ellipses (…) being used unnecessarily. Not sure why.
    let contentSize = NSSize(width: (stringSize.width + 8).rounded(), height: stringSize.height)
    associatedPlayer?.log.verbose{"TitleText intrinsicContentSize: \(contentSize): \(textStorage!.string)"}
    return contentSize
  }

  override func didChangeText() {
    self.invalidateIntrinsicContentSize()
    super.didChangeText()
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
