//! ICE host-candidate discovery.
//!
//! The SFU runs ICE-Lite with host candidates only: auto-detected interface
//! addresses (LAN + global/ULA v6 — covers the VPS public-v4 case) plus the
//! operator's `advertised_addrs` for the port-forwarded-home-NAT case.

use std::net::{IpAddr, SocketAddr};

use crate::AdvertisedAddr;

/// Resolve the set of addresses the SFU advertises to callers.
///
/// * Bound to a wildcard address → enumerate interfaces.
/// * Bound to an explicit address (tests bind `127.0.0.1:0`) → trust it
///   verbatim, even loopback.
/// * `advertised_addrs` are appended; bare IPs get the actual bound port.
pub(crate) fn candidate_addrs(bound: SocketAddr, advertised: &[AdvertisedAddr]) -> Vec<SocketAddr> {
    let mut out: Vec<SocketAddr> = Vec::new();
    let push = |addr: SocketAddr, out: &mut Vec<SocketAddr>| {
        if !out.contains(&addr) {
            out.push(addr);
        }
    };

    let port = bound.port();
    if bound.ip().is_unspecified() {
        for iface in if_addrs::get_if_addrs().unwrap_or_default() {
            let ip = iface.ip();
            if usable(ip) {
                push(SocketAddr::new(ip, port), &mut out);
            }
        }
    } else {
        push(bound, &mut out);
    }

    for a in advertised {
        let addr = match a {
            AdvertisedAddr::Full(sa) => *sa,
            AdvertisedAddr::IpOnly(ip) => SocketAddr::new(*ip, port),
        };
        push(addr, &mut out);
    }
    out
}

/// Reachable-off-box filter: no loopback, no unspecified, no link-local.
/// Private v4 and ULA v6 stay in — they are exactly what a LAN relay
/// advertises.
fn usable(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            !v4.is_loopback() && !v4.is_unspecified() && !v4.is_link_local() && !v4.is_broadcast()
        }
        IpAddr::V6(v6) => {
            // fe80::/10 (link-local needs a scope id — useless in SDP).
            let link_local = (v6.segments()[0] & 0xffc0) == 0xfe80;
            !v6.is_loopback() && !v6.is_unspecified() && !link_local
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explicit_bind_is_trusted_verbatim() {
        let bound: SocketAddr = "127.0.0.1:5000".parse().unwrap();
        assert_eq!(candidate_addrs(bound, &[]), vec![bound]);
    }

    #[test]
    fn bare_advertised_ip_gets_bound_port() {
        let bound: SocketAddr = "127.0.0.1:5000".parse().unwrap();
        let adv = [AdvertisedAddr::IpOnly("203.0.113.9".parse().unwrap())];
        let addrs = candidate_addrs(bound, &adv);
        assert!(addrs.contains(&"203.0.113.9:5000".parse().unwrap()));
    }

    #[test]
    fn full_advertised_addr_keeps_its_port() {
        let bound: SocketAddr = "127.0.0.1:5000".parse().unwrap();
        let adv = [AdvertisedAddr::Full("203.0.113.9:61000".parse().unwrap())];
        let addrs = candidate_addrs(bound, &adv);
        assert!(addrs.contains(&"203.0.113.9:61000".parse().unwrap()));
    }

    #[test]
    fn duplicates_collapse() {
        let bound: SocketAddr = "127.0.0.1:5000".parse().unwrap();
        let adv = [
            AdvertisedAddr::Full("127.0.0.1:5000".parse().unwrap()),
            AdvertisedAddr::IpOnly("127.0.0.1".parse().unwrap()),
        ];
        assert_eq!(candidate_addrs(bound, &adv).len(), 1);
    }

    #[test]
    fn usable_filters_special_ranges() {
        assert!(!usable("127.0.0.1".parse().unwrap()));
        assert!(!usable("0.0.0.0".parse().unwrap()));
        assert!(!usable("169.254.1.1".parse().unwrap()));
        assert!(usable("192.168.1.20".parse().unwrap()));
        assert!(usable("203.0.113.9".parse().unwrap()));
        assert!(!usable("::1".parse().unwrap()));
        assert!(!usable("fe80::1".parse().unwrap()));
        assert!(usable("fd12:3456::1".parse().unwrap()), "ULA v6 is LAN-usable");
        assert!(usable("2001:db8::1".parse().unwrap()));
    }
}
