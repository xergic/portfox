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

    @Test("gunicorn serving a Django project reports Django, not the server")
    func gunicornUnderDjango() {
        // Django 60 (its gunicorn custom signal) + 60 (dependency) = 120, against
        // gunicorn's 100 (exe name) + 10 (port) = 110.
        let context = DetectionFixture.context(
            argv: ["gunicorn:", "master", "[shop.wsgi]"],
            executablePath: "/proj/.venv/bin/gunicorn",
            dependencies: ["django", "gunicorn"],
            ports: [8000]
        )
        let type = engine.detect(context).type

        #expect(type == .django)
        #expect(type != .gunicorn)
    }

    @Test("gunicorn with no framework behind it reports gunicorn")
    func bareGunicorn() {
        let context = DetectionFixture.context(
            argv: ["gunicorn:", "master", "[app.wsgi]"],
            executablePath: "/proj/.venv/bin/gunicorn",
            dependencies: ["gunicorn"],
            ports: [8000]
        )

        #expect(engine.detect(context).type == .gunicorn)
    }

    @Test("uvicorn serving FastAPI still reports FastAPI")
    func uvicornUnderFastAPIDoesNotRegress() {
        let context = DetectionFixture.context(
            command: "uvicorn app.main:app --port 8000",
            executablePath: "/proj/.venv/bin/uvicorn",
            dependencies: ["fastapi", "uvicorn"],
            ports: [8000]
        )

        #expect(engine.detect(context).type == .fastAPI)
    }

    @Test("streamlit run is Streamlit")
    func streamlitRun() {
        let context = DetectionFixture.context(
            command: "/proj/.venv/bin/streamlit run dashboard.py",
            executablePath: "/proj/.venv/bin/python3",
            dependencies: ["streamlit"],
            ports: [8501]
        )

        #expect(engine.detect(context).type == .streamlit)
    }

    @Test("jupyter-lab is Jupyter, not generic python")
    func jupyterLab() {
        let context = DetectionFixture.context(
            command: "/proj/.venv/bin/jupyter-lab --port 8888",
            executablePath: "/proj/.venv/bin/jupyter-lab",
            ports: [8888]
        )
        let type = engine.detect(context).type

        #expect(type == .jupyter)
        #expect(type != .python)
    }
}
