# Hardware Manager guards with Vivado-version-compatible property handling.
namespace eval cowork {}

proc cowork::set_hw_property_if_supported {object property value} {
    if {[lsearch -exact [list_property $object] $property] >= 0} {
        set_property $property $value $object
        return true
    }
    return false
}
proc cowork::open_unique_hw_device {expected_part} {
    open_hw_manager
    connect_hw_server
    set targets [get_hw_targets *]
    if {[llength $targets] != 1} {
        error "expected exactly one JTAG target, found [llength $targets]"
    }
    set target [lindex $targets 0]
    open_hw_target $target

    set devices [get_hw_devices]
    if {[llength $devices] != 1} {
        error "expected exactly one JTAG device, found [llength $devices]"
    }
    set device [lindex $devices 0]
    if {[get_property PART $device] ne $expected_part} {
        error "expected $expected_part, found [get_property PART $device]"
    }
    return [list $target $device]
}

proc cowork::bind_hw_files {device bit_path ltx_path} {
    cowork::require_file bitstream $bit_path
    cowork::require_file probes-file $ltx_path
    set_property PROGRAM.FILE $bit_path $device
    if {![cowork::set_hw_property_if_supported $device PROBES.FILE $ltx_path]} {
        error "device does not support PROBES.FILE"
    }
    # FULL_PROBES.FILE is the persisted project property that can otherwise
    # restore an older LTX after program_hw_devices.
    cowork::set_hw_property_if_supported $device FULL_PROBES.FILE $ltx_path
}

proc cowork::program_and_refresh {device bit_path ltx_path} {
    cowork::bind_hw_files $device $bit_path $ltx_path
    program_hw_devices $device
    # Reapply both paths after programming because Vivado 2021.1 may restore
    # the probes path saved by a previous Hardware Manager image.
    cowork::bind_hw_files $device $bit_path $ltx_path
    refresh_hw_device $device
}

proc cowork::find_unique_ila {device expected_cell expected_probe expected_width} {
    set matches {}
    foreach candidate [get_hw_ilas -of_objects $device] {
        if {[get_property CELL_NAME $candidate] eq $expected_cell} {
            lappend matches $candidate
        }
    }
    if {[llength $matches] != 1} {
        error "expected exactly one hardware ILA cell $expected_cell, found [llength $matches]"
    }
    set ila [lindex $matches 0]

    set probe_matches {}
    foreach candidate [get_hw_probes -of_objects $ila] {
        if {[get_property NAME $candidate] eq $expected_probe} {
            lappend probe_matches $candidate
        }
    }
    if {[llength $probe_matches] != 1} {
        error "expected exactly one ILA probe $expected_probe, found [llength $probe_matches]"
    }
    set probe [lindex $probe_matches 0]
    if {[get_property WIDTH $probe] != $expected_width} {
        error "ILA probe width mismatch: expected $expected_width, got [get_property WIDTH $probe]"
    }
    return [list $ila $probe]
}
