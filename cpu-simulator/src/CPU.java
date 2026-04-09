/**
 * Central Processing Unit (CPU) simulator.
 *
 * Implements the fetch-decode-execute cycle with a 16-instruction set.
 * Each instruction is a 16-bit word: [opcode (4 bits)][operand (12 bits)].
 *
 * Instruction Set:
 *   0x0 HLT         - Halt the CPU
 *   0x1 LDA addr    - Load value from memory[addr] into AC
 *   0x2 STA addr    - Store AC into memory[addr]
 *   0x3 ADD addr    - AC = AC + memory[addr]
 *   0x4 SUB addr    - AC = AC - memory[addr]
 *   0x5 MUL addr    - AC = AC * memory[addr]
 *   0x6 DIV addr    - AC = AC / memory[addr]
 *   0x7 AND addr    - AC = AC & memory[addr]
 *   0x8 OR  addr    - AC = AC | memory[addr]
 *   0x9 NOT         - AC = ~AC
 *   0xA SHL         - AC = AC << 1
 *   0xB SHR         - AC = AC >> 1
 *   0xC JMP addr    - Unconditional jump to addr
 *   0xD JZ  addr    - Jump to addr if Zero flag is set
 *   0xE JN  addr    - Jump to addr if Negative flag is set
 *   0xF INP imm     - Load immediate value into AC
 */
public class CPU {

    // Opcodes
    public static final int OP_HLT = 0x0;
    public static final int OP_LDA = 0x1;
    public static final int OP_STA = 0x2;
    public static final int OP_ADD = 0x3;
    public static final int OP_SUB = 0x4;
    public static final int OP_MUL = 0x5;
    public static final int OP_DIV = 0x6;
    public static final int OP_AND = 0x7;
    public static final int OP_OR  = 0x8;
    public static final int OP_NOT = 0x9;
    public static final int OP_SHL = 0xA;
    public static final int OP_SHR = 0xB;
    public static final int OP_JMP = 0xC;
    public static final int OP_JZ  = 0xD;
    public static final int OP_JN  = 0xE;
    public static final int OP_INP = 0xF;

    private static final String[] MNEMONIC = {
        "HLT", "LDA", "STA", "ADD", "SUB", "MUL", "DIV", "AND",
        "OR",  "NOT", "SHL", "SHR", "JMP", "JZ",  "JN",  "INP"
    };

    private final Registers regs;
    private final Memory memory;
    private boolean running;
    private boolean verbose;
    private int cycleCount;

    public CPU(Memory memory) {
        this.regs = new Registers();
        this.memory = memory;
        this.running = false;
        this.verbose = true;
        this.cycleCount = 0;
    }

    /**
     * Enables or disables verbose output during execution.
     */
    public void setVerbose(boolean verbose) {
        this.verbose = verbose;
    }

    /**
     * Resets the CPU to its initial state.
     */
    public void reset() {
        regs.reset();
        running = false;
        cycleCount = 0;
    }

    /**
     * Runs the fetch-decode-execute cycle until a HLT instruction
     * or maximum cycle count is reached.
     */
    public void run() {
        run(10000); // default max cycles to prevent infinite loops
    }

    /**
     * Runs the fetch-decode-execute cycle with a specified maximum cycle count.
     */
    public void run(int maxCycles) {
        running = true;
        cycleCount = 0;

        if (verbose) {
            System.out.println("╔══════════════════════════════════════════════╗");
            System.out.println("║          CPU SIMULATOR - STARTING           ║");
            System.out.println("╚══════════════════════════════════════════════╝");
            System.out.println();
        }

        while (running && cycleCount < maxCycles) {
            cycleCount++;
            if (verbose) {
                System.out.println("── Cycle " + cycleCount + " ──────────────────────────────");
            }

            // FETCH
            int word = fetch();

            // DECODE
            Instruction instr = decode(word);

            // EXECUTE
            execute(instr);

            if (verbose) {
                System.out.println();
            }
        }

        if (cycleCount >= maxCycles && running) {
            System.out.println("⚠ CPU halted: maximum cycle count (" + maxCycles + ") reached.");
            running = false;
        }

        if (verbose) {
            System.out.println("╔══════════════════════════════════════════════╗");
            System.out.println("║        CPU HALTED after " + String.format("%-5d", cycleCount) + " cycles        ║");
            System.out.println("╚══════════════════════════════════════════════╝");
            System.out.println();
            System.out.println(regs.dump());
        }
    }

    // ─── FETCH ───────────────────────────────────────────────

    /**
     * Fetches the next instruction word from memory at the address
     * pointed to by the Program Counter (PC).
     */
    private int fetch() {
        int pc = regs.getPC();
        regs.setMAR(pc);

        int word = memory.read(pc);
        regs.setMDR(word);
        regs.setIR(word);
        regs.incrementPC();

        if (verbose) {
            System.out.printf("  FETCH:   PC=0x%03X -> word=0x%04X%n", pc, word);
        }

        return word;
    }

    // ─── DECODE ──────────────────────────────────────────────

    /**
     * Decodes a 16-bit machine word into an Instruction object.
     */
    private Instruction decode(int word) {
        Instruction instr = Instruction.decode(word);

        if (verbose) {
            String mnemonic = MNEMONIC[instr.getOpcode()];
            System.out.printf("  DECODE:  %s 0x%03X%n", mnemonic, instr.getOperand());
        }

        return instr;
    }

    // ─── EXECUTE ─────────────────────────────────────────────

