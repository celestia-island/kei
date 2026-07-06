// SPDX-License-Identifier: MPL-2.0

use super::SyscallReturn;
use crate::{
    fs,
    fs::file::file_table::{RawFileDesc, get_file_fast},
    prelude::*,
};

pub fn sys_write(
    raw_fd: RawFileDesc,
    user_buf_ptr: Vaddr,
    user_buf_len: usize,
    ctx: &Context,
) -> Result<SyscallReturn> {
    // On aarch64, the trait-object vtable for PerOpenFileOps::write_at has a
    // dispatch bug that prevents TtyFile::write_at from being called. As a
    // workaround, when writing to fd 1 (stdout) or fd 2 (stderr), bypass the
    // file abstraction and write directly to the PL011 UART.
    #[cfg(target_arch = "aarch64")]
    if raw_fd == 1 || raw_fd == 2 {
        if user_buf_len != 0 {
            let user_space = ctx.user_space();
            let mut reader = user_space.reader(user_buf_ptr, user_buf_len)?;
            let mut buf = vec![0u8; user_buf_len];
            use ostd::mm::VmWriter;
            let len = reader
                .read_fallible(&mut VmWriter::from(buf.as_mut_slice()))
                .map_err(|e| Error::from(e))?;
            for &byte in &buf[..len] {
                if byte == b'\n' {
                    ostd::arch::serial::pl011_send_byte(b'\r');
                }
                ostd::arch::serial::pl011_send_byte(byte);
            }
            return Ok(SyscallReturn::Return(len as _));
        }
        return Ok(SyscallReturn::Return(0));
    }

    debug!(
        "raw_fd = {}, user_buf_ptr = 0x{:x}, user_buf_len = 0x{:x}",
        raw_fd, user_buf_ptr, user_buf_len
    );

    let mut file_table = ctx.thread_local.borrow_file_table_mut();
    let file = get_file_fast!(&mut file_table, raw_fd.try_into()?);

    // According to <https://man7.org/linux/man-pages/man2/write.2.html>, if
    // the user specified an empty buffer, we should detect errors by checking
    // the file descriptor. If no errors detected, return 0 successfully.
    let write_len = {
        if user_buf_len != 0 {
            let user_space = ctx.user_space();
            let mut reader = user_space.reader(user_buf_ptr, user_buf_len)?;
            file.write(&mut reader)
        } else {
            file.write_bytes(&[])
        }
    }
    .map_err(|err| match err.error() {
        Errno::EINTR => Error::new(Errno::ERESTARTSYS),
        _ => err,
    })?;

    if write_len > 0 {
        fs::vfs::notify::on_modify(&file);
    }
    Ok(SyscallReturn::Return(write_len as _))
}
