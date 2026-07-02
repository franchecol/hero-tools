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
    error "No System Console master service found. Program the D2 bitstream first."
}

set master [lindex $masters 0]
open_service master $master
puts "Using master: $master"

set REG_ID      0x00
set REG_CONTROL 0x04
set REG_STATUS  0x08
set REG_A       0x0c
set REG_B       0x10
set REG_OPCODE  0x14
set REG_RESULT  0x18
set REG_CYCLES  0x1c

set id [read32 $master $REG_ID]
puts "ID       = [hex32 $id]"
if {$id != 0x44320001} {
    error "Unexpected ID register. Expected 0x44320001."
}

write32 $master $REG_CONTROL 0x2
after 10

write32 $master $REG_A 0x03
write32 $master $REG_B 0x05
write32 $master $REG_OPCODE 0x00
write32 $master $REG_CONTROL 0x01

puts "Started: A=0x03 B=0x05 opcode=ADD"

set status 0
for {set i 0} {$i < 200} {incr i} {
    after 10
    set status [read32 $master $REG_STATUS]
    if {$status & 0x1} {
        break
    }
}

set result [read32 $master $REG_RESULT]
set cycles [read32 $master $REG_CYCLES]

puts "STATUS   = [hex32 $status]"
puts "RESULT   = [hex32 $result]"
puts "CYCLES   = [hex32 $cycles]"

if {$result != 0x08} {
    error "Unexpected result. Expected 0x08."
}

puts "D2 smoke test passed."
close_service master $master

