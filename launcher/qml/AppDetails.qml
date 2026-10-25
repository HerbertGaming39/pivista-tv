import QtQuick

FocusScope {
    id: details

    anchors.fill: parent
    visible: false
    z: 120

    property var app: ({})
    property bool running: false
    signal closed()
    signal launchRequested()
    signal favoriteToggled()
    signal hiddenChanged(bool hidden)
    signal closeRequested()

    function open(appData) {
        app = appData
        visible = true
        Qt.callLater(function () { actions.focusFirst() })
    }

    function close() {
        visible = false
        closed()
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.01, 0.02, 0.05, 0.86)

        MouseArea {
            anchors.fill: parent
            onClicked: details.close()
        }

        Rectangle {
            anchors.centerIn: parent
            width: Theme.s(940)
            height: Math.min(parent.height - Theme.s(60), Theme.s(620))
            radius: Theme.s(24)
            color: Theme.bgRaised
            border.width: Theme.s(1)
            border.color: Qt.rgba(1, 1, 1, 0.12)

            Column {
                anchors.fill: parent
                anchors.margins: Theme.s(30)
                spacing: Theme.s(14)

                Row {
                    width: parent.width
                    spacing: Theme.s(18)

                    Rectangle {
                        width: Theme.s(116)
                        height: width
                        radius: Theme.s(20)
                        color: details.app.color ? details.app.color : Theme.surfaceHigh

                        Text {
                            anchors.centerIn: parent
                            text: details.app.short ? details.app.short : "?"
                            color: "white"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.s(42)
                            font.weight: Font.Black
                        }
                    }

                    Column {
                        width: parent.width - Theme.s(150)
                        spacing: Theme.s(6)

                        Text {
                            width: parent.width
                            text: details.app.name ? details.app.name : ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.s(30)
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        Row {
                            spacing: Theme.s(12)
                            Text {
                                text: details.app.kind === "web" ? "WEB SHORTCUT" : "INSTALLED APPLICATION"
                                color: details.app.kind === "web" ? Theme.highlight : Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.s(11)
                                font.letterSpacing: Theme.s(1.2)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: details.app.category ? details.app.category : ""
                                color: Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.s(12)
                            }
                            Text {
                                visible: details.app.favorite === true
                                text: "★ favourite"
                                color: Theme.warn
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.s(12)
                            }
                        }

                        Text {
                            width: parent.width
                            text: details.app.notes
                                  ? details.app.notes
                                  : (details.app.comment ? details.app.comment : "")
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.s(14)
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Theme.s(1)
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                Text {
                    width: parent.width
                    text: details.app.kind === "web"
                          ? ("Address: " + (details.app.url || ""))
                          : ("Program: " + (details.app.program || "not available"))
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(12)
                    elide: Text.ElideMiddle
                }

                Text {
                    width: parent.width
                    text: "Compatibility: " + (details.app.compatibility || "unknown")
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(12)
                }

                Text {
                    width: parent.width
                    text: details.app.valid === false
                          ? ("Unavailable: " + (details.app.problem || "this entry cannot be launched"))
                          : (details.app.kind === "web"
                             ? "Opens in its own Chromium profile. Playback depends on the site and DRM support."
                             : "Runs as an unprivileged local application. Home closes it and returns here.")
                    color: details.app.valid === false ? Theme.danger : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(13)
                    wrapMode: Text.WordWrap
                }

                ActionList {
                    id: actions
                    width: parent.width
                    height: Math.min(Theme.s(330), implicitHeight)
                    actions: {
                        const list = [
                            { label: "Open application", detail: details.app.valid === false ? "unavailable" : "launch now" },
                            { label: details.app.favorite ? "Remove from favourites" : "Add to favourites", detail: "" },
                            { label: details.app.hidden ? "Show on home screen" : "Hide from home screen", detail: "" },
                            { label: "Back", detail: "" }
                        ]
                        if (details.running)
                            list.splice(3, 0, { label: "Close running application", detail: "returns Home" })
                        return list
                    }
                    onTriggered: function (index) {
                        const labels = actions.actions.map(function (item) { return item.label })
                        const label = labels[index]
                        if (label === "Open application") {
                            details.close()
                            details.launchRequested()
                        } else if (label === "Add to favourites" || label === "Remove from favourites") {
                            details.favoriteToggled()
                        } else if (label === "Show on home screen" || label === "Hide from home screen") {
                            details.hiddenChanged(!details.app.hidden)
                        } else if (label === "Close running application") {
                            details.closeRequested()
                            details.close()
                        } else {
                            details.close()
                        }
                    }
                }

                Text {
                    text: "Back closes this sheet"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(12)
                }
            }
        }
    }

    Keys.onEscapePressed: details.close()
}
