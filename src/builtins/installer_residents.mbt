// installer_residents.mbt — canonical builtin installer residents.

///|
priv struct LongInstaller {}

///|
impl @engine.InstallerExt for LongInstaller with fn vocab(_self) {
  ["long"]
}

///|
impl @engine.InstallerExt for LongInstaller with fn apply(_self, builder) {
  inst_long(builder.definition(), builder.output(), builder.templates())
}

///|
impl @engine.InstallerExt for LongInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn long_installer() -> &@engine.InstallerExt {
  LongInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct ShortInstaller {}

///|
impl @engine.InstallerExt for ShortInstaller with fn vocab(_self) {
  ["short"]
}

///|
impl @engine.InstallerExt for ShortInstaller with fn apply(_self, builder) {
  inst_short(builder.definition(), builder.output())
}

///|
impl @engine.InstallerExt for ShortInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn short_installer() -> &@engine.InstallerExt {
  ShortInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct EnvInstaller {}

///|
impl @engine.InstallerExt for EnvInstaller with fn vocab(_self) {
  ["env"]
}

///|
impl @engine.InstallerExt for EnvInstaller with fn apply(_self, builder) {
  inst_env(builder.definition(), builder.output())
}

///|
impl @engine.InstallerExt for EnvInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn env_installer() -> &@engine.InstallerExt {
  EnvInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct DdInstaller {}

///|
impl @engine.InstallerExt for DdInstaller with fn vocab(_self) {
  ["dd"]
}

///|
impl @engine.InstallerExt for DdInstaller with fn apply(_self, builder) {
  inst_dd(builder.definition(), builder.output())
}

///|
impl @engine.InstallerExt for DdInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn dd_installer() -> &@engine.InstallerExt {
  DdInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct CommandInstaller {}

///|
impl @engine.InstallerExt for CommandInstaller with fn vocab(_self) {
  ["command"]
}

///|
impl @engine.InstallerExt for CommandInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @engine.InstallerExt for CommandInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn command_installer() -> &@engine.InstallerExt {
  CommandInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct GlobalInstaller {}

///|
impl @engine.InstallerExt for GlobalInstaller with fn vocab(_self) {
  ["global"]
}

///|
impl @engine.InstallerExt for GlobalInstaller with fn apply(_self, builder) {
  inst_global(builder)
}

///|
impl @engine.InstallerExt for GlobalInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn global_installer() -> &@engine.InstallerExt {
  GlobalInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct InheritInstaller {}

///|
impl @engine.InstallerExt for InheritInstaller with fn vocab(_self) {
  ["inherit"]
}

///|
impl @engine.InstallerExt for InheritInstaller with fn apply(_self, builder) {
  inst_inherit(builder.definition(), builder.output())
}

///|
impl @engine.InstallerExt for InheritInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn inherit_installer() -> &@engine.InstallerExt {
  InheritInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct RepeatInstaller {}

///|
impl @engine.InstallerExt for RepeatInstaller with fn vocab(_self) {
  ["repeat"]
}

///|
impl @engine.InstallerExt for RepeatInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @engine.InstallerExt for RepeatInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn repeat_installer() -> &@engine.InstallerExt {
  RepeatInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct MultipleInstaller {}

///|
impl @engine.InstallerExt for MultipleInstaller with fn vocab(_self) {
  ["multiple"]
}

///|
impl @engine.InstallerExt for MultipleInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @engine.InstallerExt for MultipleInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn multiple_installer() -> &@engine.InstallerExt {
  MultipleInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct ConfigInstaller {}

///|
impl @engine.InstallerExt for ConfigInstaller with fn vocab(_self) {
  ["config"]
}

///|
impl @engine.InstallerExt for ConfigInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @engine.InstallerExt for ConfigInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn config_installer() -> &@engine.InstallerExt {
  ConfigInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct ConstraintInstaller {}

///|
impl @engine.InstallerExt for ConstraintInstaller with fn vocab(_self) {
  ["constraint"]
}

///|
impl @engine.InstallerExt for ConstraintInstaller with fn apply(_self, builder) {
  inst_constraint(builder.definition(), builder.output(), builder.templates())
}

///|
impl @engine.InstallerExt for ConstraintInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn constraint_installer() -> &@engine.InstallerExt {
  ConstraintInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct AliasInstaller {}

///|
impl @engine.InstallerExt for AliasInstaller with fn vocab(_self) {
  ["alias"]
}

///|
impl @engine.InstallerExt for AliasInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @engine.InstallerExt for AliasInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn alias_installer() -> &@engine.InstallerExt {
  AliasInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct InheritableInstaller {}

///|
impl @engine.InstallerExt for InheritableInstaller with fn vocab(_self) {
  ["inheritable"]
}

///|
impl @engine.InstallerExt for InheritableInstaller with fn apply(_self, builder) {
  inst_inheritable(builder)
}

///|
impl @engine.InstallerExt for InheritableInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn inheritable_installer() -> &@engine.InstallerExt {
  InheritableInstaller::{  } as &@engine.InstallerExt
}

///|
pub fn install_installers(registry : @engine.Registry) -> Unit {
  registry.register_installer(long_installer())
  registry.register_installer(short_installer())
  registry.register_installer(env_installer())
  registry.register_installer(dd_installer())
  registry.register_installer(command_installer())
  registry.register_installer(global_installer())
  registry.register_installer(inherit_installer())
  registry.register_installer(repeat_installer())
  registry.register_installer(multiple_installer())
  registry.register_installer(config_installer())
  registry.register_installer(constraint_installer())
  registry.register_installer(alias_installer())
  registry.register_installer(inheritable_installer())
}
