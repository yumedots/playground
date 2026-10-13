import os
import signal
import socket
import subprocess
import sys
import time


def read_prompt(connection):
    result = bytearray()
    while not result.endswith(b"(qemu) "):
        chunk = connection.recv(4096)
        if not chunk:
            raise ConnectionError("QEMU monitor closed")
        result.extend(chunk)
    return bytes(result)


def monitor(socket_path, command):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(20)
        connection.connect(socket_path)
        read_prompt(connection)
        connection.sendall(command.encode() + bytes([10]))
        return read_prompt(connection).decode(errors="replace")


def running(socket_path):
    try:
        return "VM status: running" in monitor(socket_path, "info status")
    except OSError:
        return False


def launch(log_path, pid_path, socket_path, argv):
    with open(log_path, "w") as log:
        process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("QEMU exited during startup; see its log")
        try:
            if running(socket_path):
                with open(pid_path, "w") as pid_file:
                    pid_file.write(str(process.pid))
                print(process.pid)
                return
        except (OSError, TimeoutError):
            pass
        time.sleep(0.2)
    os.killpg(process.pid, signal.SIGTERM)
    process.wait(timeout=5)
    raise TimeoutError("QEMU monitor did not report a running VM")


def stopped(pid):
    result = subprocess.run(["ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True, check=False)
    return not result.stdout.strip() or result.stdout.strip().startswith("Z")


def stop(socket_path, pid_path):
    with open(pid_path) as pid_file:
        pid = int(pid_file.read().strip())
    try:
        monitor(socket_path, "quit")
    except ConnectionError:
        pass
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if stopped(pid):
            print("stopped")
            return
        time.sleep(0.1)
    raise TimeoutError("QEMU did not exit after quit")


if __name__ == "__main__":
    action = sys.argv[1]
    if action == "monitor":
        print(monitor(sys.argv[2], " ".join(sys.argv[3:])))
    elif action == "launch":
        launch(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    elif action == "stop":
        stop(sys.argv[2], sys.argv[3])
    elif action == "running":
        raise SystemExit(0 if running(sys.argv[2]) else 1)
    else:
        raise ValueError(f"unknown action: {action}")
