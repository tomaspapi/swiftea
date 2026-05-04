import CoreBluetooth

enum EmberGATT {
    static var service: CBUUID { CBUUID(string: "FC543622-236C-4C94-8FA9-944A3E5353FA") }
    static var currentTemperature: CBUUID { CBUUID(string: "FC540002-236C-4C94-8FA9-944A3E5353FA") }
    static var targetTemperature: CBUUID { CBUUID(string: "FC540003-236C-4C94-8FA9-944A3E5353FA") }
    static var contentsLevel: CBUUID { CBUUID(string: "FC540005-236C-4C94-8FA9-944A3E5353FA") }
    static var battery: CBUUID { CBUUID(string: "FC540007-236C-4C94-8FA9-944A3E5353FA") }
    static var liquidState: CBUUID { CBUUID(string: "FC540008-236C-4C94-8FA9-944A3E5353FA") }
    static var serialNumber: CBUUID { CBUUID(string: "FC54000D-236C-4C94-8FA9-944A3E5353FA") }
    static var pushEvent: CBUUID { CBUUID(string: "FC540012-236C-4C94-8FA9-944A3E5353FA") }
}
