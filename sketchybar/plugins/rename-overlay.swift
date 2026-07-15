
import AppKit

let args = CommandLine.arguments
func arg(_ i: Int, _ fallback: String = "") -> String { i < args.count ? args[i] : fallback }

let curLabel = arg(1)
let sx       = Double(arg(2)) ?? 0
let sy       = Double(arg(3)) ?? 0
let pillW    = Double(arg(4)) ?? 60
let pillH    = Double(arg(5)) ?? 22
let displayX = Double(arg(6)) ?? 0

func color(_ hex: String) -> NSColor {
  var s = hex.lowercased()
  if s.hasPrefix("0x") { s.removeFirst(2) }
  var v: UInt64 = 0
  Scanner(string: s).scanHexInt64(&v)
  let a = CGFloat((v >> 24) & 0xff) / 255
  let r = CGFloat((v >> 16) & 0xff) / 255
  let g = CGFloat((v >>  8) & 0xff) / 255
  let b = CGFloat( v        & 0xff) / 255
  return NSColor(srgbRed: r, green: g, blue: b, alpha: a == 0 ? 1 : a)
}
let bg     = color(arg(7,  "0xff313244"))
let fg     = color(arg(8,  "0xffcdd6f4"))
let accent = color(arg(9,  "0xff89b4fa"))
let radius = CGFloat(Double(arg(10)) ?? 6)

let font = NSFont.systemFont(ofSize: 13, weight: .semibold)

let hPad: CGFloat = 22
func width(for text: String) -> CGFloat {
  let measured = (text as NSString).size(withAttributes: [.font: font]).width
  let minW = max(CGFloat(pillW), 56)
  let maxW = min(280, screen.frame.size.width - 16)
  return min(max(ceil(measured) + hPad, minW), maxW)
}

let screen = NSScreen.screens.min { abs($0.frame.origin.x - displayX) < abs($1.frame.origin.x - displayX) }
           ?? NSScreen.main ?? NSScreen.screens[0]
let pillLeft   = (sx >= 0 && sx <= screen.frame.size.width) ? screen.frame.origin.x + sx : sx
let pillCenter = pillLeft + pillW / 2
// SketchyBar uses display-relative top-left coordinates; AppKit uses global bottom-left.
let cocoaY     = screen.frame.maxY - sy - pillH

func frame(width w: CGFloat) -> NSRect {
  var fx = pillCenter - w / 2
  fx = max(screen.frame.minX + 4, min(fx, screen.frame.maxX - w - 4))
  return NSRect(x: fx, y: cocoaY, width: w, height: pillH)
}

final class KeyWindow: NSWindow {
  // Borderless windows cannot receive keyboard input by default.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

final class Controller: NSObject, NSTextFieldDelegate, NSWindowDelegate {
  let field: NSTextField
  let window: NSWindow
  var finished = false
  init(field: NSTextField, window: NSWindow) { self.field = field; self.window = window }

  func finish(commit: Bool) {
    if finished { return }
    finished = true
    let out = commit ? "COMMIT\t\(field.stringValue)\n" : "CANCEL\n"
    FileHandle.standardOutput.write(Data(out.utf8))
    exit(0)
  }

  func controlTextDidChange(_ n: Notification) {
    let w = width(for: field.stringValue)
    if abs(w - window.frame.size.width) > 0.5 {
      window.setFrame(frame(width: w), display: true)
    }
  }

  func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
    switch sel {
    case #selector(NSResponder.insertNewline(_:)):    finish(commit: true);  return true
    case #selector(NSResponder.cancelOperation(_:)):  finish(commit: false); return true
    default: return false
    }
  }
  func windowDidResignKey(_ n: Notification) { finish(commit: true) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let initial = frame(width: width(for: curLabel))
let win = KeyWindow(contentRect: initial, styleMask: .borderless, backing: .buffered, defer: false)
win.level = .screenSaver
win.isOpaque = false
win.backgroundColor = .clear
win.hasShadow = true
win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

let box = NSView(frame: NSRect(origin: .zero, size: initial.size))
box.wantsLayer = true
box.layer?.backgroundColor = bg.cgColor
box.layer?.cornerRadius = radius
box.layer?.borderWidth = 1.5
box.layer?.borderColor = accent.cgColor
box.autoresizingMask = [.width, .height]

let field = NSTextField(frame: box.bounds.insetBy(dx: 6, dy: 0))
field.stringValue = curLabel
field.font = font
field.textColor = fg
field.drawsBackground = false
field.isBezeled = false
field.isBordered = false
field.focusRingType = .none
field.alignment = .center
field.usesSingleLineMode = true
field.lineBreakMode = .byTruncatingTail
field.cell?.wraps = false
field.cell?.isScrollable = true
field.autoresizingMask = [.width, .height]
box.addSubview(field)

let ctrl = Controller(field: field, window: win)
field.delegate = ctrl
win.delegate = ctrl
win.contentView = box

win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
win.makeFirstResponder(field)
field.selectText(nil)

app.run()
