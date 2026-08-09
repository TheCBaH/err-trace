(lang dune 3.15)
(name err_trace)
(generate_opam_files false)
(authors "Vladimir N. Silyaev")
(maintainers "err_trace maintainers")
(license MIT)
(source
 (github TheCBaH/err_trace))

(package
 (name err_trace)
 (synopsis "Typed recoverable errors with bounded provenance")
 (description
  "Dependency-free typed errors with bounded semantic traces, synchronous monitors, and portable source locations for native OCaml, js_of_ocaml, and Melange.")
 (tags
  ("error-handling" "typed-errors" tracing diagnostics javascript)))

(using melange 0.1)
(using mdx 0.4)
