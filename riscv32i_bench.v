module riscv32i_bench();
    reg CLK;
    wire RESET = 0;
    wire [2:0] STATE;
    wire [31:0] INSTR;
    wire [31:0] PC;

    SOC uut(
        .CLK(CLK),
        .RESET(RESET),
        .state_out(STATE),
        .instr_out(INSTR),
        .pc_out(PC)
    );

    integer i = 0;
    integer prev_STATE = 1;

    initial begin
        CLK = 0;
        for(i = 0; i < 512; i = i + 1) begin
            #10 
            CLK = ~CLK;
            if (STATE != prev_STATE && STATE == 3) begin
                $display($time,, "STATE = %d, PC = %h, INSTR = %b", STATE, PC, INSTR);
            end
            prev_STATE = STATE;
        end
        $finish;
    end
endmodule