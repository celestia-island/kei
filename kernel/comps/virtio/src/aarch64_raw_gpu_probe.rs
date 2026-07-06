// SPDX-License-Identifier: MPL-2.0

//! Raw virtio-gpu probe for aarch64 without kernel page table.
//!
//! This module bypasses the normal IoMem/virtqueue infrastructure (which
//! requires the kernel page table to be activated) and uses raw volatile
//! reads/writes through the boot page table's linear mapping instead.

#![allow(unsafe_code)]

use core::ptr::{read_volatile, write_volatile};

const LINEAR_BASE: usize = 0xffff_8000_0000_0000;

// virtio-mmio register offsets
const REG_MAGIC: usize = 0x000;
const REG_DEVICE_ID: usize = 0x008;
const REG_DEVICE_FEATURES: usize = 0x010;
const REG_DRIVER_FEATURES: usize = 0x020;
const REG_QUEUE_SEL: usize = 0x030;
const REG_QUEUE_NUM_MAX: usize = 0x034;
const REG_QUEUE_NUM: usize = 0x038;
const REG_QUEUE_ALIGN: usize = 0x03C;
const REG_QUEUE_PFN: usize = 0x040;
const REG_QUEUE_NOTIFY: usize = 0x050;
const REG_STATUS: usize = 0x070;

const STATUS_ACK: u32 = 1;
const STATUS_DRIVER: u32 = 2;
const STATUS_FEAT_OK: u32 = 8;
const STATUS_DRV_OK: u32 = 4;

fn mmio_r(base: usize, off: usize) -> u32 {
    unsafe { read_volatile((base + off) as *const u32) }
}
fn mmio_w(base: usize, off: usize, v: u32) {
    unsafe { write_volatile((base + off) as *mut u32, v) }
}

// Static backing for virtqueue. MUST be page-aligned for legacy virtio-mmio.
#[repr(C, align(4096))]
struct PageAligned<const N: usize>([u8; N]);

static mut VQ_MEM: PageAligned<16384> = PageAligned([0; 16384]);
static mut VQ_OFF: usize = 0;
fn vq_alloc(n: usize) -> usize {
    unsafe {
        let a = (VQ_OFF + 4095) & !4095;
        VQ_OFF = a + n;
        // We're running on identity mapping (no page table switch).
        // The vaddr IS the paddr for kernel code/data.
        core::ptr::addr_of!(VQ_MEM) as *const u8 as usize + a
    }
}

// Static backing for command/response buffers
static mut CMD_MEM: [u8; 4096] = [0; 4096];
static mut CMD_OFF: usize = 0;
fn cmd_alloc(n: usize) -> usize {
    // Returns the VIRTUAL address of the buffer (for kernel access).
    // On identity mapping, vaddr == paddr.
    unsafe {
        let o = CMD_OFF;
        CMD_OFF += n;
        core::ptr::addr_of!(CMD_MEM) as usize + o
    }
}

pub fn probe() {
    ostd::early_println!("[virtio-gpu] raw MMIO probe via linear mapping...");
    let bases: [usize; 32] = [
        0xa000000, 0xa000200, 0xa000400, 0xa000600,
        0xa000800, 0xa000a00, 0xa000c00, 0xa000e00,
        0xa001000, 0xa001200, 0xa001400, 0xa001600,
        0xa001800, 0xa001a00, 0xa001c00, 0xa001e00,
        0xa002000, 0xa002200, 0xa002400, 0xa002600,
        0xa002800, 0xa002a00, 0xa002c00, 0xa002e00,
        0xa003000, 0xa003200, 0xa003400, 0xa003600,
        0xa003800, 0xa003a00, 0xa003c00, 0xa003e00,
    ];
    for &pa in &bases {
        let mb = LINEAR_BASE + pa;
        if mmio_r(mb, REG_MAGIC) != 0x74726976 { continue; }
        let did = mmio_r(mb, REG_DEVICE_ID);
        if did == 0 { continue; }
        ostd::early_println!("[virtio] device at {:#x}: id={}", pa, did);
        if did == 16 {
            ostd::early_println!("[virtio] *** VIRTIO-GPU found! ***");
            init_gpu(mb);
        }
    }
}

