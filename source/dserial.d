/**
 * A serial port library that support non blocking IO
 * Main class that encapsulates access to the serial port
 *
 * Examples:
 * ----------------
 * DSerial serialPort = new DSerial("/dev/ttyS0");
 * serialPort.setBlockingMode(DSerial.BlockingMode.TimedImmediately);
 * serialPort.setTimeout(200); // 200 millis
 * serialPort.open();
 * ubyte c;
 * // reading
 * while (serialPort.read(c) == 1) {
 *  // Do work
 * }
 * // writing
 * ubyte[] msgBuf = messageToBytes(msg);
 * return serialPort.write(msgBuf);
 * ---------------
 *
 * Author: Jaap Geurts
 * Date:   08-2022
 * v0.0.1: 08-2022
 * v0.0.2: 09-2023 Fixed baudrate bug
 *
 */

module dserial;

import std.string;
import std.conv;

import core.sys.posix.termios;
import core.sys.linux.termios;
import core.sys.posix.unistd;
import fcntl = core.sys.posix.fcntl;
import unistd = core.sys.posix.unistd;
import core.stdc.string;
import core.stdc.errno;

import serialexception;

/** Main class for performing serial port operations */
class DSerial {

    // dfmt off
    /** Parity of the connection */
    enum Parity { None, Even, Odd, Mark, Space }

    /** Number of bits per character */
    enum DataBits { DB5 = CS5, DB6 = CS6, DB7 = CS7, DB8 = CS8 }

    /** Number of stop bits per char transmission */
    enum StopBits { SB1, SB2 }

    enum BaudRate {
            B0     = 0,         /* hang up */
            B50    = 1,
            B75    = 2,
            B110   = 3,
            B134   = 4,
            B150   = 5,
            B200   = 6,
            B300   = 7,
            B600   = 10,
            B1200  = 11,
            B1800  = 12,
            B2400  = 13,
            B4800  = 14,
            B9600  = 14,
            B19200 = 15,
            B38400 = 17,
            B57600 = 0x1001,
            B115200 = 0x1002,
            B230400 = 0x1003,
            B460800 = 0x1004,
            B500000 = 0x1005,
            B576000 = 0x1006,
            B921600 = 0x1007,
            B1000000 = 0x1008,
            B1152000 = 0x1009,
            B1500000 = 0x100A,
            B2000000 = 0x100B,
            B2500000 = 0x100C,
            B3000000 = 0x100D,
            B3500000 = 0x100E,
            B4000000 = 0x100F
    }

    /** Set the port access mode to
    NonBlocking(never blocks),
    TimedImmediately(timer starts immediately),
    TimedAfterReceive(timer starts after receiving first char),
    Blocking(blocks forever) */
    enum BlockingMode
    {
        NonBlocking,
        TimedImmediately,
        TimedAfterReceive,
        Blocking,
    }
    // dfmt on

    private string deviceName;
    private DataBits dataBits;
    private Parity parity;
    private StopBits stopBits;
    private BaudRate baudRate;
    private BlockingMode blockingMode = BlockingMode.Blocking;
    private ubyte readTimeout = 5; // == 0.5 secs

    private bool isOpen = false;

    version (linux) {
        private int fd;
        private termios options;
    }

    /** Constructor. Creates object with default settings of 9600,8N1.
	Default is blocking read/write operations */
    this(string deviceName, BaudRate baudRate = BaudRate.B9600, DataBits dataBits = DataBits.DB8,
        Parity parity = Parity.None, StopBits stopBits = StopBits.SB1) {
        this.deviceName = deviceName;
        setOptions(baudRate, dataBits, parity, stopBits);
    }

    ~this() {
        close();
    }

    /** Set the options of the port. Is applied immediately if the port is already open */
    void setOptions(BaudRate baudRate, DataBits dataBits, Parity parity, StopBits stopBits) {
        this.baudRate = baudRate;
        this.dataBits = dataBits;
        this.parity = parity;
        this.stopBits = stopBits;
        // apply immediately if the port is already open
        if (isOpen)
            applyOptions();
    }

    /** Sets read timeout in millis. On linux only increments of 100ms are available.
  Timeout maximum is 255000 = 25.5secs */
    void setTimeout(uint millis) {
        readTimeout = cast(ubyte)(millis / 100);
        if (isOpen && (blockingMode == BlockingMode.TimedImmediately
                || blockingMode == BlockingMode.TimedAfterReceive)) // reapply so that the timeout
            applyBlockingMode();
    }

