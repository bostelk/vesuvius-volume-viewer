
#ifndef LINECROSSGEOMETRY_H
#define LINECROSSGEOMETRY_H

#include <QQuick3DGeometry>
#include <QVector3D>

class LineCrossGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    QML_NAMED_ELEMENT(LineCrossGeometry)
    Q_PROPERTY(float size READ size WRITE setSize NOTIFY sizeChanged)
    Q_PROPERTY(QVector3D center READ center WRITE setCenter NOTIFY centerChanged)

public:
    LineCrossGeometry();

    float size() const { return m_size; }
    void setSize(float value);

    QVector3D center() const { return m_center; }
    void setCenter(QVector3D value);

signals:
    void sizeChanged();
    void centerChanged();

private:
    void updateData();

    float m_size = 100.0;
    QVector3D m_center = QVector3D(0, 0, 0);
};

#endif
