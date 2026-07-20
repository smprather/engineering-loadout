; Program structure
(module) @local.scope

(class_definition
  body: (block
    (expression_statement
      (assignment
        left: (identifier) @local.definition.field)))) @local.scope

(class_definition
  body: (block
    (expression_statement
      (assignment
        left: (_
          (identifier) @local.definition.field))))) @local.scope

; Imports
(aliased_import
  alias: (identifier) @local.definition.import) @local.scope

(import_statement
  name: (dotted_name
    (identifier) @local.definition.import)) @local.scope

(import_from_statement
  name: (dotted_name
    (identifier) @local.definition.import)) @local.scope

; Function with parameters, defines parameters
(parameters
  (identifier) @local.definition.parameter)

(default_parameter
  (identifier) @local.definition.parameter)

(typed_parameter
  (identifier) @local.definition.parameter)

(typed_default_parameter
  (identifier) @local.definition.parameter)

; *args parameter
(parameters
  (list_splat_pattern
    (identifier) @local.definition.parameter))

; **kwargs parameter
(parameters
  (dictionary_splat_pattern
    (identifier) @local.definition.parameter))

; Function defines function and scope
((function_definition
  name: (identifier) @local.definition.function) @local.scope
  (#set! definition.function.scope "parent"))

((class_definition
  name: (identifier) @local.definition.type) @local.scope
  (#set! definition.type.scope "parent"))

(class_definition
  body: (block
    (function_definition
      name: (identifier) @local.definition.method)))

; Loops
; not a scope!
(for_statement
  left: (pattern_list
    (identifier) @local.definition.var))

(for_statement
  left: (tuple_pattern
    (identifier) @local.definition.var))

(for_statement
  left: (identifier) @local.definition.var)

; not a scope!
;(while_statement) @local.scope
; for in list comprehension
(for_in_clause
  left: (identifier) @local.definition.var)

(for_in_clause
  left: (tuple_pattern
    (identifier) @local.definition.var))

(for_in_clause
  left: (pattern_list
    (identifier) @local.definition.var))

(dictionary_comprehension) @local.scope

(list_comprehension) @local.scope

(set_comprehension) @local.scope

; Assignments
(assignment
  left: (identifier) @local.definition.var)

(assignment
  left: (pattern_list
    (identifier) @local.definition.var))

(assignment
  left: (tuple_pattern
    (identifier) @local.definition.var))

(assignment
  left: (attribute
    (identifier)
    (identifier) @local.definition.field))

; Walrus operator  x := 1
(named_expression
  (identifier) @local.definition.var)

(as_pattern
  alias: (as_pattern_target) @local.definition.var)

; REFERENCES
(identifier) @local.reference


(rule_definition
  name: (identifier) @local.definition.type) @local.scope

(rule_inheritance
  alias: (as_pattern_target) @local.definition.type) @local.scope

(checkpoint_definition
  name: (identifier) @local.definition.type) @local.scope

(module_definition
  name: (identifier) @local.definition.type) @local.scope

; use rule A from X
(rule_import
  (rule_import_list
    (identifier) @local.definition.import)
  .
  module_name: (identifier) .) @local.scope

; use rule A from X as A_fromX
; use rule A from X as *_fromX
; use rule * from X as *_fromX
(rule_import
  alias: (as_pattern_target) @local.definition.import .) @local.scope

; use rule A from X with:
(rule_import
  (rule_import_list
    (identifier) @local.definition.type)
  .
  module_name: (identifier)
  .
  "with") @local.scope

; use rule A from X as Y with:
(rule_import
  alias: (as_pattern_target) @local.definition.type
  "with") @local.scope
