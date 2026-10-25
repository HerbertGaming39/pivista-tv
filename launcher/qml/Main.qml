import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Shapes

Window {
    id: window
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

    property string screen: initialScreen.length > 0 ? initialScreen : "home"
    property bool quickOpen: false
    property bool screensaverActive: false
    property double lastInput: Date.now()
    property string toastText: ""
    property bool online: false
    property string netLabel: "offline"
    property int statusRequest: -1
    property string clockText: Qt.formatTime(new Date(), "HH:mm")
    property string dateText: Qt.formatDateTime(new Date(), "ddd d MMM")
    property bool wizardVisible: !AppSettings.setupComplete && !uiDevMode

    readonly property var navItems: ["Home", "Apps", "Search", "Settings", "Quick"]

    Binding { target: Theme; property: "scale"; value: AppSettings.uiScale * window.designScale }
    Binding { target: Theme; property: "animations"; value: AppSettings.animations }

    function activeIndex() {
        if (window.screen === "home") return 0
        if (window.screen === "apps") return 1
        if (window.screen === "search") return 2
        if (window.screen === "settings") return 3
        return 0
    }

    function syncNav() {
        navList.currentIndex = activeIndex()
    }

    function activateNav(index) {
        if (index === 4) {
            openQuick()
            return
        }
        const names = ["home", "apps", "search", "settings"]
        if (window.screen !== names[index])
            window.screen = names[index]
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
        window.screen = "home"
        Qt.callLater(focusContent)
    }

    function openQuick() {
        quickOpen = true
        quickPanel.open()
    }

    function restoreAfterOverlay() {
        if (window.screen === "home")
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

    onScreenChanged: {
        syncNav()
        Qt.callLater(focusContent)
    }

    Component.onCompleted: {
        syncNav()
        loadStatus()
        if (wizardVisible)
            Qt.callLater(function () { wizard.forceActiveFocus() })
        else
            Qt.callLater(focusContent)
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
            window.clockText = Qt.formatTime(new Date(), "HH:mm")
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
            if (event.key === Qt.Key_Escape) {
                if (window.quickOpen) {
                    quickPanel.close()
                    event.accepted = true
                } else if (window.screen !== "home") {
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
                GradientStop { position: 0.0; color: "#081120" }
                GradientStop { position: 0.55; color: Theme.bg }
                GradientStop { position: 1.0; color: "#02040a" }
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
                    GradientStop { position: 0.0; color: Qt.rgba(0.43, 0.91, 0.98, 0.13) }
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
                    GradientStop { position: 0.0; color: Qt.rgba(0.65, 0.55, 0.98, 0.11) }
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
                anchors.left: brand.right
                anchors.leftMargin: Theme.s(46)
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.s(600)
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
            anchors.top: header.bottom
            anchors.topMargin: Theme.s(16)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Theme.screenMargin
            anchors.rightMargin: Theme.screenMargin
            anchors.bottomMargin: Theme.s(38)

            sourceComponent: window.screen === "home" ? homeScreen
                           : window.screen === "apps" ? appsScreen
                           : window.screen === "search" ? searchScreen
                           : window.screen === "settings" ? settingsScreen
                           : homeScreen

            onLoaded: {
                if (item.requestHeaderFocus)
                    item.requestHeaderFocus.connect(window.focusHeader)
                if (!window.wizardVisible)
                    Qt.callLater(window.focusContent)
            }
        }

        Component { id: homeScreen; HomeScreen {} }
        Component { id: appsScreen; AppsScreen {} }
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
            onCompleted: {
                window.screen = "home"
                window.showToast(wizard.setupWarning.length > 0
                                 ? "Setup complete · " + wizard.setupWarning
                                 : "Setup complete")
                Qt.callLater(window.focusContent)
            }
        }
    }
}
