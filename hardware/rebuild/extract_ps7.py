#!/usr/bin/env python3
"""Extract PS7 electrical and peripheral settings from an XSA into a Tcl dict.

Only restore inputs are exported. Generated clocks/divisors, address maps,
board labels, timestamps, and paths are not copied. Vivado must still check
that each CONFIG property exists and accepts its saved value.
"""

import argparse
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
import zipfile


EXACT_KEYS = {
    'PCW_CRYSTAL_PERIPHERAL_FREQMHZ',
    'PCW_APU_PERIPHERAL_FREQMHZ',
    'PCW_APU_CLK_RATIO_ENABLE',
    'PCW_CPU_PERIPHERAL_CLKSRC',
    'PCW_DDR_PERIPHERAL_CLKSRC',
    'PCW_PRESET_BANK0_VOLTAGE',
    'PCW_PRESET_BANK1_VOLTAGE',
    'PCW_IRQ_F2P_INTR',
    'PCW_IRQ_F2P_MODE',
    'PCW_SINGLE_QSPI_DATA_MODE',
    'PCW_DUAL_PARALLEL_QSPI_DATA_MODE',
    'PCW_DUAL_STACK_QSPI_DATA_MODE',
}
PERIPHERAL = re.compile(
    r'PCW_(?:ENET[01]?|UART[01]?|SD[01]|SDIO|USB[01]|QSPI|'
    r'SPI[01]?|I2C[01]?|CAN[01]?|TTC[01]?|WDT|GPIO)_'
    r'(?:PERIPHERAL_(?:ENABLE|CLKSRC|FREQMHZ)|'
    r'GRP_[A-Z0-9_]+_(?:ENABLE|IO)|RESET_(?:ENABLE|IO|POLARITY|SELECT)|'
    r'(?:ENET[01]|UART[01]|SD[01]|USB[01]|QSPI|SPI[01]|I2C[01]|'
    r'CAN[01]|TTC[01]|WDT)_IO|BAUD_RATE|'
    r'(?:MIO|EMIO)_GPIO_(?:ENABLE|IO|WIDTH))'
)

# These settings are essential for the saved board's DDR, Ethernet, console,
# and PL clock. The rebuild script overrides HP0 after applying this snapshot.
REQUIRED_KEYS = {
    'PCW_UIPARAM_DDR_ENABLE',
    'PCW_UIPARAM_DDR_MEMORY_TYPE',
    'PCW_UIPARAM_DDR_PARTNO',
    'PCW_UIPARAM_DDR_BUS_WIDTH',
    'PCW_UIPARAM_DDR_FREQ_MHZ',
    'PCW_CRYSTAL_PERIPHERAL_FREQMHZ',
    'PCW_APU_PERIPHERAL_FREQMHZ',
    'PCW_PRESET_BANK0_VOLTAGE',
    'PCW_PRESET_BANK1_VOLTAGE',
    'PCW_ENET0_PERIPHERAL_ENABLE',
    'PCW_ENET0_ENET0_IO',
    'PCW_ENET0_GRP_MDIO_ENABLE',
    'PCW_ENET0_GRP_MDIO_IO',
    'PCW_UART1_PERIPHERAL_ENABLE',
    'PCW_UART1_UART1_IO',
    'PCW_UART1_BAUD_RATE',
    'PCW_FCLK0_PERIPHERAL_CLKSRC',
    'PCW_FPGA0_PERIPHERAL_FREQMHZ',
    'PCW_EN_CLK0_PORT',
    'PCW_EN_RST0_PORT',
    'PCW_USE_M_AXI_GP0',
    'PCW_USE_S_AXI_HP0',
} | {
    f'PCW_UIPARAM_DDR_BOARD_DELAY{i}' for i in range(4)
} | {
    f'PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_{i}' for i in range(4)
}


