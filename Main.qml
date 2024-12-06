// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import QtQuick.Controls
import QtQuick.Dialogs
import Qt.labs.folderlistmodel
import QtQuick.Controls.Universal
import QtQuick.Layouts

import VolumetricExample
import "SpacingMap.mjs" as SpacingMap
import Qt.labs.qmlmodels

ApplicationWindow {
    id: window
    width: 1200
    height: 1080
    visible: true

    Universal.theme: Universal.Dark

    FileDialog {
        id: fileDialog
        onAccepted: {
            loadFile(selectedFile)
        }
    }

    function clamp(number, min, max) {
        return Math.max(min, Math.min(number, max))
    }

    function loadFile(selectedFile) {
        var width = parseInt(dataWidth.text)
        var height = parseInt(dataHeight.text)
        var depth = parseInt(dataDepth.text)
        var dataSize = dataTypeComboBox.currentText

        // Parses file names of the form:
        // boston_teapot_256x256x178_uint8.raw
        const re = new RegExp(".?([0-9]+)x([0-9]+)x([0-9]+)_([a-zA-Z0-9]+)\.raw")
        let matches = re.exec(String(selectedFile))
        if (matches && matches.length === 5) {
            width = parseInt(matches[1])
            height = parseInt(matches[2])
            depth = parseInt(matches[3])
            dataSize = matches[4]
        }

        let dimensions = Qt.vector3d(width, height, depth).normalized()
        var spacing = SpacingMap.get(String(selectedFile)).times(dimensions)
        let maxSide = Math.max(Math.max(spacing.x, spacing.y), spacing.z)
        spacing = spacing.times(1 / maxSide)

        volumeTextureData.loadAsync(selectedFile, width, height,
                                    depth, dataSize)
        spinner.running = true
    }

    function getColormapSource(currentIndex) {
        switch (currentIndex) {
        case 0:
            return "images/colormap-blackwhite.png"
        case 1:
            return "images/colormap-coolwarm.png"
        case 2:
            return "images/colormap-plasma.png"
        case 3:
            return "images/colormap-viridis.png"
        case 4:
            return "images/colormap-rainbow.png"
        case 5:
            return "images/colormap-gnuplot.png"
        default:
            break
        }
        return ""
    }

    // position and width are normalized [0..1]
    function sliceSliderMin(posX, widthX, posY, widthY, posZ, widthZ) {
        let x = clamp(posX - 0.5 * widthX, 0, 1 - widthX)
        let y = clamp(posY - 0.5 * widthY, 0, 1 - widthY)
        let z = clamp(posZ - 0.5 * widthZ, 0, 1 - widthZ)
        return Qt.vector3d(x, y, z)
    }

    // position and width are normalized [0..1]
    function sliceSliderMax(posX, widthX, posY, widthY, posZ, widthZ) {
        let x = clamp(posX + 0.5 * widthX, widthX, 1)
        let y = clamp(posY + 0.5 * widthY, widthY, 1)
        let z = clamp(posZ + 0.5 * widthZ, widthZ, 1)
        return Qt.vector3d(x, y, z)
    }

    function sliceBoxPosition(x, y, z, xWidth, yWidth, zWidth) {
        let min = sliceSliderMin(x, xWidth, y, yWidth, z, zWidth)
        let max = sliceSliderMax(x, xWidth, y, yWidth, z, zWidth)
        let xMid = (min.x + max.x) * 0.5 - 0.5
        let yMid = (min.y + max.y) * 0.5 - 0.5
        let zMid = (min.z + max.z) * 0.5 - 0.5
        return Qt.vector3d(xMid, yMid, zMid).times(100)
    }

    Connections {
        target: volumeTextureData
        function onLoadSucceeded(source, width, height, depth, dataType, localFocusPoint, globalFocusPoint) {
            var spacing = SpacingMap.get(String(source)).times(
                        Qt.vector3d(width, height, depth).normalized())
            let maxSide = Math.max(Math.max(spacing.x, spacing.y), spacing.z)
            spacing = spacing.times(1 / maxSide)

            switch (dataType) {
            case 'uint8':
                dataTypeComboBox.currentIndex = 0
                break
            case 'uint16':
                dataTypeComboBox.currentIndex = 1
                break
            case 'int16':
                dataTypeComboBox.currentIndex = 2
                break
            case 'float32':
                dataTypeComboBox.currentIndex = 3
                break
            case 'float64':
                dataTypeComboBox.currentIndex = 4
                break
            }

            dataWidth.text = width
            dataHeight.text = height
            dataDepth.text = depth
            scaleWidth.text = parseFloat(spacing.x.toFixed(4))
            scaleHeight.text = parseFloat(spacing.y.toFixed(4))
            scaleDepth.text = parseFloat(spacing.z.toFixed(4))
            stepLengthText.text = parseFloat((1 / cubeModel.maxSide).toFixed(6))
            volumeTextureData.source = source
            spinner.running = false

            cursorModel.setPosition(localFocusPoint)
            zPlaneModel.setPosition(localFocusPoint)
            xPlaneModel.setPosition(localFocusPoint)
            yPlaneModel.setPosition(localFocusPoint)

            infoLabel.setPosition(localFocusPoint, globalFocusPoint)
        }
        function onLoadFailed(source, width, height, depth, dataType) {
            spinner.running = false
        }
    }

    View3D {
        id: view

        // Shrink boundaries to not interfere with mouse events.
        x: Math.max(iconOpenSettings.x + iconOpenSettings.width, iconOpenVolumes.x + iconOpenVolumes.width)
        width: parent.width - x - originGizmo.width
        height: parent.height

        camera: cameraNode

        PerspectiveCamera {
            id: cameraNode
            z: 300
        }

        //! [cube]
        Model {
            id: cubeModel
            source: "#Cube"
            visible: true
            materials: CustomMaterial {
                shadingMode: CustomMaterial.Unshaded
                vertexShader: "shaders/alpha_blending.vert"
                fragmentShader: "shaders/alpha_blending.frag"

                //! [volume-texture]
                property TextureInput volume: TextureInput {
                    texture: Texture {
                        textureData: VolumeTextureData {
                            id: volumeTextureData
                            source: "file:///default_colormap"
                            dataType: dataTypeComboBox.currentText ? dataTypeComboBox.currentText : "uint8"
                            width: parseInt(dataWidth.text)
                            height: parseInt(dataHeight.text)
                            depth: parseInt(dataDepth.text)
                        }
                        minFilter: Texture.Nearest
                        mipFilter: Texture.None
                        magFilter: Texture.Nearest
                        tilingModeHorizontal: Texture.ClampToEdge
                        tilingModeVertical: Texture.ClampToEdge
                        //tilingModeDepth: Texture.ClampToEdge // Qt 6.7
                    }
                }
                //! [volume-texture]

                property TextureInput colormap: TextureInput {
                    enabled: true
                    texture: Texture {
                        id: colormapTexture
                        tilingModeHorizontal: Texture.ClampToEdge
                        source: getColormapSource(colormapCombo.currentIndex)
                    }
                }
                property real stepLength: Math.max(0.0001, parseFloat(
                                                       stepLengthText.text,
                                                       1 / cubeModel.maxSide))
                property real minSide: 1 / cubeModel.minSide
                property real stepAlpha: stepAlphaSlider.value
                property bool multipliedAlpha: multipliedAlphaBox.checked

                property real tMin: tSlider.first.value
                property real tMax: tSlider.second.value
                property vector3d sliceMin: sliceSliderMin(
                                                xSliceSlider.value,
                                                xSliceWidthSlider.value,
                                                ySliceSlider.value,
                                                ySliceWidthSlider.value,
                                                zSliceSlider.value,
                                                zSliceWidthSlider.value)
                property vector3d sliceMax: sliceSliderMax(
                                                xSliceSlider.value,
                                                xSliceWidthSlider.value,
                                                ySliceSlider.value,
                                                ySliceWidthSlider.value,
                                                zSliceSlider.value,
                                                zSliceWidthSlider.value)

                sourceBlend: CustomMaterial.SrcAlpha
                destinationBlend: CustomMaterial.OneMinusSrcAlpha
            }
            property real maxSide: Math.max(parseInt(dataWidth.text),
                                            parseInt(dataHeight.text),
                                            parseInt(dataDepth.text))
            property real minSide: Math.min(parseInt(dataWidth.text),
                                            parseInt(dataHeight.text),
                                            parseInt(dataDepth.text))
            scale: Qt.vector3d(parseFloat(scaleWidth.text),
                               parseFloat(scaleHeight.text),
                               parseFloat(scaleDepth.text))

            //! [bounding-boxes]
            Model {
                visible: drawBoundingBox.checked
                geometry: LineBoxGeometry {
                    size: 50
                }
                materials: PrincipledMaterial {
                    baseColor: "#323232"
                    lighting: PrincipledMaterial.NoLighting
                }
                receivesShadows: false
                castsShadows: false
            }

            Model {
                visible: drawBoundingBox.checked
                geometry: LineBoxGeometry {
                    size: 50
                }
                materials: PrincipledMaterial {
                    baseColor: "#323232"
                    lighting: PrincipledMaterial.NoLighting
                }
                receivesShadows: false
                castsShadows: false
                position: sliceBoxPosition(xSliceSlider.value,
                                           ySliceSlider.value,
                                           zSliceSlider.value,
                                           xSliceWidthSlider.value,
                                           ySliceWidthSlider.value,
                                           zSliceWidthSlider.value)
                scale: Qt.vector3d(xSliceWidthSlider.value,
                                   ySliceWidthSlider.value,
                                   zSliceWidthSlider.value)
            }
            //! [bounding-boxes]

            Model {
                id: zPlaneModel
                scale: Qt.vector3d(50, 50, 50)
                geometry: GridGeometry {
                    horizontalLines: 20
                    verticalLines: 20
                }
                visible: isVisible()
                pickable: isVisible()
                materials: PrincipledMaterial {
                    baseColor: "#268bd2"
                    lighting: PrincipledMaterial.NoLighting
                    cullMode: Material.NoCulling
                }
                receivesShadows: false
                castsShadows: false
                property string displayName: "zPlane"

                function setPosition(point) {
                    x = 0
                    y = 0
                    z = point.z
                }

                function isVisible() {
                    if (!drawXYZGrid.checked) {
                        return false
                    }
                    var rot0 = originGizmo.quaternionForAxis(OriginGizmo.Axis.PositiveZ, cubeModel.rotation)
                    var rot1 = originGizmo.quaternionForAxis(OriginGizmo.Axis.NegativeZ, cubeModel.rotation)
                    return cubeModel.rotation.fuzzyEquals(rot0) || cubeModel.rotation.fuzzyEquals(rot1)
                }
            }

            Model {
                id: yPlaneModel
                scale: Qt.vector3d(50, 50, 50)
                geometry: GridGeometry {
                    horizontalLines: 20
                    verticalLines: 20
                }
                visible: isVisible()
                pickable: isVisible()
                materials: PrincipledMaterial {
                    baseColor: "#859900"
                    lighting: PrincipledMaterial.NoLighting
                    cullMode: Material.NoCulling
                }
                receivesShadows: false
                castsShadows: false
                eulerRotation: Qt.vector3d(90, 0, 0)
                property string displayName: "yPlane"

                function setPosition(point) {
                    x = 0
                    y = point.y
                    z = 0
                }

                function isVisible() {
                    if (!drawXYZGrid.checked) {
                        return false
                    }
                    var rot0 = originGizmo.quaternionForAxis(OriginGizmo.Axis.PositiveY, cubeModel.rotation)
                    var rot1 = originGizmo.quaternionForAxis(OriginGizmo.Axis.NegativeY, cubeModel.rotation)
                    return cubeModel.rotation.fuzzyEquals(rot0) || cubeModel.rotation.fuzzyEquals(rot1)
                }
            }

            Model {
                id: xPlaneModel
                scale: Qt.vector3d(50, 50, 50)
                geometry: GridGeometry {
                    horizontalLines: 20
                    verticalLines: 20
                }
                visible: isVisible()
                pickable: isVisible()
                materials: PrincipledMaterial {
                    baseColor: "#dc322f"
                    lighting: PrincipledMaterial.NoLighting
                    cullMode: Material.NoCulling
                }
                receivesShadows: false
                castsShadows: false
                eulerRotation: Qt.vector3d(0, 90, 0)
                property string displayName: "xPlane"

                function setPosition(point) {
                    x = point.x
                    y = 0
                    z = 0
                }

                function isVisible() {
                    if (!drawXYZGrid.checked) {
                        return false
                    }
                    var rot0 = originGizmo.quaternionForAxis(OriginGizmo.Axis.PositiveX, cubeModel.rotation)
                    var rot1 = originGizmo.quaternionForAxis(OriginGizmo.Axis.NegativeX, cubeModel.rotation)
                    return cubeModel.rotation.fuzzyEquals(rot0) || cubeModel.rotation.fuzzyEquals(rot1)
                }
            }

            Model {
                id: cursorModel
                visible: drawCursor.checked
                property vector3d centroid: Qt.vector3d(0,0,0)
                geometry: LineCrossGeometry {
                    size: 100.0
                }
                materials: PrincipledMaterial {
                    baseColor: "#9400d3"
                    lighting: PrincipledMaterial.NoLighting
                }
                receivesShadows: false
                castsShadows: false

                function setPosition(point) {
                    centroid = point
                    geometry.center = point
                }
            }

            InstanceList {
                id: boxInstancing
                instances: []
            }
            Model {
                id: box
                instancing: boxInstancing
                geometry: LineBoxGeometry {}
                materials: PrincipledMaterial { 
                    baseColor: "cyan" 
                    lighting: PrincipledMaterial.NoLighting
                }
                pickable: true
            }
        }
        //! [cube]

        //! [arcball]
        ArcballController {
            id: arcballController
            controlledObject: cubeModel

            function jumpToAxis(axis) {
                cameraRotation.from = arcballController.controlledObject.rotation
                cameraRotation.to = originGizmo.quaternionForAxis(
                            axis, arcballController.controlledObject.rotation)
                cameraRotation.duration = 200
                cameraRotation.start()
            }

            function jumpToRotation(qRotation) {
                cameraRotation.from = arcballController.controlledObject.rotation
                cameraRotation.to = qRotation
                cameraRotation.duration = 100
                cameraRotation.start()
            }

            QuaternionAnimation {
                id: cameraRotation
                target: arcballController.controlledObject
                property: "rotation"
                type: QuaternionAnimation.Slerp
                running: false
                loops: 1
            }
        }

        DragHandler {
            id: dragHandler
            target: null
            acceptedModifiers: Qt.NoModifier
            onCentroidChanged: {
                arcballController.mouseMoved(toNDC(centroid.position.x,
                                                   centroid.position.y))
            }

            onActiveChanged: {
                if (active) {
                    view.forceActiveFocus()
                    arcballController.mousePressed(toNDC(centroid.position.x,
                                                         centroid.position.y))
                } else
                    arcballController.mouseReleased(toNDC(centroid.position.x,
                                                          centroid.position.y))
            }

            function toNDC(x, y) {
                return Qt.vector2d((2.0 * x / width) - 1.0,
                                   1.0 - (2.0 * y / height))
            }
        }

        WheelHandler {
            id: wheelHandler
            orientation: Qt.Vertical
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                         let delta = -event.angleDelta.y * 0.01
                         cameraNode.z += cameraNode.z * 0.1 * delta
                     }
        }
        //! [arcball]

        FrameAnimation {
            running: autoRotateCheckbox.checked
            onTriggered: {
                arcballController.mousePressed(Qt.vector2d(0, 0))
                arcballController.mouseMoved(Qt.vector2d(0.01, 0))
                arcballController.mouseReleased(Qt.vector2d(0.01, 0))
            }
        }

        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Space) {
                                let rotation = originGizmo.quaternionAlign(
                                    arcballController.controlledObject.rotation)
                                arcballController.jumpToRotation(rotation)
                            } else if (event.key === Qt.Key_S) {
                                settingsPane.toggleHide()
                            } else if (event.key === Qt.Key_V) {
                                volumesPane.toggleHide()
                            } else if (event.key === Qt.Key_M) {
                                measurementPane.toggleHide()
                            } else if (event.key === Qt.Key_Left
                                       || event.key === Qt.Key_A) {
                                let rotation = originGizmo.quaternionRotateLeft(
                                    arcballController.controlledObject.rotation)
                                arcballController.jumpToRotation(rotation)
                            } else if (event.key === Qt.Key_Right
                                       || event.key === Qt.Key_D) {
                                let rotation = originGizmo.quaternionRotateRight(
                                    arcballController.controlledObject.rotation)
                                arcballController.jumpToRotation(rotation)
                            }
                        }
    }

    //! [origingizmo]
    OriginGizmo {
        id: originGizmo
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        width: 120
        height: 120
        targetNode: cubeModel

        onAxisClicked: axis => {
                           arcballController.jumpToAxis(axis)
                       }
    }
    //! [origingizmo]

    RoundButton {
        id: iconOpenVolumes
        text: "\u222D" // Unicode Character 'TRIPPLE INTEGRAL', no qsTr()
        x: Math.max(Math.max(settingsPane.x + settingsPane.width + 10, volumesPane.x + volumesPane.width + 10), measurementPane.x + measurementPane.width + 10)
        y: 10
        onClicked: volumesPane.toggleHide()
        
        ToolTip.delay: 1000
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Volumes Menu.")
    }
    
    RoundButton {
        id: iconOpenMeasurement
        text: "\u22BE" // Unicode Character 'RIGTH ANGLE WITH ARC', no qsTr()
        x: Math.max(Math.max(settingsPane.x + settingsPane.width + 10, volumesPane.x + volumesPane.width + 10), measurementPane.x + measurementPane.width + 10)
        y: iconOpenVolumes.y + iconOpenVolumes.height + 10
        onClicked: measurementPane.toggleHide()

        ToolTip.delay: 1000
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Measurement Menu.")
    }

    RoundButton {
        id: iconOpenSettings
        text: "\u2699" // Unicode Character 'GEAR', no qsTr()
        x: Math.max(Math.max(settingsPane.x + settingsPane.width + 10, volumesPane.x + volumesPane.width + 10), measurementPane.x + measurementPane.width + 10)
        y: iconOpenMeasurement.y + iconOpenMeasurement.height + 10
        onClicked: settingsPane.toggleHide()
        
        ToolTip.delay: 1000
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Settings Menu.")
    }
   
    Spinner {
        id: spinner
        running: false
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 10
    }

    Label {
        id: infoLabel
        text: qsTr("Cursor: 0, 0, 0 (<font color='#268bd2'>Z</font>, <font color='#859900'>Y</font>, <font color='#dc322f'>X</font>)")
        anchors.horizontalCenter: parent.horizontalCenter 
        anchors.bottom: parent.bottom
        anchors.margins: 10

        function setPosition(localPoint, globalPoint) {
            text = qsTr("Focus Point (<font color='#9400d3'>\u2297</font>): %1, %2, %3 (<font color='#268bd2'>Z</font>, <font color='#859900'>Y</font>, <font color='#dc322f'>X</font>)").arg(globalPoint.z).arg(globalPoint.y).arg(globalPoint.x)
        }
    }

    ScrollView {
        id: volumesPane
        height: parent.height
        property bool hidden: true
        x: -volumesPane.width

        function toggleHide() {
            if (volumesPane.hidden) {
                volumesPaneAnimation.from = volumesPane.x
                volumesPaneAnimation.to = 0

                if (!settingsPane.hidden) {
                    settingsPane.toggleHide()
                }
                if (!measurementPane.hidden) {
                    measurementPane.toggleHide()
                }
            } else {
                volumesPaneAnimation.from = volumesPane.x
                volumesPaneAnimation.to = -volumesPane.width
            }
            volumesPane.hidden = !volumesPane.hidden
            volumesPaneAnimation.running = true
        }

        NumberAnimation on x {
            id: volumesPaneAnimation
            running: false
            from: width
            to: width
            duration: 100
        }

        Column {
            topPadding: 10
            bottomPadding: 10
            leftPadding: 20
            rightPadding: 20

            spacing: 10

            Label {
                text: qsTr("Focus point (<font color='#268bd2'>Z</font>, <font color='#859900'>Y</font>, <font color='#dc322f'>X</font>):")
            }

            Row {
                spacing: 5
                TextField {
                    id: pointZ
                    text: "10835"
                    validator: IntValidator {
                        bottom: 0
                        top: 999999
                    }
                }
                TextField {
                    id: pointY
                    text: "2602"
                    validator: IntValidator {
                        bottom: 0
                        top: 999999
                    }
                }
                TextField {
                    id: pointX
                    text: "2712"
                    validator: IntValidator {
                        bottom: 0
                        top: 999999
                    }
                }
            }

            Label {
                text: qsTr("Load Zarr Volume:")
            }

            ComboBox {
                id: scrollCombo
                model: [qsTr("Scroll1A"), qsTr("Scroll5"), qsTr("Scroll1A - Fiber"), qsTr("Scroll1A - Ink"), qsTr("Scroll1A - Boundary")]
            }

            Button {
                text: qsTr("Load Volume...")
                onClicked: {
                        var url = ""
                        var chunkSize = -1 // Read from Zarr metadata.
                        var dataType = "" // Read from Zarr metadata.
                        var level = -1 // unused.
                        var order = "C"
                        if (scrollCombo.currentText == "Scroll1A") {
                            url = "https://dl.ash2txt.org/full-scrolls/Scroll1/PHercParis4.volpkg/volumes_zarr_standardized/54keV_7.91um_Scroll1A.zarr"
                            level = 0
                        } else if (scrollCombo.currentText == "Scroll5") {
                            url = "https://dl.ash2txt.org/full-scrolls/Scroll5/PHerc172.volpkg/volumes_zarr_standardized/53keV_7.91um_Scroll5.zarr/"
                            level = 0
                        } else if (scrollCombo.currentText == "Scroll1A - Fiber") {
                            url = "https://dl.ash2txt.org/community-uploads/bruniss/Fiber-and-Surface-Models/Predictions/s1/mask-2ext-surface_erode_evenmore_ome.zarr/"
                            level = 0
                        } else if (scrollCombo.currentText == "Scroll1A - Boundary") {
                            url = "https://dl.ash2txt.org/other/dev/meshes/boundaries.zarr/"
                        } else if (scrollCombo.currentText == "Scroll1A - Ink") {
                            url = "https://dl.ash2txt.org/community-uploads/ryan/3d_predictions_scroll1.zarr/"
                            order = "yxz"
                        }
                        var point = Qt.vector3d(parseInt(pointX.text), parseInt(pointY.text), parseInt(pointZ.text))
                        volumeTextureData.loadAsync(url, chunkSize, chunkSize, chunkSize, dataType, point, level, order)
                        spinner.running = true
                }
            }

            Label {
                text: qsTr("Load Built-in Volume:")
            }

            Row {
                spacing: 5

                Button {
                    text: qsTr("Helix")
                    onClicked: {
                        volumeTextureData.loadAsync("file:///default_helix",
                                                    256, 256, 256, "uint8")
                        spinner.running = true
                    }
                }

                Button {
                    text: qsTr("Box")
                    onClicked: {
                        volumeTextureData.loadAsync("file:///default_box", 256,
                                                    256, 256, "uint8")
                        spinner.running = true
                    }
                }

                Button {
                    text: qsTr("Colormap")
                    onClicked: {
                        volumeTextureData.loadAsync("file:///default_colormap",
                                                    256, 256, 256, "uint8")
                        spinner.running = true
                    }
                }
            }

            Label {
                text: qsTr("Load On-disk Volume:")
            }

            Button {
                text: qsTr("Open file...")
                onClicked: fileDialog.open()
            }
        }
    }

    ScrollView {
        id: measurementPane
        height: parent.height
        property bool hidden: true
        x: -measurementPane.width

        function toggleHide() {
            if (measurementPane.hidden) {
                measurementPaneAnimation.from = measurementPane.x
                measurementPaneAnimation.to = 0

                if (!settingsPane.hidden) {
                    settingsPane.toggleHide()
                }
                if (!volumesPane.hidden) {
                    volumesPane.toggleHide()
                }
            } else {
                measurementPaneAnimation.from = measurementPane.x
                measurementPaneAnimation.to = -measurementPane.width
            }
            measurementPane.hidden = !measurementPane.hidden
            measurementPaneAnimation.running = true
        }

        NumberAnimation on x {
            id: measurementPaneAnimation
            running: false
            from: width
            to: width
            duration: 100
        }

        Column {
            topPadding: 10
            bottomPadding: 10
            leftPadding: 20
            rightPadding: 20

            spacing: 10

            Label {
                text: qsTr("Select a mode:")
            }

            RowLayout {
                RadioButton {
                    id: measureModeSelect
                    checked: true
                    text: qsTr("Select")
                }
                RadioButton {
                    id: measureModeAdd
                    text: qsTr("Add")
                }
                RadioButton {
                    id: measureModeRemove
                    text: qsTr("Remove")
                }
            }

            HorizontalHeaderView {
                id: horizontalHeader
                syncView: tableView
                width: 500
                height: 30
                model: [qsTr("x"), qsTr("y"), qsTr("z"), qsTr("sx"), qsTr("sy"), qsTr("sz"), qsTr("rx"), qsTr("ry"), qsTr("rz")]
                clip: true
            }

            TableView {
                id: tableView
                width: 500
                height: window.height
                columnSpacing: 1
                rowSpacing: 1
                clip: true

                model: TableModel {
                    id: boxTable

                    TableModelColumn { display: "positionX" }
                    TableModelColumn { display: "positionY" }
                    TableModelColumn { display: "positionZ" }
                    TableModelColumn { display: "scaleX" }
                    TableModelColumn { display: "scaleY" }
                    TableModelColumn { display: "scaleZ" }
                    TableModelColumn { display: "rotationX" }
                    TableModelColumn { display: "rotationY" }
                    TableModelColumn { display: "rotationZ" }

                    rows: []
                }

                selectionModel: ItemSelectionModel {}

                delegate: Rectangle {
                    implicitWidth: 80
                    implicitHeight: 30

                    color: Universal.background

                    Text {
                        anchors.fill: parent
                        text: display
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Universal.foreground
                    }

                    TableView.editDelegate: TextField {
                        anchors.fill: parent
                        text: display
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        Component.onCompleted: selectAll()

                        TableView.onCommit: {
                            display = text
                            var instance = boxTable.getRow(row).instance
                            if (column == 0) { // position
                                instance.position.x = parseFloat(text)
                            } else if (column == 1) {
                                instance.position.y = parseFloat(text)
                            } else if (column == 2) {
                                instance.position.z = parseFloat(text)
                            } else if (column == 3) {
                                instance.scale.x = parseFloat(text)
                            } else if (column == 4) {
                                instance.scale.y = parseFloat(text)
                            } else if (column == 5) {
                                instance.scale.z = parseFloat(text)
                            } else if (column == 6) {
                                instance.eulerRotation.x = parseFloat(text)
                            } else if (column == 7) {
                                instance.eulerRotation.y = parseFloat(text)
                            } else if (column == 8) {
                                instance.eulerRotation.z = parseFloat(text)
                            }
                        }
                    }
                }
            }
        }
    }

    //! [settings]
    ScrollView {
        id: settingsPane
        height: parent.height
        property bool hidden: false

        function toggleHide() {
            if (settingsPane.hidden) {
                settingsPaneAnimation.from = settingsPane.x
                settingsPaneAnimation.to = 0
                
                if (!volumesPane.hidden) {
                    volumesPane.toggleHide()
                }
                if (!measurementPane.hidden) {
                    measurementPane.toggleHide()
                }
            } else {
                settingsPaneAnimation.from = settingsPane.x
                settingsPaneAnimation.to = -settingsPane.width
            }
            settingsPane.hidden = !settingsPane.hidden
            settingsPaneAnimation.running = true
        }

        NumberAnimation on x {
            id: settingsPaneAnimation
            running: false
            from: width
            to: width
            duration: 100
        }

        Column {
            topPadding: 10
            bottomPadding: 10
            leftPadding: 20
            rightPadding: 20

            spacing: 10

            Label {
                text: qsTr("Visible value-range:")
            }

            RangeSlider {
                id: tSlider
                from: 0
                to: 1
                first.value: 0
                second.value: 1
            }

            Image {
                width: tSlider.width
                height: 20
                source: getColormapSource(colormapCombo.currentIndex)
            }

            Label {
                text: qsTr("Colormap:")
            }

            ComboBox {
                id: colormapCombo
                model: [qsTr("Black White"), qsTr("Cool Warm"), qsTr("Plasma"), qsTr("Viridis"), qsTr("Rainbow"), qsTr("Gnuplot")]
            }

            Label {
                text: qsTr("Step alpha:")
            }

            Slider {
                id: stepAlphaSlider
                from: 0
                value: 0.2
                to: 1
            }

            Grid {
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                spacing: 5
                Label {
                    text: qsTr("Step length:")
                }

                TextField {
                    id: stepLengthText
                    text: "0.00391" // ~1/256
                    width: 100
                }
            }

            CheckBox {
                id: multipliedAlphaBox
                text: qsTr("Multiplied alpha")
                checked: true
            }

            CheckBox {
                id: drawBoundingBox
                text: qsTr("Draw Bounding Box")
                checked: true
            }

            CheckBox {
                id: drawCursor
                text: qsTr("Draw Cursor Lines")
                checked: true
            }

            CheckBox {
                id: drawXYZGrid
                text: qsTr("Draw XYZ-Grids")
                checked: true
            }

            CheckBox {
                id: autoRotateCheckbox
                text: qsTr("Auto-rotate model")
                checked: false
            }

            // X plane
            Label {
                text: qsTr("X plane slice (position, width):")
            }

            Slider {
                id: xSliceSlider
                from: 0
                to: 1
                value: 0.5
            }

            Slider {
                id: xSliceWidthSlider
                from: 0
                value: 1
                to: 1
            }

            // Y plane
            Label {
                text: qsTr("Y plane slice (position, width):")
            }

            Slider {
                id: ySliceSlider
                from: 0
                to: 1
                value: 0.5
            }

            Slider {
                id: ySliceWidthSlider
                from: 0
                value: 1
                to: 1
            }

            // Z plane
            Label {
                text: qsTr("Z plane slice (position, width):")
            }

            Slider {
                id: zSliceSlider
                from: 0
                to: 1
                value: 0.5
            }

            Slider {
                id: zSliceWidthSlider
                from: 0
                value: 1
                to: 1
            }

            // Dimensions
            Label {
                text: qsTr("Dimensions (width, height, depth):")
            }

            Row {
                spacing: 5
                TextField {
                    id: dataWidth
                    text: "256"
                    validator: IntValidator {
                        bottom: 1
                        top: 2048
                    }
                }
                TextField {
                    id: dataHeight
                    text: "256"
                    validator: IntValidator {
                        bottom: 1
                        top: 2048
                    }
                }
                TextField {
                    id: dataDepth
                    text: "256"
                    validator: IntValidator {
                        bottom: 1
                        top: 2048
                    }
                }
            }

            Label {
                text: qsTr("Scale (x, y, z):")
            }

            Row {
                spacing: 5
                TextField {
                    id: scaleWidth
                    text: "1"
                    validator: DoubleValidator {
                        bottom: 0.001
                        top: 1000
                        decimals: 4
                    }
                }
                TextField {
                    id: scaleHeight
                    text: "1"
                    validator: DoubleValidator {
                        bottom: 0.001
                        top: 1000
                        decimals: 4
                    }
                }
                TextField {
                    id: scaleDepth
                    text: "1"
                    validator: DoubleValidator {
                        bottom: 0.001
                        top: 1000
                        decimals: 4
                    }
                }
            }

            Label {
                text: qsTr("Data type:")
            }

            ComboBox {
                id: dataTypeComboBox
                model: ["uint8", "uint16", "int16", "float32", "float64"]
            }
        }
    }
    //! [settings]

    MouseArea {
        anchors.fill: view
        onClicked: (mouse) => {
            var result = view.pick(mouse.x, mouse.y)
            if (result.objectHit) {
                var pickedObject = result.objectHit
                var distance = result.scenePosition.minus(cursorModel.centroid).length()
                console.log("Picked: " + pickedObject.displayName)
                console.log("Distance: " + distance)
                if (measureModeSelect.checked) {
                    
                } else if (measureModeAdd.checked) {
                    //var instance = Qt.createComponent("QtQuick3D", "InstanceListEntry", Component.Asynchronous, boxInstancing) This method does not work ???
                    var instance = Qt.createQmlObject(`
                        import QtQuick3D

                        InstanceListEntry {
                        }
                        `,
                        boxInstancing
                    )
                    instance.position = result.scenePosition
                    instance.scale = Qt.vector3d(10, 10, 10)
                    boxInstancing.instances.push(instance)
                    boxTable.appendRow({
                        "instance": instance,
                        "positionX": instance.position.x.toFixed(3),
                        "positionY": instance.position.y.toFixed(3),
                        "positionZ": instance.position.z.toFixed(3),
                        "scaleX": instance.scale.x.toFixed(3),
                        "scaleY": instance.scale.y.toFixed(3),
                        "scaleZ": instance.scale.z.toFixed(3),
                        "rotationX": instance.eulerRotation.x.toFixed(3),
                        "rotationY": instance.eulerRotation.y.toFixed(3),
                        "rotationZ": instance.eulerRotation.z.toFixed(3)
                    })
                } else if (measureModeRemove.checked) {
                    pickedObject.instancing.instances.splice(result.instanceIndex, 1)
                    boxTable.removeRow(result.instanceIndex)
                }
            }
        }
    }
}
