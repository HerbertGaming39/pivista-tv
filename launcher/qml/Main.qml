import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Shapes

Window {
    id: window
    objectName: "pivistaWindow"
    visible: true
    width: initialWidth
    height: initialHeight
    minimumWidth: Math.round(initialWidth * 0.5)
    minimumHeight: Math.round(initialHeight * 0.5)
    visibility: windowedMode ? Window.Windowed : Window.FullScreen
    color: Theme.bg
    title: "PiVista TV"

    // The UI is authored at 1920x1080. Scale it to the actual surface so a
    // 720p television, a 4K panel and an offscreen test all keep their layout.
    readonly property real designScale: Math.max(0.5, Math.min(width / 1920, height / 1080))

    property string view: initialScreen.length > 0
                           ? initialScreen
                           : (AppSettings.startScreen === "apps" ? "apps" : "home")
    property bool quickOpen: false
    property bool screensaverActive: false
    property double lastInput: Date.now()
    property string toastText: ""
    property bool online: false
    property string netLabel: "offline"
    property int statusRequest: -1
    property int appUpdateRequest: -1
    property bool appUpdateNotified: false
    property string clockText: Qt.formatTime(new Date(), AppSettings.clock24h ? "HH:mm" : "h:mm AP")
    property string dateText: Qt.formatDateTime(new Date(), "ddd d MMM")
    property bool wizardVisible: !AppSettings.setupComplete && !uiDevMode

    readonly property var navItems: ["Home", "Apps", "Games", "Media", "Search", "Settings"]

    Binding { target: Theme; property: "scale"; value: AppSettings.uiScale * window.designScale }
    Binding { target: Theme; property: "animations"; value: AppSettings.animations }
    Binding { target: Theme; property: "mode"; value: AppSettings.theme }
    Binding { target: Theme; property: "wallpaper"; value: AppSettings.wallpaper }

    function activeIndex() {
        if (window.view === "home") return 0
        if (window.view === "apps") return 1
        if (window.view === "games") return 2
        if (window.view === "media") return 3
        if (window.view === "search") return 4
        if (window.view === "settings") return 5
        return 0
    }

    function syncNav() {
        navList.currentIndex = activeIndex()
    }

    function activateNav(index) {
        const names = ["home", "apps", "games", "media", "search", "settings"]
        if (!names[index])
            return
        if (window.view !== names[index])
            window.view = names[index]
        else
            focusContent()
    }

    function focusHeader() {
        navList.currentIndex = activeIndex()
        navList.forceActiveFocus()
    }

    function focusContent() {
        if (contentLoader.item && contentLoader.item.focusContent)
            contentLoader.item.focusContent()
        else if (contentLoader.item)
            contentLoader.item.forceActiveFocus()
    }

    function goHome() {
        window.view = "home"
        Qt.callLater(focusContent)
    }

    function openQuick() {
        quickOpen = true
        quickPanel.open()
    }

    function restoreAfterOverlay() {
        if (window.view === "home")
            focusContent()
        else
            focusHeader()
    }

    function resetIdle() {
        lastInput = Date.now()
        if (screensaverActive)
            screensaverActive = false
    }

    function checkIdle() {
        if (AppSettings.idleMinutes <= 0)
            return
        if (wizardVisible || quickOpen || catalog.externalAppActive)
            return
        if ((Date.now() - lastInput) > AppSettings.idleMinutes * 60000)
            screensaverActive = true
    }

    function showToast(message) {
        toastText = message
        toastTimer.restart()
    }

    function loadStatus() {
        statusRequest = control.call("network.status", {}, 15000)
    }

    // The launcher update check is read-only: it asks the privileged daemon
    // whether a signed release exists. It never downloads or installs without
    // a Settings action, so a playing video is never interrupted by this timer.
    function checkForAppUpdates() {
        appUpdateRequest = control.call("app.update.check",
                                         { allow_prerelease: AppSettings.appPrerelease }, 60000)
    }

    onViewChanged: {
        syncNav()
        Qt.callLater(focusContent)
    }

    // A cold boot can map the window before the compositor makes it active.
    // When activation finally arrives, put focus back on the visible wizard
    // or content instead of leaving keys directed at an unfocused surface.
    onActiveChanged: {
        if (!active)
            return
        if (wizardVisible)
            Qt.callLater(wizard.focusStep)
        else if (!quickOpen)
            Qt.callLater(focusContent)
    }

    Component.onCompleted: {
        syncNav()
        loadStatus()
        if (wizardVisible) {
            // Give the overlay active focus, then move it to the first visible
            // ActionList.  Calling forceActiveFocus() alone steals focus back
            // from WizardScreen's own queued focusStep(), leaving a plain Item
            // active that has no arrow/Enter handlers.
            Qt.callLater(function () {
                wizard.forceActiveFocus()
                wizard.focusStep()
            })
        } else {
            Qt.callLater(focusContent)
        }
    }

    Connections {
        target: control
        function onResponse(id, data) {
            if (id !== window.statusRequest)
                return
            window.online = data.connected === true
            window.netLabel = data.connection ? data.connection : (data.connected ? data.ip : "offline")
        }
        function onFailed(id, code, message) {
            if (id === window.statusRequest) {
                window.online = false
                window.netLabel = "service unavailable"
            }
        }
    }

    Connections {
        target: control
        function onResponse(id, data) {
            if (id !== window.appUpdateRequest)
                return
            window.appUpdateRequest = -1
            if (!data || data.available !== true || data.postponed === true)
                window.appUpdateNotified = false
            if (data && data.available === true && data.postponed !== true
                    && AppSettings.updateNotifications && !window.wizardVisible
                    && !window.screensaverActive && !catalog.externalAppActive
                    && !window.appUpdateNotified) {
                window.appUpdateNotified = true
                window.showToast("PiVista " + data.latest + " is available in Settings → Updates")
            }
        }
        function onFailed(id, code, message) {
            if (id === window.appUpdateRequest)
                window.appUpdateRequest = -1
        }
    }

    Connections {
        target: catalog
        function onLaunchFailed(message) { window.showToast(message) }
        function onExternalAppChanged() {
            if (!catalog.externalAppActive && !window.wizardVisible && !window.screensaverActive)
                Qt.callLater(window.focusContent)
        }
    }

    // The sway Home binding runs as the session user and wakes this socket.
    // Handling it here (rather than only in the compositor) resets the QML
    // screen and closes a native app even when Chromium never had the key.
    Connections {
        target: homeRelay
        function onHomeRequested() {
            if (window.wizardVisible)
                return
            window.screensaverActive = false
            window.lastInput = Date.now()
            if (window.quickOpen)
                quickPanel.close()
            catalog.closeExternalApp()
            window.goHome()
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            window.clockText = Qt.formatTime(new Date(), AppSettings.clock24h ? "HH:mm" : "h:mm AP")
            window.dateText = Qt.formatDateTime(new Date(), "ddd d MMM")
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: window.loadStatus()
    }

    Timer {
        id: appUpdateTimer
        interval: 60000
        repeat: false
        running: true
        onTriggered: {
            window.checkForAppUpdates()
            interval = 6 * 60 * 60 * 1000
            repeat = true
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: window.checkIdle()
    }

    Timer {
        id: toastTimer
        interval: 4500
        onTriggered: window.toastText = ""
    }


    Item {
        id: rootItem
        anchors.fill: parent
        focus: true

        Keys.onPressed: function (event) {
            window.resetIdle()
            if (window.wizardVisible) {
                event.accepted = false
                return
            }
            if (window.screensaverActive) {
                window.screensaverActive = false
                event.accepted = true
                Qt.callLater(window.focusContent)
                return
            }
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back
                    || event.key === Qt.Key_Backspace) {
                if (window.quickOpen) {
                    quickPanel.close()
                    event.accepted = true
                } else if (window.view !== "home") {
                    window.goHome()
                    event.accepted = true
                }
            } else if (event.key === Qt.Key_Home) {
                window.goHome()
                event.accepted = true
            } else if (event.key === Qt.Key_F10 || event.key === Qt.Key_Menu) {
                window.openQuick()
                event.accepted = true
            }
        }

        // Ambient background.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.wallpaperTop }
                GradientStop { position: 0.55; color: Theme.bg }
                GradientStop { position: 1.0; color: Theme.wallpaperBottom }
            }
        }

        Shape {
            width: Theme.s(1300)
            height: width
            x: -Theme.s(480)
            y: -Theme.s(620)
            ShapePath {
                strokeWidth: 0
                fillGradient: RadialGradient {
                    centerX: Theme.s(650)
                    centerY: Theme.s(650)
                    centerRadius: Theme.s(650)
                    focalX: Theme.s(650)
                    focalY: Theme.s(650)
                    GradientStop { position: 0.0; color: Theme.glowA }
                    GradientStop { position: 0.45; color: Qt.rgba(0.43, 0.91, 0.98, 0.05) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                startX: 0
                startY: 0
                PathLine { x: Theme.s(1300); y: 0 }
                PathLine { x: Theme.s(1300); y: Theme.s(1300) }
                PathLine { x: 0; y: Theme.s(1300) }
                PathLine { x: 0; y: 0 }
            }
        }

        Shape {
            width: Theme.s(1100)
            height: width
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -Theme.s(420)
            anchors.topMargin: -Theme.s(400)
            ShapePath {
                strokeWidth: 0
                fillGradient: RadialGradient {
                    centerX: Theme.s(550)
                    centerY: Theme.s(550)
                    centerRadius: Theme.s(550)
                    focalX: Theme.s(550)
                    focalY: Theme.s(550)
                    GradientStop { position: 0.0; color: Theme.glowB }
                    GradientStop { position: 0.5; color: Qt.rgba(0.65, 0.55, 0.98, 0.04) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                startX: 0
                startY: 0
                PathLine { x: Theme.s(1100); y: 0 }
                PathLine { x: Theme.s(1100); y: Theme.s(1100) }
                PathLine { x: 0; y: Theme.s(1100) }
                PathLine { x: 0; y: 0 }
            }
        }

        // Header
        Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Theme.headerHeight

            Row {
                id: brand
                anchors.left: parent.left
                anchors.leftMargin: Theme.screenMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s(4)

                Text {
                    text: "PiVista"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(26)
                    font.weight: Font.Bold
                }
                Text {
                    text: "TV"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(26)
                    font.weight: Font.Bold
                }
            }

            ListView {
                id: navList
                objectName: "navList"
                anchors.left: brand.right
                anchors.leftMargin: Theme.s(46)
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.s(760)
                height: Theme.s(54)
                orientation: ListView.Horizontal
                spacing: Theme.s(6)
                model: window.navItems
                clip: false
                focus: false
                keyNavigationWraps: false

                Keys.onReturnPressed: window.activateNav(navList.currentIndex)
                Keys.onEnterPressed: window.activateNav(navList.currentIndex)
                Keys.onDownPressed: window.focusContent()

                delegate: NavTab {
                    label: modelData
                    selected: index === window.activeIndex()
                    tabFocused: ListView.isCurrentItem && navList.activeFocus
                    onClicked: {
                        navList.currentIndex = index
                        window.activateNav(index)
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: Theme.screenMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s(18)

                Rectangle {
                    width: Theme.s(8)
                    height: width
                    radius: width / 2
                    color: window.online ? Theme.good : Theme.textFaint
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: window.netLabel
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(13)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.s(170)
                    elide: Text.ElideRight
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        anchors.right: parent.right
                        text: window.clockText
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(22)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.right: parent.right
                        text: window.dateText
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(11)
                    }
                }
            }
        }

        // Content
        Loader {
            id: contentLoader
            // The wizard is a full-screen overlay.  Do not load or focus the
            // home screen underneath it: its queued focus calls used to steal
            // focus from the wizard's ActionList a moment after activation,
            // which made every key look dead on the first boot.
            active: !window.wizardVisible
            anchors.top: header.bottom
            anchors.topMargin: Theme.s(16)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Theme.screenMargin
            anchors.rightMargin: Theme.screenMargin
            anchors.bottomMargin: Theme.s(38)

            sourceComponent: window.view === "home" ? homeScreen
                           : window.view === "apps" ? appsScreen
                           : window.view === "games" ? gamesScreen
                           : window.view === "media" ? mediaScreen
                           : window.view === "search" ? searchScreen
                           : window.view === "settings" ? settingsScreen
                           : homeScreen

            onLoaded: {
                if (item.requestHeaderFocus)
                    item.requestHeaderFocus.connect(window.focusHeader)
                if (!window.wizardVisible)
                    Qt.callLater(window.focusContent)
            }
        }

        Component { id: homeScreen; HomeScreen {} }
        Component { id: appsScreen; AppsScreen { mode: "apps" } }
        Component { id: gamesScreen; AppsScreen { mode: "games" } }
        Component { id: mediaScreen; MediaScreen {} }
        Component { id: searchScreen; SearchScreen {} }
        Component { id: settingsScreen; SettingsScreen {} }

        // Toast
        Rectangle {
            visible: window.toastText.length > 0
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.s(24)
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - Theme.s(144), toastLabel.implicitWidth + Theme.s(48))
            height: Theme.s(48)
            radius: Theme.s(12)
            color: "#241a0c"
            border.width: Theme.s(1)
            border.color: Theme.warn
            z: 60

            Text {
                id: toastLabel
                anchors.centerIn: parent
                width: parent.width - Theme.s(32)
                text: window.toastText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(14)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Screensaver {
            id: saver
            visible: window.screensaverActive
            onDismissed: {
                window.screensaverActive = false
                window.lastInput = Date.now()
                Qt.callLater(window.focusContent)
            }
        }

        QuickPanel {
            id: quickPanel
            onClosed: {
                window.quickOpen = false
                window.restoreAfterOverlay()
            }
        }

        WizardScreen {
            id: wizard
            objectName: "wizard"
            onCompleted: {
                window.view = "home"
                window.showToast(wizard.setupWarning.length > 0
                                 ? "Setup complete · " + wizard.setupWarning
                                 : "Setup complete")
                Qt.callLater(window.focusContent)
            }
        }
    }
}
