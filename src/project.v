/*
 * Copyright 2024 Jaeden Amero
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_patater_demokit_2 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // VGA signals
  wire hsync;
  wire vsync;
  // Should we reg for the colors? No need, palette has reg for it.
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;
  wire display_on;
  wire [9:0] hpos;
  wire [9:0] vpos;
  wire [5:0] rrggbb;
  wire [7:0] tunnel_color;

  wire [7:0] color;

  // TinyVGA PMOD
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // All output pins must be assigned. If not used, assign to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  hvsync_generator hvsync_gen(
     .clk(clk),
     .reset(~rst_n),
     .hsync(hsync),
     .vsync(vsync),
     .display_on(display_on),
     .hpos(hpos),
     .vpos(vpos)
  );

  palette palette_inst (
    .color(color),
    .rrggbb(rrggbb)
  );

  tunnel tunnel_demo (
    .vsync(vsync),
    .rst_n(rst_n),
    .frame(frame[1:0]),
    .hpos(hpos),
    .vpos(vpos),
    .color(tunnel_color)
  );

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in[7:3], uio_in, 1'b0};

  assign color = tunnel_color;

  assign R = display_on ? rrggbb[5:4] : 2'b00;
  assign G = display_on ? rrggbb[3:2] : 2'b00;
  assign B = display_on ? rrggbb[1:0] : 2'b00;

  reg [9:0] frame;
  always @(posedge vsync or negedge rst_n) begin
    if (~rst_n) begin
      frame <= 0;
    end else begin
      frame <= frame + 1;
    end
  end

endmodule


module tunnel (vsync, rst_n, frame, hpos, vpos, color);
  input wire vsync;
  input wire rst_n;
  input wire [1:0] frame;
  input wire [9:0] hpos;
  input wire [9:0] vpos;
  output wire [7:0] color;

  parameter WIDTH = 640;
  parameter HEIGHT = 480;
  parameter WIDTH_2 = WIDTH / 2;
  parameter HEIGHT_2 = HEIGHT / 2;

  wire [9:0] xlook;
  wire [9:0] ylook;
  wire signed [9:0] xsine_out;
  wire signed [9:0] ysine_out;
  wire signed [10:0] xi;
  wire signed [10:0] yi;

  wire [7:0] u;
  wire [7:0] v;

  reg [9:0] xpos;
  reg [9:0] ypos;
  reg [7:0] aoff;
  reg [7:0] doff;

  always @(posedge vsync or negedge rst_n) begin
    if (~rst_n) begin
      xpos <= 0;
      ypos <= 0;
      aoff <= 0;
      doff <= 0;
    end else begin
      if (frame[0]) begin
        xpos <= xpos + 1;
        aoff <= aoff + 1;
      end
      if (frame[1]) begin
        ypos <= ypos + 1;
      end
      // Every frame
      doff <= doff + 6;
    end
  end

  cordic_sine xsine(
    .angle(xpos),
    .sine(xsine_out)
  );

  cordic_sine ysine(
    .angle(ypos),
    .sine(ysine_out)
  );

  wire [9:0] r;
  wire [9:0] theta;
  cordic_atan polar_inst(
    .x(xi),
    .y(yi),
    .r(r),
    .theta(theta)
  );

  wire [7:0] d;
  perspective p_inst(
    .r(r),
    .out(d)
  );

  assign xlook = WIDTH_2 + (xsine_out >>> 1);
  assign ylook = HEIGHT_2 + ((ysine_out >>> 1) * 3) >> 2;
  assign xi = hpos + xlook - WIDTH;
  assign yi = vpos + ylook - HEIGHT;
  assign u = theta[9:2] + aoff;
  assign v = d + doff;

  assign color = u ^ v;
endmodule


module cordic (
    input signed [10:0] x_in,
    input signed [10:0] y_in,
    input signed [9:0] z_in,
    input rotation_en,
    output signed [10:0] x_out,
    output signed [10:0] y_out,
    output signed [9:0] z_out
);

  parameter NUM_STEPS = 9;

  // Define 10-bit (9-step) CORDIC angle table
  wire [NUM_STEPS:0] atan_table [0:NUM_STEPS - 1];
  assign atan_table[0] = 10'd128;
  assign atan_table[1] = 10'd76;
  assign atan_table[2] = 10'd40;
  assign atan_table[3] = 10'd20;
  assign atan_table[4] = 10'd10;
  assign atan_table[5] = 10'd5;
  assign atan_table[6] = 10'd3;
  assign atan_table[7] = 10'd1;
  assign atan_table[8] = 10'd1;

  reg signed [10:0] x_i [0:NUM_STEPS];
  reg signed [10:0] y_i [0:NUM_STEPS];
  reg signed o_i [0:NUM_STEPS];
  reg signed [9:0] z_i [0:NUM_STEPS];

  integer i;
  always @(*) begin
    x_i[0] = x_in;
    y_i[0] = y_in;
    z_i[0] = z_in;

    // For rotation mode, o_i is sign(z_i)
    //  sign of z_i is complement of the highest bit
    // For vectoring mode, o_i is -sign(y_i)

    for (i = 0; i < NUM_STEPS; i += 1) begin
      o_i[i] = rotation_en ? ~z_i[i][9] : y_i[i][10];
      if (o_i[i]) begin
        x_i[i+1] = x_i[i] - (y_i[i] >>> i);
        y_i[i+1] = y_i[i] + (x_i[i] >>> i);
        z_i[i+1] = z_i[i] - atan_table[i];
      end else begin
        x_i[i+1] = x_i[i] + (y_i[i] >>> i);
        y_i[i+1] = y_i[i] - (x_i[i] >>> i);
        z_i[i+1] = z_i[i] + atan_table[i];
      end
    end
  end

  assign x_out = x_i[NUM_STEPS];
  assign y_out = y_i[NUM_STEPS];
  assign z_out = z_i[NUM_STEPS];

endmodule


module cordic_atan (x, y, r, theta);
  input signed [10:0] x;
  input signed [10:0] y;
  output [9:0] r;
  output [9:0] theta;

  parameter [10:0] CORDIC_GAIN = 11'b10011011100;  // ~0.607253 * 2^10 (1/An)

  wire signed [10:0] x_out, y_out;
  wire signed [9:0] z_out;
  wire signed [10:0] x_abs, y_abs;

  assign x_abs = x < 0 ? -x : x;
  assign y_abs = y < 0 ? -y : y;

  cordic core (
    .x_in(x_abs),
    .y_in(y_abs),
    .z_in(10'd0),
    .rotation_en(1'b0),
    .x_out(x_out),
    .y_out(y_out),
    .z_out(z_out)
  );

  wire [21:0] r_unscaled = x_out * CORDIC_GAIN;
  assign r = r_unscaled[20:11];

  wire [9:0] theta_abs = z_out < 0 ? -z_out : z_out;
  assign theta = (x > 0) ?
                 (y < 0 ? -theta_abs : theta_abs) :
                 (y < 0 ? -512 + theta_abs : 511 - theta_abs);
endmodule


module cordic_sine (angle, sine);
  input signed [9:0] angle;
  output signed [9:0] sine;

  //parameter [10:0] CORDIC_GAIN = 11'b10011011100;  // ~0.607253 * 2^10 (1/An)
  parameter [10:0] CORDIC_GAIN = 11'b10011000000;  // ~1.647 * 320

  wire signed [10:0] x_out, y_out;
  wire signed [9:0] z_out;

  cordic core (
    .x_in(CORDIC_GAIN),
    .y_in(11'd0),
    .z_in(angle),
    .rotation_en(1'b1),
    .x_out(x_out),
    .y_out(y_out),
    .z_out(z_out)
  );

  assign sine = y_out[10:1];

endmodule


module perspective (r, out);
  input wire[9:0] r;
  output wire[7:0] out;

  reg [7:0] plut[800:0];

  initial begin
    plut[0] = 0;
    plut[1] = 0;
    plut[2] = 0;
    plut[3] = 170;
    plut[4] = 0;
    plut[5] = 102;
    plut[6] = 85;
    plut[7] = 146;
    plut[8] = 0;
    plut[9] = 142;
    plut[10] = 51;
    plut[11] = 232;
    plut[12] = 170;
    plut[13] = 118;
    plut[14] = 73;
    plut[15] = 34;
    plut[16] = 0;
    plut[17] = 225;
    plut[18] = 199;
    plut[19] = 175;
    plut[20] = 153;
    plut[21] = 134;
    plut[22] = 116;
    plut[23] = 100;
    plut[24] = 85;
    plut[25] = 71;
    plut[26] = 59;
    plut[27] = 47;
    plut[28] = 36;
    plut[29] = 26;
    plut[30] = 17;
    plut[31] = 8;
    plut[32] = 0;
    plut[33] = 248;
    plut[34] = 240;
    plut[35] = 234;
    plut[36] = 227;
    plut[37] = 221;
    plut[38] = 215;
    plut[39] = 210;
    plut[40] = 204;
    plut[41] = 199;
    plut[42] = 195;
    plut[43] = 190;
    plut[44] = 186;
    plut[45] = 182;
    plut[46] = 178;
    plut[47] = 174;
    plut[48] = 170;
    plut[49] = 167;
    plut[50] = 163;
    plut[51] = 160;
    plut[52] = 157;
    plut[53] = 154;
    plut[54] = 151;
    plut[55] = 148;
    plut[56] = 146;
    plut[57] = 143;
    plut[58] = 141;
    plut[59] = 138;
    plut[60] = 136;
    plut[61] = 134;
    plut[62] = 132;
    plut[63] = 130;
    plut[64] = 128;
    plut[65] = 126;
    plut[66] = 124;
    plut[67] = 122;
    plut[68] = 120;
    plut[69] = 118;
    plut[70] = 117;
    plut[71] = 115;
    plut[72] = 113;
    plut[73] = 112;
    plut[74] = 110;
    plut[75] = 109;
    plut[76] = 107;
    plut[77] = 106;
    plut[78] = 105;
    plut[79] = 103;
    plut[80] = 102;
    plut[81] = 101;
    plut[82] = 99;
    plut[83] = 98;
    plut[84] = 97;
    plut[85] = 96;
    plut[86] = 95;
    plut[87] = 94;
    plut[88] = 93;
    plut[89] = 92;
    plut[90] = 91;
    plut[91] = 90;
    plut[92] = 89;
    plut[93] = 88;
    plut[94] = 87;
    plut[95] = 86;
    plut[96] = 85;
    plut[97] = 84;
    plut[98] = 83;
    plut[99] = 82;
    plut[100] = 81;
    plut[101] = 81;
    plut[102] = 80;
    plut[103] = 79;
    plut[104] = 78;
    plut[105] = 78;
    plut[106] = 77;
    plut[107] = 76;
    plut[108] = 75;
    plut[109] = 75;
    plut[110] = 74;
    plut[111] = 73;
    plut[112] = 73;
    plut[113] = 72;
    plut[114] = 71;
    plut[115] = 71;
    plut[116] = 70;
    plut[117] = 70;
    plut[118] = 69;
    plut[119] = 68;
    plut[120] = 68;
    plut[121] = 67;
    plut[122] = 67;
    plut[123] = 66;
    plut[124] = 66;
    plut[125] = 65;
    plut[126] = 65;
    plut[127] = 64;
    plut[128] = 64;
    plut[129] = 63;
    plut[130] = 63;
    plut[131] = 62;
    plut[132] = 62;
    plut[133] = 61;
    plut[134] = 61;
    plut[135] = 60;
    plut[136] = 60;
    plut[137] = 59;
    plut[138] = 59;
    plut[139] = 58;
    plut[140] = 58;
    plut[141] = 58;
    plut[142] = 57;
    plut[143] = 57;
    plut[144] = 56;
    plut[145] = 56;
    plut[146] = 56;
    plut[147] = 55;
    plut[148] = 55;
    plut[149] = 54;
    plut[150] = 54;
    plut[151] = 54;
    plut[152] = 53;
    plut[153] = 53;
    plut[154] = 53;
    plut[155] = 52;
    plut[156] = 52;
    plut[157] = 52;
    plut[158] = 51;
    plut[159] = 51;
    plut[160] = 51;
    plut[161] = 50;
    plut[162] = 50;
    plut[163] = 50;
    plut[164] = 49;
    plut[165] = 49;
    plut[166] = 49;
    plut[167] = 49;
    plut[168] = 48;
    plut[169] = 48;
    plut[170] = 48;
    plut[171] = 47;
    plut[172] = 47;
    plut[173] = 47;
    plut[174] = 47;
    plut[175] = 46;
    plut[176] = 46;
    plut[177] = 46;
    plut[178] = 46;
    plut[179] = 45;
    plut[180] = 45;
    plut[181] = 45;
    plut[182] = 45;
    plut[183] = 44;
    plut[184] = 44;
    plut[185] = 44;
    plut[186] = 44;
    plut[187] = 43;
    plut[188] = 43;
    plut[189] = 43;
    plut[190] = 43;
    plut[191] = 42;
    plut[192] = 42;
    plut[193] = 42;
    plut[194] = 42;
    plut[195] = 42;
    plut[196] = 41;
    plut[197] = 41;
    plut[198] = 41;
    plut[199] = 41;
    plut[200] = 40;
    plut[201] = 40;
    plut[202] = 40;
    plut[203] = 40;
    plut[204] = 40;
    plut[205] = 39;
    plut[206] = 39;
    plut[207] = 39;
    plut[208] = 39;
    plut[209] = 39;
    plut[210] = 39;
    plut[211] = 38;
    plut[212] = 38;
    plut[213] = 38;
    plut[214] = 38;
    plut[215] = 38;
    plut[216] = 37;
    plut[217] = 37;
    plut[218] = 37;
    plut[219] = 37;
    plut[220] = 37;
    plut[221] = 37;
    plut[222] = 36;
    plut[223] = 36;
    plut[224] = 36;
    plut[225] = 36;
    plut[226] = 36;
    plut[227] = 36;
    plut[228] = 35;
    plut[229] = 35;
    plut[230] = 35;
    plut[231] = 35;
    plut[232] = 35;
    plut[233] = 35;
    plut[234] = 35;
    plut[235] = 34;
    plut[236] = 34;
    plut[237] = 34;
    plut[238] = 34;
    plut[239] = 34;
    plut[240] = 34;
    plut[241] = 33;
    plut[242] = 33;
    plut[243] = 33;
    plut[244] = 33;
    plut[245] = 33;
    plut[246] = 33;
    plut[247] = 33;
    plut[248] = 33;
    plut[249] = 32;
    plut[250] = 32;
    plut[251] = 32;
    plut[252] = 32;
    plut[253] = 32;
    plut[254] = 32;
    plut[255] = 32;
    plut[256] = 32;
    plut[257] = 31;
    plut[258] = 31;
    plut[259] = 31;
    plut[260] = 31;
    plut[261] = 31;
    plut[262] = 31;
    plut[263] = 31;
    plut[264] = 31;
    plut[265] = 30;
    plut[266] = 30;
    plut[267] = 30;
    plut[268] = 30;
    plut[269] = 30;
    plut[270] = 30;
    plut[271] = 30;
    plut[272] = 30;
    plut[273] = 30;
    plut[274] = 29;
    plut[275] = 29;
    plut[276] = 29;
    plut[277] = 29;
    plut[278] = 29;
    plut[279] = 29;
    plut[280] = 29;
    plut[281] = 29;
    plut[282] = 29;
    plut[283] = 28;
    plut[284] = 28;
    plut[285] = 28;
    plut[286] = 28;
    plut[287] = 28;
    plut[288] = 28;
    plut[289] = 28;
    plut[290] = 28;
    plut[291] = 28;
    plut[292] = 28;
    plut[293] = 27;
    plut[294] = 27;
    plut[295] = 27;
    plut[296] = 27;
    plut[297] = 27;
    plut[298] = 27;
    plut[299] = 27;
    plut[300] = 27;
    plut[301] = 27;
    plut[302] = 27;
    plut[303] = 27;
    plut[304] = 26;
    plut[305] = 26;
    plut[306] = 26;
    plut[307] = 26;
    plut[308] = 26;
    plut[309] = 26;
    plut[310] = 26;
    plut[311] = 26;
    plut[312] = 26;
    plut[313] = 26;
    plut[314] = 26;
    plut[315] = 26;
    plut[316] = 25;
    plut[317] = 25;
    plut[318] = 25;
    plut[319] = 25;
    plut[320] = 25;
    plut[321] = 25;
    plut[322] = 25;
    plut[323] = 25;
    plut[324] = 25;
    plut[325] = 25;
    plut[326] = 25;
    plut[327] = 25;
    plut[328] = 24;
    plut[329] = 24;
    plut[330] = 24;
    plut[331] = 24;
    plut[332] = 24;
    plut[333] = 24;
    plut[334] = 24;
    plut[335] = 24;
    plut[336] = 24;
    plut[337] = 24;
    plut[338] = 24;
    plut[339] = 24;
    plut[340] = 24;
    plut[341] = 24;
    plut[342] = 23;
    plut[343] = 23;
    plut[344] = 23;
    plut[345] = 23;
    plut[346] = 23;
    plut[347] = 23;
    plut[348] = 23;
    plut[349] = 23;
    plut[350] = 23;
    plut[351] = 23;
    plut[352] = 23;
    plut[353] = 23;
    plut[354] = 23;
    plut[355] = 23;
    plut[356] = 23;
    plut[357] = 22;
    plut[358] = 22;
    plut[359] = 22;
    plut[360] = 22;
    plut[361] = 22;
    plut[362] = 22;
    plut[363] = 22;
    plut[364] = 22;
    plut[365] = 22;
    plut[366] = 22;
    plut[367] = 22;
    plut[368] = 22;
    plut[369] = 22;
    plut[370] = 22;
    plut[371] = 22;
    plut[372] = 22;
    plut[373] = 21;
    plut[374] = 21;
    plut[375] = 21;
    plut[376] = 21;
    plut[377] = 21;
    plut[378] = 21;
    plut[379] = 21;
    plut[380] = 21;
    plut[381] = 21;
    plut[382] = 21;
    plut[383] = 21;
    plut[384] = 21;
    plut[385] = 21;
    plut[386] = 21;
    plut[387] = 21;
    plut[388] = 21;
    plut[389] = 21;
    plut[390] = 21;
    plut[391] = 20;
    plut[392] = 20;
    plut[393] = 20;
    plut[394] = 20;
    plut[395] = 20;
    plut[396] = 20;
    plut[397] = 20;
    plut[398] = 20;
    plut[399] = 20;
    plut[400] = 20;
    plut[401] = 20;
    plut[402] = 20;
    plut[403] = 20;
    plut[404] = 20;
    plut[405] = 20;
    plut[406] = 20;
    plut[407] = 20;
    plut[408] = 20;
    plut[409] = 20;
    plut[410] = 19;
    plut[411] = 19;
    plut[412] = 19;
    plut[413] = 19;
    plut[414] = 19;
    plut[415] = 19;
    plut[416] = 19;
    plut[417] = 19;
    plut[418] = 19;
    plut[419] = 19;
    plut[420] = 19;
    plut[421] = 19;
    plut[422] = 19;
    plut[423] = 19;
    plut[424] = 19;
    plut[425] = 19;
    plut[426] = 19;
    plut[427] = 19;
    plut[428] = 19;
    plut[429] = 19;
    plut[430] = 19;
    plut[431] = 19;
    plut[432] = 18;
    plut[433] = 18;
    plut[434] = 18;
    plut[435] = 18;
    plut[436] = 18;
    plut[437] = 18;
    plut[438] = 18;
    plut[439] = 18;
    plut[440] = 18;
    plut[441] = 18;
    plut[442] = 18;
    plut[443] = 18;
    plut[444] = 18;
    plut[445] = 18;
    plut[446] = 18;
    plut[447] = 18;
    plut[448] = 18;
    plut[449] = 18;
    plut[450] = 18;
    plut[451] = 18;
    plut[452] = 18;
    plut[453] = 18;
    plut[454] = 18;
    plut[455] = 18;
    plut[456] = 17;
    plut[457] = 17;
    plut[458] = 17;
    plut[459] = 17;
    plut[460] = 17;
    plut[461] = 17;
    plut[462] = 17;
    plut[463] = 17;
    plut[464] = 17;
    plut[465] = 17;
    plut[466] = 17;
    plut[467] = 17;
    plut[468] = 17;
    plut[469] = 17;
    plut[470] = 17;
    plut[471] = 17;
    plut[472] = 17;
    plut[473] = 17;
    plut[474] = 17;
    plut[475] = 17;
    plut[476] = 17;
    plut[477] = 17;
    plut[478] = 17;
    plut[479] = 17;
    plut[480] = 17;
    plut[481] = 17;
    plut[482] = 16;
    plut[483] = 16;
    plut[484] = 16;
    plut[485] = 16;
    plut[486] = 16;
    plut[487] = 16;
    plut[488] = 16;
    plut[489] = 16;
    plut[490] = 16;
    plut[491] = 16;
    plut[492] = 16;
    plut[493] = 16;
    plut[494] = 16;
    plut[495] = 16;
    plut[496] = 16;
    plut[497] = 16;
    plut[498] = 16;
    plut[499] = 16;
    plut[500] = 16;
    plut[501] = 16;
    plut[502] = 16;
    plut[503] = 16;
    plut[504] = 16;
    plut[505] = 16;
    plut[506] = 16;
    plut[507] = 16;
    plut[508] = 16;
    plut[509] = 16;
    plut[510] = 16;
    plut[511] = 16;
    plut[512] = 16;
    plut[513] = 15;
    plut[514] = 15;
    plut[515] = 15;
    plut[516] = 15;
    plut[517] = 15;
    plut[518] = 15;
    plut[519] = 15;
    plut[520] = 15;
    plut[521] = 15;
    plut[522] = 15;
    plut[523] = 15;
    plut[524] = 15;
    plut[525] = 15;
    plut[526] = 15;
    plut[527] = 15;
    plut[528] = 15;
    plut[529] = 15;
    plut[530] = 15;
    plut[531] = 15;
    plut[532] = 15;
    plut[533] = 15;
    plut[534] = 15;
    plut[535] = 15;
    plut[536] = 15;
    plut[537] = 15;
    plut[538] = 15;
    plut[539] = 15;
    plut[540] = 15;
    plut[541] = 15;
    plut[542] = 15;
    plut[543] = 15;
    plut[544] = 15;
    plut[545] = 15;
    plut[546] = 15;
    plut[547] = 14;
    plut[548] = 14;
    plut[549] = 14;
    plut[550] = 14;
    plut[551] = 14;
    plut[552] = 14;
    plut[553] = 14;
    plut[554] = 14;
    plut[555] = 14;
    plut[556] = 14;
    plut[557] = 14;
    plut[558] = 14;
    plut[559] = 14;
    plut[560] = 14;
    plut[561] = 14;
    plut[562] = 14;
    plut[563] = 14;
    plut[564] = 14;
    plut[565] = 14;
    plut[566] = 14;
    plut[567] = 14;
    plut[568] = 14;
    plut[569] = 14;
    plut[570] = 14;
    plut[571] = 14;
    plut[572] = 14;
    plut[573] = 14;
    plut[574] = 14;
    plut[575] = 14;
    plut[576] = 14;
    plut[577] = 14;
    plut[578] = 14;
    plut[579] = 14;
    plut[580] = 14;
    plut[581] = 14;
    plut[582] = 14;
    plut[583] = 14;
    plut[584] = 14;
    plut[585] = 14;
    plut[586] = 13;
    plut[587] = 13;
    plut[588] = 13;
    plut[589] = 13;
    plut[590] = 13;
    plut[591] = 13;
    plut[592] = 13;
    plut[593] = 13;
    plut[594] = 13;
    plut[595] = 13;
    plut[596] = 13;
    plut[597] = 13;
    plut[598] = 13;
    plut[599] = 13;
    plut[600] = 13;
    plut[601] = 13;
    plut[602] = 13;
    plut[603] = 13;
    plut[604] = 13;
    plut[605] = 13;
    plut[606] = 13;
    plut[607] = 13;
    plut[608] = 13;
    plut[609] = 13;
    plut[610] = 13;
    plut[611] = 13;
    plut[612] = 13;
    plut[613] = 13;
    plut[614] = 13;
    plut[615] = 13;
    plut[616] = 13;
    plut[617] = 13;
    plut[618] = 13;
    plut[619] = 13;
    plut[620] = 13;
    plut[621] = 13;
    plut[622] = 13;
    plut[623] = 13;
    plut[624] = 13;
    plut[625] = 13;
    plut[626] = 13;
    plut[627] = 13;
    plut[628] = 13;
    plut[629] = 13;
    plut[630] = 13;
    plut[631] = 12;
    plut[632] = 12;
    plut[633] = 12;
    plut[634] = 12;
    plut[635] = 12;
    plut[636] = 12;
    plut[637] = 12;
    plut[638] = 12;
    plut[639] = 12;
    plut[640] = 12;
    plut[641] = 12;
    plut[642] = 12;
    plut[643] = 12;
    plut[644] = 12;
    plut[645] = 12;
    plut[646] = 12;
    plut[647] = 12;
    plut[648] = 12;
    plut[649] = 12;
    plut[650] = 12;
    plut[651] = 12;
    plut[652] = 12;
    plut[653] = 12;
    plut[654] = 12;
    plut[655] = 12;
    plut[656] = 12;
    plut[657] = 12;
    plut[658] = 12;
    plut[659] = 12;
    plut[660] = 12;
    plut[661] = 12;
    plut[662] = 12;
    plut[663] = 12;
    plut[664] = 12;
    plut[665] = 12;
    plut[666] = 12;
    plut[667] = 12;
    plut[668] = 12;
    plut[669] = 12;
    plut[670] = 12;
    plut[671] = 12;
    plut[672] = 12;
    plut[673] = 12;
    plut[674] = 12;
    plut[675] = 12;
    plut[676] = 12;
    plut[677] = 12;
    plut[678] = 12;
    plut[679] = 12;
    plut[680] = 12;
    plut[681] = 12;
    plut[682] = 12;
    plut[683] = 11;
    plut[684] = 11;
    plut[685] = 11;
    plut[686] = 11;
    plut[687] = 11;
    plut[688] = 11;
    plut[689] = 11;
    plut[690] = 11;
    plut[691] = 11;
    plut[692] = 11;
    plut[693] = 11;
    plut[694] = 11;
    plut[695] = 11;
    plut[696] = 11;
    plut[697] = 11;
    plut[698] = 11;
    plut[699] = 11;
    plut[700] = 11;
    plut[701] = 11;
    plut[702] = 11;
    plut[703] = 11;
    plut[704] = 11;
    plut[705] = 11;
    plut[706] = 11;
    plut[707] = 11;
    plut[708] = 11;
    plut[709] = 11;
    plut[710] = 11;
    plut[711] = 11;
    plut[712] = 11;
    plut[713] = 11;
    plut[714] = 11;
    plut[715] = 11;
    plut[716] = 11;
    plut[717] = 11;
    plut[718] = 11;
    plut[719] = 11;
    plut[720] = 11;
    plut[721] = 11;
    plut[722] = 11;
    plut[723] = 11;
    plut[724] = 11;
    plut[725] = 11;
    plut[726] = 11;
    plut[727] = 11;
    plut[728] = 11;
    plut[729] = 11;
    plut[730] = 11;
    plut[731] = 11;
    plut[732] = 11;
    plut[733] = 11;
    plut[734] = 11;
    plut[735] = 11;
    plut[736] = 11;
    plut[737] = 11;
    plut[738] = 11;
    plut[739] = 11;
    plut[740] = 11;
    plut[741] = 11;
    plut[742] = 11;
    plut[743] = 11;
    plut[744] = 11;
    plut[745] = 10;
    plut[746] = 10;
    plut[747] = 10;
    plut[748] = 10;
    plut[749] = 10;
    plut[750] = 10;
    plut[751] = 10;
    plut[752] = 10;
    plut[753] = 10;
    plut[754] = 10;
    plut[755] = 10;
    plut[756] = 10;
    plut[757] = 10;
    plut[758] = 10;
    plut[759] = 10;
    plut[760] = 10;
    plut[761] = 10;
    plut[762] = 10;
    plut[763] = 10;
    plut[764] = 10;
    plut[765] = 10;
    plut[766] = 10;
    plut[767] = 10;
    plut[768] = 10;
    plut[769] = 10;
    plut[770] = 10;
    plut[771] = 10;
    plut[772] = 10;
    plut[773] = 10;
    plut[774] = 10;
    plut[775] = 10;
    plut[776] = 10;
    plut[777] = 10;
    plut[778] = 10;
    plut[779] = 10;
    plut[780] = 10;
    plut[781] = 10;
    plut[782] = 10;
    plut[783] = 10;
    plut[784] = 10;
    plut[785] = 10;
    plut[786] = 10;
    plut[787] = 10;
    plut[788] = 10;
    plut[789] = 10;
    plut[790] = 10;
    plut[791] = 10;
    plut[792] = 10;
    plut[793] = 10;
    plut[794] = 10;
    plut[795] = 10;
    plut[796] = 10;
    plut[797] = 10;
    plut[798] = 10;
    plut[799] = 10;
    plut[800] = 10;
  end

  assign out = plut[r];

endmodule


module palette (color, rrggbb);
  input wire [7:0] color;
  output wire [5:0] rrggbb;

  reg [5:0] palette;

  always @(color) begin
    case(1)
      color < 14: palette = 6'b110000;
      color >= 14 && color < 28: palette = 6'b110100;
      color >= 28 && color < 43: palette = 6'b111000;
      color >= 43 && color < 57: palette = 6'b111100;
      color >= 57 && color < 71: palette = 6'b101100;
      color >= 71 && color < 85: palette = 6'b011100;
      color >= 85 && color < 100: palette = 6'b001100;
      color >= 100 && color < 114: palette = 6'b001101;
      color >= 114 && color < 128: palette = 6'b001110;
      color >= 128 && color < 142: palette = 6'b001111;
      color >= 142 && color < 156: palette = 6'b001011;
      color >= 156 && color < 171: palette = 6'b000111;
      color >= 171 && color < 185: palette = 6'b000011;
      color >= 185 && color < 199: palette = 6'b010011;
      color >= 199 && color < 213: palette = 6'b100011;
      color >= 213 && color < 228: palette = 6'b110011;
      color >= 228 && color < 242: palette = 6'b110010;
      color >= 242: palette = 6'b110001;
    endcase
  end

  assign rrggbb = palette;
endmodule
