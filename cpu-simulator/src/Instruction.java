/**
 * Represents a single CPU instruction with an opcode and operand.
 * Each instruction is stored as a 16-bit word:
 *   - Bits 12-15: opcode (4 bits, supports 16 opcodes)
 *   - Bits 0-11:  operand (12 bits, address or immediate value)
 */
public class Instruction {

    private final int opcode;
    private final int operand;

    public Instruction(int opcode, int operand) {
        this.opcode = opcode & 0xF;
        this.operand = operand & 0xFFF;
    }

    /**
     * Decodes a 16-bit machine word into an Instruction.
     */
    public static Instruction decode(int word) {
        int opcode = (word >> 12) & 0xF;
        int operand = word & 0xFFF;
        return new Instruction(opcode, operand);
    }

    /**
     * Encodes this instruction into a 16-bit machine word.
     */
    public int encode() {
        return (opcode << 12) | operand;
    }

    public int getOpcode() {
        return opcode;
    }

    public int getOperand() {
        return operand;
    }

    @Override
    public String toString() {
        return String.format("Instruction[opcode=0x%X, operand=0x%03X]", opcode, operand);
    }
}
