use clap::Parser;
use log::{debug, error, info, LevelFilter};
use rusb::Context;
use simple_logger::SimpleLogger;
use std::time::Duration;

use driver::{axis_usb::*, tart_logger, tart_telemetry};

#[derive(Parser, Debug, Clone)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Verbosity
    #[arg(short, long, value_name = "LEVEL")]
    log_level: Option<String>,

    #[arg(short, long, default_value = "false")]
    read_first: bool,

    #[arg(long, default_value = "false")]
    read_twice: bool,

    #[arg(long, default_value = "false")]
    write_twice: bool,

    #[arg(short, long, default_value = "false")]
    no_read: bool,

    #[arg(short, long, default_value = "false")]
    writeless: bool,

    #[arg(short, long, default_value = "50")]
    delay: usize,

    #[arg(short, long, default_value = "20")]
    size: usize,

    #[arg(short, long, default_value = "32")]
    chunks: usize,

    #[arg(long, default_value = "false")]
    sdram: bool,

    #[arg(short, long, default_value = "false")]
    telemetry: bool,

    #[arg(long, default_value = "false")]
    logger: bool,

    /// Verbosity of generated output?
    #[arg(short, long, action = clap::ArgAction::Count)]
    verbose: u8,
}

fn tart_read(args: &Args, tart: &mut AxisUSB) -> Result<Vec<u8>, rusb::Error> {
    if args.no_read {
        return Ok(Vec::new());
    }

    let bytes: Vec<u8> = match tart.try_read(None) {
        Ok(xs) => xs,
        Err(e) => {
            error!("TART read failed: {:?}", e);
            Vec::new()
        }
    };

    info!("RECEIVED (bytes = {}): {:?}", bytes.len(), &bytes);

    Ok(bytes)
}

fn tart_write(args: &Args, tart: &mut AxisUSB) -> Result<Vec<u8>, rusb::Error> {
    let wrdat: [u8; 24] = [
        0x35, 0x24, 0xa0, 0x1a, 0x3b, 0x1f, 0xf6, 0x9d, 0x03, 0xb0, 0x00, 0x10,
        // 0xff, 0x5a, 0xc3, 0x2d, 0x03, 0xb0, 0x00, 0x10, 0x03, 0xb0, 0x00, 0x10,
        0xff, 0x5a, 0xc3, 0x2d, 0xff, 0x80, 0x08, 0x3c, 0xa5, 0xc3, 0x5a, 0x99,
    ];
    let wrdat: Vec<u8> = wrdat[0..args.size].to_owned().repeat(args.chunks);

    let num = tart.write(&wrdat)?;

    info!("WRITTEN (bytes = {}): {:?}", num, &wrdat);

    Ok(wrdat)
}

fn tart_ddr3_read(args: &Args, tart: &mut AxisUSB) -> Result<Vec<u8>, rusb::Error> {
    let rdcmd: [u8; 6] = [0xA0, 0x0B, 0x78, 0xF0, 0x08, 0x80];
    // let rdcmd: [u8; 6] = [0xA0, 0x07, 0x80, 0xF0, 0x08, 0x80];
    let num = tart.write(&rdcmd)?;
    if num != 6 {
        error!("TART DDR3 CMD failed, num = {:?}", num);
        return Ok(Vec::new());
    }
    debug!("DDR3 WRITTEN (bytes = {}): {:?}", num, &rdcmd);

    if args.no_read {
        return Ok(Vec::new());
    }

    if args.read_twice {
        let mut bytes = Vec::new();

        while let Ok(mut xs) = tart.try_read(None) {
            if xs.is_empty() {
                break;
            }
            bytes.append(&mut xs);
        }

        info!("DDR3 RECEIVED (bytes = {}): {:?}", bytes.len(), &bytes);
        return Ok(bytes);
    }

    let bytes: Vec<u8> = match tart.try_read(None) {
        Ok(xs) => xs,
        Err(e) => {
            error!("TART DDR3 READ failed: {:?}", e);
            Vec::new()
        }
    };

    info!("DDR3 RECEIVED (bytes = {}): {:?}", bytes.len(), &bytes);

    Ok(bytes)
}

