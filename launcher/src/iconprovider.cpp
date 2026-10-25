#include "iconprovider.h"

#include <QIcon>

IconProvider::IconProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

QImage IconProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const int edge = requestedSize.isValid() && requestedSize.width() > 0
                         ? qBound(16, requestedSize.width(), 512)
                         : 256;
    const QString key = id + QLatin1Char('@') + QString::number(edge);
    if (m_cache.contains(key)) {
        if (size)
            *size = m_cache.value(key).size();
        return m_cache.value(key);
    }
    QIcon icon = QIcon::fromTheme(id);
    QImage image = icon.isNull() ? QImage() : icon.pixmap(edge, edge).toImage();
    image.setDevicePixelRatio(1.0);
    m_cache.insert(key, image);
    if (size)
        *size = image.size();
    return image;
}
