import argparse
import socket
import struct
import sys
import time

import numpy as np
import soundcard as sc

HOST = "127.0.0.1"
PORT = 49152
RATE = 48000
CHANNELS = 2
FRAMES = 480  # 10 ms
BYTES_PER_FRAME = CHANNELS * 2


def list_devices():
    devices = sc.all_microphones(include_loopback=True)
    for index, device in enumerate(devices):
        print(f"[{index}] {device.name} (loopback={getattr(device, 'isloopback', 'unknown')})")


def choose_loopback(name=None):
    devices = sc.all_microphones(include_loopback=True)
    if name:
        matches = [d for d in devices if d.name == name]
        if not matches:
            raise RuntimeError(f"找不到设备: {name!r}。请使用 --list 查看名称。")
        return matches[0]
    loopbacks = [d for d in devices if getattr(d, "isloopback", False)]
    if loopbacks:
        return loopbacks[0]
    # Some SoundCard/driver combinations don't expose isloopback consistently.
    named = [d for d in devices if "loopback" in d.name.lower() or "扬声器" in d.name or "speaker" in d.name.lower()]
    if named:
        return named[0]
    raise RuntimeError("没有找到系统声音回环设备。运行 python host.py --list 查看设备。")


def pcm16_payload(samples):
    samples = np.asarray(samples, dtype=np.float32)
    if samples.ndim == 1:
        samples = np.column_stack((samples, samples))
    if samples.shape[1] == 1:
        samples = np.repeat(samples, 2, axis=1)
    elif samples.shape[1] > 2:
        samples = samples[:, :2]
    samples = np.clip(samples, -1.0, 1.0)
    return (samples * 32767.0).astype("<i2", copy=False).tobytes()


def send_all(sock, payload):
    sock.sendall(struct.pack(">I", len(payload)))
    sock.sendall(payload)


def main():
    parser = argparse.ArgumentParser(description="iPhoneSpeaker Windows USB audio sender")
    parser.add_argument("--device", help="Exact loopback device name")
    parser.add_argument("--list", action="store_true", help="List capture devices and exit")
    parser.add_argument("--host", default=HOST, help="iproxy local host (default 127.0.0.1)")
    parser.add_argument("--port", type=int, default=PORT)
    args = parser.parse_args()

    if args.list:
        list_devices()
        return

    device = choose_loopback(args.device)
    print(f"音频来源: {device.name}")
    print(f"连接目标: {args.host}:{args.port}")
    print("请确认 iPhoneSpeaker 已打开，并且 iproxy 已运行。")

    while True:
        try:
            with socket.create_connection((args.host, args.port), timeout=5) as sock:
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                print("USB 音频通道已连接，开始传输。Ctrl+C 停止。")
                with device.recorder(samplerate=RATE, channels=CHANNELS, blocksize=FRAMES) as recorder:
                    while True:
                        audio = recorder.record(numframes=FRAMES)
                        payload = pcm16_payload(audio)
                        if len(payload) != FRAMES * BYTES_PER_FRAME:
                            continue
                        send_all(sock, payload)
        except KeyboardInterrupt:
            print("\n已停止。")
            return
        except (OSError, RuntimeError) as exc:
            print(f"连接/采集错误: {exc}")
            print("3 秒后重试；Ctrl+C 退出。")
            time.sleep(3)


if __name__ == "__main__":
    main()
