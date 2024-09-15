use super::{axis_usb::*, common::*};
use log::info;

fn to_state(seq: usize, lo: u8, hi: u8) -> String {
    let state = match hi >> 4 {
        0x01 => "ST_IDLE",
        0x02 => "ST_CTRL",
        0x04 => "ST_BULK",
        0x08 => "ST_DUMP",
        _ => "- XXX -",
    };
    let xctrl = match hi & 0x0f {
        0x00 => "CTL_DONE      ",
        0x01 => "CTL_SETUP_RX  ",
        0x02 => "CTL_SETUP_ACK ",
        0x03 => "CTL_DATA_TOK  ",
        0x04 => "CTL_DATO_RX   ",
        0x05 => "CTL_DATO_ACK  ",
        0x06 => "CTL_DATI_TX   ",
        0x07 => "CTL_DATI_ACK  ",
        0x08 => "CTL_STATUS_TOK",
        0x09 => "CTL_STATUS_RX ",
        0x0a => "CTL_STATUS_TX ",
        0x0b => "CTL_STATUS_ACK",
        _ => "- UNKNOWN -   ",
    };
    let xbulk = match lo {
        0x01 => "BLK_IDLE    ",
        0x02 => "BLK_DATI_TX ",
        0x04 => "BLK_DATI_ZDP",
        0x08 => "BLK_DATI_ACK",
        0x10 => "BLK_DATO_RX ",
        0x20 => "BLK_DATO_ACK",
        0x40 => "BLK_DATO_ERR",
        0x80 => "BLK_DONE    ",
        _ => "- UNKNOWN - ",
    };

    format!("{:5}  ->  {{ {} : {} : {} }}", seq, state, xctrl, xbulk)
}

pub fn to_hexdump(bytes: &[u8]) -> String {
    let mut words = Vec::with_capacity(bytes.len() / 2);
    let mut odd = false;
    let mut low = bytes[0] as u16;

    for b in bytes.iter() {
        let x = *b as u16;
        if odd {
            words.push((x << 8) | low);
            odd = false;
        } else {
            low = x;
            odd = true;
        }
    }

    let mut hexes = Vec::with_capacity(bytes.len());

    for (count, w) in words.iter().enumerate() {
        let chr = match count % 16 {
            15 => '\n',
            1 | 3 | 5 | 7 | 9 | 11 | 13 => ' ',
            _ => '-',
        };
        hexes.push(format!("{:04X}{}", w, chr));
    }

    hexes.concat()
}

pub fn tart_telemetry(tart: &mut AxisUSB, verbose: u8) -> TartResult<Vec<u8>> {
    let mut buf = [0; MAX_BUF_SIZE];
    let mut result = Vec::new();

    loop {
        let len = tart
            .handle
            .read_bulk(tart.ex_in.read_address(), &mut buf, DEFAULT_TIMEOUT)?;
        if len == 0 {
            break;
        }
        result.append(&mut Vec::from(&buf[0..len]));
    }

    let mut ptr = 0;
    let len = result.len();
    let hex = to_hexdump(&result);
    print!("{}", hex);

    if verbose > 1 {
        for i in 0..(len / 2) {
            info!("{}", to_state(i, result[ptr], result[ptr + 1]));
            ptr += 2;
        }
    }
    Ok(result)
}
