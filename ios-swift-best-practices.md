# Modern Swift iOS Best Practices

A durable reference for architecture, design patterns, testing, observability, and the rest of the engineering surface. Written against Swift 6.2 / Xcode 26, but the principles outlast any single version. Where a practice depends on a current API, that is called out.

The goal: a default set of conventions a team can adopt so that any engineer can move between codebases and find the same shapes. Treat this as a starting baseline, not a rulebook. Deviate when you have a reason and write the reason down.

---

## 1. Language and concurrency foundations

These are the bedrock decisions. Get them wrong and everything above them leaks.

1. **Adopt Swift 6 language mode and strict concurrency.** Compile-time data-race safety is the single largest correctness win available. Migrate module by module. Do not ship a codebase that mixes `-strict-concurrency=minimal` indefinitely.
2. **Default to the main actor for UI code.** Swift 6.2 lets you isolate a target to `@MainActor` by default. Use it for app and UI targets. Push work off the main actor deliberately, not accidentally.
3. **Use structured concurrency over manual threading.** `async`/`await`, `async let`, and `TaskGroup` instead of `DispatchQueue` hopping, completion handlers, or raw threads. Reserve GCD for the rare low-level case.
4. **Make types `Sendable` on purpose.** Prefer value types and immutability so `Sendable` is free. Reach for `actor` to protect mutable shared state. Use `@unchecked Sendable` only with a written invariant explaining why it is safe.
5. **Scope `Task` to a lifecycle.** Cancel tasks when the owning view or object goes away. Unstructured `Task { }` that outlives its owner is a leak and a race.
6. **Model absence with optionals, errors with typed `throws` or `Result`.** Do not use sentinel values, `NSNull`, or empty strings to mean "nothing."
7. **Prefer value semantics.** Structs and enums by default. Use classes for identity, shared mutable state, or reference-type interop. This makes concurrency and testing dramatically easier.
8. **Use enums with associated values to make illegal states unrepresentable.** A loading screen is `enum State { case idle, loading, loaded(Data), failed(Error) }`, not four loose boolean flags.

---

## 2. Architecture

The architecture's job is to keep change local. A change to one feature should not ripple across the app. Most failures here come from blurry boundaries, not from picking the wrong acronym.

### 2.1 Principles

1. **Unidirectional data flow.** State flows down, events flow up. This holds whether you use MVVM, TCA, or plain SwiftUI `@Observable` models. It makes state predictable and debuggable.
2. **Layer by responsibility.** A common, durable split:
   - **Presentation**: SwiftUI views and view models. No networking, no persistence.
   - **Domain**: use cases, business rules, entities. Pure Swift, no UIKit, no framework imports. This is the most valuable and most testable layer.
   - **Data**: repositories, network clients, persistence. Hidden behind protocols the domain owns.
3. **Depend on abstractions, not implementations.** Higher layers define protocols; lower layers conform to them. The domain never imports the networking library.
4. **One way to do each thing.** Pick one navigation approach, one networking approach, one persistence approach. Consistency beats local optimization in a 65-person org.

### 2.2 Modularization

1. **Split the app into Swift Package modules** by feature and by layer. Feature modules depend on shared infrastructure modules, never on each other directly.
2. **Enforce boundaries with the package graph.** If module A should not see module B, do not let the dependency exist. The compiler is your strongest architecture test.
3. **Keep a thin app target.** The app target wires modules together and owns the entry point. Logic lives in packages.
4. **Benefits compound at scale:** faster incremental builds, parallel team ownership, isolated tests, and previewable features without launching the whole app.

### 2.3 Dependency injection

1. **Inject dependencies; do not reach for singletons.** Constructor injection is the default. It makes dependencies explicit and tests trivial.
2. **Define dependencies as protocols** so production and test implementations are interchangeable.
3. **Avoid a service locator or global container as the primary mechanism.** It hides the dependency graph and reintroduces the singleton problem. A small composition root that assembles the graph at launch is fine.
4. **For SwiftUI, `@Environment` is a legitimate injection channel** for cross-cutting dependencies. Keep view-model construction explicit.

### 2.4 Navigation

1. **Centralize navigation state.** Use SwiftUI `NavigationStack` with a typed path, or a coordinator that owns routing decisions. Views request navigation; they do not perform it ad hoc.
2. **Make routes data.** A route is an enum or value, not a hard-coded push. This enables deep linking, restoration, and testing.

---

## 3. State management

