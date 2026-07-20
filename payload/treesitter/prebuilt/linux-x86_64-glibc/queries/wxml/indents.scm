((element
  (start_tag
    (tag_name) @_not_void_element))
  (#not-any-of? @_not_void_element
    "area" "base" "basefont" "bgsound" "br" "col" "command" "embed" "frame" "hr" "image" "img"
    "input" "isindex" "keygen" "link" "menuitem" "meta" "nextid" "param" "source" "track" "wbr")) @indent.begin

(element
  (self_closing_tag)) @indent.begin

((start_tag
  (tag_name) @_void_element)
  (#any-of? @_void_element
    "area" "base" "basefont" "bgsound" "br" "col" "command" "embed" "frame" "hr" "image" "img"
    "input" "isindex" "keygen" "link" "menuitem" "meta" "nextid" "param" "source" "track" "wbr")) @indent.begin

; These are the nodes that will be captured when we do `normal o`
; But last element has already been ended, so capturing this
; to mark end of last element
(element
  (end_tag
    ">" @indent.end))

(element
  (self_closing_tag
    "/>" @indent.end))

; Script/style elements aren't indented, so only branch the end tag of other elements
(element
  (end_tag) @indent.branch)

[
  ">"
  "/>"
] @indent.branch

(comment) @indent.ignore


(block_element) @indent.begin

(template_element) @indent.begin

(wxs_element) @indent.begin

(block_element
  (block_end_tag
    ">" @indent.end))

(template_element
  (template_end_tag
    ">" @indent.end))

(wxs_element
  (wxs_end_tag
    ">" @indent.end))

(block_element
  (block_end_tag) @indent.branch)

(template_element
  (template_end_tag) @indent.branch)

(wxs_element
  (wxs_end_tag) @indent.branch)

(import_statement) @indent.ignore

(include_statement) @indent.ignore
