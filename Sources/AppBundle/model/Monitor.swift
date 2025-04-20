import AppKit
import Common

private struct MonitorImpl {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
}

extension MonitorImpl: Monitor {
    var height: CGFloat { rect.height }
    var width: CGFloat { rect.width }
}

/// Use it instead of NSScreen because it can be mocked in tests
protocol Monitor: AeroAny {
    /// The index in NSScreen.screens array. 1-based index
    var monitorAppKitNsScreenScreensId: Int { get }
    var name: String { get }
    var rect: Rect { get }
    var visibleRect: Rect { get }
    var width: CGFloat { get }
    var height: CGFloat { get }
}

class LazyMonitor: Monitor {
    private let screen: NSScreen
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let width: CGFloat
    let height: CGFloat
    private var _rect: Rect?
    private var _visibleRect: Rect?

    init(monitorAppKitNsScreenScreensId: Int, _ screen: NSScreen) {
        self.monitorAppKitNsScreenScreensId = monitorAppKitNsScreenScreensId
        self.name = screen.localizedName
        self.width = screen.frame.width // Don't call rect because it would cause recursion during mainMonitor init
        self.height = screen.frame.height // Don't call rect because it would cause recursion during mainMonitor init
        self.screen = screen
    }

    var rect: Rect {
        _rect ?? screen.rect.also { _rect = $0 }
    }

    var visibleRect: Rect {
        _visibleRect ?? screen.visibleRect.also { _visibleRect = $0 }
    }
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
private extension NSScreen {
    func toMonitor(monitorAppKitNsScreenScreensId: Int) -> Monitor {
        MonitorImpl(
            monitorAppKitNsScreenScreensId: monitorAppKitNsScreenScreensId,
            name: localizedName,
            rect: rect,
            visibleRect: visibleRect
        )
    }

    var isMainScreen: Bool {
        frame.minX == 0 && frame.minY == 0
    }

    /// The property is a replacement for Apple's crazy ``frame``
    ///
    /// - For ``MacWindow.topLeftCorner``, (0, 0) is main screen top left corner, and positive y-axis goes down.
    /// - For ``frame``, (0, 0) is main screen bottom left corner, and positive y-axis goes up (which is crazy).
    ///
    /// The property "normalizes" ``frame``
    var rect: Rect { frame.monitorFrameNormalized() }

    /// Same as ``rect`` but for ``visibleFrame``
    var visibleRect: Rect { visibleFrame.monitorFrameNormalized() }
}

private let testMonitorRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
private let testMonitor = MonitorImpl(
    monitorAppKitNsScreenScreensId: 1,
    name: "Test Monitor",
    rect: testMonitorRect,
    visibleRect: testMonitorRect
)

var mainMonitor: Monitor {
    if isUnitTest { return testMonitor }
    let elem = NSScreen.screens.withIndex.singleOrNil(where: \.value.isMainScreen)!
    return LazyMonitor(monitorAppKitNsScreenScreensId: elem.index + 1, elem.value)
}

var monitors: [Monitor] {
    if (isUnitTest) { return [testMonitor] }

    var result = NSScreen.screens.enumerated().map { $0.element.toMonitor(monitorAppKitNsScreenScreensId: $0.offset + 1) }
    var newResult: [Monitor] = []
    let myConfig: Config = store.get()
    dump(myConfig.virtualSplitOnTheseMonitors)
    for m in result {
        if myConfig.virtualSplitOnTheseMonitors.contains(m.name) { // m.name == "LEN P32p-20" {
            var r1 = m.rect;
            r1.width = r1.width / 2
            var vr1 = m.visibleRect
            vr1.width = vr1.width / 2
            var h1 = MonitorImpl(
                monitorAppKitNsScreenScreensId: m.monitorAppKitNsScreenScreensId,
                name: m.name + " H1",
                rect: r1,
                visibleRect: vr1
            )
            newResult.append(h1)

            var r2 = r1;
            r2.topLeftX = r2.topLeftX + r2.width
            var vr2 = vr1
            vr2.topLeftX = r2.topLeftX
            var h2 = MonitorImpl(
                monitorAppKitNsScreenScreensId: m.monitorAppKitNsScreenScreensId,
                name: m.name + " H2",
                rect: r2,
                visibleRect: vr2
            )
            newResult.append(h2)
        } else {
            newResult.append(m)
        }
    }
    
    return newResult
}

var sortedMonitors: [Monitor] {
    monitors.sortedBy([\.rect.minX, \.rect.minY])
}
