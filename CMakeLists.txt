# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

cmake_minimum_required(VERSION 3.16)
project(volumeraycaster LANGUAGES CXX)
find_package(OpenMP)

set(CMAKE_AUTOMOC ON)

list(APPEND CMAKE_PREFIX_PATH "/opt/Qt/6.8.0/gcc_64/lib/cmake")
find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Quick3D)

qt_add_executable(volumeraycaster
    src/main.cpp
    src/volumetexturedata.cpp
    src/volumetexturedata.h
    src/lineboxgeometry.cpp
    src/lineboxgeometry.h
    src/linecrossgeometry.cpp
    src/linecrossgeometry.h
    src/storagezarr.cpp
    src/storagezarr.h
)

set_target_properties(volumeraycaster PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
)

pkg_check_modules(BLOSC2 REQUIRED blosc2)
include_directories(${BLOSC2_INCLUDE_DIRS})

find_path(TEEM_INCLUDE_DIR NAMES nrrd.h
    HINTS {CMAKE_INSTALL_PREFIX}
    PATH_SUFFIXES include include/teem
)
find_library(TEEM_LIBRARY NAMES teem
    HINTS {CMAKE_INSTALL_PREFIX}
    PATH_SUFFIXES lib
)
include_directories(${TEEM_INCLUDE_DIR})

pkg_check_modules(ZLIB REQUIRED zlib) # <-- TEEM dep

find_library(BZIP2_LIBRARY NAMES libbz2 # <-- TEEM dep
    HINTS {CMAKE_INSTALL_PREFIX}
    PATH_SUFFIXES lib lib/x86_64-linux-gnu
)

find_package(PNG 1.6) # <-- TEEM dep

target_link_libraries(volumeraycaster PUBLIC
    Qt::Core
    Qt::Gui
    Qt::Quick
    Qt::Quick3D
    ${BLOSC2_LIBRARIES}
    ${TEEM_LIBRARY}
    ${ZLIB_LIBRARIES}
    ${BZIP2_LIBRARY}
    ${PNG_LIBRARIES}
)

if(OpenMP_CXX_FOUND AND NOT ANDROID)
    target_link_libraries(volumeraycaster PUBLIC
        OpenMP::OpenMP_CXX
    )
endif()

qt_add_qml_module(volumeraycaster
    URI VolumetricExample
    VERSION 1.0
    QML_FILES
        Main.qml
        ArcballController.qml
        OriginGizmo.qml
        Spinner.qml
    RESOURCES
        images/circle.png
        images/colormap-blackwhite.png
        images/colormap-coolwarm.png
        images/colormap-gist_rainbow.png
        images/colormap-gnuplot.png
        images/colormap-plasma.png
        images/colormap-rainbow.png
        images/colormap-viridis.png
        alpha_blending.frag
        alpha_blending.vert
        SpacingMap.mjs
    RESOURCE_PREFIX "/qt/qml"
    IMPORTS
        QtQuick3D
)

install(TARGETS volumeraycaster
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

qt_generate_deploy_qml_app_script(
    TARGET volumeraycaster
    OUTPUT_SCRIPT deploy_script
    MACOS_BUNDLE_POST_BUILD
    NO_UNSUPPORTED_PLATFORM_ERROR
    DEPLOY_USER_QML_MODULES_ON_UNSUPPORTED_PLATFORM
)
install(SCRIPT ${deploy_script})
