#include <QDebug>
#include <QJsonValue>
#include <QJsonArray>
#include <QJsonObject>
#include <QtGlobal>

#include <src/storagezarr.h>
#include <blosc2.h> //Zarr decompression.

StorageZarr::StorageZarr(QUrl url)
{
	m_baseUrl = url;
}

StorageZarr::~StorageZarr()
{
}

QByteArray StorageZarr::readChunk(const QByteArray& data)
{
    /* Decompress  */
    if (m_meta.compressor.id == "blosc") {
        qsizetype chunkSizeBytes = getChunkSizeBytes();
        QByteArray newData(chunkSizeBytes, Qt::Uninitialized);

        int err = blosc2_decompress(data.constData(), data.size(), newData.data(), newData.size());
        if (err < 0) {
            qWarning() << "Blosc2 Decompression error. Error code:" << err;
            return QByteArray(); // Empty.
        }

        return newData;
    } else if (m_meta.compressor.id.isEmpty()) { // No compression.
        return data;
    } else {
        qWarning() << "Compressor not available" << m_meta.compressor.id;
        return QByteArray(); // Empty.
    }

}

QUrl StorageZarr::getMetadataUrl(int level)
{
    QString combinedPath = m_baseUrl.path();
    if (level >= 0) {
        QString levelPath = QString("/%1/").arg(level);
        combinedPath += levelPath;
    }
    combinedPath += ".zarray";
    QUrl combinedPathUrl(combinedPath);
    QUrl metadataUrl = m_baseUrl.resolved(combinedPathUrl);
    return metadataUrl;
}

QUrl StorageZarr::getChunkUrl(int level, int z, int y, int x) {
    QStringList coordinates;
    if (m_meta.order == "C") {
        coordinates << QString::number(z) << QString::number(y) << QString::number(x);
    }
    else if (m_meta.order == "yxz") { // This order value is not in the spec.
        coordinates << QString::number(y) << QString::number(x) << QString::number(z);
    }
    QString chunkResourcePath = "/" + coordinates.join(m_meta.dimensionSeparator);
    QString combinedPath = m_baseUrl.path();
    if (level >= 0) {
        QString levelPath = QString("/%1").arg(level);
        combinedPath += levelPath;
    }
    combinedPath += chunkResourcePath;
    QUrl combinedPathUrl(combinedPath);
    QUrl chunkUrl = m_baseUrl.resolved(combinedPathUrl);
    return chunkUrl;
}

triplet<int> StorageZarr::getNearestChunk(triplet<int> point) // z, y, x
{
    int z = std::get<0>(point) / std::get<0>(m_meta.chunks);
    int y = std::get<1>(point) / std::get<1>(m_meta.chunks);
    int x = std::get<2>(point) / std::get<2>(m_meta.chunks);
    return std::make_tuple(z, y, x);
}

triplet<float> StorageZarr::getNearestChunkRemainder(triplet<int> point) // z, y, x
{
    float z = std::get<0>(point) / (float)std::get<0>(m_meta.chunks);
    z = z - std::floor(z);
    float y = std::get<1>(point) / (float)std::get<1>(m_meta.chunks);
    y = y - std::floor(y);
    float x = std::get<2>(point) / (float)std::get<2>(m_meta.chunks);
    x = x - std::floor(x);
    return std::make_tuple(z, y, x);
}

StorageZarr::Metadata StorageZarr::Metadata::fromJson(const QJsonObject& json)
{
    Metadata result;

    if (const QJsonValue zarrFormat = json["zarr_format"]; zarrFormat.isDouble()) {
        result.version = zarrFormat.toInt();
    }

    if (result.version <= 2) {
        result.dimensionSeparator = ".";
    }
    // Changed compared to sepc v2 to decrease maximum number of items in hierarchical stores, ie. filesystem.
    else if (result.version == 3) {
        result.dimensionSeparator = "/";
    }

    if (const QJsonValue dimensionSeparator = json["dimension_separator"]; dimensionSeparator.isString()) {
        result.dimensionSeparator = dimensionSeparator.toString();
    }
    
    if (const QJsonValue shape = json["shape"]; shape.isArray()) {
        QJsonArray arr = shape.toArray();
        result.shape = std::make_tuple(arr[0].toInt(), arr[1].toInt(), arr[2].toInt());
    }

    if (const QJsonValue chunks = json["chunks"]; chunks.isArray()) {
        QJsonArray arr = chunks.toArray();
        result.chunks = std::make_tuple(arr[0].toInt(), arr[1].toInt(), arr[2].toInt());
    }

    if (const QJsonValue dtype = json["dtype"]; dtype.isString()) {
        result.dtype = dtype.toString();
    }

    if (const QJsonValue compression = json["compression"]; compression.isString()) {
        result.compression = compression.toString();
    }

    if (const QJsonValue order = json["order"]; order.isString()) {
        result.order = order.toString();
    }

    if (const QJsonValue compression = json["compression"]; compression.isString()) {
        result.compression = compression.toString();
    }

    if (const QJsonValue compressor = json["compressor"]; compressor.isObject()) {
        if (const QJsonValue id = compressor["id"]; id.isString()) {
            result.compressor.id = id.toString();
        }
    }

    return result;
}

StorageZarr::Metadata StorageZarr::Metadata::fromByteArray(const QByteArray& data)
{
    return fromJson(QJsonDocument::fromJson(data).object());
}
