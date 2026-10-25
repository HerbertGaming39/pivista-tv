import QtQuick

Item {
    id: appsScreen

    property string filter: "All"
    property var shown: []

    signal requestHeaderFocus()

    function categories() {
        return ["All"].concat(catalog.availableCategories())
    }

    function refresh() {
        const all = catalog.apps
        if (filter === "All") {
            shown = all
        } else if (filter === "Web") {
            shown = all.filter(function (app) { return app.kind === "web" })
        } else {
            shown = all.filter(function (app) { return app.category === filter })
        }
    }

    function focusFirst() {
        if (shown.length > 0) {
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

    Component.onCompleted: {
        refresh()
        Qt.callLater(focusFirst)
    }

    Connections {
        target: catalog
        function onChanged() { appsScreen.refresh() }
    }

    ListView {
        id: chips
        anchors.top: parent.top
        width: parent.width
        height: Theme.s(46)
        orientation: ListView.Horizontal
        spacing: Theme.s(10)
        model: appsScreen.categories()
        clip: true
        focus: false

        Keys.onDownPressed: {
            if (appsScreen.shown.length > 0) {
                grid.currentIndex = 0
                grid.forceActiveFocus()
            }
        }
        Keys.onUpPressed: appsScreen.requestHeaderFocus()
        Keys.onReturnPressed: if (currentItem) currentItem.activate()

        delegate: Rectangle {
            id: chip
            property bool isSelected: appsScreen.filter === modelData
            width: Math.max(Theme.s(64), chipText.implicitWidth + Theme.s(32))
            height: Theme.s(38)
            radius: height / 2
            color: isSelected ? Theme.accent : Theme.surface
            border.width: isSelected ? 0 : Theme.s(1)
            border.color: Qt.rgba(1, 1, 1, 0.08)

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
        anchors.top: chips.bottom
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
                chips.forceActiveFocus()
            }
        }
        Keys.onReturnPressed: if (currentItem) currentItem.activate()
        Keys.onEnterPressed: if (currentItem) currentItem.activate()
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_F && currentItem) {
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
        }
    }

    Text {
        id: hint
        anchors.bottom: parent.bottom
        width: parent.width
        text: shown.length === 0
              ? "No applications in this category."
              : "Enter opens · F adds to favourites · H hides from the home screen"
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(13)
    }
}
