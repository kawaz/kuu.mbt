// completion.mbt — DR-117 completion_script capability seat and preset firing detection.

///|
/// Registry carrier for the script-generation capability. The script implementation belongs to the
/// UX/product layer; kuu.mbt supplies the stable capability name and dispatch connection point.
pub struct CompletionScriptCapability {}

///|
pub impl @engine.CapabilityExt for CompletionScriptCapability with fn name(
  _self,
) {
  "completion_script"
}

///|
pub fn completion_script_capability() -> &@engine.CapabilityExt {
  CompletionScriptCapability::{  } as &@engine.CapabilityExt
}

///|
/// Result of checking the completion_script orchestration seat after parsing and resolution.
pub(all) enum CompletionScriptRequest {
  Requested(String)
  NotRequested
  Unavailable
} derive(Eq, Debug)

///|
/// Confirm the capability is registered, then read the definition-wide internal cell populated by
/// the completion_script preset. Script generation itself is intentionally not invoked here.
pub fn dispatch_completion_script(
  registry : @engine.Registry,
  outcome : @engine.Outcome,
) -> CompletionScriptRequest {
  if registry.lookup_capability("completion_script") is None {
    return Unavailable
  }
  guard outcome is @engine.Success(bindings) else { return NotRequested }
  let mut requested : String? = None
  for binding in bindings {
    if binding.key == "#completion_script" && binding.op is @engine.Set {
      match binding.value {
        @engine.String(shell) => requested = Some(shell)
        _ => ()
      }
    }
  }
  match requested {
    Some(shell) => Requested(shell)
    None => NotRequested
  }
}
