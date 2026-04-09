/**
 * Simulates the CPU register file.
 *
 * Registers:
 *   AC  - Accumulator: main working register for arithmetic/logic
 *   PC  - Program Counter: address of the next instruction to fetch
 *   IR  - Instruction Register: holds the currently fetched instruction
 *   MAR - Memory Address Register: holds the address for memory access
 *   MDR - Memory Data Register: holds data read from or to be written to memory
 *   FLAGS - Status flags (Zero, Negative, Carry, Overflow)
 */
public class Registers {

    // Flag bit positions
    public static final int FLAG_ZERO     = 0;
    public static final int FLAG_NEGATIVE = 1;
    public static final int FLAG_CARRY    = 2;
    public static final int FLAG_OVERFLOW = 3;

    private int ac;    // Accumulator
    private int pc;    // Program Counter
    private int ir;    // Instruction Register
    private int mar;   // Memory Address Register
    private int mdr;   // Memory Data Register
    private int flags; // Status flags

    public Registers() {
        reset();
    }

    public void reset() {
        ac = 0;
        pc = 0;
        ir = 0;
        mar = 0;
        mdr = 0;
        flags = 0;
    }

    // --- Accumulator ---
    public int getAC() { return ac; }
    public void setAC(int value) { this.ac = value & 0xFFFF; }

    // --- Program Counter ---
    public int getPC() { return pc; }
    public void setPC(int value) { this.pc = value & 0xFFF; }
    public void incrementPC() { this.pc = (this.pc + 1) & 0xFFF; }

    // --- Instruction Register ---
    public int getIR() { return ir; }
    public void setIR(int value) { this.ir = value & 0xFFFF; }

    // --- Memory Address Register ---
    public int getMAR() { return mar; }
    public void setMAR(int value) { this.mar = value & 0xFFF; }

    // --- Memory Data Register ---
    public int getMDR() { return mdr; }
    public void setMDR(int value) { this.mdr = value & 0xFFFF; }

    // --- Flags ---
    public int getFlags() { return flags; }

    public boolean getFlag(int flagBit) {
        return (flags & (1 << flagBit)) != 0;
    }

    public void setFlag(int flagBit, boolean value) {
        if (value) {
            flags |= (1 << flagBit);
        } else {
            flags &= ~(1 << flagBit);
        }
    }

    /**
     * Updates Zero and Negative flags based on the accumulator value.
     */
    public void updateFlags() {
        setFlag(FLAG_ZERO, ac == 0);
        setFlag(FLAG_NEGATIVE, (ac & 0x8000) != 0);
    }

    /**
     * Returns a formatted display of all register values.
     */
    public String dump() {
        StringBuilder sb = new StringBuilder();
        sb.append("Register State:\n");
        sb.append("─".repeat(40)).append("\n");
        sb.append(String.format("  AC  = 0x%04X  (%5d)%n", ac, toSigned(ac)));
        sb.append(String.format("  PC  = 0x%03X   (%5d)%n", pc, pc));
        sb.append(String.format("  IR  = 0x%04X%n", ir));
        sb.append(String.format("  MAR = 0x%03X%n", mar));
        sb.append(String.format("  MDR = 0x%04X%n", mdr));
        sb.append(String.format("  Flags: Z=%d N=%d C=%d V=%d%n",
            getFlag(FLAG_ZERO) ? 1 : 0,
            getFlag(FLAG_NEGATIVE) ? 1 : 0,
            getFlag(FLAG_CARRY) ? 1 : 0,
            getFlag(FLAG_OVERFLOW) ? 1 : 0));
        return sb.toString();
    }

    private int toSigned(int val) {
        if ((val & 0x8000) != 0) {
            return val - 0x10000;
        }
        return val;
    }
}
