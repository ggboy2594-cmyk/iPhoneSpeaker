import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var receiver: AudioReceiver

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 54))
                .foregroundStyle(.blue)

            Text("iPhoneSpeaker")
                .font(.largeTitle.bold())

            Text(receiver.status)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("USB 音频接收端 · TCP 49152")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(receiver.isRunning ? "重新启动接收" : "启动接收") {
                receiver.start()
            }
            .buttonStyle(.borderedProminent)

            Text("请用 USB 连接 Windows，并在电脑运行 iproxy 49152 49152。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(28)
    }
}
