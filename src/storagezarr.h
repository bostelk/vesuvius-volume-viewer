#ifndef STORAGEZARR_H
#define STORAGEZARR_H

#include <QUrl>
#include <QByteArray>
#include <QJsonDocument>

template<typename T>
using triplet = std::tuple<T, T, T>;

// Interface to access large N-dimensional typed arrays stored in Zarr format.
class StorageZarr
{
public:

    // See: https://zarr-specs.readthedocs.io/en/latest/specs.html
    struct Metadata
    {
        struct Compressor {
            int blocksize;
            int clevel;
            QString cname;
            QString id;
            int shuffle;
        };

        int version = -1; // The data is invalid.
        triplet<int> chunks;
        triplet<int> shape;
        QString order;
        QString dimensionSeparator; // The default is dependent on version.
        QString dtype;
        QString compression;
        Compressor compressor;

        static Metadata fromJson(const QJsonObject& json);
        static Metadata fromByteArray(const QByteArray& data);
    };

    StorageZarr(QUrl url);
    ~StorageZarr();

    // Get URL to the metadata resource.
    QUrl getMetadataUrl(int level = -1);
    // Get URL to the chunk resource.
    QUrl getChunkUrl(int level, int z, int y, int x);

    void setMetadata(const QByteArray& data) {
        m_meta = Metadata::fromByteArray(data);
    }

    std::tuple<int, int, int> getChunks() {
        return m_meta.chunks;
    }

    size_t getChunkSizeBytes() const {
        size_t dataTypeSizeBytes = 1;
        return dataTypeSizeBytes * std::get<0>(m_meta.chunks) * std::get<1>(m_meta.chunks) * std::get<2>(m_meta.chunks);
    }

    triplet<int> getNearestChunk(triplet<int> point); // z, y, x
    triplet<float> getNearestChunkRemainder(triplet<int> point); // z, y, x

    QByteArray readChunk(const QByteArray& data);

    QString getOrder() const {
        return m_meta.order;
    }
    void setOrder(const QString value) {
        m_meta.order = value;
    }

    QString getDataType() const {
        return m_meta.dtype;
    }
private:
    // The path to the .zarr directory.
    QUrl m_baseUrl;

    // The metadata resource.
    Metadata m_meta;
};

#endif // STORAGEZARR_H
