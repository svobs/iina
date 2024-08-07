//
//  PrefUIViewController.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let SizeWidthTag = 0
fileprivate let SizeHeightTag = 1
fileprivate let UnitPointTag = 0
fileprivate let UnitPercentTag = 1
fileprivate let SideLeftTag = 0
fileprivate let SideRightTag = 1
fileprivate let SideTopTag = 0
fileprivate let SideBottomTag = 1

@objcMembers
class PrefUIViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefUIViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.ui", comment: "UI")
  }

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_ui"))!
  }

  static var oscToolbarButtons: [Preference.ToolBarButton] {
    get {
      return (Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []).compactMap(Preference.ToolBarButton.init(rawValue:))
    }
  }

  override var sectionViews: [NSView] {
    return [sectionWindowView, sectionFullScreenView, sectionAppearanceView, sectionOSCView, sectionSidebarsView, sectionOSDView,
            sectionThumbnailView, sectionPictureInPictureView, sectionAccessibilityView]
  }

  private let toolbarSettingsSheetController = PrefOSCToolbarSettingsSheetController()

  @IBOutlet weak var aspectPresetsTokenField: AspectTokenField!
  @IBOutlet weak var cropPresetsTokenField: AspectTokenField!

  @IBOutlet weak var resetAspectPresetsButton: NSButton!
  @IBOutlet weak var resetCropPresetsButton: NSButton!

  @IBOutlet var sectionAppearanceView: NSView!
  @IBOutlet var sectionFullScreenView: NSView!
  @IBOutlet var sectionWindowView: NSView!
  @IBOutlet var sectionOSCView: NSView!
  @IBOutlet var sectionOSDView: NSView!
  @IBOutlet var sectionSidebarsView: NSView!
  @IBOutlet var sectionThumbnailView: NSView!
  @IBOutlet var sectionPictureInPictureView: NSView!
  @IBOutlet var sectionAccessibilityView: NSView!

  @IBOutlet weak var themeMenu: NSMenu!
  @IBOutlet weak var topBarPositionContainerView: NSView!
  @IBOutlet weak var showTopBarTriggerContainerView: NSView!
  @IBOutlet weak var windowPreviewImageView: NSImageView!
  @IBOutlet weak var oscBottomPlacementContainerView: NSView!
  @IBOutlet weak var oscSnapToCenterCheckboxContainerView: NSView!
  @IBOutlet weak var oscToolbarStackView: NSStackView!
  @IBOutlet weak var oscAutoHideTimeoutTextField: NSTextField!
  @IBOutlet weak var hideFadeableViewsOutsideWindowCheckBox: NSButton!

  @IBOutlet var leadingSidebarBox: NSBox!
  @IBOutlet var trailingSidebarBox: NSBox!

  @IBOutlet weak var resizeWindowWhenOpeningFileCheckbox: NSButton!
  @IBOutlet weak var resizeWindowTimingPopUpButton: NSPopUpButton!
  @IBOutlet weak var unparsedGeometryabel: NSTextField!
  @IBOutlet weak var mpvWindowSizeCollapseView: CollapseView!
  @IBOutlet weak var mpvWindowPositionCollapseView: CollapseView!
  @IBOutlet weak var windowSizeCheckBox: NSButton!
  @IBOutlet weak var simpleVideoSizeRadioButton: NSButton!
  @IBOutlet weak var mpvGeometryRadioButton: NSButton!
  @IBOutlet weak var spacer0: NSView!
  @IBOutlet weak var windowSizeTypePopUpButton: NSPopUpButton!
  @IBOutlet weak var windowSizeValueTextField: NSTextField!
  @IBOutlet weak var windowSizeUnitPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowSizeBox: NSBox!
  @IBOutlet weak var windowPosCheckBox: NSButton!
  @IBOutlet weak var windowPosXOffsetTextField: NSTextField!
  @IBOutlet weak var windowPosXUnitPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosXAnchorPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosYOffsetTextField: NSTextField!
  @IBOutlet weak var windowPosYUnitPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosYAnchorPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosBox: NSBox!

  @IBOutlet weak var currentThumbCacheSizeTextField: NSTextField!

  @IBOutlet weak var pipDoNothing: NSButton!
  @IBOutlet weak var pipHideWindow: NSButton!
  @IBOutlet weak var pipMinimizeWindow: NSButton!

  private let observedPrefKeys: [Preference.Key] = [
    .enableAdvancedSettings,
    .showTopBarTrigger,
    .topBarPlacement,
    .bottomBarPlacement,
    .enableOSC,
    .oscPosition,
    .themeMaterial,
    .settingsTabGroupLocation,
    .playlistTabGroupLocation,
    .controlBarToolbarButtons,
    .oscBarToolbarIconSize,
    .oscBarToolbarIconSpacing,
    .useLegacyWindowedMode,
    .aspectRatioPanelPresets,
    .cropPanelPresets,
  ]

  override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    // Set up key-value observing for changes to this view's properties:
    addObserver(self, forKeyPath: #keyPath(view.effectiveAppearance), options: [.old, .new], context: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    ObjcUtils.silenced {
      for key in self.observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
      UserDefaults.standard.removeObserver(self, forKeyPath: #keyPath(view.effectiveAppearance))
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    updateAspectControlsFromPrefs()
    updateCropControlsFromPrefs()

    oscToolbarStackView.wantsLayer = true

    refreshSidebarSection()
    refreshTitleBarAndOSCSection(animate: false)
    updateOSCToolbarButtons()
    updateGeometryUI()
    updatePipBehaviorRelatedControls()

    let removeThemeMenuItemWithTag = { (tag: Int) in
      if let item = self.themeMenu.item(withTag: tag) {
        self.themeMenu.removeItem(item)
      }
    }
    removeThemeMenuItemWithTag(Preference.Theme.mediumLight.rawValue)
    removeThemeMenuItemWithTag(Preference.Theme.ultraDark.rawValue)
  }

  override func viewDidAppear() {
    super.viewDidAppear()

    updateThumbnailCacheStat()
  }

  private func updateThumbnailCacheStat() {
    AppDelegate.shared.preferenceWindowController.indexingQueue.async { [self] in
      let newString = "\(FloatingPointByteCountFormatter.string(fromByteCount: ThumbnailCacheManager.shared.getCacheSize(), countStyle: .binary))B"
      DispatchQueue.main.async { [self] in
        currentThumbCacheSizeTextField.stringValue = newString
      }
    }
  }

  private func updateAspectControlsFromPrefs() {
    let newAspects = Preference.string(for: .aspectRatioPanelPresets) ?? ""
    aspectPresetsTokenField.commaSeparatedValues = newAspects
    let defaultAspects = Preference.defaultPreference[.aspectRatioPanelPresets] as? String
    resetAspectPresetsButton.isHidden = (defaultAspects == newAspects)
  }

  private func updateCropControlsFromPrefs() {
    let newCropPresets = Preference.string(for: .cropPanelPresets) ?? ""
    cropPresetsTokenField.commaSeparatedValues = newCropPresets
    let defaultCropPresets = Preference.defaultPreference[.cropPanelPresets] as? String
    resetCropPresetsButton.isHidden = defaultCropPresets == newCropPresets
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let _ = change else { return }

    switch keyPath {
    case PK.aspectRatioPanelPresets.rawValue:
      updateAspectControlsFromPrefs()
  case PK.cropPanelPresets.rawValue:
      updateCropControlsFromPrefs()
    case PK.showTopBarTrigger.rawValue,
      PK.enableOSC.rawValue,
      PK.topBarPlacement.rawValue,
      PK.bottomBarPlacement.rawValue,
      PK.oscPosition.rawValue,
      PK.useLegacyWindowedMode.rawValue,
      PK.themeMaterial.rawValue,
      PK.enableAdvancedSettings.rawValue:

      refreshTitleBarAndOSCSection()
      updateGeometryUI()
    case PK.settingsTabGroupLocation.rawValue, PK.playlistTabGroupLocation.rawValue:
      refreshSidebarSection()
    case PK.controlBarToolbarButtons.rawValue,
      PK.oscBarToolbarIconSize.rawValue,
      PK.oscBarToolbarIconSpacing.rawValue:

      updateOSCToolbarButtons()
    case #keyPath(view.effectiveAppearance):
      if Preference.enum(for: .themeMaterial) == Preference.Theme.system {
        // Refresh image in case dark mode changed
        let ib = PlayerWindowPreviewImageBuilder(self.view)
        windowPreviewImageView.image = ib.updateWindowPreviewImage()
      }
    default:
      break
    }
  }

  private func refreshSidebarSection() {
    let tabGroup1: Preference.SidebarLocation = Preference.enum(for: .settingsTabGroupLocation)
    let tabGroup2: Preference.SidebarLocation = Preference.enum(for: .playlistTabGroupLocation)
    let isUsingLeadingSidebar = tabGroup1 == .leadingSidebar || tabGroup2 == .leadingSidebar
    let isUsingTrailingSidebar = tabGroup1 == .trailingSidebar || tabGroup2 == .trailingSidebar
    setSubViews(of: leadingSidebarBox, enabled: isUsingLeadingSidebar)
    setSubViews(of: trailingSidebarBox, enabled: isUsingTrailingSidebar)
  }

  private func refreshTitleBarAndOSCSection(animate: Bool = true) {
    let ib = PlayerWindowPreviewImageBuilder(self.view)

    let titleBarIsOverlay = ib.hasTitleBar && ib.topBarPlacement == .insideViewport
    let oscIsOverlay = ib.oscEnabled && (ib.oscPosition == .floating ||
                                         (ib.oscPosition == .top && ib.topBarPlacement == .insideViewport) ||
                                         (ib.oscPosition == .bottom && ib.bottomBarPlacement == .insideViewport))
    let hasOverlay = titleBarIsOverlay || oscIsOverlay

    var viewHidePairs: [(NSView, Bool)] = []
    // Use animation where possible to make the transition less jarring
    NSAnimationContext.runAnimationGroup({context in
      context.duration = 0
      context.allowsImplicitAnimation = animate ? !AccessibilityPreferences.motionReductionEnabled : false
      context.timingFunction = CAMediaTimingFunction(name: .linear)

      oscAutoHideTimeoutTextField.isEnabled = hasOverlay
      hideFadeableViewsOutsideWindowCheckBox.isEnabled = hasOverlay
      windowPreviewImageView.image = ib.updateWindowPreviewImage()

      let oscIsFloating = ib.oscEnabled && ib.oscPosition == .floating

      if oscSnapToCenterCheckboxContainerView.isHidden != !oscIsFloating {
        viewHidePairs.append((oscSnapToCenterCheckboxContainerView, !oscIsFloating))
      }

      let oscIsBottom = ib.oscEnabled && ib.oscPosition == .bottom
      if oscBottomPlacementContainerView.isHidden != !oscIsBottom {
        viewHidePairs.append((oscBottomPlacementContainerView, !oscIsBottom))
      }

      let hasTopBar = ib.hasTopBar
      if topBarPositionContainerView.isHidden != !hasTopBar {
        viewHidePairs.append((topBarPositionContainerView, !hasTopBar))
      }

      let showTopBarTrigger = hasTopBar && ib.topBarPlacement == .insideViewport && Preference.isAdvancedEnabled
      if showTopBarTriggerContainerView.isHidden != !showTopBarTrigger {
        viewHidePairs.append((showTopBarTriggerContainerView, !showTopBarTrigger))
      }

      for (view, shouldHide) in viewHidePairs {
        for subview in view.subviews {
          subview.animator().isHidden = shouldHide
        }
      }

      // Need this to get proper slide effect
      oscBottomPlacementContainerView.superview?.layoutSubtreeIfNeeded()
    }, completionHandler: { [self] in
      oscAutoHideTimeoutTextField.isEnabled = hasOverlay
      hideFadeableViewsOutsideWindowCheckBox.isEnabled = hasOverlay
      windowPreviewImageView.image = ib.updateWindowPreviewImage()

      NSAnimationContext.runAnimationGroup({context in
        context.duration = animate ? AccessibilityPreferences.adjustedDuration(IINAAnimation.DefaultDuration) : 0
        context.allowsImplicitAnimation = animate ? !AccessibilityPreferences.motionReductionEnabled : false
        context.timingFunction = CAMediaTimingFunction(name: .linear)
        for (view, shouldHide) in viewHidePairs {
          view.animator().isHidden = shouldHide
        }
      }, completionHandler: {
      })
    })
  }

  @IBAction func saveAspectPresets(_ sender: AspectTokenField) {
    let csv = sender.commaSeparatedValues
    if Preference.string(for: .aspectRatioPanelPresets) != csv {
      Logger.log("Saving \(Preference.Key.aspectRatioPanelPresets.rawValue): \"\(csv)\"", level: .verbose)
      Preference.set(csv, for: .aspectRatioPanelPresets)
    }
  }

  @IBAction func saveCropPresets(_ sender: AspectTokenField) {
    let csv = sender.commaSeparatedValues
    if Preference.string(for: .cropPanelPresets) != csv {
      Logger.log("Saving \(Preference.Key.cropPanelPresets.rawValue): \"\(csv)\"", level: .verbose)
      Preference.set(csv, for: .cropPanelPresets)
    }
  }

  @IBAction func resetAspectPresets(_ sender: NSButton) {
    let defaultValue = Preference.defaultPreference[.aspectRatioPanelPresets]
    Preference.set(defaultValue, for: .aspectRatioPanelPresets)
  }

  @IBAction func resetCropPresets(_ sender: NSButton) {
    let defaultValue = Preference.defaultPreference[.cropPanelPresets]
    Preference.set(defaultValue, for: .cropPanelPresets)
  }

  @IBAction func setupPipBehaviorRelatedControls(_ sender: NSButton) {
    Preference.set(sender.tag, for: .windowBehaviorWhenPip)
  }

  private func updatePipBehaviorRelatedControls() {
    let pipBehaviorOption = Preference.enum(for: .windowBehaviorWhenPip) as Preference.WindowBehaviorWhenPip
    ([pipDoNothing, pipHideWindow, pipMinimizeWindow] as [NSButton])
      .first { $0.tag == pipBehaviorOption.rawValue }?.state = .on
  }

  @IBAction func customizeOSCToolbarAction(_ sender: Any) {
    toolbarSettingsSheetController.currentItemsView?.initItems(fromItems: PrefUIViewController.oscToolbarButtons)
    toolbarSettingsSheetController.currentButtonTypes = PrefUIViewController.oscToolbarButtons
    view.window?.beginSheet(toolbarSettingsSheetController.window!) { response in
      guard response == .OK else { return }
      let newItems = self.toolbarSettingsSheetController.currentButtonTypes
      let array = newItems.map { $0.rawValue }
      Preference.set(array, for: .controlBarToolbarButtons)
    }
  }

  private func updateOSCToolbarButtons() {
    oscToolbarStackView.views.forEach { oscToolbarStackView.removeView($0) }
    for buttonType in PrefUIViewController.oscToolbarButtons {
      let button = OSCToolbarButton()
      button.setStyle(buttonType: buttonType)
      oscToolbarStackView.addView(button, in: .trailing)
      oscToolbarStackView.spacing = 2 * button.iconPadding
      oscToolbarStackView.edgeInsets = .init(top: button.iconPadding, left: button.iconPadding, bottom: button.iconPadding, right: button.iconPadding)
      // Button is actually disabled so that its mouseDown goes to its superview instead
      button.isEnabled = false
      // But don't gray it out
      (button.cell! as! NSButtonCell).imageDimsWhenDisabled = false
    }
  }

  @IBAction func updateWindowResizeScheme(_ sender: AnyObject) {
    guard let scheme = Preference.ResizeWindowScheme(rawValue: sender.tag) else {
      let tag: String = String(sender.tag ?? -1)
      Logger.log("Could not find ResizeWindowScheme matching rawValue \(tag)", level: .error)
      return
    }
    Preference.set(scheme.rawValue, for: .resizeWindowScheme)
    updateGeometryUI()
  }

  // Called by a UI control. Updates prefs + any dependent UI controls
  @IBAction func updateGeometryValue(_ sender: AnyObject) {
    if resizeWindowWhenOpeningFileCheckbox.state == .off {
      Preference.set(Preference.ResizeWindowTiming.never.rawValue, for: .resizeWindowTiming)
      Preference.set("", for: .initialWindowSizePosition)

    } else {
      if let timing = Preference.ResizeWindowTiming(rawValue: resizeWindowTimingPopUpButton.selectedTag()) {
        Preference.set(timing.rawValue, for: .resizeWindowTiming)
      }

      var geometry = ""
      // size
      if windowSizeCheckBox.state == .on {
        // either width or height, but not both
        if windowSizeTypePopUpButton.selectedTag() == SizeHeightTag {
          geometry += "x"
        }

        let isPercentage = windowSizeUnitPopUpButton.selectedTag() == UnitPercentTag
        if isPercentage {
          geometry += normalizePercentage(windowSizeValueTextField.stringValue)
        } else {
          geometry += windowSizeValueTextField.stringValue
        }
      }
      // position
      if windowPosCheckBox.state == .on {
        // X
        geometry += windowPosXAnchorPopUpButton.selectedTag() == SideLeftTag ? "+" : "-"

        if windowPosXUnitPopUpButton.selectedTag() == UnitPercentTag {
          geometry += normalizePercentage(windowPosXOffsetTextField.stringValue)
        } else {
          geometry += normalizeSignedInteger(windowPosXOffsetTextField.stringValue)
        }

        // Y
        geometry += windowPosYAnchorPopUpButton.selectedTag() == SideTopTag ? "+" : "-"

        if windowPosYUnitPopUpButton.selectedTag() == UnitPercentTag {
          geometry += normalizePercentage(windowPosYOffsetTextField.stringValue)
        } else {
          geometry += normalizeSignedInteger(windowPosYOffsetTextField.stringValue)
        }
      }
      Logger.log("Saving pref \(Preference.Key.initialWindowSizePosition.rawValue.quoted) with geometry: \(geometry.quoted)")
      Preference.set(geometry, for: .initialWindowSizePosition)
    }

    updateGeometryUI()
  }

  private func normalizeSignedInteger(_ string: String) -> String {
    let intValue = Int(string) ?? 0
    return intValue < 0 ? "\(intValue)" : "+\(intValue)"
  }

  private func normalizePercentage(_ string: String) -> String {
    var sizeInt = Int(string) ?? 100
    sizeInt = max(0, sizeInt)
    sizeInt = min(sizeInt, 100)
    return "\(sizeInt)%"
  }

  // Updates UI from prefs
  private func updateGeometryUI() {
    let resizeOption = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
    let scheme: Preference.ResizeWindowScheme = Preference.enum(for: .resizeWindowScheme)

    let isAnyResizeEnabled: Bool
    switch resizeOption {
    case .never:
      resizeWindowWhenOpeningFileCheckbox.state = .off
      isAnyResizeEnabled = false
    case .always, .onlyWhenOpen:
      resizeWindowWhenOpeningFileCheckbox.state = .on
      isAnyResizeEnabled = true
      resizeWindowTimingPopUpButton.selectItem(withTag: resizeOption.rawValue)

      switch scheme {
      case .mpvGeometry:
        mpvGeometryRadioButton.state = .on
        simpleVideoSizeRadioButton.state = .off
      case .simpleVideoSizeMultiple:
        mpvGeometryRadioButton.state = .off
        simpleVideoSizeRadioButton.state = .on
      }
    }

    mpvGeometryRadioButton.isHidden = !isAnyResizeEnabled
    simpleVideoSizeRadioButton.superview?.isHidden = !isAnyResizeEnabled

    // mpv
    let isMpvGeometryEnabled = isAnyResizeEnabled && scheme == .mpvGeometry
    var isUsingMpvSize = false
    var isUsingMpvPos = false

    if isMpvGeometryEnabled {
      let geometryString = Preference.string(for: .initialWindowSizePosition) ?? ""
      if let geometry = MPVGeometryDef.parse(geometryString) {
        Logger.log("Parsed \(Preference.quoted(.initialWindowSizePosition))=\(geometryString.quoted) ➤ \(geometry)")
        unparsedGeometryabel.stringValue = "\"\(geometryString)\""
        // size
        if let h = geometry.h {
          isUsingMpvSize = true
          windowSizeTypePopUpButton.selectItem(withTag: SizeHeightTag)
          windowSizeUnitPopUpButton.selectItem(withTag: geometry.hIsPercentage ? UnitPercentTag : UnitPointTag)
          windowSizeValueTextField.stringValue = h
        } else if let w = geometry.w {
          isUsingMpvSize = true
          windowSizeTypePopUpButton.selectItem(withTag: SizeWidthTag)
          windowSizeUnitPopUpButton.selectItem(withTag: geometry.wIsPercentage ? UnitPercentTag : UnitPointTag)
          windowSizeValueTextField.stringValue = w
        }
        // position
        if var x = geometry.x, var y = geometry.y {
          let xSign = geometry.xSign ?? "+"
          let ySign = geometry.ySign ?? "+"
          x = x.hasPrefix("+") ? String(x.dropFirst()) : x
          y = y.hasPrefix("+") ? String(y.dropFirst()) : y
          isUsingMpvPos = true
          windowPosXAnchorPopUpButton.selectItem(withTag: xSign == "+" ? SideLeftTag : SideRightTag)
          windowPosXOffsetTextField.stringValue = x
          windowPosXUnitPopUpButton.selectItem(withTag: geometry.xIsPercentage ? UnitPercentTag : UnitPointTag)
          windowPosYAnchorPopUpButton.selectItem(withTag: ySign == "+" ? SideTopTag : SideBottomTag)
          windowPosYOffsetTextField.stringValue = y
          windowPosYUnitPopUpButton.selectItem(withTag: geometry.yIsPercentage ? UnitPercentTag : UnitPointTag)
        }
      } else {
        if !geometryString.isEmpty {
          Logger.log("Failed to parse string \(geometryString.quoted) from \(Preference.quoted(.initialWindowSizePosition)) pref", level: .error)
        }
        unparsedGeometryabel.stringValue = ""
      }
    }
    unparsedGeometryabel.isHidden = !(Preference.isAdvancedEnabled && isMpvGeometryEnabled)
    spacer0.isHidden = !isMpvGeometryEnabled
    mpvWindowSizeCollapseView.isHidden = !isMpvGeometryEnabled
    mpvWindowPositionCollapseView.isHidden = !isMpvGeometryEnabled
    windowSizeCheckBox.state = isUsingMpvSize ? .on : .off
    windowPosCheckBox.state = isUsingMpvPos ? .on : .off
    mpvWindowSizeCollapseView.setCollapsed(!isUsingMpvSize, animated: true)
    mpvWindowPositionCollapseView.setCollapsed(!isUsingMpvPos, animated: true)
  }

  private func setSubViews(of view: NSBox, enabled: Bool) {
    view.contentView?.subviews.forEach { ($0 as? NSControl)?.isEnabled = enabled }
  }

  @IBAction func disableAnimationsHelpAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.disableAnimationsHelpLink)!)
  }
}

