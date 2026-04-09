/**
 * Main entry point for the CPU Simulator.
 * Demonstrates the fetch-decode-execute cycle with several sample programs.
 */
public class CPUSimulator {

    public static void main(String[] args) {
        System.out.println();
        System.out.println("╔══════════════════════════════════════════════════════════╗");
        System.out.println("║              AVADAFY CPU SIMULATOR v1.0                  ║");
        System.out.println("║         Fetch - Decode - Execute Cycle Demo              ║");
        System.out.println("╚══════════════════════════════════════════════════════════╝");
        System.out.println();

        printInstructionSet();

        // Run each demo program
        demoBasicArithmetic();
        demoCountdown();
        demoMultiplyByRepeatedAddition();
        demoBitwiseOperations();
    }

    /**
     * Prints the full instruction set reference.
     */
    private static void printInstructionSet() {
        System.out.println("┌──────────────────────────────────────────────────────────┐");
        System.out.println("│                   INSTRUCTION SET                        │");
        System.out.println("├────────┬──────────┬─────────────────────────────────────┤");
        System.out.println("│ Opcode │ Mnemonic │ Description                         │");
        System.out.println("├────────┼──────────┼─────────────────────────────────────┤");
        System.out.println("│  0x0   │ HLT      │ Halt the CPU                        │");
        System.out.println("│  0x1   │ LDA addr │ Load memory[addr] into AC           │");
        System.out.println("│  0x2   │ STA addr │ Store AC into memory[addr]          │");
        System.out.println("│  0x3   │ ADD addr │ AC = AC + memory[addr]              │");
        System.out.println("│  0x4   │ SUB addr │ AC = AC - memory[addr]              │");
        System.out.println("│  0x5   │ MUL addr │ AC = AC * memory[addr]              │");
        System.out.println("│  0x6   │ DIV addr │ AC = AC / memory[addr]              │");
        System.out.println("│  0x7   │ AND addr │ AC = AC & memory[addr] (bitwise)    │");
        System.out.println("│  0x8   │ OR  addr │ AC = AC | memory[addr] (bitwise)    │");
        System.out.println("│  0x9   │ NOT      │ AC = ~AC (bitwise complement)       │");
        System.out.println("│  0xA   │ SHL      │ AC = AC << 1 (shift left)           │");
        System.out.println("│  0xB   │ SHR      │ AC = AC >> 1 (shift right)          │");
        System.out.println("│  0xC   │ JMP addr │ Jump to addr (unconditional)        │");
        System.out.println("│  0xD   │ JZ  addr │ Jump to addr if Zero flag set       │");
        System.out.println("│  0xE   │ JN  addr │ Jump to addr if Negative flag set   │");
        System.out.println("│  0xF   │ INP imm  │ Load immediate value into AC        │");
        System.out.println("└────────┴──────────┴─────────────────────────────────────┘");
        System.out.println();
    }

    // ─── HELPER: build instruction word ──────────────────────

    private static int instr(int opcode, int operand) {
        return (opcode << 12) | (operand & 0xFFF);
    }

    // ─── DEMO 1: Basic Arithmetic ────────────────────────────

    /**
     * Computes: result = (10 + 25) - 5 = 30
     * Stores the result in memory address 0x103.
     */
    private static void demoBasicArithmetic() {
        System.out.println("━".repeat(60));
        System.out.println("  DEMO 1: Basic Arithmetic   ->  (10 + 25) - 5 = 30");
        System.out.println("━".repeat(60));
        System.out.println();

        Memory mem = new Memory();
        CPU cpu = new CPU(mem);

        // Program: compute (10 + 25) - 5 and store result
        //   Address 0x100 = 10 (data)
        //   Address 0x101 = 25 (data)
        //   Address 0x102 = 5  (data)
        //   Address 0x103 = result (data)
        int[] program = {
            instr(CPU.OP_LDA, 0x100),  // 0x000: Load 10 into AC
            instr(CPU.OP_ADD, 0x101),  // 0x001: AC = 10 + 25 = 35
            instr(CPU.OP_SUB, 0x102),  // 0x002: AC = 35 - 5 = 30
            instr(CPU.OP_STA, 0x103),  // 0x003: Store result at 0x103
            instr(CPU.OP_HLT, 0x000), // 0x004: Halt
        };

        mem.loadProgram(program);
        mem.write(0x100, 10);  // operand A
        mem.write(0x101, 25);  // operand B
        mem.write(0x102, 5);   // operand C

        System.out.println("Program loaded. Data: mem[0x100]=10, mem[0x101]=25, mem[0x102]=5");
        System.out.println();

        cpu.run();

        System.out.println(mem.dump(0x100, 0x103));
        System.out.println();
    }

