`default_nettype none
`timescale 1ns / 1ps

module tb_fir_filter();

    // Clock and reset
    reg clock;
    reg reset;
    
    // DUT signals
    reg [7:0] ui_in;
    reg [7:0] uio_in;
    reg ena;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    
    // Test variables
    integer test_count;
    integer error_count;
    reg [15:0] expected_output;
    reg [7:0] expected_scaled;
    
    // Delay line tracking for golden model
    reg signed [7:0] x0_model, x1_model, x2_model, x3_model;
    reg signed [15:0] y_model;
    
    // Clock generation (10ns period = 100MHz)
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end
    
    // DUT instantiation
    tt_um_fir_filter dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clock),
        .rst_n(reset)
    );
    
    // Task: Apply reset
    task apply_reset;
        begin
            reset = 0;
            ui_in = 8'h00;
            uio_in = 8'h00;
            ena = 1;
            x0_model = 0;
            x1_model = 0;
            x2_model = 0;
            x3_model = 0;
            repeat(3) @(posedge clock);
            reset = 1;
            @(posedge clock);
        end
    endtask
    
    // Task: Send sample to filter
    task send_sample;
        input [1:0] mode;
        input [5:0] sample;
        begin
            ui_in = {sample, mode};
            @(posedge clock);
            // Update delay line model
            x3_model = x2_model;
            x2_model = x1_model;
            x1_model = x0_model;
            x0_model = {2'b00, sample};
        end
    endtask
    
    // Function: Calculate expected output for given mode
    function [15:0] calc_expected;
        input [1:0] mode;
        reg signed [15:0] result;
        begin
            case(mode)
                2'b00: result = {8'b0, x0_model}; // Bypass
                2'b01: result = x0_model + x1_model + x2_model + x3_model; // Moving avg
                2'b10: result = (x0_model * 4) + (x1_model * 2) + x2_model + x3_model; // Low-pass
                2'b11: result = x0_model - x1_model; // High-pass
            endcase
            calc_expected = result;
        end
    endfunction
    
    // Task: Check output
    task check_output;
        input [1:0] mode;
        input [15:0] expected;
        input string mode_name;
        reg [7:0] expected_out;
        begin
            test_count = test_count + 1;
            expected_out = expected[15:8];
            
            if (uo_out !== expected_out) begin
                error_count = error_count + 1;
                $display("LOG: %0t : ERROR : tb_fir_filter : dut.uo_out : expected_value: 8'h%02h actual_value: 8'h%02h", 
                         $time, expected_out, uo_out);
                $display("  Mode: %s, Full expected: 16'h%04h, Sample history: x0=%0d x1=%0d x2=%0d x3=%0d",
                         mode_name, expected, x0_model, x1_model, x2_model, x3_model);
            end else begin
                $display("LOG: %0t : INFO : tb_fir_filter : dut.uo_out : expected_value: 8'h%02h actual_value: 8'h%02h", 
                         $time, expected_out, uo_out);
            end
        end
    endtask
    
    // Main test sequence
    initial begin
        $display("TEST START");
        $display("=========================================");
        $display("FIR Filter Testbench");
        $display("=========================================");
        
        test_count = 0;
        error_count = 0;
        
        // Initialize signals
        apply_reset();
        $display("\n[%0t] Reset applied", $time);
        
        // ========================================
        // Test 1: Mode 0 - Bypass
        // ========================================
        $display("\n--- Test 1: Mode 0 - Bypass ---");
        apply_reset();
        
        // Wait one extra cycle for the mode selector register
        @(posedge clock);
        
        send_sample(2'b00, 6'd10);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b00, calc_expected(2'b00), "Bypass");
        
        send_sample(2'b00, 6'd20);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b00, calc_expected(2'b00), "Bypass");
        
        send_sample(2'b00, 6'd30);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b00, calc_expected(2'b00), "Bypass");
        
        send_sample(2'b00, 6'd63); // Max 6-bit value
        @(posedge clock);
        @(posedge clock);
        check_output(2'b00, calc_expected(2'b00), "Bypass");
        
        // ========================================
        // Test 2: Mode 1 - Moving Average
        // ========================================
        $display("\n--- Test 2: Mode 1 - Moving Average ---");
        apply_reset();
        @(posedge clock);
        
        send_sample(2'b01, 6'd16);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b01, calc_expected(2'b01), "Moving Avg");
        
        send_sample(2'b01, 6'd16);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b01, calc_expected(2'b01), "Moving Avg");
        
        send_sample(2'b01, 6'd16);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b01, calc_expected(2'b01), "Moving Avg");
        
        send_sample(2'b01, 6'd16);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b01, calc_expected(2'b01), "Moving Avg");
        
        // Should average to 16 now (16+16+16+16)/4 = 16
        // But output is [15:8], so (16*4)>>8 = 64>>8 = 0
        
        // ========================================
        // Test 3: Mode 2 - Low-pass (4,2,1,1)
        // ========================================
        $display("\n--- Test 3: Mode 2 - Low-pass Filter ---");
        apply_reset();
        @(posedge clock);
        
        send_sample(2'b10, 6'd8);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b10, calc_expected(2'b10), "Low-pass");
        
        send_sample(2'b10, 6'd8);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b10, calc_expected(2'b10), "Low-pass");
        
        send_sample(2'b10, 6'd8);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b10, calc_expected(2'b10), "Low-pass");
        
        send_sample(2'b10, 6'd8);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b10, calc_expected(2'b10), "Low-pass");
        
        // ========================================
        // Test 4: Mode 3 - High-pass (1,-1,0,0)
        // ========================================
        $display("\n--- Test 4: Mode 3 - High-pass/Edge Detector ---");
        apply_reset();
        @(posedge clock);
        
        // Step response - should show edge
        send_sample(2'b11, 6'd0);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b11, calc_expected(2'b11), "High-pass");
        
        send_sample(2'b11, 6'd32);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b11, calc_expected(2'b11), "High-pass");
        
        send_sample(2'b11, 6'd32);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b11, calc_expected(2'b11), "High-pass");
        
        send_sample(2'b11, 6'd32);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b11, calc_expected(2'b11), "High-pass");
        
        // ========================================
        // Test 5: Impulse Response (all modes)
        // ========================================
        $display("\n--- Test 5: Impulse Response ---");
        
        // Mode 1 impulse
        apply_reset();
        @(posedge clock);
        send_sample(2'b01, 6'd63); // Max impulse
        @(posedge clock);
        @(posedge clock);
        check_output(2'b01, calc_expected(2'b01), "Impulse-Avg");
        
        send_sample(2'b01, 6'd0);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b01, calc_expected(2'b01), "Impulse-Avg");
        
        send_sample(2'b01, 6'd0);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b01, calc_expected(2'b01), "Impulse-Avg");
        
        send_sample(2'b01, 6'd0);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b01, calc_expected(2'b01), "Impulse-Avg");
        
        // ========================================
        // Test 6: Mode Switching
        // ========================================
        $display("\n--- Test 6: Mode Switching ---");
        apply_reset();
        @(posedge clock);
        
        send_sample(2'b00, 6'd10);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b00, calc_expected(2'b00), "Mode0");
        
        send_sample(2'b01, 6'd20);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b01, calc_expected(2'b01), "Mode1");
        
        send_sample(2'b10, 6'd30);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b10, calc_expected(2'b10), "Mode2");
        
        send_sample(2'b11, 6'd40);
        @(posedge clock);
        @(posedge clock);
        check_output(2'b11, calc_expected(2'b11), "Mode3");
        
        // ========================================
        // Test 7: Random stimulus (keep same mode for multiple samples)
        // ========================================
        $display("\n--- Test 7: Random Stimulus ---");
        apply_reset();
        @(posedge clock);
        
        repeat(5) begin  // 5 different modes
            automatic reg [1:0] rand_mode = $urandom_range(0, 3);
            $display("  Testing mode %0d with random samples", rand_mode);
            repeat(4) begin  // 4 samples per mode
                automatic reg [5:0] rand_sample = $urandom_range(0, 63);
                send_sample(rand_mode, rand_sample);
                @(posedge clock);
                @(posedge clock);
                check_output(rand_mode, calc_expected(rand_mode), "Random");
            end
        end
        
        // ========================================
        // Final Report
        // ========================================
        $display("\n=========================================");
        $display("Test Summary");
        $display("=========================================");
        $display("Total tests: %0d", test_count);
        $display("Errors:      %0d", error_count);
        
        if (error_count == 0) begin
            $display("\n*** TEST PASSED ***");
            $display("TEST PASSED");
        end else begin
            $display("\n*** TEST FAILED ***");
            $display("ERROR");
            $error("TEST FAILED with %0d errors", error_count);
        end
        
        $display("=========================================");
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #100000; // 100us timeout
        $display("\nERROR: Timeout - simulation ran too long");
        $fatal(1, "Simulation timeout");
    end
    
    // Waveform dump
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule
