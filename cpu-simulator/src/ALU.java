/**
 * Arithmetic Logic Unit (ALU).
 * Performs arithmetic and logic operations and updates CPU flags.
 */
public class ALU {

    /**
     * Adds two 16-bit values. Updates carry and overflow flags.
     */
    public static int add(int a, int b, Registers regs) {
        int result = a + b;
        regs.setFlag(Registers.FLAG_CARRY, result > 0xFFFF);

        // Overflow: sign of result differs from both operands
        boolean signA = (a & 0x8000) != 0;
        boolean signB = (b & 0x8000) != 0;
        boolean signR = (result & 0x8000) != 0;
        regs.setFlag(Registers.FLAG_OVERFLOW, (signA == signB) && (signA != signR));

        return result & 0xFFFF;
    }

    /**
     * Subtracts b from a (a - b). Updates carry (borrow) and overflow flags.
     */
    public static int subtract(int a, int b, Registers regs) {
        int result = a - b;
        regs.setFlag(Registers.FLAG_CARRY, result < 0);

        boolean signA = (a & 0x8000) != 0;
        boolean signB = (b & 0x8000) != 0;
        boolean signR = (result & 0x8000) != 0;
        regs.setFlag(Registers.FLAG_OVERFLOW, (signA != signB) && (signB == signR));

        return result & 0xFFFF;
    }

    /**
     * Multiplies two 16-bit values. Returns lower 16 bits.
     */
    public static int multiply(int a, int b, Registers regs) {
        int result = a * b;
        regs.setFlag(Registers.FLAG_CARRY, false);
        regs.setFlag(Registers.FLAG_OVERFLOW, result > 0xFFFF);
        return result & 0xFFFF;
    }

    /**
     * Divides a by b (integer division). Throws on division by zero.
     */
    public static int divide(int a, int b, Registers regs) {
        if (b == 0) {
            throw new ArithmeticException("Division by zero at runtime");
        }
        int result = a / b;
        regs.setFlag(Registers.FLAG_CARRY, false);
        regs.setFlag(Registers.FLAG_OVERFLOW, false);
        return result & 0xFFFF;
    }

    /**
     * Bitwise AND.
     */
    public static int and(int a, int b, Registers regs) {
        int result = a & b;
        regs.setFlag(Registers.FLAG_CARRY, false);
        regs.setFlag(Registers.FLAG_OVERFLOW, false);
        return result & 0xFFFF;
    }

    /**
     * Bitwise OR.
     */
    public static int or(int a, int b, Registers regs) {
        int result = a | b;
        regs.setFlag(Registers.FLAG_CARRY, false);
        regs.setFlag(Registers.FLAG_OVERFLOW, false);
        return result & 0xFFFF;
    }

    /**
     * Bitwise NOT (one's complement).
     */
    public static int not(int a, Registers regs) {
        int result = ~a & 0xFFFF;
        regs.setFlag(Registers.FLAG_CARRY, false);
        regs.setFlag(Registers.FLAG_OVERFLOW, false);
        return result;
    }

    /**
     * Logical shift left by 1 bit.
     */
    public static int shiftLeft(int a, Registers regs) {
        regs.setFlag(Registers.FLAG_CARRY, (a & 0x8000) != 0);
        int result = (a << 1) & 0xFFFF;
        regs.setFlag(Registers.FLAG_OVERFLOW, false);
        return result;
    }

    /**
     * Logical shift right by 1 bit.
     */
    public static int shiftRight(int a, Registers regs) {
        regs.setFlag(Registers.FLAG_CARRY, (a & 0x1) != 0);
        int result = (a >> 1) & 0xFFFF;
        regs.setFlag(Registers.FLAG_OVERFLOW, false);
        return result;
    }
}
