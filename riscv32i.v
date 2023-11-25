module top (
    input CLK,
    input BTN_N,
    input BTN1,
    input BTN2,
    input BTN3,
    output LED1,
    output LED2,
    output LED3,
    output LED4,
    output LED5,
    output P1A1,
    output P1A2,
    output P1A3,
    output P1A4,
    output P1A7,
    output P1A8,
    output P1A9,
    output P1A10
  );
  SOC #(.CLK_DIV(2))SoC(
        .CLK(CLK),
        .RESET(!BTN_N),
        .BUTTONS({BTN1, BTN2, BTN3}),
        .leds({LED1, LED2, LED3, LED4, LED5}),
        .segment_select(P1A10),
        .segment_display({P1A9, P1A8, P1A7, P1A4, P1A3, P1A2, P1A1})
      );
endmodule

module SOC (
    input CLK,
    input RESET,
    input [0:2] BUTTONS,
    output reg [0:4] leds,
    output segment_select,
    output [6:0] segment_display
  );

  parameter CLK_DIV = 2;

  initial
  begin
    leds = 5'b0;
  end

  // Main internal clock divider
  wire clk;

  Clockworks #(
               .SLOW(CLK_DIV)
             )CLOCK(
               .CLK(CLK),
               .clk(clk)
             );
  // Segment display
  reg [7:0] segment_number;

  initial
  begin
    segment_number = 8'b0;
  end

  SegmentDisplay SEGDISP(
                   .CLK(clk),
                   .NUMBER(segment_number),
                   .digit_sel(segment_select),
                   .seg_pins_n(segment_display)
                 );

  wire [31:0] mem_addr;
  wire [31:0] mem_rdata;
  wire [31:0] mem_wdata;
  wire [4:0] mem_wmask;

  localparam io_start_addr = 'h400000;

  wire isIO = mem_addr[22];
  wire isRAM = !isIO;

  // Input device mapping - BUTTONS - IO_ADDR + 16
  wire [31:0] io_rdata = mem_addr[4] ? {29'b0, BUTTONS[2], BUTTONS[1], BUTTONS[0]} : 32'b0;

  wire [31:0] ram_mem_addr = isRAM ? mem_addr : 32'b0;
  wire [4:0] ram_mem_wmask = isRAM ? mem_wmask : 32'b0;
  wire [31:0] cpu_mem_rdata = isRAM ? mem_rdata : io_rdata;

  CPU RISCV32I(
        .CLK(clk),
        .RESET(RESET),
        .MEM_RDATA(cpu_mem_rdata),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask)
      );

  Memory #(
           .MEMORY_SIZE_KB(8)
         )RAM(
           .CLK(clk),
           .ADDR(ram_mem_addr),
           .WDATA(mem_wdata),
           .WMASK(ram_mem_wmask),
           .rdata(mem_rdata)
         );

  always @(posedge clk)
  begin
    // Output device mappings
    if (isIO & mem_wmask[0])
    begin
      case (mem_addr[3:2])
        2'b01: // LED - IO_ADDR + 4
          leds <= {mem_wdata[4], mem_wdata[3], mem_wdata[2], mem_wdata[1], mem_wdata[0]};
        2'b10: // SEGDISPLAY - IO_ADDR + 8
          segment_number <= mem_wdata[7:0];
      endcase
    end
  end
endmodule

module SegmentDisplay (
    input CLK,
    input [7:0] NUMBER,
    output reg digit_sel,
    output reg [6:0] seg_pins_n
  );

  wire [6:0] tens;
  wire [6:0] ones;

  initial
  begin
    digit_sel = 1'b0;
  end

  wire [3:0] digit = digit_sel ? NUMBER[3:0] : NUMBER[7:4];
  wire [6:0] segments = digit_sel? ones : tens;

  SevenSeg SegTens(
             .CLK(CLK),
             .DIGIT(digit),
             .segments(tens)
           );

  SevenSeg SegOnes(
             .CLK(CLK),
             .DIGIT(digit),
             .segments(ones)
           );

  always @(posedge CLK)
  begin
    seg_pins_n <= ~segments;
    digit_sel <= !digit_sel;
  end
endmodule

