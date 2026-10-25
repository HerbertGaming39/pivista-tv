pragma Singleton
import QtQuick

QtObject {
    id: theme

    // Runtime-adjustable accessibility settings.
    property real scale: 1.0
    property bool animations: true

    readonly property int anim: animations ? 170 : 0
    readonly property int animShort: animations ? 110 : 0

    readonly property color bg: "#05070f"
    readonly property color bgDeep: "#02040a"
    readonly property color bgRaised: "#0b1220"
    readonly property color surface: "#101827"
    readonly property color surfaceHigh: "#182235"
    readonly property color surfaceGlass: "#1b2740"
    readonly property color text: "#f6f8ff"
    readonly property color textDim: "#95a3bf"
    readonly property color textFaint: "#5f6d88"
    readonly property color accent: "#6ee7f9"
    readonly property color accentDim: "#1d5f6d"
    readonly property color highlight: "#a78bfa"
    readonly property color good: "#34d399"
    readonly property color warn: "#fbbf24"
    readonly property color danger: "#f87171"

    readonly property string fontFamily: "Inter"
    readonly property int radius: s(16)
    readonly property int screenMargin: s(72)
    readonly property int headerHeight: s(92)

    function s(value) {
        return Math.round(value * scale)
    }
}
