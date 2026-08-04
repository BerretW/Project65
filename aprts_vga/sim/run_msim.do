# ============================================================
# ModelSim / Questa-Intel DO script for APARTS_BUS tests
# Usage (from aprts_vga/sim):
#   vsim -c -do run_msim.do
# Or from Quartus: Tools → Run Simulation Tool → RTL Simulation
# ============================================================

if {[file exists work]} {
    vdel -all
}
vlib work
vmap work work

set ROOT ..

# DUT sources
vlog -work work $ROOT/vga_timing.v
vlog -work work $ROOT/vga_video_gen.v
vlog -work work $ROOT/sram_controller.v
vlog -work work $ROOT/aprts_audio.v
vlog -work work $ROOT/aprts_bus.v

# TB + models
vlog -work work sram_model.v
vlog -work work tb_vga_timing.v
vlog -work work tb_aprts_audio.v
vlog -work work tb_aprts_bus.v

puts "========== RUN tb_vga_timing =========="
vsim -c work.tb_vga_timing
run -all
quit -sim

puts "========== RUN tb_aprts_audio =========="
vsim -c work.tb_aprts_audio
run -all
quit -sim

puts "========== RUN tb_aprts_bus =========="
vsim -c work.tb_aprts_bus
run -all
quit -sim

puts "========== ALL SIMS FINISHED =========="
quit -f
