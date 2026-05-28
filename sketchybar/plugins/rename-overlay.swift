// rename-overlay.swift — inline pill rename for space-labels.
//
// SketchyBar has no native text input, so to make a pill "turn into an editable
// text box" we float a borderless NSTextField, styled like the pill, exactly
// over it. Run by plugins/space_click.sh on a right-click. Prints the outcome
// to stdout for the shell to apply:
//   COMMIT\t<text>   — Enter pressed OR clicked away: set this label
//   CANCEL           — Escape pressed: leave the label unchanged
// An empty COMMIT text is intentional: space.sh renders the space number when
// the label is "", so clearing the field falls back to the desktop number.
//
// Args (all positional, from space_click.sh):
//   1 currentLabel  2 sx  3 sy  4 pillW  5 pillH  6 displayX
//   7 bgHex(0xAARRGGBB)  8 fgHex  9 cornerRadius
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
let bg = color(arg(7, "0xff89b4fa"))
let fg = color(arg(8, "0xff1e1e2e"))
let radius = CGFloat(Double(arg(9)) ?? 6)

// ── place the field over the pill ─────────────────────────────────────────
// Match the pill's display to a screen by left edge (x is shared by yabai's CG
// coords and Cocoa). Treat sx as display-relative when it fits the screen
// width, else as already-global — robust to either SketchyBar convention.
let screen = NSScreen.screens.min { abs($0.frame.origin.x - displayX) < abs($1.frame.origin.x - displayX) }
           ?? NSScreen.main ?? NSScreen.screens[0]
let pillLeft = (sx >= 0 && sx <= screen.frame.size.width) ? screen.frame.origin.x + sx : sx
let cocoaY   = screen.frame.maxY - sy - pillH

// Comfortable minimum width to type into; centered on the pill, clamped to screen.
let fieldW = max(pillW, 160)
let pillCenter = pillLeft + pillW / 2
var fx = pillCenter - fieldW / 2
fx = max(screen.frame.minX + 4, min(fx, screen.frame.maxX - fieldW - 4))
let frame = NSRect(x: fx, y: cocoaY, width: fieldW, height: pillH)

// Borderless windows refuse key status by default — must override.
final class KeyWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

final class Controller: NSObject, NSTextFieldDelegate, NSWindowDelegate {
  let field: NSTextField
  var finished = false
  init(_ f: NSTextField) { field = f }

  func finish(commit: Bool) {
    if finished { return }
    finished = true
    let out = commit ? "COMMIT\t\(field.stringValue)\n" : "CANCEL\n"
    FileHandle.standardOutput.write(Data(out.utf8))  // pipe-safe (avoids print buffering)
    exit(0)
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

let win = KeyWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
win.level = .screenSaver              // above SketchyBar's menu-bar topmost strip
win.isOpaque = false
win.backgroundColor = .clear
win.hasShadow = false                 // square shadow behind rounded field looks off
win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

let field = NSTextField(frame: NSRect(origin: .zero, size: frame.size))
field.stringValue = curLabel
field.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
field.textColor = fg
field.backgroundColor = bg
field.drawsBackground = true
field.isBezeled = false
field.isBordered = false
field.focusRingType = .none
field.alignment = .center
field.usesSingleLineMode = true
field.lineBreakMode = .byTruncatingTail
field.cell?.wraps = false
field.cell?.isScrollable = true
field.wantsLayer = true
field.layer?.cornerRadius = radius
field.layer?.masksToBounds = true

let ctrl = Controller(field)
field.delegate = ctrl
win.delegate = ctrl
win.contentView = field

win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
win.makeFirstResponder(field)
field.selectText(nil)                 // select-all so typing replaces the name

app.run()