fn init_gpu(mmio_base: usize) {
    // Negotiate
    mmio_w(mmio_base, REG_STATUS, 0);
    mmio_w(mmio_base, REG_STATUS, STATUS_ACK | STATUS_DRIVER);
    mmio_w(mmio_base, REG_DRIVER_FEATURES, 0);
    mmio_w(mmio_base, REG_STATUS, STATUS_ACK | STATUS_DRIVER | STATUS_FEAT_OK);
    let st = mmio_r(mmio_base, REG_STATUS);
    if st & STATUS_FEAT_OK == 0 {
        ostd::early_println!("[virtio-gpu] FEATURES_OK failed!");
        return;
    }
    ostd::early_println!("[virtio-gpu] features OK");

    // Setup control queue (queue 0)
    mmio_w(mmio_base, REG_QUEUE_SEL, 0);
    let qmax = mmio_r(mmio_base, REG_QUEUE_NUM_MAX);
    let qsize: usize = (qmax as usize).min(64);
    ostd::early_println!("[virtio-gpu] queue max={} size={}", qmax, qsize);

    let desc_sz = qsize * 16;
    let avail_sz = 6 + 2 * qsize;
    let used_sz = 6 + 8 * qsize;
    // Legacy virtio-mmio layout: desc+avail contiguous, used page-aligned after
    let used_off = (desc_sz + avail_sz + 4095) & !4095;
    let total = used_off + used_sz;
    let base_pa = vq_alloc(total);
    let base_va = LINEAR_BASE + base_pa;

    ostd::early_println!("[virtio-gpu] vq base_pa={:#x} pfn={}", base_pa, base_pa / 4096);
    ostd::early_println!("[virtio-gpu] desc_sz={} avail_sz={} used_sz={} used_off={}", desc_sz, avail_sz, used_sz, used_off);
    ostd::early_println!("[virtio-gpu] total_alloc={}", total);

    mmio_w(mmio_base, REG_QUEUE_NUM, qsize as u32);
    mmio_w(mmio_base, REG_QUEUE_ALIGN, 4096u32);
    mmio_w(mmio_base, REG_QUEUE_PFN, (base_pa / 4096) as u32);
    mmio_w(mmio_base, REG_STATUS, STATUS_ACK | STATUS_DRIVER | STATUS_FEAT_OK | STATUS_DRV_OK);
    ostd::early_println!("[virtio-gpu] DRIVER_OK, queue ready");

    // Legacy layout: desc at 0, avail at desc_sz, used at used_off
    let avail_off = desc_sz;

    // cmd hdr: type=0x0100, fence=1
    let cmd_va = cmd_alloc(24);
    let resp_va = cmd_alloc(80); // resp_hdr(24) + display info(56)
    ostd::early_println!("[virtio-gpu] cmd_va={:#x} resp_va={:#x}", cmd_va, resp_va);
    unsafe {
        let p = cmd_va as *mut u8;
        write_volatile(p.add(0) as *mut u32, 0x0100); // GET_DISPLAY_INFO
        write_volatile(p.add(8) as *mut u64, 1); // fence_id
    }

    // Setup descriptors
    unsafe {
        let d = base_va;
        // desc[0]: cmd (device-readable)
        write_volatile(d as *mut u64, cmd_va as u64); // identity-mapped: vaddr=paddr
        write_volatile((d + 8) as *mut u32, 24);
        write_volatile((d + 12) as *mut u16, 0); // flags
        write_volatile((d + 14) as *mut u16, 1); // next

        // desc[1]: resp (device-writable)
        let d1 = d + 16;
        write_volatile(d1 as *mut u64, resp_va as u64);
        write_volatile((d1 + 8) as *mut u32, 80);
        write_volatile((d1 + 12) as *mut u16, 1); // WRITE flag
        write_volatile((d1 + 14) as *mut u16, 0); // no next

        // Avail ring
        let av = base_va + avail_off;
        write_volatile(av as *mut u16, 0); // flags
        write_volatile((av + 4) as *mut u16, 0); // ring[0] = 0
        write_volatile((av + 2) as *mut u16, 1); // idx = 1
    }

    // Notify
    mmio_w(mmio_base, REG_QUEUE_NOTIFY, 0);
    ostd::early_println!("[virtio-gpu] GET_DISPLAY_INFO sent...");

    // Poll used ring
    let used = base_va + used_off;
    let mut ok = false;
    for _ in 0..1_000_000 {
        let ui = unsafe { read_volatile((used + 2) as *const u16) };
        if ui > 0 { ok = true; break; }
    }
    if ok {
        let rt = unsafe { read_volatile(resp_va as *const u32) };
        ostd::early_println!("[virtio-gpu] resp type={:#x}", rt);
        if rt == 0x1100 || rt == 0x1101 {
            // Display info: x(4), y(4), width(4), height(4), enabled(4)
            let w = unsafe { read_volatile((resp_va + 24 + 8) as *const u32) };
            let h = unsafe { read_volatile((resp_va + 24 + 12) as *const u32) };
            ostd::early_println!("[virtio-gpu] display: {}x{}", w, h);
        }
    } else {
        ostd::early_println!("[virtio-gpu] no response (timeout)");
    }
}
