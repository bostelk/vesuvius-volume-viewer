// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

#include "lineboxgeometry.h"
#include <QRandomGenerator>
#include <QVector3D>
#include <array>

LineBoxGeometry::LineBoxGeometry()
{
    updateData();
}

void LineBoxGeometry::updateData()
{
    constexpr int kStride = sizeof(QVector3D);

    QByteArray vertexData(24 * kStride, Qt::Initialization::Uninitialized);
    QVector3D* p = reinterpret_cast<QVector3D*>(vertexData.data());

    std::array<QVector3D, 8> pts;
    pts[0] = QVector3D(-m_size, -m_size, -m_size);
    pts[1] = QVector3D(-m_size, -m_size, +m_size);
    pts[2] = QVector3D(-m_size, +m_size, +m_size);
    pts[3] = QVector3D(-m_size, +m_size, -m_size);
    pts[4] = QVector3D(+m_size, -m_size, -m_size);
    pts[5] = QVector3D(+m_size, -m_size, +m_size);
    pts[6] = QVector3D(+m_size, +m_size, +m_size);
    pts[7] = QVector3D(+m_size, +m_size, -m_size);
    // left side
    *p = pts[0];
    p++;
    *p = pts[1];
    p++;
    *p = pts[1];
    p++;
    *p = pts[2];
    p++;
    *p = pts[2];
    p++;
    *p = pts[3];
    p++;
    *p = pts[3];
    p++;
    *p = pts[0];
    p++;
    // right side
    *p = pts[4];
    p++;
    *p = pts[5];
    p++;
    *p = pts[5];
    p++;
    *p = pts[6];
    p++;
    *p = pts[6];
    p++;
    *p = pts[7];
    p++;
    *p = pts[7];
    p++;
    *p = pts[4];
    p++;
    // across
    *p = pts[0];
    p++;
    *p = pts[4];
    p++;
    *p = pts[1];
    p++;
    *p = pts[5];
    p++;
    *p = pts[2];
    p++;
    *p = pts[6];
    p++;
    *p = pts[3];
    p++;
    *p = pts[7];
    p++;

    setVertexData(vertexData);
    setStride(kStride);
    setBounds(QVector3D(-m_size, -m_size, -m_size), QVector3D(+m_size, +m_size, +m_size));

    setPrimitiveType(QQuick3DGeometry::PrimitiveType::Lines);

    addAttribute(QQuick3DGeometry::Attribute::PositionSemantic, 0, QQuick3DGeometry::Attribute::F32Type);
}

void LineBoxGeometry::setSize(float size)
{
    m_size = size;
    updateData();
    update();
    emit sizeChanged();
}