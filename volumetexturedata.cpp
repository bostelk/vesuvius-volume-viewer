// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

#include "volumetexturedata.h"
#include "qthread.h"
#include <QSize>
#include <QFile>
#include <QElapsedTimer>

#include <QDebug>
#include <QCoreApplication>
#include <QEventLoop>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkAccessManager>

#include <blosc2.h> //Zarr volume.
#include <nrrd.h> 

QT_BEGIN_NAMESPACE

enum ExampleId { Helix, Box, Colormap };

// Method to convert data from T to uint8_t
template<typename T>
static void convertData(QByteArray &imageData, const QByteArray &imageDataSource)
{
    Q_ASSERT(imageDataSource.size() > 0);
    constexpr auto kScale = sizeof(T) / sizeof(uint8_t);
    auto imageDataSourceData = reinterpret_cast<const T *>(imageDataSource.constData());
    qsizetype imageDataSourceSize = imageDataSource.size() / kScale;
    imageData.resize(imageDataSourceSize);
    auto imageDataPtr = reinterpret_cast<uint8_t *>(imageData.data());

    T min = std::numeric_limits<T>::max();
    T max = std::numeric_limits<T>::min();

#pragma omp parallel for
    for (int i = 0; i < imageDataSourceSize; i++) {
        if (imageDataSourceData[i] > max) {
#pragma omp critical
            max = qMax(max, imageDataSourceData[i]);
        }
    }

#pragma omp parallel for
    for (int i = 0; i < imageDataSourceSize; i++) {
        if (imageDataSourceData[i] < min) {
#pragma omp critical
            min = qMin(min, imageDataSourceData[i]);
        }
    }
    const T range = max - min;
    const double rangeInv = 255.0 / range; // use double for optimal precision

#pragma omp parallel for
    for (int i = 0; i < imageDataSourceSize; i++) {
        imageDataPtr[i] = (imageDataSourceData[i] - min) * rangeInv;
    }
}

