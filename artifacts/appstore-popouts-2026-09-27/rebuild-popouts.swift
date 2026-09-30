import AppKit
import Foundation

let width = 1290.0
let height = 2796.0
let originals = "/Users/sirishjoshi/Documents/drive-download-20260927T122937Z-1-001"
let edits = "/Users/sirishjoshi/Documents/ChatGPT/Speaking Coach/artifacts/appstore-popouts-2026-09-27"
struct TopRect { let x: Double; let y: Double; let w: Double; let h: Double
    var ns: NSRect { NSRect(x: x, y: height-y-h, width: w, height: h) }
}
func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> TopRect { TopRect(x:x,y:y,w:w,h:h) }
func roundedPanel(_ target: TopRect, radius: Double = 42, shadow: Bool = true) {
    NSGraphicsContext.saveGraphicsState()
    if shadow {
        let s = NSShadow()
        s.shadowBlurRadius = 26
        s.shadowOffset = NSSize(width: 0, height: -13)
        s.shadowColor = NSColor.black.withAlphaComponent(0.20)
        s.set()
    }
    NSColor.white.setFill()
    NSBezierPath(roundedRect: target.ns, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()
}
func crop(_ image: NSImage, _ source: TopRect, _ target: TopRect, radius: Double = 0, shadow: Bool = false) {
    if radius > 0 { roundedPanel(target, radius: radius, shadow: shadow) }
    NSGraphicsContext.saveGraphicsState()
    if radius > 0 { NSBezierPath(roundedRect: target.ns, xRadius: radius, yRadius: radius).addClip() }
    image.draw(in: target.ns, from: source.ns, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}
func label(_ string: String, _ box: TopRect, size: Double, color: NSColor, weight: NSFont.Weight = .regular) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attr: [NSAttributedString.Key: Any] = [.font:font, .foregroundColor:color, .paragraphStyle:p]
    (string as NSString).draw(in: box.ns, withAttributes: attr)
}
func bars() {
    let heights: [Double] = [32,53,83,142,83,53,32]
    let xs: [Double] = [459,505,551,597,663,709,755]
    for i in 0..<7 {
        let h = heights[i]
        let bar = rect(xs[i], 1480-h/2, i == 3 ? 40 : 34, h)
        NSColor(calibratedRed: 1.0, green: 0.31, blue: 0.36, alpha: 1).setFill()
        NSBezierPath(roundedRect: bar.ns, xRadius: bar.w/2, yRadius: bar.w/2).fill()
    }
}
func cleanPhoneBackground(_ target: TopRect) {
    let colors = [
        NSColor(calibratedRed:0.979,green:0.963,blue:0.948,alpha:1),
        NSColor(calibratedRed:0.964,green:0.947,blue:0.930,alpha:1)
    ]
    NSGradient(colors:colors)!.draw(in:target.ns, angle:-90)
    NSColor(calibratedRed:0.65,green:0.60,blue:0.57,alpha:0.13).setFill()
    var yy = target.y + 20
    while yy < target.y + target.h {
        var xx = target.x + 24
        while xx < target.x + target.w {
            NSBezierPath(ovalIn:rect(xx,yy,2.3,2.3).ns).fill()
            xx += 51
        }
        yy += 51
    }
}
func keyedCrop(_ image:NSImage, _ source:TopRect, _ target:TopRect, radius:Double) {
    let pw = Int(target.w), ph = Int(target.h)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pw,pixelsHigh:ph,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
          let ctx = NSGraphicsContext(bitmapImageRep:rep), let bytes = rep.bitmapData else { fatalError("keyed crop") }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=ctx; ctx.imageInterpolation = .high
    image.draw(in:NSRect(x:0,y:0,width:target.w,height:target.h),from:source.ns,operation:.copy,fraction:1)
    ctx.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
    for y in 0..<ph { for x in 0..<pw {
        let offset = y*rep.bytesPerRow+x*4
        let r=Int(bytes[offset]),g=Int(bytes[offset+1]),b=Int(bytes[offset+2])
        if r > 236 && g > 230 && b > 224 && abs(r-g) < 22 && abs(g-b) < 22 { bytes[offset+3]=0 }
    }}
    let overlay = NSImage(size:NSSize(width:target.w,height:target.h))
    overlay.addRepresentation(rep)
    roundedPanel(target,radius:radius,shadow:true)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect:target.ns,xRadius:radius,yRadius:radius).addClip()
    overlay.draw(in:target.ns,from:NSRect(x:0,y:0,width:target.w,height:target.h),operation:.sourceOver,fraction:1)
    NSGraphicsContext.restoreGraphicsState()
}
let jobs = ["01", "03", "04", "05", "06", "07", "08"]
for n in jobs {
    guard let original = NSImage(contentsOfFile: "\(originals)/screenshot_\(n).png"),
          let edited = NSImage(contentsOfFile: "\(edits)/screenshot_\(n)-popout-no-glow-1290x2796.png"),
          let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:1290, pixelsHigh:2796, bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false, colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0),
          let context = NSGraphicsContext(bitmapImageRep:bitmap) else { fatalError("Cannot open \(n)") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.white.setFill(); NSRect(x:0,y:0,width:width,height:height).fill()
    original.draw(in:NSRect(x:0,y:0,width:width,height:height), from:NSRect(origin:.zero,size:original.size), operation:.copy, fraction:1)
    switch n {
    case "01":
        crop(edited, rect(178,2720,930,76), rect(178,2720,930,76))
        crop(edited, rect(917,2310,310,430), rect(917,2310,310,430))
        crop(original, rect(214,2370,640,400), rect(116,2320,810,416), radius:54, shadow:true)
        crop(edited, rect(952,2320,230,416), rect(952,2320,230,416), radius:54, shadow:true)
    case "03":
        crop(original, rect(228,1382,834,466), rect(92,1286,1108,646), radius:40, shadow:true)
        crop(original, rect(239,2440,812,130), rect(134,2384,1022,182), radius:80, shadow:true)
    case "04":
        let source = [rect(239,1798,396,288),rect(655,1798,396,288),rect(239,2100,396,315),rect(655,2100,396,315)]
        let target = [rect(130,1792,504,286),rect(660,1792,504,286),rect(130,2094,504,320),rect(660,2094,504,320)]
        for i in 0..<4 { crop(original, source[i], target[i], radius:48, shadow:true) }
    case "05":
        crop(original,rect(220,1950,850,310),rect(220,2290,850,310))
        roundedPanel(rect(116,1270,1060,1050), radius:65, shadow:true)
        bars()
        label("A hiring manager",rect(438,1620,414,55),size:31,color:NSColor(calibratedRed:0.96,green:0.25,blue:0.31,alpha:1))
        label("Interesting. What's one tool you made\nthat people actually use every day?",rect(168,1705,954,140),size:42,color:NSColor(calibratedWhite:0.10,alpha:1),weight:.regular)
        crop(original, rect(238,2300,395,125), rect(158,1925,474,145), radius:68, shadow:true)
        crop(original, rect(654,2300,397,125), rect(658,1925,474,145), radius:68, shadow:true)
        crop(original, rect(238,2440,813,140), rect(158,2105,974,147), radius:68, shadow:true)
    case "06":
        crop(edited,rect(180,2180,910,52),rect(180,2180,910,52))
        crop(original, rect(239,1405,810,686), rect(130,1388,1030,810), radius:44, shadow:true)
    case "07":
        keyedCrop(original, rect(265,1535,816,858), rect(150,1460,1048,942), radius:58)
    case "08":
        crop(original, rect(239,924,810,950), rect(158,916,976,1038), radius:52, shadow:true)
    default: break
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using:.png, properties:[:]) else { fatalError("Cannot encode \(n)") }
    let destination = "\(edits)/screenshot_\(n)-popout-native-1290x2796.png"
    try data.write(to:URL(fileURLWithPath:destination))
    print(destination)
}
