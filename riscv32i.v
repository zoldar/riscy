module Clockworks (
    input CLK,
    input RESET,
    output clk,
    output resetn
  );

  parameter SLOW = 0;
  reg [SLOW:0] slow_CLK = 0;

  always @(posedge CLK)
  begin
    slow_CLK <= slow_CLK + 1;
  end

  assign clk = slow_CLK[SLOW];
  assign resetn = !RESET;
endmodule

module Memory (
    input CLK,
    input [31:0] MEM_ADDR,
    output reg [31:0] mem_rdata
  );

  parameter MEMORY_SIZE_KB = 4;

  // Memory
  reg [31:0] MEM [0:((MEMORY_SIZE_KB * 1024 / 4) - 1)];

  wire [29:0] word_addr = MEM_ADDR[31:2];

  initial
  begin
    // 0:	000000b3          	add	ra,zero,zero
    MEM[0]  = 'h000000b3;
    // 4:	00108093          	addi	ra,ra,1
    MEM[1]  = 'h00108093;
    // 8:	0000a103          	lw	sp,0(ra)
    MEM[2]  = 'h0000a103;
    // c:	0020a023          	sw	sp,0(ra)
    MEM[3]  = 'h0020a023;
    // 10:	00100073          	ebreak
    MEM[4] = 'h00100073;
  end

  always @(posedge CLK)
  begin
    mem_rdata <= MEM[word_addr];
  end
endmodule

module top (
    input CLK,
    input BTN1,
    output LED1,
    output LED2,
    output LED3,
    output LED4,
    output LED5
);
  wire [2:0] state_out;
  wire [31:0] instr_out;
  wire [31:0] pc_out;
  wire clk_out;

  SOC #(.CLK_DIV(21))RiscV(
    .CLK(CLK),
    .RESET(BTN1),
    .state_out(state_out),
    .instr_out(instr_out),
    .pc_out(pc_out),
    .clk_out(clk_out)
  );

  assign LED1 = state_out[0];
  assign LED2 = state_out[1];
  assign LED3 = state_out[2];
  assign LED4 = pc_out[2];
  assign LED5 = clk_out;
endmodule

module SOC (
    input CLK,
    input RESET,
    output [2:0] state_out,
    output [31:0] instr_out,
    output [31:0] pc_out,
    output clk_out
  );

  parameter CLK_DIV = 2;

  // Main internal clock divider (and negative reset source)
  wire clk;
  wire resetn;

  Clockworks #(
               .SLOW(CLK_DIV)
             )CLOCK(
               .CLK(CLK),
               .RESET(RESET),
               .clk(clk),
               .resetn(resetn)
             );

  // Memory
  wire [31:0] mem_addr;
  wire [31:0] mem_rdata;

  // CPU state
  reg [31:0] registers [0:31];
  reg [31:0] rs1;
  reg [31:0] rs2;
  reg [31:0] instr;
  reg [31:0] PC = 0;

  initial
  begin
    registers[0] = 0;
  end

  assign mem_addr = PC;

  Memory #(
           .MEMORY_SIZE_KB(8)
         )RAM(
           .CLK(clk),
           .MEM_ADDR(mem_addr),
           .mem_rdata(mem_rdata)
         );

  // Decoder

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
   
  // Main state machine

  localparam FETCH_INSTR = 0;
  localparam WAIT_INSTR = 1;
  localparam LOAD_REGS = 2;
  localparam EXECUTE = 3;

  reg [2:0] state = FETCH_INSTR;

  always @(posedge clk)
  begin
    if (!resetn)
    begin
      PC <= 0;
      state <= FETCH_INSTR;
    end

    case (state)
      FETCH_INSTR:
      begin
        state <= WAIT_INSTR;
      end
      WAIT_INSTR:
      begin
        instr <= mem_rdata;
        state <= LOAD_REGS;
      end
      LOAD_REGS:
      begin
        rs1 <= registers[rs1Id];
        rs2 <= registers[rs2Id];
        state <= EXECUTE;
      end
      EXECUTE:
      begin
        if (isALU)
        begin
            case (funct3)
                0: registers[rdId] = funct7[5] ? rs1 - rs2 : rs1 + rs2;
                4: registers[rdId] = rs1 ^ rs2;
                6: registers[rdId] = rs1 | rs2;
                7: registers[rdId] = rs1 & rs2;
                1: registers[rdId] = rs1 << rs2;
                5: registers[rdId] = funct7[5] ? (rs1 >> rs2) & ({32{rs1[31]}} << rs2) : rs1 >> rs2;
                2: registers[rdId] = $signed(rs1) < $signed(rs2);
                3: registers[rdId] = rs1 < rs2;
            endcase
        end

        if (!isSYSTEM)
          PC <= PC + 4;
        state <= FETCH_INSTR;
      end
    endcase
  end

  assign pc_out = PC;
  assign state_out = state;
  assign instr_out = {rdId, 3'b111, rs1Id, rs1[7:0]};
  assign clk_out = clk;
endmodule
