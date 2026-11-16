import AppKit
import WebKit

struct SlideNotes: Decodable {
  let time: String
  let title: String
  let text: String

  func storageKey(at index: Int) -> String {
    "transcript.\(index).\(title)"
  }

}

final class Presenter: NSObject, NSApplicationDelegate, WKNavigationDelegate, NSWindowDelegate,
  NSTextViewDelegate
{
  let entries: [SlideNotes]
  let screenView: WKWebView
  var slides: NSWindow!
  var transcript: NSWindow!
  let heading = NSTextField(wrappingLabelWithString: "")
  let clockLabel = NSTextField(labelWithString: "0:00")
  var startTime: TimeInterval?

  let counter = NSTextField(labelWithString: "")
  let words = NSTextView()
  let scroll = NSScrollView()
  var page = 0
  var ready = false

  let checking = CommandLine.arguments.contains("--verify")

  override init() {
    let data = try! Data(
      contentsOf: Bundle.main.url(forResource: "Transcript", withExtension: "json")!)
    entries = try! JSONDecoder().decode([SlideNotes].self, from: data)
    let config = WKWebViewConfiguration()
    config.mediaTypesRequiringUserActionForPlayback = []
    screenView = WKWebView(frame: .zero, configuration: config)
    super.init()
  }
  func window(_ title: String, _ rect: NSRect) -> NSWindow {
    let window = NSWindow(
      contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = title
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.collectionBehavior = [.managed, .fullScreenNone]
    return window
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    configureMenu()
    configureWindows()
    configureKeyboard()
    setPage(0)
    slides.orderFront(nil)
    transcript.makeKeyAndOrderFront(nil)
    transcript.makeFirstResponder(nil)
    NSApp.activate(ignoringOtherApps: true)
    let url = Bundle.main.url(forResource: "Slides", withExtension: "html")!
    screenView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
  }

  func configureMenu() {
    let menu = NSMenu()
    let appItem = NSMenuItem()
    menu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "Quit Presenter", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    appItem.submenu = appMenu
    let editItem = NSMenuItem()
    menu.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editItem.submenu = editMenu
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    NSApp.mainMenu = menu
  }

  func configureWindows() {
    let display = NSScreen.main ?? NSScreen.screens[0]
    let frame = display.visibleFrame.insetBy(dx: 8, dy: 8)
    let other = NSScreen.screens.first { $0 != display }
    let noteWidth =
      other == nil ? min(max(frame.width * 0.33, 350), 540) : min(660, frame.width * 0.85)
    let area =
      other?.visibleFrame.insetBy(dx: 12, dy: 14)
      ?? NSRect(
        x: frame.minX, y: frame.minY, width: frame.width - noteWidth - 10, height: frame.height)
    let width = min(area.width, (area.height - 40) * 16 / 9)
    let height = width * 9 / 16
    slides = window(
      "Slides",
      NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height))
    slides.contentAspectRatio = NSSize(width: 16, height: 9)
    slides.contentView = screenView
    screenView.navigationDelegate = self
    let x = other == nil ? frame.maxX - noteWidth : frame.midX - noteWidth / 2
    transcript = window(
      "Transcript — Presenter only",
      NSRect(x: x, y: frame.minY + 16, width: noteWidth, height: min(frame.height - 55, 780)))
    transcript.sharingType = .none
    transcript.minSize = NSSize(width: 320, height: 330)
    configureNotes()
  }

  func configureKeyboard() {
    NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown]) { [weak self] event in
      guard let self, event.window === self.slides || event.window === self.transcript else {
        return event
      }
      if event.type == .rightMouseDown {
        self.move(1)
        return nil
      }
      if event.window === self.transcript && self.transcript.firstResponder === self.words {
        if event.keyCode == 53 {
          self.transcript.makeFirstResponder(nil)
          return nil
        }
        return event
      }
      if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty { return event }
      switch event.keyCode {
      case 124, 121, 49:
        if !event.isARepeat { self.move(1) }
        return nil
      case 123, 116:
        if !event.isARepeat { self.move(-1) }
        return nil
      case 115:
        self.setPage(0)
        return nil
      default: return event
      }
    }
  }

  func configureNotes() {
    let root = NSView()
    transcript.contentView = root
    clockLabel.font = .monospacedDigitSystemFont(ofSize: 64, weight: .semibold)
    clockLabel.alignment = .center
    heading.font = .systemFont(ofSize: 22, weight: .semibold)
    heading.maximumNumberOfLines = 3
    counter.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
    counter.textColor = .secondaryLabelColor
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.autohidesScrollers = true
    words.isEditable = true
    words.isSelectable = true
    words.isRichText = false
    words.allowsUndo = true
    words.delegate = self
    words.drawsBackground = false
    words.isVerticallyResizable = true
    words.autoresizingMask = [.width]
    words.textContainer?.widthTracksTextView = true
    words.textContainer?.lineFragmentPadding = 0
    scroll.documentView = words
    let hint = NSTextField(
      labelWithString: "Click text to edit · Esc to finish · → / Right-click to advance")
    hint.textColor = .secondaryLabelColor
    hint.font = .systemFont(ofSize: 13)
    for view in [clockLabel, counter, heading, scroll, hint] as [NSView] {
      root.addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
      view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20).isActive = true
      view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18).isActive = true
    }
    NSLayoutConstraint.activate([
      clockLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
      counter.topAnchor.constraint(equalTo: clockLabel.bottomAnchor, constant: 8),
      heading.topAnchor.constraint(equalTo: counter.bottomAnchor, constant: 12),
      scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 16),
      scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -14),
      hint.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
    ])
  }
  func savedText(for index: Int) -> String {
    let entry = entries[index]
    return UserDefaults.standard.string(forKey: entry.storageKey(at: index)) ?? entry.text
  }
  func textDidChange(_ notification: Notification) {
    let entry = entries[page]
    if words.string == entry.text {
      UserDefaults.standard.removeObject(forKey: entry.storageKey(at: page))
    } else {
      UserDefaults.standard.set(words.string, forKey: entry.storageKey(at: page))
    }
  }
  func move(_ step: Int) {
    if step > 0 && page == 0 && startTime == nil {
      startTime = ProcessInfo.processInfo.systemUptime
      let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
        guard let self, let start = self.startTime else { return }
        let seconds = Int(ProcessInfo.processInfo.systemUptime - start)
        self.clockLabel.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
      }
      RunLoop.main.add(timer, forMode: .common)
      return
    }
    setPage(page + step)
  }
  func setPage(_ index: Int) {
    guard entries.indices.contains(index) else { return }
    if transcript.firstResponder === words { transcript.makeFirstResponder(nil) }
    words.undoManager?.removeAllActions()
    page = index
    let current = entries[index]
    counter.stringValue = "Slide \(index+1) / \(entries.count)     \(current.time)"
    heading.stringValue = current.title
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 4
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 22),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: style,
    ]
    words.textStorage?.setAttributedString(
      NSAttributedString(string: savedText(for: index), attributes: attributes))
    words.typingAttributes = attributes
    transcript.contentView?.layoutSubtreeIfNeeded()
    fitNotes()
    scroll.contentView.scroll(to: .zero)
    scroll.reflectScrolledClipView(scroll.contentView)
    if ready { screenView.evaluateJavaScript("showSlide(\(index))", completionHandler: nil) }
  }
  func fitNotes() {
    let size = scroll.contentSize
    guard size.width > 50, size.height > 50, let layout = words.layoutManager,
      let container = words.textContainer
    else { return }
    words.setFrameSize(NSSize(width: size.width, height: size.height))
    let range = NSRange(location: 0, length: (words.string as NSString).length)
    for fontSize in stride(from: 25, through: 17, by: -1) {
      words.textStorage?.addAttribute(
        .font, value: NSFont.systemFont(ofSize: CGFloat(fontSize)), range: range)
      layout.ensureLayout(for: container)
      if layout.usedRect(for: container).height <= size.height - 5 { break }
    }
    words.setFrameSize(
      NSSize(
        width: size.width,
        height: max(size.height, ceil(layout.usedRect(for: container).height) + 5)))
  }
  func windowDidResize(_ notification: Notification) {
    if let window = notification.object as? NSWindow, window === transcript { fitNotes() }
  }
  func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    ready = true
    screenView.evaluateJavaScript("showSlide(\(page))", completionHandler: nil)
    if checking { verifyEditingAndNavigation() }
  }
}

