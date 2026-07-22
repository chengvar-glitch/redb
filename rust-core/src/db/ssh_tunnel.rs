use std::sync::Arc;
use std::time::Duration;

use tokio::io::copy_bidirectional;
use tokio::net::TcpListener;
use tokio::sync::{oneshot, Mutex as AsyncMutex};
use tokio::task::JoinHandle;

use crate::types::DbError;

/// Internal SSH tunnel handle. Lives inside a `DbConnection` variant and is
/// dropped when the owning connection is disconnected — the accept loop
/// receives shutdown_tx, cancels itself, and the russh session is dropped.
pub struct SshTunnel {
    local_port: u16,
    _accept_task: JoinHandle<()>,
    shutdown_tx: Option<oneshot::Sender<()>>,
}

impl SshTunnel {
    pub fn local_port(&self) -> u16 {
        self.local_port
    }

    /// Open a tunnel on the caller's tokio runtime. Bastion auth is password-only
    /// (per product scope). Host key is trust-on-first-use — accepted silently for
    /// MVP; when a persistent known_hosts store lands, this handler consults it.
    pub async fn open(
        ssh_host: String,
        ssh_port: u16,
        ssh_user: String,
        ssh_password: String,
        target_host: String,
        target_port: u16,
    ) -> Result<Self, DbError> {
        let config = Arc::new(russh::client::Config {
            keepalive_interval: Some(Duration::from_secs(30)),
            inactivity_timeout: Some(Duration::from_secs(600)),
            nodelay: true,
            ..Default::default()
        });

        let mut handle_raw = russh::client::connect(
            config,
            (ssh_host.as_str(), ssh_port),
            TunnelHandler,
        )
        .await
        .map_err(|e| DbError::ConnectionError {
            message: format!("SSH connect failed: {e}"),
        })?;

        let auth = handle_raw
            .authenticate_password(&ssh_user, &ssh_password)
            .await
            .map_err(|e| DbError::ConnectionError {
                message: format!("SSH auth error: {e}"),
            })?;
        if !auth.success() {
            return Err(DbError::ConnectionError {
                message: "SSH password authentication rejected by server".to_string(),
            });
        }

        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .map_err(|e| DbError::ConnectionError {
                message: format!("SSH tunnel bind failed: {e}"),
            })?;
        let local_port = listener
            .local_addr()
            .map_err(|e| DbError::ConnectionError {
                message: format!("SSH tunnel local_addr failed: {e}"),
            })?
            .port();

        let (shutdown_tx, mut shutdown_rx) = oneshot::channel::<()>();

        let handle = Arc::new(AsyncMutex::new(handle_raw));
        let accept_task = tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = &mut shutdown_rx => break,
                    accept = listener.accept() => {
                        let Ok((mut local_stream, peer_addr)) = accept else { break };
                        let h = handle.clone();
                        let th = target_host.clone();
                        tokio::spawn(async move {
                            let channel = {
                                let guard = h.lock().await;
                                guard
                                    .channel_open_direct_tcpip(
                                        th.as_str(),
                                        target_port as u32,
                                        peer_addr.ip().to_string(),
                                        peer_addr.port() as u32,
                                    )
                                    .await
                            };
                            let channel = match channel {
                                Ok(c) => c,
                                Err(e) => {
                                    tracing::warn!("SSH direct-tcpip open failed: {e}");
                                    return;
                                }
                            };
                            let mut remote = channel.into_stream();
                            let _ = copy_bidirectional(&mut local_stream, &mut remote).await;
                        });
                    }
                }
            }
        });

        Ok(Self {
            local_port,
            _accept_task: accept_task,
            shutdown_tx: Some(shutdown_tx),
        })
    }
}

impl Drop for SshTunnel {
    fn drop(&mut self) {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(());
        }
    }
}

struct TunnelHandler;

impl russh::client::Handler for TunnelHandler {
    type Error = russh::Error;

    fn check_server_key(
        &mut self,
        _server_key: &russh::keys::ssh_key::PublicKey,
    ) -> impl std::future::Future<Output = Result<bool, Self::Error>> + Send {
        async { Ok(true) }
    }
}
