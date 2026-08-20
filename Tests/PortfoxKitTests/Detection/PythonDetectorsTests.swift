import Testing
@testable import PortfoxKit

@Suite("python detectors")
struct PythonDetectorsTests {
    let engine = DetectionEngine(detectors: DetectorCatalog.python + DetectorCatalog.infrastructure)

    @Test("uvicorn serving a project that depends on fastapi is reported as fastAPI")
    func uvicornServingFastAPIProject() {
        let context = DetectionFixture.context(
            command: "/path/.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000",
            executablePath: "/path/.venv/bin/python",
            dependencies: ["fastapi"],
            ports: [8000]
        )

        #expect(engine.detect(context).type == .fastAPI)
    }

    @Test("uvicorn with the executable literally named uvicorn still favors fastAPI when it's the dependency")
    func uvicornExeServingFastAPIProject() {
        let context = DetectionFixture.context(
            command: "uvicorn main:app --reload --port 8000",
            executablePath: "/path/.venv/bin/uvicorn",
            dependencies: ["fastapi"],
            ports: [8000]
        )

        #expect(engine.detect(context).type == .fastAPI)
    }

    @Test("uvicorn with no fastAPI evidence reports uvicorn")
    func uvicornWithoutFastAPIProject() {
        let context = DetectionFixture.context(
            command: "/path/.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000",
            executablePath: "/path/.venv/bin/python",
            ports: [8000]
        )

        #expect(engine.detect(context).type == .uvicorn)
    }

    @Test("manage.py runserver is unambiguous Django")
    func djangoRunserver() {
        let context = DetectionFixture.context(
            command: "python manage.py runserver 0.0.0.0:8000",
            executablePath: "/usr/bin/python",
            projectFiles: ["manage.py"],
            dependencies: ["django"],
            ports: [8000]
        )

        #expect(engine.detect(context).type == .django)
    }

    @Test("a fully-evidenced Django match has high confidence")
    func djangoConfidenceIsHigh() {
        let context = DetectionFixture.context(
            command: "python manage.py runserver 0.0.0.0:8000",
            executablePath: "/usr/bin/python",
            projectFiles: ["manage.py"],
            dependencies: ["django"],
            ports: [8000]
        )

        #expect(engine.detect(context).confidence > 0.8)
    }

    @Test("gunicorn serving a project that depends on django is reported as django")
    func gunicornServingDjangoProject() {
        let context = DetectionFixture.context(
            command: "/path/.venv/bin/gunicorn myproject.wsgi",
            executablePath: "/path/.venv/bin/gunicorn",
            dependencies: ["django"]
        )

        #expect(engine.detect(context).type == .django)
    }

    @Test("flask run is detected from its bin path and command")
    func flaskRun() {
        let context = DetectionFixture.context(
            command: "flask run --port 5000",
            executablePath: "/path/.venv/bin/flask",
            dependencies: ["flask"],
            ports: [5000]
        )

        #expect(engine.detect(context).type == .flask)
    }

    @Test("python app.py with no framework evidence reports generic python")
    func plainPythonScript() {
        let context = DetectionFixture.context(
            command: "python3 -m http.server 8000",
            executablePath: "/usr/bin/python3",
            ports: [8000]
        )

        #expect(engine.detect(context).type == .python)
    }
}
