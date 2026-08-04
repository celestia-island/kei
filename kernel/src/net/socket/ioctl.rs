// SPDX-License-Identifier: MPL-2.0

//! Socket ioctls.
//!
//! Implements the interface-configuration ioctls (SIOCSIFADDR family) that
//! userspace (e.g. `ifconfig`) issues on a datagram socket.

use core::ffi::CStr;
use core::net::Ipv4Addr;

use crate::{
    net::iface::{get_iface_flags, set_iface_ipv4_addr, set_iface_ipv4_prefix},
    prelude::*,
    util::ioctl::{InOutData, RawIoctl, dispatch_ioctl, ioc},
};

/// `struct ifreq` (subset): the interface request used by the SIOCSIF* ioctls.
///
/// Layout mirrors `<linux/if.h>`: a 16-byte name followed by a 16-byte union
/// (a `sockaddr`, a short flags value, or a pointer depending on the command).
#[repr(C)]
#[derive(Clone, Copy, Pod)]
struct IfReq {
    ifr_name: [u8; 16],
    ifr_union: [u8; 16],
}

const AF_INET: u16 = 2;

impl IfReq {
    fn name(&self) -> Result<&CStr> {
        CStr::from_bytes_until_nul(&self.ifr_name)
            .map_err(|_| Error::with_message(Errno::EINVAL, "ifreq name is not NUL-terminated"))
    }

    /// Extracts the IPv4 address from the embedded `sockaddr_in`.
    ///
    /// Layout: family(2) | port(2) | s_addr(4, network byte order) | zero(8).
    fn ipv4_addr(&self) -> Result<Ipv4Addr> {
        let family = u16::from_ne_bytes([self.ifr_union[0], self.ifr_union[1]]);
        if family != AF_INET {
            return_errno_with_message!(
                Errno::EAFNOSUPPORT,
                "only AF_INET addresses are supported for SIOCSIFADDR"
            );
        }
        Ok(Ipv4Addr::from([
            self.ifr_union[4],
            self.ifr_union[5],
            self.ifr_union[6],
            self.ifr_union[7],
        ]))
    }

    /// Writes the interface flags (`ifr_flags`, a `short`) into the union.
    fn set_flags(&mut self, flags: u16) {
        self.ifr_union[..2].copy_from_slice(&flags.to_ne_bytes());
    }
}

/// Converts a netmask (`255.255.255.0`) into a prefix length (`24`).
fn prefix_len_from_mask(mask: Ipv4Addr) -> u8 {
    let bits = u32::from_be_bytes(mask.octets());
    bits.leading_ones() as u8
}

pub type GetIfaceFlags = ioc!(SIOCGIFFLAGS, 0x8913, InOutData<IfReq>);
pub type SetIfaceAddr = ioc!(SIOCSIFADDR, 0x8916, InOutData<IfReq>);
pub type SetIfaceNetmask = ioc!(SIOCSIFNETMASK, 0x891c, InOutData<IfReq>);
pub type SetIfaceFlags = ioc!(SIOCSIFFLAGS, 0x8914, InOutData<IfReq>);

/// Handles an ioctl issued on a socket fd.
///
/// kei interfaces are always marked UP/RUNNING at creation (see
/// `net::iface::init`), so SIOCSIFFLAGS is accepted without tracking runtime
/// flag state.
pub fn handle_socket_ioctl(raw_ioctl: RawIoctl) -> Result<i32> {
    dispatch_ioctl!(match raw_ioctl {
        cmd @ GetIfaceFlags => {
            let mut req: IfReq = cmd.read()?;
            // Linux's ifr_flags is a short: high bits (IFF_LOWER_UP et al.)
            // are truncated in the ifreq exchange.
            let flags = get_iface_flags(req.name()?)? as u16 as i16 as u16;
            req.set_flags(flags);
            cmd.write(&req)?;
        }
        cmd @ SetIfaceAddr => {
            let req: IfReq = cmd.read()?;
            set_iface_ipv4_addr(req.name()?, req.ipv4_addr()?)?;
        }
        cmd @ SetIfaceNetmask => {
            let req: IfReq = cmd.read()?;
            set_iface_ipv4_prefix(req.name()?, prefix_len_from_mask(req.ipv4_addr()?))?;
        }
        cmd @ SetIfaceFlags => {
            // Accept the request; kei interfaces are always up.
        }
        _ => {
            return_errno_with_message!(Errno::ENOTTY, "the ioctl command is unknown");
        }
    });

    Ok(0)
}