    // ─── DEMO 2: Countdown Loop ─────────────────────────────

    /**
     * Counts down from 5 to 0 using a loop with conditional jump.
     * Demonstrates: INP, SUB, JZ, JMP instructions.
     */
    private static void demoCountdown() {
        System.out.println("━".repeat(60));
        System.out.println("  DEMO 2: Countdown Loop     ->  5, 4, 3, 2, 1, 0");
        System.out.println("━".repeat(60));
        System.out.println();

        Memory mem = new Memory();
        CPU cpu = new CPU(mem);

        // Program: count down from 5 to 0
        //   Address 0x100 = 1 (decrement constant)
        //   Address 0x101 = counter storage
        int[] program = {
            instr(CPU.OP_INP, 0x005),  // 0x000: AC = 5 (immediate load)
            instr(CPU.OP_STA, 0x101),  // 0x001: Store counter
            instr(CPU.OP_LDA, 0x101),  // 0x002: Load counter (loop start)
            instr(CPU.OP_JZ,  0x007),  // 0x003: If AC == 0, jump to HLT
            instr(CPU.OP_SUB, 0x100),  // 0x004: AC = counter - 1
            instr(CPU.OP_STA, 0x101),  // 0x005: Store updated counter
            instr(CPU.OP_JMP, 0x002),  // 0x006: Jump back to loop start
            instr(CPU.OP_HLT, 0x000), // 0x007: Halt
        };

        mem.loadProgram(program);
        mem.write(0x100, 1);  // decrement value

        System.out.println("Program loaded. Counting down from 5...");
        System.out.println();

        cpu.run();

        System.out.println(mem.dump(0x100, 0x101));
        System.out.println();
    }

    // ─── DEMO 3: Multiply by Repeated Addition ──────────────

    /**
     * Computes 6 * 4 = 24 using repeated addition.
     * Demonstrates how multiplication can be implemented with
     * basic add, subtract, and conditional jump instructions.
     */
    private static void demoMultiplyByRepeatedAddition() {
        System.out.println("━".repeat(60));
        System.out.println("  DEMO 3: Multiply via Repeated Addition  ->  6 * 4 = 24");
        System.out.println("━".repeat(60));
        System.out.println();

        Memory mem = new Memory();
        CPU cpu = new CPU(mem);

        // Data addresses:
        //   0x100 = multiplicand (6)
        //   0x101 = multiplier / counter (4)
        //   0x102 = result (accumulated sum)
        //   0x103 = constant 1 (for decrementing counter)

        int[] program = {
            // Initialize result to 0
            instr(CPU.OP_INP, 0x000),  // 0x000: AC = 0
            instr(CPU.OP_STA, 0x102),  // 0x001: result = 0

            // Loop: check if counter == 0
            instr(CPU.OP_LDA, 0x101),  // 0x002: AC = counter
            instr(CPU.OP_JZ,  0x00B),  // 0x003: if counter == 0, jump to end

            // Add multiplicand to result
            instr(CPU.OP_LDA, 0x102),  // 0x004: AC = result
            instr(CPU.OP_ADD, 0x100),  // 0x005: AC = result + multiplicand
            instr(CPU.OP_STA, 0x102),  // 0x006: store updated result

            // Decrement counter
            instr(CPU.OP_LDA, 0x101),  // 0x007: AC = counter
            instr(CPU.OP_SUB, 0x103),  // 0x008: AC = counter - 1
            instr(CPU.OP_STA, 0x101),  // 0x009: store updated counter
            instr(CPU.OP_JMP, 0x002),  // 0x00A: jump back to loop start

            // End
            instr(CPU.OP_LDA, 0x102),  // 0x00B: load final result into AC
            instr(CPU.OP_HLT, 0x000), // 0x00C: halt
        };

        mem.loadProgram(program);
        mem.write(0x100, 6);  // multiplicand
        mem.write(0x101, 4);  // multiplier (counter)
        mem.write(0x103, 1);  // constant 1

        System.out.println("Program loaded. Computing 6 * 4 via repeated addition...");
        System.out.println();

        cpu.run();

        System.out.println(mem.dump(0x100, 0x103));
        System.out.println();
    }

