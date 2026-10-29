import AppKit

// Usage: display-probe <width>x<height>
// Prints NOTCH:<safeTop>:<width>:<notchLeft>:<notchRight>:<thickness>
//     or FLAT:<menuHeight>:<width>:0:0:<thickness> for the screen with those dims.
let targetDims = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let thickness = Int(NSStatusBar.system.thickness)

for screen in NSScreen.screens {
  let width = Int(screen.frame.size.width)
  let height = Int(screen.frame.size.height)
  guard "\(width)x\(height)" == targetDims else { continue }

  let safeTop = Int(screen.safeAreaInsets.top)
  if safeTop > 0 {
    let notchLeft = Int((screen.auxiliaryTopLeftArea ?? .zero).size.width)
    let rightAreaWidth = (screen.auxiliaryTopRightArea ?? .zero).size.width
    let notchRight = Int(CGFloat(width) - rightAreaWidth)
    print("NOTCH:\(safeTop):\(width):\(notchLeft):\(notchRight):\(thickness)")
  } else {
    // NSStatusBar.thickness under-reports some scaled displays.
    let measuredMenuHeight = Int(screen.frame.maxY - screen.visibleFrame.maxY)
    let menuHeight = measuredMenuHeight > 0 ? measuredMenuHeight : thickness
    print("FLAT:\(menuHeight):\(width):0:0:\(thickness)")
  }
  exit(0)
}
print("FLAT:\(thickness):0:0:0:\(thickness)")
