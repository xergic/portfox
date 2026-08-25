import Foundation

/// The host-side processes that hold a container's published port.
///
/// Shared by the `.docker` detector and by the gate that decides whether a scan
/// is allowed to spawn `docker ps`. One list, so the gate's recall is the
/// detector's recall by construction: a machine whose forwarder Portfox cannot
/// recognise is never asked about its containers, and the row it gets is the
/// undifferentiated Docker row it would have got anyway.
public enum ContainerRuntime {
    /// Matched against the executable's last path component, exactly.
    public static let forwarderNames = ["com.docker.backend", "docker-proxy", "vpnkit"]

    /// Matched anywhere in the executable path. A raw `contains`, not
    /// `containsToken`: these sit inside path segments such as
    /// `/Applications/OrbStack.app/Contents/MacOS/xbin/`, where a word boundary
    /// is not guaranteed on either side.
    public static let forwarderPathFragments = ["orbstack", "/colima/", "limactl"]

    public static func isForwarder(_ process: ProcessSnapshot) -> Bool {
        let name = process.executableName.lowercased()
        if forwarderNames.contains(name) { return true }
        let path = (process.resolvedExecutablePath ?? "").lowercased()
        return forwarderPathFragments.contains(where: path.contains)
    }
}