static QByteArray createBuiltinVolume(int exampleId)
{
    constexpr int size = 256;

    QByteArray byteArray(size * size * size, 0);
    uint8_t *data = reinterpret_cast<uint8_t *>(byteArray.data());
    const auto cellIndex = [size](int x, int y, int z) {
        Q_UNUSED(size); // MSVC specific
        const int index = x + size * (z + size * y);
        Q_ASSERT(index < size * size * size && index >= 0);
        return index;
    };

    const auto createHelix = [&](float zOffset, uint8_t color) {
        //  x = radius * cos(t)
        //  y = radius * sin(t)
        //  z = climb * t
        //
        // We go through t until z is outside of box

        constexpr float radius = 70.f;
        constexpr float climb = 15.f;
        constexpr float offset = 256 / 2;
        constexpr int thick = 6; // half radius

        int i = -1;
        QVector3D lastCell = QVector3D(0, 0, 0);
        while (true) {
            i++;
            const float t = i * 0.005f;
            const int cellX = offset + radius * qCos(t);
            const int cellY = offset + radius * qSin(t);
            const int cellZ = (climb * t) - zOffset;
            if (cellZ < 0) {
                continue;
            }
            if (cellZ > 255)
                break;

            QVector3D originalCell(cellX, cellY, cellZ);
            if (originalCell == lastCell)
                continue;
            lastCell = originalCell;

#pragma omp parallel for
            for (int z = cellZ - thick; z < cellZ + thick; z++) {
                if (z < 0 || z > 255)
                    continue;
                for (int y = cellY - thick; y < cellY + thick; y++) {
                    if (y < 0 || y > 255)
                        continue;
                    for (int x = cellX - thick; x < cellX + thick; x++) {
                        if (x < 0 || x > 255)
                            continue;
                        QVector3D currCell(x, y, z);
                        float dist = originalCell.distanceToPoint(currCell);
                        if (dist < thick) {
                            data[cellIndex(x, y, z)] = color;
                        }
                    }
                }
            }
        }
    };

    if (exampleId == ExampleId::Helix) {
        // Fill with weird ball and holes
        QVector3D centreCell(size / 2, size / 2, size / 2);
#pragma omp parallel for
        for (int z = 0; z < size; z++) {
            for (int y = 0; y < size; y++) {
                for (int x = 0; x < size; x++) {
                    const float dist = centreCell.distanceToPoint(QVector3D(x, y, z));
                    const float value = dist * 0.5f - 40.f; // Negative value means cell is inside of sphere
                    data[cellIndex(x, y, z)] = value >= 0 ? quint8(qBound(value, 0.f, 80.f)) : 80;
                }
            }
        }
        createHelix(0, 200);
        createHelix(30, 150);
        createHelix(60, 100);

    } else if (exampleId == ExampleId::Colormap) {
#pragma omp parallel for
        for (int z = 0; z < 256; z++) {
            for (int y = 0; y < 256; y++) {
                for (int x = 0; x < 256; x++) {
                    data[cellIndex(x, y, z)] = x;
                }
            }
        }
    } else if (exampleId == ExampleId::Box) {
        std::array<int, 6> colors = { 50, 100, 255, 200, 150, 10 };
        constexpr int width = 10;
#pragma omp parallel for
        for (int i = 0; i < width; i++) {
            int x0 = i;
            int x1 = 255 - i;
            for (int z = 0; z < 256; z++) {
                for (int y = 0; y < 256; y++) {
                    data[cellIndex(x0, y, z)] = colors[0];
                    data[cellIndex(x1, y, z)] = colors[1];
                }
            }
        }
#pragma omp parallel for
        for (int i = 0; i < width; i++) {
            int y0 = i;
            int y1 = 255 - i;
            for (int z = 0; z < 256; z++) {
                for (int x = 0; x < 256; x++) {
                    data[cellIndex(x, y0, z)] = colors[2];
                    data[cellIndex(x, y1, z)] = colors[3];
                }
            }
        }
#pragma omp parallel for
        for (int i = 0; i < width; i++) {
            int z0 = i;
            int z1 = 255 - i;
            for (int y = 0; y < 256; y++) {
                for (int x = 0; x < 256; x++) {
                    data[cellIndex(x, y, z0)] = colors[4];
                    data[cellIndex(x, y, z1)] = colors[5];
                }
            }
        }
    }

    return byteArray;
}

static QByteArray decompressZarrChunk(QByteArray data, int depth, int width, int height)
{
    qsizetype decompressed_size_bytes = depth * width * height;
    unsigned char* decompressed_data = (unsigned char*)malloc(decompressed_size_bytes);

    /* Decompress  */
    int err = blosc2_decompress(data.constData(), data.size(), decompressed_data, decompressed_size_bytes);
    if (err < 0) {
        free(decompressed_data);
        qWarning() << "Blosc2 Decompression error. Error code:" << err;
        return QByteArray();
    }

    QByteArray newData((const char* )decompressed_data, decompressed_size_bytes);

    free(decompressed_data);
    return newData;
}

static QUrl getZarrChunkUrl(const QUrl zarrUrl, int level, int z, int y, int x, char chunkSeparator = '/', int order = 0) {
    QStringList coordinates;
    if (order == 0) {
        coordinates << QString::number(z) << QString::number(y) << QString::number(x);
    } else if (order == 1) {
        coordinates << QString::number(y) << QString::number(x) << QString::number(z);
    }
    QString chunkResourcePath = "/" + coordinates.join(chunkSeparator);
    QString combinedPath = zarrUrl.path();
    if (level >= 0) {
        QString levelPath = QString("/%1").arg(level);
        combinedPath += levelPath;
    } 
    combinedPath += chunkResourcePath;
    QUrl combinedPathUrl(combinedPath);
    QUrl zarrChunkURL = zarrUrl.resolved(combinedPathUrl);
    return zarrChunkURL;
}

