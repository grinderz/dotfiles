// audio-device: the few CoreAudio operations macOS gives no CLI for.
//   list                         devices with uid, inputs/outputs
//   uid <name>                   the device UID screencapture -G wants
//   default-output [<name>]      print or set the system output device
//   create-aggregate <name> <uid> <sub uid...>   input aggregate (stacked: no)
//   create-multi-output <name> <uid> <sub uid...> output to several devices
//   destroy <uid>                remove an aggregate created here
import CoreAudio
import Foundation

func prop(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func devices() -> [AudioDeviceID] {
    var addr = prop(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
    return ids
}

func string(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String {
    var addr = prop(sel)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString? = nil
    let st = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0) }
    return st == noErr ? (value as String? ?? "") : ""
}

func channels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
    var addr = prop(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let buf = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
    defer { buf.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return 0 }
    return UnsafeMutableAudioBufferListPointer(buf).reduce(0) { $0 + Int($1.mNumberChannels) }
}

func find(_ name: String) -> AudioDeviceID? {
    devices().first { string($0, kAudioObjectPropertyName) == name || string($0, kAudioDevicePropertyDeviceUID) == name }
}

func defaultOutput() -> AudioDeviceID {
    var addr = prop(kAudioHardwarePropertyDefaultOutputDevice)
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
    var addr = prop(kAudioHardwarePropertyDefaultOutputDevice)
    var dev = id
    return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &dev) == noErr
}

func createAggregate(name: String, uid: String, subs: [String], stacked: Bool) -> Int32 {
    if find(uid) != nil { print("exists: \(uid)"); return 0 }
    let desc: [String: Any] = [
        kAudioAggregateDeviceNameKey: name,
        kAudioAggregateDeviceUIDKey: uid,
        kAudioAggregateDeviceIsStackedKey: stacked ? 1 : 0,   // stacked = multi-output
        kAudioAggregateDeviceMasterSubDeviceKey: subs[0],     // clock source: the first
        kAudioAggregateDeviceSubDeviceListKey: subs.map { [kAudioSubDeviceUIDKey: $0] },
    ]
    var id: AudioDeviceID = 0
    let st = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id)
    if st != noErr { fputs("create failed: \(st)\n", stderr); return 1 }
    print("created: \(uid)")
    return 0
}

let args = CommandLine.arguments.dropFirst()
switch args.first ?? "list" {
case "list":
    for id in devices() {
        print("\(string(id, kAudioObjectPropertyName))\t\(string(id, kAudioDevicePropertyDeviceUID))\tin:\(channels(id, kAudioObjectPropertyScopeInput)) out:\(channels(id, kAudioObjectPropertyScopeOutput))")
    }
case "uid":
    guard args.count >= 2, let id = find(args[args.startIndex + 1]) else { fputs("no such device\n", stderr); exit(1) }
    print(string(id, kAudioDevicePropertyDeviceUID))
case "default-output":
    if args.count >= 2 {
        guard let id = find(args[args.startIndex + 1]) else { fputs("no such device\n", stderr); exit(1) }
        exit(setDefaultOutput(id) ? 0 : 1)
    }
    print(string(defaultOutput(), kAudioObjectPropertyName))
case "create-aggregate", "create-multi-output":
    guard args.count >= 4 else { fputs("usage: \(args.first!) <name> <uid> <sub uid...>\n", stderr); exit(2) }
    let a = Array(args)
    exit(createAggregate(name: a[1], uid: a[2], subs: Array(a[3...]), stacked: a[0] == "create-multi-output"))
case "destroy":
    guard args.count >= 2, let id = find(args[args.startIndex + 1]) else { fputs("no such device\n", stderr); exit(1) }
    exit(AudioHardwareDestroyAggregateDevice(id) == noErr ? 0 : 1)
default:
    fputs("audio-device: list | uid <name> | default-output [<name>] | create-aggregate | create-multi-output | destroy\n", stderr); exit(2)
}