    /**
     * Executes a decoded instruction.
     */
    private void execute(Instruction instr) {
        int opcode = instr.getOpcode();
        int operand = instr.getOperand();
        int ac = regs.getAC();
        int memValue;

        switch (opcode) {
            case OP_HLT: // Halt
                running = false;
                if (verbose) System.out.println("  EXECUTE: HLT - CPU stopped");
                return;

            case OP_LDA: // Load from memory
                memValue = memory.read(operand);
                regs.setAC(memValue);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: LDA [0x%03X] -> AC = 0x%04X (%d)%n",
                    operand, memValue, memValue);
                break;

            case OP_STA: // Store to memory
                memory.write(operand, ac);
                if (verbose) System.out.printf("  EXECUTE: STA [0x%03X] <- AC = 0x%04X (%d)%n",
                    operand, ac, ac);
                break;

            case OP_ADD: // Add
                memValue = memory.read(operand);
                int addResult = ALU.add(ac, memValue, regs);
                regs.setAC(addResult);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: ADD [0x%03X]=%d -> AC = %d + %d = %d%n",
                    operand, memValue, ac, memValue, addResult);
                break;

            case OP_SUB: // Subtract
                memValue = memory.read(operand);
                int subResult = ALU.subtract(ac, memValue, regs);
                regs.setAC(subResult);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: SUB [0x%03X]=%d -> AC = %d - %d = %d%n",
                    operand, memValue, ac, memValue, subResult);
                break;

            case OP_MUL: // Multiply
                memValue = memory.read(operand);
                int mulResult = ALU.multiply(ac, memValue, regs);
                regs.setAC(mulResult);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: MUL [0x%03X]=%d -> AC = %d * %d = %d%n",
                    operand, memValue, ac, memValue, mulResult);
                break;

            case OP_DIV: // Divide
                memValue = memory.read(operand);
                int divResult = ALU.divide(ac, memValue, regs);
                regs.setAC(divResult);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: DIV [0x%03X]=%d -> AC = %d / %d = %d%n",
                    operand, memValue, ac, memValue, divResult);
                break;

            case OP_AND: // Bitwise AND
                memValue = memory.read(operand);
                int andResult = ALU.and(ac, memValue, regs);
                regs.setAC(andResult);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: AND [0x%03X]=0x%04X -> AC = 0x%04X%n",
                    operand, memValue, andResult);
                break;

            case OP_OR: // Bitwise OR
                memValue = memory.read(operand);
                int orResult = ALU.or(ac, memValue, regs);
                regs.setAC(orResult);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: OR  [0x%03X]=0x%04X -> AC = 0x%04X%n",
                    operand, memValue, orResult);
                break;

            case OP_NOT: // Bitwise NOT
                int notResult = ALU.not(ac, regs);
                regs.setAC(notResult);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: NOT -> AC = ~0x%04X = 0x%04X%n",
                    ac, notResult);
                break;

            case OP_SHL: // Shift left
                int shlResult = ALU.shiftLeft(ac, regs);
                regs.setAC(shlResult);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: SHL -> AC = 0x%04X << 1 = 0x%04X%n",
                    ac, shlResult);
                break;

            case OP_SHR: // Shift right
                int shrResult = ALU.shiftRight(ac, regs);
                regs.setAC(shrResult);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: SHR -> AC = 0x%04X >> 1 = 0x%04X%n",
                    ac, shrResult);
                break;

            case OP_JMP: // Unconditional jump
                regs.setPC(operand);
                if (verbose) System.out.printf("  EXECUTE: JMP -> PC = 0x%03X%n", operand);
                break;

            case OP_JZ: // Jump if zero
                if (regs.getFlag(Registers.FLAG_ZERO)) {
                    regs.setPC(operand);
                    if (verbose) System.out.printf("  EXECUTE: JZ  -> Zero flag SET, jumping to 0x%03X%n", operand);
                } else {
                    if (verbose) System.out.println("  EXECUTE: JZ  -> Zero flag CLEAR, no jump");
                }
                break;

            case OP_JN: // Jump if negative
                if (regs.getFlag(Registers.FLAG_NEGATIVE)) {
                    regs.setPC(operand);
                    if (verbose) System.out.printf("  EXECUTE: JN  -> Negative flag SET, jumping to 0x%03X%n", operand);
                } else {
                    if (verbose) System.out.println("  EXECUTE: JN  -> Negative flag CLEAR, no jump");
                }
                break;

            case OP_INP: // Load immediate value
                regs.setAC(operand);
                regs.updateFlags();
                if (verbose) System.out.printf("  EXECUTE: INP -> AC = 0x%03X (%d)%n",
                    operand, operand);
                break;

            default:
                throw new IllegalStateException("Unknown opcode: 0x" + Integer.toHexString(opcode));
        }
    }

    // ─── PUBLIC ACCESSORS ────────────────────────────────────

    public Registers getRegisters() { return regs; }
    public Memory getMemory() { return memory; }
    public boolean isRunning() { return running; }
    public int getCycleCount() { return cycleCount; }

    /**
     * Returns the mnemonic string for a given opcode.
     */
    public static String getMnemonic(int opcode) {
        if (opcode >= 0 && opcode < MNEMONIC.length) {
            return MNEMONIC[opcode];
        }
        return "???";
    }

    /**
     * Disassembles a region of memory into human-readable instructions.
     */
    public String disassemble(int startAddr, int endAddr) {
        StringBuilder sb = new StringBuilder();
        sb.append("Disassembly:\n");
        sb.append("─".repeat(40)).append("\n");
        for (int addr = startAddr; addr <= endAddr; addr++) {
            int word = memory.read(addr);
            Instruction instr = Instruction.decode(word);
            String mnemonic = MNEMONIC[instr.getOpcode()];
            sb.append(String.format("  0x%03X:  0x%04X  %s 0x%03X%n",
                addr, word, mnemonic, instr.getOperand()));
        }
        return sb.toString();
    }
}