static std::tuple<int, int, int> getNearestZarrChunk(std::tuple<int, int, int> size, std::tuple<int, int, int> point) // z, y, x
{
    int z = std::get<0>(point) / std::get<0>(size);
    int y = std::get<1>(point) / std::get<1>(size);
    int x = std::get<2>(point) / std::get<2>(size);
    return std::make_tuple(z, y, x);
}

static std::tuple<float, float, float> getNearestZarrChunkRemainder(std::tuple<int, int, int> size, std::tuple<int, int, int> point) // z, y, x
{
    float z = std::get<0>(point) / (float)std::get<0>(size);
    z = z - std::floor(z);
    float y = std::get<1>(point) / (float)std::get<1>(size);
    y = y - std::floor(y);
    float x = std::get<2>(point) / (float)std::get<2>(size);
    x = x - std::floor(x);
    return std::make_tuple(z, y, x);
}

static QByteArray fetchResourceBlocking(QUrl resourceUrl)
{
    qDebug() << "Fetch:" << resourceUrl;

    QNetworkRequest netRequest(resourceUrl);
    QNetworkAccessManager* manager = new QNetworkAccessManager();

    // Create an event loop to block until the request finishes
    QEventLoop loop;

    // Connect the finished signal to quit the event loop
    QObject::connect(manager, &QNetworkAccessManager::finished, &loop, &QEventLoop::quit);

    // Make the request
    QNetworkReply* reply = manager->get(netRequest);

    // Enter the event loop and block until the request is finished
    loop.exec();

    // Once finished, handle the reply
    if (reply->error() == QNetworkReply::NoError) {
        // Success: process the reply data
        QByteArray data = reply->readAll();
        qDebug() << "Reply data:" << data.size();
        return data;
    }
    else {
        // Error handling
        qDebug() << "Error:" << reply->errorString();
    }

    // Clean up the reply
    reply->deleteLater();

    return QByteArray(); // Empty.
}

QByteArray loadNrrdFromByteArray(QByteArray data) {
    // Create a memory stream from the byte array
    FILE* stream = fmemopen(const_cast<char*>(data.constData()), data.size(), "r");
    if (!stream) {
        qWarning() << "Failed to open memory stream.";
        return QByteArray(); // Empty.
    }

    NrrdIoState* nio = nrrdIoStateNew();

    // Create a Nrrd object to hold the data
    Nrrd* nrrd = nrrdNew();
    if (nrrdRead(nrrd, stream, nio)) {
        qWarning() << "Error loading NRRD from memory.";
        nrrdNuke(nrrd);
        nio = nrrdIoStateNix(nio);
        fclose(stream);
        return QByteArray(); // Empty.
    }

    nio = nrrdIoStateNix(nio);

    // Optionally print out the header info for debugging
    //char* header = nrrdContent(nrrd);
    //std::cout << "NRRD Header: " << std::endl << header << std::endl;

    qDebug() << "element size:" << QString::number(nrrdElementSize(nrrd));

    uint8_t maxVal = 0;
    for (size_t i = 0; i < nrrdElementNumber(nrrd); i++) {
        uint8_t value = ((uint8_t*)nrrd->data)[i];
        if (value > maxVal) {
            maxVal = value;
        }
    }

    qDebug() << "max value:" << QString::number(maxVal);


    // Access the raw data
    size_t dataSizeBytes = nrrdElementNumber(nrrd) * nrrdElementSize(nrrd);
    QByteArray newData((const char*)nrrd->data, dataSizeBytes);

    // Perform any processing with the data here

    // Clean up
    nrrdNuke(nrrd);
    fclose(stream);
    return newData;
}

