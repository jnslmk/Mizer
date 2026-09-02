use std::net::{SocketAddr, ToSocketAddrs};
use std::sync::Mutex;

use sacn::source::SacnSource;

use super::DmxOutput;
use crate::buffer::DmxBuffer;

/// The port sACN uses for both multicast and unicast destinations (E1.31).
const SACN_PORT: u16 = 5568;

pub struct SacnOutput {
    pub priority: u8,
    /// Optional unicast destination; multicast (per universe) when absent.
    pub host: Option<String>,
    source: Mutex<SacnSource>,
}

impl SacnOutput {
    pub fn new(priority: Option<u8>, host: Option<String>) -> Self {
        Self {
            priority: priority.unwrap_or(100),
            host,
            source: Mutex::new(SacnSource::new_v4("mizer").unwrap()),
        }
    }

    /// The unicast destination, or `None` to send multicast.
    fn destination(&self) -> anyhow::Result<Option<SocketAddr>> {
        match &self.host {
            None => Ok(None),
            Some(host) => {
                let address = match host.parse::<SocketAddr>() {
                    // A host may carry an explicit port; otherwise default to the sACN port.
                    Ok(address) => address,
                    Err(_) => (host.as_str(), SACN_PORT)
                        .to_socket_addrs()?
                        .next()
                        .ok_or_else(|| anyhow::anyhow!("cannot resolve sacn host '{}'", host))?,
                };
                Ok(Some(address))
            }
        }
    }
}

impl Default for SacnOutput {
    fn default() -> Self {
        Self::new(None, None)
    }
}

impl DmxOutput for SacnOutput {
    fn name(&self) -> String {
        let Ok(source) = self.source.lock() else {
            return "sACN".into();
        };
        format!("sACN ({})", source.name().unwrap_or_default())
    }

    fn flush(&self, buffer: &DmxBuffer) {
        profiling::scope!("SacnOutput::flush");
        let destination = match self.destination() {
            Ok(destination) => destination,
            Err(err) => {
                tracing::error!("Unable to resolve sacn host {:?}: {:?}", self.host, err);
                return;
            }
        };

        let Ok(mut source) = self.source.lock() else {
            tracing::error!("sacn source mutex poisoned");
            return;
        };

        // E1.31 property values are the DMX start code (0) followed by the 512 slots.
        let mut payload = [0u8; 513];
        for (universe, data) in buffer.iter() {
            if let Err(err) = source.register_universe(universe) {
                tracing::error!("Unable to register sacn universe {:?}", err);
                continue;
            }
            payload[1..].copy_from_slice(&data);
            if let Err(err) = source.send(
                &[universe],
                &payload,
                Some(self.priority),
                destination,
                None,
            ) {
                tracing::error!("Unable to send dmx universe {:?}", err);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::net::UdpSocket;
    use std::time::Duration;

    use crate::buffer::DmxBuffer;

    use super::*;

    #[test]
    fn no_host_sends_multicast() {
        assert_eq!(SacnOutput::new(None, None).destination().unwrap(), None);
    }

    #[test]
    fn host_defaults_to_the_sacn_port() {
        let output = SacnOutput::new(None, Some("127.0.0.1".into()));

        assert_eq!(
            output.destination().unwrap(),
            Some(SocketAddr::from(([127, 0, 0, 1], SACN_PORT)))
        );
    }

    #[test]
    fn host_may_carry_an_explicit_port() {
        let output = SacnOutput::new(None, Some("127.0.0.1:6001".into()));

        assert_eq!(
            output.destination().unwrap(),
            Some(SocketAddr::from(([127, 0, 0, 1], 6001)))
        );
    }

    #[test]
    fn unresolvable_host_is_an_error() {
        let output = SacnOutput::new(None, Some("999.999.999.999".into()));

        assert!(output.destination().is_err());
    }

    #[test]
    fn unicast_flush_sends_an_e131_packet_to_the_host() {
        let receiver = UdpSocket::bind("127.0.0.1:0").unwrap();
        receiver
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let port = receiver.local_addr().unwrap().port();
        let output = SacnOutput::new(None, Some(format!("127.0.0.1:{port}")));

        let buffer = DmxBuffer::default();
        buffer.write_single(1, 511, 0xAB); // last DMX slot
        output.flush(&buffer);

        let mut packet = [0u8; 700];
        let length = receiver.recv(&mut packet).unwrap();
        assert_eq!(&packet[4..16], b"ASC-E1.17\0\0\0");
        let marker = packet[..length].iter().rposition(|b| *b == 0xAB);
        assert_eq!(
            marker,
            Some(length - 1),
            "marker at {marker:?}, len {length}, tail {:02x?}",
            &packet[length - 16..length]
        );
    }
}
