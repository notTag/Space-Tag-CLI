// rename-overlay.swift — inline pill rename for space-labels.
//
// SketchyBar has no native text input, so to make a pill "turn into an editable
// text box" we float a borderless NSTextField over it. Run by space_click.sh on
// a right-click. Prints the outcome to stdout for the shell to apply:
//   COMMIT\t<text>   — Enter pressed OR clicked away: set this label
//   CANCEL           — Escape pressed: leave the label unchanged
// An empty COMMIT text is intentional: space.sh renders the space number when
// the label is "", so clearing the field falls back to the desktop number.
//
// The field is sized to its text (growing live as you type) so it stays close
// to the pill instead of ballooning over its neighbours, and is styled as a
// floating editor (dark fill, bright accent ring, drop shadow) so it reads as
// distinct from the sibling pills rather than blending into the row.
//
// Args (all positional, from space_click.sh):
//   1 currentLabel  2 sx  3 sy  4 pillW  5 pillH  6 displayX
//   7 bgHex(0xAARRGGBB)  8 fgHex  9 accentHex  10 cornerRadius
//
// Coordinates: SketchyBar reports the pill rect relative to its display's
// TOP-left (y down). Cocoa windows use GLOBAL BOTTOM-left (y up). We match the
// pill's display to an NSScreen via displayX (yabai's CG global x, which shares
// the x axis with Cocoa), then flip y within that screen. See the
// topmost-coordinate-systems note in the repo for why this keeps biting.

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
let bg     = color(arg(7,  "0xff313244"))   // dark fill (unfocused pill bg)
let fg     = color(arg(8,  "0xffcdd6f4"))   // light text
let accent = color(arg(9,  "0xff89b4fa"))   // ring (focused pill bg)
let radius = CGFloat(Double(arg(10)) ?? 6)

let font = NSFont.systemFont(ofSize: 13, weight: .semibold)

// ── width sized to the text (clamped), so it hugs the pill, not the row ────
let hPad: CGFloat = 22                       // breathing room around the text
func width(for text: String) -> CGFloat {
  let measured = (text as NSString).size(withAttributes: [.font: font]).width
  let minW = max(CGFloat(pillW), 56)
  let maxW = min(280, screen.frame.size.width - 16)
  return min(max(ceil(measured) + hPad, minW), maxW)
}

// ── place the field over the pill ─────────────────────────────────────────
// Match the pill's display to a screen by left edge (x is shared by yabai's CG
// coords and Cocoa). Treat sx as display-relative when it fits the screen
// width, else as already-global — robust to either SketchyBar convention.
let screen = NSScreen.screens.min { abs($0.frame.origin.x - displayX) < abs($1.frame.origin.x - displayX) }
           ?? NSScreen.main ?? NSScreen.screens[0]
let pillLeft   = (sx >= 0 && sx <= screen.frame.size.width) ? screen.frame.origin.x + sx : sx
let pillCenter = pillLeft + pillW / 2
let cocoaY     = screen.frame.maxY - sy - pillH

// Center the field on the pill, clamped to the screen.
func frame(width w: CGFloat) -> NSRect {
  var fx = pillCenter - w / 2
  fx = max(screen.frame.minX + 4, min(fx, screen.frame.maxX - w - 4))
  return NSRect(x: fx, y: cocoaY, width: w, height: pillH)
}

// Borderless windows refuse key status by default — must override.
final class KeyWindow: NSWindow {
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
    FileHandle.standardOutput.write(Data(out.utf8))  // pipe-safe (avoids print buffering)
    exit(0)
  }

  // Grow/shrink the field to fit as the name is typed, staying centered.
  func controlTextDidChange(_ n: Notification) {
    let w = width(for: field.stringValue)
    if abs(w - window.frame.size.width) > 0.5 {
      window.setFrame(frame(width: w), display: true)
    }
  }

  // Enter commits, Escape cancels; everything else stays in the editor.
  func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
    switch sel {
    case #selector(NSResponder.insertNewline(_:)):    finish(commit: true);  return true
    case #selector(NSResponder.cancelOperation(_:)):  finish(commit: false); return true
    default: return false
    }
  }
  // Clicking outside the field (loses key) locks in the name.
  func windowDidResignKey(_ n: Notification) { finish(commit: true) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, can still hold a key window

let initial = frame(width: width(for: curLabel))
let win = KeyWindow(contentRect: initial, styleMask: .borderless, backing: .buffered, defer: false)
win.level = .screenSaver              // above SketchyBar's menu-bar topmost strip
win.isOpaque = false
win.backgroundColor = .clear
win.hasShadow = true                  // lift it off the row (rounded layer-backed field)
win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

// Layer-backed container carries the rounded fill, accent ring and shadow so the
// editor visibly floats above the pills instead of looking like one of them.
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
field.selectText(nil)                 // select-all so typing replaces the name

app.run()