static VolumeTextureData::AsyncLoaderData loadVolume(const VolumeTextureData::AsyncLoaderData& input)
{
    QByteArray imageDataSource;

    QVector3D globalFocusPoint = input.globalFocusPoint; // Point to center the cursor on in global scroll coorindates.
    QVector3D localFocusPoint; // Point to center the cursor on in local box coordinates.

    if (input.source == QUrl("file:///default_helix")) {
        imageDataSource = createBuiltinVolume(ExampleId::Helix);
    } else if (input.source == QUrl("file:///default_box")) {
        imageDataSource = createBuiltinVolume(ExampleId::Box);
    } else if (input.source == QUrl("file:///default_colormap")) {
        imageDataSource = createBuiltinVolume(ExampleId::Colormap);
    } else if (input.source.scheme() == "http" || input.source.scheme() == "https") {
        const auto chunkPoint = std::make_tuple(globalFocusPoint.z(), globalFocusPoint.y(), globalFocusPoint.x()); // PI letter (z, y, x).
        const auto chunkShape = std::make_tuple(input.depth, input.width, input.height);
        const auto [chunkZ, chunkY, chunkX] = getNearestZarrChunk(chunkShape, chunkPoint);
        const auto [remZ, remY, remX] = getNearestZarrChunkRemainder(chunkShape, chunkPoint);

        float boxSize = 50;
        localFocusPoint = 2 * boxSize * QVector3D(remX, remY, remZ) - QVector3D(boxSize, boxSize, boxSize);

        QUrl zarrChunkURL = getZarrChunkUrl(input.source, input.level, chunkZ, chunkY, chunkX, input.chunkSeparator, input.order);
        QByteArray data = fetchResourceBlocking(zarrChunkURL);
        if (!data.isEmpty()) {
            imageDataSource = decompressZarrChunk(data, input.depth, input.width, input.height);
        }
    } else {
        // NOTE: we always assume a local file is opened
        QFile file(input.source.toLocalFile());
        if (!file.open(QIODevice::ReadOnly)) {
            qWarning() << "Could not open file: " << file.fileName();
            auto result = input;
            result.success = false;
            return result;
        }

        imageDataSource = file.readAll();
        imageDataSource = loadNrrdFromByteArray(imageDataSource);

        file.close();
    }

    QByteArray imageData;

    // We scale the values to uint8_t data size
    if (input.dataType == "uint8") {
        imageData = imageDataSource;
    } else if (input.dataType == "uint16") {
        convertData<uint16_t>(imageData, imageDataSource);
    } else if (input.dataType == "int16") {
        convertData<int16_t>(imageData, imageDataSource);
    } else if (input.dataType == "float32") {
        convertData<float>(imageData, imageDataSource);
    } else if (input.dataType == "float64") {
        convertData<double>(imageData, imageDataSource);
    } else {
        qWarning() << "Unknown data type, assuming uint8";
        imageData = imageDataSource;
    }

    // If our source data is smaller than expected we need to expand the texture
    // and fill with something
    qsizetype dataSize = input.depth * input.width * input.height;
    if (imageData.size() < dataSize) {
        imageData.resize(dataSize, '0');
    }

    auto result = input;
    result.volumeData = imageData;
    result.globalFocusPoint = globalFocusPoint;
    result.localFocusPoint = localFocusPoint;
    result.success = true;
    return result;
}

class Worker : public QThread
{
    Q_OBJECT
public:
    Worker(VolumeTextureData *parent, const VolumeTextureData::AsyncLoaderData &loaderData)
        : QThread(parent), m_loaderData(loaderData)
    {
    }
    void run() override { emit resultReady(loadVolume(m_loaderData)); }

signals:
    void resultReady(const VolumeTextureData::AsyncLoaderData result);

private:
    VolumeTextureData::AsyncLoaderData m_loaderData;
};

///////////////////////////////////////////////////////////////////////

VolumeTextureData::VolumeTextureData()
{
    // Load a volume by default so we have something to render to avoid crashes
    m_source = QUrl("file:///default_colormap");
    m_width = 256;
    m_height = 256;
    m_depth = 256;
    m_dataType = "uint8";
    auto result = loadVolume(AsyncLoaderData { m_source, m_width, m_height, m_depth, m_dataType });
    setFormat(Format::R8);
    setTextureData(result.volumeData);
    setSize(QSize(m_width, m_height));
    QQuick3DTextureData::setDepth(m_depth);
}

VolumeTextureData::~VolumeTextureData()
{
    if (m_worker) {
        m_worker->quit();
        m_worker->wait();
        delete m_worker;
    }
}

