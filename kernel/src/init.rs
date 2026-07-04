// SPDX-License-Identifier: MPL-2.0

//! Kernel initialization.

use aster_cmdline::INIT_PROC_ARGS;
use component::InitStage;
use ostd::{cpu::CpuId, util::id_set::Id};
use spin::once::Once;

use crate::{
    fs::vfs::path::{MountNamespace, PathResolver},
    prelude::*,
    process::{Process, spawn_init_process},
    sched::SchedPolicy,
    thread::kernel_thread::ThreadOptions,
};

pub(super) fn main() {
    // VBE graphics framebuffer (x86_64 QEMU with -vga std)
    #[cfg(target_arch = "x86_64")]
    {
        ostd::early_println!("[VBE] Setting graphics mode 640x480x32...");
        if let Some((fb_addr, w, h, bpp)) = crate::vbe_dispi::set_graphics_mode(640, 480, 32) {
            ostd::early_println!("[VBE] Framebuffer at {:#x}, {}x{}x{}", fb_addr, w, h, bpp);

            // Draw a test pattern: blue background with green banner area
            crate::vbe_dispi::draw_rect(fb_addr, w, h, bpp, 0, 0, w, h, 10, 10, 40); // dark blue bg
            crate::vbe_dispi::draw_rect(fb_addr, w, h, bpp, 50, 80, 540, 160, 20, 20, 20); // banner bg

            ostd::early_println!("[VBE] Graphics displayed on QEMU VGA.");
        } else {
            ostd::early_println!("[VBE] No VBE DISPI support, falling back to VGA text");
            crate::vga_text::print_banner();
        }
    }

    // Initialize the global states for all CPUs.
    ostd::early_println!("OSTD initialized. Preparing components.");
    if let Err(e) = component::init_all(InitStage::Bootstrap, component::parse_metadata!()) {
        ostd::early_println!("[WARN] component::init_all(Bootstrap) failed: {:?}", e);
    }
    ostd::early_println!("Components Bootstrap done.");
    init();
    ostd::early_println!("Kernel init done.");
    ostd::early_println!("Kernel init done.");

    // Initialize the per-CPU states for BSP.
    init_on_each_cpu();
    ostd::early_println!("Per-CPU init done.");

    // Enable APs.
    ostd::boot::smp::register_ap_entry(ap_init);
    ostd::early_println!("Spawning BSP idle thread...");

    // Give the control of the BSP to the idle thread.
    ThreadOptions::new(bsp_idle_loop)
        .cpu_affinity(CpuId::bsp().into())
        .sched_policy(SchedPolicy::Idle)
        .spawn();
    ostd::early_println!("BSP idle thread spawned.");
}

fn init() {
    ostd::early_println!("[init] arch::init");
    crate::arch::init();
    ostd::early_println!("[init] thread::init");
    crate::thread::init();
    ostd::early_println!("[init] random::init");
    crate::util::random::init();
    ostd::early_println!("[init] driver::init");
    crate::driver::init();
    ostd::early_println!("[init] time::init");
    crate::time::init();
    ostd::early_println!("[init] net::init");
    crate::net::init();
    ostd::early_println!("[init] sched::init");
    crate::sched::init();
    ostd::early_println!("[init] process::init");
    crate::process::init();
    ostd::early_println!("[init] fs::init");
    crate::fs::init();
    ostd::early_println!("[init] security::init");
    crate::security::init();
    ostd::early_println!("[init] done");
}

fn init_on_each_cpu() {
    crate::sched::init_on_each_cpu();
    crate::process::init_on_each_cpu();
    crate::fs::init_on_each_cpu();
    crate::time::init_on_each_cpu();
}

fn ap_init() {
    // Initialize the per-CPU states for AP.
    init_on_each_cpu();

    ThreadOptions::new(ap_idle_loop)
        // No races because `ap_init` runs on a certain AP.
        .cpu_affinity(CpuId::current_racy().into())
        .sched_policy(SchedPolicy::Idle)
        .spawn();
}

//--------------------------------------------------------------------------
// Per-CPU idle threads
//--------------------------------------------------------------------------

// Note: Keep the code in the idle loop to the bare minimum.
//
// We do not want the idle loop to
// rely on the APIs of other kernel subsystems for two reasons.
// First, the idle task must never sleep or block.
// This property is relied upon by the scheduler.
// Second, the idle task is spawned before the kernel is fully initialized.
// So other subsystems may not be ready, yet.
//
// In addition,
// doing more work in the idle task may have negative impact on
// the latency to switching from the idle task to a useful, runnable one.

