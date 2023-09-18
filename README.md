# dserial

A serial port library (for Linux) that supports non blocking IO

## Example usage

Default (blocking usage)
```D
import dserial;

DSerial serialPort = new DSerial("/dev/ttyUSB0",DSerial.BaudRate.B115200);
serialPort.open();
// writing
ubyte[] msgBuf = messageToBytes(msg);
return serialPort.write(msgBuf);
```

Non blocking usage
```D
import dserial;

// Non blocking usage
DSerial serialPort = new DSerial("/dev/ttyS0");
serialPort.setBlockingMode(DSerial.BlockingMode.TimedImmediately);
serialPort.setTimeout(200); // 200 millis
serialPort.open();
ubyte c;
// reading (will return after 200ms if nothing available)
// read returns number of chars read and modifies c
while (serialPort.read(c) == 1) {
  // do work with c
}
 ```
