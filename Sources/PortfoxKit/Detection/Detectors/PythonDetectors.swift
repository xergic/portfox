import Foundation

public extension DetectorCatalog {
    /// Python web frameworks and their servers. `.uvicorn` and `.python` are low
    /// specificity fallbacks: their signal sets stay small and their thresholds low
    /// so a real framework match, which scores far higher, always outranks them.
    static let python: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .fastAPI,
            threshold: standardThreshold,
            signals: [
                .commandContains("fastapi", 90),
                .dependency("fastapi", 60),
                // FastAPI is almost always served by uvicorn, so a project that
                // depends on fastapi outweighs the plain uvicorn detector even when
                // "fastapi" never appears on the command line itself.
                .custom("uvicorn command line and manifest depends on fastapi", 60, group: "command") { ctx in
                    ctx.command.contains("uvicorn") && (ctx.project?.hasDependency("fastapi") ?? false)
                }
            ]
        ),
        RuleBasedDetector(
            type: .django,
            threshold: standardThreshold,
            signals: [
                .commandContains("manage.py runserver", 90),
                .commandContains("manage.py", 85),
                .configFile("manage.py", 70),
                .dependency("django", 60),
                .custom("gunicorn or uvicorn command line and manifest depends on django", 60, group: "command") { ctx in
                    // Django's own deployment docs use both servers, so neither
                    // may be reported as the bare server it is running under.
                    let servers = ["gunicorn", "uvicorn", "daphne", "hypercorn"]
                    guard servers.contains(where: { ctx.command.containsToken($0) }) else { return false }
                    return (ctx.project?.hasDependency("django") ?? false)
                        || (ctx.project?.hasFile(prefix: "manage.py") ?? false)
                }
            ]
        ),
        RuleBasedDetector(
            type: .flask,
            threshold: standardThreshold,
            signals: [
                .binPath("flask", 100),
                .commandContains("flask run", 90),
                .dependency("flask", 60)
            ]
        ),
        RuleBasedDetector(
            type: .uvicorn,
            threshold: 80,
            signals: [
                .executableNamed("uvicorn", 100),
                .commandContains("uvicorn", 85),
                .defaultPort(8000)
            ]
        ),
        RuleBasedDetector(
            type: .python,
            threshold: 50,
            signals: [
                .executableNamed("python", 60),
                .executableNamed("python3", 60),
                .defaultPort(8000)
            ]
        ),
        RuleBasedDetector(
            type: .gunicorn,
            threshold: 80,
            signals: [
                // Gunicorn rewrites its argv to `gunicorn: master [myapp]`.
                .executableNamed("gunicorn", 100),
                .commandContains("gunicorn", 85),
                .defaultPort(8000)
            ]
        ),
        RuleBasedDetector(
            type: .streamlit,
            threshold: standardThreshold,
            signals: [
                .binPath("streamlit", 100),
                .commandContains("streamlit run", 92),
                .commandContains("streamlit", 85),
                .dependency("streamlit", 60),
                .defaultPort(8501)
            ]
        ),
        RuleBasedDetector(
            type: .jupyter,
            threshold: standardThreshold,
            signals: [
                // The binaries are `jupyter-lab` and `jupyter-notebook`, and `-`
                // is a word character, so `containsToken("jupyter")` matches
                // neither. Only the bare `jupyter` launcher would have been found.
                .custom("a jupyter launcher binary", 100, group: "command") { ctx in
                    ctx.executableName.hasPrefix("jupyter")
                },
                .custom("a jupyter command line", 88, group: "command") { ctx in
                    ctx.command.contains("/jupyter") || ctx.command.containsToken("jupyter")
                },
                .anyDependency(["jupyterlab", "notebook", "jupyter"], 60),
                .defaultPorts([8888, 8889])
            ]
        ),
        RuleBasedDetector(
            type: .flower,
            threshold: standardThreshold,
            signals: [
                .binPath("flower", 100),
                .commandContains("flower", 88),
                .defaultPort(5555)
            ]
        )
    ]
}