    /** Apply the options to the connection. Note: only call this when the port is already open */
    private void applyOptions() {
        if (!isOpen)
            throw new SerialException("Can't apply options on closed connection");
        // TODO: check error codes
        // set attributes
        version (linux) {
            tcgetattr(fd, &options);

            // baud rate
            cfsetispeed(&options, baudRate);
            cfsetospeed(&options, baudRate);

            // disable IGNBRK for mismatched speed tests; otherwise receive break
            // as \000 chars
            options.c_iflag &= ~(IGNBRK|BRKINT|PARMRK|ISTRIP|INLCR|IGNCR|ICRNL); // disable break processing
            options.c_iflag &= ~(IXON | IXOFF | IXANY); // shut off xon/xoff ctrl
            // TODO: these flags should be unset. not set to 0
            options.c_lflag &= ~(ICANON|ECHO|ECHOE|ECHONL|ISIG); // no signaling chars, no echo,
            // no canonical processing(reading lines)

            options.c_cflag |= (CLOCAL | CREAD); // ignore modem controls, enable reading

            // set databits
            options.c_cflag &= ~CSIZE; // clear field first
            options.c_cflag |= dataBits;

            // parity
            final switch (parity) {
            case Parity.None:
                options.c_cflag &= ~(PARENB | PARODD);
                break;
            case Parity.Even:
                options.c_cflag |= PARENB;
                break;
            case Parity.Odd:
                options.c_cflag |= (PARENB | PARODD);
                break;
            case Parity.Mark:
                options.c_cflag |= (PARENB | PARODD | PARMRK);
                break;
            case Parity.Space:
                options.c_cflag |= (PARENB | PARMRK);
                break;
            }
            // stop bits
            final switch (stopBits) {
            case StopBits.SB1:
                options.c_cflag &= ~CSTOPB;
                break;
            case StopBits.SB2:
                options.c_cflag |= CSTOPB;
                break;
            }

            options.c_cflag &= ~CRTSCTS; // disable crtscts

            options.c_oflag &= ~OPOST;  // Prevent special interpretation of output bytes (e.g. newline chars)
            options.c_oflag &= ~ONLCR; // Prevent conversion of newline to carriage return/line feed

            // TODO: check error codes
            tcsetattr(fd, TCSANOW, &options);
        }

    }

    /** Apply blocking mode settings to the connection. Don't apply on closed connections */
    private void applyBlockingMode() {
        if (!isOpen)
            throw new SerialException("Can't apply blocking mode on closed connection");

        version (linux) {
            final switch (blockingMode) {
            case BlockingMode.NonBlocking:
                options.c_cc[VMIN] = 0; // read doesn't block
                options.c_cc[VTIME] = 0; // don't wait for timeout
                break;
            case BlockingMode.TimedImmediately:
                options.c_cc[VMIN] = 0; // read doesn't block, only timeout
                options.c_cc[VTIME] = readTimeout;
                break;
            case BlockingMode.TimedAfterReceive:
                options.c_cc[VMIN] = 1; // blocks until at least 1 byte
                options.c_cc[VTIME] = readTimeout;
                break;
            case BlockingMode.Blocking:
                options.c_cc[VMIN] = 1; // blocks until at least 1 byte
                options.c_cc[VTIME] = 0;
                break;
            }
            tcsetattr(fd, TCSANOW, &options);
        }
    }

    /** set blocking mode for operations */
    void setBlockingMode(BlockingMode mode) {
        blockingMode = mode;
        if (isOpen)
            applyBlockingMode();
    }

    /** Opens the serial port with current settings. Throws an exception if the port can't be opened */
    void open() {

        version (linux) {
            // open the port
            fd = fcntl.open(deviceName.toStringz(), fcntl.O_RDWR | fcntl.O_NOCTTY);
            if (fd == -1) {
                throw new SerialException("Can't open device '" ~ deviceName ~ "'");
            }
        }

        isOpen = true;

        applyOptions();
        applyBlockingMode();
    }

    /** Closes the serial port */
    void close() {
        if (!isOpen)
            return;

        version (linux) {
            unistd.close(fd);
        }
        isOpen = false;
    }

    /** convenience function. reads a single byte */
    ulong read(ref ubyte data) {
        return read(&data, 1);
    }

    /** convenience function. Reads up to data.length bytes*/
    ulong read(ubyte[] data) {
        return read(data.ptr, data.length);
    }

    /** Reads data into the bytes array.
      Blocks until at least one char has been read.
      Returns:
        positive number of bytes read
      throws exception upon error */
    ulong read(ubyte* data, ulong length) {

        if (!isOpen)
            throw new SerialException("Attempted read from closed port.");

        long n;
        version (linux) {
            n = unistd.read(fd, data, length);
            // TODO: check read return values and return appropriate result
            if (n < 0)
                throw new SerialException(to!string(strerror(errno).fromStringz));
            else if (blockingMode == BlockingMode.Blocking && n == 0) // TODO: check if blockingmode == timedimmediately
                throw new SerialException("Error: probably device removal");
        }
        return n;
    }

    /** Write bytes to the serial port
    returns bytes written,
    Only supports blocking and nonblocking writes.
    Timed writes are unsupported. */
    long write(const ubyte[] bytes) {
        long n;
        version (linux) {
            n = unistd.write(fd, bytes.ptr, bytes.length);
            //
            if (blockingMode == BlockingMode.Blocking) {
                tcdrain(fd);
            }
        }

        return n;
    }
}