1. **Use the Observation framework (`@Observable`) for model state.** It replaced `ObservableObject`/`@Published` for most cases and tracks only the properties a view actually reads, which reduces redundant view updates.
2. **Keep view state minimal.** `@State` for view-local ephemeral state. Source-of-truth state lives in observable models, owned one level up and passed down.
3. **Derive, do not duplicate.** Computed properties over stored copies. Duplicated state is the most common source of UI bugs.
4. **Make state transitions explicit.** A reducer or a small set of methods on the model that move it between known states. Avoid scattering mutations across the view body.

---

## 4. UI

1. **SwiftUI first.** Default to SwiftUI for new screens. Drop to UIKit/`UIViewRepresentable` for capabilities SwiftUI lacks or for performance-critical, highly custom surfaces. Wrap UIKit so the seam is contained.
2. **Compose small views.** Many small, focused views over one large body. Extract subviews when a body exceeds roughly one screen or takes more than a couple of parameters.
3. **Keep views dumb.** Views render state and emit events. Formatting, branching, and side effects belong in the view model or domain.
4. **Drive previews from injected, deterministic state.** Every nontrivial view ships with previews covering empty, loaded, error, and edge-case states. Previews are documentation and a fast feedback loop.
5. **Design for dynamic type, dark mode, and RTL from the start.** Retrofitting these later costs far more.

---

## 5. Design patterns

The standard patterns still apply, but Swift's protocols, generics, value types, and closures make several of them lighter than their classic object-oriented form. Use the pattern, not the ceremony.

### 5.1 Patterns you will use constantly

1. **Protocol-oriented abstraction.** Define behavior as protocols; provide shared behavior in protocol extensions. This is Swift's substitute for deep class hierarchies. Prefer composition of small protocols over inheritance.
2. **Dependency injection** (see 2.3). The most important pattern in the codebase for testability.
3. **Repository.** A protocol that abstracts data access. The domain asks the repository for entities and does not know if they came from network, cache, or disk.
4. **Factory.** Centralize construction of objects whose creation is nontrivial or varies by environment. In Swift this is often a function or static method, not a `Factory` class.
5. **Coordinator / Router.** Owns navigation flow and keeps view models free of routing knowledge.
6. **Adapter.** Wrap a third-party SDK or legacy API behind a protocol you control, so you can swap or mock it. Apply this to every external SDK by default.
7. **Facade.** Present a simple interface over a complex subsystem (for example, a single `SyncService` over several lower-level clients).
8. **Strategy.** Inject behavior as a protocol or closure so an algorithm can vary. Swift closures make this nearly free.
9. **Observer.** Now mostly served by the Observation framework, Combine, or `AsyncSequence` rather than a hand-rolled observer list.
10. **Decorator.** Wrap a conforming type to add behavior (logging, caching, retry) without touching the original. Clean fit for protocol-based services.

### 5.2 Swift-idiomatic patterns

1. **Result builders** for declarative DSLs (SwiftUI itself, custom builders for things like form or query construction).
2. **Property wrappers** for cross-cutting field behavior (`@AppStorage`, custom validation, clamping). Use sparingly; they hide control flow.
3. **Phantom types and generics** to encode invariants in the type system (for example, typed identifiers `Identifier<User>` so a user ID cannot be passed where an order ID is expected).
4. **`Result` and typed throws** for explicit, exhaustive error handling at boundaries.

### 5.3 Anti-patterns to reject

1. **Massive view model / massive view controller.** A view model over a few hundred lines is a smell. Split by responsibility.
2. **Singletons as the default sharing mechanism.** They hide dependencies and wreck tests. Reserve for genuinely global, stateless, or platform-mandated cases.
3. **Stringly-typed code.** Notification names, dictionary keys, and route strings as raw strings. Use enums and typed values.
4. **God objects and manager classes** that accumulate unrelated responsibilities.

---

## 6. Networking and data

1. **Wrap the network behind a client protocol.** Endpoints are typed values; the client turns them into requests. No `URLSession` calls scattered through view models.
2. **Use `async`/`await` with `URLSession`.** Model endpoints as values, decode with `Codable`, and centralize headers, auth, and retry.
3. **Make decoding total and defensive.** Validate at the boundary. Map transport errors, decoding errors, and domain errors into distinct, typed cases.
4. **Cache deliberately.** Decide per resource: in-memory, on-disk, or none. Define invalidation rules. Caching without an invalidation strategy is a bug generator.
5. **Treat the network as unreliable by default.** Timeouts, retries with backoff, and offline behavior are part of the design, not an afterthought, especially for field and mobile use.

---

## 7. Persistence

