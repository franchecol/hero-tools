proc hex32 {value} {
    return [format "0x%08x" [expr {$value & 0xffffffff}]]
}

proc read32 {master offset} {
    set values [master_read_32 $master $offset 1]
    return [lindex $values 0]
}

proc write32 {master offset value} {
    master_write_32 $master $offset $value
}

set masters [get_service_paths master]
if {[llength $masters] == 0} {
    error "No System Console master service found. Program the S8 bitstream first."
}

set master [lindex $masters 0]
open_service master $master
puts "Using master: $master"

set REG_ID          0x00
set REG_CONTROL     0x04
set REG_STATUS      0x08
set REG_RESULT      0x0c
set REG_START_COUNT 0x10
set REG_RUN_CYCLES  0x14
set REG_ROM_WORDS   0x18
set REG_RAM0        0x1c

set id [read32 $master $REG_ID]
puts "ID          = [hex32 $id]"
if {$id != 0x53380001} {
    error "Unexpected ID register. Expected 0x53380001."
}

write32 $master $REG_CONTROL 0x2
after 10

set status [read32 $master $REG_STATUS]
puts "STATUS clr  = [hex32 $status]"
if {$status != 0x0} {
    error "Unexpected non-zero status after clear."
}

write32 $master $REG_CONTROL 0x1
puts "Started Snitch-Lite RAM check"

set status 0
for {set i 0} {$i < 200} {incr i} {
    after 10
    set status [read32 $master $REG_STATUS]
    if {$status & 0x1} {
        break
    }
}

set result [read32 $master $REG_RESULT]
set starts [read32 $master $REG_START_COUNT]
set cycles [read32 $master $REG_RUN_CYCLES]
set words  [read32 $master $REG_ROM_WORDS]
set ram0   [read32 $master $REG_RAM0]

puts "STATUS      = [hex32 $status]"
puts "RESULT      = [hex32 $result]"
puts "START_COUNT = [hex32 $starts]"
puts "RUN_CYCLES  = [hex32 $cycles]"
puts "ROM_WORDS   = [hex32 $words]"
puts "RAM0        = [hex32 $ram0]"

if {($status & 0x1) == 0} {
    error "Timed out waiting for done."
}

if {($status & 0x4) == 0} {
    error "PASS bit is not set."
}

if {($status & 0x8) != 0} {
    error "FAIL bit is set."
}

if {$result != 0x1a5} {
    error "Unexpected result. Expected 0x1a5."
}

if {$ram0 != 0x0a5} {
    error "Unexpected RAM0. Expected 0x0a5."
}

if {$starts != 0x1} {
    error "Unexpected start count. Expected 1."
}

puts "S8 JTAG host-control smoke test passed."
close_service master $master
