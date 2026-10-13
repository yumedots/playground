#pragma once

#include <QByteArray>
#include <QList>
#include <QPixmap>

class LoadingAnimation
{
public:
    explicit LoadingAnimation(const QByteArray &art);

    int frameCount() const;
    int indexAt(qint64 elapsedMs) const;
    QPixmap frameAt(qint64 elapsedMs) const;

private:
    QList<QPixmap> frames_;
};
