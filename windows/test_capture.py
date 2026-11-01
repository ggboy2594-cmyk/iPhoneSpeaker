
import soundcard as sc
import numpy as np

name = "扬声器 (Realtek(R) Audio Codec with THX Spatial Audio)"

devices = sc.all_microphones(include_loopback=True)
device = next((d for d in devices if d.name == name), None)

if device is None:
    print("没有找到 Realtek 回环设备")
    exit()

print("正在采集：", device.name)
print("请现在播放一段音乐或视频...")

with device.recorder(samplerate=48000, channels=2) as recorder:
    for i in range(10):
        audio = recorder.record(numframes=4800)
        peak = np.max(np.abs(audio))
        rms = np.sqrt(np.mean(audio ** 2))
        print(f"第 {i+1} 秒：Peak={peak:.5f}, RMS={rms:.5f}")

print("采集测试完成")