@objc(IntEqualsZeroTransformer) class IntEqualsZeroTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSNumber.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let number = value as? NSNumber else { return nil }
    return number == 0
  }
}

@objc(IntEqualsOneTransformer) class IntEqualsOneTransformer: IntEqualsZeroTransformer {

  override func transformedValue(_ value: Any?) -> Any? {
    guard let number = value as? NSNumber else { return nil }
    return number == 1
  }
}

@objc(IntEqualsTwoTransformer) class IntEqualsTwoTransformer: IntEqualsZeroTransformer {

  override func transformedValue(_ value: Any?) -> Any? {
    guard let number = value as? NSNumber else { return nil }
    return number == 2
  }
}

@objc(IntNotEqualsOneTransformer) class IntNotEqualsOneTransformer: IntEqualsZeroTransformer {

  override func transformedValue(_ value: Any?) -> Any? {
    guard let number = value as? NSNumber else { return nil }
    return number != 1
  }
}

@objc(IntNotEqualsTwoTransformer) class IntNotEqualsTwoTransformer: IntEqualsZeroTransformer {

  override func transformedValue(_ value: Any?) -> Any? {
    guard let number = value as? NSNumber else { return nil }
    return number != 2
  }
}


@objc(ResizeTimingTransformer) class ResizeTimingTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSNumber.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let timing = value as? Int else { return nil }
    return timing != Preference.ResizeWindowTiming.never.rawValue
  }
}

@objc(InverseResizeTimingTransformer) class InverseResizeTimingTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSNumber.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let timing = value as? Int else { return nil }
    return timing == Preference.ResizeWindowTiming.never.rawValue
  }
}


class PlayerWindowPreviewView: NSView {

  override func awakeFromNib() {
    self.wantsLayer = true
    self.layer?.cornerRadius = 6
    self.layer?.masksToBounds = true
    self.layer?.borderWidth = 1
    self.layer?.borderColor = CGColor(gray: 0.6, alpha: 0.5)
  }

}
