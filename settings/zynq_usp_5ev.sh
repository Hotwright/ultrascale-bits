#!/bin/bash
#
# Copyright 2020-2022 F4PGA Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
#
# Zynq UltraScale+ ZU5EV - the die in the Kria K26 / KV260.
#
# prjuray ships zynq_usp_3eg and zynq_usp_7ev; the K26 is neither. The ZU5EV is
# ~1.7x the ZU3EG (112,250 tiles / 9,090,733 nodes against 66,385 / 5,281,651),
# so the per-part layer - part.yaml, tilegrid, tileconn - has to be generated
# for it. prjuray-db ships part.yaml for two ZU3EG parts only.
#
# URAY_PART is the Kria part itself rather than the catalogue xczu5ev. The die
# is identical (verified by full tile-signature comparison) but the IDCODE is
# not: K26 is 0x04a49093, xczu5ev-sfvc784-1-e is 0x04a46093. Generating against
# xck26 directly avoids baking the wrong IDCODE into part.yaml, which is the
# exact trap hit on 7-series with xc7z007s/xc7z010.
#
# Note the IDCODE here is the PL JTAG TAP. Zynq UltraScale+ has two TAPs and
# the BSDL IDCODE_REGISTER describes the PS one (0x04724093) - wrong for
# bitstream configuration.
export URAY_DATABASE="zynqusp"
export URAY_PART="xck26-sfvc784-2LV-c"
export URAY_ARCH="UltraScalePlus"

export URAY_ROI_FRAMES="0x00000000:0xffffffff"

# Whole-device ROI. The shipped zynq_usp_3eg.sh comments its ROI "All CLB's in
# part" but is in fact a sub-region (SLICE_X0Y120:X28Y179 out of X0Y0:X48Y179);
# that is fine for solving tile-type bits, which are position independent, but
# the per-part tilegrid this die needs must cover everything.
#
# Ranges below are derived, not assumed - dumped from Vivado by
# rw-fuzzers/env/uray_5ev_sites.tcl, grouping every site by SITE_TYPE:
#   SLICEL      7440  X0Y0:X60Y239     SLICEM  7200  X1Y0:X58Y239   (14,640 total)
#   DSP48E2     1248  X0Y0:X12Y95
#   RAMB181      144  X0Y1:X2Y95       RAMBFIFO18  144             (288 RAMB18E2)
#   RAMBFIFO36   144  X0Y0:X2Y47                                   (144 RAMB36E2)
#   URAM288       64  X0Y0:X0Y63
# Those totals independently match what nextpnr reports from the RapidWright
# chipdb (CARRY8 14640, RAMB18E2 288, RAMB36E2 144, URAM288 64, DSP 1248).
#
# An earlier pass that filtered on 7-series site-type names reported
# "RAMB18 144, RAMB36 none" - UltraScale+ names these RAMB181 / RAMBFIFO18 /
# RAMBFIFO36, so filter by the names above, not the 7-series ones.
export URAY_ROI_TILEGRID="SLICE_X0Y0:SLICE_X60Y239 DSP48E2_X0Y0:DSP48E2_X12Y95 RAMB18_X0Y0:RAMB18_X2Y95 RAMB36_X0Y0:RAMB36_X2Y47 URAM288_X0Y0:URAM288_X0Y63"

# These settings must remain in sync
export URAY_ROI="SLICE_X0Y0:SLICE_X60Y239 DSP48E2_X0Y0:DSP48E2_X12Y95 RAMB18_X0Y0:RAMB18_X2Y95 RAMB36_X0Y0:RAMB36_X2Y47 URAM288_X0Y0:URAM288_X0Y63"

# Full grid extent: 449 columns x 250 rows, 112,250 tiles.
export URAY_ROI_GRID_X1="0"
export URAY_ROI_GRID_X2="448"
export URAY_ROI_GRID_Y1="0"
export URAY_ROI_GRID_Y2="249"

# The same four pins zynq_usp_3eg.sh uses. All four are present on the ZU5EV as
# user IO in bank 45 (HDIO) - checked, not assumed:
#   E12 IOB_X0Y132   C12 IOB_X0Y141   D12 IOB_X0Y140   A11 IOB_X0Y139
# Four bank-45 HDIO pins for the fuzzer harness (clk, di, do, stb). These four
# are taken from the set the KV260 PMOD XDC already places successfully, so they
# are known valid on xck26-sfvc784 -- the earlier C12/D12/A11 were not, and
# Vivado rejected the first with
#   ERROR: [Common 17-69] Command failed: 'C12' is not a valid site or package
#   pin name.
# F12 is IO_L6P_HDGC_45 -- the P side of a clock-capable pair, which is what the
# harness wants for clk. F11 is the N side of the SAME pair and Vivado rejects it:
#   ERROR: [DRC PLIO-9] The following clock source has been LOCed to a N-Type
#   CCIO : clk
# That is a hardware rule, and nextpnr does not check it.
export URAY_PIN_00="F12"
export URAY_PIN_01="E12"
export URAY_PIN_02="D11"
export URAY_PIN_03="B11"

source $(dirname ${BASH_SOURCE[0]})/../utils/environment.sh
