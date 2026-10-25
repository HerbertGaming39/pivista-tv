import QtQuick

Item {
    id: search
    property string query: ""
    property var results: []

    signal requestHeaderFocus()

    function refresh() {
        const needle = query.trim().toLowerCase()
        const all = catalog.apps
        if (needle.length === 0) {
            results = all.slice(0, 12)
            return
        }
        results = all.filter(function (app) {
            return (app.name + " " + app.category + " " + app.comment).toLowerCase().indexOf(needle) >= 0
        })
    }

    function focusContent() {
        keyboard.focusKeyboard()
    }

    Component.onCompleted: {
        refresh()
        Qt.callLater(function () { keyboard.focusKeyboard() })
    }

    Connections {
        target: catalog
        function onChanged() { search.refresh() }
    }

    Text {
        id: title
        anchors.top: parent.top
        text: "Search"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(26)
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: queryBox
        anchors.top: title.bottom
        anchors.topMargin: Theme.s(12)
        width: parent.width
        height: Theme.s(54)
        radius: Theme.s(12)
        color: Theme.surface
        border.width: Theme.s(1)
        border.color: Theme.accentDim

        Text {
            anchors.fill: parent
            anchors.leftMargin: Theme.s(18)
            verticalAlignment: Text.AlignVCenter
            text: search.query.length > 0 ? search.query : "Type to search applications and shortcuts"
            color: search.query.length > 0 ? Theme.text : Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: Theme.s(18)
            elide: Text.ElideRight
        }
    }

    ListView {
        id: resultsList
        anchors.top: queryBox.bottom
        anchors.topMargin: Theme.s(14)
        anchors.bottom: keyboard.top
        anchors.bottomMargin: Theme.s(12)
        width: parent.width
        model: search.results
        clip: true
        focus: false
        spacing: Theme.s(8)

        Keys.onDownPressed: keyboard.focusKeyboard()
        Keys.onReturnPressed: if (currentItem) currentItem.activate()
        Keys.onEnterPressed: if (currentItem) currentItem.activate()

        delegate: Rectangle {
            width: resultsList.width
            height: Theme.s(64)
            radius: Theme.s(12)
            color: ListView.isCurrentItem ? Theme.surfaceHigh : Theme.surface

            function activate() {
                catalog.launch(modelData.id)
            }

            Rectangle {
                id: badge
                anchors.left: parent.left
                anchors.leftMargin: Theme.s(12)
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.s(40)
                height: Theme.s(40)
                radius: Theme.s(10)
                color: modelData.color ? modelData.color : Theme.surfaceHigh
                Text {
                    anchors.centerIn: parent
                    text: modelData.short ? modelData.short : "?"
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(16)
                    font.weight: Font.DemiBold
                }
            }

            Column {
                anchors.left: badge.right
                anchors.leftMargin: Theme.s(14)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s(2)
                Text {
                    text: modelData.name
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(17)
                    font.weight: Font.DemiBold
                }
                Text {
                    text: modelData.kind === "web" ? "Web shortcut" : "Application"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(12)
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: Theme.s(16)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.favorite ? "★" : ""
                color: Theme.accent
                font.pixelSize: Theme.s(20)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    resultsList.currentIndex = index
                    parent.activate()
                }
            }
        }
    }

    Text {
        visible: search.results.length === 0
        anchors.centerIn: resultsList
        text: "No matches"
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(18)
    }

    Keyboard {
        id: keyboard
        anchors.bottom: parent.bottom
        width: parent.width
        onTextChanged: {
            search.query = text
            search.refresh()
        }
        onCancelled: search.query = ""
        onAccepted: {
            if (search.results.length > 0)
                catalog.launch(search.results[0].id)
        }
        Keys.onUpPressed: {
            if (search.results.length > 0) {
                resultsList.currentIndex = 0
                resultsList.forceActiveFocus()
            }
        }
    }
}
