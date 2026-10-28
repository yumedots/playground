#include "guestProcess.h"

#include <QFile>

Launch parseLaunch(const QString &text)
{
    Launch launch;
    launch.environment = QProcessEnvironment::systemEnvironment();
    for (const QString &line : text.split('\n')) {
        if (line.startsWith("program=")) {
            launch.program = line.mid(8).trimmed();
        } else if (line.startsWith("arg=")) {
            launch.arguments << line.mid(4);
        } else if (line.startsWith("env=")) {
            const QString pair = line.mid(4);
            const int split = pair.indexOf('=');
            if (split > 0) {
                launch.environment.insert(pair.left(split), pair.mid(split + 1));
            }
        }
    }
    return launch;
}

GuestProcess::GuestProcess(QObject *parent)
    : QObject(parent), qemu_(new QProcess(this))
{
    connect(qemu_, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        setState(GuestState::Stopped, status == QProcess::NormalExit
            ? "guest stopped, exit " + QString::number(code)
            : QString("guest stopped by signal"));
    });
}

GuestProcess::~GuestProcess()
{
    stop();
}

GuestState GuestProcess::state() const
{
    return state_;
}

void GuestProcess::start()
{
    if (state_ != GuestState::Stopped) {
        return;
    }
    setState(GuestState::Preparing, "starting the guest");
    printArgs();
}

void GuestProcess::stop()
{
    if (state_ != GuestState::Running) {
        return;
    }
    qemu_->terminate();
    if (!qemu_->waitForFinished(3000)) {
        qemu_->kill();
        qemu_->waitForFinished(3000);
    }
}

void GuestProcess::runGuest(const Launch &launch)
{
    qemu_->setProgram(launch.program);
    qemu_->setArguments(launch.arguments);
    qemu_->setProcessEnvironment(launch.environment);
    qemu_->start();
    if (qemu_->waitForStarted()) {
        setState(GuestState::Running, "guest running");
    } else {
        setState(GuestState::Stopped, "could not start QEMU: " + qemu_->errorString());
    }
}

void GuestProcess::setState(GuestState state, const QString &message)
{
    state_ = state;
    emit changed(state, message);
}

void GuestProcess::fail(const QString &message)
{
    setState(GuestState::Stopped, message);
}

void GuestProcess::printArgs()
{
    runXmake({"vm", "--print-args"}, [this](const QString &out) { runGuest(parseLaunch(out)); });
}

void GuestProcess::runXmake(const QStringList &arguments, std::function<void(const QString &)> then)
{
    auto *xmake = new QProcess(this);
    connect(xmake, &QProcess::errorOccurred, this, [this, xmake](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            fail("could not run xmake: " + xmake->errorString());
            xmake->deleteLater();
        }
    });
    connect(xmake, &QProcess::finished, this,
        [this, xmake, arguments, then](int code, QProcess::ExitStatus status) {
            const QString out = QString::fromUtf8(xmake->readAllStandardOutput());
            const QString err = QString::fromUtf8(xmake->readAllStandardError()).trimmed();
            xmake->deleteLater();
            if (status == QProcess::NormalExit && code == 0) {
                then(out);
            } else {
                fail("xmake " + arguments.join(' ') + " failed: " + err.section('\n', -1));
            }
        });
    xmake->start("xmake", arguments);
}
