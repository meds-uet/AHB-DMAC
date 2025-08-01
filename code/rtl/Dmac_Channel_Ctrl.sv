// Copyright 2025 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Description: Controller for Channel Module, Decides which request should be sent,
//              when to stop the burst and when to shift to single transfer.
//
// Authors: Muhammad Mouzzam and Danish Hassan 
// Date: July 23rd, 2025

`timescale 1ns/10ps
// State Encodings
typedef enum logic [2:0] {
    DISABLED      = 3'b000,
    ENABLED       = 3'b001,
    READ_WAIT     = 3'b010,
    HOLD_READ     = 3'b011,
    WRITE_WAIT    = 3'b100,
    HOLD_WRITE    = 3'b101
} state_t;

// HTrans Encodings
parameter IDLE     = 2'b00;
parameter BUSY     = 2'b01;
parameter NON_SEQ  = 2'b10;
parameter SEQ      = 2'b11;
module channel_ctrl(
    // Inputs
    input  logic       clk,
    input  logic       rst,
    input  logic       channel_en,
    input  logic       readyIn,
    input  logic       fifo_full,
    input  logic       fifo_empty,
    input  logic       bsz,
    input  logic       tslb,
    input  logic       tsz,
    input  logic [1:0] M_HResp,

    // Outputs
    output logic       irq,
    output logic [1:0] HTrans,
    output logic       write,
    output logic       b_sel, d_sel, t_sel, s_sel, h_sel,
    output logic       d_en, s_en, ts_en, burst_en, count_en, sz_en,
    output logic       rd_en, wr_en,
    output logic       trigger
);
    state_t current_state, next_state;
    // State Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            current_state <= DISABLED;
        else
            current_state <= next_state;
    end
    // Next State Logic
    always_comb begin
        case (current_state)
            DISABLED: begin
                next_state = (channel_en) ? ENABLED : DISABLED;
            end
            ENABLED: begin
                next_state = tsz ? DISABLED : READ_WAIT;
            end
            READ_WAIT: begin
                if (!readyIn)
                    next_state = READ_WAIT;
                else if (!channel_en && readyIn) 
                    next_state = HOLD_READ;
                else if (channel_en && readyIn && !bsz && !M_HResp)
                    next_state = READ_WAIT;
                else if (channel_en && readyIn && bsz && (M_HResp == 0))
                    next_state = WRITE_WAIT;
                else
                    next_state = READ_WAIT;
            end

            HOLD_READ: begin
                if (channel_en && bsz) begin
                    next_state = WRITE_WAIT;
                end else if (channel_en && !bsz) begin
                    next_state = READ_WAIT;
                end else begin
                    next_state = HOLD_READ;
                end
            end

            WRITE_WAIT: begin
                if (channel_en && tsz && bsz)
                    next_state = DISABLED;
                else if (!readyIn)
                    next_state = WRITE_WAIT;
                else if (!channel_en && readyIn)
                    next_state = HOLD_WRITE; 
                else if (channel_en && readyIn && !bsz && (M_HResp == 0))
                    next_state = WRITE_WAIT; 
                else if (channel_en && readyIn && bsz && (M_HResp == 0))
                    next_state = READ_WAIT;
                else
                    next_state = WRITE_WAIT;
            end

            HOLD_WRITE: begin
                if (channel_en && !bsz) begin
                    next_state = WRITE_WAIT;
                end else if (channel_en && bsz) begin
                    if (tsz)
                        next_state = DISABLED;
                    else 
                        next_state = READ_WAIT;
                end else begin
                    next_state = HOLD_WRITE;
                end
            end
            default: next_state = current_state;
        endcase
    end

    // Output Logic
    always_comb begin
        // Default values
        irq       = 0;
        b_sel     = 0;
        d_sel     = 0;
        t_sel     = 0;
        s_sel     = 0;
        h_sel     = 0;
        d_en      = 0;
        s_en      = 0;
        ts_en     = 0;
        burst_en  = 0;
        count_en  = 0;
        sz_en     = 0;
        rd_en     = 0;
        wr_en     = 0;
        trigger   = 0;
        write     = 0;
        HTrans    = IDLE;
        case (current_state)
            DISABLED: begin
                if (channel_en) begin
                    t_sel     = 1;
                    d_sel     = 1;
                    s_sel     = 1;
                    burst_en  = 1;
                    s_en      = 1;
                    d_en      = 1;
                    sz_en     = 1;
                    ts_en     = 1;
                    HTrans    = IDLE;
                end
            end

            ENABLED: begin
                if (tsz) begin
                    irq = 1;
                end else if (channel_en) begin
                    write = 0;
                    count_en  = 1;
                    s_en = 1;
                    HTrans    = NON_SEQ;
                end
            end

            READ_WAIT: begin
                if (!readyIn) begin
                    write     = 0;
                    HTrans    = BUSY;
                end else if (!channel_en && readyIn) begin
                    wr_en = 1;
                    HTrans = IDLE;
                end
                else if (channel_en && readyIn && (M_HResp == 0) && !bsz)  begin
                    write     = 0;
                    wr_en     = 1;
                    count_en  = 1;
                    s_en      = 1;
                    HTrans    = SEQ;

                end else if (channel_en && bsz && (M_HResp == 0) && readyIn)  begin
                    wr_en = 1;
                    ts_en = 1;
                    count_en = 1;
                    write    = 1;
                    h_sel    = 1;
                    d_en     = 1;
                    HTrans    = NON_SEQ;
                end
            end

            HOLD_READ: begin
                if (channel_en && !bsz) begin
                    count_en = 1;
                    s_en     = 1;
                    HTrans   = SEQ;
                end else if (channel_en && bsz) begin
                    ts_en = 1;
                    write = 1;
                    h_sel = 1;
                    d_en = 1;
                    count_en = 1;
                    HTrans = NON_SEQ;
                end else
                    HTrans = IDLE;
            end
            
            WRITE_WAIT: begin
                if (!readyIn) begin
                    write     = 1;
                    HTrans    = BUSY;
                end else if (!channel_en && readyIn) begin
                    rd_en = 1;
                    trigger = 1;
                    HTrans = IDLE;
                end else if (channel_en && tsz && bsz) begin
                    irq = 1;
                    rd_en = 1;
                    trigger = 1;
                    HTrans = IDLE;
                end else if (channel_en && readyIn && (M_HResp == 0) && !bsz) begin
                    h_sel = 1;
                    write = 1;
                    trigger = 1;
                    rd_en = 1;
                    d_en      =  1;
                    count_en  = 1;
                    HTrans    = SEQ;
                end
                else if (channel_en && readyIn && (M_HResp == 0) && !tslb && bsz) begin
                    h_sel = 0;
                    write = 0;
                    count_en  = 1;
                    s_en = 1;
                    trigger = 1;
                    rd_en = 1;
                    HTrans    = NON_SEQ;

                end else if (channel_en && readyIn && (M_HResp == 0) && tslb && bsz) begin
                    burst_en = 1;
                    b_sel = 1;
                    write = 0;
                    count_en  = 1;
                    s_en = 1;
                    h_sel = 0;
                    trigger = 1;
                    rd_en = 1;
                    HTrans    = NON_SEQ;
                end
            end
            HOLD_WRITE: begin
                if (channel_en && !bsz) begin
                    h_sel = 1;
                    write = 1;
                    d_en = 1;
                    count_en = 1;
                    HTrans = SEQ;
                end else if (channel_en && bsz) begin
                    if (tsz) begin
                        irq = 1;
                        HTrans = IDLE;
                    end else if (tslb) begin
                        burst_en = 1;
                        b_sel   = 1;
                        count_en = 1;
                        s_en = 1;
                        HTrans = NON_SEQ;
                    end else if (!tslb) begin
                        count_en = 1;
                        s_en = 1;
                        HTrans = NON_SEQ;
                    end
            end
        end
        endcase
    end
endmodule