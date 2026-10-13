#include "loadingAnimation.h"

#include "cute_aseprite.h"

#include <QImage>

#include <cstring>
#include <numeric>

namespace {

constexpr int iconScale = 3;
constexpr int displayScale = 2;

const QList<int> holds = {
    200, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 500, 500, 90, 90, 90, 90, 90, 90, 90, 90, 90,
    90, 90, 90,
};

}

LoadingAnimation::LoadingAnimation(const QByteArray &art)
{
    ase_t *ase = cute_aseprite_load_from_memory(art.constData(), art.size(), nullptr);
    if (!ase) {
        qFatal("the loading animation is not an aseprite file");
    }
    const int block = iconScale * displayScale;
    for (int index = 0; index < ase->frame_count; ++index) {
        QImage source(ase->w, ase->h, QImage::Format_RGBA8888);
        std::memcpy(source.bits(), ase->frames[index].pixels, std::size_t(ase->w) * ase->h * 4);
        QPixmap pixmap = QPixmap::fromImage(source.scaled(
            ase->w * block, ase->h * block, Qt::IgnoreAspectRatio, Qt::FastTransformation));
        pixmap.setDevicePixelRatio(displayScale);
        frames_.append(pixmap);
    }
    cute_aseprite_free(ase);
}

int LoadingAnimation::frameCount() const
{
    return frames_.size();
}

int LoadingAnimation::indexAt(qint64 elapsedMs) const
{
    const qint64 total = std::accumulate(holds.cbegin(), holds.cend(), qint64{0});
    qint64 left = elapsedMs % total;
    for (int index = 0; index < holds.size(); ++index) {
        if (left < holds[index]) {
            return index;
        }
        left -= holds[index];
    }
    return 0;
}

QPixmap LoadingAnimation::frameAt(qint64 elapsedMs) const
{
    return frames_[indexAt(elapsedMs)];
}
