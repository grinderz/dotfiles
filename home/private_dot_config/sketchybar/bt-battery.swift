// Battery levels of the connected Bluetooth LE devices, read straight from
// their Battery Service (0x180F / 0x2A19) through CoreBluetooth: macOS
// shows them in its Bluetooth settings but publishes them nowhere a
// script can read (blueutil, system_profiler and ioreg all come back
// empty for a ZMK keyboard). Prints "<name>\t<percent>" per device;
// devices without the service are skipped. Needs the Bluetooth
// permission for the process that runs it (sketchybar). sketchybarrc
// compiles this into the cache dir.
import CoreBluetooth
import Foundation

let batteryService = CBUUID(string: "180F")
let batteryLevel = CBUUID(string: "2A19")

final class Reader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var pending = 0
    var peripherals: [CBPeripheral] = []

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func finish() { exit(0) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { if c.state != .unknown && c.state != .resetting { exit(1) }; return }
        peripherals = c.retrieveConnectedPeripherals(withServices: [batteryService])
        pending = peripherals.count
        if pending == 0 { finish() }
        for p in peripherals {
            p.delegate = self
            c.connect(p, options: nil)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([batteryService])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { done() }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == batteryService }) else { done(); return }
        p.discoverCharacteristics([batteryLevel], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first(where: { $0.uuid == batteryLevel }) else { done(); return }
        p.readValue(for: ch)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let v = ch.value, let b = v.first {
            print("\(p.name ?? "?")\t\(b)")
        }
        done()
    }

    func done() {
        pending -= 1
        if pending <= 0 { finish() }
    }
}

let reader = Reader()
// whatever happens, out within three seconds
DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
RunLoop.main.run()
