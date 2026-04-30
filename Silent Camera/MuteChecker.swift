//
//  MuteChecker.swift
//  Silent Camera
//
//  AudioServicesPlaySystemSoundWithCompletion の完了時間でマナーモードを判定する。
//  RBDMuteSwitch / Qiita の sadoru 氏の記事と同じロジック。
//
//  本実装ではランタイムで 200ms の無音 CAF を生成して使うため、
//  バンドルに音声ファイルを追加する必要がない。
//

import Foundation
import AudioToolbox
import QuartzCore

final class MuteChecker {
    static let shared = MuteChecker()

    private var soundID: SystemSoundID = 0

    private init() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mute_check.caf")
        if !FileManager.default.fileExists(atPath: url.path) {
            createSilentCAF(at: url, durationSeconds: 0.2)
        }
        AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
    }

    /// マナーモードかどうかを判定する。完了は MainActor 側で呼ばれる。
    func check(completion: @escaping (Bool) -> Void) {
        guard soundID != 0 else {
            completion(false)
            return
        }
        let startTime = CACurrentMediaTime()
        AudioServicesPlaySystemSoundWithCompletion(soundID) {
            let elapsed = CACurrentMediaTime() - startTime
            // 0.1 秒未満で完了 = iOS が無音化したのでマナーモード
            let isMuted = elapsed < 0.1
            DispatchQueue.main.async {
                completion(isMuted)
            }
        }
    }

    private func createSilentCAF(at url: URL, durationSeconds: Double) {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 22050,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var fileRef: AudioFileID?
        let status = AudioFileCreateWithURL(url as CFURL, kAudioFileCAFType, &asbd, .eraseFile, &fileRef)
        guard status == noErr, let file = fileRef else { return }
        let frameCount = UInt32(22050.0 * durationSeconds)
        var samples = [Int16](repeating: 0, count: Int(frameCount))
        var bytesToWrite: UInt32 = frameCount * 2
        AudioFileWriteBytes(file, false, 0, &bytesToWrite, &samples)
        AudioFileClose(file)
    }
}
