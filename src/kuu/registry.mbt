// registry.mbt — canonical kuu assembly of engine extension residents.

///|
fn canonical_registry() -> @engine.Registry {
  let registry = @engine.Registry::new()
  @builtins.install(registry)
  registry
}
