import Foundation

public extension DetectorCatalog {
    /// PHP frameworks and the bare runtime. `containsToken("php")` matches
    /// neither `php8.3` nor `php-fpm`, since digits and `-` are word characters,
    /// so every row here gates on `ctx.isPHP` instead of the exe-name signals.
    static let php: [any ServiceDetector] = [
        RuleBasedDetector(
            type: .laravel,
            threshold: standardThreshold,
            signals: [
                // `php artisan serve` execs `php -S 127.0.0.1:8000
                // .../vendor/laravel/framework/.../server.php`, and the socket
                // belongs to that child, not to the artisan parent.
                .custom("php built-in server routed through vendor/laravel", 95, group: "command") { ctx in
                    ctx.isPHP && ctx.command.containsToken("laravel")
                },
                .treeCommandContains("artisan", 88),
                .configFile("artisan", 70),
                .anyDependency(["laravel/framework", "laravel"], 60),
                .defaultPort(8000)
            ]
        ),
        RuleBasedDetector(
            type: .symfony,
            threshold: standardThreshold,
            signals: [
                .executableNamed("symfony", 100),
                .commandContains("symfony server:start", 92),
                .treeCommandContains("symfony", 85),
                // Never symfony/console: Laravel depends on it too, for its
                // own CLI, so it cannot be Symfony-specific evidence.
                .anyDependency(["symfony/framework-bundle", "symfony/runtime"], 60),
                .defaultPorts([8000, 8001])
            ]
        ),
        RuleBasedDetector(
            type: .php,
            threshold: 40,
            signals: [
                .custom("php built-in web server (-S)", 70, group: "command") { ctx in
                    ctx.isPHP && ctx.process.arguments.contains("-S")
                },
                .custom("php process", 40, group: "command") { ctx in ctx.isPHP },
                .defaultPorts([8000, 8080]),
                .veto("an FPM pool serves a webserver, not a project directly") {
                    $0.command.contains("php-fpm")
                },
                .veto("executable runs from inside an app bundle's own tooling, not a served project") {
                    $0.executablePath.contains(".app/contents/")
                }
            ]
        )
    ]
}
