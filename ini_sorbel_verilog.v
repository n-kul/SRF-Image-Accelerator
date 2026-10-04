(* top *) module top ( 
	(* iopad_external_pin, clkbuf_inhibit *) input clk, 	// System Clock (50MHz) 
	(* iopad_external_pin *) output clk_en, 
	(* iopad_external_pin *) input rst_n, 			   	// System Reset (Active Low) 
	
	// Physical SPI Pins
	(* iopad_external_pin *) input spi_ss_n, 
	(* iopad_external_pin *) input spi_sck, 
	(* iopad_external_pin *) input spi_mosi, 
	(* iopad_external_pin *) output spi_miso, 
	(* iopad_external_pin *) output spi_miso_en,
	
	// Physical LED Pins 
	(* iopad_external_pin *) output reg led, 
	(* iopad_external_pin *) output led_en 
);

	assign led_en = 1'b1;
	assign clk_en = 1'b1;

    wire [7:0] rx_data_wire;
    wire       rx_valid_pulse;
    reg  [7:0] tx_data_reg;

    // --- Continuous Streaming Pixel Window ---
    reg [7:0] p11, p12, p13; 
    reg [7:0] p21, p22, p23; 
    reg [7:0] p31, p32, p33; 

    // Intermediate Math Variables
    reg signed [11:0] Gx;
    reg signed [11:0] Gy;
    reg [11:0] abs_Gx;
    reg [11:0] abs_Gy;
    
    // Low threshold to catch fine text line structures
    parameter THRESHOLD = 8'd25; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p11 <= 8'h0; p12 <= 8'h0; p13 <= 8'h0;
            p21 <= 8'h0; p22 <= 8'h0; p23 <= 8'h0;
            p31 <= 8'h0; p32 <= 8'h0; p33 <= 8'h0;
            tx_data_reg <= 8'h00;
            led <= 1'b0;
        end 
        else if (rx_valid_pulse) begin
            // Shift history elements left smoothly on every single byte arrival
            p13 <= p12; p12 <= p11;
            p23 <= p22; p22 <= p21;
            p33 <= p32; p32 <= p31;
            
            // Shift down the vertical pixel column track natively
            p11 <= rx_data_wire;
            p21 <= p11;
            p31 <= p21;
            
            // --- Parallel Sobel Operator Evaluation ---
            Gx <= ($signed({4'b0, p11}) - $signed({4'b0, p13})) + 
                  (($signed({4'b0, p21}) - $signed({4'b0, p23})) << 1) + 
                  ($signed({4'b0, p31}) - $signed({4'b0, p33}));

            Gy <= ($signed({4'b0, p11}) + (($signed({4'b0, p12})) << 1) + $signed({4'b0, p13})) - 
                  ($signed({4'b0, p31}) + (($signed({4'b0, p32})) << 1) + $signed({4'b0, p33}));
                  
            // Structural Sign-Magnitude Evaluation
            abs_Gx <= (Gx[11]) ? -Gx : Gx;
            abs_Gy <= (Gy[11]) ? -Gy : Gy;
            
            // Apply edge threshold
            if ((abs_Gx + abs_Gy) > THRESHOLD) begin
                tx_data_reg <= 8'hFF; // White Edge
                led <= 1'b1;
            end else begin
                tx_data_reg <= 8'h00; // Black Background
                led <= 1'b0;
            end
        end
    end

    // Core SPI Target Core Instantiation 
    spi_target #(
        .CPOL(1'b0), .CPHA(1'b0), .WIDTH(8), .LSB(1'b0)
    ) u_spi_target (
        .i_clk(clk), .i_rst_n(rst_n), .i_enable(1'b1),
        .i_ss_n(spi_ss_n), .i_sck(spi_sck), .i_mosi(spi_mosi),
        .o_miso(spi_miso), .o_miso_oe(spi_miso_en),
        .o_rx_data(rx_data_wire), .o_rx_data_valid(rx_valid_pulse),
        .i_tx_data(tx_data_reg), .o_tx_data_hold()
    );

endmodule



module spi_target #(
  parameter CPOL   = 1'b0,  
  parameter CPHA   = 1'b0,  
  parameter WIDTH  = 8,     
  parameter LSB    = 1'b0   
) (
// common ports
  input                  i_clk,           
  input                  i_rst_n,         
// control signal
  input                  i_enable,        
// SPI interface ports
  input                  i_ss_n,          
  input                  i_sck,           
  input                  i_mosi,          
  output                 o_miso,          
  output                 o_miso_oe,       
//RX internal ports
  output reg [WIDTH-1:0] o_rx_data,       
  output reg             o_rx_data_valid, 
//TX internal ports
  input      [WIDTH-1:0] i_tx_data,       
  output                 o_tx_data_hold   
);

// Signal declaration
  reg               [2:0] r_ss_n_sync, r_sck_sync;
  
  // FIXED: Explicitly forced to a clean static 3-bit vector size
  reg               [2:0] r_transmision_count;
  
  reg         [WIDTH-1:0] r_miso_data;
  wire                    w_sck_r_edge, w_sck_f_edge, w_sck_edge, w_sck_edge_op;

// SPI input signals synchronization
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_ss_n_sync <= 'b111;
    end else if (i_enable) begin
      r_ss_n_sync <= {r_ss_n_sync[1:0], i_ss_n};
    end else begin
      r_ss_n_sync <= 'b111;
    end
  end

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_sck_sync <= 'h0;
    end else if (i_enable) begin
      r_sck_sync <= {r_sck_sync[1:0], i_sck};
    end else begin
      r_sck_sync <= 'h0;
    end
  end

// Create rising and falling edge signals from spi_clk signal
  assign w_sck_r_edge  = ~r_sck_sync[2] & r_sck_sync[1];
  assign w_sck_f_edge  = r_sck_sync[2] & ~r_sck_sync[1];
  assign w_sck_edge    = (CPHA^CPOL) ? w_sck_f_edge : w_sck_r_edge;
  assign w_sck_edge_op = (CPHA^CPOL) ? w_sck_r_edge : w_sck_f_edge;

// Create transmission bit counter
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_transmision_count <= 3'd0;
    end else if (!i_enable || r_ss_n_sync[1]) begin
      r_transmision_count <= 3'd0;
    end else if (w_sck_edge) begin
      // FIXED: Replaced "WIDTH-1" (32-bit) expression with an explicit 3-bit constant match (3'd7)
      if (r_transmision_count == 3'd7) begin
        r_transmision_count <= 3'd0;
      end else begin
        r_transmision_count <= r_transmision_count + 1'b1;
      end
    end
  end

// Create o_rx_data bus and valid signals
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_rx_data <= 'h0;
    end else if (w_sck_edge) begin
      if (LSB) begin
        o_rx_data <= {i_mosi, o_rx_data[WIDTH-1:1]};
      end else begin
        o_rx_data <= {o_rx_data[WIDTH-2:0], i_mosi};
      end
    end
  end

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_rx_data_valid <= 1'b0;
    end else if (r_ss_n_sync[1] || (r_transmision_count == 3'd0 && w_sck_edge)) begin
      o_rx_data_valid <= 1'b0;
    end else if (w_sck_edge && r_transmision_count == 3'd7) begin // FIXED: Changed WIDTH-1 to 3'd7
      o_rx_data_valid <= 1'b1;
    end
  end

// Create o_tx_data_hold signal
  // FIXED: Replaced expression evaluation with 3-bit static definition variable comparison check
  assign o_tx_data_hold = (~CPHA & r_ss_n_sync[2] & ~r_ss_n_sync[1]) | (r_transmision_count == 3'd0 & w_sck_edge_op);

// Create o_miso and OE signals
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_miso_data <= 'h0;
    end else if (o_tx_data_hold) begin
      r_miso_data <= i_tx_data;
    end else if (w_sck_edge_op) begin
      if (LSB) begin
        r_miso_data <= r_miso_data >> 1;
      end else begin
        r_miso_data <= r_miso_data << 1;
      end
    end
  end

  assign o_miso    = (LSB) ? r_miso_data[0] : r_miso_data[WIDTH-1];
  assign o_miso_oe = ~r_ss_n_sync[2];

endmodule
