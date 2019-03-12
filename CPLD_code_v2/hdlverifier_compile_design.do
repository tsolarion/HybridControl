# Create design library
vlib work
# Create and open project
project new . compile_project
project open compile_project
# Add source files to project
project addfile "C:/Users/tsolarig/Desktop/CPLD_code/CPLD_current_top.vhd"
project addfile "C:/Users/tsolarig/Desktop/CPLD_code/moving_avg.vhd"
project addfile "C:/Users/tsolarig/Desktop/CPLD_code/statemachine.vhd"
# Calculate compilation order
project calculateorder
set compcmd [project compileall -n]
# Close project
project close
# Compile all files and report error
if [catch {eval $compcmd}] {
    exit -code 1
}
