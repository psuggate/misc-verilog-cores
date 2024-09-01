use log::{debug, info, warn};
use rusb::{Context, Device, DeviceHandle, Direction, TransferType};
use std::time::Duration;

pub use crate::common::find_axis_usb;
use crate::common::*;

pub const TRANSFER_LENGTH_REGISTER: u16 = 0x01u16;

#[derive(Debug, PartialEq)]
pub struct AxisUSB {
    pub handle: DeviceHandle<Context>,
    interfaces: Vec<u8>,
    ep_in: Endpoint,
    ep_out: Endpoint,
    pub telemetry: Endpoint,
    vendor: String,
    label: String,
    serial: String,
    context: Context,
}

impl AxisUSB {
    pub fn open(device: &mut Device<Context>, context: Context) -> Result<AxisUSB, rusb::Error> {
        let descriptor = device.device_descriptor()?;
        let mut handle = device.open()?;
        info!("AXIS USB opened ...");

        let vendor = handle.read_manufacturer_string_ascii(&descriptor)?;
        let label = handle.read_product_string_ascii(&descriptor)?;
        let serial = handle.read_serial_number_string_ascii(&descriptor)?;

        let mut interfaces: Vec<u8> = Vec::with_capacity(2);
        let ep_in = find_endpoint(
            device,
            &descriptor,
            &handle,
            TransferType::Bulk,
            Direction::In,
        )
        .ok_or(rusb::Error::NotFound)?;
        interfaces.push(ep_in.interface);
        info!(" - IN (bulk) endpoint found");

        let ep_out = find_endpoint(
            device,
            &descriptor,
            &handle,
            TransferType::Bulk,
            Direction::Out,
        )
        .ok_or(rusb::Error::NotFound)?;

        if ep_in.interface == ep_out.interface {
            debug!(
                "Both USB endpoints share the same interface ('{}')",
                ep_in.interface
            );
            configure_endpoints(&mut handle, &ep_in, &ep_out)?;
        } else {
            configure_endpoint(&mut handle, &ep_in)?;
            interfaces.push(ep_out.interface);
            configure_endpoint(&mut handle, &ep_out)?;
        }
        info!(" - OUT (bulk) endpoint found");

        let ex_in = Endpoint {
            config: ep_in.config,
            interface: ep_in.interface,
            setting: ep_in.setting,
            address: 0x83u8,
            has_driver: false,
        };

        Ok(Self {
            handle,
            interfaces,
            ep_in,
            ep_out,
            telemetry: ex_in,
            vendor,
            label,
            serial,
            context,
        })
    }

    pub fn vendor(&self) -> String {
        self.vendor.clone()
    }

    pub fn product(&self) -> String {
        self.label.clone()
    }

    pub fn serial_number(&self) -> String {
        self.serial.clone()
    }

    pub fn read_register(
        &mut self,
        register: u16,
        timeout: Option<Duration>,
    ) -> Result<u16, rusb::Error> {
        let mut buf = [0u8; 2];
        let tim = timeout.unwrap_or(DEFAULT_TIMEOUT);
        let num = self
            .handle
            .read_control(0xC0, 0x01, register, 0, &mut buf, tim)?;
        if num == 2 {
            let res = ((buf[1] as u16) << 8) | buf[0] as u16;
            Ok(res)
        } else {
            Err(rusb::Error::Io)
        }
    }

    pub fn write_register(
        &mut self,
        register: u16,
        value: u16,
        timeout: Option<Duration>,
    ) -> Result<usize, rusb::Error> {
        let tim = timeout.unwrap_or(DEFAULT_TIMEOUT);
        let buf = [(value & 0xff) as u8, (value >> 8) as u8];
        self.handle
            .write_control(0x40, 0x01, register, 0, &buf, tim)
    }

    pub fn try_read(&mut self, timeout: Option<Duration>) -> Result<Vec<u8>, rusb::Error> {
        let timeout = timeout.unwrap_or(DEFAULT_TIMEOUT);
        let mut buf = [0; MAX_BUF_SIZE];
        debug!("READ (timeout: {} ms)", timeout.as_millis() as u32);
        let len = self
            .handle
            .read_bulk(self.ep_in.read_address(), &mut buf, timeout)?;
        debug!("RESPONSE (bytes = {})", len);
        Ok(Vec::from(&buf[0..len]))
    }

    pub fn write(&mut self, bytes: &[u8]) -> Result<usize, rusb::Error> {
        let len: u16 = bytes.len() as u16;
        debug!("WRITE (bytes = {})", len);
        self.handle
            .write_bulk(self.ep_out.write_address(), bytes, DEFAULT_TIMEOUT)
    }
}

impl Drop for AxisUSB {
    fn drop(&mut self) {
        if self.ep_in.has_driver {
            warn!("Re-attaching kernel driver !!");
            self.handle
                .attach_kernel_driver(self.ep_in.interface)
                .unwrap();
        }
    }
}
