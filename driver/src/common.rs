use log::{debug, info, warn};
use rusb::{
    ConfigDescriptor, Context, Device, DeviceDescriptor, DeviceHandle, Direction,
    InterfaceDescriptor, TransferType, UsbContext,
};
use std::time::Duration;

pub const VENDOR_ID: u16 = 0xF4CE;
pub const PRODUCT_ID: u16 = 0x0003;
pub const MAX_BUF_SIZE: usize = 1024;
pub const DEFAULT_TIMEOUT: Duration = Duration::from_millis(20);

pub type TartResult<T> = Result<T, rusb::Error>;

#[derive(Debug, Clone, PartialEq)]
pub struct Endpoint {
    pub config: u8,
    pub interface: u8,
    pub setting: u8,
    pub address: u8,
    pub has_driver: bool,
}

impl Endpoint {
    pub fn new(cfg: u8, ix: &InterfaceDescriptor) -> Self {
        Self {
            config: cfg,
            interface: ix.interface_number(),
            setting: ix.setting_number(),
            address: 0u8,
            has_driver: false,
        }
    }
    pub fn read_address(&self) -> u8 {
        self.address
    }
    pub fn write_address(&self) -> u8 {
        self.address & 0x7f
    }
}

pub fn find_axis_usb(context: &Context) -> TartResult<Device<Context>> {
    if let Ok(devices) = context.devices() {
        return devices
            .iter()
            .find_map(|ref device| {
                let descriptor = device.device_descriptor().ok()?;
                let vid: u16 = descriptor.vendor_id();
                let pid: u16 = descriptor.product_id();
                debug!("Vendor ID: 0x{:04x}, Product ID: 0x{:04x}", vid, pid);

                if descriptor.vendor_id() == VENDOR_ID && descriptor.product_id() == PRODUCT_ID {
                    Some(device.to_owned())
                } else {
                    None
                }
            })
            .ok_or(rusb::Error::NotFound);
    }
    Err(rusb::Error::NotFound)
}

pub fn find_interfaces<T: UsbContext>(
    device: &mut Device<T>,
    descriptor: &DeviceDescriptor,
) -> Vec<u8> {
    let numcfg = descriptor.num_configurations();
    let config: ConfigDescriptor = (0..numcfg)
        .find_map(|n| device.config_descriptor(n).ok())
        .unwrap();

    let mut interfaces = Vec::new();
    for ix in config.interfaces().flat_map(|i| i.descriptors()) {
        interfaces.push(ix.interface_number());
    }

    interfaces
}

pub fn find_endpoint<T: UsbContext>(
    device: &mut Device<T>,
    descriptor: &DeviceDescriptor,
    handle: &DeviceHandle<T>,
    transfer_type: TransferType,
    direction: Direction,
) -> Option<Endpoint> {
    let numcfg = descriptor.num_configurations();
    let config: ConfigDescriptor = (0..numcfg).find_map(|n| device.config_descriptor(n).ok())?;
    debug!("Found '{}' configuration descriptors", numcfg);

    for ix in config.interfaces().flat_map(|i| i.descriptors()) {
        let ix_num: u8 = ix.interface_number();

        for ep in ix.endpoint_descriptors() {
            if ep.transfer_type() == transfer_type && ep.direction() == direction {
                let has_driver: bool = handle.kernel_driver_active(ix_num).unwrap_or(false);
                let endpoint = Endpoint {
                    config: config.number(),
                    interface: ix_num,
                    setting: ix.setting_number(),
                    address: ep.address(),
                    has_driver,
                };
                debug!("Found USB endpoint: {:?}", &endpoint);
                return Some(endpoint);
            }
        }
    }

    None
}

pub fn configure_endpoint<T: UsbContext>(
    handle: &mut DeviceHandle<T>,
    endpoint: &Endpoint,
) -> rusb::Result<()> {
    if endpoint.has_driver {
        warn!("USB device has a kernel driver loaded, attempting to detach ...");
        handle.detach_kernel_driver(endpoint.interface).ok();
        info!("USB kernel driver detached successfully");
    }
    debug!("EP: {:?}", endpoint);

    handle.set_active_configuration(endpoint.config)?;
    handle.claim_interface(endpoint.interface)?;
    handle.set_alternate_setting(endpoint.interface, endpoint.setting)?;

    Ok(())
}

pub fn configure_endpoints<T: UsbContext>(
    handle: &mut DeviceHandle<T>,
    ep_in: &Endpoint,
    ep_out: &Endpoint,
) -> rusb::Result<()> {
    if ep_in.has_driver {
        warn!("USB device has a kernel driver loaded, attempting to detach ...");
        handle.detach_kernel_driver(ep_in.interface).ok();
        info!("USB kernel driver detached successfully");
    }
    if ep_in.interface != ep_out.interface && ep_out.has_driver {
        warn!("USB device has a kernel driver loaded, attempting to detach ...");
        handle.detach_kernel_driver(ep_out.interface).ok();
        info!("USB kernel driver detached successfully");
    }
    debug!("IN: {:?}", ep_in);
    debug!("OUT: {:?}", ep_out);

    handle.set_active_configuration(ep_out.config)?;
    handle.claim_interface(ep_out.interface)?;
    handle.set_alternate_setting(ep_out.interface, ep_out.setting)?;

    if ep_in.interface != ep_out.interface {
        handle.set_active_configuration(ep_in.config)?;
        handle.claim_interface(ep_in.interface)?;
        handle.set_alternate_setting(ep_in.interface, ep_in.setting)?;
    }

    Ok(())
}
