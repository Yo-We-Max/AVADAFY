/**
 * Simulates main memory (RAM) for the CPU.
 * Memory is word-addressable with 16-bit words.
 * Default size: 4096 words (addressable with 12-bit operands).
 */
public class Memory {

    private final int[] data;
    private final int size;

    public Memory(int size) {
        this.size = size;
        this.data = new int[size];
    }

    public Memory() {
        this(4096);
    }

    /**
     * Reads a 16-bit word from the given address.
     */
    public int read(int address) {
        validateAddress(address);
        return data[address];
    }

    /**
     * Writes a 16-bit word to the given address.
     */
    public void write(int address, int value) {
        validateAddress(address);
        data[address] = value & 0xFFFF;
    }

    /**
     * Loads a program (array of machine words) into memory starting at address 0.
     */
    public void loadProgram(int[] program) {
        if (program.length > size) {
            throw new IllegalArgumentException(
                "Program size (" + program.length + ") exceeds memory size (" + size + ")");
        }
        System.arraycopy(program, 0, data, 0, program.length);
    }

    /**
     * Returns a formatted dump of memory from startAddr to endAddr (inclusive).
     */
    public String dump(int startAddr, int endAddr) {
        StringBuilder sb = new StringBuilder();
        sb.append(String.format("Memory Dump [0x%03X - 0x%03X]:%n", startAddr, endAddr));
        sb.append("─".repeat(35)).append("\n");
        for (int i = startAddr; i <= endAddr && i < size; i++) {
            sb.append(String.format("  [0x%03X]  0x%04X  (%5d)%n", i, data[i], data[i]));
        }
        return sb.toString();
    }

    public int getSize() {
        return size;
    }

    /**
     * Clears all memory to zero.
     */
    public void clear() {
        java.util.Arrays.fill(data, 0);
    }

    private void validateAddress(int address) {
        if (address < 0 || address >= size) {
            throw new IllegalArgumentException(
                "Memory address out of bounds: 0x" + Integer.toHexString(address)
                + " (valid range: 0x000 - 0x" + Integer.toHexString(size - 1) + ")");
        }
    }
}
