`default_nettype none

module tt_um_fir_filter (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ========================================================================
    // REGISTER-MAPPED INTERFACE (ENHANCED!)
    // ========================================================================
    // ui_in[7:6] = operation type:
    //   00 = input sample data (streaming mode)
    //   01 = write coefficient h0
    //   10 = write coefficient h1  
    //   11 = mode selection or write h2/h3
    //
    // ui_in[5:0] = data payload (6-bit)
    //
    // For op_type == 11 (mode/coeff control):
    //   ui_in[5:4] = mode select (00=bypass, 01=avg, 10=lowpass, 11=highpass)
    //   ui_in[3]   = mode_enable (1=load preset mode, 0=write h2/h3)
    //   ui_in[2:0] = coefficient data (when mode_enable=0)
    //
    // uio_in[1:0] = coefficient readback select (00=h0, 01=h1, 10=h2, 11=h3)
    // uio_out[7:2] = selected coefficient value (6-bit readback)
    // uio_out[1] = pipeline_valid (indicates valid filtered output)
    // uio_out[0] = coeff_update_flag (pulses when coefficient written)
    // ========================================================================
    
    wire [1:0] op_type;
    wire [5:0] data_in;
    
    assign op_type = ui_in[7:6];
    assign data_in = ui_in[5:0];
    
    // ========================================================================
    // COEFFICIENT REGISTERS (runtime configurable)
    // ========================================================================
    reg signed [7:0] h0_reg;  // Coefficient 0
    reg signed [7:0] h1_reg;  // Coefficient 1
    reg signed [7:0] h2_reg;  // Coefficient 2
    reg signed [7:0] h3_reg;  // Coefficient 3
    
    // ========================================================================
    // MODE REGISTER (selects filter behavior)
    // ========================================================================
    // Mode 0: Bypass (1,0,0,0)
    // Mode 1: Moving average (1,1,1,1)
    // Mode 2: Weighted low-pass (4,2,1,1)
    // Mode 3: High-pass edge detector (1,-1,0,0)
    reg [1:0] mode_reg;
    
    // ========================================================================
    // STATUS REGISTERS (NEW!)
    // ========================================================================
    reg coeff_update_flag;   // Pulses when coefficient is written
    reg pipeline_valid;       // Indicates output contains valid data
    reg [2:0] pipeline_count; // Counts cycles after reset for valid data
    
    // ========================================================================
    // REGISTER WRITE LOGIC (ENHANCED!)
    // ========================================================================
    wire mode_enable;
    wire [1:0] mode_select;
    
    assign mode_enable = (op_type == 2'b11) && data_in[3];  // Mode load enable
    assign mode_select = data_in[5:4];                       // Mode selection bits
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Default coefficients (moving average)
            h0_reg <= 8'sd1;
            h1_reg <= 8'sd1;
            h2_reg <= 8'sd1;
            h3_reg <= 8'sd1;
            mode_reg <= 2'b01;  // Default to moving average mode
            coeff_update_flag <= 1'b0;
            pipeline_valid <= 1'b0;
            pipeline_count <= 3'b000;
        end
        else begin
            // Default: clear update flag each cycle
            coeff_update_flag <= 1'b0;
            
            // Track pipeline validity (valid after 4 samples)
            if (sample_en) begin
                if (pipeline_count < 3'd4)
                    pipeline_count <= pipeline_count + 1'b1;
                pipeline_valid <= (pipeline_count >= 3'd3);
            end
            
            case (op_type)
                2'b01: begin  // Write h0
                    h0_reg <= {2'b00, data_in};
                    coeff_update_flag <= 1'b1;
                end
                
                2'b10: begin  // Write h1
                    h1_reg <= {2'b00, data_in};
                    coeff_update_flag <= 1'b1;
                end
                
                2'b11: begin  // Mode select OR write h2/h3
                    if (mode_enable) begin
                        // Load preset mode coefficients
                        mode_reg <= mode_select;
                        coeff_update_flag <= 1'b1;
                        
                        case (mode_select)
                            2'b00: begin  // Bypass mode
                                h0_reg <= 8'sd1;
                                h1_reg <= 8'sd0;
                                h2_reg <= 8'sd0;
                                h3_reg <= 8'sd0;
                            end
                            2'b01: begin  // Moving average mode
                                h0_reg <= 8'sd1;
                                h1_reg <= 8'sd1;
                                h2_reg <= 8'sd1;
                                h3_reg <= 8'sd1;
                            end
                            2'b10: begin  // Low-pass mode
                                h0_reg <= 8'sd4;
                                h1_reg <= 8'sd2;
                                h2_reg <= 8'sd1;
                                h3_reg <= 8'sd1;
                            end
                            2'b11: begin  // High-pass mode
                                h0_reg <= 8'sd1;
                                h1_reg <= -8'sd1;  // Negative coefficient
                                h2_reg <= 8'sd0;
                                h3_reg <= 8'sd0;
                            end
                        endcase
                    end
                    else begin
                        // Write h2/h3 directly (legacy mode)
                        h2_reg <= {2'b00, data_in[5:3], 3'b000};  // Upper 3 bits -> h2
                        h3_reg <= {5'b00000, data_in[2:0]};       // Lower 3 bits -> h3
                        coeff_update_flag <= 1'b1;
                    end
                end
                
                default: begin  // Sample operation (00)
                    // Keep registers unchanged during sampling
                    h0_reg <= h0_reg;
                    h1_reg <= h1_reg;
                    h2_reg <= h2_reg;
                    h3_reg <= h3_reg;
                    mode_reg <= mode_reg;
                end
            endcase
        end
    end
    
    // ========================================================================
    // COEFFICIENT READBACK (NEW!)
    // ========================================================================
    wire [1:0] coeff_select;
    reg [7:0] coeff_readback;
    
    assign coeff_select = uio_in[1:0];
    
    always @(*) begin
        case (coeff_select)
            2'b00: coeff_readback = h0_reg;
            2'b01: coeff_readback = h1_reg;
            2'b10: coeff_readback = h2_reg;
            2'b11: coeff_readback = h3_reg;
        endcase
    end
    
    // ========================================================================
    // SAMPLE INPUT AND DELAY LINE
    // ========================================================================
    // Only update delay line during sample operations (op_type == 00)
    wire sample_en;
    assign sample_en = (op_type == 2'b00);
    
    wire [7:0] sample;
    assign sample = {2'b00, data_in};  // Extend 6-bit to 8-bit unsigned
    
    wire [7:0] x0, x1, x2, x3;
    
    delay_line_controlled delay_inst (
        .clk(clk),
        .rst_n(rst_n),
        .sample_en(sample_en),
        .sample_in(sample),
        .x0(x0),
        .x1(x1),
        .x2(x2),
        .x3(x3)
    );
    
    // ========================================================================
    // CONFIGURABLE FIR CORE
    // ========================================================================
    wire signed [15:0] y_filtered;
    
    fir_core_dynamic fir_inst (
        .x0(x0),
        .x1(x1),
        .x2(x2),
        .x3(x3),
        .h0(h0_reg),
        .h1(h1_reg),
        .h2(h2_reg),
        .h3(h3_reg),
        .y(y_filtered)
    );
    
    // ========================================================================
    // OUTPUT PIPELINE REGISTER
    // ========================================================================
    reg [15:0] y_output_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            y_output_reg <= 16'b0;
        else
            y_output_reg <= y_filtered;  // Continuously update
    end
    
    // Scale output: take upper 8 bits for fixed-point scaling
    assign uo_out = y_output_reg[15:8];
    
    // ========================================================================
    // BIDIRECTIONAL I/O OUTPUTS (ENHANCED!)
    // ========================================================================
    // uio_in[1:0]  = coefficient select (INPUT)
    // uio_out[0]   = coeff_update_flag (OUTPUT)
    // uio_out[1]   = pipeline_valid (OUTPUT)
    // uio_out[7:2] = coefficient readback (OUTPUT - 6 bits)
    assign uio_out = {coeff_readback[5:0], pipeline_valid, coeff_update_flag};
    assign uio_oe  = 8'b11111100;  // Only [7:2] are outputs, [1:0] are inputs
    
    wire _unused = &{ena, uio_in[7:2], coeff_readback[7:6], 1'b0};

endmodule
