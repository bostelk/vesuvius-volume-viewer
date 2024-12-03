
#include "linecrossgeometry.h"
#include <QRandomGenerator>
#include <QVector3D>
#include <array>

LineCrossGeometry::LineCrossGeometry()
{
    updateData();
}

void LineCrossGeometry::updateData()
{
    constexpr int kStride = sizeof(QVector3D);

    QByteArray vertexData(6 * kStride, Qt::Initialization::Uninitialized);
    QVector3D* p = reinterpret_cast<QVector3D*>(vertexData.data());

    float halfSize = m_size / 2.0f;

    std::array<QVector3D, 6> pts;
    pts[0] = QVector3D(-halfSize, m_center.y(), m_center.z());
    pts[1] = QVector3D(halfSize, m_center.y(), m_center.z());
    pts[2] = QVector3D(m_center.x(), -halfSize, m_center.z());
    pts[3] = QVector3D(m_center.x(), halfSize, m_center.z());
    pts[4] = QVector3D(m_center.x(), m_center.y(), -halfSize);
    pts[5] = QVector3D(m_center.x(), m_center.y(), halfSize);

    *p = pts[0];
    p++;
    *p = pts[1];
    p++;
    *p = pts[2];
    p++;
    *p = pts[3];
    p++;
    *p = pts[4];
    p++;
    *p = pts[5];

    setVertexData(vertexData);
    setStride(kStride);
    setBounds(QVector3D(-halfSize, -halfSize, -halfSize), QVector3D(halfSize, halfSize, halfSize));

    setPrimitiveType(QQuick3DGeometry::PrimitiveType::Lines);

    addAttribute(QQuick3DGeometry::Attribute::PositionSemantic, 0, QQuick3DGeometry::Attribute::F32Type);
}

void LineCrossGeometry::setSize(float size)
{
    m_size = size;
    updateData();
    update();
    emit sizeChanged();
}

void LineCrossGeometry::setCenter(QVector3D center)
{
    m_center = center;
    updateData();
    update();
    emit centerChanged();
}