fn tart_ddr3_write(args: &Args, tart: &mut AxisUSB) -> Result<Vec<u8>, rusb::Error> {
    let wrdat: [u8; 38] = [
        0xA0, 0x07, 0x80, 0xF0, 0x08, 0x01, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x00, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70,
        0x80, 0x90, 0xA0, 0xB0, 0xC0, 0xD0, 0xE0, 0xF0,
    ];
    let wrdat: Vec<u8> = wrdat.to_vec().repeat(args.chunks);

    let num = tart.write(&wrdat)?;

    info!("DDR3 WRITTEN (bytes = {}): {:?}", num, &wrdat);

    spin_sleep::native_sleep(Duration::from_millis(args.delay as u64));

    // Each 'WRITE' should generate a single-byte response
    let bytes: Vec<u8> = match tart.try_read(None) {
        Ok(xs) => xs,
        Err(e) => {
            error!("TART DDR3 READ-RESPONSE failed: {:?}", e);
            Vec::new()
        }
    };
    info!("DDR3 RESPONSE (bytes = {}): {:?}", bytes.len(), &bytes);

    Ok(wrdat)
}

fn axis_usb(args: Args) -> Result<(), rusb::Error> {
    if args.verbose > 0 {
        info!("{:?}", &args);
    }
    let context = Context::new()?;
    let mut device = find_axis_usb(&context)?;

    let mut axis_usb = AxisUSB::open(&mut device, context)?;

    if args.verbose > 1 {
        info!(
            "Manufacturer: {}, Product: {}, S/N: {}",
            axis_usb.vendor(),
            axis_usb.product(),
            axis_usb.serial_number()
        );
    }

    if args.read_first {
        let bytes: Vec<u8> = axis_usb.try_read(None).unwrap_or(Vec::new());
        info!("RECEIVED (bytes = {}): {:?}", bytes.len(), &bytes);
    }

    spin_sleep::native_sleep(Duration::from_millis(args.delay as u64));

    if !args.writeless {
        let _ = tart_write(&args, &mut axis_usb)?;
    }

    spin_sleep::native_sleep(Duration::from_millis(args.delay as u64));

    let _bytes: Vec<u8> = tart_read(&args, &mut axis_usb)?;

    if args.read_twice {
        let _bytes: Vec<u8> = tart_read(&args, &mut axis_usb)?;
    }

    if args.telemetry {
        tart_telemetry(&mut axis_usb, args.verbose)?;
    }

    if args.logger {
        tart_logger(&mut axis_usb, args.verbose)?;
    }

    Ok(())
}

/**
 * Store some data to DDR3 SDRAM, via USB, and then read it back.
 */
fn usb_ddr3(args: Args) -> Result<(), rusb::Error> {
    if args.verbose > 0 {
        info!("{:?}", &args);
    }
    let context = Context::new()?;
    let mut device = find_axis_usb(&context)?;

    let mut axis_usb = AxisUSB::open(&mut device, context)?;

    if args.verbose > 1 {
        info!(
            "Manufacturer: {}, Product: {}, S/N: {}",
            axis_usb.vendor(),
            axis_usb.product(),
            axis_usb.serial_number()
        );
    }

    if args.read_first {
        let bytes: Vec<u8> = axis_usb.try_read(None).unwrap_or(Vec::new());
        info!("RECEIVED (bytes = {}): {:?}", bytes.len(), &bytes);
    }

    spin_sleep::native_sleep(Duration::from_millis(args.delay as u64));

    if !args.writeless {
        let _ = tart_ddr3_write(&args, &mut axis_usb)?;
        if args.write_twice {
            let _ = tart_ddr3_write(&args, &mut axis_usb)?;
        }
    }

    spin_sleep::native_sleep(Duration::from_millis(args.delay as u64));

    let _bytes: Vec<u8> = tart_ddr3_read(&args, &mut axis_usb)?;

    if args.read_twice {
        let _bytes: Vec<u8> = tart_ddr3_read(&args, &mut axis_usb)?;
    }

    if args.telemetry {
        tart_telemetry(&mut axis_usb, args.verbose)?;
    }

    if args.logger {
        tart_logger(&mut axis_usb, args.verbose)?;
    }

    Ok(())
}

fn main() -> Result<(), rusb::Error> {
    println!("AXIS USB2 bulk-device driver");
    let args: Args = Args::parse();

    let level = if args.verbose > 0 {
        LevelFilter::Debug
    } else {
        LevelFilter::Warn
    };
    SimpleLogger::new().with_level(level).init().unwrap();

    let res = if args.sdram {
        usb_ddr3(args)
    } else {
        axis_usb(args)
    };

    match res {
        Ok(()) => {}
        Err(rusb::Error::Access) => {
            error!("Insufficient privileges to access USB device");
        }
        Err(e) => {
            error!("Failed with error: {:?}", e);
        }
    }
    Ok(())
}
