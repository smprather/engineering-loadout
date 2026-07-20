[
  (block)
  (declaration)
] @indent.begin

(block
  "}" @indent.branch)

"}" @indent.dedent

(comment) @indent.ignore


[
  (mixin_statement)
  (while_statement)
  (each_statement)
] @indent.begin
