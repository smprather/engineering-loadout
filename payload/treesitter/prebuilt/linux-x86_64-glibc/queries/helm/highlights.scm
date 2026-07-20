; Priorities of the highlight queries are raised, so that they overrule the
; often surrounding and overlapping highlights from the non-gotmpl injections.
;
; Identifiers
([
  (field)
  (field_identifier)
] @variable.member
  (#set! priority 110))

((variable) @variable
  (#set! priority 110))

; Function calls
(function_call
  function: (identifier) @function
  (#set! priority 110))

(method_call
  method: (selector_expression
    field: (field_identifier) @function
    (#set! priority 110)))

; Builtin functions
(function_call
  function: (identifier) @function.builtin
  (#set! priority 110)
  (#any-of? @function.builtin
    "and" "call" "html" "index" "slice" "js" "len" "not" "or" "print" "printf" "println" "urlquery"
    "eq" "ne" "lt" "ge" "gt" "ge"))

; Operators
([
  "|"
  "="
  ":="
] @operator
  (#set! priority 110))

; Delimiters
([
  "."
  ","
] @punctuation.delimiter
  (#set! priority 110))

([
  "{{"
  "}}"
  "{{-"
  "-}}"
  ")"
  "("
] @punctuation.bracket
  (#set! priority 110))

; Actions
(if_action
  [
    "if"
    "else"
    "end"
  ] @keyword.conditional
  (#set! priority 110))

(range_action
  [
    "range"
    "else"
    "end"
  ] @keyword.repeat
  (#set! priority 110))

(template_action
  "template" @function.builtin
  (#set! priority 110))

(block_action
  [
    "block"
    "end"
  ] @keyword.directive
  (#set! priority 110))

(define_action
  [
    "define"
    "end"
  ] @keyword.directive.define
  (#set! priority 110))

(with_action
  [
    "with"
    "else"
    "end"
  ] @keyword.conditional
  (#set! priority 110))

(continue_action
  "continue" @keyword.repeat
  (#set! priority 110))

(break_action
  "break" @keyword.repeat
  (#set! priority 110))

; Literals
([
  (interpreted_string_literal)
  (raw_string_literal)
] @string
  (#set! priority 110))

((rune_literal) @string.special.symbol
  (#set! priority 110))

((escape_sequence) @string.escape
  (#set! priority 110))

([
  (int_literal)
  (imaginary_literal)
] @number
  (#set! priority 110))

((float_literal) @number.float
  (#set! priority 110))

([
  (true)
  (false)
] @boolean
  (#set! priority 110))

((nil) @constant.builtin
  (#set! priority 110))

((comment) @comment @spell
  (#set! priority 110))


; For the reasoning concerning the priorities, see gotmpl highlights.
;
; Builtin functions
(function_call
  function: (identifier) @function.builtin
  (#set! priority 110)
  (#any-of? @function.builtin
    "and" "or" "not" "eq" "ne" "lt" "le" "gt" "ge" "default" "required" "empty" "fail" "coalesce"
    "ternary" "print" "println" "printf" "trim" "trimAll" "trimPrefix" "trimSuffix" "lower" "upper"
    "title" "untitle" "repeat" "substr" "nospace" "trunc" "abbrev" "abbrevboth" "initials"
    "randAlphaNum" "randAlpha" "randNumeric" "randAscii" "wrap" "wrapWith" "contains" "hasPrefix"
    "hasSuffix" "quote" "squote" "cat" "indent" "nindent" "replace" "plural" "snakecase" "camelcase"
    "kebabcase" "swapcase" "shuffle" "toStrings" "toDecimal" "toJson" "mustToJson" "toPrettyJson"
    "mustToPrettyJson" "toRawJson" "mustToRawJson" "fromYaml" "fromJson" "fromJsonArray"
    "fromYamlArray" "toYaml" "regexMatch" "mustRegexMatch" "regexFindAll" "mustRegexFinDall"
    "regexFind" "mustRegexFind" "regexReplaceAll" "mustRegexReplaceAll" "regexReplaceAllLiteral"
    "mustRegexReplaceAllLiteral" "regexSplit" "mustRegexSplit" "sha1sum" "sha256sum" "adler32sum"
    "htpasswd" "derivePassword" "genPrivateKey" "buildCustomCert" "genCA" "genSelfSignedCert"
    "genSignedCert" "encryptAES" "decryptAES" "now" "ago" "date" "dateInZone" "duration"
    "durationRound" "unixEpoch" "dateModify" "mustDateModify" "htmlDate" "htmlDateInZone" "toDate"
    "mustToDate" "dict" "get" "set" "unset" "hasKey" "pluck" "dig" "merge" "mustMerge"
    "mergeOverwrite" "mustMergeOverwrite" "keys" "pick" "omit" "values" "deepCopy" "mustDeepCopy"
    "b64enc" "b64dec" "b32enc" "b32dec" "list" "first" "mustFirst" "rest" "mustRest" "last"
    "mustLast" "initial" "mustInitial" "append" "mustAppend" "prepend" "mustPrepend" "concat"
    "reverse" "mustReverse" "uniq" "mustUniq" "without" "mustWithout" "has" "mustHas" "compact"
    "mustCompact" "index" "slice" "mustSlice" "until" "untilStep" "seq" "add" "add1" "sub" "div"
    "mod" "mul" "max" "min" "len" "addf" "add1f" "subf" "divf" "mulf" "maxf" "minf" "floor" "ceil"
    "round" "getHostByName" "base" "dir" "clean" "ext" "isAbs" "kindOf" "kindIs" "typeOf" "typeIs"
    "typeIsLike" "deepequal" "semver" "semverCompare" "urlParse" "urlJoin" "urlquery" "lookup"
    "include"))

; {{ .Values.test }}
(selector_expression
  operand: (field
    name: (identifier) @constant.builtin
    (#set! priority 110)
    (#any-of? @constant.builtin
      "Values" "Chart" "Release" "Capabilities" "Files" "Subcharts" "Template"))
  (field_identifier))

; {{ $.Values.test }}
(selector_expression
  operand: (variable)
  field: (field_identifier) @constant.builtin
  (#set! priority 110)
  (#any-of? @constant.builtin
    "Values" "Chart" "Release" "Capabilities" "Files" "Subcharts" "Template"))
