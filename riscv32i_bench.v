module riscv32i_bench();
    reg CLK;
    wire RESET = 0;
    wire [0:2] buttons = 3'b0;
    wire [0:4] leds;

    SOC #(.CLK_DIV(2))uut(
        .CLK(CLK),
        .RESET(RESET),
        .BUTTONS(buttons),
        .leds(leds)
    );

    integer i;
    integer prev_leds = 0;

    initial begin
        CLK = 0;
        for(i = 0; i < 1024; i = i + 1) begin
            #10 
            CLK = ~CLK;
            if (leds != prev_leds) begin
                $display($time,, "LEDS = %b", leds);
            end
            prev_leds = leds;
        end
        $finish;
    end
endmodule