// accumulator_residents.mbt — canonical accumulator and collector residents.

///|
fn append_resolve_cli(
  name : String,
  cli : Array[@engine.Binding],
  include_default : Bool,
  lower : @engine.LowerSeat,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
  let resolved : Array[@engine.Binding] = []
  let mut committed = false
  for binding in cli {
    if binding.key == name {
      match binding.op {
        @engine.Invoke(_) =>
          abort(
            "unreachable: accumulated cells reject update operations at definition time",
          )
        @engine.Remove | @engine.Splice =>
          abort(
            "unreachable: remove and splice pieces belong to the merge accumulator",
          )
        @engine.Default =>
          match lower(true) {
            Ok(defaults) => {
              resolved.push({ ..binding, source: @engine.Cli })
              for default in defaults {
                resolved.push({
                  ..default,
                  op: @engine.Set,
                  source: @engine.Cli,
                })
              }
              committed = true
            }
            Err(error) => return Err(error)
          }
        @engine.Unset => {
          resolved.push(binding)
          committed = false
        }
        @engine.Empty | @engine.Set => {
          resolved.push(binding)
          committed = true
        }
      }
    }
  }
  if committed {
    Ok(resolved)
  } else {
    lower(include_default)
  }
}

///|
priv struct AppendAccumulator {}

///|
impl @engine.AccumulatorExt for AppendAccumulator with fn kind(_self) {
  "append"
}

///|
impl @engine.AccumulatorExt for AppendAccumulator with fn encode(_self) {
  ().to_json()
}

///|
impl @engine.AccumulatorExt for AppendAccumulator with fn resolve_cli(
  _self,
  name,
  cli,
  include_default,
  lower,
) {
  append_resolve_cli(name, cli, include_default, lower)
}

///|
impl @engine.AccumulatorExt for AppendAccumulator with fn collect(_self, values) {
  let out : Array[@engine.RVal] = []
  for value in values {
    out.push(@engine.Scalar(value))
  }
  @engine.Array(out)
}

///|
pub fn append_accumulator() -> &@engine.AccumulatorExt {
  AppendAccumulator::{  } as &@engine.AccumulatorExt
}

///|
priv enum MergeGroup {
  Cell(@engine.Binding)
  Fire(Array[@engine.Binding])
}

///|
priv enum MergeMark {
  MAdd(@engine.Value)
  MRemove(@engine.Value)
  MSplice
}

///|
fn value_contains(
  values : Array[@engine.Value],
  target : @engine.Value,
) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}

///|
fn merge_pieces_has_no_marker(marks : Array[MergeMark]) -> Bool {
  for mark in marks {
    match mark {
      MAdd(_) => ()
      _ => return false
    }
  }
  true
}

///|
fn merge_pieces_with_implicit_splice(
  marks : Array[MergeMark],
) -> Array[MergeMark] {
  for mark in marks {
    if mark is MSplice {
      return marks
    }
  }
  let out : Array[MergeMark] = [MSplice]
  for mark in marks {
    out.push(mark)
  }
  out
}

///|
fn eval_merge_pieces(
  marks : Array[MergeMark],
  old : Array[@engine.Value],
) -> Array[@engine.Value] {
  let values : Array[@engine.Value] = []
  let removed : Array[@engine.Value] = []
  for mark in marks {
    match mark {
      MAdd(value) => values.push(value)
      MRemove(value) => {
        if !value_contains(removed, value) {
          removed.push(value)
        }
        let kept : Array[@engine.Value] = []
        for current in values {
          if current != value {
            kept.push(current)
          }
        }
        values.clear()
        for current in kept {
          values.push(current)
        }
      }
      MSplice =>
        for value in old {
          if !value_contains(removed, value) {
            values.push(value)
          }
        }
    }
  }
  values
}

