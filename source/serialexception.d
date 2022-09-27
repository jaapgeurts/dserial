module serialexception;
/** 
 * Exception class for dserial
 *
 * Author: Jaap Geurts
 * Date:   08-2022
 * 
 */

/** Exceptions for DSerialport */
class SerialException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) pure nothrow @nogc @safe
    {
        super(msg, file, line, nextInChain);
    }
}
