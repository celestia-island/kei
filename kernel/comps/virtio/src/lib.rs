// SPDX-License-Identifier: MPL-2.0

//! The virtio of Asterinas.
#![no_std]
#![deny(unsafe_code)]

extern crate alloc;
#[macro_use]
extern crate ostd_pod;

use alloc::boxed::Box;
use core::hint::spin_loop;

use aster_block::MajorIdOwner;
use bitflags::bitflags;
use component::{ComponentInitError, init_component};
use device::{
    VirtioDeviceType, block::device::BlockDevice, console::device::ConsoleDevice,
    entropy::device::EntropyDevice, filesystem::device::FileSystemDevice, gpu::device::GpuDevice,
    input::device::InputDevice, network::device::NetworkDevice, socket::device::SocketDevice,
};
use ostd::{error, warn};
use spin::Once;
use transport::{DeviceStatus, mmio::VIRTIO_MMIO_DRIVER, pci::VIRTIO_PCI_DRIVER};

use crate::transport::VirtioTransport;

// Set this crate's log prefix for `ostd::log`.
macro_rules! __log_prefix {
    () => {
        "virtio: "
    };
}

pub mod device;
mod dma_buf;
mod id_alloc;
mod queue;
mod transport;

static VIRTIO_BLOCK_MAJOR_ID: Once<MajorIdOwner> = Once::new();

/// Public init function for manual invocation (aarch64 bypass path).
pub fn virtio_component_init_pub() -> Result<(), ComponentInitError> {
    virtio_component_init_inner()
}

#[init_component]
fn virtio_component_init() -> Result<(), ComponentInitError> {
    virtio_component_init_inner()
}