1. **Pick one local store and standardize.** SwiftData for new SwiftUI-centric apps; Core Data where you need its maturity, migration control, or existing investment. Do not mix without a reason.
2. **Hide the store behind a repository.** The domain works with entities, not `NSManagedObject` or `@Model` types directly. This keeps persistence swappable and testable.
3. **Plan migrations from day one.** Versioned schemas, tested migration paths, and a rollback story. Data-loss bugs are the least forgivable.
4. **Use the right tool for the data.** Keychain for secrets, `UserDefaults`/`@AppStorage` for small preferences, the database for structured data, the file system for blobs. Do not store secrets in `UserDefaults`.
5. **For offline-first apps, treat the local store as the source of truth** and sync against it. Define conflict resolution explicitly.

---

## 8. Error handling

1. **Define domain error types.** Each layer has its own error enum. Map errors as they cross layer boundaries rather than leaking low-level errors to the UI.
2. **Errors carry enough context to act on.** Include what failed and what the user or caller can do next.
3. **Fail loudly in development, gracefully in production.** Use `assert`/`precondition` for programmer errors and recoverable handling for user-facing errors.
4. **Never silently swallow errors.** An empty `catch` is a future incident. At minimum, log it.
5. **Separate recoverable from unrecoverable.** Reserve `fatalError` for truly impossible states, and document why it is impossible.

---

## 9. Testing

The point of tests is confidence to change code quickly. Optimize for fast, deterministic, behavior-focused tests, not coverage as a number.

### 9.1 Framework and structure

1. **Use Swift Testing for new tests.** The `@Test` / `#expect` / `#require` model is the current standard, with parameterized tests and better failure output. Keep XCTest where it already exists or where Swift Testing has gaps (notably some UI testing).
2. **Follow the test pyramid.** Many fast unit tests, fewer integration tests, a small number of end-to-end UI tests. Inverting this gives slow, flaky suites.
3. **Name tests by behavior.** The name states the scenario and expected outcome, not the method under test.
4. **Arrange-Act-Assert.** One logical behavior per test. Multiple assertions are fine if they describe one outcome.

### 9.2 Practices

1. **Design for testability through injection.** If a unit is hard to test, the design is usually the problem. Fix the seam, not the test.
2. **Mock at protocol boundaries you own.** Provide fake implementations of your repository and client protocols. Do not mock Apple's frameworks directly; wrap them first.
3. **Keep tests deterministic.** Inject clocks, dates, randomness, and schedulers. No real network, no real time, no sleeps. Use the `Clock` API and controllable schedulers.
4. **Test the domain layer hardest.** It holds the rules, is pure Swift, and tests there are fast and stable.
5. **Use snapshot tests for UI regressions** with care: pin device, OS, and locale, and review diffs. They catch visual breakage cheaply but go stale if unmanaged.
6. **Reserve UI/E2E tests for critical user journeys.** Login, checkout, core flows. They are valuable but slow and flaky; keep the set small and stable.
7. **Use fixtures and builders** for test data so setup is readable and intent is clear.
8. **Treat flaky tests as bugs.** Quarantine, then fix or delete. A flaky suite that no one trusts is worse than a smaller reliable one.

---

## 10. Observability

You cannot fix what you cannot see. Build observability in from the start; it is far harder to retrofit. Three pillars: logs, metrics, traces, plus crash and diagnostics.

### 10.1 Logging

1. **Use the unified logging system (`Logger` / OSLog).** It is structured, performant, and integrated with Console and Instruments. Do not ship `print`.
2. **Use a subsystem and category per module** so logs are filterable and attributable.
3. **Set privacy levels explicitly.** Mark dynamic values `.public` or `.private` deliberately. Default to private for anything that could be user data. This is both a privacy and a compliance requirement.
4. **Log at the right level.** Debug for development detail, info for normal flow, error and fault for problems. Avoid noisy logging that buries signal.
5. **Log decisions and state transitions, not just entry/exit.** The useful question in an incident is "why did it do that," not "did it run."

### 10.2 Metrics and performance signals

1. **Adopt MetricKit** to receive aggregated power, performance, launch-time, hang-rate, and disk-write metrics from the field.
2. **Use `os_signpost` / Instruments** to measure critical paths (launch, scroll, sync). Measure before optimizing.
3. **Track a small set of product-level health metrics** that map to user experience: crash-free rate, ANR/hang rate, cold start time, key flow latency. Pick the few that matter and watch them.

### 10.3 Crash and diagnostics

1. **Ship a crash and error reporting pipeline.** Symbolicated crashes with breadcrumbs leading to them. Tie crash-free sessions to releases.
2. **Capture breadcrumbs**: recent navigation, key events, and non-fatal errors, so a crash report tells a story.
3. **Watch non-fatals too.** Handled errors at scale reveal degraded experiences that never crash.

