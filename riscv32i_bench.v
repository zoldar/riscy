module riscv32i_bench();
    reg CLK;
    wire RESET = 0;
    wire [0:2] buttons = 3'b110;
    wire [0:4] leds;
    wire [6:0] segment_display;
    wire segment_select;

    SOC #(.CLK_DIV(2))uut(
        .CLK(CLK),
        .RESET(RESET),
        .BUTTONS(buttons),
        .leds(leds),
        .segment_select(segment_select),
        .segment_display(segment_display)
    );

    integer i;
    integer prev_leds = 0;
    integer prev_segment_select = 0;
    integer prev_segment_display = 7'b0;

    initial begin
        CLK = 0;
        for(i = 0; i < 1024; i = i + 1) begin
            #10 
            CLK = ~CLK;
            if (leds != prev_leds || segment_display != prev_segment_display || segment_select != prev_segment_select) begin
                $display($time,, "LEDS = %b, SEGMENT_DISPLAY = %b, SEGMENT_SELECT = %b", leds, segment_display, segment_select);
            end
            prev_leds = leds;
            prev_segment_display = segment_display;
            prev_segment_select = segment_select;
        end
        $finish;
    end
endmodule