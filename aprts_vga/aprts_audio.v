// =============================================================
// APRTS_AUDIO - Multi-Channel Audio Synthesizer & ADSR Controller
// =============================================================
// Features a 4-channel mixed stereo audio generator with:
// - ADSR Envelope Generators for each channel.
// - DDS Phase Accumulators (Square, Triangle, Sawtooth, Sine, Trapezoid).
// - Serial I2S shift register transmitter for PCM5102A.
// =============================================================

module aprts_audio (
    input clk,
    input reset,

    // CPU Register Interface
    input write_en,
    input [3:0] lv_addr,
    input [7:0] lv_data,
    output [7:0] audio_read_val,

    // PCM5102A Interface
    output        pcm_bck,
    output        pcm_din,
    output        pcm_lrck,
    output        pcm_sck
);

    // Audio registers (4 channels)
    reg [4:0] aud_addr      = 5'h00;
    reg [7:0] reg_freq_lo_0 = 8'h00;
    reg [7:0] reg_freq_hi_0 = 8'h00;
    reg [7:0] reg_vol_0     = 8'h00;
    reg [7:0] reg_freq_lo_1 = 8'h00;
    reg [7:0] reg_freq_hi_1 = 8'h00;
    reg [7:0] reg_vol_1     = 8'h00;
    reg [7:0] reg_freq_lo_2 = 8'h00;
    reg [7:0] reg_freq_hi_2 = 8'h00;
    reg [7:0] reg_vol_2     = 8'h00;
    reg [7:0] reg_freq_lo_3 = 8'h00;
    reg [7:0] reg_freq_hi_3 = 8'h00;
    reg [7:0] reg_vol_3     = 8'h00;
    reg [7:0] reg_ctrl_0    = 8'h00;
    reg [7:0] reg_ctrl_1    = 8'h00;
    reg [7:0] reg_ctrl_2    = 8'h00;
    reg [7:0] reg_ctrl_3    = 8'h00;
    reg [7:0] reg_adsr_ad_0 = 8'h00;
    reg [7:0] reg_adsr_sr_0 = 8'h00;
    reg [7:0] reg_adsr_ad_1 = 8'h00;
    reg [7:0] reg_adsr_sr_1 = 8'h00;
    reg [7:0] reg_adsr_ad_2 = 8'h00;
    reg [7:0] reg_adsr_sr_2 = 8'h00;
    reg [7:0] reg_adsr_ad_3 = 8'h00;
    reg [7:0] reg_adsr_sr_3 = 8'h00;

    // DDS synthesis signals
    reg [8:0] audio_div     = 9'd0;
    reg [15:0] phase_acc_0  = 16'd0;
    reg [15:0] phase_acc_1  = 16'd0;
    reg [15:0] phase_acc_2  = 16'd0;
    reg [15:0] phase_acc_3  = 16'd0;
    reg pcm_din_r           = 1'b0;

    // CPU registers write/read logic
    always @(posedge clk) begin
        if (reset) begin
            aud_addr       <= 5'h00;
            reg_freq_lo_0  <= 8'h00;
            reg_freq_hi_0  <= 8'h00;
            reg_vol_0      <= 8'h00;
            reg_freq_lo_1  <= 8'h00;
            reg_freq_hi_1  <= 8'h00;
            reg_vol_1      <= 8'h00;
            reg_freq_lo_2  <= 8'h00;
            reg_freq_hi_2  <= 8'h00;
            reg_vol_2      <= 8'h00;
            reg_freq_lo_3  <= 8'h00;
            reg_freq_hi_3  <= 8'h00;
            reg_vol_3      <= 8'h00;
            reg_ctrl_0     <= 8'h00;
            reg_ctrl_1     <= 8'h00;
            reg_ctrl_2     <= 8'h00;
            reg_ctrl_3     <= 8'h00;
            reg_adsr_ad_0  <= 8'h00;
            reg_adsr_sr_0  <= 8'h00;
            reg_adsr_ad_1  <= 8'h00;
            reg_adsr_sr_1  <= 8'h00;
            reg_adsr_ad_2  <= 8'h00;
            reg_adsr_sr_2  <= 8'h00;
            reg_adsr_ad_3  <= 8'h00;
            reg_adsr_sr_3  <= 8'h00;
        end else if (write_en) begin
            if (lv_addr == 4'h5) begin
                aud_addr <= lv_data[4:0];
            end else if (lv_addr == 4'h6) begin
                case (aud_addr)
                    5'h00: reg_freq_lo_0 <= lv_data;
                    5'h01: reg_freq_hi_0 <= lv_data;
                    5'h02: reg_vol_0     <= lv_data;
                    5'h03: reg_freq_lo_1 <= lv_data;
                    5'h04: reg_freq_hi_1 <= lv_data;
                    5'h05: reg_vol_1     <= lv_data;
                    5'h06: reg_freq_lo_2 <= lv_data;
                    5'h07: reg_freq_hi_2 <= lv_data;
                    5'h08: reg_vol_2     <= lv_data;
                    5'h09: reg_freq_lo_3 <= lv_data;
                    5'h0A: reg_freq_hi_3 <= lv_data;
                    5'h0B: reg_vol_3     <= lv_data;
                    5'h0C: reg_ctrl_0    <= lv_data;
                    5'h0D: reg_ctrl_1    <= lv_data;
                    5'h0E: reg_ctrl_2    <= lv_data;
                    5'h0F: reg_ctrl_3    <= lv_data;
                    5'h10: reg_adsr_ad_0 <= lv_data;
                    5'h11: reg_adsr_sr_0 <= lv_data;
                    5'h12: reg_adsr_ad_1 <= lv_data;
                    5'h13: reg_adsr_sr_1 <= lv_data;
                    5'h14: reg_adsr_ad_2 <= lv_data;
                    5'h15: reg_adsr_sr_2 <= lv_data;
                    5'h16: reg_adsr_ad_3 <= lv_data;
                    5'h17: reg_adsr_sr_3 <= lv_data;
                    default: ;
                endcase
                // Auto-increment selector index
                if (aud_addr < 5'h17) begin
                    aud_addr <= aud_addr + 5'd1;
                end else begin
                    aud_addr <= 5'h00;
                end
            end
        end
    end

    reg [7:0] internal_read_val;
    always @(*) begin
        if (lv_addr == 4'h5) begin
            internal_read_val = {3'b0, aud_addr};
        end else if (lv_addr == 4'h6) begin
            case (aud_addr)
                5'h00: internal_read_val = reg_freq_lo_0;
                5'h01: internal_read_val = reg_freq_hi_0;
                5'h02: internal_read_val = reg_vol_0;
                5'h03: internal_read_val = reg_freq_lo_1;
                5'h04: internal_read_val = reg_freq_hi_1;
                5'h05: internal_read_val = reg_vol_1;
                5'h06: internal_read_val = reg_freq_lo_2;
                5'h07: internal_read_val = reg_freq_hi_2;
                5'h08: internal_read_val = reg_vol_2;
                5'h09: internal_read_val = reg_freq_lo_3;
                5'h0A: internal_read_val = reg_freq_hi_3;
                5'h0B: internal_read_val = reg_vol_3;
                5'h0C: internal_read_val = reg_ctrl_0;
                5'h0D: internal_read_val = reg_ctrl_1;
                5'h0E: internal_read_val = reg_ctrl_2;
                5'h0F: internal_read_val = reg_ctrl_3;
                5'h10: internal_read_val = reg_adsr_ad_0;
                5'h11: internal_read_val = reg_adsr_sr_0;
                5'h12: internal_read_val = reg_adsr_ad_1;
                5'h13: internal_read_val = reg_adsr_sr_1;
                5'h14: internal_read_val = reg_adsr_ad_2;
                5'h15: internal_read_val = reg_adsr_sr_2;
                5'h16: internal_read_val = reg_adsr_ad_3;
                5'h17: internal_read_val = reg_adsr_sr_3;
                default: internal_read_val = 8'h00;
            endcase
        end else begin
            internal_read_val = 8'h00;
        end
    end
    assign audio_read_val = internal_read_val;

    // Master I2S clock divider
    always @(posedge clk) begin
        if (reset) begin
            audio_div <= 9'd0;
        end else begin
            audio_div <= audio_div + 9'd1;
        end
    end

    // DDS Phase Accumulators (Fs = 48.828 kHz)
    always @(posedge clk) begin
        if (reset) begin
            phase_acc_0 <= 16'd0;
            phase_acc_1 <= 16'd0;
            phase_acc_2 <= 16'd0;
            phase_acc_3 <= 16'd0;
        end else if (audio_div == 9'd0) begin
            phase_acc_0 <= phase_acc_0 + {reg_freq_hi_0, reg_freq_lo_0};
            phase_acc_1 <= phase_acc_1 + {reg_freq_hi_1, reg_freq_lo_1};
            phase_acc_2 <= phase_acc_2 + {reg_freq_hi_2, reg_freq_lo_2};
            phase_acc_3 <= phase_acc_3 + {reg_freq_hi_3, reg_freq_lo_3};
        end
    end

    // Helper functions for wavetable generation
    function [7:0] get_step_size;
        input [3:0] rate;
        case (rate)
            4'd0:  get_step_size = 8'd1;
            4'd1:  get_step_size = 8'd2;
            4'd2:  get_step_size = 8'd3;
            4'd3:  get_step_size = 8'd4;
            4'd4:  get_step_size = 8'd6;
            4'd5:  get_step_size = 8'd8;
            4'd6:  get_step_size = 8'd12;
            4'd7:  get_step_size = 8'd16;
            4'd8:  get_step_size = 8'd24;
            4'd9:  get_step_size = 8'd32;
            4'd10: get_step_size = 8'd48;
            4'd11: get_step_size = 8'd64;
            4'd12: get_step_size = 8'd96;
            4'd13: get_step_size = 8'd128;
            4'd14: get_step_size = 8'd192;
            4'd15: get_step_size = 8'd255;
        endcase
    endfunction

    // Sine wavetable LUT
    function [7:0] get_sine;
        input [5:0] phase;
        case (phase)
            6'd0:  get_sine = 8'd128;
            6'd1:  get_sine = 8'd140;
            6'd2:  get_sine = 8'd153;
            6'd3:  get_sine = 8'd165;
            6'd4:  get_sine = 8'd177;
            6'd5:  get_sine = 8'd188;
            6'd6:  get_sine = 8'd199;
            6'd7:  get_sine = 8'd209;
            6'd8:  get_sine = 8'd218;
            6'd9:  get_sine = 8'd226;
            6'd10: get_sine = 8'd234;
            6'd11: get_sine = 8'd240;
            6'd12: get_sine = 8'd245;
            6'd13: get_sine = 8'd250;
            6'd14: get_sine = 8'd253;
            6'd15: get_sine = 8'd254;
            6'd16: get_sine = 8'd255;
            6'd17: get_sine = 8'd254;
            6'd18: get_sine = 8'd253;
            6'd19: get_sine = 8'd250;
            6'd20: get_sine = 8'd245;
            6'd21: get_sine = 8'd240;
            6'd22: get_sine = 8'd234;
            6'd23: get_sine = 8'd226;
            6'd24: get_sine = 8'd218;
            6'd25: get_sine = 8'd209;
            6'd26: get_sine = 8'd199;
            6'd27: get_sine = 8'd188;
            6'd28: get_sine = 8'd177;
            6'd29: get_sine = 8'd165;
            6'd30: get_sine = 8'd153;
            6'd31: get_sine = 8'd140;
            6'd32: get_sine = 8'd128;
            6'd33: get_sine = 8'd115;
            6'd34: get_sine = 8'd102;
            6'd35: get_sine = 8'd90;
            6'd36: get_sine = 8'd78;
            6'd37: get_sine = 8'd67;
            6'd38: get_sine = 8'd56;
            6'd39: get_sine = 8'd46;
            6'd40: get_sine = 8'd37;
            6'd41: get_sine = 8'd29;
            6'd42: get_sine = 8'd21;
            6'd43: get_sine = 8'd15;
            6'd44: get_sine = 8'd10;
            6'd45: get_sine = 8'd5;
            6'd46: get_sine = 8'd2;
            6'd47: get_sine = 8'd1;
            6'd48: get_sine = 8'd0;
            6'd49: get_sine = 8'd1;
            6'd50: get_sine = 8'd2;
            6'd51: get_sine = 8'd5;
            6'd52: get_sine = 8'd10;
            6'd53: get_sine = 8'd15;
            6'd54: get_sine = 8'd21;
            6'd55: get_sine = 8'd29;
            6'd56: get_sine = 8'd37;
            6'd57: get_sine = 8'd46;
            6'd58: get_sine = 8'd56;
            6'd59: get_sine = 8'd67;
            6'd60: get_sine = 8'd78;
            6'd61: get_sine = 8'd90;
            6'd62: get_sine = 8'd102;
            6'd63: get_sine = 8'd115;
            default: get_sine = 8'd128;
        endcase
    endfunction

    // Channel states (0: IDLE, 1: ATTACK, 2: DECAY, 3: SUSTAIN, 4: RELEASE)
    localparam STATE_IDLE    = 3'd0;
    localparam STATE_ATTACK  = 3'd1;
    localparam STATE_DECAY   = 3'd2;
    localparam STATE_SUSTAIN = 3'd3;
    localparam STATE_RELEASE = 3'd4;

    reg [17:0] adsr_div = 18'd0;

    reg [2:0] adsr_state_0 = STATE_IDLE;
    reg [7:0] envelope_vol_0 = 8'h00;
    reg gate_last_0 = 1'b0;

    reg [2:0] adsr_state_1 = STATE_IDLE;
    reg [7:0] envelope_vol_1 = 8'h00;
    reg gate_last_1 = 1'b0;

    reg [2:0] adsr_state_2 = STATE_IDLE;
    reg [7:0] envelope_vol_2 = 8'h00;
    reg gate_last_2 = 1'b0;

    reg [2:0] adsr_state_3 = STATE_IDLE;
    reg [7:0] envelope_vol_3 = 8'h00;
    reg gate_last_3 = 1'b0;

    always @(posedge clk) begin
        if (reset) begin
            adsr_div <= 18'd0;
        end else begin
            adsr_div <= adsr_div + 18'd1;
        end
    end

    // ADSR State Machine
    always @(posedge clk) begin
        if (reset) begin
            adsr_state_0 <= STATE_IDLE;
            envelope_vol_0 <= 8'd0;
            gate_last_0 <= 1'b0;

            adsr_state_1 <= STATE_IDLE;
            envelope_vol_1 <= 8'd0;
            gate_last_1 <= 1'b0;

            adsr_state_2 <= STATE_IDLE;
            envelope_vol_2 <= 8'd0;
            gate_last_2 <= 1'b0;

            adsr_state_3 <= STATE_IDLE;
            envelope_vol_3 <= 8'd0;
            gate_last_3 <= 1'b0;
        end else begin
            // Instant gate state tracking to minimize latency
            gate_last_0 <= reg_ctrl_0[4];
            gate_last_1 <= reg_ctrl_1[4];
            gate_last_2 <= reg_ctrl_2[4];
            gate_last_3 <= reg_ctrl_3[4];

            // Immediate transition on Gate Edge
            if (reg_ctrl_0[3]) begin // ADSR Enabled
                if (reg_ctrl_0[4] && !gate_last_0) begin
                    adsr_state_0 <= STATE_ATTACK;
                end else if (!reg_ctrl_0[4] && gate_last_0 && adsr_state_0 != STATE_IDLE) begin
                    adsr_state_0 <= STATE_RELEASE;
                end
            end else begin
                adsr_state_0 <= STATE_IDLE;
                envelope_vol_0 <= 8'd0;
            end

            if (reg_ctrl_1[3]) begin // ADSR Enabled
                if (reg_ctrl_1[4] && !gate_last_1) begin
                    adsr_state_1 <= STATE_ATTACK;
                end else if (!reg_ctrl_1[4] && gate_last_1 && adsr_state_1 != STATE_IDLE) begin
                    adsr_state_1 <= STATE_RELEASE;
                end
            end else begin
                adsr_state_1 <= STATE_IDLE;
                envelope_vol_1 <= 8'd0;
            end

            if (reg_ctrl_2[3]) begin // ADSR Enabled
                if (reg_ctrl_2[4] && !gate_last_2) begin
                    adsr_state_2 <= STATE_ATTACK;
                end else if (!reg_ctrl_2[4] && gate_last_2 && adsr_state_2 != STATE_IDLE) begin
                    adsr_state_2 <= STATE_RELEASE;
                end
            end else begin
                adsr_state_2 <= STATE_IDLE;
                envelope_vol_2 <= 8'd0;
            end

            if (reg_ctrl_3[3]) begin // ADSR Enabled
                if (reg_ctrl_3[4] && !gate_last_3) begin
                    adsr_state_3 <= STATE_ATTACK;
                end else if (!reg_ctrl_3[4] && gate_last_3 && adsr_state_3 != STATE_IDLE) begin
                    adsr_state_3 <= STATE_RELEASE;
                end
            end else begin
                adsr_state_3 <= STATE_IDLE;
                envelope_vol_3 <= 8'd0;
            end

            // ADSR clock update tick
            if (adsr_div == 18'd0) begin
                // Channel 0
                if (reg_ctrl_0[3]) begin
                    case (adsr_state_0)
                        STATE_IDLE: begin
                            envelope_vol_0 <= 8'd0;
                        end
                        STATE_ATTACK: begin
                            if (envelope_vol_0 >= (8'd255 - get_step_size(reg_adsr_ad_0[7:4]))) begin
                                envelope_vol_0 <= 8'd255;
                                adsr_state_0   <= STATE_DECAY;
                            end else begin
                                envelope_vol_0 <= envelope_vol_0 + get_step_size(reg_adsr_ad_0[7:4]);
                            end
                        end
                        STATE_DECAY: begin
                            if (envelope_vol_0 <= ({reg_adsr_sr_0[7:4], reg_adsr_sr_0[7:4]} + get_step_size(reg_adsr_ad_0[3:0]))) begin
                                envelope_vol_0 <= {reg_adsr_sr_0[7:4], reg_adsr_sr_0[7:4]};
                                adsr_state_0   <= STATE_SUSTAIN;
                            end else begin
                                envelope_vol_0 <= envelope_vol_0 - get_step_size(reg_adsr_ad_0[3:0]);
                            end
                        end
                        STATE_SUSTAIN: begin
                            envelope_vol_0 <= {reg_adsr_sr_0[7:4], reg_adsr_sr_0[7:4]};
                        end
                        STATE_RELEASE: begin
                            if (envelope_vol_0 <= get_step_size(reg_adsr_sr_0[3:0])) begin
                                envelope_vol_0 <= 8'd0;
                                adsr_state_0   <= STATE_IDLE;
                            end else begin
                                envelope_vol_0 <= envelope_vol_0 - get_step_size(reg_adsr_sr_0[3:0]);
                            end
                        end
                    endcase
                end

                // Channel 1
                if (reg_ctrl_1[3]) begin
                    case (adsr_state_1)
                        STATE_IDLE: begin
                            envelope_vol_1 <= 8'd0;
                        end
                        STATE_ATTACK: begin
                            if (envelope_vol_1 >= (8'd255 - get_step_size(reg_adsr_ad_1[7:4]))) begin
                                envelope_vol_1 <= 8'd255;
                                adsr_state_1   <= STATE_DECAY;
                            end else begin
                                envelope_vol_1 <= envelope_vol_1 + get_step_size(reg_adsr_ad_1[7:4]);
                            end
                        end
                        STATE_DECAY: begin
                            if (envelope_vol_1 <= ({reg_adsr_sr_1[7:4], reg_adsr_sr_1[7:4]} + get_step_size(reg_adsr_ad_1[3:0]))) begin
                                envelope_vol_1 <= {reg_adsr_sr_1[7:4], reg_adsr_sr_1[7:4]};
                                adsr_state_1   <= STATE_SUSTAIN;
                            end else begin
                                envelope_vol_1 <= envelope_vol_1 - get_step_size(reg_adsr_ad_1[3:0]);
                            end
                        end
                        STATE_SUSTAIN: begin
                            envelope_vol_1 <= {reg_adsr_sr_1[7:4], reg_adsr_sr_1[7:4]};
                        end
                        STATE_RELEASE: begin
                            if (envelope_vol_1 <= get_step_size(reg_adsr_sr_1[3:0])) begin
                                envelope_vol_1 <= 8'd0;
                                adsr_state_1   <= STATE_IDLE;
                            end else begin
                                envelope_vol_1 <= envelope_vol_1 - get_step_size(reg_adsr_sr_1[3:0]);
                            end
                        end
                    endcase
                end

                // Channel 2
                if (reg_ctrl_2[3]) begin
                    case (adsr_state_2)
                        STATE_IDLE: begin
                            envelope_vol_2 <= 8'd0;
                        end
                        STATE_ATTACK: begin
                            if (envelope_vol_2 >= (8'd255 - get_step_size(reg_adsr_ad_2[7:4]))) begin
                                envelope_vol_2 <= 8'd255;
                                adsr_state_2   <= STATE_DECAY;
                            end else begin
                                envelope_vol_2 <= envelope_vol_2 + get_step_size(reg_adsr_ad_2[7:4]);
                            end
                        end
                        STATE_DECAY: begin
                            if (envelope_vol_2 <= ({reg_adsr_sr_2[7:4], reg_adsr_sr_2[7:4]} + get_step_size(reg_adsr_ad_2[3:0]))) begin
                                envelope_vol_2 <= {reg_adsr_sr_2[7:4], reg_adsr_sr_2[7:4]};
                                adsr_state_2   <= STATE_SUSTAIN;
                            end else begin
                                envelope_vol_2 <= envelope_vol_2 - get_step_size(reg_adsr_ad_2[3:0]);
                            end
                        end
                        STATE_SUSTAIN: begin
                            envelope_vol_2 <= {reg_adsr_sr_2[7:4], reg_adsr_sr_2[7:4]};
                        end
                        STATE_RELEASE: begin
                            if (envelope_vol_2 <= get_step_size(reg_adsr_sr_2[3:0])) begin
                                envelope_vol_2 <= 8'd0;
                                adsr_state_2   <= STATE_IDLE;
                            end else begin
                                envelope_vol_2 <= envelope_vol_2 - get_step_size(reg_adsr_sr_2[3:0]);
                            end
                        end
                    endcase
                end

                // Channel 3
                if (reg_ctrl_3[3]) begin
                    case (adsr_state_3)
                        STATE_IDLE: begin
                            envelope_vol_3 <= 8'd0;
                        end
                        STATE_ATTACK: begin
                            if (envelope_vol_3 >= (8'd255 - get_step_size(reg_adsr_ad_3[7:4]))) begin
                                envelope_vol_3 <= 8'd255;
                                adsr_state_3   <= STATE_DECAY;
                            end else begin
                                envelope_vol_3 <= envelope_vol_3 + get_step_size(reg_adsr_ad_3[7:4]);
                            end
                        end
                        STATE_DECAY: begin
                            if (envelope_vol_3 <= ({reg_adsr_sr_3[7:4], reg_adsr_sr_3[7:4]} + get_step_size(reg_adsr_ad_3[3:0]))) begin
                                envelope_vol_3 <= {reg_adsr_sr_3[7:4], reg_adsr_sr_3[7:4]};
                                adsr_state_3   <= STATE_SUSTAIN;
                            end else begin
                                envelope_vol_3 <= envelope_vol_3 - get_step_size(reg_adsr_ad_3[3:0]);
                            end
                        end
                        STATE_SUSTAIN: begin
                            envelope_vol_3 <= {reg_adsr_sr_3[7:4], reg_adsr_sr_3[7:4]};
                        end
                        STATE_RELEASE: begin
                            if (envelope_vol_3 <= get_step_size(reg_adsr_sr_3[3:0])) begin
                                envelope_vol_3 <= 8'd0;
                                adsr_state_3   <= STATE_IDLE;
                            end else begin
                                envelope_vol_3 <= envelope_vol_3 - get_step_size(reg_adsr_sr_3[3:0]);
                            end
                        end
                    endcase
                end
            end
        end
    end

    // Waveform generator helper function
    function [7:0] get_wave_val;
        input [15:0] phase;
        input [2:0] ctrl;
        case (ctrl)
            3'd0: begin // Square
                get_wave_val = phase[15] ? 8'hFF : 8'h00;
            end
            3'd1: begin // Triangle
                get_wave_val = phase[15] ? ~phase[14:7] : phase[14:7];
            end
            3'd2: begin // Sawtooth
                get_wave_val = phase[15:8];
            end
            3'd3: begin // Sine
                get_wave_val = get_sine(phase[15:10]);
            end
            3'd4: begin // Trapezoid (Trapéz)
                if (!phase[15]) begin
                    get_wave_val = phase[14] ? 8'hFF : {phase[13:7], 1'b0};
                end else begin
                    get_wave_val = phase[14] ? 8'h00 : ~{phase[13:7], 1'b0};
                end
            end
            default: begin
                get_wave_val = phase[15] ? 8'hFF : 8'h00;
            end
        endcase
    endfunction

    // Waveforms
    wire [7:0] wave_0 = get_wave_val(phase_acc_0, reg_ctrl_0[2:0]);
    wire [7:0] wave_1 = get_wave_val(phase_acc_1, reg_ctrl_1[2:0]);
    wire [7:0] wave_2 = get_wave_val(phase_acc_2, reg_ctrl_2[2:0]);
    wire [7:0] wave_3 = get_wave_val(phase_acc_3, reg_ctrl_3[2:0]);

    // Envelope computation
    wire [15:0] scaled_vol_0 = envelope_vol_0 * reg_vol_0;
    wire [15:0] scaled_vol_1 = envelope_vol_1 * reg_vol_1;
    wire [15:0] scaled_vol_2 = envelope_vol_2 * reg_vol_2;
    wire [15:0] scaled_vol_3 = envelope_vol_3 * reg_vol_3;

    wire [7:0] eff_vol_0 = reg_ctrl_0[3] ? scaled_vol_0[15:8] : reg_vol_0;
    wire [7:0] eff_vol_1 = reg_ctrl_1[3] ? scaled_vol_1[15:8] : reg_vol_1;
    wire [7:0] eff_vol_2 = reg_ctrl_2[3] ? scaled_vol_2[15:8] : reg_vol_2;
    wire [7:0] eff_vol_3 = reg_ctrl_3[3] ? scaled_vol_3[15:8] : reg_vol_3;

    wire [15:0] prod_0 = wave_0 * eff_vol_0;
    wire [15:0] prod_1 = wave_1 * eff_vol_1;
    wire [15:0] prod_2 = wave_2 * eff_vol_2;
    wire [15:0] prod_3 = wave_3 * eff_vol_3;

    wire [7:0] weighted_0 = prod_0[15:8];
    wire [7:0] weighted_1 = prod_1[15:8];
    wire [7:0] weighted_2 = prod_2[15:8];
    wire [7:0] weighted_3 = prod_3[15:8];

    // Mixed signal [0..1020]
    wire [9:0] mixed_unsigned = weighted_0 + weighted_1 + weighted_2 + weighted_3;

    // Convert unsigned [0..1020] range to signed 16-bit I2S format
    wire signed [9:0] mixed_signed = mixed_unsigned - 10'd510;
    wire [15:0] current_sample = {mixed_signed[9], mixed_signed[8:0], 6'b0};

    // I2S Shift register transmitter
    always @(posedge clk) begin
        if (reset) begin
            pcm_din_r <= 1'b0;
        end else if (audio_div[3:0] == 4'd15) begin
            case (audio_div[7:4])
                4'd0:  pcm_din_r <= current_sample[15];
                4'd1:  pcm_din_r <= current_sample[14];
                4'd2:  pcm_din_r <= current_sample[13];
                4'd3:  pcm_din_r <= current_sample[12];
                4'd4:  pcm_din_r <= current_sample[11];
                4'd5:  pcm_din_r <= current_sample[10];
                4'd6:  pcm_din_r <= current_sample[9];
                4'd7:  pcm_din_r <= current_sample[8];
                4'd8:  pcm_din_r <= current_sample[7];
                4'd9:  pcm_din_r <= current_sample[6];
                4'd10: pcm_din_r <= current_sample[5];
                4'd11: pcm_din_r <= current_sample[4];
                4'd12: pcm_din_r <= current_sample[3];
                4'd13: pcm_din_r <= current_sample[2];
                4'd14: pcm_din_r <= current_sample[1];
                4'd15: pcm_din_r <= current_sample[0];
            endcase
        end
    end

    assign pcm_bck  = audio_div[3];
    assign pcm_lrck = audio_div[8];
    assign pcm_din  = pcm_din_r;
    assign pcm_sck  = 1'b0;

endmodule