module SevenSeg(
    input CLK,
    input [3:0] DIGIT,
    output reg [6:0] segments
  );
  initial
  begin
    segments = 7'b0111111;
  end

  always @(posedge CLK)
  begin
    case (DIGIT)
      0:
        segments <= 7'b0111111;
      1:
        segments <= 7'b0000110;
      2:
        segments <= 7'b1011011;
      3:
        segments <= 7'b1001111;
      4:
        segments <= 7'b1100110;
      5:
        segments <= 7'b1101101;
      6:
        segments <= 7'b1111101;
      7:
        segments <= 7'b0000111;
      8:
        segments <= 7'b1111111;
      9:
        segments <= 7'b1101111;
      4'hA:
        segments <= 7'b1110111;
      4'hB:
        segments <= 7'b1111100;
      4'hC:
        segments <= 7'b0111001;
      4'hD:
        segments <= 7'b1011110;
      4'hE:
        segments <= 7'b1111001;
      4'hF:
        segments <= 7'b1110001;
    endcase
  end
endmodule

module Clockworks (
    input CLK,
    output clk
  );

  parameter SLOW = 0;
  reg [SLOW:0] slow_CLK = 0;

  always @(posedge CLK)
  begin
    slow_CLK <= slow_CLK + 1;
  end

  assign clk = slow_CLK[SLOW];
endmodule

module Memory (
    input CLK,
    input [31:0] ADDR,
    input [31:0] WDATA,
    input [4:0] WMASK,
    output reg [31:0] rdata
  );

  parameter MEMORY_SIZE_KB = 4;

  // Memory
  reg [31:0] MEM [0:((MEMORY_SIZE_KB * 1024 / 4) - 1)];

  wire [29:0] word_addr = ADDR[31:2];

  initial
  begin
    //   0:	00400237          	lui	tp,0x400
    //   4:	01022283          	lw	t0,16(tp) # 0x400010
    //   8:	0c028093          	addi	ra,t0,192
    //   c:	00122223          	sw	ra,4(tp) # 0x4
    //  10:	00122423          	sw	ra,8(tp) # 0x8
    //  14:	00100073          	ebreak
    MEM[0] = 'h00400237;
    MEM[1] = 'h01022283;
    MEM[2] = 'h0c028093;
    MEM[3] = 'h00122223;
    MEM[4] = 'h00122423;
    MEM[5] = 'h00100073;
  end

  always @(posedge CLK)
  begin
    if (WMASK[0])
    begin
      case (WMASK)
        5'b00111:
          MEM[word_addr + 24] <= WDATA[7:0];
        5'b01111:
          MEM[word_addr + 16] <= WDATA[15:0];
        5'b11111:
          MEM[word_addr] <= WDATA;
      endcase
    end

    rdata <= MEM[word_addr];
  end
endmodule

