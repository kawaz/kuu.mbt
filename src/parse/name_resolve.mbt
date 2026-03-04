///| 名前解決の結果
enum NameMatch {
  ExactMatch
  PrefixMatch
  NegateMatch
  NoMatch
} derive(Eq, Show, Debug)

///| 文字列がターゲットのプレフィックスかチェック（完全一致は除外）
fn is_strict_prefix(name : String, target : String) -> Bool {
  name.length() < target.length() && target.has_prefix(name)
}

///| ロングオプション名前解決
/// arg は "--" プレフィックスを除去した状態で渡される（例: "port", "no-port"）
fn resolve_long(name : String, meta : @core.OptMeta) -> NameMatch {
  // 1. meta.name と完全一致
  if name == meta.name {
    return ExactMatch
  }
  // 2. aliases の name と完全一致
  for a in meta.aliases {
    if name == a.name {
      return ExactMatch
    }
  }
  // 3. 反転パターンチェック
  match meta.inversion {
    Some(@core.FlagInversion::No) => {
      let negated = "no-" + meta.name
      if name == negated {
        return NegateMatch
      }
    }
    Some(@core.FlagInversion::EnableDisable) => {
      let enabled = "enable-" + meta.name
      let disabled = "disable-" + meta.name
      if name == enabled {
        return ExactMatch
      }
      if name == disabled {
        return NegateMatch
      }
    }
    Some(@core.FlagInversion::Custom(p1, p2)) => {
      let positive = p1 + "-" + meta.name
      let negative = p2 + "-" + meta.name
      if name == positive {
        return ExactMatch
      }
      if name == negative {
        return NegateMatch
      }
    }
    None => ()
  }
  // 4. meta.name のプレフィックスに一致
  if is_strict_prefix(name, meta.name) {
    return PrefixMatch
  }
  // 5. aliases のプレフィックスに一致
  for a in meta.aliases {
    if is_strict_prefix(name, a.name) {
      return PrefixMatch
    }
  }
  // 6. 不一致
  NoMatch
}

///| ショートオプション名前解決
fn resolve_short(ch : Char, meta : @core.OptMeta) -> Bool {
  for entry in meta.shorts {
    if ch == entry.char {
      return true
    }
  }
  false
}
