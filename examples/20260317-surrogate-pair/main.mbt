// サロゲートペア調査 PoC
// MoonBit String UTF-16 内部表現と kuu short combining の検証

// ============================================================
// Part 1: MoonBit String UTF-16 内部表現の検証
// ============================================================

///|
test "String.length() は UTF-16 コードユニット数を返す" {
  // BMP 文字
  inspect("A".length(), content=(
    #|1
  ))
  inspect("漢".length(), content=(
    #|1
  ))
  // Supplementary Plane（サロゲートペア）
  inspect("😀".length(), content=(
    #|2
  ))
  inspect("𝄞".length(), content=(
    #|2
  ))
  inspect("𠮷".length(), content=(
    #|2
  ))
}

///|
test "String.char_length() は Unicode コードポイント数を返す" {
  inspect("A".char_length(), content=(
    #|1
  ))
  inspect("😀".char_length(), content=(
    #|1
  ))
  inspect("A😀B".char_length(), content=(
    #|3
  ))
}

///|
test "String のインデックスアクセスは UTF-16 コードユニット単位" {
  let s = "A😀B"
  // s.length() = 4 (A=1, 😀=2, B=1)
  inspect(s.length(), content=(
    #|4
  ))
  // s[0] = 'A' の UTF-16 コードユニット値 (UInt16)
  inspect(s[0].to_int(), content=(
    #|65
  ))
  // s[1] = high surrogate
  inspect(s[1].to_int(), content=(
    #|55357
  ))
  // s[2] = low surrogate
  inspect(s[2].to_int(), content=(
    #|56832
  ))
  // s[3] = 'B'
  inspect(s[3].to_int(), content=(
    #|66
  ))
}

///|
test "String.iter() は Unicode コードポイント単位でイテレートする" {
  let s = "A😀B"
  let chars : Array[String] = []
  for ch in s {
    chars.push(ch.to_string())
  }
  inspect(chars, content=(
    #|["A", "😀", "B"]
  ))
}

///|
test "Char型は単一Unicodeコードポイントを表す" {
  let ch : Char = '😀'
  inspect(ch, content=(
    #|😀
  ))
  // Char.to_int() はコードポイント値を返す
  inspect(ch.to_int(), content=(
    #|128512
  ))
}

///|
test "String.to_array() は Char（コードポイント）の配列を返す" {
  let arr = "A😀B".to_array()
  inspect(arr.length(), content=(
    #|3
  ))
  inspect(arr, content=(
    #|['A', '😀', 'B']
  ))
}

// ============================================================
// Part 2: サロゲートペアが壊れるパターンの検証
// ============================================================

///|
test "unsafe_to_char でサロゲートペアが壊れる" {
  let s = "😀"
  // s[0] は high surrogate の UInt16 値
  let high = s[0]
  // unsafe_to_char で「文字」に変換すると不正なコードポイントになる
  let broken_char = high.to_int().unsafe_to_char()
  inspect(broken_char.to_int(), content=(
    #|55357
  ))
  // 元の文字 0x1F600 とは全く異なる
  inspect('😀'.to_int(), content=(
    #|128512
  ))
}

///|
test "length() ベースのループでサロゲートペアのコードユニット値が分離する" {
  let s = "A😀B"
  let result : Array[Int] = []
  let mut i = 0
  while i < s.length() {
    // s[i] は UInt16 を返すので .to_int() で Int に変換
    result.push(s[i].to_int())
    i += 1
  }
  // 4要素: A(65), high(55357=0xD83D), low(56832=0xDE00), B(66)
  inspect(result, content=(
    #|[65, 55357, 56832, 66]
  ))
}

///|
test "iter() ベースのループならサロゲートペアは正しく処理される" {
  let s = "A😀B"
  let result : Array[String] = []
  for ch in s {
    result.push(ch.to_string())
  }
  inspect(result.length(), content=(
    #|3
  ))
  inspect(result, content=(
    #|["A", "😀", "B"]
  ))
}

// ============================================================
// Part 3: kuu の short combining における問題の検証
// ============================================================

///|
test "BMP文字の short combining は正常に動作する" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let all = p.flag(name="all", shorts="a")
  let force = p.flag(name="force", shorts="f")
  let _ = p.parse(["-vaf"])
  inspect(verbose.get(), content=(
    #|Some(true)
  ))
  inspect(all.get(), content=(
    #|Some(true)
  ))
  inspect(force.get(), content=(
    #|Some(true)
  ))
}

///|
test "Supplementary Plane文字の個別 short option は動作する" {
  let p = @core.Parser::new()
  let emoji = p.flag(name="emoji", shorts="😀")
  let _ = p.parse(["-😀"])
  inspect(emoji.get(), content=(
    #|Some(true)
  ))
}

///|
test "Supplementary Plane文字の short combining は失敗する" {
  let p = @core.Parser::new()
  let _emoji = p.flag(name="emoji", shorts="😀")
  let _verbose = p.flag(name="verbose", shorts="v")
  // -😀v: combining で emoji ノードが name.length()==2 の条件で除外される
  let result = try? p.parse(["-😀v"])
  inspect(result is Ok(_), content=(
    #|false
  ))
  match result {
    Err(@core.ParseError(info)) => inspect(info.to_string(), content=(
      #|error: unexpected argument: -😀v
      #|
      #|Usage: [OPTIONS]
      #|
      #|Options:
      #|  -😀, --emoji
      #|  -v, --verbose
      #|  -h, --help     Print help
      #|
    ))
    Err(@core.HelpRequested(_)) => inspect("help requested", content="")
    Ok(_) => inspect("(no error)", content="")
  }
}

///|
test "BMP文字とSupplementary文字の混在 combining は失敗する" {
  let p = @core.Parser::new()
  let _verbose = p.flag(name="verbose", shorts="v")
  let _emoji = p.flag(name="emoji", shorts="😀")
  // -v😀: v は正常に処理されるが、その後の😀でサロゲートペアが壊れる
  let result = try? p.parse(["-v😀"])
  inspect(result is Ok(_), content=(
    #|false
  ))
  match result {
    Err(@core.ParseError(info)) => inspect(info.to_string(), content=(
      #|error: unexpected argument: -v😀
      #|
      #|Usage: [OPTIONS]
      #|
      #|Options:
      #|  -v, --verbose
      #|  -😀, --emoji
      #|  -h, --help     Print help
      #|
    ))
    Err(@core.HelpRequested(_)) => inspect("help requested", content="")
    Ok(_) => inspect("(no error)", content="")
  }
}