module CPU (
    input CLK,
    input RESET,
    input [31:0] MEM_RDATA,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    output reg [4:0] mem_wmask
  );

  // CPU state
  reg [31:0] registers [0:31];
  reg [31:0] rs1;
  reg [31:0] rs2;
  reg [31:0] instr;
  reg [31:0] PC = 0;

  initial
  begin
    mem_wmask = 5'b0;
    registers[0] = 0;
  end

  /*** Decoder ***/

  // Opcodes
  wire [5:0] opcode = instr[6:2];

  wire isALU = (opcode == 5'b01100);
  wire isALUImm = (opcode == 5'b00100);
  wire isLoad = (opcode == 5'b00000);
  wire isStore = (opcode == 5'b01000);
  wire isBranch = (opcode == 5'b11000);
  wire isJAL = (opcode == 5'b11011);
  wire isJALR = (opcode == 5'b11001);
  wire isLUI = (opcode == 5'b01101);
  wire isAUIPC = (opcode == 5'b00101);
  wire isSYSTEM = (opcode == 5'b11100);

  // Function codes
  wire [2:0] funct3 = instr[14:12];
  wire [6:0] funct7 = instr[31:25];

  // Instruction registers
  wire [5:0] rdId = instr[11:7];
  wire [5:0] rs1Id = instr[19:15];
  wire [5:0] rs2Id = instr[24:20];

  // Immediate address mappings
  wire [31:0] Iimm = {{21{instr[31]}}, instr[30:20]};
  wire [31:0] Simm = {{21{instr[31]}}, instr[30:25], instr[11:8], instr[7]};
  wire [31:0] Bimm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
  wire [31:0] Uimm = {instr[31:12], 12'b0};
  wire [31:0] Jimm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:25], instr[24:21], 1'b0};

  wire [31:0] rs2ForALU = isALU ? rs2 : Iimm;
  wire [31:0] rs2ShiftForALU = isALU ? rs2 : Iimm[4:0];

  /*** Main state machine ***/

  localparam FETCH_INSTR = 0;
  localparam WAIT_INSTR = 1;
  localparam LOAD_REGS = 2;
  localparam WAIT_DATA = 3;
  localparam EXECUTE = 4;
  localparam WAIT_WRITE = 5;

  reg [2:0] state = FETCH_INSTR;

  assign mem_addr = (state == EXECUTE & isLoad) ? rs1 + Iimm : ((state == WAIT_WRITE) ? rs1 + Simm : PC);
  assign mem_wdata = rs2;

  always @(posedge CLK)
  begin
    if (RESET)
    begin
      PC <= 0;
      state <= FETCH_INSTR;
    end
    else
    begin
      case (state)
        FETCH_INSTR:
        begin
          state <= WAIT_INSTR;
        end
        WAIT_INSTR:
        begin
          instr <= MEM_RDATA;
          state <= LOAD_REGS;
        end
        LOAD_REGS:
        begin
          rs1 <= registers[rs1Id];
          rs2 <= registers[rs2Id];

          if (isLoad)
          begin
            state <= WAIT_DATA;
          end
          else
          begin
            state <= EXECUTE;
          end
        end
        WAIT_DATA:
        begin
          state <= EXECUTE;
        end
        EXECUTE:
        begin
          if (isALU || isALUImm)
          begin
            case (funct3)
              0:
              begin
                registers[rdId] = funct7[5] ? rs1 - rs2ForALU : rs1 + rs2ForALU;
              end
              4:
                registers[rdId] = rs1 ^ rs2ForALU;
              6:
                registers[rdId] = rs1 | rs2ForALU;
              7:
                registers[rdId] = rs1 & rs2ForALU;
              1:
                registers[rdId] = rs1 << rs2ShiftForALU;
              5:
                registers[rdId] = funct7[5] ? $signed(rs1 >> rs2ShiftForALU) : rs1 >> rs2ShiftForALU;
              2:
                registers[rdId] = ($signed(rs1) < $signed(rs2ForALU)) ? 1'b1 : 1'b0;
              3:
                registers[rdId] = (rs1 < rs2ForALU) ? 1'b1: 1'b0;
            endcase

            state <= FETCH_INSTR;
            PC <= PC + 4;
          end
          else if (isLoad)
          begin
            case (funct3)
              0:
                registers[rdId] = $signed(MEM_RDATA[7:0]);

              1:
                registers[rdId] = $signed(MEM_RDATA[15:0]);

              2:
                registers[rdId] = MEM_RDATA;

              4:
                registers[rdId] = MEM_RDATA[7:0];

              5:
                registers[rdId] = MEM_RDATA[15:0];
            endcase

            state <= FETCH_INSTR;
            PC <= PC + 4;
          end
          else if (isStore)
          begin
            case (funct3)
              0:
                mem_wmask <= 3'b111;
              1:
                mem_wmask <= 4'b1111;
              2:
              begin
                mem_wmask <= 5'b11111;
              end
            endcase
            state <= WAIT_WRITE;
          end
          else if (isJAL)
          begin
            registers[rdId] <= PC + 4;
            PC <= PC + Jimm;
            state <= FETCH_INSTR;
          end
          else if (isJALR)
          begin
            registers[rdId] = PC + 4;
            PC <= rs1 + Iimm;
            state <= FETCH_INSTR;
          end
          else if (isLUI)
          begin
            registers[rdId] <= Uimm;
            state <= FETCH_INSTR;
            PC <= PC + 4;
          end
          else if (isAUIPC)
          begin
            registers[rdId] <= PC + Uimm;
            state <= FETCH_INSTR;
            PC <= PC + 4;
          end
          else if (isBranch)
          begin
            case (funct3)
              0:
                PC <= (rs1 == rs2) ? PC <= PC + Bimm : PC;
              1:
                PC <= (rs1 != rs2) ? PC <= PC + Bimm : PC;
              4:
                PC <= ($signed(rs1) < $signed(rs2)) ? PC <= PC + Bimm : PC;
              5:
                PC <= ($signed(rs1) >= $signed(rs2)) ? PC <= PC + Bimm : PC;
              6:
                PC <= (rs1 < rs2) ? PC <= PC + Bimm : PC;
              7:
                PC <= (rs1 >= rs2) ? PC <= PC + Bimm : PC;
            endcase
            state <= FETCH_INSTR;
          end
          else if (isSYSTEM)
          begin
            state <= FETCH_INSTR;
          end
          else
          begin
            state <= FETCH_INSTR;
            PC <= PC + 4;
          end
        end
        WAIT_WRITE:
        begin
          mem_wmask <= 5'b0;
          state <= FETCH_INSTR;
          PC <= PC + 4;
        end
      endcase
    end
  end
endmodule

