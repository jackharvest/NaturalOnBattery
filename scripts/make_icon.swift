import Cocoa

let sizes = [16, 32, 128, 256, 512]
let iconsetPath = "icon.iconset"

try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderIcon(pixelSize: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: pixelSize * 0.22, yRadius: pixelSize * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.74, blue: 0.47, alpha: 1.0),
        NSColor(calibratedRed: 0.11, green: 0.53, blue: 0.58, alpha: 1.0)
    ])
    gradient?.draw(in: bgPath, angle: -90)

    // "↕" — scroll direction, doubling as the menu bar glyph.
    let text = "\u{2195}" as NSString
    let font = NSFont.systemFont(ofSize: pixelSize * 0.5, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let textSize = text.size(withAttributes: attrs)
    let textRect = NSRect(
        x: (pixelSize - textSize.width) / 2,
        y: (pixelSize - textSize.height) / 2 - pixelSize * 0.02,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attrs)

    // Small battery notch at the bottom, the one detail that isn't just "arrows."
    let batteryWidth = pixelSize * 0.34
    let batteryHeight = pixelSize * 0.14
    let batteryX = (pixelSize - batteryWidth) / 2
    let batteryY = pixelSize * 0.16
    let bodyPath = NSBezierPath(roundedRect: NSRect(x: batteryX, y: batteryY, width: batteryWidth, height: batteryHeight), xRadius: batteryHeight * 0.25, yRadius: batteryHeight * 0.25)
    NSColor.white.withAlphaComponent(0.9).setStroke()
    bodyPath.lineWidth = max(1, pixelSize * 0.02)
    bodyPath.stroke()
    let nubWidth = pixelSize * 0.02
    let nubPath = NSBezierPath(roundedRect: NSRect(x: batteryX + batteryWidth, y: batteryY + batteryHeight * 0.28, width: nubWidth, height: batteryHeight * 0.44), xRadius: nubWidth * 0.4, yRadius: nubWidth * 0.4)
    NSColor.white.withAlphaComponent(0.9).setFill()
    nubPath.fill()
    let fillInset = pixelSize * 0.02
    let fillPath = NSBezierPath(roundedRect: NSRect(x: batteryX + fillInset, y: batteryY + fillInset, width: (batteryWidth - fillInset * 2) * 0.6, height: batteryHeight - fillInset * 2), xRadius: (batteryHeight - fillInset * 2) * 0.3, yRadius: (batteryHeight - fillInset * 2) * 0.3)
    NSColor.white.withAlphaComponent(0.9).setFill()
    fillPath.fill()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(path)")
    }
    FileManager.default.createFile(atPath: path, contents: data)
}

for size in sizes {
    savePNG(renderIcon(pixelSize: CGFloat(size)), to: "\(iconsetPath)/icon_\(size)x\(size).png")
    savePNG(renderIcon(pixelSize: CGFloat(size * 2)), to: "\(iconsetPath)/icon_\(size)x\(size)@2x.png")
}

print("Iconset written to \(iconsetPath)")