fn bsp_idle_loop() {
    ostd::info!("Idle thread for CPU #0 started");

    // Spawn the first non-idle kernel thread on BSP.
    ThreadOptions::new(first_kthread)
        .cpu_affinity(CpuId::bsp().into())
        .sched_policy(SchedPolicy::default())
        .spawn();

    // Wait till the init process is spawned.
    let init_process = loop {
        if let Some(init_process) = INIT_PROCESS.get() {
            break init_process;
        };

        ostd::task::halt_cpu();
    };

    // Wait till the init process becomes zombie.
    while !init_process.status().is_zombie() {
        ostd::task::halt_cpu();
    }

    panic!(
        "The init process terminates with code {:?}",
        init_process.status().exit_code()
    );
}

fn ap_idle_loop() {
    ostd::info!(
        "Idle thread for CPU #{} started",
        // No races because this function runs on a certain AP.
        CpuId::current_racy().as_usize(),
    );

    loop {
        ostd::task::halt_cpu();
    }
}

//--------------------------------------------------------------------------
// The first kernel thread
//--------------------------------------------------------------------------

// The main function of the first (non-idle) kernel thread
fn first_kthread() {
    println!("Spawn the first kernel thread");

    let init_mnt_ns = MountNamespace::get_init_singleton();
    let fs_resolver = init_mnt_ns.new_path_resolver();
    init_in_first_kthread(&fs_resolver);

    print_banner();

    INIT_PROCESS.call_once(|| {
        let karg = INIT_PROC_ARGS.get().unwrap();
        let init_path = INIT_PATH.get().map(|s| s.as_str());
        spawn_init_process(init_path, karg.argv().to_vec(), karg.envp().to_vec())
            .expect("Failed to run the init process")
    });
}

static INIT_PROCESS: Once<Arc<Process>> = Once::new();

fn init_in_first_kthread(path_resolver: &PathResolver) {
    if let Err(e) = component::init_all(InitStage::Kthread, component::parse_metadata!()) {
        ostd::early_println!("[WARN] component::init_all(Kthread) failed: {:?}", e);
    }
    // Work queue should be initialized before interrupt is enabled,
    // in case any irq handler uses work queue as bottom half
    crate::thread::work_queue::init_in_first_kthread();
    crate::device::init_in_first_kthread();
    crate::net::init_in_first_kthread();
    crate::fs::init_in_first_kthread(path_resolver);
    #[cfg(any(target_arch = "x86_64", target_arch = "riscv64"))]
    crate::vdso::init_in_first_kthread();
}

fn print_banner() {
    println!("");
    println!("{}", logo_ascii_art::get_gradient_color_version());
}

pub(super) fn on_first_process_startup(ctx: &Context) {
    component::init_all(InitStage::Process, component::parse_metadata!()).unwrap();
    crate::device::init_in_first_process(ctx).unwrap();
    crate::fs::init_in_first_process(ctx);

    // Open /dev/console as fd 0 (stdin), 1 (stdout), 2 (stderr) for the init
    // process.  Linux does this in kernel_init() before exec'ing init; without
    // it, user-space writes to stdout silently fail (EBADF).
    open_initial_console(ctx);
}

/// Opens `/dev/console` and assigns it to fd 0, 1, 2.
///
/// Mirrors Linux's `init/main.c`:
///   fd = open("/dev/console", O_RDWR);
///   dup(fd);  // stdout
///   dup(fd);  // stderr
fn open_initial_console(ctx: &Context) {
    use crate::fs::{
        file::{
            AccessMode, FileLike, InodeHandle, StatusFlags,
            file_table::FdFlags,
        },
        vfs::path::FsPath,
    };

    // Try /dev/ttyS0 first (created by serial init in RamFs), then /dev/console.
    let console_paths = ["/dev/ttyS0", "/dev/console"];
    let fs_info = ctx.thread_local.borrow_fs();
    let resolver = fs_info.resolver();
    let resolver_guard = resolver.read();

    let path = console_paths.iter().find_map(|p| {
        FsPath::try_from(*p).ok().and_then(|fp| {
            resolver_guard.lookup(&fp).ok().map(|path| (*p, path))
        })
    });
    drop(resolver_guard);

    let Some((found_path, path)) = path else {
        return;
    };

    let file: Arc<dyn FileLike> = match InodeHandle::new(path, AccessMode::O_RDWR, StatusFlags::empty()) {
        Ok(f) => Arc::new(f),
        Err(_) => return,
    };

    let file_table = ctx.thread_local.borrow_file_table();
    let mut ft = file_table.unwrap().write();
    let _ = ft.insert(file.clone(), FdFlags::empty()); // fd 0 = stdin
    let _ = ft.insert(file.clone(), FdFlags::empty()); // fd 1 = stdout
    let _ = ft.insert(file.clone(), FdFlags::empty()); // fd 2 = stderr
}

static INIT_PATH: Once<String> = Once::new();
aster_cmdline::define_kv_param!("init", INIT_PATH);