fn virtio_component_init_inner() -> Result<(), ComponentInitError> {
    ostd::early_println!("[virtio] allocating major ID...");
    VIRTIO_BLOCK_MAJOR_ID.call_once(|| aster_block::allocate_major().unwrap());

    ostd::early_println!("[virtio] transport::init...");
    // Find all devices and register them to the corresponding crate
    transport::init();
    ostd::early_println!("[virtio] transport::init done");

    ostd::early_println!("[virtio] entropy::init...");
    device::entropy::init();
    ostd::early_println!("[virtio] network::init...");
    device::network::init();
    ostd::early_println!("[virtio] socket::init...");
    device::socket::init();
    ostd::early_println!("[virtio] device sub-inits done");

    // On aarch64, the IoMem KVirtArea mapping doesn't work without the
    // kernel page table switch. Instead, manually probe each MMIO device
    // using raw volatile reads through the linear mapping.
    #[cfg(target_arch = "aarch64")]
    {
        // Raw MMIO probe via linear mapping. The virtio crate has
        // #![deny(unsafe_code)], so we use a dedicated module with allow.
        mod raw_probe {
            #![allow(unsafe_code)]
            use core::ptr::{read_volatile, write_volatile};

            const LINEAR_BASE: usize = 0xffff_8000_0000_0000;

            // virtio-mmio register offsets (spec 4.2.4)
            const REG_MAGIC: usize = 0x000;
            const REG_VERSION: usize = 0x004;
            const REG_DEVICE_ID: usize = 0x008;
            const REG_VENDOR_ID: usize = 0x00C;
            const REG_DEVICE_FEATURES: usize = 0x010;
            const REG_DRIVER_FEATURES: usize = 0x020;
            const REG_QUEUE_SEL: usize = 0x030;
            const REG_QUEUE_NUM_MAX: usize = 0x034;
            const REG_QUEUE_NUM: usize = 0x038;
            const REG_QUEUE_ALIGN: usize = 0x03C;
            const REG_QUEUE_PFN: usize = 0x040;
            const REG_STATUS: usize = 0x070;
            const REG_CONFIG_MSIX: usize = 0x06C;
            const REG_CONFIG_GEN: usize = 0x104;

            // Status bits
            const STATUS_ACKNOWLEDGE: u32 = 1;
            const STATUS_DRIVER: u32 = 2;
            const STATUS_FEATURES_OK: u32 = 8;
            const STATUS_DRIVER_OK: u32 = 4;

            fn mmio_read(base: usize, off: usize) -> u32 {
                unsafe { read_volatile((base + off) as *const u32) }
            }
            fn mmio_write(base: usize, off: usize, val: u32) {
                unsafe { write_volatile((base + off) as *mut u32, val) }
            }

            // Simple phys-to-virt for allocating virtqueue pages.
            // We allocate from a static bump allocator in the kernel's BSS.
            // The backing store is large enough for one control queue.
            static mut VQ_STORAGE: [u8; 16384] = [0; 16384]; // 16KB
            static mut VQ_OFFSET: usize = 0;

            fn alloc_pages(nbytes: usize) -> usize {
                unsafe {
                    let aligned = (VQ_OFFSET + 4095) & !4095;
                    VQ_OFFSET = aligned + nbytes;
                    let vaddr = core::ptr::addr_of!(VQ_STORAGE) as usize + aligned;
                    // Convert to physical address for virtio (subtract linear base)
                    vaddr - LINEAR_BASE
                }
            }

            pub fn probe() {
                let mmio_bases: [usize; 32] = [
                    0xa000000, 0xa000200, 0xa000400, 0xa000600,
                    0xa000800, 0xa000a00, 0xa000c00, 0xa000e00,
                    0xa001000, 0xa001200, 0xa001400, 0xa001600,
                    0xa001800, 0xa001a00, 0xa001c00, 0xa001e00,
                    0xa002000, 0xa002200, 0xa002400, 0xa002600,
                    0xa002800, 0xa002a00, 0xa002c00, 0xa002e00,
                    0xa003000, 0xa003200, 0xa003400, 0xa003600,
                    0xa003800, 0xa003a00, 0xa003c00, 0xa003e00,
                ];

                for &paddr in &mmio_bases {
                    let mmio_base = LINEAR_BASE + paddr;
                    let magic = mmio_read(mmio_base, REG_MAGIC);
                    if magic != 0x74726976 {
                        continue;
                    }
                    let device_id = mmio_read(mmio_base, REG_DEVICE_ID);
                    if device_id == 0 {
                        continue;
                    }
                    ostd::early_println!("[virtio] device at {:#x}: id={}", paddr, device_id);

                    if device_id == 16 {
                        ostd::early_println!("[virtio] *** VIRTIO-GPU found! Initializing... ***");
                        init_gpu(mmio_base);
                    }
                }
            }

            fn init_gpu(mmio_base: usize) {
                // 1. Negotiate features
                mmio_write(mmio_base, REG_STATUS, 0);
                mmio_write(mmio_base, REG_STATUS, STATUS_ACKNOWLEDGE | STATUS_DRIVER);
                let device_features = mmio_read(mmio_base, REG_DEVICE_FEATURES);
                // We want no special features (no virgl, just 2D)
                mmio_write(mmio_base, REG_DRIVER_FEATURES, 0);
                mmio_write(mmio_base, REG_STATUS, STATUS_ACKNOWLEDGE | STATUS_DRIVER | STATUS_FEATURES_OK);
                let status = mmio_read(mmio_base, REG_STATUS);
                if status & STATUS_FEATURES_OK == 0 {
                    ostd::early_println!("[virtio-gpu] FEATURES_OK not set!");
                    return;
                }
                ostd::early_println!("[virtio-gpu] features negotiated OK");

                // 2. Set up the control queue (queue 0)
                mmio_write(mmio_base, REG_QUEUE_SEL, 0);
                let queue_max = mmio_read(mmio_base, REG_QUEUE_NUM_MAX);
                ostd::early_println!("[virtio-gpu] control queue max={}", queue_max);
                let queue_size: usize = if queue_max > 0 { (queue_max as usize).min(64) } else { 64 };

                // Allocate virtqueue: desc + avail + used
                let desc_size = queue_size * 16;
                let avail_size = 6 + 2 * queue_size;
                let used_size = 6 + 8 * queue_size;
                let align: usize = 4096;

                let total_size = desc_size + align + avail_size + align + used_size;
                let base_paddr = alloc_pages(total_size);

                // For legacy virtio-mmio, queue_pfn is the page frame number
                // of the descriptor table. avail and used follow at fixed offsets.
                // Queue align = 4096 (page aligned).
                mmio_write(mmio_base, REG_QUEUE_NUM, queue_size as u32);
                mmio_write(mmio_base, REG_QUEUE_ALIGN, align as u32);
                mmio_write(mmio_base, REG_QUEUE_PFN, (base_paddr / 4096) as u32);

                // 3. DRIVER_OK
                mmio_write(mmio_base, REG_STATUS, STATUS_ACKNOWLEDGE | STATUS_DRIVER | STATUS_FEATURES_OK | STATUS_DRIVER_OK);
                ostd::early_println!("[virtio-gpu] DRIVER_OK set, queue initialized");
                ostd::early_println!("[virtio-gpu] TODO: send GET_DISPLAY_INFO + 2D commands");

                // Read config: num_scanouts, num_capsets
                // Config is at MMIO + 0x104 (config generation) then the config struct
                // For virtio-gpu: num_scanouts at offset 4, events_read at 0, num_capsets at 8
                let num_scanouts = mmio_read(mmio_base, 0x108); // offset 0x104 + 4
                ostd::early_println!("[virtio-gpu] num_scanouts={}", num_scanouts);
            }
        }
        ostd::early_println!("[virtio] raw MMIO probe via linear mapping...");
        raw_probe::probe();
    }

    let mut dev_idx = 0;
    while let Some(mut transport) = pop_device_transport() {
        dev_idx += 1;
        ostd::early_println!("[virtio] processing device #{}", dev_idx);
        // Reset device
        ostd::early_println!("[virtio] dev #{}: resetting...", dev_idx);
        transport
            .write_device_status(DeviceStatus::empty())
            .unwrap();
        while transport.read_device_status() != DeviceStatus::empty() {
            spin_loop();
        }

        // Set to acknowledge
        transport
            .write_device_status(DeviceStatus::ACKNOWLEDGE | DeviceStatus::DRIVER)
            .unwrap();
        // negotiate features
        negotiate_features(&mut transport);

        if !transport.is_legacy_version() {
            // change to features ok status
            let status =
                DeviceStatus::ACKNOWLEDGE | DeviceStatus::DRIVER | DeviceStatus::FEATURES_OK;
            transport.write_device_status(status).unwrap();
        }

        let device_type = transport.device_type();
        let res = match transport.device_type() {
            VirtioDeviceType::Block => BlockDevice::init(transport),
            VirtioDeviceType::Console => ConsoleDevice::init(transport),
            VirtioDeviceType::Entropy => EntropyDevice::init(transport),
            VirtioDeviceType::Gpu => GpuDevice::init(transport),
            VirtioDeviceType::Input => InputDevice::init(transport),
            VirtioDeviceType::Network => NetworkDevice::init(transport),
            VirtioDeviceType::Socket => SocketDevice::init(transport),
            VirtioDeviceType::FileSystem => FileSystemDevice::init(transport),
            _ => {
                warn!("Found unimplemented device: {:?}", device_type);
                Ok(())
            }
        };
        if res.is_err() {
            error!(
                "Device initialization error: {:?}, device type: {:?}",
                res, device_type
            );
        }
    }
    Ok(())
}

