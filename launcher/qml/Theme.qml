pragma Singleton
import QtQuick

QtObject {
    id: theme

    // Runtime-adjustable accessibility and appearance settings.
    property real scale: 1.0
    property bool animations: true
    property string mode: "aurora"      // aurora | midnight | warm
    property string wallpaper: "aurora" // aurora | nebula | graphite

    readonly property int anim: animations ? 170 : 0
    readonly property int animShort: animations ? 110 : 0

    readonly property bool warm: mode === "warm"
    readonly property bool midnight: mode === "midnight"

    readonly property color bg: midnight ? "#010206" : (warm ? "#100b08" : "#05070f")
    readonly property color bgDeep: midnight ? "#000104" : (warm ? "#080504" : "#02040a")
    readonly property color bgRaised: midnight ? "#080d18" : (warm ? "#1b120c" : "#0b1220")
    readonly property color surface: midnight ? "#0b1220" : (warm ? "#21160f" : "#101827")
    readonly property color surfaceHigh: midnight ? "#121d30" : (warm ? "#302016" : "#182235")
    readonly property color surfaceGlass: midnight ? "#17243a" : (warm ? "#3a261a" : "#1b2740")
    readonly property color text: warm ? "#fff7ed" : "#f6f8ff"
    readonly property color textDim: warm ? "#c9b6a5" : "#95a3bf"
    readonly property color textFaint: warm ? "#988472" : "#5f6d88"
    readonly property color accent: warm ? "#f7b267" : (midnight ? "#9ae6ff" : "#6ee7f9")
    readonly property color accentDim: warm ? "#70451f" : (midnight ? "#164b5a" : "#1d5f6d")
    readonly property color highlight: warm ? "#f4845f" : "#a78bfa"
    readonly property color good: "#34d399"
    readonly property color warn: "#fbbf24"
    readonly property color danger: "#f87171"

    readonly property color wallpaperTop: wallpaper === "graphite"
                                             ? "#1b2433"
                                             : (wallpaper === "nebula" ? "#160b2e" : bg)
    readonly property color wallpaperBottom: wallpaper === "graphite"
                                               ? "#05070a"
                                               : (wallpaper === "nebula" ? "#03050f" : bgDeep)
    readonly property color glowA: wallpaper === "graphite"
                                     ? Qt.rgba(0.42, 0.50, 0.64, 0.10)
                                     : (wallpaper === "nebula"
                                        ? Qt.rgba(0.65, 0.45, 1.0, 0.16)
                                        : Qt.rgba(0.43, 0.91, 0.98, 0.13))
    readonly property color glowB: wallpaper === "graphite"
                                     ? Qt.rgba(0.55, 0.62, 0.76, 0.07)
                                     : (wallpaper === "nebula"
                                        ? Qt.rgba(0.95, 0.38, 0.72, 0.12)
                                        : Qt.rgba(0.65, 0.55, 0.98, 0.11))

    readonly property string fontFamily: "Inter"
    readonly property int radius: s(16)
    readonly property int screenMargin: s(72)
    readonly property int headerHeight: s(92)

    function s(value) {
        return Math.round(value * scale)
    }
}