def is_restore_input(name):
    if name in EXACT_KEYS:
        return True
    if name.startswith('PCW_UIPARAM_DDR_'):
        # Package trace lengths are device-derived, not PCB settings.
        return not name.endswith('_PACKAGE_LENGTH')
    return bool(
        PERIPHERAL.fullmatch(name)
        or re.fullmatch(r'PCW_MIO_[0-9]+_(?:IOTYPE|PULLUP|SLEW)', name)
        or re.fullmatch(r'PCW_EN_(?:CLK|RST)[0-3]_PORT', name)
        or re.fullmatch(r'PCW_FPGA[0-3]_PERIPHERAL_FREQMHZ', name)
        or re.fullmatch(r'PCW_FCLK[0-3]_PERIPHERAL_CLKSRC', name)
        or re.fullmatch(r'PCW_USE_(?:M_AXI_GP[01]|S_AXI_(?:GP[01]|HP[0-3]|ACP))', name)
        or re.fullmatch(r'PCW_S_AXI_HP[0-3]_DATA_WIDTH', name)
    )


def read_ps7_parameters(xsa):
    matches = []
    with zipfile.ZipFile(xsa) as archive:
        for member in archive.namelist():
            if not member.lower().endswith('.hwh'):
                continue
            root = ET.fromstring(archive.read(member))
            for module in root.iter('MODULE'):
                if module.get('INSTANCE') == 'processing_system7_0':
                    matches.append(module)
    if len(matches) != 1:
        raise ValueError('Expected exactly one processing_system7_0 in the XSA HWH')
    module = matches[0]
    if not module.get('VLNV', '').startswith('xilinx.com:ip:processing_system7:'):
        raise ValueError('processing_system7_0 does not identify a Xilinx PS7 core')
    parameters = {}
    for item in module.iter('PARAMETER'):
        name, value = item.get('NAME', ''), item.get('VALUE')
        if name.startswith('PCW_') and value is not None:
            if name in parameters and parameters[name] != value:
                raise ValueError(f'Conflicting values for {name}')
            parameters[name] = value
    return parameters


def restore_config(parameters):
    selected = {
        name: value for name, value in parameters.items()
        if is_restore_input(name) and value not in ('', '<Select>', 'NA', '-1')
    }
    missing = sorted(REQUIRED_KEYS - selected.keys())
    if missing:
        raise ValueError('Missing essential PS7 settings: ' + ', '.join(missing))
    return {'CONFIG.' + name: selected[name] for name in sorted(selected)}


def tcl_word(value):
    # Quoted Tcl words preserve strings without allowing command/variable
    # substitution, including when an input archive contains unusual text.
    escaped = (value.replace('\\', '\\\\').replace('"', '\\"')
               .replace('$', '\\$').replace('[', '\\[').replace(']', '\\]')
               .replace('\r', '\\r').replace('\n', '\\n').replace('\t', '\\t'))
    return '"' + escaped + '"'


def render_tcl(config):
    lines = [
        '# PS7 restore inputs only; generated metadata is intentionally omitted.',
        'set adb_ps7_config [dict create \\',
    ]
    for name, value in sorted(config.items()):
        lines.append(f'    {tcl_word(name)} {tcl_word(value)} \\')
    lines.extend([']', ''])
    return '\n'.join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xsa', type=Path, required=True, help='Saved XSA handoff')
    parser.add_argument('--output', type=Path, required=True, help='Output Tcl file')
    args = parser.parse_args(argv)
    try:
        if args.xsa.resolve() == args.output.resolve():
            raise ValueError('Output must not overwrite the input XSA')
        config = restore_config(read_ps7_parameters(args.xsa))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(render_tcl(config), encoding='utf-8', newline='\n')
    except (OSError, ValueError, zipfile.BadZipFile, ET.ParseError) as error:
        print(f'PS7 extraction failed: {error}', file=sys.stderr)
        return 1
    print(f'Exported {len(config)} PS7 restore settings.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
