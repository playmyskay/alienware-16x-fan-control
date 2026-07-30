#!/bin/bash

ACPI_CALL=/proc/acpi/call

call_acpi() {
    echo "$1" > $ACPI_CALL
}

call_acpi_get() {
    echo "$1" > $ACPI_CALL
    cat $ACPI_CALL | tr -d '\0'
}

get_current_profile() {
    local id
    id=$(call_acpi_get "\_SB.AMWW.WMAX 0 0x14 {0x0B,0x00,0x00,0x00}" | tr -d ' \t\r\n' | tr 'A-F' 'a-f')
    case "$id" in
      0xa0) echo "Balanced" ;;
      0xa1) echo "Balanced Performance" ;;
      0xa2) echo "Cool" ;;
      0xa3) echo "Quiet" ;;
      0xa4) echo "Performance" ;;
      0xab) echo "Game Shift" ;;
      *)    echo "Unknown ($id)" ;;
    esac
}

find_hwmon_by_name() {
    grep -rl "^${1}$" /sys/class/hwmon/hwmon*/name 2>/dev/null | head -1 | xargs dirname
}

print_fan_speeds() {
    local hwmon
    hwmon=$(find_hwmon_by_name alienware_wmi)
    echo "=== Fan Speeds ==="
    for f in 1 2; do
        local label input min max boost
        label=$(cat "${hwmon}/fan${f}_label" 2>/dev/null || echo "Fan $f")
        input=$(cat "${hwmon}/fan${f}_input" 2>/dev/null || echo "N/A")
        min=$(cat   "${hwmon}/fan${f}_min"   2>/dev/null || echo "N/A")
        max=$(cat   "${hwmon}/fan${f}_max"   2>/dev/null || echo "N/A")
        boost=$(cat "${hwmon}/fan${f}_boost" 2>/dev/null || echo "N/A")
        printf "  %-12s %4s RPM  (min: %s  max: %s  boost: %s)\n" \
               "${label}:" "$input" "$min" "$max" "$boost"
    done
}

print_cpu_temperatures() {
    local hwmon_aw hwmon_ct pkg
    hwmon_aw=$(find_hwmon_by_name alienware_wmi)
    hwmon_ct=$(find_hwmon_by_name coretemp)
    echo "=== CPU Temperatures ==="
    if [[ -n "$hwmon_aw" ]]; then
        local lbl val
        lbl=$(cat "${hwmon_aw}/temp1_label" 2>/dev/null)
        val=$(cat "${hwmon_aw}/temp1_input" 2>/dev/null)
        [[ -n "$val" ]] && printf "  %-22s %d°C\n" "${lbl} (WMI):" $(( val / 1000 ))
    fi
    if [[ -n "$hwmon_ct" ]]; then
        pkg=$(cat "${hwmon_ct}/temp1_input" 2>/dev/null)
        [[ -n "$pkg" ]] && printf "  %-22s %d°C\n" "CPU Package (coretemp):" $(( pkg / 1000 ))
    fi
}

print_gpu_temperatures() {
    local hwmon_aw hwmon_dd
    hwmon_aw=$(find_hwmon_by_name alienware_wmi)
    hwmon_dd=$(find_hwmon_by_name dell_ddv)
    echo "=== GPU Temperatures ==="
    if [[ -n "$hwmon_aw" ]]; then
        local lbl val
        lbl=$(cat "${hwmon_aw}/temp2_label" 2>/dev/null)
        val=$(cat "${hwmon_aw}/temp2_input" 2>/dev/null)
        [[ -n "$val" ]] && printf "  %-22s %d°C\n" "${lbl} (WMI):" $(( val / 1000 ))
    fi
    if [[ -n "$hwmon_dd" ]]; then
        for label_file in "${hwmon_dd}"/temp*_label; do
            local lbl val
            lbl=$(cat "$label_file" 2>/dev/null)
            val=$(cat "${label_file/_label/_input}" 2>/dev/null)
            [[ "$lbl" == "Video" && -n "$val" ]] && \
                printf "  %-22s %d°C\n" "GPU Video (dell_ddv):" $(( val / 1000 ))
        done
    fi
}

