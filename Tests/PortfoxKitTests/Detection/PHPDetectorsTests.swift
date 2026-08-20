import Foundation
import Testing
@testable import PortfoxKit

@Suite("PHP detectors")
struct PHPDetectorsTests {
    private let engine = DetectionEngine(
        detectors: DetectorCatalog.php + DetectorCatalog.python + DetectorCatalog.nodeEcosystem
    )

    @Test("artisan serve's child, the built-in server routed through vendor/laravel, is Laravel")
    func artisanServeChildIsLaravel() {
        let context = DetectionFixture.context(
            command: "php -S 127.0.0.1:8000 /proj/vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php",
            executablePath: "/opt/homebrew/bin/php8.3",
            ports: [8000]
        )

        #expect(engine.detect(context).type == .laravel)
    }

    @Test("an artisan ancestor in the process tree identifies Laravel even off the plain built-in server command")
    func artisanAncestorIsLaravel() {
        let context = DetectionFixture.context(
            command: "php -S 127.0.0.1:8000 /proj/public/index.php",
            executablePath: "/opt/homebrew/bin/php8.3",
            projectFiles: ["artisan"],
            ports: [8000],
            relatedCommands: ["php artisan serve"]
        )

        #expect(engine.detect(context).type == .laravel)
    }

    @Test("a version-suffixed php binary with no framework evidence is generic php, not swallowed by containsToken")
    func versionedPHPWithNoFrameworkIsGenericPHP() {
        // isPHP is the only thing that can see this executable: containsToken("php")
        // does not match "php8.3", since a digit is a word character.
        let context = DetectionFixture.context(
            command: "php8.3 -S localhost:8000 -t public",
            executablePath: "/opt/homebrew/bin/php8.3",
            ports: [8000]
        )

        #expect(engine.detect(context).type == .php)
    }

    @Test("an FPM pool is not reported as the php dev server")
    func fpmPoolIsNotPHP() {
        let context = DetectionFixture.context(
            command: "php-fpm: master process (/opt/homebrew/etc/php/8.3/php-fpm.conf)",
            executablePath: "/opt/homebrew/sbin/php-fpm",
            ports: [9000]
        )

        #expect(engine.detect(context).type != .php)
    }

    @Test("symfony server:start, a Go binary literally named symfony, is Symfony")
    func symfonyServerStartIsSymfony() {
        let context = DetectionFixture.context(
            command: "symfony server:start",
            executablePath: "/opt/homebrew/bin/symfony",
            ports: [8000]
        )

        #expect(engine.detect(context).type == .symfony)
    }

    @Test("a Laravel project that also depends on symfony/console stays Laravel")
    func laravelWithSymfonyConsoleDependencyStaysLaravel() {
        // symfony/console is a Laravel dependency too, for its own CLI, so it must
        // never be enough evidence to pull this toward Symfony.
        let context = DetectionFixture.context(
            command: "php -S 127.0.0.1:8000 /proj/vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php",
            executablePath: "/opt/homebrew/bin/php8.3",
            dependencies: ["laravel/framework", "symfony/console"],
            ports: [8000]
        )

        let result = engine.detect(context)
        #expect(result.type == .laravel)
        #expect(result.type != .symfony)
    }

    @Test("Django's manage.py runserver is Django, not Laravel or php")
    func djangoRunserverIsNeitherLaravelNorPHP() {
        let context = DetectionFixture.context(
            command: "python manage.py runserver 0.0.0.0:8000",
            executablePath: "/usr/bin/python",
            projectFiles: ["manage.py"],
            dependencies: ["django"],
            ports: [8000]
        )

        let result = engine.detect(context)
        #expect(result.type == .django)
        #expect(result.type != .laravel)
        #expect(result.type != .php)
    }

    @Test("a Node server in a directory named laravel-notes is not Laravel")
    func laravelNamedDirectoryIsNotEvidence() {
        let context = DetectionFixture.context(
            command: "node /Users/me/Code/laravel-notes/server.js",
            executablePath: "/usr/local/bin/node",
            ports: [8000]
        )

        #expect(engine.detect(context).type == .node)
    }
}
