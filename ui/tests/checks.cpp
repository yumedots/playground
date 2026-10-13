#include "guestProcess.h"
#include "loadingAnimation.h"
#include "settings.h"

#include <QApplication>
#include <QFile>
#include <QTemporaryDir>

#include <cstdio>
#include <cstdlib>

namespace {

void expect(bool ok, const char *what)
{
    if (!ok) {
        std::fprintf(stderr, "FAILED: %s\n", what);
        std::exit(1);
    }
}

}

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    QTemporaryDir dir;
    qputenv("PLAYGROUND_STATE_DIR", dir.path().toUtf8());
    expect(writeSettings({6, "12G", false}), "settings could not be written");
    QFile written(dir.filePath("settings"));
    expect(written.open(QIODevice::ReadOnly | QIODevice::Text), "settings file missing");
    expect(written.readAll() == "cores=6\nmem=12G\naudio=off\n", "settings format changed");
    const Settings read = readSettings();
    expect(read.cores == 6 && read.mem == "12G" && !read.audio, "settings did not round trip");

    QFile artFile("ui/loading.aseprite");
    expect(artFile.open(QIODevice::ReadOnly), "loading.aseprite missing");
    const LoadingAnimation animation(artFile.readAll());
    expect(animation.frameCount() == 25, "loading animation frame count");
    expect(animation.frameAt(0).width() == 64 * 6, "loading frame is not magnified");
    expect(animation.indexAt(199) == 0 && animation.indexAt(200) == 1, "frame 1 timing");
    expect(animation.indexAt(1100) == 11 && animation.indexAt(1600) == 12, "hold timing");
    expect(animation.indexAt(3179) == 24 && animation.indexAt(3180) == 0, "animation loop");

    const Launch launch = parseLaunch("program=/bin/qemu\narg=-m\narg=4G x\nenv=A=b=c\n");
    expect(launch.program == "/bin/qemu", "launch program");
    expect(launch.arguments == QStringList({"-m", "4G x"}), "launch arguments");
    expect(launch.environment.value("A") == "b=c", "launch environment");

    GuestProcess guest;
    expect(guest.state() == GuestState::Stopped, "new guest is not stopped");
    guest.runGuest({"sleep", {"30"}, QProcessEnvironment::systemEnvironment()});
    expect(guest.state() == GuestState::Running, "guest did not run");
    guest.stop();
    expect(guest.state() == GuestState::Stopped, "guest did not stop");

    std::puts("checks passed");
    return 0;
}
