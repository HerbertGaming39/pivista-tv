#pragma once

#include <QHash>
#include <QImage>
#include <QQuickImageProvider>

class IconProvider : public QQuickImageProvider
{
public:
    IconProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    QHash<QString, QImage> m_cache;
};
