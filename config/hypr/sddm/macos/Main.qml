// macOS-style SDDM login window (Qt 6)
import QtQuick
import QtQuick.Effects

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "black"

    readonly property string fontFamily: "Inter"
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    readonly property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    readonly property Item user: users.count > userIndex ? users.itemAt(userIndex) : null
    readonly property Item session: sessions.count > sessionIndex ? sessions.itemAt(sessionIndex) : null
    property bool busy: false
    property bool failed: false
    // Wallpaper blurs once you start typing, like the macOS lock screen
    readonly property bool blurred: pw.text.length > 0 || busy

    function login() {
        if (!user || busy) return
        busy = true
        failed = false
        sddm.login(user.uName, pw.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.failed = true
            pw.text = ""
            pw.forceActiveFocus()
            shake.restart()
        }
    }

    // Role readers for the user and session models
    Item {
        visible: false
        Repeater {
            id: users
            model: userModel
            delegate: Item {
                property string uName: model.name
                property string uReal: model.realName
                property string uIcon: model.icon
            }
        }
        Repeater {
            id: sessions
            model: sessionModel
            delegate: Item { property string sName: model.name }
        }
    }

    // Background
    Image {
        id: bg
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    MultiEffect {
        anchors.fill: bg
        source: bg
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: root.blurred ? 1.0 : 0.0
        brightness: root.blurred ? -0.06 : 0.0
        Behavior on blur { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        Behavior on brightness { NumberAnimation { duration: 450 } }
    }
    // Soft shade at the top and bottom keeps the text legible on bright walls
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.22) }
            GradientStop { position: 0.3; color: "transparent" }
            GradientStop { position: 0.7; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.28) }
        }
    }

    // Any click refocuses the password field
    MouseArea {
        anchors.fill: parent
        onClicked: pw.forceActiveFocus()
    }

    // Top right status: session and keyboard layout
    Row {
        anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 16 }
        spacing: 18

        Text {
            text: root.session ? root.session.sName : ""
            color: "white"
            font { family: root.fontFamily; pixelSize: 13; weight: Font.Medium }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessions.count
            }
        }
        Text {
            visible: keyboard.layouts.length > 0
            text: visible ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase() : ""
            color: "white"
            font { family: root.fontFamily; pixelSize: 13; weight: Font.Medium }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
            }
        }
    }

    // Date and clock
    Column {
        id: clock
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: root.height * 0.075 }
        spacing: -root.height * 0.012
        property date now: new Date()

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clock.now = new Date()
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.now, "dddd d MMMM")
            color: Qt.rgba(1, 1, 1, 0.9)
            font { family: root.fontFamily; pixelSize: Math.round(root.height * 0.022); weight: Font.DemiBold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.now, "HH:mm")
            color: Qt.rgba(1, 1, 1, 0.88)
            font { family: "Inter Display"; pixelSize: Math.round(root.height * 0.115); weight: Font.DemiBold; letterSpacing: -2 }
        }
    }

    // User, password field
    Column {
        id: loginBox
        anchors.centerIn: parent
        spacing: 12

        Item {
            id: avatar
            anchors.horizontalCenter: parent.horizontalCenter
            width: 76
            height: 76
            readonly property string icon: root.user ? root.user.uIcon : ""
            // SDDM hands out its generic face when the user has none
            readonly property bool hasFace: icon !== "" && !icon.endsWith("/.face.icon") && face.status === Image.Ready

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                visible: !avatar.hasFace
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#a8adb7" }
                    GradientStop { position: 1.0; color: "#6f747e" }
                }
                Text {
                    anchors.centerIn: parent
                    text: {
                        const n = root.user ? (root.user.uReal || root.user.uName) : ""
                        return n.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                    }
                    color: "white"
                    font { family: root.fontFamily; pixelSize: 30; weight: Font.Medium }
                }
            }
            Image {
                id: face
                anchors.fill: parent
                source: avatar.icon === "" ? "" : (avatar.icon.startsWith("file:") ? avatar.icon : "file://" + avatar.icon)
                sourceSize: Qt.size(width * 2, height * 2)
                fillMode: Image.PreserveAspectCrop
                visible: false
            }
            Rectangle {
                id: faceMask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: true
            }
            MultiEffect {
                anchors.fill: parent
                source: face
                visible: avatar.hasFace
                maskEnabled: true
                maskSource: faceMask
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.user ? (root.user.uReal || root.user.uName) : ""
            color: "white"
            font { family: root.fontFamily; pixelSize: 16; weight: Font.DemiBold }
        }

        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 212
            height: 32
            radius: height / 2
            color: Qt.rgba(1, 1, 1, pw.activeFocus ? 0.22 : 0.16)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.22) }
            opacity: root.busy ? 0.6 : 1
            transform: Translate { id: shakeX }

            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeX; property: "x"; to: -14; duration: 50 }
                NumberAnimation { target: shakeX; property: "x"; to: 12; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: -9; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: 6; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: -3; duration: 60 }
                NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 50 }
            }

            TextInput {
                id: pw
                // Equal margins on both sides keep the dots centered in the pill
                anchors { left: parent.left; right: parent.right; leftMargin: 32; rightMargin: 32; verticalCenter: parent.verticalCenter }
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "●"
                passwordMaskDelay: 0
                color: "white"
                selectionColor: Qt.rgba(1, 1, 1, 0.3)
                font { family: root.fontFamily; pixelSize: 12; letterSpacing: 1 }
                clip: true
                focus: true
                enabled: !root.busy
                onTextChanged: if (text.length > 0) root.failed = false
                Keys.onReturnPressed: root.login()
                Keys.onEnterPressed: root.login()
                Keys.onEscapePressed: text = ""
            }
            Text {
                anchors.centerIn: parent
                visible: pw.text.length === 0
                text: "Enter Password"
                color: Qt.rgba(1, 1, 1, 0.6)
                font { family: root.fontFamily; pixelSize: 13 }
            }
            Image {
                id: caps
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 14
                height: 14
                source: "icons/capslock.svg"
                sourceSize: Qt.size(28, 28)
                opacity: 0.75
                visible: keyboard.capsLock
            }
            Rectangle {
                id: submit
                anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
                width: 22
                height: 22
                radius: 11
                color: Qt.rgba(1, 1, 1, submitArea.containsMouse ? 0.35 : 0.22)
                opacity: pw.text.length > 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Image {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    source: "icons/arrow.svg"
                    sourceSize: Qt.size(28, 28)
                }
                MouseArea {
                    id: submitArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: submit.opacity > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.login()
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.failed ? "Incorrect password" : (keyboard.capsLock ? "Caps Lock is on" : " ")
            color: Qt.rgba(1, 1, 1, 0.75)
            font { family: root.fontFamily; pixelSize: 12 }
        }
    }

    // Sleep / Restart / Shut Down
    Row {
        id: power
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: root.height * 0.045 }
        spacing: 16

        Repeater {
            model: [
                { label: "Sleep", icon: "icons/sleep.svg", ok: sddm.canSuspend, act: () => sddm.suspend() },
                { label: "Restart", icon: "icons/restart.svg", ok: sddm.canReboot, act: () => sddm.reboot() },
                { label: "Shut Down", icon: "icons/power.svg", ok: sddm.canPowerOff, act: () => sddm.powerOff() }
            ]
            // Fixed width so the circles sit evenly no matter the label length
            delegate: Column {
                visible: modelData.ok
                width: 80
                spacing: 7

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 40
                    height: 40
                    radius: 20
                    color: Qt.rgba(1, 1, 1, btn.pressed ? 0.4 : btn.containsMouse ? 0.3 : 0.18)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Image {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: modelData.icon
                        sourceSize: Qt.size(36, 36)
                    }
                    MouseArea {
                        id: btn
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modelData.act()
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label
                    color: Qt.rgba(1, 1, 1, 0.85)
                    font { family: root.fontFamily; pixelSize: 12; weight: Font.Medium }
                }
            }
        }
    }

    Component.onCompleted: pw.forceActiveFocus()
}