fn pop_device_transport() -> Option<Box<dyn VirtioTransport>> {
    if let Some(device) = VIRTIO_PCI_DRIVER.get().unwrap().pop_device_transport() {
        return Some(device);
    }
    if let Some(device) = VIRTIO_MMIO_DRIVER.get().unwrap().pop_device_transport() {
        return Some(Box::new(device));
    }
    None
}

fn negotiate_features(transport: &mut Box<dyn VirtioTransport>) {
    let features = transport.read_device_features();
    let mask = ((1u64 << 24) - 1) | (((1u64 << 24) - 1) << 50);
    let device_specified_features = features & mask;
    let device_support_features = match transport.device_type() {
        VirtioDeviceType::Network => NetworkDevice::negotiate_features(device_specified_features),
        VirtioDeviceType::Block => BlockDevice::negotiate_features(device_specified_features),
        VirtioDeviceType::Input => InputDevice::negotiate_features(device_specified_features),
        VirtioDeviceType::Console => ConsoleDevice::negotiate_features(device_specified_features),
        VirtioDeviceType::Gpu => GpuDevice::negotiate_features(device_specified_features),
        VirtioDeviceType::Socket => SocketDevice::negotiate_features(device_specified_features),
        VirtioDeviceType::FileSystem => {
            FileSystemDevice::negotiate_features(device_specified_features)
        }
        _ => device_specified_features,
    };
    let mut support_feature = Feature::from_bits_truncate(features);
    support_feature.remove(Feature::RING_EVENT_IDX);
    transport
        .write_driver_features(features & (support_feature.bits | device_support_features))
        .unwrap();
}

bitflags! {
    /// all device features, bits 0~23 and 50~63 are specified by device.
    /// if using this struct to translate u64, use from_bits_truncate function instead of from_bits
    ///
    struct Feature: u64 {

        // device independent
        const NOTIFY_ON_EMPTY       = 1 << 24; // legacy
        const ANY_LAYOUT            = 1 << 27; // legacy
        const RING_INDIRECT_DESC    = 1 << 28;
        const RING_EVENT_IDX        = 1 << 29;
        const UNUSED                = 1 << 30; // legacy
        const VERSION_1             = 1 << 32; // detect legacy

        // since virtio v1.1
        const ACCESS_PLATFORM       = 1 << 33;
        const RING_PACKED           = 1 << 34;
        const IN_ORDER              = 1 << 35;
        const ORDER_PLATFORM        = 1 << 36;
        const SR_IOV                = 1 << 37;
        const NOTIFICATION_DATA     = 1 << 38;
        const NOTIF_CONFIG_DATA     = 1 << 39;
        const RING_RESET            = 1 << 40;
    }
}