extension Presenter {
  func verifyEditingAndNavigation() {
    let original = savedText(for: page)
    transcript.makeFirstResponder(words)
    words.insertText(
      " test", replacementRange: NSRange(location: (words.string as NSString).length, length: 0))
    let saved = savedText(for: page) == original + " test"
    arrow(123, transcript)
    let stillEditing = page == 0 && startTime == nil
    words.insertText(
      original, replacementRange: NSRange(location: 0, length: (words.string as NSString).length))
    transcript.makeFirstResponder(nil)
    guard saved, stillEditing, savedText(for: page) == original else { exit(1) }
    arrow(124, transcript)
    guard page == 0, startTime != nil else { exit(1) }
    verify(0)
  }
  // Smoke test the actual two windows, their key bindings, and WebKit playback.
  func arrow(_ code: UInt16, _ window: NSWindow) {
    let event = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
    )!
    NSApp.sendEvent(event)
  }
  func verify(_ index: Int, attemptsLeft: Int = 5) {
    DispatchQueue.main.asyncAfter(deadline: .now() + (index == 0 ? 0.3 : 1.2)) {
      let snapshot = """
        ({
            page: active,
            visible: document.querySelectorAll('section.on').length,
            audienceOnly: !document.querySelector('#notes,nav'),
            playback: document.querySelector('.on video')?.currentTime ?? -1
        })
        """
      self.screenView.evaluateJavaScript(snapshot) { result, error in
        guard error == nil, let state = result as? [String: Any],
          state["page"] as? Int == index, state["visible"] as? Int == 1,
          state["audienceOnly"] as? Bool == true,
          self.words.string == self.savedText(for: index),
          self.slides.windowNumber != self.transcript.windowNumber
        else {
          print("Presenter verification failed at slide", index + 1, error as Any)
          exit(1)
        }
        if state["playback"] as? Double == 0 {
          guard attemptsLeft > 0 else {
            print("Video did not start on slide", index + 1)
            exit(1)
          }
          self.verify(index, attemptsLeft: attemptsLeft - 1)
          return
        }
        if index + 1 < self.entries.count {
          self.arrow(124, index.isMultiple(of: 2) ? self.transcript : self.slides)
          self.verify(index + 1)
        } else {
          self.arrow(123, self.transcript)
          guard self.page == max(0, index - 1) else { exit(1) }
          print("Verified both windows, notes, navigation and playback on", index + 1, "slides.")
          exit(0)
        }
      }
    }
  }
}
let application = NSApplication.shared
let presenter = Presenter()
application.setActivationPolicy(.regular)
application.delegate = presenter
application.run()