print_system_temperatures() {
    local hwmon_dd
    hwmon_dd=$(find_hwmon_by_name dell_ddv)
    echo "=== System Temperatures ==="
    [[ -z "$hwmon_dd" ]] && return
    declare -A total_count seen_count
    for label_file in "${hwmon_dd}"/temp*_label; do
        local lbl
        lbl=$(cat "$label_file" 2>/dev/null)
        [[ "$lbl" == "Video" || -z "$lbl" ]] && continue
        total_count["$lbl"]=$(( ${total_count["$lbl"]:-0} + 1 ))
    done
    for label_file in "${hwmon_dd}"/temp*_label; do
        local lbl val display_lbl
        lbl=$(cat "$label_file" 2>/dev/null)
        val=$(cat "${label_file/_label/_input}" 2>/dev/null)
        [[ "$lbl" == "Video" || -z "$val" ]] && continue
        seen_count["$lbl"]=$(( ${seen_count["$lbl"]:-0} + 1 ))
        if [[ ${total_count["$lbl"]} -gt 1 ]]; then
            display_lbl="${lbl} ${seen_count[$lbl]}"
        else
            display_lbl="${lbl}"
        fi
        printf "  %-22s %d°C\n" "${display_lbl}:" $(( val / 1000 ))
    done
}

print_status() {
    echo "=== Active Profile ==="
    echo "  $(get_current_profile)"
    echo ""
    print_fan_speeds
    echo ""
    print_cpu_temperatures
    echo ""
    print_gpu_temperatures
    echo ""
    print_system_temperatures
}

set_cpu_fan() {
    call_acpi "\_SB.AMWW.WMAX 0 0x15 {0x02,0x32,0x$(printf '%02X' $1),0x00}"
}

set_gpu_fan() {
    call_acpi "\_SB.AMWW.WMAX 0 0x15 {0x02,0x33,0x$(printf '%02X' $1),0x00}"
}

set_both_fans() {
    set_cpu_fan "$1"
    set_gpu_fan "$2"
}

set_profile() {
    case "$1" in
      balanced)             call_acpi "\_SB.AMWW.WMAX 0 0x15 {0x01,0xA0,0x00,0x00}" ;;
      balanced-performance) call_acpi "\_SB.AMWW.WMAX 0 0x15 {0x01,0xA1,0x00,0x00}" ;;
      cool)                 call_acpi "\_SB.AMWW.WMAX 0 0x15 {0x01,0xA2,0x00,0x00}" ;;
      quiet)                call_acpi "\_SB.AMWW.WMAX 0 0x15 {0x01,0xA3,0x00,0x00}" ;;
      performance)          call_acpi "\_SB.AMWW.WMAX 0 0x15 {0x01,0xA4,0x00,0x00}" ;;
      gameshift)            call_acpi "\_SB.AMWW.WMAX 0 0x15 {0x01,0xAB,0x00,0x00}" ;;
      *) echo "Unknown profile: $1"; exit 1 ;;
    esac
}

case "$1" in
  cpu)     set_cpu_fan "$2" ;;
  gpu)     set_gpu_fan "$2" ;;
  both)    set_both_fans "$2" "$3" ;;
  profile) set_profile "$2" ;;
  status)  print_status ;;
  current-profile) get_current_profile ;;
  *)
    echo "Usage: fan_helper.sh cpu <0-100>"
    echo "       fan_helper.sh gpu <0-100>"
    echo "       fan_helper.sh both <cpu%> <gpu%>"
    echo "       fan_helper.sh profile <balanced|balanced-performance|cool|quiet|performance|gameshift>"
    echo "       fan_helper.sh status"
    echo "       fan_helper.sh current-profile"
    exit 1
    ;;
esac
