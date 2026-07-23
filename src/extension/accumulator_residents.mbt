// accumulator_residents.mbt — canonical accumulator and collector residents.

///|
fn append_resolve_cli(
  name : String,
  cli : Array[@abi.Binding],
  include_default : Bool,
  lower : LowerSeat,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  let resolved : Array[@abi.Binding] = []
  let mut committed = false
  for binding in cli {
    if binding.key == name {
      match binding.op {
        @abi.Invoke(_) =>
          abort(
            "unreachable: accumulated cells reject update operations at definition time",
          )
        @abi.Remove | @abi.Splice =>
          abort(
            "unreachable: remove and splice pieces belong to the merge accumulator",
          )
        @abi.Default =>
          match lower(true) {
            Ok(defaults) => {
              resolved.push({ ..binding, source: @abi.Cli })
              for default in defaults {
                resolved.push({ ..default, op: @abi.Set, source: @abi.Cli })
              }
              committed = true
            }
            Err(error) => return Err(error)
          }
        @abi.Unset => {
          resolved.push(binding)
          committed = false
        }
        @abi.Empty | @abi.Set => {
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
impl AccumulatorExt for AppendAccumulator with fn kind(_self) {
  "append"
}

///|
impl AccumulatorExt for AppendAccumulator with fn encode(_self) {
  ().to_json()
}

///|
impl AccumulatorExt for AppendAccumulator with fn resolve_cli(
  _self,
  name,
  cli,
  include_default,
  lower,
) {
  append_resolve_cli(name, cli, include_default, lower)
}

///|
impl AccumulatorExt for AppendAccumulator with fn collect(_self, values) {
  let out : Array[@abi.ResultValue] = []
  for value in values {
    out.push(@abi.Scalar(value))
  }
  @abi.Array(out)
}

///|
pub fn append_accumulator() -> &AccumulatorExt {
  AppendAccumulator::{  } as &AccumulatorExt
}

///|
priv enum MergeGroup {
  Cell(@abi.Binding)
  Fire(Array[@abi.Binding])
}

///|
priv enum MergeMark {
  MAdd(@abi.Value)
  MRemove(@abi.Value)
  MSplice
}

///|
fn value_contains(values : Array[@abi.Value], target : @abi.Value) -> Bool {
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
  old : Array[@abi.Value],
) -> Array[@abi.Value] {
  let values : Array[@abi.Value] = []
  let removed : Array[@abi.Value] = []
  for mark in marks {
    match mark {
      MAdd(value) => values.push(value)
      MRemove(value) => {
        if !value_contains(removed, value) {
          removed.push(value)
        }
        let kept : Array[@abi.Value] = []
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
  cli : Array[@abi.Binding],
  include_default : Bool,
  lower : LowerSeat,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  let groups : Array[MergeGroup] = []
  let mut fire : Array[@abi.Binding] = []
  let mut fire_pos : Int? = None
  for binding in cli {
    if binding.key == name {
      match binding.op {
        @abi.Set | @abi.Remove | @abi.Splice => {
          if fire.length() > 0 && fire_pos != binding.at_pos {
            groups.push(Fire(fire))
            fire = []
          }
          fire_pos = binding.at_pos
          fire.push(binding)
        }
        @abi.Invoke(_) | @abi.Default | @abi.Unset | @abi.Empty => {
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

  let mut result : Array[@abi.Binding] = []
  let mut committed = false
  let mut old_values : Array[@abi.Value]? = None
  for group in groups {
    match group {
      Cell(binding) =>
        match binding.op {
          @abi.Invoke(_) =>
            abort(
              "unreachable: accumulated cells reject update operations at definition time",
            )
          @abi.Default =>
            match lower(true) {
              Ok(defaults) => {
                let next : Array[@abi.Binding] = [
                  { ..binding, source: @abi.Cli },
                ]
                let values : Array[@abi.Value] = []
                for default in defaults {
                  next.push({ ..default, op: @abi.Set, source: @abi.Cli })
                  values.push(default.value)
                }
                result = next
                old_values = Some(values)
                committed = true
              }
              Err(error) => return Err(error)
            }
          @abi.Unset => {
            result = [binding]
            old_values = None
            committed = false
          }
          @abi.Empty => {
            result = [binding]
            old_values = Some([])
            committed = true
          }
          @abi.Set | @abi.Remove | @abi.Splice =>
            abort("unreachable: merge cell operations are grouped as a firing")
        }
      Fire(pieces) => {
        let marks : Array[MergeMark] = []
        for piece in pieces {
          match piece.op {
            @abi.Set => marks.push(MAdd(piece.value))
            @abi.Remove => marks.push(MRemove(piece.value))
            @abi.Splice => marks.push(MSplice)
            _ =>
              abort("unreachable: merge firing contains only set/remove/splice")
          }
        }
        if merge_pieces_has_no_marker(marks) {
          let values : Array[@abi.Value] = []
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
                  let values : Array[@abi.Value] = []
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
          let next : Array[@abi.Binding] = []
          for value in values {
            next.push(@abi.Binding::new(name, value, @abi.Cli))
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
impl AccumulatorExt for MergeAccumulator with fn kind(_self) {
  "merge"
}

///|
impl AccumulatorExt for MergeAccumulator with fn encode(_self) {
  ().to_json()
}

///|
impl AccumulatorExt for MergeAccumulator with fn resolve_cli(
  _self,
  name,
  cli,
  include_default,
  lower,
) {
  merge_resolve_cli(name, cli, include_default, lower)
}

///|
impl AccumulatorExt for MergeAccumulator with fn collect(_self, values) {
  let out : Array[@abi.ResultValue] = []
  for value in values {
    out.push(@abi.Scalar(value))
  }
  @abi.Array(out)
}

///|
pub fn merge_accumulator() -> &AccumulatorExt {
  MergeAccumulator::{  } as &AccumulatorExt
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
impl AccumulatorExt for KvMapAccumulator with fn kind(_self) {
  "kv_map"
}

///|
impl AccumulatorExt for KvMapAccumulator with fn encode(_self) {
  ().to_json()
}

///|
impl AccumulatorExt for KvMapAccumulator with fn resolve_cli(
  _self,
  name,
  cli,
  include_default,
  lower,
) {
  append_resolve_cli(name, cli, include_default, lower)
}

///|
impl AccumulatorExt for KvMapAccumulator with fn collect(_self, values) {
  let fields : Array[(String, @abi.ResultValue)] = []
  let seen : Map[String, Int] = Map([])
  for value in values {
    let raw = match value {
      @abi.String(text) => text
      _ => ""
    }
    let (key, rest) = split_first_eq(raw)
    match seen.get(key) {
      Some(index) => fields[index] = (key, @abi.Scalar(@abi.String(rest)))
      None => {
        seen.set(key, fields.length())
        fields.push((key, @abi.Scalar(@abi.String(rest))))
      }
    }
  }
  @abi.Object(fields)
}

///|
pub fn kv_map_accumulator() -> &AccumulatorExt {
  KvMapAccumulator::{  } as &AccumulatorExt
}

///|
fn unwrap_single(value : @abi.ResultValue) -> @abi.ResultValue {
  match value {
    @abi.Scalar(value) => @abi.Scalar(value)
    @abi.Array(values) =>
      if values.length() == 1 {
        unwrap_single(values[0])
      } else {
        let out : Array[@abi.ResultValue] = []
        for value in values {
          out.push(unwrap_single(value))
        }
        @abi.Array(out)
      }
    @abi.Object(fields) => {
      let out : Array[(String, @abi.ResultValue)] = []
      for field in fields {
        out.push((field.0, unwrap_single(field.1)))
      }
      @abi.Object(out)
    }
  }
}

///|
priv struct UnwrapSingleCollector {}

///|
impl CollectorExt for UnwrapSingleCollector with fn kind(_self) {
  "unwrap_single"
}

///|
impl CollectorExt for UnwrapSingleCollector with fn encode(_self) {
  ().to_json()
}

///|
impl CollectorExt for UnwrapSingleCollector with fn collect(_self, value) {
  unwrap_single(value)
}

///|
pub fn unwrap_single_collector() -> &CollectorExt {
  UnwrapSingleCollector::{  } as &CollectorExt
}

///|
pub(all) enum FromEntriesSpec {
  Entries
  KeyValue(String, String)
  KeyPromote(String)
} derive(Eq, Debug)

///|
pub fn from_entries_spec_of(json : Json) -> FromEntriesSpec? {
  match json {
    String("entries") => Some(Entries)
    String(key) => Some(KeyPromote(key))
    Array(items) =>
      if items.length() == 2 {
        match (items[0], items[1]) {
          (String(key), String(value)) => Some(KeyValue(key, value))
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn result_value_json(value : @abi.ResultValue) -> Json {
  match value {
    @abi.Scalar(value) =>
      match value {
        @abi.String(value) => value.to_json()
        @abi.Number(value) => value.to_json()
        @abi.Bool(value) => value.to_json()
      }
    @abi.Array(values) => {
      let out : Array[Json] = []
      for value in values {
        out.push(result_value_json(value))
      }
      out.to_json()
    }
    @abi.Object(fields) => {
      let out : Map[String, Json] = Map([])
      for field in fields {
        out.set(field.0, result_value_json(field.1))
      }
      out.to_json()
    }
  }
}

///|
fn result_key(value : @abi.ResultValue) -> String {
  match value {
    @abi.Scalar(value) => @abi.value_str(value)
    @abi.Array(_) | @abi.Object(_) => result_value_json(value).stringify()
  }
}

///|
fn result_field(value : @abi.ResultValue, name : String) -> @abi.ResultValue? {
  match value {
    @abi.Object(fields) => {
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
fn all_pairs(values : Array[@abi.ResultValue]) -> Bool {
  if values.length() == 0 {
    return false
  }
  for value in values {
    match value {
      @abi.Array(items) => if items.length() != 2 { return false }
      _ => return false
    }
  }
  true
}

///|
fn all_have_fields(
  values : Array[@abi.ResultValue],
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
fn from_entries(
  value : @abi.ResultValue,
  spec : FromEntriesSpec,
) -> @abi.ResultValue {
  match value {
    @abi.Scalar(value) => @abi.Scalar(value)
    @abi.Object(fields) => {
      let out : Array[(String, @abi.ResultValue)] = []
      for field in fields {
        out.push((field.0, from_entries(field.1, spec)))
      }
      @abi.Object(out)
    }
    @abi.Array(values) =>
      match spec {
        Entries =>
          if all_pairs(values) {
            let fields : Array[(String, @abi.ResultValue)] = []
            for value in values {
              match value {
                @abi.Array(items) =>
                  fields.push(
                    (result_key(items[0]), from_entries(items[1], spec)),
                  )
                _ => ()
              }
            }
            @abi.Object(fields)
          } else {
            let out : Array[@abi.ResultValue] = []
            for value in values {
              out.push(from_entries(value, spec))
            }
            @abi.Array(out)
          }
        KeyValue(key_field, value_field) =>
          if all_have_fields(values, [key_field, value_field]) {
            let fields : Array[(String, @abi.ResultValue)] = []
            for value in values {
              let key = match result_field(value, key_field) {
                Some(key) => result_key(key)
                None => "?"
              }
              let item = match result_field(value, value_field) {
                Some(item) => item
                None => @abi.Scalar(@abi.Bool(false))
              }
              fields.push((key, from_entries(item, spec)))
            }
            @abi.Object(fields)
          } else {
            let out : Array[@abi.ResultValue] = []
            for value in values {
              out.push(from_entries(value, spec))
            }
            @abi.Array(out)
          }
        KeyPromote(key_field) =>
          if all_have_fields(values, [key_field]) {
            let fields : Array[(String, @abi.ResultValue)] = []
            for value in values {
              match value {
                @abi.Object(items) => {
                  let mut key = ""
                  let rest : Array[(String, @abi.ResultValue)] = []
                  for item in items {
                    if item.0 == key_field {
                      key = result_key(item.1)
                    } else {
                      rest.push((item.0, from_entries(item.1, spec)))
                    }
                  }
                  fields.push((key, @abi.Object(rest)))
                }
                _ => ()
              }
            }
            @abi.Object(fields)
          } else {
            let out : Array[@abi.ResultValue] = []
            for value in values {
              out.push(from_entries(value, spec))
            }
            @abi.Array(out)
          }
      }
  }
}

///|
priv struct FromEntriesCollector {
  spec : FromEntriesSpec
}

///|
impl CollectorExt for FromEntriesCollector with fn kind(_self) {
  "from_entries"
}

///|
impl CollectorExt for FromEntriesCollector with fn encode(self) {
  match self.spec {
    Entries => "entries".to_json()
    KeyValue(key, value) => [key, value].to_json()
    KeyPromote(key) => key.to_json()
  }
}

///|
impl CollectorExt for FromEntriesCollector with fn collect(self, value) {
  from_entries(value, self.spec)
}

///|
pub fn from_entries_collector(spec : FromEntriesSpec) -> &CollectorExt {
  FromEntriesCollector::{ spec, } as &CollectorExt
}