QUrl VolumeTextureData::source() const
{
    return m_source;
}

void VolumeTextureData::setSource(const QUrl &newSource)
{
    if (m_source == newSource)
        return;

    m_source = newSource;
    if (!m_isLoading && !m_source.isEmpty())
        loadAsync(m_source, m_width, m_height, m_depth, m_dataType);
    emit sourceChanged();
}

qsizetype VolumeTextureData::width() const
{
    return m_width;
}

void VolumeTextureData::setWidth(qsizetype newWidth)
{
    if (m_width == newWidth)
        return;

    m_width = newWidth;
    updateTextureDimensions();
    emit widthChanged();
}

qsizetype VolumeTextureData::height() const
{
    return m_height;
}

void VolumeTextureData::setHeight(qsizetype newHeight)
{
    if (m_height == newHeight)
        return;

    m_height = newHeight;
    updateTextureDimensions();
    emit heightChanged();
}

qsizetype VolumeTextureData::depth() const
{
    return m_depth;
}

void VolumeTextureData::setDepth(qsizetype newDepth)
{
    if (m_depth == newDepth)
        return;

    m_depth = newDepth;
    updateTextureDimensions();
    emit depthChanged();
}

QString VolumeTextureData::dataType() const
{
    return m_dataType;
}

void VolumeTextureData::setDataType(const QString &newDataType)
{
    if (m_dataType == newDataType)
        return;
    m_dataType = newDataType;
    if (!m_isLoading && !m_source.isEmpty())
        loadAsync(m_source, m_width, m_height, m_depth, m_dataType);
    emit dataTypeChanged();
}

void VolumeTextureData::updateTextureDimensions()
{
    if (m_width * m_height * m_depth > m_currentDataSize)
        return;

    setSize(QSize(m_width, m_height));
    QQuick3DTextureData::setDepth(m_depth);
}

void VolumeTextureData::loadAsync(QUrl source, qsizetype width, qsizetype height, qsizetype depth, QString dataType, QVector3D globalFocusPoint, QString chunkSeparator, int level, int order)
{
    loaderData.source = source;
    loaderData.width = width;
    loaderData.height = height;
    loaderData.depth = depth;
    loaderData.dataType = dataType;
    loaderData.globalFocusPoint = globalFocusPoint;
    loaderData.chunkSeparator = chunkSeparator[0].toLatin1();
    loaderData.level = level;
    loaderData.order = order;

    if (m_isLoading) {
        m_isAborting = true;
        return;
    }

    m_isLoading = true;
    initWorker();
}

void VolumeTextureData::initWorker()
{
    Q_ASSERT(!m_worker || !m_worker->isRunning());
    delete m_worker;
    m_worker = new Worker(this, loaderData);
    connect(m_worker, &Worker::resultReady, this, &VolumeTextureData::handleResults);
    m_worker->start();
    Q_ASSERT(m_worker->isRunning());
}

void VolumeTextureData::handleResults(AsyncLoaderData result)
{
    m_worker->quit();
    m_worker->wait();

    if (m_isAborting) {
        m_isAborting = false;
        initWorker();
        return;
    }

    if (!result.success) {
        emit loadFailed(result.source, result.width, result.height, result.depth, result.dataType, result.localFocusPoint, result.globalFocusPoint);
    }

    m_currentDataSize = result.volumeData.size();

    setSize(QSize(m_width, m_height));
    QQuick3DTextureData::setDepth(m_depth);
    setFormat(Format::R8);
    setTextureData(result.volumeData);
    updateTextureDimensions();

    setWidth(result.width);
    setHeight(result.height);
    setDepth(result.depth);
    setDataType(result.dataType);
    setSource(result.source);

    emit loadSucceeded(result.source, result.width, result.height, result.depth, result.dataType, result.localFocusPoint, result.globalFocusPoint);
    m_isLoading = false;
}

QT_END_NAMESPACE

#include "volumetexturedata.moc"
