use super::{axis_usb::*, common::*};
use log::info;

fn to_state(seq: usize, val: u32) -> String {
    let state = match val & 0x07 {
        0x00 => "ST_IDLE",
        0x01 => "ST_RECV",
        0x02 => "ST_RESP",
        0x03 => "ST_DROP",
        0x04 => "ST_SEND",
        0x05 => "ST_WAIT",
        _ => "- XXX -",
    };
    let sof = (val >> 20) & 0x07ff;
    let pid = (val >> 4) & 0x0F;
    let ep1 = (val >> 8) & 0x0F;
    let ep2 = (val >> 12) & 0x0F;
    let ep3 = (val >> 16) & 0x0F;

    format!(
        "{:5}  ->  {{ {} : {} : {:x} : {:x} : {:x} : {:x} }}",
        seq, state, sof, pid, ep1, ep2, ep3
    )
}

fn to_hexdump(bytes: &[u8]) -> String {
    let mut words = Vec::with_capacity(bytes.len() / 2);
    if bytes.is_empty() {
        return "<none>\n".to_string();
    }

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

pub fn tart_logger(tart: &mut AxisUSB, verbose: u8) -> TartResult<Vec<u8>> {
    let mut buf = [0; MAX_BUF_SIZE];
    let mut result = Vec::new();

    loop {
        let len =
            tart.handle
                .read_bulk(tart.telemetry.read_address(), &mut buf, DEFAULT_TIMEOUT)?;
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
        for i in 0..(len / 4) {
            let end = ptr + 4;
            let sample = u32::from_be_bytes(buf[ptr..end].try_into().unwrap());
            info!("{}", to_state(i, sample));
            ptr += 4;
        }
    }
    Ok(result)
}
