pragma Singleton
import QtQuick
import Qt.labs.settings

Item {
    id: root

    visible: false
    width: 0
    height: 0

    Settings {
        id: storage
        category: "launcher"

        property bool setupComplete: false
        property real uiScale: 1.0
        property bool animations: true
        property int idleMinutes: 5
        property string locale: "en_GB.UTF-8"
        property string timezone: "Europe/Warsaw"
        property bool privacyAccepted: false
        property bool updateNotifications: true
        property bool appPrerelease: false
        property string theme: "aurora"
        property string wallpaper: "aurora"
        property bool showRecent: true
        property bool showFavorites: true
        property bool showStreaming: true
        property bool showApps: true
        property string startScreen: "home"
        property bool clock24h: true
    }

    property alias setupComplete: storage.setupComplete
    property alias uiScale: storage.uiScale
    property alias animations: storage.animations
    property alias idleMinutes: storage.idleMinutes
    property alias locale: storage.locale
    property alias timezone: storage.timezone
    property alias privacyAccepted: storage.privacyAccepted
    property alias updateNotifications: storage.updateNotifications
    property alias appPrerelease: storage.appPrerelease
    property alias theme: storage.theme
    property alias wallpaper: storage.wallpaper
    property alias showRecent: storage.showRecent
    property alias showFavorites: storage.showFavorites
    property alias showStreaming: storage.showStreaming
    property alias showApps: storage.showApps
    property alias startScreen: storage.startScreen
    property alias clock24h: storage.clock24h
}