    // ─── DEMO 4: Bitwise Operations ─────────────────────────

    /**
     * Demonstrates AND, OR, NOT, SHL, SHR operations.
     */
    private static void demoBitwiseOperations() {
        System.out.println("━".repeat(60));
        System.out.println("  DEMO 4: Bitwise Operations");
        System.out.println("━".repeat(60));
        System.out.println();

        Memory mem = new Memory();
        CPU cpu = new CPU(mem);

        // Data:
        //   0x100 = 0x00FF (mask)
        //   0x101 = 0x0F0F (pattern)
        //   0x102 = AND result
        //   0x103 = OR result
        //   0x104 = NOT result
        //   0x105 = SHL result
        //   0x106 = SHR result

        int[] program = {
            // AND: 0x00FF & 0x0F0F = 0x000F
            instr(CPU.OP_LDA, 0x100),  // 0x000: AC = 0x00FF
            instr(CPU.OP_AND, 0x101),  // 0x001: AC = 0x00FF & 0x0F0F
            instr(CPU.OP_STA, 0x102),  // 0x002: store AND result

            // OR: 0x00FF | 0x0F0F = 0x0FFF
            instr(CPU.OP_LDA, 0x100),  // 0x003: AC = 0x00FF
            instr(CPU.OP_OR,  0x101),  // 0x004: AC = 0x00FF | 0x0F0F
            instr(CPU.OP_STA, 0x103),  // 0x005: store OR result

            // NOT: ~0x00FF = 0xFF00
            instr(CPU.OP_LDA, 0x100),  // 0x006: AC = 0x00FF
            instr(CPU.OP_NOT, 0x000),  // 0x007: AC = ~0x00FF
            instr(CPU.OP_STA, 0x104),  // 0x008: store NOT result

            // SHL: 0x00FF << 1 = 0x01FE
            instr(CPU.OP_LDA, 0x100),  // 0x009: AC = 0x00FF
            instr(CPU.OP_SHL, 0x000),  // 0x00A: AC = AC << 1
            instr(CPU.OP_STA, 0x105),  // 0x00B: store SHL result

            // SHR: 0x00FF >> 1 = 0x007F
            instr(CPU.OP_LDA, 0x100),  // 0x00C: AC = 0x00FF
            instr(CPU.OP_SHR, 0x000),  // 0x00D: AC = AC >> 1
            instr(CPU.OP_STA, 0x106),  // 0x00E: store SHR result

            instr(CPU.OP_HLT, 0x000), // 0x00F: halt
        };

        mem.loadProgram(program);
        mem.write(0x100, 0x00FF);  // mask
        mem.write(0x101, 0x0F0F);  // pattern

        System.out.println("Program loaded. Data: mem[0x100]=0x00FF, mem[0x101]=0x0F0F");
        System.out.println();

        cpu.run();

        System.out.println(mem.dump(0x100, 0x106));
        System.out.println("Expected results:");
        System.out.println("  AND: 0x00FF & 0x0F0F = 0x000F");
        System.out.println("  OR:  0x00FF | 0x0F0F = 0x0FFF");
        System.out.println("  NOT: ~0x00FF         = 0xFF00");
        System.out.println("  SHL: 0x00FF << 1     = 0x01FE");
        System.out.println("  SHR: 0x00FF >> 1     = 0x007F");
        System.out.println();
    }
}
