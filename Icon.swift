import AppKit
import Foundation

let root = URL(fileURLWithPath: "Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: 1) }
func draw(name: String, dark: Bool) throws {
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()
    let background = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    if dark {
        let gradient = NSGradient(starting: color(0.035, 0.035, 0.04), ending: color(0.12, 0.12, 0.13))!
        gradient.draw(in: background, angle: 90)
    } else {
        color(1, 1, 1).setFill()
        background.fill()
    }
    let ink = dark ? color(1, 1, 1) : color(0, 0, 0)
    NSGraphicsContext.saveGraphicsState()
    // Use the same larger wallet size in light and dark appearances.
    let transform = NSAffineTransform()
    transform.translateX(by: 512, yBy: 545)
    transform.scale(by: 1.18)
    transform.translateX(by: -512, yBy: -545)
    transform.concat()
    ink.setStroke()
    // The upper edge suggests a folded wallet behind the main body.
    let upper = NSBezierPath()
    upper.move(to: NSPoint(x: 229, y: 638))
    upper.curve(to: NSPoint(x: 300, y: 730), controlPoint1: NSPoint(x: 229, y: 685), controlPoint2: NSPoint(x: 260, y: 716))
    upper.line(to: NSPoint(x: 675, y: 785))
    upper.curve(to: NSPoint(x: 754, y: 715), controlPoint1: NSPoint(x: 720, y: 794), controlPoint2: NSPoint(x: 754, y: 760))
    upper.line(to: NSPoint(x: 754, y: 650))
    upper.lineWidth = 44
    upper.lineJoinStyle = .round
    upper.lineCapStyle = .round
    upper.stroke()
    let wallet = NSBezierPath(roundedRect: NSRect(x: 225, y: 305, width: 574, height: 350), xRadius: 76, yRadius: 76)
    wallet.lineWidth = 44
    wallet.stroke()
    let flap = NSBezierPath(roundedRect: NSRect(x: 565, y: 430, width: 238, height: 140), xRadius: 68, yRadius: 68)
    ink.setFill(); flap.fill()
    color(0.33, 0.78, 0.65).setFill()
    NSBezierPath(ovalIn: NSRect(x: 626, y: 477, width: 46, height: 46)).fill()
    NSGraphicsContext.restoreGraphicsState()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("icon encoding failed") }
    try png.write(to: root.appendingPathComponent(name))
}
try draw(name: "light.png", dark: false)
try draw(name: "dark.png", dark: true)
let json = """
{"images":[{"filename":"light.png","idiom":"universal","platform":"ios","size":"1024x1024"},{"appearances":[{"appearance":"luminosity","value":"dark"}],"filename":"dark.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try json.write(to: root.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

