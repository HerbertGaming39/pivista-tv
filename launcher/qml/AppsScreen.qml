import QtQuick

Item {
    id: appsScreen
    objectName: "appsScreen"

    property string mode: "apps"          // apps | games
    property string filter: "All"
    property var shown: []
    property var detailApp: ({})

    signal requestHeaderFocus()

    readonly property bool gamesMode: mode === "games"
    readonly property string heading: gamesMode ? "Games" : "Applications"
    readonly property string subheading: gamesMode
                                          ? (shown.length === 1 ? "1 installed game" : shown.length + " installed games")
                                          : (catalog.nativeApps.length + " installed · " + catalog.streaming.length + " web shortcuts")

    function categories() {
        if (gamesMode)
            return ["Games"]
        const values = ["All", "Installed", "Web"]
        const extras = catalog.availableCategories()
        for (let i = 0; i < extras.length; ++i) {
            if (values.indexOf(extras[i]) === -1)
                values.push(extras[i])
        }
        return values
    }

    function refresh() {
        if (gamesMode) {
            shown = catalog.games
            return
        }
        if (filter === "All") {
            shown = catalog.apps
        } else if (filter === "Installed") {
            shown = catalog.nativeApps
        } else if (filter === "Web") {
            shown = catalog.streaming
        } else {
            shown = catalog.apps.filter(function (app) { return app.category === filter })
        }
    }

    function focusFirst() {
        if (gamesMode || shown.length > 0) {
            grid.currentIndex = 0
            grid.forceActiveFocus()
        } else {
            chips.currentIndex = 0
            chips.forceActiveFocus()
        }
    }

    function focusContent() {
        focusFirst()
    }

    function openDetails(app) {
        if (!app || !app.id)
            return
        detailApp = catalog.application(app.id)
        details.open(detailApp)
    }

    Component.onCompleted: {
        if (gamesMode)
            filter = "Games"
        refresh()
        Qt.callLater(focusFirst)
        if (initialDetails.length > 0) {
            Qt.callLater(function () {
                const app = catalog.application(initialDetails)
                if (app.id)
                    appsScreen.openDetails(app)
            })
        }
    }

    Connections {
        target: catalog
        function onChanged() {
            appsScreen.refresh()
            if (appsScreen.detailApp && appsScreen.detailApp.id)
                appsScreen.detailApp = catalog.application(appsScreen.detailApp.id)
        }
    }

    Text {
        id: title
        anchors.top: parent.top
        text: appsScreen.heading
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(30)
        font.weight: Font.Bold
    }

    Text {
        id: counts
        anchors.top: parent.top
        anchors.right: parent.right
        text: appsScreen.subheading
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(13)
        anchors.verticalCenter: title.verticalCenter
    }

    ListView {
        id: chips
        objectName: "categoryChips"
        anchors.top: title.bottom
        anchors.topMargin: Theme.s(16)
        width: parent.width
        height: Theme.s(46)
        orientation: ListView.Horizontal
        spacing: Theme.s(10)
        model: appsScreen.categories()
        clip: true
        focus: false
        visible: !appsScreen.gamesMode

        Keys.onDownPressed: {
            if (appsScreen.shown.length > 0) {
                grid.currentIndex = 0
                grid.forceActiveFocus()
            }
        }
        Keys.onUpPressed: appsScreen.requestHeaderFocus()
        Keys.onLeftPressed: if (currentIndex > 0) currentIndex--
        Keys.onRightPressed: if (currentIndex < count - 1) currentIndex++
        Keys.onReturnPressed: if (currentItem) currentItem.activate()
        Keys.onEnterPressed: if (currentItem) currentItem.activate()

        delegate: Rectangle {
            id: chip
            property bool isSelected: appsScreen.filter === modelData
            width: Math.max(Theme.s(64), chipText.implicitWidth + Theme.s(32))
            height: Theme.s(38)
            radius: height / 2
            color: isSelected ? Theme.accent : Theme.surface
            border.width: (chips.activeFocus && ListView.isCurrentItem) ? Theme.s(2)
                          : (isSelected ? 0 : Theme.s(1))
            border.color: (chips.activeFocus && ListView.isCurrentItem) ? Theme.text
                          : Qt.rgba(1, 1, 1, 0.08)

            Behavior on color {
                ColorAnimation { duration: Theme.animShort }
            }

            function activate() {
                appsScreen.filter = modelData
                appsScreen.refresh()
            }

            Text {
                id: chipText
                anchors.centerIn: parent
                text: modelData
                color: chip.isSelected ? Theme.bg : Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(14)
                font.weight: chip.isSelected ? Font.DemiBold : Font.Normal
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    chips.currentIndex = index
                    parent.activate()
                }
            }
        }
    }

    GridView {
        id: grid
        objectName: "appsGrid"
        anchors.top: appsScreen.gamesMode ? title.bottom : chips.bottom
        anchors.topMargin: Theme.s(22)
        anchors.bottom: hint.top
        width: parent.width
        cellWidth: Theme.s(240)
        cellHeight: Theme.s(182)
        model: appsScreen.shown
        clip: true
        focus: false
        keyNavigationWraps: false

        Keys.onUpPressed: {
            if (grid.currentIndex < Math.floor(grid.width / grid.cellWidth)) {
                if (appsScreen.gamesMode)
                    appsScreen.requestHeaderFocus()
                else
                    chips.forceActiveFocus()
            }
        }
        Keys.onReturnPressed: if (currentItem) currentItem.activate()
        Keys.onEnterPressed: if (currentItem) currentItem.activate()
        Keys.onPressed: function (event) {
            if ((event.key === Qt.Key_I || event.key === Qt.Key_Info) && currentItem) {
                appsScreen.openDetails(currentItem.app)
                event.accepted = true
            } else if (event.key === Qt.Key_F && currentItem) {
                catalog.toggleFavorite(currentItem.app.id)
                event.accepted = true
            } else if (event.key === Qt.Key_H && currentItem) {
                catalog.setHidden(currentItem.app.id, true)
                event.accepted = true
            }
        }

        delegate: Tile {
            app: modelData
            selected: GridView.isCurrentItem
            active: grid.activeFocus
            onActivated: catalog.launch(app.id)
            onDetailsRequested: {
                grid.currentIndex = index
                appsScreen.openDetails(app)
            }
        }
    }

    Text {
        id: empty
        anchors.centerIn: grid
        width: parent.width - Theme.s(80)
        visible: appsScreen.shown.length === 0
        text: appsScreen.gamesMode
              ? "No games installed yet.\n\nGames are ordinary Linux applications with a Game category. Install one with apt or a desktop package, then reopen this page."
              : "No applications in this category."
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(17)
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 1.3
    }

    Text {
        id: hint
        anchors.bottom: parent.bottom
        width: parent.width
        text: appsScreen.shown.length === 0
              ? "Settings → Applications can add a web shortcut."
              : "Enter opens · I details · F favourite · H hides"
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(13)
    }

    AppDetails {
        id: details
        app: appsScreen.detailApp
        running: catalog.externalAppActive
        onClosed: grid.forceActiveFocus()
        onLaunchRequested: catalog.launch(detailApp.id)
        onFavoriteToggled: {
            catalog.toggleFavorite(detailApp.id)
            detailApp = catalog.application(detailApp.id)
        }
        onHiddenChanged: function (hidden) {
            catalog.setHidden(detailApp.id, hidden)
            detailApp = catalog.application(detailApp.id)
            if (hidden)
                details.close()
        }
        onCloseRequested: catalog.closeExternalApp()
    }
}
