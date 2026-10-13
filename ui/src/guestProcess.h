#pragma once

#include <QObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStringList>

#include <functional>

enum class GuestState { Stopped, Preparing, Running };

struct Launch
{
    QString program;
    QStringList arguments;
    QProcessEnvironment environment;
};

Launch parseLaunch(const QString &text);

class GuestProcess : public QObject
{
    Q_OBJECT

public:
    explicit GuestProcess(QObject *parent = nullptr);
    ~GuestProcess() override;

    GuestState state() const;
    void start();
    void stop();
    void runGuest(const Launch &launch);

signals:
    void changed(GuestState state, const QString &message);

private:
    void setState(GuestState state, const QString &message);
    void fail(const QString &message);
    void printArgs();
    void runXmake(const QStringList &arguments, std::function<void(const QString &)> then);

    QProcess *qemu_;
    GuestState state_ = GuestState::Stopped;
};
