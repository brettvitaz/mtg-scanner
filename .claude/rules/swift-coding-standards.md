---
paths:
  - "apps/ios/**/*.swift"
---

# Swift Coding Standards

## Type design
- `final class` by default for view models, services, and non-inherited types.
- Conform models to `Codable` for JSON serialization and `Identifiable` for list rendering.
- Use `enum` for finite state (detection modes, provider types) with raw values where practical.

## Safety
- No force unwraps (`!`) in production code. Use `guard let` or `if let`.
- Force unwraps are acceptable in test code for brevity.
- `[weak self]` in closures captured by long-lived objects to prevent retain cycles.
- Check for retain cycles in any closure stored as a property.

## Concurrency
- `@MainActor` on all UI-bound classes (view models, app model).
- Camera and Vision work runs on dedicated serial `DispatchQueue`s, never the main thread.
- Bridge background → main with `Task { @MainActor in }` or `DispatchQueue.main.async`.
- Never hold more than 1 Vision request in flight — use a boolean flag to skip frames.
- `CATransaction.setDisableActions(true)` when updating overlay layer paths.

## Naming
- Follow Swift API Design Guidelines.
- Descriptive names over comments. If a function needs a comment, rename it.
- Use MARK comments (`// MARK: - Section`) to organize class members.

## Structure
- Functions < 30 lines where practical, < 50 max.
- Nesting depth ≤ 3 levels. Extract early returns with `guard`.
- Prefer flat control flow over deep nesting.
- Imports: framework imports at top, sorted alphabetically.

## SwiftUI patterns
- `@StateObject` for owned state, `@ObservedObject` for injected state.
- `@EnvironmentObject` for app-wide dependencies.
- Keep views thin — logic belongs in view models.
- Use `UIViewControllerRepresentable` for AVFoundation/UIKit camera integration.