///|
fn merge_resolve_cli(
  name : String,
  cli : Array[@engine.Binding],
  include_default : Bool,
  lower : @engine.LowerSeat,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
  let groups : Array[MergeGroup] = []
  let mut fire : Array[@engine.Binding] = []
  let mut fire_pos : Int? = None
  for binding in cli {
    if binding.key == name {
      match binding.op {
        @engine.Set | @engine.Remove | @engine.Splice => {
          if fire.length() > 0 && fire_pos != binding.at_pos {
            groups.push(Fire(fire))
            fire = []
          }
          fire_pos = binding.at_pos
          fire.push(binding)
        }
        @engine.Invoke(_) | @engine.Default | @engine.Unset | @engine.Empty => {
          if fire.length() > 0 {
            groups.push(Fire(fire))
            fire = []
            fire_pos = None
          }
          groups.push(Cell(binding))
        }
      }
    }
  }
  if fire.length() > 0 {
    groups.push(Fire(fire))
  }

  let mut result : Array[@engine.Binding] = []
  let mut committed = false
  let mut old_values : Array[@engine.Value]? = None
  for group in groups {
    match group {
      Cell(binding) =>
        match binding.op {
          @engine.Invoke(_) =>
            abort(
              "unreachable: accumulated cells reject update operations at definition time",
            )
          @engine.Default =>
            match lower(true) {
              Ok(defaults) => {
                let next : Array[@engine.Binding] = [
                  { ..binding, source: @engine.Cli },
                ]
                let values : Array[@engine.Value] = []
                for default in defaults {
                  next.push({ ..default, op: @engine.Set, source: @engine.Cli })
                  values.push(default.value)
                }
                result = next
                old_values = Some(values)
                committed = true
              }
              Err(error) => return Err(error)
            }
          @engine.Unset => {
            result = [binding]
            old_values = None
            committed = false
          }
          @engine.Empty => {
            result = [binding]
            old_values = Some([])
            committed = true
          }
          @engine.Set | @engine.Remove | @engine.Splice =>
            abort("unreachable: merge cell operations are grouped as a firing")
        }
      Fire(pieces) => {
        let marks : Array[MergeMark] = []
        for piece in pieces {
          match piece.op {
            @engine.Set => marks.push(MAdd(piece.value))
            @engine.Remove => marks.push(MRemove(piece.value))
            @engine.Splice => marks.push(MSplice)
            _ =>
              abort("unreachable: merge firing contains only set/remove/splice")
          }
        }
        if merge_pieces_has_no_marker(marks) {
          let values : Array[@engine.Value] = []
          for piece in pieces {
            values.push(piece.value)
          }
          result = pieces
          old_values = Some(values)
          committed = true
        } else {
          let old = match old_values {
            Some(values) => values
            None =>
              match lower(true) {
                Ok(bindings) => {
                  let values : Array[@engine.Value] = []
                  for binding in bindings {
                    values.push(binding.value)
                  }
                  values
                }
                Err(error) => return Err(error)
              }
          }
          let values = eval_merge_pieces(
            merge_pieces_with_implicit_splice(marks),
            old,
          )
          let next : Array[@engine.Binding] = []
          for value in values {
            next.push(@engine.Binding::new(name, value, @engine.Cli))
          }
          result = next
          old_values = Some(values)
          committed = true
        }
      }
    }
  }
  if committed {
    Ok(result)
  } else {
    lower(include_default)
  }
}

///|
priv struct MergeAccumulator {}

///|
impl @engine.AccumulatorExt for MergeAccumulator with fn kind(_self) {
  "merge"
}

///|
impl @engine.AccumulatorExt for MergeAccumulator with fn encode(_self) {
  ().to_json()
}

///|
impl @engine.AccumulatorExt for MergeAccumulator with fn resolve_cli(
  _self,
  name,
  cli,
  include_default,
  lower,
) {
  merge_resolve_cli(name, cli, include_default, lower)
}

///|
impl @engine.AccumulatorExt for MergeAccumulator with fn collect(_self, values) {
  let out : Array[@engine.RVal] = []
  for value in values {
    out.push(@engine.Scalar(value))
  }
  @engine.Array(out)
}

///|
pub fn merge_accumulator() -> &@engine.AccumulatorExt {
  MergeAccumulator::{  } as &@engine.AccumulatorExt
}

///|
fn split_first_eq(value : String) -> (String, String) {
  let mut key = ""
  let mut rest = ""
  let mut found = false
  for char in value {
    if found {
      rest = rest + char.to_string()
    } else if char == '=' {
      found = true
    } else {
      key = key + char.to_string()
    }
  }
  (key, rest)
}

///|
priv struct KvMapAccumulator {}

///|
impl @engine.AccumulatorExt for KvMapAccumulator with fn kind(_self) {
  "kv_map"
}

///|
impl @engine.AccumulatorExt for KvMapAccumulator with fn encode(_self) {
  ().to_json()
}

///|
impl @engine.AccumulatorExt for KvMapAccumulator with fn resolve_cli(
  _self,
  name,
  cli,
  include_default,
  lower,
) {
  append_resolve_cli(name, cli, include_default, lower)
}

///|
impl @engine.AccumulatorExt for KvMapAccumulator with fn collect(_self, values) {
  let fields : Array[(String, @engine.RVal)] = []
  let seen : Map[String, Int] = Map([])
  for value in values {
    let raw = match value {
      @engine.String(text) => text
      _ => ""
    }
    let (key, rest) = split_first_eq(raw)
    match seen.get(key) {
      Some(index) => fields[index] = (key, @engine.Scalar(@engine.String(rest)))
      None => {
        seen.set(key, fields.length())
        fields.push((key, @engine.Scalar(@engine.String(rest))))
      }
    }
  }
  @engine.Object(fields)
}

///|
pub fn kv_map_accumulator() -> &@engine.AccumulatorExt {
  KvMapAccumulator::{  } as &@engine.AccumulatorExt
}

///|
fn unwrap_single(value : @engine.RVal) -> @engine.RVal {
  match value {
    @engine.Scalar(value) => @engine.Scalar(value)
    @engine.Array(values) =>
      if values.length() == 1 {
        unwrap_single(values[0])
      } else {
        let out : Array[@engine.RVal] = []
        for value in values {
          out.push(unwrap_single(value))
        }
        @engine.Array(out)
      }
    @engine.Object(fields) => {
      let out : Array[(String, @engine.RVal)] = []
      for field in fields {
        out.push((field.0, unwrap_single(field.1)))
      }
      @engine.Object(out)
    }
  }
}

