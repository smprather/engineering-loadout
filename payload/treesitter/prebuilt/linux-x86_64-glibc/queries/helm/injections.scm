((comment) @injection.content
  (#set! injection.language "comment"))

; {{"put" | printf "%s%s" "out" | printf "%q"}}
(function_call
  function: (identifier) @_function
  arguments: (argument_list
    .
    (interpreted_string_literal) @injection.content)
  (#eq? @_function "printf")
  (#set! injection.language "printf"))

; {{ js "var a = 1 + 1" }}
(function_call
  function: (identifier) @_function
  arguments: (argument_list
    .
    (interpreted_string_literal) @injection.content)
  (#eq? @_function "js")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "javascript"))

; {{ html "<h1>hello</h1>" }}
(function_call
  function: (identifier) @_function
  arguments: (argument_list
    .
    (interpreted_string_literal) @injection.content)
  (#eq? @_function "html")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "html"))


((text) @injection.content
  (#set! injection.language "yaml")
  (#set! injection.combined))

; {{ regexFind "[a-zA-Z][1-9]" "abcd1234" }}
(function_call
  function: (identifier) @_function
  arguments: (argument_list
    .
    (interpreted_string_literal) @injection.content)
  (#any-of? @_function
    "regexMatch" "mustRegexMatch" "regexFindAll" "mustRegexFinDall" "regexFind" "mustRegexFind"
    "regexReplaceAll" "mustRegexReplaceAll" "regexReplaceAllLiteral" "mustRegexReplaceAllLiteral"
    "regexSplit" "mustRegexSplit")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "regex"))

(function_call
  function: (identifier) @_function
  arguments: (argument_list
    .
    (interpreted_string_literal) @injection.content)
  (#any-of? @_function "fromYaml" "fromYamlArray")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "yaml"))

(function_call
  function: (identifier) @_function
  arguments: (argument_list
    .
    (interpreted_string_literal) @injection.content)
  (#any-of? @_function "fromJson" "fromJsonArray")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.language "json"))
