#compdef taplo

autoload -U is-at-least

_taplo() {
    typeset -A opt_args
    typeset -a _arguments_options
    local ret=1

    if is-at-least 5.2; then
        _arguments_options=(-s -S -C)
    else
        _arguments_options=(-s -C)
    fi

    local context curcontext="$curcontext" state line
    _arguments "${_arguments_options[@]}" \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'-V[Print version]' \
'--version[Print version]' \
":: :_taplo_commands" \
"*::: :->taplo" \
&& ret=0
    case $state in
    (taplo)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:taplo-command-$line[1]:"
        case $line[1] in
            (lint)
_arguments "${_arguments_options[@]}" \
'-c+[Path to the Taplo configuration file]:CONFIG:_files' \
'--config=[Path to the Taplo configuration file]:CONFIG:_files' \
'--cache-path=[Set a cache path]:CACHE_PATH:_files' \
'--schema=[URL to the schema to be used for validation]:SCHEMA: ' \
'*--schema-catalog=[URL to a schema catalog (index) that is compatible with Schema Store or Taplo catalogs]:SCHEMA_CATALOG: ' \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--no-auto-config[Do not search for a configuration file]' \
'--default-schema-catalogs[Use the default online catalogs for schemas]' \
'--no-schema[Disable all schema validations]' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'*::files -- Paths or glob patterns to TOML documents:' \
&& ret=0
;;
(format)
_arguments "${_arguments_options[@]}" \
'-c+[Path to the Taplo configuration file]:CONFIG:_files' \
'--config=[Path to the Taplo configuration file]:CONFIG:_files' \
'--cache-path=[Set a cache path]:CACHE_PATH:_files' \
'*-o+[A formatter option given as a "key=value", can be set multiple times]:OPTIONS: ' \
'*--option=[A formatter option given as a "key=value", can be set multiple times]:OPTIONS: ' \
'--stdin-filepath=[A path to the file that the Taplo CLI will treat like stdin]:STDIN_FILEPATH: ' \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--no-auto-config[Do not search for a configuration file]' \
'-f[Ignore syntax errors and force formatting]' \
'--force[Ignore syntax errors and force formatting]' \
'--check[Dry-run and report any files that are not correctly formatted]' \
'--diff[Print the differences in patch formatting to \`stdout\`]' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'*::files -- Paths or glob patterns to TOML documents:' \
&& ret=0
;;
(lsp)
_arguments "${_arguments_options[@]}" \
'-c+[Path to the Taplo configuration file]:CONFIG:_files' \
'--config=[Path to the Taplo configuration file]:CONFIG:_files' \
'--cache-path=[Set a cache path]:CACHE_PATH:_files' \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--no-auto-config[Do not search for a configuration file]' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_taplo__lsp_commands" \
"*::: :->lsp" \
&& ret=0

    case $state in
    (lsp)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:taplo-lsp-command-$line[1]:"
        case $line[1] in
            (tcp)
_arguments "${_arguments_options[@]}" \
'--address=[The address to listen on]:ADDRESS: ' \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(stdio)
_arguments "${_arguments_options[@]}" \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_taplo__lsp__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:taplo-lsp-help-command-$line[1]:"
        case $line[1] in
            (tcp)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(stdio)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(config)
_arguments "${_arguments_options[@]}" \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_taplo__config_commands" \
"*::: :->config" \
&& ret=0

    case $state in
    (config)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:taplo-config-command-$line[1]:"
        case $line[1] in
            (default)
_arguments "${_arguments_options[@]}" \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(schema)
_arguments "${_arguments_options[@]}" \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_taplo__config__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:taplo-config-help-command-$line[1]:"
        case $line[1] in
            (default)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(schema)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(get)
_arguments "${_arguments_options[@]}" \
'-o+[The format specifying how the output is printed]:OUTPUT_FORMAT:((value\:"Extract the value outputting it in a text format"
json\:"Output format in JSON"
toml\:"Output format in TOML"))' \
'--output-format=[The format specifying how the output is printed]:OUTPUT_FORMAT:((value\:"Extract the value outputting it in a text format"
json\:"Output format in JSON"
toml\:"Output format in TOML"))' \
'-f+[Path to the TOML document, if omitted the standard input will be used]:FILE_PATH:_files' \
'--file-path=[Path to the TOML document, if omitted the standard input will be used]:FILE_PATH:_files' \
'--separator=[A string that separates array values when printing to stdout]:SEPARATOR: ' \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'-s[Strip the trailing newline from the output]' \
'--strip-newline[Strip the trailing newline from the output]' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'::pattern -- A dotted key pattern to the value within the TOML document:' \
&& ret=0
;;
(toml-test)
_arguments "${_arguments_options[@]}" \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(completions)
_arguments "${_arguments_options[@]}" \
'--colors=[]:COLORS:((auto\:"Determine whether to colorize output automatically"
always\:"Always colorize output"
never\:"Never colorize output"))' \
'--verbose[Enable a verbose logging format]' \
'--log-spans[Enable logging spans]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
':shell:' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_taplo__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:taplo-help-command-$line[1]:"
        case $line[1] in
            (lint)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(format)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(lsp)
_arguments "${_arguments_options[@]}" \
":: :_taplo__help__lsp_commands" \
"*::: :->lsp" \
&& ret=0

    case $state in
    (lsp)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:taplo-help-lsp-command-$line[1]:"
        case $line[1] in
            (tcp)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(stdio)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
(config)
_arguments "${_arguments_options[@]}" \
":: :_taplo__help__config_commands" \
"*::: :->config" \
&& ret=0

    case $state in
    (config)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:taplo-help-config-command-$line[1]:"
        case $line[1] in
            (default)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(schema)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
(get)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(toml-test)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(completions)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
}

(( $+functions[_taplo_commands] )) ||
_taplo_commands() {
    local commands; commands=(
'lint:Lint TOML documents' \
'check:Lint TOML documents' \
'validate:Lint TOML documents' \
'format:Format TOML documents' \
'fmt:Format TOML documents' \
'lsp:Language server operations' \
'config:Operations with the Taplo config file' \
'cfg:Operations with the Taplo config file' \
'get:Extract a value from the given TOML document' \
'toml-test:Start a decoder for \`toml-test\` (https\://github.com/BurntSushi/toml-test)' \
'completions:Generate completions for Taplo CLI' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'taplo commands' commands "$@"
}
(( $+functions[_taplo__completions_commands] )) ||
_taplo__completions_commands() {
    local commands; commands=()
    _describe -t commands 'taplo completions commands' commands "$@"
}
(( $+functions[_taplo__help__completions_commands] )) ||
_taplo__help__completions_commands() {
    local commands; commands=()
    _describe -t commands 'taplo help completions commands' commands "$@"
}
(( $+functions[_taplo__config_commands] )) ||
_taplo__config_commands() {
    local commands; commands=(
'default:Print the default \`.taplo.toml\` configuration file' \
'schema:Print the JSON schema of the \`.taplo.toml\` configuration file' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'taplo config commands' commands "$@"
}
(( $+functions[_taplo__help__config_commands] )) ||
_taplo__help__config_commands() {
    local commands; commands=(
'default:Print the default \`.taplo.toml\` configuration file' \
'schema:Print the JSON schema of the \`.taplo.toml\` configuration file' \
    )
    _describe -t commands 'taplo help config commands' commands "$@"
}
(( $+functions[_taplo__config__default_commands] )) ||
_taplo__config__default_commands() {
    local commands; commands=()
    _describe -t commands 'taplo config default commands' commands "$@"
}
(( $+functions[_taplo__config__help__default_commands] )) ||
_taplo__config__help__default_commands() {
    local commands; commands=()
    _describe -t commands 'taplo config help default commands' commands "$@"
}
(( $+functions[_taplo__help__config__default_commands] )) ||
_taplo__help__config__default_commands() {
    local commands; commands=()
    _describe -t commands 'taplo help config default commands' commands "$@"
}
(( $+functions[_taplo__format_commands] )) ||
_taplo__format_commands() {
    local commands; commands=()
    _describe -t commands 'taplo format commands' commands "$@"
}
(( $+functions[_taplo__help__format_commands] )) ||
_taplo__help__format_commands() {
    local commands; commands=()
    _describe -t commands 'taplo help format commands' commands "$@"
}
(( $+functions[_taplo__get_commands] )) ||
_taplo__get_commands() {
    local commands; commands=()
    _describe -t commands 'taplo get commands' commands "$@"
}
(( $+functions[_taplo__help__get_commands] )) ||
_taplo__help__get_commands() {
    local commands; commands=()
    _describe -t commands 'taplo help get commands' commands "$@"
}
(( $+functions[_taplo__config__help_commands] )) ||
_taplo__config__help_commands() {
    local commands; commands=(
'default:Print the default \`.taplo.toml\` configuration file' \
'schema:Print the JSON schema of the \`.taplo.toml\` configuration file' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'taplo config help commands' commands "$@"
}
(( $+functions[_taplo__config__help__help_commands] )) ||
_taplo__config__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'taplo config help help commands' commands "$@"
}
(( $+functions[_taplo__help_commands] )) ||
_taplo__help_commands() {
    local commands; commands=(
'lint:Lint TOML documents' \
'format:Format TOML documents' \
'lsp:Language server operations' \
'config:Operations with the Taplo config file' \
'get:Extract a value from the given TOML document' \
'toml-test:Start a decoder for \`toml-test\` (https\://github.com/BurntSushi/toml-test)' \
'completions:Generate completions for Taplo CLI' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'taplo help commands' commands "$@"
}
(( $+functions[_taplo__help__help_commands] )) ||
_taplo__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'taplo help help commands' commands "$@"
}
(( $+functions[_taplo__lsp__help_commands] )) ||
_taplo__lsp__help_commands() {
    local commands; commands=(
'tcp:Run the language server and listen on a TCP address' \
'stdio:Run the language server over the standard input and output' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'taplo lsp help commands' commands "$@"
}
(( $+functions[_taplo__lsp__help__help_commands] )) ||
_taplo__lsp__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'taplo lsp help help commands' commands "$@"
}
(( $+functions[_taplo__help__lint_commands] )) ||
_taplo__help__lint_commands() {
    local commands; commands=()
    _describe -t commands 'taplo help lint commands' commands "$@"
}
(( $+functions[_taplo__lint_commands] )) ||
_taplo__lint_commands() {
    local commands; commands=()
    _describe -t commands 'taplo lint commands' commands "$@"
}
(( $+functions[_taplo__help__lsp_commands] )) ||
_taplo__help__lsp_commands() {
    local commands; commands=(
'tcp:Run the language server and listen on a TCP address' \
'stdio:Run the language server over the standard input and output' \
    )
    _describe -t commands 'taplo help lsp commands' commands "$@"
}
(( $+functions[_taplo__lsp_commands] )) ||
_taplo__lsp_commands() {
    local commands; commands=(
'tcp:Run the language server and listen on a TCP address' \
'stdio:Run the language server over the standard input and output' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'taplo lsp commands' commands "$@"
}
(( $+functions[_taplo__config__help__schema_commands] )) ||
_taplo__config__help__schema_commands() {
    local commands; commands=()
    _describe -t commands 'taplo config help schema commands' commands "$@"
}
(( $+functions[_taplo__config__schema_commands] )) ||
_taplo__config__schema_commands() {
    local commands; commands=()
    _describe -t commands 'taplo config schema commands' commands "$@"
}
(( $+functions[_taplo__help__config__schema_commands] )) ||
_taplo__help__config__schema_commands() {
    local commands; commands=()
    _describe -t commands 'taplo help config schema commands' commands "$@"
}
(( $+functions[_taplo__help__lsp__stdio_commands] )) ||
_taplo__help__lsp__stdio_commands() {
    local commands; commands=()
    _describe -t commands 'taplo help lsp stdio commands' commands "$@"
}
(( $+functions[_taplo__lsp__help__stdio_commands] )) ||
_taplo__lsp__help__stdio_commands() {
    local commands; commands=()
    _describe -t commands 'taplo lsp help stdio commands' commands "$@"
}
(( $+functions[_taplo__lsp__stdio_commands] )) ||
_taplo__lsp__stdio_commands() {
    local commands; commands=()
    _describe -t commands 'taplo lsp stdio commands' commands "$@"
}
(( $+functions[_taplo__help__lsp__tcp_commands] )) ||
_taplo__help__lsp__tcp_commands() {
    local commands; commands=()
    _describe -t commands 'taplo help lsp tcp commands' commands "$@"
}
(( $+functions[_taplo__lsp__help__tcp_commands] )) ||
_taplo__lsp__help__tcp_commands() {
    local commands; commands=()
    _describe -t commands 'taplo lsp help tcp commands' commands "$@"
}
(( $+functions[_taplo__lsp__tcp_commands] )) ||
_taplo__lsp__tcp_commands() {
    local commands; commands=()
    _describe -t commands 'taplo lsp tcp commands' commands "$@"
}
(( $+functions[_taplo__help__toml-test_commands] )) ||
_taplo__help__toml-test_commands() {
    local commands; commands=()
    _describe -t commands 'taplo help toml-test commands' commands "$@"
}
(( $+functions[_taplo__toml-test_commands] )) ||
_taplo__toml-test_commands() {
    local commands; commands=()
    _describe -t commands 'taplo toml-test commands' commands "$@"
}

if [ "$funcstack[1]" = "_taplo" ]; then
    _taplo "$@"
else
    compdef _taplo taplo
fi