///|
priv struct UnwrapSingleCollector {}

///|
impl @engine.CollectorExt for UnwrapSingleCollector with fn kind(_self) {
  "unwrap_single"
}

///|
impl @engine.CollectorExt for UnwrapSingleCollector with fn encode(_self) {
  ().to_json()
}

///|
impl @engine.CollectorExt for UnwrapSingleCollector with fn collect(
  _self,
  value,
) {
  unwrap_single(value)
}

///|
pub fn unwrap_single_collector() -> &@engine.CollectorExt {
  UnwrapSingleCollector::{  } as &@engine.CollectorExt
}

///|
pub(all) enum FromEntriesSpec {
  Entries
  KeyValue(String, String)
  KeyPromote(String)
} derive(Eq, Debug)

///|
fn result_key(value : @engine.RVal) -> String {
  match value {
    @engine.Scalar(value) => @engine.value_str(value)
    _ => "?"
  }
}

///|
fn result_field(value : @engine.RVal, name : String) -> @engine.RVal? {
  match value {
    @engine.Object(fields) => {
      for field in fields {
        if field.0 == name {
          return Some(field.1)
        }
      }
      None
    }
    _ => None
  }
}

///|
fn all_pairs(values : Array[@engine.RVal]) -> Bool {
  if values.length() == 0 {
    return false
  }
  for value in values {
    match value {
      @engine.Array(items) => if items.length() != 2 { return false }
      _ => return false
    }
  }
  true
}

///|
fn all_have_fields(
  values : Array[@engine.RVal],
  fields : Array[String],
) -> Bool {
  if values.length() == 0 {
    return false
  }
  for value in values {
    for field in fields {
      if result_field(value, field) is None {
        return false
      }
    }
  }
  true
}

///|
fn from_entries(value : @engine.RVal, spec : FromEntriesSpec) -> @engine.RVal {
  match value {
    @engine.Scalar(value) => @engine.Scalar(value)
    @engine.Object(fields) => {
      let out : Array[(String, @engine.RVal)] = []
      for field in fields {
        out.push((field.0, from_entries(field.1, spec)))
      }
      @engine.Object(out)
    }
    @engine.Array(values) =>
      match spec {
        Entries =>
          if all_pairs(values) {
            let fields : Array[(String, @engine.RVal)] = []
            for value in values {
              match value {
                @engine.Array(items) =>
                  fields.push(
                    (result_key(items[0]), from_entries(items[1], spec)),
                  )
                _ => ()
              }
            }
            @engine.Object(fields)
          } else {
            let out : Array[@engine.RVal] = []
            for value in values {
              out.push(from_entries(value, spec))
            }
            @engine.Array(out)
          }
        KeyValue(key_field, value_field) =>
          if all_have_fields(values, [key_field, value_field]) {
            let fields : Array[(String, @engine.RVal)] = []
            for value in values {
              let key = match result_field(value, key_field) {
                Some(key) => result_key(key)
                None => "?"
              }
              let item = match result_field(value, value_field) {
                Some(item) => item
                None => @engine.Scalar(@engine.Bool(false))
              }
              fields.push((key, from_entries(item, spec)))
            }
            @engine.Object(fields)
          } else {
            let out : Array[@engine.RVal] = []
            for value in values {
              out.push(from_entries(value, spec))
            }
            @engine.Array(out)
          }
        KeyPromote(key_field) =>
          if all_have_fields(values, [key_field]) {
            let fields : Array[(String, @engine.RVal)] = []
            for value in values {
              match value {
                @engine.Object(items) => {
                  let mut key = ""
                  let rest : Array[(String, @engine.RVal)] = []
                  for item in items {
                    if item.0 == key_field {
                      key = result_key(item.1)
                    } else {
                      rest.push((item.0, from_entries(item.1, spec)))
                    }
                  }
                  fields.push((key, @engine.Object(rest)))
                }
                _ => ()
              }
            }
            @engine.Object(fields)
          } else {
            let out : Array[@engine.RVal] = []
            for value in values {
              out.push(from_entries(value, spec))
            }
            @engine.Array(out)
          }
      }
  }
}

///|
priv struct FromEntriesCollector {
  spec : FromEntriesSpec
}

///|
impl @engine.CollectorExt for FromEntriesCollector with fn kind(_self) {
  "from_entries"
}

///|
impl @engine.CollectorExt for FromEntriesCollector with fn encode(self) {
  match self.spec {
    Entries => "entries".to_json()
    KeyValue(key, value) => [key, value].to_json()
    KeyPromote(key) => key.to_json()
  }
}

///|
impl @engine.CollectorExt for FromEntriesCollector with fn collect(self, value) {
  from_entries(value, self.spec)
}

///|
pub fn from_entries_collector(spec : FromEntriesSpec) -> &@engine.CollectorExt {
  FromEntriesCollector::{ spec, } as &@engine.CollectorExt
}
