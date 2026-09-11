set script_dir [file dirname [file normalize [info script]]]
set example_root [file normalize [file join $script_dir ..]]
set probe_dir [file join $example_root work catalog_probe]

file mkdir $probe_dir
create_project -force ethernet_ip_catalog_probe $probe_dir -part xc7k325tffg676-2

create_ip -name gig_ethernet_pcs_pma -vendor xilinx.com -library ip \
    -version 16.2 -module_name pcs_pma_probe
create_ip -name tri_mode_ethernet_mac -vendor xilinx.com -library ip \
    -version 9.0 -module_name temac_probe

foreach ip_name {pcs_pma_probe temac_probe} {
    puts "===== BEGIN_CONFIG $ip_name ====="
    foreach property_name [lsort [list_property [get_ips $ip_name]]] {
        if {[string match "CONFIG.*" $property_name]} {
            puts "$property_name=[get_property $property_name [get_ips $ip_name]]"
        }
    }
    puts "===== END_CONFIG $ip_name ====="
}

close_project
exit