### 10.4 Distributed tracing and correlation

1. **Propagate a correlation/request ID** from client through backend so a single user action is traceable end to end.
2. **For server-side or cross-service Swift, use swift-distributed-tracing** to integrate with standard backends.

### 10.5 Privacy discipline

1. **Never log PII, tokens, or secrets.** Enforce with log privacy levels and review. A leaked log is a breach.
2. **Maintain the privacy manifest** and declare data collection accurately. Required-reason APIs must be justified.

---

## 11. Performance

1. **Measure first.** Use Instruments (Time Profiler, Allocations, Hangs). Optimize against data, not intuition.
2. **Protect the main thread.** No blocking work on it. Hangs and dropped frames come from main-thread contention.
3. **Watch memory and retain cycles.** Use `weak`/`unowned` in closures and delegates deliberately. Profile for leaks; do not guess.
4. **Optimize launch time.** Defer non-critical work past first frame. Audit static initializers and heavy dependency graphs at startup.
5. **Handle images responsibly.** Downsample to display size, cache decoded images, and avoid decoding on the main thread. Images are a top memory and scroll-jank source.
6. **Make lists efficient.** Lazy containers, stable identity, and minimal per-row work.

---

## 12. Security and privacy

1. **Store secrets in the Keychain** with appropriate accessibility. Never in `UserDefaults`, plist, or source.
2. **Keep App Transport Security on.** TLS everywhere. Justify and scope any exception.
3. **Apply file data protection** for sensitive at-rest data.
4. **Never hard-code credentials, API keys, or tokens** in the binary. Inject at build or fetch at runtime.
5. **Maintain privacy manifests and minimize data collection.** Collect what you need, declare what you collect.
6. **Validate all input crossing a trust boundary**, including deep links and URL schemes.

---

## 13. Accessibility

1. **Treat accessibility as a baseline requirement**, not a feature. Label controls, group elements meaningfully, and support VoiceOver.
2. **Support Dynamic Type** with scalable text and layouts that reflow.
3. **Meet contrast and target-size guidance.** Respect reduce-motion and reduce-transparency settings.
4. **Test with VoiceOver and large text** on real flows. SwiftUI gives a lot for free; verify rather than assume.

---

## 14. Code quality and conventions

1. **Follow the Swift API Design Guidelines.** Clarity at the point of use. Name for readability, not brevity.
2. **Automate formatting and linting.** SwiftFormat and SwiftLint in CI, enforced, not advisory. Consistency removes a class of review friction.
3. **Keep functions and types small and single-purpose.** Extract when responsibilities multiply.
4. **Prefer immutability.** `let` by default, `var` only when needed.
5. **Document the why, not the what.** Code shows what it does; comments explain decisions, trade-offs, and non-obvious constraints. Use DocC for public module interfaces.
6. **Make the public surface of a module deliberate.** Default to `internal`; expose `public` only what consumers need. A small public API is easier to evolve.

---

## 15. Dependencies and build

1. **Use Swift Package Manager** as the default dependency and module tool.
2. **Minimize and vet third-party dependencies.** Every dependency is a maintenance, security, and binary-size liability. Prefer the platform. Wrap the ones you keep behind your own protocols (see Adapter, 5.1).
3. **Pin versions and review updates.** Audit transitive dependencies. A surprise transitive dependency is a supply-chain risk.
4. **Keep build configuration in code and version control.** Reproducible builds. No machine-specific setup steps living only in someone's head.

---

## 16. CI/CD and release

1. **Run build, lint, and the fast test suite on every PR.** Block merge on failure. The pipeline is the quality gate.
2. **Automate the release pipeline** (signing, build, distribution). Manual release steps are where mistakes ship.
3. **Roll out in phases.** Use staged/phased release so a regression reaches a fraction of users before everyone.
4. **Gate risky changes behind feature flags** so you can disable without a new build.
5. **Tie observability to releases.** Watch crash-free rate and key metrics per version, and define rollback criteria before you ship.

---

## How to use this

1. Adopt the foundations (sections 1 to 3) first. They constrain everything else.
2. Encode the conventions you agree on into linters, templates, and module boundaries so they are enforced by tooling, not by review memory.
3. Revisit yearly against the current Swift and Xcode release. The principles are durable; the specific APIs (Observation, Swift Testing, approachable concurrency) are the current expression of them and will keep moving.
4. When you deviate, write down why. The reasons are more valuable than the rules.
